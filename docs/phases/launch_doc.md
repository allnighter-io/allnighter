# Pre-Launch — Do These Three

Status: **Active — founder-simplified 2026-08-12**
Owner: Founder
Created: 2026-08-12
Updated: 2026-08-12

Ephemeral packet. Not SSOT. A tiny user base does not need a 22-item lock-in
program. Three things before the gate opens; everything else waits for a real
complaint or a paying customer.

The long review this replaced is git history (`97f58726`). Do not restore it as
a work queue.

---

## The three

### 1. Public docs tell the truth *(legal done 2026-08-12; marketing still open)*

Do not promise tools or apps that are not in the binary.

**Legal (this slice):** EULA / ToS / Privacy v1.1 — dropped Aider (driver
rejected 2026-06-26); iOS is "when available," not included. Site HTML in
`Ikiro/allnighter` still needs a mirror before the pages go live.

**Still open:** marketing copy (`Launch_Positioning_And_Copy.md`,
`Pricing_Recommendation.md`, Growth playbook, homepage) still lists Aider,
bundles iPhone in the $8 offer, and uses retired pilot/relay nouns. Same pass,
same rule: shipped drivers only, Mac-first, overnight is not the pitch.

### 2. A stranger can install it

One paste: `curl -fsSL https://get.allnighter.io | sh`. Developer ID sign +
notarize the first public binary. DNS CNAME for `get`. Without this there is no
gate to open — ad-hoc dogfood is not a launch.

Packet: `One_Paste_Cold_Start.md` OPC-S05.

### 3. First open on someone else's Mac does not look broken

One cold install that is not yours:

- Find your team actually finds the CLIs they already pay for (Cursor.app ≠
  `cursor-agent`).
- Opening the app does not spray TCC dialogs or duplicate Dock icons.
- `alln capacity` does not print a warming table for every seat.

That is the whole first-week conversion test. If it fails, they uninstall.

---

## Not now

Billing, entitlement, Founding Builder caps, in-app terms clickwrap, support
zips, contract freezes, chat-path consolidation, Live Team Board, work recovery,
keyboard completeness, iOS, Ollama, and splitting `RunService` can wait. Hardly
anyone will be here. Ship, watch, fix what they hit.

When you start charging, *then* build the ledger described in
`One_Paste_Cold_Start.md` §Trial — not before, and not as a launch blocker.

---

## Routing

| Work | Read first |
| --- | --- |
| Legal source | `docs/legal/` (v1.1, 2026-08-12) |
| Site mirror after legal edits | `docs/legal/README.md` § Keeping the site in sync |
| Marketing claim pass | `docs/marketing/` |
| Public install | `One_Paste_Cold_Start.md` OPC-S05 |
| First-launch TCC | `docs/operations/debugger/DEBUGLOG.md` 2026-08-10 |
| Capacity warming lie | `docs/operations/debugger/DEBUGLOG.md` 2026-08-12 |
