Verdict: REFACTOR REQUIRED. Do not archive or treat RSC as release-ready yet.

  The direction is sound—cross-process flock, same-binary relaunch, and one
  RunService owner—but the implementation acknowledges work before it has been
  durably accepted. It also exposes unsafe run IDs and introduces hidden
  continuation state machines. Your concern is justified.

  ## Highest-priority findings

  - [P1] --run-id is unsafe and not atomically claimed. Any string is accepted,
    then interpolated directly into a filesystem path in Packages/
    AllnighterCore/Sources/AllnighterEngine/RunStore.swift:26. IDs containing
    slashes and .. can resolve outside the runs root. The collision check in
    Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift:98 is also a
    read-then-act TOCTOU: two processes can both observe “unused,” and
    observational Teams can dispatch concurrently under the same ID. A corrupt
    existing journal is treated as absent because loadRaw collapses corruption
    to nil.
    Required: preferably remove public --run-id; otherwise enforce a canonical
    safe grammar and add one atomic RunStore claim that treats existing or
    corrupt IDs as occupied.

  - [P1] A dispatched acknowledgement does not mean the child accepted the work.
    Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift:330 acknowledges
    immediately after Process.run(). Actual team readiness, retry validation,
    idempotency, and durable journal creation happen later in the discarded-
    output child. With --idempotency-key, the child can replay an older run with
    a different ID while the parent prints a newly minted ID that will never
    exist; conflict and --retry-of refusals are also hidden after the ack. Relay
    start has the same preflight-to-child race.
    Required: a bounded child-ready handshake. Print success only after the
    child has durably claimed the work, and return the actual run/relay ID.

  - [P1] The relay safety mechanism created a second, externally reachable state
    machine. Packages/AllnighterCore/Sources/AllnighterCLI/PairCLI.swift:27
    routes the “hidden” relay-start-continue and relay-continue verbs. They are
    unregistered, but they are callable; unregistered merely skips normal flag
    validation. relay-start-continue accepts an arbitrary relay ID, performs no
    same-ID collision check, and can overwrite an existing relay when root/doc
    differs. The immediate 5a2d22a1 fix had to add a durable dispatch token
    after S03 initially made relay-continue capable of bypassing the guard and
    double-dispatching.
    Required: delete both hidden verbs, dispatchToken, and the guard/
    continuation split. Use one typed, staged child request and have the child
    invoke the normal coordinator entry point after claiming ownership.

  - [P1] The lock guarantee depends on a save that explicitly ignores failure.
    Resume/adopt/start take the correct lock, but the critical .running write
    funnels through try? stateStore.save in Packages/AllnighterCore/Sources/
    AllnighterEngine/RelayCoordinator.swift:1924. Disk-full, permission, or
    encoding failure therefore releases the lock and runs in memory while disk
    still says the relay is resumable. A second process may then dispatch too.
    Lock creation/I/O failure is also reported as contention or even
    alreadyActive("unknown"), which invents the wrong cause.
    Required: make the locked claim a throwing, hard-gated RelayStateStore
    operation with distinct busy, journalUnavailable, and alreadyActive results.

  - [P1] The packet’s decisive proofs have not landed. The packet explicitly
    requires real killed-caller and two-process race tests at docs/phases/
    Round_Survives_The_Caller.md:340. RunNoWaitTests explicitly says the real
    subprocess round trip exists only in the manual Works Test; the “concurrent
    resume/adopt” tests mostly hold the flock manually rather than race two real
    CLI processes. There is no durable proof receipt that Works Test steps 1 and
    3 ran.
    Required: checked-in, fake-worker subprocess tests: kill caller PID/process
    group, poll the ID, and race two actual CLI invocations.

  - [P2] Several user-visible edge cases remain wrong.
      - Resume/adopt reconstruct child arguments and drop --no-auto-serve, so
        the child starts alln serve despite the explicit opt-out (Packages/
        AllnighterCore/Sources/AllnighterCLI/RelayCLI.swift:199).

      - Mac start performs a lock-free preflight, seeds a thread, then
        asynchronously calls the real guarded start and ignores its result
        (Apps/AllnighterMac/Sources/RelayLaunchViewModel.swift:128). A racing
        CLI can still win after preflight, leaving the GUI with a returned ID
        and orphan seed.

      - Duplicate identity uses exact docPath, so docs/spec.md and ./docs/
        spec.md are different keys. Parked/escalated relays are intentionally
        allowed, so “asking twice never runs twice” is broader than the
        implementation.

      - run --no-wait --json advertises .teamRunJSON in Packages/AllnighterCore/
        Sources/AllnighterCore/ContractRegistry+Milestone1.swift:438 but emits
        an unregistered DetachedDispatchJSON.

  ## Blast-radius assessment

  For S01–S04 plus the immediate S03 safety fix:

  - 33 files
  - +2,387 / −184 lines
  - Production: +969 / −86
  - Tests: +1,308 / −75
  - Generated/fixtures: +110 / −23

  Most file count is defensible testing and generated contracts. The concerning
  blast radius is the roughly 575 added lines in RelayCLI and RelayCoordinator,
  plus a new durable token field and hidden verbs. That complexity exists
  because the foreground process mutates/validates, then tries to hand execution
  to another process without an acceptance protocol.

  The repository previously had a proper detached-runner pattern—setsid,
  recorded detached ownership, staged request, and runner_ready handshake—
  deleted in 588e0621 when phantom --detach was removed. I would not restore its
  entire old control plane, but RSC should reuse those proven mechanics instead
  of rebuilding a weaker acknowledgement path.

  ## Recommended follow-up round

  1. One detached-acceptance primitive
      - Use ProcessOwnership.spawnProcessGroupLeader/detached ownership.
      - Typed immutable request, explicit environment policy, child-ready
        handshake.

      - Ack only after durable ownership and validation.
      - Preserve the actual ID returned by idempotency replay.

  2. Collapse relay
      - Put atomic start/resume/adopt claims in RelayStateStore.
      - Canonicalize project root plus repo-relative doc identity.
      - Hard-fail persistence.
      - Delete hidden continuation verbs, dispatch tokens, and split guard APIs.
      - GUI seeds/navigates only after an accepted claim.

  3. Harden run identity
      - Remove public --run-id unless a genuine external use remains.
      - Otherwise validate and atomically claim it in RunService/RunStore.
      - Treat corrupt journals as occupied.
      - Register the detached acknowledgement schema honestly.

  4. Hostile proof gate
      - Real subprocess tests for all four verbs.
      - Caller PID and process-group death.
      - Two-process start/resume races.
      - ID traversal/corruption/concurrent-ID tests.
      - Idempotency replay/conflict and retry-of refusal.
      - GUI preflight race and --no-auto-serve preservation.

  ## Verification performed

  - 63 focused tests passed from the existing compiled XCTest bundle.
  - Architecture policy passed.
  - Generated contract check passed.
  - A local process probe confirmed the Foundation child gets a separate process
    group and survives normal parent exit. That is encouraging, but it is not
    the required hostile killed-session proof.

  - Direct swift test was blocked by this host’s nested SwiftPM sandbox; a
    broader relay run later hung in its SIGKILL-based stale-lock test under the
    same host restrictions and was stopped.

  No files or git state were changed by me. While the audit was running, another
  process landed c60a4315 (S05 teaching) and cfdfd8b2 (render the GUI refusal).
  Those do not resolve the P1 findings above. The phase doc is also stale: it
  still says “Ready for Implementation” and targets contract 4.2.0 / binary
  0.10.2, while current HEAD is 4.4.1 / 0.10.5.