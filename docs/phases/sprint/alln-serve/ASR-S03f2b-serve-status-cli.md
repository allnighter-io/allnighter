# ASR-S03f2b — `alln serve status` emits v2, with §5.3 exit codes

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.1
(commands), §5.2 (v2 + five states), §5.3 (exit codes).

**13 of N** in the ASR-S03 cut. The shape, the resolver, and the gatherer are
built and proven (`41f39215`, `bd0e1800`, `50c36b30`, `fb42dade` — 62 tests).
This slice connects them to the front door.

**This is the first slice in the packet that changes a command's output.** Read
§9 before touching anything.

## 1. Goal

`alln serve --health --json` emits `CoordinatorHealth` v1, whose top-level state
is `available` — "a process exists". After this slice, `alln serve status --json`
and `alln serve --health --json` both emit `ServeStatusJSON` v2 and answer "is
useful scheduling alive?", with an exit code the caller can branch on.

## 2. Copy-paste prompt

> Add the `alln serve status [--json]` subcommand, make `alln serve --health`
> the compatibility spelling for it per §5.1, and have both emit
> `ServeStatusJSON` v2 via `ServeStatusGatherer` with the §5.3 exit codes. Keep
> the loopback `/health` endpoint body exactly as it is. Register the new
> command in `ContractRegistry`; leave help topics and teaching to ASR-S05.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift`
  — the entry point; it already gathers and resolves. Call it; add no logic.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift`
  — the five states and `recovery`.
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` around
  line 633–680 — the existing `serve [--health]` branch, its human output, and
  the teaching string at ~678 that ASR-S05 will replace. Do not fix that string
  here.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift
Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry.swift
Packages/AllnighterCore/Tests/AllnighterCLITests/ServeStatusCLITests.swift   (new)
Packages/AllnighterCore/Tests/AllnighterCoreTests/ContractRegistryTests.swift
```

## 5. Do not touch

`ServeStatusJSON`, `ServeStatusGatherer`, `ServeDaemon`, the loopback health
server or its body, any scheduler, `ServeLifecycle`, `HelpTopicRegistry`,
`TeachingSnippet`, `RetiredVocabulary`, any script, `Apps/`.

## 6. The one thing that must not break

`ServeDaemon`'s loopback `/health` body is `CoordinatorHealth`, and
`ServeHealthClient` parses it. That handshake is what `ServeStatusGatherer`
depends on to decide liveness. **Changing that body breaks the gatherer that
feeds the command you are wiring.** `CoordinatorHealth` stays exactly as it is;
this slice changes only what the *CLI prints*, never what the daemon *serves*.

## 7. Steps

1. **`alln serve status [--json]`**, and `alln serve --health [--json]` routed
   to the identical code path — same output, same exit code (§5.1). Do not
   deprecate or warn on `--health`; §5.1 keeps it as a supported spelling.

2. **JSON mode emits exactly one object on stdout** — `ServeStatusJSON` v2, no
   stray diagnostics (§5.3). Anything else goes to stderr or the serve log.

3. **Exit codes, §5.3, for the read-only status path only:**
   - `0` — `healthy`, or `disabled` when that is the desired state;
   - `69` `EX_UNAVAILABLE` — enabled but not actively healthy (`degraded`,
     `starting`), with the stable code from `recovery`;
   - `77` `EX_NOPERM` — `requiresApproval`;
   - `2` — CLI usage error only.
   `75`/`SERVE_BUSY` belongs to update/restart, not status. Do not add it here.

4. **Human output ends with one working recovery command** (§5.3), taken from
   `recovery`. Not a list, not a suggestion to read docs — one command that can
   be pasted. When healthy, no recovery line.

5. **Status stays read-only.** No install, repair, bootstrap, or write on any
   path, including the failure paths. If status cannot determine something it
   reports it; it never fixes it.

6. **Register the command in `ContractRegistry`** so the surface is discoverable
   and catalog validation passes. Bump `contractVersion` only if the registry's
   own rules require it for an added command — say either way in the commit
   message. Help topics, teaching snippets, and retired vocabulary are ASR-S05.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusCLITests|ContractRegistryTests|ServeStatusGathererTests|ServeStatusResolverTests'
```

## 9. Host-state invariant — read before starting

This is the first output change in the packet, so state it precisely in the
commit message: after this slice, `alln serve --health --json` emits v2 instead
of v1, and its exit code becomes meaningful.

The founder's live daemon keeps running the same bytes; nothing about
supervision, scheduling, or the plist changes. What changes is what one
read-only command *prints*. Anything on this machine parsing v1's
`state: "available"` will see `state: "healthy"` instead — that is the intended
cutover, and ASR-S05 owns sweeping the teaching that still describes v1.

## 10. Done when

- [ ] `alln serve status --json` and `alln serve --health --json` emit
      byte-identical v2 objects and the same exit code — asserted, both spellings.
- [ ] Exactly one JSON object on stdout, asserted by parsing the whole stream.
- [ ] Each of `healthy` / `disabled` / `degraded` / `requiresApproval` maps to
      its §5.3 exit code — four tests against a faked gatherer, no real host.
- [ ] Human output for every non-healthy state ends with one pasteable command;
      healthy prints none. Asserted.
- [ ] The status path performs no writes — asserted with a failing filesystem.
- [ ] `CoordinatorHealth` and the loopback `/health` body are unmodified, and
      `ServeHealthClient` still parses a live daemon's response.
- [ ] `ContractRegistry` lists `serve status`; catalog validation passes.
- [ ] No test writes outside a temp directory. One commit, explicit paths.
