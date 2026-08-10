# CT-S04 — Lock-gated sibling `external_directory`

Status: **done** (Grok 4.5 run `C1404143`, commits AgentOS `d82b070` + Allnighter `99aa2c70`)
SSOT: [`OpenCode_Completion_Truth_Followup.md`](../../../OpenCode_Completion_Truth_Followup.md) CT-08
Model: **Grok 4.5** (`model_cursor_grok_45`)

## Goal

Enforce CT-08 ruling: auto-approve sibling `external_directory` only when the
caller holds that root's write lock (run root always allowed for its own tree).

## Copy-paste prompt

Implement CT-08 lock-gated sibling `external_directory` approval.

**Ruling:** `OpenCodePermissionPolicy.patternsAllowed` must accept a
`heldWriteLockRoots: Set<String>` (normalized paths). A pattern under a
sibling allow-list root is allowed only if that root is in `heldWriteLockRoots`
OR equals the run's `workingDirectory`. Run root patterns always allowed.

**Touch:**
- `AgentOS/Sources/AgentOSCLI/OpenCodePermissionPolicy.swift`
- `AgentOS/Sources/AgentOSCLI/OpenCodeServeClient.swift` (pass run root + held locks into permission handler)
- `AgentOS/Tests/AgentOSCLITests/OpenCodePermissionPolicyTests.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/` — wire held lock roots from `RunWriteLockRegistry` into OpenCode `WorkerInvocation` (add field if needed)
- `Packages/AllnighterCore/Tests/` — one test: mutating run in Allnighter does not auto-approve AgentOS sibling without lock

**Do not:** change static allow-list roots; do not weaken `..` fail-closed.

**Proof:**
```bash
cd AgentOS && swift test --filter OpenCodePermissionPolicyTests
cd Allnighter && scripts/swift-test.sh --filter OpenCodePermissionPolicy
```

Also amend `HelpTopicRegistry.swift` topic `opencode_headless_completion`: add
bullet on lock-gated siblings + dogfood prereq (port 4096 free, let alln spawn).

Commit with explicit paths. No scope creep into CT-10.

## Read only

- `docs/phases/OpenCode_Completion_Truth_Followup.md` § CT-08
- `AgentOS/Sources/AgentOSCLI/OpenCodePermissionPolicy.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/RunWriteLock.swift` (or registry SSOT)

## Exit

- [ ] Sibling path denied without write lock on that root
- [ ] Run root + held-lock sibling paths allowed
- [ ] Unit tests green
- [ ] Help topic updated
