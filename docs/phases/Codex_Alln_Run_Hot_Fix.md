# Codex `alln run` Hot Fix

Status: **BLOCKED — CAR-S00 RED (LaunchServices refused launch from default Codex); awaiting founder architecture decision per §2**
Owner: CLI handoff transport + Mac app handoff host + release/install contract
Created: 2026-08-01
Updated: 2026-08-02

Founder intent: `alln run` must work when invoked by an agent inside Codex just
as it works inside Claude, Cursor, and Grok. The caller uses one command and gets
one answer. App lifecycle, sandbox boundaries, credentials, queues, and recovery
commands are product plumbing, not work the calling agent should coordinate.

Product value: Allnighter exists so agents can delegate to other subscription
CLIs. A supported host that can discover Allnighter but cannot complete a run
breaks the core product claim.

This is a hard cutover. There are zero users to migrate: no aliases, shims,
parallel handoff modes, compatibility queue, or legacy behavior.

---

## Trusted workflow slice

```text
Codex agent
  -> alln run <request>
  -> Allnighter crosses the Codex-only credential boundary automatically
  -> the existing RunService.run executes against the canonical repository
  -> one terminal TeamRun returns in the same terminal
```

The caller does not open another app, paste a recovery command, run a doctor,
choose a transport, poll, or understand why Codex differs from another CLI.

`RunService.run` remains the sole run-semantics owner. This packet changes only
how a Codex-originated request reaches that owner when nested vendor CLIs cannot
use their credentials inside Codex's sandbox.

## Incident classification

Tier: **T3 Critical** — core product path, sandbox/Keychain boundary, repeated
handoff work, and latent quota-spend risk.

Symptom:

- The same Spec Review works when `alln` is called from Claude, Cursor, or Grok.
- From Codex, every nested vendor CLI fails quickly with authentication,
  filesystem, or process-start denial.
- Alln queues the request for the Mac app, waits 30 seconds, then returns the
  failed local run because no app host claims it.
- The unclaimed request remains in the mailbox and can execute later when the
  app opens, after the caller was told the attempt failed.

Bug fingerprint:

```text
CODEX_SANDBOX=seatbelt
  -> nested vendor credential/process denial
  -> HostSandboxAdvice detects the real failure
  -> SandboxHandoff.enqueue
  -> no guaranteed out-of-sandbox host
  -> claim timeout
  -> request remains runnable
```

Attempt count: **3+**. The earlier Code Red and Sandbox Handoff packets repaired
state-root divergence, failure projection, payload fidelity, claim ownership,
and terminal delivery. The cold-host requirement remained explicitly open and
was treated as an operational precondition instead of part of `alln run`.

Isolation-harness mandate: **required before product edits**. This crosses
Codex Seatbelt, LaunchServices, app signing, and macOS process authority. A mock
mailbox test cannot prove it.

## Evidence from the 2026-08-01 repro

Two real `code_spec_review` attempts originated inside Codex:

| Local run | Handoff run | Result |
| --- | --- | --- |
| `1ED48D02-8A64-441D-9CF5-ED20F769BFAF` | `handoff-D6FF7F05-E07B-4838-92F3-49B7F409529A` | No host claimed it |
| `9B303384-1A77-4EDD-A894-FEB34462AA6E` | `handoff-256BDB10-8A49-4AE1-88CF-8E627CD83778` | No host claimed it |

Observed worker failures included Codex PATH/app-server `Operation not
permitted`, Grok `FS_PERMISSION_DENIED`, and Claude reporting not logged in.
These are the known Codex sandbox signatures; they are not evidence that the
vendor installations are broken.

`alln doctor handoff --json` returned:

```json
{
  "verdict": "hostNotRunning",
  "detail": "Nothing claimed this check. Open Allnighter — while it is closed, nothing outside your terminal can start your AI tools."
}
```

The handoff log had no host start for roughly ten hours. No canonical app was
installed at `/Applications/Allnighter.app` or `~/Applications/Allnighter.app`;
only a developer build existed. `open -a Allnighter` could not resolve it, and
LaunchServices refused the developer bundle even though its executable and code
signature were present.

Both timed-out handoff files remained unclaimed under Application Support. The
runner claims every unclaimed request without an age limit, so opening the app
later would have started both six-seat reviews. The founder explicitly
authorized deletion; both files were removed on 2026-08-01 and the inbox was
verified empty.

## Root cause

The sandbox boundary is real and expected. The defect is that Allnighter exposes
an automatic fallback without owning the availability of its receiver.

Other hosts use the direct path and therefore never exercise this missing
lifecycle. Codex is the only supported host whose happy path currently depends
on a separately installed, separately launched Mac app.

Three contracts contradict one another:

1. `SandboxHandoff` says the user does not copy, paste, or restart anything.
2. Bootstrap/help says the CLI is the whole agent surface with no human in the
   loop, and the cold-start packet says CLI-only users never open the Mac app.
3. The implementation requires the Mac app already to be open; the CLI neither
   installs it, launches it, nor proves it is ready before queuing real work.

The timeout compounds the defect: returning failure does not withdraw or expire
the queued request. A failed command can therefore become delayed quota spend.

Truth owners:

- Run semantics: `RunService.run` — unchanged.
- Caller-side transport lifecycle: `SandboxHandoff`.
- Receiver lifecycle: `SandboxHandoffHost` at application-process startup.
- Canonical app availability and version identity: the shared release/install
  channel.
- Request claim, expiry, and cleanup: `SandboxHandoffSpool`.

Lie-prone layers:

- `alln run` text/JSON saying a request was handed to the app when only a file
  was written.
- A SwiftUI `Window.task` used as the availability boundary for a process-level
  service.
- A claim timeout presented as terminal while its request remains executable.
- Component tests with an already-running synthetic host presented as proof of
  a cold Codex invocation.

Missing proof: no test begins inside a real Codex sandbox with the app closed and
ends with the real answer returned to that same terminal.

## Binding design

### 1. One command owns the recovery

`alln run` remains the only user action. `alln doctor handoff` remains a
diagnostic surface, not a prerequisite or recovery workflow.

Alln may attempt the direct path first because a user-selected
full-access Codex session works normally. Only an observed typed sandbox failure
activates the alternate authority path.

### 2. Prove the launch primitive before choosing architecture

Build a product-free temporary harness:

1. Install a minimal correctly signed app in the same canonical location and
   signing posture planned for Allnighter.
2. From a real default Codex session, ask LaunchServices to start it by bundle
   identifier.
3. Have the app write a nonce-bearing readiness receipt and perform a
   non-secret Keychain availability probe.
4. Prove the spawned app has independent macOS authority rather than inheriting
   Codex Seatbelt restrictions.

If GREEN, LaunchServices is the transport bootstrap and no persistent daemon or
login item is needed.

If RED, stop for a founder architecture decision. Code inside Codex cannot grant
itself authority the sandbox denies. The honest remaining choices are a
pre-running app/login item or explicit per-session full access. Do not hide
either choice behind another queue or a credential workaround.

### 3. Make the canonical app part of installation

The supported macOS installation must provide a signed, LaunchServices-visible
`Allnighter.app` and the matching `alln` CLI. A CLI that advertises Codex runs
while its required execution host is absent is an incomplete install.

The readiness handshake must include compatible product/contract identity. A
stale app must fail closed before accepting work, with one update action. Do not
add old/new compatibility decoding or parallel protocols.

### 4. Start the host with the application, not a window

Move handoff-host startup to application lifecycle ownership so it begins even
when no main window task appears. It must start before network bootstrap and
remain independent of window visibility.

The host remains a thin adapter: claim one request, call the existing
`RunService.run`, persist the ordinary journal. It gains no run semantics.

### 5. Establish readiness before queuing real work

After the direct path observes a sandbox failure:

1. Resolve the one canonical app by bundle identifier.
2. Ask LaunchServices to start it without requiring user interaction.
3. Use the existing quota-free ping to prove a compatible host is claiming and
   journaling.
4. Only then submit the real request.

If any readiness step fails, return one typed terminal refusal and enqueue
nothing. Do not tell the caller to open the app and resume a phantom run.

### 6. One request has one terminal fate

Every real handoff request carries a bounded acceptance expiry. An app must
refuse and remove an expired unclaimed request rather than execute it.

The claim/expiry transition must be race-safe: either the host accepted the
request before expiry and the caller waits for it, or it expired and can never
run. There is no third state where the caller returns failure while work stays
eligible.

Use one user-visible run identity across the discarded local attempt, handoff,
journal, `show`, artifact, and terminal response. Transport attempt IDs may
exist internally but must not become competing run identities.

## Non-goals

- No global Codex `danger-full-access` configuration.
- No Keychain copying, credential export, fake homes, or vendor-specific login
  bypass.
- No mirror, clone, alternate repository, or alternate Application Support
  root.
- No new daemon, resident run owner, general RPC framework, or `alln serve`
  execution responsibility.
- No new user command, alias, shim, waiter, or manual app-open workflow.
- No change to Team resolution, write locks, worker selection, or
  `RunService.run` semantics.
- No broad app lifecycle, GUI, update, or installer cleanup beyond what the
  trusted workflow requires.

## Slices

| Slice | Scope | Exit gate |
| --- | --- | --- |
| CAR-S00 | Product-free Codex → LaunchServices → signed-app authority harness | Real Codex receipt proves or disproves automatic app launch |
| CAR-S01 | Canonical app install/discovery and exact compatibility handshake | Missing/stale app fails before real work is queued |
| CAR-S02 | Application-process-owned `SandboxHandoffHost` startup | Cold app launch answers a quota-free ping without a window dependency |
| CAR-S03 | `alln run` ensure-host flow and one run identity | App initially closed; one command returns one terminal run |
| CAR-S04 | Request expiry, race-safe claim, and cleanup | Timed-out/abandoned work can never execute later |
| CAR-S05 | Live Codex Works Test, focused proofs, Code Audit, and closeout | Full trusted workflow green; durable law promoted; packet archived |

One bounded implementation work order per slice. Do not combine installation,
transport lifecycle, and expiry correctness into one patch.

## Required proofs

Focused deterministic proofs:

- already-running compatible host;
- app initially closed, then readiness succeeds;
- app missing;
- app version/contract mismatch;
- LaunchServices refusal;
- readiness timeout leaves no real request;
- request expires before claim and never runs;
- claim wins before expiry and runs exactly once;
- caller disappears after claim without creating a duplicate;
- one canonical run identity across local failure and handoff result;
- the existing non-Codex direct path remains unchanged;
- a user-selected full-access Codex session remains on the direct path.

Required isolation proof: CAR-S00's signed-app harness from a real default Codex
session. A unit test that sets `CODEX_SANDBOX` is not a substitute.

Required founder Works Test:

```text
Precondition: Allnighter app is not running; handoff inbox is empty.
Origin: a normal default Codex session.
Action: one `alln run ... --team code_spec_review --project . --json`.
Expected:
  - no manual app launch, paste, retry, doctor, or resume;
  - one user-visible run id;
  - the requested Team executes once through RunService.run;
  - the complete answer returns in the originating terminal;
  - terminal JSON is authoritative and successful;
  - handoff inbox is empty afterward;
  - opening/reopening the app later starts no stale work.
```

Closeout proof: focused wrapper tests during implementation, then
`bash scripts/check.sh` once at closeout, followed by Deslop and Code Audit.

## Regression law

If `alln run` returns without a host accepting the work, no future process may
execute that request. A supported agent host must never need to coordinate
Allnighter's internal authority boundary manually.

What was the agent allowed to do that must never be allowed again: close a
host-boundary workflow after proving only the already-open-host case, while
calling the missing receiver an operational precondition and leaving failed
requests eligible for later quota spend.

## Done when

- The product-free authority harness is recorded and its result determines the
  permitted architecture.
- A default Codex session completes the founder Works Test with the app initially
  closed.
- No failed or abandoned invocation leaves runnable work behind.
- The caller observes one command, one run identity, and one terminal answer.
- Claude, Cursor, Grok, and full-access Codex keep their direct behavior.
- No forbidden resident/control-plane concepts return.
- Keepable laws are promoted to code/standing docs and this packet is archived.

## Open questions

Only CAR-S00 may answer this: can LaunchServices start the signed installed app
from default Codex with independent authority? If not, implementation stops for
the founder choice named in §2. No implementation agent may infer that choice.

---

## CAR-S00 result

**Verdict: RED** — leg B proved the sandbox was active, and leg C showed
LaunchServices **refusing** the launch from inside a real default Codex
session. The honest remaining choices named in §2 (a pre-running app/login
item, or explicit per-session full access) are the founder's decision; this
slice picks no architecture.

The specific refusal that caused RED, from the leg C `open -b` call:

```text
open rc: 1
open output: LSCopyApplicationURLsForBundleIdentifier() failed while trying to determine the application with bundle identifier com.happymoose.allnighter.harness.
VERDICT: NO RECEIPT within 30s
```

### Evidence

Raw captured output (committed under `scripts/harness/car_s00/receipts/`):

| Leg | File | Result |
| --- | --- | --- |
| A — control, outside Codex | `leg_A_outside_codex.txt` | GREEN: receipt fresh (nonce match), pid 5510 ppid 1, `codex_sandbox: null`, keychain `-25300` (errSecItemNotFound — reachable), outside-workspace fs write `ok` |
| B — sandbox-active control, inside Codex | `leg_B_inside_codex_sandbox_control.txt` | Sandbox genuinely in force: `CODEX_SANDBOX=seatbelt`; `touch .../AllnighterHarness/legB_denial_probe.txt` → `Operation not permitted`, exit 1 |
| C — real test, inside Codex | `leg_C_inside_codex.txt` | REFUSED: caller writes denied (`Operation not permitted`), `open -b` rc 1 with the `LSCopyApplicationURLsForBundleIdentifier()` failure above, no receipt within 30s |
| Post-C sanity check, outside Codex | `leg_C_postcheck_resolution_outside_codex.txt` | Bundle id still resolved by LaunchServices at 2026-08-02T14:13:54Z, minutes after the leg C refusal — the app was installed and registered; the refusal is attributable to the seatbelt context, not to a broken install |

### Exact commands

```bash
# Build/sign/install (Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)),
# install to ~/Applications/AllnighterHarness.app, lsregister -f:
scripts/harness/car_s00/build_and_install.sh

# Leg A (outside Codex):
scripts/harness/car_s00/probe.sh

# Leg B (real default Codex session, no sandbox flags, no config change):
codex exec "Run exactly these commands from the repo root /Users/mike/Documents/GitHub/Allnighter and report their verbatim output and exit codes. ... 1) echo \"CODEX_SANDBOX=\$CODEX_SANDBOX\"  2) touch \"\$HOME/Library/Application Support/AllnighterHarness/legB_denial_probe.txt\"  3) id"

# Leg C (same default Codex posture, session id 019fc2d1-8ec8-7242-918d-af81c4548298):
codex exec "From the repo root /Users/mike/Documents/GitHub/Allnighter, run this exact command: bash scripts/harness/car_s00/probe.sh ..."
```

Codex session posture in legs B and C (reported by Codex itself): `sandbox:
workspace-write [workdir, /tmp, $TMPDIR, ..., /Users/mike/Library/Application
Support/Allnighter]`. The harness directory `~/Library/Application
Support/AllnighterHarness` is **not** in the writable list, which is why both
the leg B touch and the leg C nonce write were denied — the sandbox-active
control is unambiguous.

### Notes

- The harness itself is proven: leg A launched via `open -b` outside Codex and
  the app came up with ppid 1 (launchd, properly detached), full Keychain
  reachability, and full filesystem authority. RED here is about Codex-side
  launch refusal, not harness correctness.
- Inside Codex, the sandboxed caller could not write the nonce or delete the
  stale receipt (both denied) — expected, and itself leg-B-grade evidence. Leg
  C was run with the receipt/nonce files pre-cleared from outside Codex so no
  stale receipt could be mistaken for a fresh one.
- One unanticipated observation, stated plainly: I do not know at which layer
  the refusal occurs (LaunchServices database lookup vs. `open` spawn vs.
  seatbelt mach-service denial) — `open` only reports the
  `LSCopyApplicationURLsForBundleIdentifier()` failure. No workaround was
  attempted; that is the founder's decision per §Open questions.
- Harness is product-free and temporary: `scripts/harness/car_s00/` (README
  includes cleanup steps). No product source was touched.
