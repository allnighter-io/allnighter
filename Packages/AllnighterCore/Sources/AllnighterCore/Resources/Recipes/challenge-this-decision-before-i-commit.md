# Challenge this decision before I commit

Session-led blind jury (Panel). Spec Review is the common recipe — you synthesize; seats return structured findings only.

## Example utterances

1. "Challenge this decision before I commit."
2. "Run Spec Review on this doc — I want a second opinion."
3. "Blind-jury this architecture call before we build."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the router first:

```bash
alln team hello --for "challenge this decision before I commit" --json
```

Start a Panel on the target (required `--doc` / `--project`):

```bash
alln panel start --doc <path> --project <id|path> --json
```

Dispatch one blind round (built-in brief on round 1):

```bash
alln panel round --panel <id> --json
```

Check durable state / declare done when finished judging:

```bash
alln panel status --panel <id> --json
alln panel done --panel <id> --json
```

Optional chain into Pilot on the same doc after `panel done`:

```bash
alln pair pilot start --doc <same-path> --project <id|path> --json
```
