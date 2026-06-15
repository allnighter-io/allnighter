---
name: allnighter-design
description: Use this skill to generate well-branded interfaces and assets for Allnighter, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, the logo/icon, and design tokens for prototyping. Allnighter is a dark-mode-only macOS app that turns the user's Mac into an overnight AI-agent factory; brand is "amber phosphor on midnight."
user-invocable: true
---

Read the `readme.md` file within this skill, and explore the other available files
(`styles.css`, `tokens/`, `assets/`, `guidelines/`).

Core rules to honor:
- **Dark mode only.** Build on the midnight surfaces (`--bg-base/-surface/-raised`);
  never a light background.
- **One warm signal.** Amber (`--accent`, `#FFA630`) is reserved for the single
  primary action, the live/"alive" state, the synthesizer/winner, and the mark.
  Status hues stay muted. Don't introduce new accent colors.
- **Type:** SF Pro (native macOS) → Inter on web; SF Mono → JetBrains Mono for
  slugs, counts, model IDs, timestamps and paths. 13px body density.
- **Voice:** calm, plain-spoken, sentence case, verbs first, no emoji, no hype.
  Hide the plumbing (panel/worker/council/master plan, not worktree/subprocess).
  Numbers are concrete and mono; a worker that failed is shown failed, never faked.
- **Tight, precise chrome** (Cursor/Linear/Raycast lineage): 6px controls, 10px
  cards, white-alpha hairline borders, deep-black shadows, amber glow for "alive".

If creating visual artifacts (slides, mocks, throwaway prototypes), copy assets out
and create static HTML files that link `styles.css`. If working on production code,
copy assets and read the rules here to design as a brand expert.

If the user invokes this skill without other guidance, ask what they want to build,
ask a few focused questions, and act as an expert designer who outputs HTML artifacts
or production code, grounded in the tokens and brand above.
