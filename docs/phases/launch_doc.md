# Pre-Launch Review — Recommendations

Status: **Captured review — founder may disagree with priority or scope**
Owner: Founder
Created: 2026-08-12
Updated: 2026-08-12

Ephemeral packet. Not SSOT. Captures a Cursor agent pre-launch review for
founder triage. Closeout: promote anything that becomes law into
`docs/operations/` or code; archive when superseded.

---

## Context

Allnighter is close to a real launch. A lot of work is 10×–100× easier before
customers than after. This doc records what to refactor, polish, and improve
before opening the gates — ordered by lock-in cost, not engineering interest.

The product already works as an all-day bench for the founder. What is **not**
launch-ready is the commercial, legal, and distribution shell — plus a handful
of on-disk and agent-facing contracts that become expensive the day a stranger's
machine has state.

---

## Gates — do these before strangers pay you

These are not polish. Opening the faucet without them either gives the product
away forever or creates bait-and-switch.

### 1. Trial and entitlement (not built)

Pricing, ToS, and Privacy already describe: 14-day trial starting at first run,
3 full-power dispatches/day after that, Founding Builder (first 100, $160),
Stripe, Sign in with Apple, server-side machine-hash so `rm -rf` cannot mint a
new trial.

The sibling packet `Trial_And_Entitlement.md` is referenced in
`One_Paste_Cold_Start.md` and **does not exist**. `canStartTeamRun` in
`AgentBootstrap` is a bench-readiness verdict, not billing. Seams in
`One_Paste_Cold_Start.md` (MenuJSON `entitlement` field, `RunService` admission,
24h refresh piggybacking the update check) are the cheap insertion points —
after launch you are migrating live tokens.

If you launch "free for now, we'll meter later," you cannot put the 3/day cap on
people who already built a workday around unlimited. Build the ledger **before**
the first public binary, even if the first week is "everyone is on trial."

### 2. Public distribution: Developer ID, notarization, `get.allnighter.io`

OPC-S05 is still founder DNS + signing. Sparkle is not wired; `latest.json` is
the channel. Ad-hoc codesign is a known Documents TCC residual — waived for
dogfood, **not** for strangers. A notarized cold install from `~` is the only
first-user path that matches the privacy/TCC story.

### 3. Recorded legal acceptance

Terms are published (v1.0, Aug 7). Missing: Stripe Checkout consent, first-run
Mac gate (version + timestamp, block until accepted), CLI print-and-record that
**must not** block `menu` / `help` / `doctor` / `capacity`. No `termsAccept`
code exists. A later ToS revision has nothing to re-prompt against.

See `docs/legal/README.md` § Acceptance gate.

### 4. Claim freeze against what actually ships

Public copy still promises things the product does not:

| Claim still in marketing / legal | Reality |
| --- | --- |
| Aider as a worker | Driver **rejected** 2026-06-26 |
| "iPhone floor manager included" / "Mac + iPhone" in the $8 offer | iOS is **parked** |
| Growth playbook still says "pilot/relay" | Live verb is `alln loop` |
| Launch copy "Download free / Run your first team" | Entitlement and DMG are unbuilt |

False roster claims become App Store / Stripe / Reddit incidents. One pass over
`Launch_Positioning_And_Copy.md`, `Pricing_Recommendation.md`, ToS, EULA, and
the site — **shipped drivers only**, Mac-first, iPhone as "coming," overnight
never the lead.

### 5. Founding Builder hard cap

"First 100, then retired permanently" only works if Stripe + entitlement enforce
it on day one. You cannot reconstruct "who was in the first 100" from email
later.

---

## 100× cheaper now — lock-in surfaces

These are the items where the first 50 customers freeze the design.

### 6. Freeze the agent contract as 1.0, additive-only

`MenuJSON`, `TeamRunJSON`, `DoctorResult`, `schemaVersion: 1` everywhere.
Agents paste `alln menu --json` into every host. A breaking field rename after
launch is a silent outage across other people's repos. Publish "1.0 contract:
additive minors only; removals wait for a major" and stop treating
`docs/phases/` as if it can still reshuffle the wire.

### 7. Teaching snippet is the most widely distributed string you ship

`TeachingSnippet` is pasted into files the user owns (`CLAUDE.md`, etc.) and
you cannot reach later. v11 already had to bump schema so stale blocks parse as
stale, not "user edited this."

The Agent Teaching Surface packet is still open: retired `pilot`/`relay` nouns
still appear in `HelpTopicRegistry` (`pilot status` / `relay-status`). Fix the
deny-list seam **before** hundreds of hosts have a hash-pinned block. After
launch, every teaching fix is a "your agent is teaching the old product"
support class.

### 8. On-disk layout under `~/Library/Application Support/Allnighter/`

Runs, Threads, Pending, Projects, Loops, Config, Coordinator, Stalled — plus a
`Relays/` → `Loops/` move already in the past. No customers means you can still
rename, version, and add a migrator. After customers, every layout change is a
data-loss incident. Decide now: schema version per store, one migrator,
uninstall keeps user data (already true), and a documented wipe vs export.

### 9. Privacy policy vs code — audit once, then stop collecting

The policy is a launch asset: we never see prompts, code, credentials, or
outputs. That promise is almost impossible to walk back. Before gates:

- Confirm the hardware-hash trial design matches Privacy §3 (irreversible, never
  reversed).
- Fence OpenCode Go's encrypted credential file: founder ruled **no vendor-stored
  tokens for a dashboard**; Go is a live exception. Either document it as
  opt-in dogfood or keep it off the public binary.
- Decide crash/telemetry **now**. There is no Sentry/Sparkle/crash reporter. If
  you add one later, you will want breadcrumbs that include paths and prompts —
  which the policy forbids. Design a redacted crash schema (version, OS, driver
  id, error code — never prompt, path, or output) even if the pipe is empty for
  v1.

### 10. Support bundle before the first ticket

`alln doctor --json` is strong. What you will get in week one is "it doesn't
work" from a machine you cannot SSH. Ship `alln doctor --support` (or
equivalent): redacted zip of version, contract hash, bench tally, serve status,
last error envelopes — **no journals, no prompts, no repo paths**. Uninstall
already reports `userDataRetainedPath`; pair it with "how to send us a bundle"
on the support mailbox.

### 11. PIPEDA deletion and export for *account* data

Local run export exists (`alln export`). Account/entitlement/Stripe rows do not
have a deletion path. Privacy §7 will be tested by the first EU/Canadian buyer.
Cheap now: one table, one webhook, one "delete my account" that drops the ledger
row and keeps the machine-hash trial stamp (so they cannot re-trial).

### 12. One live chat path; kill or quarantine the other

There are two chat substrates: thread chat (team-free, cold, no Mac caller) and
`RunService` (warm, live Mac path). Chat Module Extraction is a multi-app
AgentOS project, not a launch item. What *is* a launch item: make Path B the
only path in the public binary so you are not migrating two histories later.

### 13. Remote kill / driver disable

No feature-flag system. The first vendor CLI change that makes a parser hang or
a serve loop fork-bomb the Dock (already happened in dogfood, 2026-08-10) will
hit every customer at once. A signed `latest.json` sibling — "disable source X"
/ "minimum version" — is a day of work now and a week of refunds later. Keep it
dumb: not smart routing, just a brake.

### 14. Grandfathering fields on the entitlement token

`plan`, `purchasedAt`, `priceLocked`. The strategy already says later customers
pay $19–24 and early ones stay at $8. If the token does not carry purchase-era,
you will argue with CSV exports in 2027.

---

## First-week conversion — the product strangers actually see

The phase board is right that the next item should come from using the product.
These are the moments that decide whether a download becomes a habit.

### 15. Notarized first-launch TCC

2026-08-10: cold open sprayed Documents/Downloads/network prompts and could
fork-bomb the Dock via `ServeAutoLaunch`. Gates exist in tests; the founder
test is `tccutil reset` → open → **one Dock icon, zero dialogs** until Refresh
/ Setup / Run. Re-run that on the **signed** binary, not Debug. This is the #1
uninstall.

### 16. First-run "Find your team" on a virgin Mac

Lean setup is built; the cinematic WOW was correctly cut. Detection CODE RED is
closed. The remaining hole is the waived cold-install dogfood: a machine that is
not yours, signed `curl | sh`, Find my team, Cursor.app vs `cursor-agent`
teaching, never-scanned ≠ `0/9`. That is the proof of "you already pay for the
team."

### 17. Capacity strip must not lie

Today's debug log: Dock app open, `alln capacity` prints warming placeholders
for every seat. Capacity is the daily-use surface the founder already routes
from, and it is free forever by pricing law. A blank/warming table on first open
reads as "this app doesn't work." Fix the warming-socket fast path before the
faucet.

### 18. `alln serve` health that a stranger can repair

Silent LaunchAgent disable is **not closed** (DEBUGLOG R1). For you it is a debug
session; for a customer it is "capacity is stale and loops died." Need: honest
"scheduler is off" in doctor/menu, and `alln serve repair` that works without
reading the debug log.

### 19. Live Team Board (the demo)

A team run that is "one line for minutes" fails the first Spec Review a buyer
actually watches. This is worth more than keyboard-shortcut completeness. Honest
rows: seated, started, streaming if real deltas exist, done — never fake %.

### 20. Thin work recovery

`Work_Recovery_And_PM_Continuity.md` is unbuilt, born from a real PM outage.
First paid mutating loop that vanishes will refund. v1 can be small:
`workRecovery` envelope on loop status (what exists, where, committed?, resume
command) — not the full scan product.

### 21. Daily-driver keys, not the whole Keyboard packet

Enter-to-send, `⌘L` focus composer, `⌘.` stop. The rest (⌘P, j/k, numbered
views) can follow. Re-base KBD-S05 off the retired approve ceremony before
touching it.

### 22. Help search and retired nouns

`alln help search` is the agent front door after bootstrap. Empty or
retired-vocabulary hits teach the old product. Same packet as teaching.

---

## Do not do these before the gates open

These are real products. They are also the wrong work while entitlement, signing,
and first-run trust are open.

| Packet | Why wait |
| --- | --- |
| iOS companion | Parked; pricing already over-promises it |
| Ollama / Context Firewall / Second Mac | Code unauthorized; founder queue ended |
| Chat Module Extraction / AgentOS ChatCore | Multi-app refactor; freeze one path instead |
| Copy lane, Contradiction Pass, Scarcity-aware routing | Not authorized or brainstorm-only |
| Receipt public signing / Buzz | Founder decision still open; local artifact already ships |
| Folder-native memory consolidation | Pointer shipped; engine is a post-habit feature |
| Thread forking | Child of persistent threads; not a first-run need |
| Splitting `RunService.swift` (~2.8k lines) "because it's big" | High regression risk; only touch for a named launch bug |
| Automated seat selection | Killed 2026-08-12 |

Broad cleanup (Deslop-the-repo, Chat extraction, "make the GUI pretty") will eat
the week you need for entitlement and the notarized first-launch.

---

## Suggested sequence

1. **Claim freeze** (copy + legal + site) — hours, unblocks everything else.
2. **Write `Trial_And_Entitlement.md` and build the ledger** — the one multi-day
   slice that cannot slip past launch.
3. **OPC-S05** — CNAME, Developer ID, notarize, one public `curl | sh` + DMG.
4. **Legal acceptance + Stripe consent + Founding Builder cap.**
5. **Contract 1.0 freeze + teaching/help retired-noun gate.**
6. **Notarized TCC + virgin Find-my-team + capacity-not-warming + serve repair.**
7. **Support bundle + redacted crash schema (even if unused).**
8. **Live Team Board + thin work recovery** — first wow and first "I didn't lose
   work."
9. **Concierge beta on 3–5 machines that are not yours** before Product Hunt /
   Show HN. Tests cannot reach live vendors; those machines *are* the live
   test.

---

## Bottom line

The strategy line is already right: *you already pay for the team; Allnighter
makes it show up to work.* Launch work is making that true for a stranger's Mac
on day one, with a deal you can still charge for on day fifteen — not adding
another team type.

---

## Routing

| Topic | Read first |
| --- | --- |
| Cold start / install / update | `One_Paste_Cold_Start.md` |
| Trial / entitlement design (referenced, not written) | `One_Paste_Cold_Start.md` §Trial |
| Legal acceptance gate | `docs/legal/README.md` |
| Pricing / offer | `docs/marketing/Pricing_Recommendation.md` |
| Launch copy | `docs/marketing/Launch_Positioning_And_Copy.md` |
| Teaching drift | `Agent_Teaching_Surface.md` |
| Open phase board | `docs/phases/README.md` |
