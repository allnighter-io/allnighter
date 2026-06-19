# Handoff: Send-to-Team **Result Reader** (SwiftUI / macOS)

## Overview
This is the screen a user lands on after a **Send to team** run completes — the result of fanning one prompt out to several CLI agents (Claude Code, Grok CLI, Codex, Gemini) and getting each reply back. It is a **reading-first** view: the agent's reply is the hero, and a left rail lets you switch between each team member's full reply in one click.

The guiding principle, and the reason this design exists: **the response is the product.** Earlier drafts buried the replies under dashboard chrome. This one makes the text the hero, the way Cursor / Claude Code / Codex do.

## About the design file
`designs/send-to-team-reader.html` is a **design reference built in HTML/CSS/JS** — it encodes the intended layout, type, spacing, color, and interactions. It is **not** code to ship. Recreate it natively in the Allnighter macOS app using **SwiftUI** (the app is a native macOS app: SF Pro, ~13px base density, dark-mode only). Pull exact values from `tokens/`.

Open the HTML in a browser to see it live (update the `../styles.css` and `../assets/` paths to this bundle's `tokens/` + `assets/`, or open it from the original project).

## Fidelity
**High-fidelity.** Final colors, type, spacing, radii, and shadows — all specified via the Allnighter tokens in `tokens/`. Match it closely; this is a polished surface.

---

## The single most important detail: **faithful markdown rendering**

Every reply on this screen — including the **Lead's synthesis** — is **raw markdown returned by a third-party CLI agent.** Allnighter does **not** restructure, summarize, or reshape it. The renderer's only job is to display the agent's markdown beautifully and **truthfully.**

Two consequences for implementation:

1. **Use a real block-level Markdown renderer.** `AttributedString(markdown:)` in Foundation only handles **inline** syntax (bold/italic/code/links) and *collapses block structure* (headings, lists, blockquotes, fenced code all flatten). That is **not sufficient** here — the replies lean heavily on `##`/`###` headings, `-` lists, `>` blockquotes, and the occasional fenced code block. Use one of:
   - **MarkdownUI** (`gonzalezreal/swift-markdown-ui`) — best SwiftUI option, fully themeable. **Recommended.** Build a `Theme` that maps to the tokens below.
   - **swift-markdown** (Apple's `apple/swift-markdown`) — parse to an AST and render to SwiftUI yourself if you want zero third-party deps.
   - The HTML prototype ships a ~30-line markdown→HTML function (in the `<script>`) showing exactly which constructs must be supported: fenced code, ATX headings (1–4), blockquotes, unordered + ordered lists, paragraphs, and inline `**bold**` / `*italic*` / `` `code` ``. Treat that as the **minimum feature set**.

2. **Ship a Rendered / Raw toggle** (top-right of the reader header). **Raw** shows the *literal* markdown source in a monospaced `Text` — nothing parsed. This is a deliberate honesty feature for power users: nothing is hidden or invented. It is also the cheapest way to prove faithfulness. Keep it.

> Do **not** parse agent prose into bespoke cards/structures. If an agent returns three plain paragraphs, render three plain paragraphs. The structure belongs to the agent.

The **one** piece of UI that is Allnighter's own (not agent text) is the **next-move action block**, and it is shown only under the **Lead** reply, explicitly labeled *"Allnighter · from this run."* Keep that labeling so product chrome is never confused with agent output.

---

## Layout / View hierarchy

Overall window is a vertical stack: **top bar** → **body**. The body is a fixed-width **cast rail** + a flexible **reader column**.

```
WindowRootView (VStack, spacing 0)
├─ TopBar                      // height 52
└─ HStack(spacing: 0)          // = .body
   ├─ CastRail                 // fixed width 298
   └─ ReaderColumn             // fills remaining
      ├─ PromptBar             // collapsible, aligned to reading column
      ├─ ReaderHeader          // who you're reading + Rendered/Raw + copy
      ├─ ScrollView { ReplyDoc + NextMove }   // the hero
      └─ Composer              // pinned bottom
```

Implementation note: a `NavigationSplitView` is the idiomatic macOS choice (sidebar = cast rail, detail = reader column). A plain `HStack` with a fixed-width sidebar is equally fine and gives you tighter control over the 298px rail and the custom header chrome. The prototype is the `HStack` model.

### Window
- Min content size ~1360 × 884. Background `bgBase` (#090B13). Dark mode only — set `.preferredColorScheme(.dark)`.

### TopBar (height 52, bg `bgSubtle` #0D101A, 1px bottom hairline `borderSubtle`)
- Traffic lights (cosmetic in-app; the real window uses the native title bar — you can drop these and use the system chrome).
- Allnighter glyph (21px, `assets/allnighter-glyph.svg`).
- **Mode switch** segmented control: `Inbox` (icon `tray`, unread badge) · `Teams` (icon `person.2`). This is the app-level workspace toggle (⌘1 / ⌘2). On this screen **Inbox** is active. Active segment: bg `bgActive` (#1F2331), text `ink50`, inset 1px `borderSubtle`. Inactive text `textMuted`.
- Spacer → project slug (`folder` icon + "Allnighter / main", mono, `textFaint`) → avatar chip ("JD", 28×28, radius 8).

### CastRail (width 298, bg `bgSubtle`, 1px right hairline, vertical scroll)
Top-padded container, `padding 12,10,16,10`.

1. **CastHead** (bottom hairline, 12 bottom padding, 10 bottom margin)
   - Row: **Back** button (30×30, radius 8, 1px `borderSubtle`, icon `chevron.left`/`arrow.left`, `textMuted`; hover bg `bgHover`) + crumb "INBOX · RESULT" (mono caps, `textFaint`).
   - **Team pill** (full-width, height 38, radius 9, bg `bgRaised` #151822, 1px `borderSubtle`, `edgeTop` inner shadow): a model glyph (15px, `textFaint`) + "Signal · **Post-to-Project Signal**" (mono 12.5; team name `ink50` bold, truncates). This is the run's team identity.
2. **Cast label row**: "THE TEAM" (mono caps, `textFaint`) ··· "6 replies" (`textDisabled`).
3. **CastCard list** — one selectable row per team member. The **Lead** is first, then a hairline divider, then the workers.

**CastCard** (`grid 32px + 1fr`, gap 11, padding 10, radius 10):
- **Glyph tile** (32×32, radius 9, bg `bgSurface` #111420, 1px `borderDefault`): the member's **model logo** (17px). Monochrome, `textMuted` (→ `textSecondary` when selected).
- Text stack (3 lines, each truncates):
  - **Role** (`ink50`, 13, semibold) + optional **tag** chip ("synthesis" — mono 8.5 caps, `accentText` text, 1px `accentBorder`, radius 4). The Lead carries the `synthesis` tag.
  - **Model** (mono 11, `textFaint`) — e.g. "Claude Opus", "Grok".
  - **Gist** (11.5, `textDisabled`) — a 3–5 word preview of the reply.
- **Default** transparent; **hover** bg `bgHover`; **selected** bg `bgActive` + 1px `borderSubtle`. The **Lead, when selected**, also gets an amber left-edge: inset 2px `accent` bar (the prototype uses `box-shadow: inset 2px 0 0`; in SwiftUI use a 2px `accent` `Rectangle` overlay on the leading edge or a leading capsule).

### ReaderColumn (fills remaining width; vertical stack: PromptBar, ReaderHeader, ScrollView, Composer)

**PromptBar** (collapsible — the prompt that started the run; bottom hairline, bg `bgBase`)
- Inner content is constrained to **max-width 720, centered, horizontal padding 32** so it aligns with the reply body below it. (This is why the prompt lives *inside* the reader column and not as a full-width bar — expanding it must not overlap the sidebar.)
- Row: avatar chip ("JD", 26×26) + text stack + a `chevron.down` that rotates 180° when open.
  - Label: "YOU SENT · 6 WORKERS · 41s" (mono caps, `textFaint`).
  - Prompt text (14, `textSecondary`): **collapsed → single line, truncated**; **expanded → wraps full, color `ink100`.**
- **Tap anywhere on the row toggles** collapsed/expanded. State: `@State private var promptExpanded = false`. This mirrors Cursor / Claude Code / Codex, where the originating prompt sits right above the response and expands in place.

**ReaderHeader** (bottom hairline, padding 15,26,14,26) — *who you're currently reading*
- Glyph tile (34×34, radius 9) with the selected member's model logo (18px, `textSecondary`).
- Meta stack: **Role** (15, bold, `ink50`) + tag chip; **subtitle** (mono 11.5, `textFaint`) — model name in `textMuted` + a short descriptor ("designated lead — synthesized the team" for the Lead, else "read the full reply below").
- **Rendered / Raw** segmented control (`seg`): bg `bgSurface`, 1px `borderSubtle`, radius 9, 3px pad. Active item bg `bgActive`, `ink50`. Mono 11.5.
- **Copy** button (32×32, radius 8, icon `doc.on.doc`) — copies the current reply's raw markdown.

**Reply document** (ScrollView; reset scroll to top on member change)
- Content constrained **max-width 720, centered, padding 18,32,40,32**.
- **Rendered mode** → the themed markdown (see Type tokens for exact element styles).
- **Raw mode** → the literal markdown string in a monospaced block: bg `bgSurface`, 1px `borderSubtle`, radius 10, padding 18,20, font SF Mono 12.5 / line-height 1.65, color `textMuted`, `white-space: pre-wrap` (in SwiftUI: `Text(rawString).font(.system(.callout, design: .monospaced))` in a bordered container, `.textSelection(.enabled)`).

**NextMove block** — *rendered only under the Lead, only in Rendered mode.* Allnighter's own chrome.
- Constrained to the same 720 column. Card: 1px `borderSubtle`, radius 12, bg `bgRaised`, `edgeTop`.
- Label row: `arrow.triangle.merge` + "TAKE THE NEXT MOVE" (mono caps, `textFaint`) ··· "Allnighter · from this run" (`textDisabled`) — **this attribution is required** so the buttons read as product, not agent text.
- Three action rows (predictable, repeatable labels across every run — **not** bespoke per-run names):
  - **Primary — "Send to Copy team"** (sub: "draft the founder thread"): the one amber element. bg `accent` #FFA630, text/`ink` `textOnAmber` #1A1203, icon tile bg `rgba(26,18,3,.16)`, trailing `arrow.right`. Hover → `accentHover`.
  - **"Send to Code team"** (sub: "build the Return Review demo") + trailing `lock` "Execute" gate (mutating → needs Execute approval).
  - **"Save to Pending"** (sub: "run later, via CLI or agent") + trailing `chevron.right`.
  - Secondary rows: 1px `borderDefault`, bg `bgSurface`, radius 10, text `textSecondary`; hover bg `bgHover` + `borderStrong`.

**Composer** (pinned bottom; top hairline, bg `bgBase`, padding 14,26,16,26)
- Constrained max-width 760, centered. Box: 1px `borderDefault`, radius 13, bg `bgRaised`, `edgeTop`; focus → `borderStrong`.
- Placeholder "Reply to the team, or ask a follow-up…" (14, `textFaint`).
- Tools row: a **"Send to team ▾"** pill (mode selector, icon `person.2` in `accentText`) · spacer · attach (`paperclip`) icon button · **send** button (36×36, radius 10, bg `accent`, icon `arrow.up`, `glowAmberSm` shadow; hover `accentHover` + `glowAmber`).

---

## Interactions & State

```swift
@State private var selectedMemberID: CastMember.ID   // default = lead
@State private var viewMode: ReplyView = .rendered    // .rendered | .raw
@State private var promptExpanded = false
@State private var composerMode: ComposerMode = .sendToTeam
```

- **Select a cast member** → reader header + reply document swap to that member's reply; scroll resets to top; NextMove shown only if `member.isLead && viewMode == .rendered`.
- **Rendered/Raw** → swaps the document body for the *current* member (global toggle is fine; persist per-screen).
- **Prompt tap** → toggles `promptExpanded` (truncate ↔ wrap), chevron rotates.
- **Copy** → puts `member.markdown` on `NSPasteboard`.
- Keyboard niceties to consider: ↑/↓ to move through the cast, ⌘C to copy the open reply, ⌘1/⌘2 for Inbox/Teams.

## Data model (suggested)

```swift
struct TeamRun {
    let prompt: String
    let team: TeamRef            // family + name, e.g. Signal / "Post-to-Project Signal"
    let workerCount: Int         // 6
    let elapsed: Duration        // 41s
    let members: [CastMember]    // members[0].isLead == true
}

struct CastMember: Identifiable {
    let id: String
    let role: String             // "Lead", "Signal Scout", "Skeptic"
    let tag: String?             // "synthesis" for the lead, else nil
    let model: String            // "Claude Opus", "Grok", "Codex", "Gemini"
    let modelGlyph: ModelGlyph   // brand logo asset
    let gist: String             // short preview for the rail
    let markdown: String         // RAW reply from the CLI — render faithfully
    var isLead: Bool { tag == "synthesis" }
}
```

The Lead is **not special-cased as Allnighter output** — it is just a CLI agent assigned the synthesis/lead role. Treat its `markdown` exactly like any worker's. The only Allnighter-authored content is the NextMove block.

---

## Design tokens → Swift

Source of truth: `tokens/colors.css`, `tokens/typography.css`, `tokens/elevation.css`. Dark-mode only — you can hardcode these (no light variants).

### Color (define a `Color` extension or asset catalog)
```swift
extension Color {
    // backgrounds
    static let bgVoid    = Color(hex: 0x05060C)
    static let bgBase    = Color(hex: 0x090B13)   // window
    static let bgSubtle  = Color(hex: 0x0D101A)   // rail, top bar
    static let bgSurface = Color(hex: 0x111420)   // tiles, controls
    static let bgRaised  = Color(hex: 0x151822)   // cards, pill, composer
    static let bgHover   = Color(hex: 0x1A1E2A)
    static let bgActive  = Color(hex: 0x1F2331)   // selected
    // text (ink ramp)
    static let ink50  = Color(hex: 0xF2F4FA)      // highest-emphasis
    static let ink100 = Color(hex: 0xE1E5F0)      // body strong / textPrimary
    static let textSecondary = Color(hex: 0xAEB5C9)
    static let textMuted     = Color(hex: 0x7E869E)
    static let textFaint     = Color(hex: 0x555C74)
    static let textDisabled  = Color(hex: 0x454C62)
    // accent (amber) — reserve for ONE primary element per screen
    static let accent      = Color(hex: 0xFFA630)
    static let accentHover = Color(hex: 0xFFC169)
    static let accentText  = Color(hex: 0xFFC169) // amber AS text
    static let textOnAmber = Color(hex: 0x1A1203) // ink on amber fills
    // borders are white-alpha:
    // borderSubtle  = .white.opacity(0.06)
    // borderDefault = .white.opacity(0.10)
    // borderStrong  = .white.opacity(0.16)
    static let accentBorder = Color.white.opacity(0)  // use Color(hex:0xFFA630).opacity(0.32)
}
```
Borders: `Color.white.opacity(0.06 / 0.10 / 0.16)`. `accentSurface` = `Color(hex:0xFFA630).opacity(0.12)`, `accentBorder` = `…opacity(0.32)`.

### Type (SF Pro + SF Mono; base 13)
- Sans = system (`.font(.system(size:weight:))`). Mono = `.system(size:..., design: .monospaced)`.
- Markdown element styles for the **Rendered** document (match these in your MarkdownUI `Theme`):

| Element | Size / weight / line-height | Color | Spacing |
|---|---|---|---|
| `h2` | 21 / 700 / 1.3, tracking −0.014em | `ink50` | 6 top, 14 bottom |
| `h3` | 14 / 700 / 1.35, **UPPERCASE**, tracking 0.08em | `textSecondary` | 26 top, 10 bottom |
| `h4` | 14 / 700 | `ink100` | 20 top, 8 bottom |
| paragraph | 14 / 400 / 1.62 | `textSecondary` | 0 0 14 |
| `strong` | inherit / 600 | `ink100` | — |
| `em` | inherit / italic | `ink100`/`textPrimary` | — |
| list item | 14 / 1.6 | `textSecondary` | 7 between; marker `textFaint` |
| blockquote | 14 / 1.6 | `textPrimary` | left 2px `accentBorder` bar, bg `white.opacity(.02)`, pad 12/16, radius 0 8 8 0 |
| inline `code` | mono 12.5 / 500 | `ink100` | bg `bgSurface`, 1px `borderSubtle`, radius 5, pad 1/6 |
| code block | mono 12.5 / 1.6 | `textSecondary` | bg `bgSurface`, 1px `borderSubtle`, radius 10, pad 14/16 |

- UI chrome type: rail role 13/600; rail model & gist 11/11.5; reader role 15/700; mono caps labels 10–11 with 0.08em tracking; segmented controls mono 11.5/600.

### Elevation
- `edgeTop` = inner top hairline `inset 0 1px 0 rgba(255,255,255,0.05)` — on raised cards/pills/composer. (SwiftUI: a 1px white-opacity overlay on the top edge, or `.shadow` won't reproduce an *inset* — use an overlay `LinearGradient`/top border.)
- `glowAmberSm` = `0 0 0 1px rgba(255,166,48,.35), 0 2px 12px rgba(255,166,48,.28)` on the send button; `glowAmber` on hover.
- General shadows are deep/low-opacity black; the window uses `shadowXL`. Depth comes from **lighter surfaces + hairlines**, not big drop shadows.

---

## Assets
- `assets/allnighter-glyph.svg`, `assets/allnighter-icon.svg` — brand marks (top bar / app icon).
- **Model logos** (Grok, Claude, OpenAI/Codex, Gemini): the prototype uses **monochrome placeholder SVGs** (inline `<symbol>`s near the top of the HTML). Replace with the real, licensed brand marks as **template images** (`.renderingMode(.template)`) tinted `textMuted` / `textSecondary` — **monochrome and muted, never full color** (a deliberate design decision — color is reserved for the single amber action).
- **UI icons** = SF Symbols. Mapping from the prototype's Lucide names:
  `inbox`→`tray` · `users-round`→`person.2` · `folder-git-2`→`folder` · `arrow-left`→`chevron.left` · `chevron-down`→`chevron.down` · `copy`→`doc.on.doc` · `git-merge`→`arrow.triangle.merge` · `file-text`→`doc.text` · `hammer`→`hammer` · `lock`→`lock` · `clock`→`clock` · `arrow-right`→`arrow.right` · `chevron-right`→`chevron.right` · `paperclip`→`paperclip` · `arrow-up`→`arrow.up`.

## Files
- `designs/send-to-team-reader.html` — the reference design (open in a browser; read the `<script>` for the markdown constructs that must render and the exact element styling).
- `tokens/colors.css` · `tokens/typography.css` · `tokens/elevation.css` — design tokens (source of truth for the Swift values above).
- `assets/` — brand SVGs.

## Open product questions (worth deciding before build)
- **Rail gist** — agent's first line, or a short Lead-written label? (Prototype uses a hand-written gist.)
- **Default reply view** — Rendered (current) vs Raw for power users.
- **Long/messy replies** — confirm the renderer degrades gracefully (huge code blocks, tables, tool-call noise). Faithful means showing mess as mess; just make sure layout holds.
