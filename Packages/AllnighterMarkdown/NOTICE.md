# AllnighterMarkdown — provenance

Allnighter's **owned, themeable Markdown renderer**. We render agent output
(Inbox replies + the Floor) at IDE/Cursor quality — beautiful, not terminal-ugly —
and we control it ourselves rather than depending on a third-party tool.

## What this is forked from

- **Renderer** — vendored from [`gonzalezreal/swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui)
  (MIT, see `LICENSE-swift-markdown-ui`). The `Sources/AllnighterMarkdown` tree is
  that library's source, brought in-house as our starting point to own, theme, and
  evolve. The public API (`Markdown`, `Theme`, …) is unchanged for now; the module
  is renamed to `AllnighterMarkdown`.
- **Image loading** — vendored from [`gonzalezreal/NetworkImage`](https://github.com/gonzalezreal/NetworkImage)
  (MIT, see `LICENSE-NetworkImage`) as `Sources/NetworkImage`, so it isn't an
  external dependency.

## What we deliberately did NOT fork

- **The Markdown parser** stays on [`swiftlang/swift-cmark`](https://github.com/swiftlang/swift-cmark)
  (the standard `cmark-gfm`). Reimplementing a CommonMark/GFM parser is reinventing
  a famously hard wheel with endless edge cases — cmark-gfm is the reference parser
  everyone (Apple, GitHub) wraps. It is the one external dependency, and it is the
  standard, not a third-party tool.

So: **we own the rendering** (theme it to our tokens, Cursor-grade) and reuse the
**standard parser**. Used everywhere an agent replies — the Inbox thread and the
Team Run Floor — for one consistent experience.

Upstream is vendored, not tracked; pull fixes manually when needed.
