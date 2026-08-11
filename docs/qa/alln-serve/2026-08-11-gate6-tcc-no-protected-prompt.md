# ASR-S06 gate 6 — no protected-folder prompt on the supported path — **PASS, with one deliberate scope limit**

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 host matrix item **6** — "TCC reset + CLI install/serve from the
supported canonical layout produces no Documents/Desktop/Downloads prompt."
Host: second Mac (Mac mini), macOS 15.6 (24G84), arm64. Ad-hoc track.
Build: `777bb1d5` era.
Related incident: `docs/operations/debugger/2026-08-10-first-launch-tcc-popups-PACKET.md`,
and §3's finding that `serve enable` could read a debug binary from a Documents
checkout via `Data(contentsOf:)`.

## Result: PASS

Four independent lines of evidence.

### 1. The supported path *refuses* protected sources — behavioural

A copy of the canonical binary placed in `~/Documents` and asked to install:

```json
{ "code": "INSTALL_CANDIDATE_REFUSED",
  "message": "candidate is under ~/Documents: /Users/openclaw/Documents/alln-tcc-probe",
  "retryable": false, "success": false }
```

This is §4.3 step 1 working. The install does not merely *avoid* protected
folders — it refuses to accept a candidate from one, which is the direct fix for
the §3 seam.

### 2. Structural — the only reference is that refusal

`grep` for `Documents|Desktop|Downloads` across `CanonicalCLIInstall`,
`ServeLifecycle` and `ServeDaemon` returns exactly one hit:
`CanonicalCLIInstall.refusalReason` (line 78), the refusal list itself. No read,
write, or enumeration of a protected folder exists anywhere on the install or
serve path.

### 3. Nothing on the runtime path is protected

```text
Program:          /Users/openclaw/.local/share/allnighter/bin/alln
WorkingDirectory: /Users/openclaw/Library/Application Support/Allnighter/ProbeScratch
PATH:             /Users/openclaw/.local/share/allnighter/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

Canonical binary, working directory, and PATH are all outside TCC-protected
space. §4.2's deterministic PATH also means the daemon never evaluates a login
shell that might reach into one.

### 4. Post-reset install/serve produced no TCC event

```bash
tccutil reset SystemPolicyDesktopFolder     # Successfully reset
tccutil reset SystemPolicyDownloadsFolder   # Successfully reset
bash scripts/rebuild_cli.sh                 # full rebuild → install-cli → serve
alln serve status                           # healthy, loaded, matches
log show --last 3m --predicate 'subsystem == "com.apple.TCC"' | grep -i alln
#   → no output
```

A complete rebuild → `install-cli` → LaunchAgent registration → daemon start
cycle, run immediately after revoking Desktop and Downloads permissions,
produced **zero** TCC events attributed to `alln` and no prompt. Host ended
healthy.

## Scope limit — `SystemPolicyDocumentsFolder` was NOT reset, deliberately

This repository lives at `~/Documents/GitHub/Allnighter`. Resetting Documents
permission would revoke the running terminal's access to the working tree
mid-session, which would break the ability to commit, to run the harness, or to
restore the host if anything went wrong. The founder granted permission to run
any test; this was declined on operational-risk grounds, not permission grounds,
and is recorded rather than quietly skipped.

Documents is instead covered by evidence 1–3: the install actively **refuses** a
Documents-resident candidate, and no code on the install or serve path references
the folder at all except to refuse it. That is arguably stronger than a
no-prompt observation, because it is a property of the code rather than of one
run — but it is **not** the same measurement the gate asks for, and this record
does not pretend it is.

To close the literal gate, run on a host where the repo is **not** under
`~/Documents`:

```bash
tccutil reset SystemPolicyDocumentsFolder
bash scripts/rebuild_cli.sh
alln serve status --json
log show --last 3m --predicate 'subsystem == "com.apple.TCC"' | grep -i alln
```

## What this does NOT prove

- Documents was not empirically reset here (above).
- One host, one install lineage, ad-hoc track.
- Full Disk Access and other TCC categories are out of scope; this gate is about
  the three protected user folders.
- Says nothing about the Dock app, which is absent on this host.
- §10.1 R1 untouched.

## Signature

**No founder signature required.** §8 names gates **7, 8, 9 and 10** as the
ones needing a human at the machine, and only those. This gate was executed
and measured by the PM agent on the live host; the record above is the
evidence. An earlier draft of this file carried a "pending founder
countersignature" line — that was ceremony this packet does not ask for, and
it is removed.
