# Surface Briefs

One folder per non-trivial surface: `docs/gui/surfaces/<surface>/brief.md`.
A brief is required for Tier C/D surfaces (see `../GUI_Workflow.md` §5) — those
that render run/dispatch state, quota, secrets, or pairing.

Keep briefs short. They name states, the owning core contract, and which view
fields map to which model fields, *before* code.

## `brief.md` template

```markdown
# <Surface> — Brief

**Tier:** C | D
**Visual kit:** docs/design-system/ui_kits/<kit>/
**Behavioral owner:** docs/mvp/<phase>.md  (or RB*/ios doc)

## States
loading · empty · error · running · done  (+ failed / timed_out where runs apply)

## Intents (what the user can do)
- <intent> → <core call / event sent>

## Field Ownership Ledger
| GUI field | Core model field | Source | States it appears in | Test owner |
| --- | --- | --- | --- | --- |
| Human label | `model.field` | AllnighterCore type / RunEvent | running, done | exact test file |

Rules:
- A GUI field with no core field → stop; raise the contract gap. Do not invent it.
- A derived field → name the source fields and the owner.
- Secret/quota/dispatch fields → Tier D; do not render without the owning contract.
```
