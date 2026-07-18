# CR-32 — Review LoopbackHealthServer trust

## Summary

`LoopbackHealthServer` binds correctly to `127.0.0.1` on an ephemeral kernel-assigned
port (port 0 → `getsockname`), so there is no network-exposure or port-collision defect.
The binding, `SO_REUSEADDR`, and byte-order handling for `boundPort` are all correct.
However, the **shutdown path** has three real defects that compound each other: a
double-close of the listen FD (cancel handler + explicit `close`), a blocking
`accept` loop that can permanently hog a dispatch thread, and an unsynchronized read
of `listenFD` inside the accept loop that races with `stop()`. None of these leak the
endpoint off-loopback, but together they make `stop()` unreliable and can corrupt the
process FD table.

## Findings

### P0 — None

No invariant or security violation found. The server binds to `127.0.0.1` only
(`LoopbackHealthServer.swift:37`), uses an ephemeral port (`LoopbackHealthServer.swift:36`,
`sin_port = 0`), and the response body is caller-provided — the server itself does not
leak sensitive data. The `Content-Length` header correctly uses `body.utf8.count`
(`LoopbackHealthServer.swift:110`), preventing response-splitting via length mismatch.

---

### P1 — Double-close of listen FD in `stop()`

- **Invariant:** A file descriptor must be closed exactly once. A second `close` after
  the FD number has been recycled by the kernel closes an unrelated resource.
- **Evidence:** `stop()` calls `acceptSource?.cancel()` at `LoopbackHealthServer.swift:72`,
  which schedules the async cancel handler registered at `LoopbackHealthServer.swift:62`
  (`source.setCancelHandler { [fd] in close(fd) }`). `stop()` then **synchronously**
  closes the same FD at `LoopbackHealthServer.swift:74` (`if listenFD >= 0 { close(listenFD) }`).
  When the cancel handler fires later on the dispatch queue it calls `close(fd)` a second
  time. Between the two closes the FD number can be reused by any other `socket`/`open`
  call in the process, causing the cancel handler to close an unrelated descriptor.
- **Suggested fix:** Remove the explicit `close(listenFD)` from `stop()` and let the
  cancel handler own the close (it already captures `fd` by value). Alternatively, set
  `listenFD = -1` before cancelling and do not close in `stop()` at all. Pick one owner
  for the close — not both.
- **Suggested slice:** `loopback-health: single-owner FD close in stop()`

### P1 — Blocking `accept` loop hogs the dispatch thread

- **Invariant:** A `DispatchSource` event handler must return promptly so the source can
  re-arm and the cancel handler can run.
- **Evidence:** The socket is created blocking at `LoopbackHealthServer.swift:26`
  (`socket(AF_INET, SOCK_STREAM, 0)`) with no `fcntl(fd, F_SETFL, O_NONBLOCK)` anywhere
  in `start`. `acceptConnections()` (`LoopbackHealthServer.swift:80-86`) loops
  `while true { accept(listenFD, ...) }`. After the last pending connection is consumed,
  the next `accept` **blocks** the dispatch thread until a new connection arrives. The
  handler never returns, so the dispatch source cannot re-arm and the cancel handler
  cannot run. This also means `stop()`'s `acceptSource?.cancel()`
  (`LoopbackHealthServer.swift:72`) is deferred indefinitely — the cancel handler that
  closes the FD never fires while the handler is blocked.
- **Suggested fix:** Set the socket non-blocking (`fcntl(fd, F_SETFL, flags | O_NONBLOCK)`)
  before `listen`. In `acceptConnections`, break the loop when `accept` returns `EAGAIN`/
  `EWOULDBLOCK` (not just on `< 0`). Treat `EINTR` as continue.
- **Suggested slice:** `loopback-health: non-blocking accept loop`

### P1 — Unsynchronized `listenFD` read in `acceptConnections` races with `stop()`

- **Invariant:** `@unchecked Sendable` requires all mutable state to be protected by the
  lock. `listenFD` is mutated under the lock in `start`/`stop` but read without the lock
  in the accept loop.
- **Evidence:** `acceptConnections` reads `listenFD` directly at `LoopbackHealthServer.swift:82`
  (`accept(listenFD, nil, nil)`) with no lock held. `stop()` sets `listenFD = -1` at
  `LoopbackHealthServer.swift:75` and closes the FD at `:74`, both under the lock. If
  `stop()` runs while the accept loop is between the `listenFD` read and the `accept`
  syscall, `accept` operates on a stale or closed FD. If the FD was closed and recycled,
  `accept` could accept a connection on an unrelated socket. This is the same class of
  bug as the double-close: FD lifetime is not owned by a single synchronization domain.
- **Suggested fix:** Snapshot `listenFD` under the lock at the top of each iteration, or
  (better) make the cancel handler the sole owner of FD lifetime and have `acceptConnections`
  check a `stopped` flag. Combined with the non-blocking fix above, the loop should break
  on `EAGAIN` and re-check the snapshot.
- **Suggested slice:** `loopback-health: synchronize listenFD in accept loop`

---

### P2 — Single `write()` call; partial writes and errors ignored

- **Invariant:** `write` may return fewer bytes than requested; the return value must be
  checked and the remainder retried.
- **Evidence:** `LoopbackHealthServer.swift:114` —
  `_ = response.withCString { write(client, $0, strlen($0)) }`. The return value is
  discarded and there is no loop. For small health responses on loopback this almost
  always succeeds, but it is not guaranteed. A short write produces a malformed HTTP
  response (truncated body without re-sending headers).
- **Suggested fix:** Loop on `write` until all bytes are sent, or use `URLSession`-style
  buffered writing. At minimum, check the return value for `-1` and break.

### P2 — Loose path prefix match

- **Invariant:** The health route should match `GET /health` and `GET /health?…`, not
  arbitrary paths that start with that string.
- **Evidence:** `LoopbackHealthServer.swift:99` —
  `if firstLine.hasPrefix("GET /health")`. This matches `GET /healthfoo`, `GET /health/secret`,
  etc. Not a security issue (the body is caller-provided and loopback-only), but it is
  surprising behavior.
- **Suggested fix:** Match `GET /health ` (with trailing space or end-of-line), or parse
  the path component and compare exactly.

### P2 — `getsockname` failure misreported as `bindFailed`

- **Invariant:** Error cases should report the failing operation.
- **Evidence:** `LoopbackHealthServer.swift:54` —
  `guard nameResult == 0 else { throw LoopbackError.bindFailed(errno) }`. The failing
  call is `getsockname` (`LoopbackHealthServer.swift:51`), not `bind`. The error type
  `bindFailed` is misleading for callers diagnosing failures.
- **Suggested fix:** Add a `nameFailed(Int32)` case or reuse `listenFailed` with a
  distinct message.

### P2 — `strlen` for write length is fragile if body contains a NUL byte

- **Invariant:** The write length should be derived from the UTF-8 byte count, not from a
  C-string terminator.
- **Evidence:** `LoopbackHealthServer.swift:114` —
  `write(client, $0, strlen($0))`. `withCString` provides a NUL-terminated buffer; if the
  health body (caller-provided JSON) ever contains an embedded NUL, `strlen` undercounts
  and the response is truncated. `Content-Length` (`LoopbackHealthServer.swift:110`)
  already uses `body.utf8.count`, so the header and body can disagree.
- **Suggested fix:** Use `response.utf8.withContiguousStorageIfAvailable` or
  `response.utf8.count` for the length and a byte-buffer write, not `withCString`/`strlen`.

## False alarms ruled out

- **Binding to 0.0.0.0 / external exposure:** Not present. `inet_addr("127.0.0.1")` at
  `LoopbackHealthServer.swift:37` binds loopback only. Verified.
- **Port collision / fixed port:** Not present. `sin_port = 0` (`LoopbackHealthServer.swift:36`)
  lets the kernel assign an ephemeral port; `getsockname` retrieves it. No collision possible.
- **Port byte-order bug:** Not present. `UInt16(bigEndian: bound.sin_port)` at
  `LoopbackHealthServer.swift:58` correctly converts from network to host order.
- **`SO_REUSEADDR` missing:** Present at `LoopbackHealthServer.swift:31`. Correct for
  rapid restart.
- **`start` failure leaks FD:** Not present. The `defer { if listenFD < 0 { close(fd) } }`
  at `LoopbackHealthServer.swift:28` closes the FD on any throw before `listenFD` is
  assigned. After assignment (`LoopbackHealthServer.swift:57`) no throwing calls remain.
- **`Content-Length` mismatch:** Not present. Uses `body.utf8.count` at
  `LoopbackHealthServer.swift:110`, matching the body encoding.
- **Per-iteration `defer { close(client) }` leak:** Not present. The defer is scoped to
  the loop body and runs at the end of each iteration, closing each accepted client.
- **HTTP response line endings:** Correct. The `\r` escape followed by the literal
  newline in the multi-line string produces `\r\n` as required by HTTP/1.1.

## Greps avoided

Confirmed: no `grep`, `glob`, `read`, or `task` tool calls were issued. All evidence is
from the inlined source block in the review request. No files outside
`docs/phases/code_review/findings/CR-32.md` were read or modified.