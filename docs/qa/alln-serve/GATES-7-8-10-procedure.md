# Gates 7, 8, 10 — founder procedure (COMPLETE)

**Status: RUN COMPLETE 2026-08-11. All three gates PASS. Awaiting founder
signature on the three records.**

Host: the second Mac (Mac mini), macOS 15.6 (24G84), arm64, no
`/Applications/Allnighter.app` — §9's clean-host precondition held.
The bench was left **enabled and healthy**.

The procedure below is kept as the reproducible runbook. Re-running it means
starting a **new** run: pick a new folder under `runs/`, re-pin the build at
Setup, and clear the progress table.

---

## Progress — final

| Step | Result | Artifacts |
| --- | --- | --- |
| Setup — rebuild, pin, healthy | **DONE** | `00-setup-healthy.json` |
| Gate 7 — serve returns after logout/login | **PASS** | `gate7-before.json` (pid 83101) · `gate7-after.json` (pid 84207, launchd `runs = 1`) → record `2026-08-11-gate7-logout-login.md` |
| Gate 8 — disable survives login + reinstall | **PASS** | `gate8-before.json` · `gate8-after.json` · `gate8-after-install.json` · `gate8-restored.json` → record `2026-08-11-gate8-disable-survives-login.md` |
| Gate 10 — deadline that came due while asleep | **PASS** | `gate10-before.json` · `gate10-after.json` → record `2026-08-11-gate10-deadline-due-while-asleep.md` |

Artifacts: `docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/`.
Build under test: `ef928f6e76bcbb4fbe27335419650810bc76b795`, contract 9.19.0,
cdhash `e8bf976f73b11885cd3d32f26a650a22f6c39f62` (ad-hoc).

**Open follow-ups** (recorded, not fixed — this run was testing only):

1. While `desiredState == disabled`, `serve status` still reports the dead
   daemon's `pid`/`daemonId` in its `daemon` block. Not a live-daemon claim
   (`activeHealthRespondedAt` is null), but it reads like one. Gate 8 record,
   "Observation".
2. Gate 8 exercised `install-cli` on the `alreadyInstalled` path. A reinstall
   that actually **replaces bytes** while disabled is untested and is the more
   dangerous variant.
3. §10.1 R1 stays open. Three green gates are absence evidence for an
   undiagnosed fault, not a diagnosed fix.

---

## Resuming a run in progress (read this first)

Only relevant while a run is live. Do these before anything else:

```bash
cd ~/Documents/GitHub/Allnighter
alln version --json                 # gitSha MUST match the pinned commit below
ls docs/qa/alln-serve/runs/<run-folder>/
```

- If `gitSha` differs, **stop**. Someone rebuilt mid-run; the gates are void and
  the run restarts from Setup.
- The artifact listing tells you exactly how far the run got. The progress table
  says what is next. Do not re-run a gate that already has its files.
- **Testing only.** No dev work unless a gate fails; a failure is recorded and
  reported, not fixed inline.

Artifacts live in `docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/`.
An unrecorded gate is an unrun gate — nothing counts until the file exists.

---

## Build identity under test (pinned)

Fixed at Setup. Every gate result is only meaningful against this row.

| Field | Value |
| --- | --- |
| Commit | `ef928f6e76bcbb4fbe27335419650810bc76b795` (tree clean at build time) |
| `contractVersion` | `9.19.0` |
| `binaryVersion` | `1.0.1` |
| Built | `2026-08-11T15:34:14Z` |
| Canonical binary | `~/.local/share/allnighter/bin/alln` |
| cdhash | `e8bf976f73b11885cd3d32f26a650a22f6c39f62` (ad-hoc, `TeamIdentifier not set`) |
| Host | macOS 15.6 (24G84), arm64 — **not** the 15.6.1/24G90 gate-9 host |

The repo tree may be dirty from here on: this run writes its own artifacts into
it. Cleanliness mattered only to pin the build, which is already done.

---

## Setup — DONE 2026-08-11

Recorded, do not repeat unless the run restarts.

```bash
git status --short          # empty
git rev-parse --short HEAD  # ef928f6e
bash scripts/rebuild_cli.sh
alln version --json         # gitSha == HEAD  ✔
alln serve status --json    # healthy, EXIT=0 ✔
```

Result:

- `install-cli` migrated the LaunchAgent program from
  `~/Library/Application Support/Allnighter/CLI/alln` to the canonical
  `~/.local/share/allnighter/bin/alln`, and repaired a stale `~/.local/bin/alln`
  symlink that still pointed into the repo `.build` directory. Pre-rebuild the
  binary on PATH was built from `21c77439` — a full day stale.
- `state: "healthy"`, `EXIT=0`, `supervisor.loaded: true`,
  `binary.matches: true`, daemon pid 83101, all 7 schedulers registered
  (`boostSeed`, `capacityRefresh`, `notifications`, `pendingWake`, `pmTurnWake`,
  `probeRecordRefresh`, `vendorBackoff`).
- §9 precondition holds: no `/Applications/Allnighter.app` on this host.
- `~/.local/bin` is on PATH persistently via `~/.zshrc:5`, so the manual
  `export PATH` below is belt-and-braces, not load-bearing.

---

## Gate 7 — serve returns after logout/login

**Block A — DONE 2026-08-11 15:47Z. Do not re-run it.** Recorded before state:
`healthy`, `EXIT=0`, `desiredState: enabled`, `supervisor.loaded: true`,
`binary.matches: true`, **daemon pid 83101**, daemonId `32c158e1-933c-43aa-91c0-a51bf794dc11`,
started `2026-08-11T15:34:36Z`. Block B must show a pid other than 83101.

<details><summary>Block A commands (for a restarted run)</summary>

```bash
cd ~/Documents/GitHub/Allnighter
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate7-before.json; echo "EXIT=$?"
grep -o '"pid" : [0-9]*' docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate7-before.json
```

</details>

Then: **Apple menu → Log Out.** Log back in.

**Block B — after login. Open Terminal ONLY.** Do not open any app, do not run
any other `alln` command first. The whole point is that nothing you did started
the daemon — launchd did.

```bash
cd ~/Documents/GitHub/Allnighter
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate7-after.json; echo "EXIT=$?"
grep -o '"pid" : [0-9]*' docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate7-after.json
```

**Pass:** `after` is `healthy`, exit 0, `supervisor.loaded: true`, and a **new**
daemon pid — different from the one you wrote down.

**Fail looks like:** not healthy, non-zero exit, `loaded: false`, or the same pid
as before (which would mean the process outlived the logout rather than launchd
restarting it).

---

## Gate 8 — disable survives login, and install does not re-enable it

**Block A — DONE 2026-08-11 15:56Z. Do not re-run it.** `alln serve disable`
returned `outcome: "disabled"` / "bootout settled, plist removed, stopped
verified" / `registryVerified: true`. Recorded state: `state: "disabled"`,
`desiredState: "disabled"`, `supervisor.loaded: false`, exit 0; no `launchctl
list` entry; no plist in `~/Library/LaunchAgents/`; prior daemon pid 84207 gone
with no orphan `alln` process.

<details><summary>Block A commands (for a restarted run)</summary>

```bash
cd ~/Documents/GitHub/Allnighter
alln serve disable --json
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate8-before.json; echo "EXIT=$?"
```

</details>

**The host is disabled right now.** If the run is abandoned here, restore it with
`alln serve enable --json` — do not leave the bench off.

Then log out, log back in, **Terminal only**.

**Block B:**

```bash
cd ~/Documents/GitHub/Allnighter
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate8-after.json; echo "EXIT=$?"

# an install must not silently re-enable it
alln install-cli --json
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate8-after-install.json; echo "EXIT=$?"

# restore, then confirm the restore actually took
alln serve enable --json
alln serve status --json; echo "EXIT=$?"
```

**Pass:** disabled survives both the login and the reinstall. A disable you did
not undo must never be undone for you. The final `enable` must return the host
to `healthy` — leave the bench working.

---

## Gate 10 — a deadline that came due while asleep

Scheduler receipts carry `nextWakeAt` and `lastSuccessAt`, so this is directly
measurable rather than inferred.

**Block A — read the next due deadline:**

```bash
cd ~/Documents/GitHub/Allnighter
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate10-before.json
python3 -c "
import json
d=json.load(open('docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate10-before.json'))
for s in d['schedulers']:
    print(s['id'], 'next:', s.get('nextWakeAt'), 'lastSuccess:', s.get('lastSuccessAt'))
"
```

Note the row with the soonest `nextWakeAt` (`capacityRefresh` is usually a few
minutes out) and its `lastSuccessAt`.

Then: **close the lid.** Leave it asleep until well past that `nextWakeAt` — give
it 10 minutes to be safe. Open the lid, wait 2 minutes, then:

**Block B:**

```bash
cd ~/Documents/GitHub/Allnighter
alln serve status --json > docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate10-after.json
python3 -c "
import json
d=json.load(open('docs/qa/alln-serve/runs/2026-08-11-gates-7-8-10/gate10-after.json'))
for s in d['schedulers']:
    print(s['id'], 'next:', s.get('nextWakeAt'), 'lastSuccess:', s.get('lastSuccessAt'))
"
```

**Pass:** that scheduler's `lastSuccessAt` advanced to a time after the wake,
within 2 minutes of opening the lid (§4.4).

**Fail looks like:** `lastSuccessAt` unchanged, or `nextWakeAt` still the old
pre-sleep deadline — the loop slept through and is waiting out the original
interval. That is the failure §10.1 R2 calls the least-designed part of the
packet, and it is worth finding.

---

## Recording

Per §8 the founder is the signer; the PM records. One record per gate under
`docs/qa/alln-serve/`, carrying date, the pinned build identity above,
before/after, and pass/fail — then the founder signs.
