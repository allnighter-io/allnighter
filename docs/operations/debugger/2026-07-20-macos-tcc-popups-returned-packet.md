# macOS TCC popups returned — investigation packet

Date: 2026-07-20
Status: investigation only; no runtime fix applied

## Boundary verdict

This is `T3 Critical`: a repeated permission regression.

The best-supported trigger is an **ordinary project run**, not cold launch and
not an explicit Setup/Re-check. This is not yet an OS-proven attribution because
the report does not include popup timestamps or the action immediately before
each popup, and the investigation sandbox cannot read the macOS TCC log.

The strongest local correlation is exact in count: on 2026-07-19 from
15:53:20Z through 15:54:47Z, the run journal records ten invocations of the same
Kimi prompt. Every invocation used
`/Users/mike/Documents/GitHub/websitemd.studio` as its process CWD and failed
with Kimi's HTTP 403 usage-limit response. The ten prompt files have the same
SHA-256 (`0105b08085e5c049dca084e388a16506621a7718766c70f70e92f3fc74bccf0d`).
The founder separately reports approximately ten TCC dialogs yesterday. That is
strong correlation, not proof that each run caused one dialog.

The original `2f57af74` defect was a **nil/inherited CWD** on a rootless worker
run. The current candidate is a different path: after the hotfix, the Unified
Run Model required every project-scoped run to use the real repo root, and
`765611d4` (2026-06-22) deliberately began passing `repoRoot` to workers. A repo
under `~/Documents` is therefore an explicit protected CWD. The old neutral-CWD
kill test remains green but does not cover the ordinary product path.

## Debug Packet

Tier:
`T3 Critical` — permission regression + repeated founder-visible failure.

Symptom / repro:

No complete reproduction is proven yet because the trigger observation is
missing. The smallest evidence-backed candidate scenario is:

1. Registered project root:
   `/Users/mike/Documents/GitHub/websitemd.studio`.
2. Start an ordinary mutating run using `model_kimi_k3` and the
   `execution_playbook` preset.
3. The worker spawn receipt records command `kimi`, six arguments, direct
   invocation, and the project root above as CWD.
4. Repeat the identical input ten times. The recorded starts are 8–12 seconds
   apart.

Expected behavior:
Ordinary run/chat must not surprise the user with Documents, Downloads, or
network-volume permission dialogs. A quota-exhausted Kimi run should fail
honestly without changing filesystem-permission posture.

Observed behavior:
The founder saw approximately ten macOS permission dialogs attributed to
Allnighter. Separately, the journal proves ten identical Kimi launches in the
protected project root, each exiting 1 with Kimi's 403 usage-limit response.
The journal contains no TCC event and cannot join the two observations by
timestamp.

Missing observation:

- exact popup timestamps;
- exact popup service/path wording for each dialog;
- whether the dialogs followed cold launch, Setup/Re-check, or Send/Run;
- whether the user allowed, denied, or dismissed each dialog;
- whether the ten Kimi runs were initiated manually or by an external retry
  loop (the runs have no Allnighter run links);
- TCC audit-token/process ancestry identifying the responsible executable;
- A/B result for Kimi versus another CLI under the same signed app, project,
  CWD, and reset TCC state.

Bug fingerprint:
`ordinary project run + repeated TCC protected-folder dialogs + explicit repoRoot under ~/Documents / missing TCC-to-spawn receipt`

Attempt count:
At least two prior TCC boundaries were fixed: H0–H6 for cold launch/setup probes
and `2f57af74` for rootless worker runs. This report is the third investigation,
but its best-supported fingerprint is the newer explicit-project-root path.

Seam:
macOS TCC attribution and protected-folder authorization across:

`user intent -> Project.repoRoot -> RunService/WorkerInvocation -> spawn adapter/direct Process -> CLI descendants -> TCC audit event`

Truth owner:

- Event truth: macOS TCC audit events own which process/path caused a prompt.
- Product root truth: the registered `Project` / canonical `repoRoot` owns the
  working directory for an ordinary run.
- Spawn truth: `WorkerInvocation` plus durable `spawnDiagnostics` owns the
  effective worker command and CWD.
- Route-specific spawn truth: Allnighter's `WorkerInvokerFactory` owns standard
  CLI adaptation; AgentOS `OpenCodeServeCoordinator` owns the separate warm
  `opencode serve` process; `ProcessACPTransport` owns warm ACP processes.

Lie-prone layer:

- `WorkerRunnerCWDTests.testChatRunSpawnsInNeutralScratchNotInheritedCWD` is
  green, but ordinary project chat now always supplies a repo root. It proves a
  fallback path, not the founder path.
- `AllnighterSpawnEnvironmentPolicy` sounds like a total spawn policy but owns
  only environment transformation. It does not own CWD and is bypassed by
  direct `Foundation.Process` paths.
- macOS labeling the dialog “Allnighter” does not identify which child CLI or
  descendant performed the protected access.
- A model manifest can expose a path by changing Auto selection without owning
  the shared spawn behavior.

Regression considered:

- **Cold launch:** current `AllnighterMacApp.init` has no login-shell call;
  `RootView.onAppear` calls only `loadCachedSetupState`; `scripts/dev.sh` builds
  under `~/Library/Developer/Allnighter/Build`. Source evidence does not support
  the old cold-launch fingerprint. Runtime TCC proof is still missing.
- **Explicit Setup/Re-check:** still intentionally runs `-lic` plus real CLI
  probes from neutral ProbeScratch. It remains a plausible source of
  Documents/Downloads/network-volume dialogs through shell profiles, but no
  observation says Re-check preceded this incident.
- **Ordinary run/chat:** best-supported. Ten matching Kimi run receipts used an
  explicit repo root under Documents.
- **`2f57af74` regression:** disproved for the old nil-CWD seam. The current
  factory still maps no root to ProbeScratch; focused tests pass.
- **Unified repo-root path:** confirmed as a new authority path. `19a52763` made
  repo-root execution the contract and `765611d4` passed it to workers.
- **`e617a97d` AgentOS cutover:** not the cause for standard CLI CWD propagation.
  It added `WorkerInvocationCWD` and a factory decorator preserving override ->
  default -> ProbeScratch. The focused CWD suite is green.
- **`bcadb313` environment policy:** not a CWD fix/regression. It restores the
  recursion-depth env guard and token scrub.
- **Kimi (`bb2ea097`):** not a launcher-code RCA. The commit adds catalog data
  and a manifest, and makes Kimi K3 the flagship Auto choice. It plausibly
  exposed/amplified the shared project-root boundary. Kimi-specific descendant
  access is unproven without an A/B harness.
- **Any new CLI:** subject to the same explicit project-root rule when routed
  through `WorkerInvokerFactory`. A new CLI can expose the shared boundary or
  touch additional protected locations internally; the manifest alone is not
  the authority owner.
- **OpenCode serve:** a real adjacent gap. AgentOS
  `OpenCodeServeCoordinator.defaultLaunchServe()` creates `Process()` for
  `opencode serve` without setting `currentDirectoryURL` and without the
  Allnighter environment policy. It inherits the parent CWD. This does not match
  the ten-run evidence (only two OpenCode receipts were present earlier that
  day), but it violates the no-ambient-spawn rule and needs its own kill test.
- **Warm ACP:** `ProcessACPTransport` explicitly sets `currentDirectoryURL` to
  the repo root. It does not inherit ambient CWD, but it shares the intentional
  protected-project-root authority question. Kimi does not use this path.

Isolation harness:
Required before a fix. This is a repeated native TCC seam and the existing unit
tests cannot observe the platform primitive.

Harness shape:

1. A minimal signed macOS app built/launched outside protected folders.
2. Three buttons only: spawn a tiny helper in Application Support scratch;
   spawn the same helper with CWD at the selected Documents project; spawn one
   CLI variant with that same CWD.
3. Record timestamp, parent PID, executable, effective CWD, and the one path the
   helper stats. Do not import Allnighter architecture.
4. Run a reset matrix for helper, Kimi, another standard CLI, OpenCode serve,
   and one warm ACP transport. Reset TCC between variants.
5. Join each popup to the TCC log timestamp/audit token.

Success criterion:
Cold launch and owned-scratch spawns show no prompt. A project-root run either
uses a durable user-authorized project-access mechanism or produces one explicit
authorization event owned by project selection, never repeated surprise prompts
per child/retry. The harness must decide what macOS actually permits before the
product boundary is chosen.

Missing kill test / proof:
No current wall command traverses signed app -> child/descendant -> protected
repo root -> TCC event. Current tests assert only the CWD value passed to a mock.
The required harness command does not exist yet; do not report the bug fixed
until it is created and fails against the current product-equivalent matrix.

Fix boundary:

- Do not patch Kimi's manifest first.
- Do not move ordinary repo-aware runs back to ProbeScratch; that violates the
  Unified Run Model and makes agents blind.
- Do not add Full Disk Access or a broad entitlement as a symptom patch.
- Establish one explicit spawn-authority contract for operation class,
  effective CWD, environment policy, and durable receipt. Every process path
  must either use it or prove an explicit owned/user-authorized CWD.
- Include standard AgentOS CLI workers, OpenCode serve and its `lsof` helper,
  warm ACP transports, setup probes, and detached runners in the audit.
- Separately decide and prove how a registered project under a TCC-protected
  root becomes durably user-authorized. That decision is the product boundary;
  implementation must follow the harness result.
- Treat the ten Kimi quota retries as a separate continuity/retry observation
  unless TCC timestamps prove they are the popup multiplier.

RCA:
Proven structural RCA: the prior neutral-CWD proof was scoped to no-root runs,
then product semantics changed to explicit repo-root execution. The test stayed
green while the founder path moved outside its claim. That is proof-boundary
drift/new authority path, not a demonstrated loss of `2f57af74` inside
`e617a97d`.

Incident RCA remains open at the last seam: only TCC event timestamps can prove
whether the ten Kimi launches caused the ten dialogs, whether Kimi descendants
touched additional protected locations, or whether an explicit Re-check or
OpenCode serve launch was responsible.

Proof command / founder test:

Current focused proof (passed 12/12 on 2026-07-20):

```bash
swift test --disable-sandbox --package-path Packages/AllnighterCore \
  --filter 'LaunchAuthorityProbeTests|WorkerRunnerCWDTests'
```

This is a guardrail, not the TCC kill test.

Founder evidence capture for the isolation run (requires explicit consent
because `tccutil reset` changes permission state):

```bash
/usr/bin/log stream --style compact --level debug \
  --predicate 'subsystem == "com.apple.TCC"'

tccutil reset All com.allnighter.mac
open "$HOME/Library/Developer/Allnighter/Build/Build/Products/Debug/Allnighter.app"
```

Run the harness matrix one variant per reset and record the action + timestamp.
Pass is no popup on cold launch/owned scratch and no repeated surprise popup for
an already authorized project run.

## What was the agent allowed to do that must never be allowed again?

Allow a product-semantic change from rootless/scratch chat to mandatory
repo-root execution while leaving the old no-root CWD unit test presented as the
TCC regression proof, without an end-to-end signed-app TCC harness covering the
new ordinary run path and every direct-process bypass.
