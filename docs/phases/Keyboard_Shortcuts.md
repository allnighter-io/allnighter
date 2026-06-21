# Keyboard Shortcuts

Status: SPEC (2026-06-21). Owner surface: `AllnighterMac`.
Sister docs: [Composer_Model_Popup_Update.md](Composer_Model_Popup_Update.md)
(the routing picker this binds), [Pending_Work_And_Drain.md](Pending_Work_And_Drain.md)
(the PM/pending loop keys).

## Why now, and the law

Allnighter is a tool people live in all day — the same loop Cursor / Claude / Linear
power-users run hundreds of times: open input, route it, send, read, move on. Today
the Mac app ships ~8 bindings. That is the gap. Keyboard-first navigation is not a
nicety here; it is the difference between a toy and a daily driver.

**The law: one registry, three surfaces, zero drift.** Every shortcut is an
`AppCommand` in the `CommandCenter` spine (`Apps/AllnighterMac/Sources/CommandCenter.swift`).
That single registry already feeds the macOS menu bar (real ⌘-accelerators), the ⌘K
command palette (discoverable, shows its own accelerator per row), and the transient
compose/home intents. **No shortcut may exist outside this registry** except the
focus-scoped single-key nav (see Two Tiers). If it has a key, it shows in the palette.

## Two tiers (architecture constraint — do not violate)

The `AppCommand` registry binds through `.commands {}` on the Scene, which fires
**window-globally** while the app is key. That is correct for ⌘-combos but fatal for
bare letters — a global `j` would hijack every text field.

- **Tier 1 — Global ⌘-commands.** Live in the `AppCommand` registry. Menu bar +
  palette + accelerator. All combos that include ⌘/⌃/⌥ or a function key.
- **Tier 2 — Focus-scoped single keys.** `j`/`k` list nav, `1`–`9` picker selection.
  Handled by `.onKeyPress` on the owning view (thread list, open picker) — **never**
  in the registry. These do NOT appear in the menu bar; they MAY appear in the palette
  as documentation rows (no live accelerator) or in the Settings page only.

## Locked decisions (2026-06-21)

1. **Enter sends. Follow Cursor.** `↵` sends the composer; `⇧↵` inserts a newline.
   Sending is the common act and must be one key; the line break is the two-key path.
   This replaces today's `⌘↵`-to-send (`RoutingComposer.swift` ~L746). `⌘↵` is kept as
   an always-send fallback (fires even when focus is ambiguous).
2. **Two pickers, not one.** `⌘K` = run a command (actions). `⌘P` = go to (fuzzy jump
   to any thread/project). The "jump to a thread" muscle is too valuable to bury under
   command results. Mirrors Cursor/VSCode (`⌘P` files / `⌘⇧P` commands).
3. **Numbered views, not a 2-way toggle.** `⌘1`=Inbox `⌘2`=Teams `⌘3`=Pending
   `⌘4`=Projects. Scales past two surfaces without inventing more keys. `⌃⇥` offered as
   an optional true-cycle alias.
4. **Avoid macOS-reserved combos.** `⌘M` (Minimize), `⌘H` (Hide), `⌘W`, `⌘,`,
   `⌘Space`, `⌘Tab`, edit keys. The routing picker is therefore `⌘/`, **not** `⌘M`.

## The binding map (canonical)

Status: ✓ exists · ★ explicitly requested · ◇ new.

### Zone A — Navigate
| Action | Key | Tier | Status | Precedent |
| --- | --- | --- | --- | --- |
| Inbox / Teams / Pending / Projects | `⌘1` `⌘2` `⌘3` `⌘4` | 1 | ★◇ | Slack, Linear, Things |
| Cycle view (optional true toggle) | `⌃⇥` | 1 | ◇ | — |
| Go to… (fuzzy thread/project) | `⌘P` | 1 | ◇ | Cursor/VSCode |
| Toggle sidebar | `⌘B` | 1 | ◇ | VSCode/Cursor |
| Next / prev thread in list | `j` / `k` | 2 | ◇ | Superhuman, Linear, Gmail |
| Back / forward through visited threads | `⌘[` / `⌘]` | 1 | ◇ | browser |

### Zone B — Daily loop (compose + run)
| Action | Key | Tier | Status | Notes |
| --- | --- | --- | --- | --- |
| New Chat | `⌘N` | 1 | ✓ | |
| Focus composer (from anywhere) | `⌘L` | 1 | ◇ | Cursor `⌘L`; highest-ROI add |
| **Send** | `↵` | 2 | ★◇ | Enter sends; see Decision 1 |
| Newline | `⇧↵` | 2 | ★◇ | the two-key path |
| Always-send fallback | `⌘↵` | 1 | ✓→keep | |
| Send to the *other* lane (worker⇄team) | `⇧⌘↵` | 1 | ◇ | route without switching the tab |
| Stop this run / Stop all | `⌘.` / `⇧⌘.` | 1 | ★◇ | macOS cancel; Allnighter hard-stop |
| Edit / reuse last prompt | `⌘↑` | 1 | ◇ | ChatGPT ↑-to-edit |
| Re-run last prompt | `⌘⇧R` | 1 | ◇ | re-fire same prompt at current route |

### Zone C — Routing (model / team / effort)
| Action | Key | Tier | Status | Notes |
| --- | --- | --- | --- | --- |
| Open routing picker | `⌘/` | 1 | ★◇ | model/team/effort; NOT `⌘M` |
| Toggle Model ⇄ Team tab (picker open) | `⇥` or `←/→` | 2 | ★◇ | the pill tabs |
| Pick model/team by index (picker open) | `1`–`9` | 2 | ◇ | one-keystroke route |
| Cycle Effort Low→Med→High | `⌃E` | 1 | ◇ | the `Med ▼` control |
| Use my default route | `⌘D` | 1 | ◇ | snap back to Auto/default |

### Zone D — Manage threads & projects
| Action | Key | Tier | Status |
| --- | --- | --- | --- |
| Rename thread | `F2` (also accept `⌘⇧R`? — see Open) | 1 | ✓ (fix label) |
| Pin / Archive thread | `⇧⌘P` / `⇧⌘E` | 1 | ✓ |
| Delete thread | `⌘⌫` | 1 | ◇ |
| New project (the ＋folder) | `⌘⇧N` | 1 | ◇ |
| Search list / search everything | `⌘F` / `⌘⇧F` | 1 | ✓ / ◇ |

### Zone E — Read & extract output
| Action | Key | Tier | Status |
| --- | --- | --- | --- |
| Raw ⇄ Rendered | `⌥⌘R` | 1 | ✓ |
| Copy last response / last code block | `⌘⇧C` | 1 | ◇ |
| Attach file/image | `⌘⇧A` | 1 | ◇ |
| Jump to latest / top | `⌘↓` / `⌘↑` | 1 | ◇ |
| Quick-look an attachment | `Space` | 2 | ◇ |

### Zone F — Allnighter differentiator (PM / pending loop)
| Action | Key | Tier | Status |
| --- | --- | --- | --- |
| Approve & send selected pending order | `⌘↵` (in Pending) | 2 | ◇ |
| Reject / discard pending | `⌘⌫` (in Pending) | 2 | ◇ |
| Advance PM loop ("What's next?") | `⌘↵` (in PM view) | 2 | ◇ |
| Dispatch / Verify | palette-first, show binds | 1 | ◇ |

## Settings → Keyboard Shortcuts (customizable, first-class)

Users must be able to **see and rebind** every shortcut. The registry is the SSOT,
so the Settings page is a *view + override layer* over it — it invents no new truth.

**Backend.** Introduce `KeyboardShortcutStore` (UserDefaults-backed): a map of
`AppCommand.id → KeyBinding{key, modifiers}`. `CommandCenter`/RootView resolves each
command's live accelerator as `store.override(for: id) ?? command.defaultBinding`.
`AppCommand` gains a `defaultBinding` (its current `key`+`modifiers`) so reset is
lossless. Tier-2 keys are registered in the same store (flagged `scoped: true`) so
they appear in Settings even though they bind via `onKeyPress`.

**Screen (`KeyboardShortcutsSettingsView`).**
- Searchable list, grouped by Zone (A–F headers), one row per command:
  `symbol · title · current accelerator · [Record] [⤺ reset]`.
- **Record** captures the next keystroke (NSEvent monitor scoped to the row), shows
  the glyphs live, commits on a valid combo, Esc cancels.
- **Conflict detection.** On commit, if the combo collides with another command or a
  macOS-reserved combo (Decision 4 list), show an inline warning and offer "reassign"
  (steal it, clearing the other) or "cancel."
- **Reset row / Reset all** to defaults. Per-row dirty dot when overridden.
- Renders Tier-2 rows read-only-ish with a "list/picker scope" tag.

**Discoverability stays free:** the palette and menu bar read the same resolved
bindings, so a rebind shows everywhere instantly — no second source to update.

## Two fixes to fold in (independent of new bindings)

- **`F2` label bug.** `AppCommand.shortcutLabel` upcases the raw scalar, so the
  function-key rename binding (`0xF705`) renders as `⌘?` (visible in the palette
  screenshot). Special-case function keys / arrows / return / delete to their glyphs
  (`F2`, `↩`, `⌫`, `↑`…). Fixed in S00.
- **Global-vs-scoped split.** Today everything is Tier 1. Establish the Tier-2 path
  (`onKeyPress` on the thread list + open picker) before adding `j/k` or index keys,
  or they will fight text fields. Done in S02.

## Slices (ordered; green wall after each)

- [x] **KBD-S00 — Registry hardening + label fix (DONE 2026-06-21, `2e0f07f3`).**
  Added `KeyBinding` + `AppCommand.defaultBinding`; `shortcutLabel` now renders
  function/arrow/return/delete/escape/tab/space glyphs (the rename row was showing
  `⌘?`); rename rebound to plain `F2`. `CommandCenterTests` +2 cases (special-key
  glyphs, defaultBinding).
- [x] **KBD-S01 — Phase 1 muscle-memory core (DONE 2026-06-21, `2e0f07f3`).**
  `⌘L` focus composer; `⌘1/⌘2/⌘3` Inbox/Teams/Pending; `⌘/` routing picker + `⇥`
  Model⇄Team toggle. Wired via `CommandCenter` intents (`focusComposerTick`,
  `openRoutePickerTick`) + a `.tab` `PopoverKeyAction`. **Enter-to-send / ⇧↵
  newline was already shipped** in `AllnighterTextEditor`/`handleReturn` — verified,
  no change needed. **`⌘.` stop run DEFERRED** — no run-cancel surface exists in the
  app yet to bind to (binding a key to a no-op would be fake); re-slot when a stop
  affordance lands. Covers all three explicit requests.
- [ ] **KBD-S02 — Tier-2 plumbing + list nav.** Establish `onKeyPress` scope; `j/k`
  prev/next thread; `1`–`9` model/team pick inside the open picker.
- [ ] **KBD-S03 — Go-to + window nav.** `⌘P` fuzzy quick-switcher (threads+projects);
  `⌘B` sidebar; `⌘[`/`⌘]` history; `⌘4` Projects; `⌃⇥` cycle.
- [ ] **KBD-S04 — Output + manage.** `⌘⇧C` copy last; `⌘⇧A` attach; `⌘⌫` delete
  thread; `⌘⇧N` new project; `⌘⇧F` global search; `⌃E` effort; `⌘D` default;
  `⌘↑/⌘↓` message nav.
- [ ] **KBD-S05 — PM / pending loop.** `⌘↵` approve-and-send / advance; `⌘⌫` reject;
  Dispatch/Verify palette entries with shown binds.
- [ ] **KBD-S06 — Settings page.** `KeyboardShortcutStore` override layer +
  `KeyboardShortcutsSettingsView` (record, conflict detection, reset). Wire resolution
  into menu bar + palette. GUIFixture seal for the settings screen.

## Done When

- Every action in the map is reachable by keyboard, shows its accelerator in the
  palette, and (Tier 1) in the menu bar.
- Enter sends; ⇧↵ newlines; no regressions to multiline prompts or attachments.
- The Settings → Keyboard Shortcuts page lists every command, rebinds with conflict
  detection, and resets to default; a rebind reflects in palette + menu instantly.
- `j/k` and picker index keys never fire inside a focused text field.
- No shortcut exists outside the registry/store (the law holds).
