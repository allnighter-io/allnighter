# CR-31 — DirectModeCommandServer boundary

## Summary
Loopback TCP command server (`DirectModeCommandServer`): binds `127.0.0.1` on an
ephemeral port, drives an accept loop via a `DispatchSourceRead`, and fans each
connection out to a `Task.detached`. The inlined window (lines 520–650) covers
`init`, `port`, `start`, `stop`, `acceptConnections`, and the head of `respond`;
`readRequest` and the handler dispatch are below line 650 and were not read.

One P0: `stop()` and the dispatch source's cancel handler both close the listen
fd → double close. Two P1s: `acceptConnections` reads `listenFD` off-lock (data
race that undermines the `@unchecked Sendable` claim), and there is no cap on
concurrent in-flight connections (local DoS). Auth, request-size enforcement,
and path traversal cannot be confirmed from the inlined window (`respond` /
`readRequest` / handlers are not shown) and are flagged as needs-verification,
not as confirmed clean.

## Findings

### P0 — Double close of `listenFD` on `stop()` (fd-recycle risk)
- **Invariant:** A file descriptor is closed exactly once; ownership of `close`
  is singular and unambiguous.
- **Evidence:** `start()` registers
  `source.setCancelHandler { [fd] in close(fd) }` (DirectModeCommandServer.swift:618),
  where `fd` is the same value later assigned to `listenFD` at
  DirectModeCommandServer.swift:613. `stop()` then calls
  `acceptSource?.cancel()` (DirectModeCommandServer.swift:628) followed by
  `if listenFD >= 0 { close(listenFD) }` (DirectModeCommandServer.swift:630).
  `cancel()` schedules the cancel handler asynchronously on
  `.global(qos: .userInitiated)`; `stop()` closes `listenFD` synchronously
  first. The cancel handler then runs `close(fd)` on the same fd number again.
  Between the synchronous close and the async cancel-handler close, another
  thread can allocate a new socket/file and recycle the fd number; the second
  `close` then releases that unrelated resource.
- **Suggested fix:** Make the cancel handler the sole owner of `close(fd)`. In
  `stop()`, drop `if listenFD >= 0 { close(listenFD) }` (DirectModeCommandServer.swift:630)
  and keep only `acceptSource?.cancel(); acceptSource = nil; listenFD = -1;
  boundPort = 0`. The cancel handler already closes the real fd; `listenFD = -1`
  just marks the server stopped. (Do not also set `listenFD = -1` before
  `cancel()` if `acceptConnections` is changed to snapshot the fd — see P1
  below; order `cancel()` first, then flip the flag.)
- **Suggested slice:** `directmode-server: single-close ownership`

### P1 — `acceptConnections` reads `listenFD` without the lock (data race; undermines `@unchecked Sendable`)
- **Invariant:** Mutable state guarded by `lock` is accessed only under `lock`;
  `@unchecked Sendable` must be justified by complete synchronization, not
  "mostly."
- **Evidence:** `acceptConnections()` calls `accept(listenFD, nil, nil)`
  (DirectModeCommandServer.swift:637) with no `lock.lock()`, while `stop()`
  writes `listenFD = -1` (DirectModeCommandServer.swift:631) and `port` reads it
  under `lock`. The dispatch-source event handler is serialized on its target
  queue, but an already-running `acceptConnections` can execute concurrently
  with `stop()` (cancel suppresses future events, not an in-flight handler). In
  the Swift memory model this is a data race on `listenFD`; combined with the
  P0 double-close it also means `accept` can be called on a fd that `stop()` is
  about to close.
- **Suggested fix:** Snapshot the fd under the lock at the top of
  `acceptConnections()`: `lock.lock(); let fd = listenFD; lock.unlock(); guard
  fd >= 0 else { return }`, then `accept(fd, nil, nil)`. Treat `fd < 0` as
  "stopped, return." This makes the read synchronized and decouples the accept
  loop from `stop()`'s mutation.
- **Suggested slice:** `directmode-server: lock accept fd read`

### P1 — No concurrency cap on accepted connections (local DoS)
- **Invariant:** A loopback command server bounds concurrent in-flight
  requests; it does not spawn unbounded work per accepted fd.
- **Evidence:** `acceptConnections()` spawns `Task.detached(priority:
  .userInitiated) { … await self?.respond(on: client) }` per accepted client
  (DirectModeCommandServer.swift:639) with no semaphore, counter, or queue
  limit. A local process can open many connections and exhaust the cooperative
  thread pool / memory, degrading the app. Loopback scoping reduces but does
  not remove this — any local process can connect.
- **Suggested fix:** Cap concurrent `respond` tasks with an `AsyncSemaphore` or
  an atomic counter; when the cap is hit, `accept`-and-immediately-close with a
  `503` rather than spawning another task.
- **Suggested slice:** `directmode-server: accept backpressure`

### P1 — Auth boundary not enforceable at the server layer (cannot verify from inlined window)
- **Invariant:** Binding to `127.0.0.1` is transport scoping, not
  authentication; any local process can connect to `/remote/command`.
- **Evidence:** `start()` binds `addr.sin_addr.s_addr = inet_addr("127.0.0.1")`
  (DirectModeCommandServer.swift:594). No token, bearer, or pairing check is
  visible anywhere in the inlined window. `respond(on:)` — where credential
  checks would live — is cut off at DirectModeCommandServer.swift:646–650, and
  `readRequest` is not inlined at all.
- **Suggested fix:** Confirm `respond`/`readRequest` enforce a per-request
  credential (e.g., a pairing-derived bearer token) before dispatching to any
  handler, and that the comparison is constant-time. If auth currently lives in
  individual handlers, hoist it to the server so a newly added handler cannot
  accidentally bypass it. This is a verification request, not a confirmed code
  change.
- **Suggested slice:** (verification; code change only if auth is missing or per-handler)

### P2 — `maxRequestBytes` enforcement cannot be verified
- **Invariant:** Request bodies are capped at `maxRequestBytes`; oversize
  bodies are rejected before parsing.
- **Evidence:** `maxRequestBytes` is stored (DirectModeCommandServer.swift:544,
  default `512 * 1024` at DirectModeCommandServer.swift:559, clamped to
  `max(1024, …)` at DirectModeCommandServer.swift:570), but the actual read
  loop lives in `readRequest(on:)`, which is below line 650 and not inlined.
- **Suggested fix:** Confirm `readRequest` reads at most `maxRequestBytes + 1`
  and rejects on overflow before any parse, and that the cap is applied to the
  raw byte stream (not a decoded length field).

## False alarms ruled out
- **Port byte order:** `boundPort = UInt16(bigEndian: bound.sin_port)`
  (DirectModeCommandServer.swift:614) correctly converts network-order
  `sin_port` to host order. Not a bug.
- **`inet_addr` byte order:** `inet_addr("127.0.0.1")` already returns the
  address in network byte order; assigning directly to `sin_addr.s_addr`
  (DirectModeCommandServer.swift:594) is correct — no `htonl` needed.
- **`defer { if listenFD < 0 { close(fd) } }` in `start()`:** Correctly closes
  the socket only if `start` throws before transferring fd ownership to
  `listenFD`/the cancel handler (DirectModeCommandServer.swift:585). Once
  `listenFD = fd` (DirectModeCommandServer.swift:613) the defer is a no-op and
  the cancel handler owns the close. Not a leak — the leak is the *second*
  close in `stop()` (see P0).
- **Error leakage to network clients (inlined window):** The only inlined
  network response is `["error": "bad_request"]` with `400 Bad Request`
  (DirectModeCommandServer.swift:648) — minimal, no errno, stack, or path info.
  `ServerError.socketFailed/bindFailed/listenFailed(errno)` are thrown to the
  caller, not written to the socket. No leakage in the inlined window. (Handler
  error responses are below line 650 and were not verified.)
- **Path traversal (`mediaPath` / `mediaKeyPath`):** Depends entirely on the
  injected `mediaHandler` / `mediaKeyHandler` implementations, which are not
  inlined. Cannot be evaluated from this window; explicitly **not** asserted
  clean. Flag for a follow-up review that includes the media handlers.
- **`SO_REUSEADDR` on loopback:** Harmless and standard; not a finding.

## Greps avoided
Confirmed: no repo exploration. Only the inlined lines 520–650 of
`DirectModeCommandServer.swift` and the resolved-symbol list (`start`→578,
`stop`→625, `acceptConnections`→635, `respond`→646) were used. `respond`,
`readRequest`, the `writeJSON` helper, and all `DirectMode*Handling` protocols
are below/outside the inlined window and were not read. Line numbers for
non-anchored lines were derived by counting from the `start`/`stop`/
`acceptConnections` anchors within the inlined block.