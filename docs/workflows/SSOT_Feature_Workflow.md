# SSOT Feature Workflow

Use before planning any Allnighter feature, workflow, schema, WebSocket message,
agent driver, auth path, or UI state that carries product meaning.

## Product Unit

Allnighter ships trusted workflow slices.

A slice is valuable only when it includes:

- a user-visible claim;
- one truth owner;
- one Works Test or explicit proof waiver;
- generated artifacts updated from the source, if any;
- deletion targets for duplicate truth.

Example shape:

```text
enroll repo -> run team -> review plan -> spawn lane work
```

MVP loop from `ALLNIGHTER.md`:

```text
enroll repo on Mac -> run team (parallel CLIs -> plan) -> review on Mac
```

## Phases Are Ephemeral (never SSOT)

`docs/phases/` holds **build packets** while a feature is in flight. It is
never the durable SSOT.

When the product ships (or the packet closes):

1. **Promote** keepable law into the right standing home — code for runtime
   behavior; `docs/operations/`, `docs/workflows/`, `docs/design-system/`,
   `docs/gui/`, or `docs/strategy/` for process, invariants, brand, and
   standing engineering rules.
2. **Archive** the phase packet under `docs/archive/phases/`.

Do not leave “living SSOT” or “Product shipped” documents in `docs/phases/`.
Do not archive without promotion when prose must outlive the build.

See `docs/phases/README.md` §Purpose + §Operating Rules.

## Non-Negotiable Rule

Every semantic rule starts in an owning source of truth.

No durable product, permission, pairing, run, agent-driver, privacy, or
readiness rule may begin life only in:

- SwiftUI view code;
- prompt prose;
- docs;
- generated parser output;
- local fixture data;
- runtime heuristics.

## CLI-First Rule

Every capability ships as an `alln` CLI command first; the GUI and iOS only present
that contract. A slice's CLI surface (commands, arguments, JSON output, exit codes,
errors) is part of the slice, not a follow-up. A feature with no CLI surface is not
Ready for Implementation. CLI, GUI, and iOS share one contract — never parallel
JSON. This is the exact gap that let the old MCP surface fall behind the app before
MCP was retired (`docs/phases/MCP_Retirement.md`); the discipline stays even with
one wire format.

## Teaching Surface Rule

The agent-facing teaching surface — `HelpTopicRegistry` topics, help search
aliases, bootstrap/teach snippets, `nextToolPlan` steps, doctor recovery text,
and any active ops doc agents are routed to — is part of every capability, not
polish. It is a **lie-prone layer in every packet by default**.

- A capability change ships in the same slice as the help topics that teach it,
  the search terms that find it, and the decision-tree row that routes to it.
  See `SSOT_Founder_Input_Workflow.md` §Agent-facing help for the closeout
  questions.
- **Retirement Rule:** retiring a command, flag, surface, or vocabulary is not
  done at code deletion. The same slice must (a) sweep every teaching surface
  for the dead grammar, and (b) add the dead grammar to the retired-vocabulary
  deny-list that the help-corpus test gate enforces — so the grammar can never
  be re-taught, only re-introduced deliberately by editing the deny-list.
- **A surface that cannot work must not be discoverable.** A command left
  listed, helped and searchable while failing closed is a trap: it cost a full
  founder session when a frozen `alln panel` sent an agent down a fallback path.
  Delete the surface with the feature, or make its failure name the working
  replacement.
- Prose that names an `alln` command or flag which `ContractRegistry` cannot
  resolve is a P0 bug, same class as GUI-only truth.
- **Product vocabulary** for shipped capabilities belongs in
  `docs/workflows/Product_Vocabulary.md` at closeout (substitution tiers,
  team depth, crafts, **agent / model / skill**, CLI `--model`, etc.) — not only
  in archived phase packets. Retiring a noun (e.g. **worker**) requires the same
  slice to sweep GUI, CLI flags, help, recipes, and `RetiredVocabulary` — never
  a blind grep; **agents** count roster seats, **models** name CLI pins.
- A phase doc may claim "shipped"/"verified" only for state that is committed
  AND observable on a binary built from committed HEAD. "Bumped in my working
  tree" is not shipped.

## Honest Reporting Rule

A layer that consumes work must leave a readable record of what happened to it,
and must never name a cause it did not observe.

Learned the expensive way in `docs/archive/phases/Sandbox_Handoff_Hotfix.md`,
where every single defect was silence rather than wrong logic: a discarded
failure, an unlogged host, `exit 0` on a failed run, silently dropped request
fields, a 30-minute wait with nothing on screen, and a message that told the
founder "Allnighter isn't open" about an app that was open and busy.

- **A silent drop is worse than a failure.** Any path that can consume work
  writes a terminal, readable record — or it does not ship.
- **Never assert an unobserved cause.** Report what was observed. If two
  different problems produce the same symptom, the surface must distinguish
  them, not pick the likelier-sounding one.
- **Exit codes are part of the contract.** A failed run that exits 0 is
  indistinguishable, to an agent host, from a command that did nothing.
- **A comment is not a contract.** Two comments in that subsystem described
  behavior the code beneath them did not implement.

## Deterministic Guardrail Rule

Recurring correctness questions should become deterministic checks: Swift types,
Codable schemas, parser tests, lint, fixture replay, XCTest, script, or CI gate.

Use agents for review-heavy work. Do not leave repeatable checks to model
review once the rule is known.

## Planning Order

1. Read `ALLNIGHTER.md`, `docs/mvp/README.md`, and `docs/WORKING_RULES.md`.
2. **Prior art.** Name how this problem is already solved by mature tools
   (CLI frameworks, `git`/`kubectl`/`terraform`/`gh`/`wrangler`, and the AI CLIs
   we orchestrate). Adopt the convention or write down why we deviate. We do not
   re-derive solved problems under incident pressure — that is how a codebase
   ends up hand-maintaining what a framework generates.
3. Translate founder/user input into a Feature Packet.
4. Identify the trusted workflow slice.
5. Name the truth owner.
6. Name affected models, WebSocket messages, Mac/iOS surfaces, parsers, and
   agent driver configs.
7. Define the CLI surface first: the `alln` command(s), their arguments, JSON
   output, exit codes, and errors. The GUI/iOS present this contract; they never
   own a parallel one.
8. Define the teaching surface: which help topics teach it, what search terms
   find it, what the retirement sweep must remove and deny-list.
9. Define the user-visible claim.
10. Define the Works Test: setup, gesture, owner path, output, assertion.
11. Name supporting checks. **A mock cannot close a host-boundary claim:** the
    only evidence for "works from inside host X" is a run started from inside
    host X. Mock tests prove plumbing, not the boundary.
12. Name deletion targets for duplicate truth.
13. Name proof waiver only when proof cannot be built yet.

If the rule cannot be assigned to an owner, stop and fix the design.

## Feature Packet

```text
Allnighter Feature Packet

Status: Draft | Blocked | Ready for Implementation

Founder Intent
- Raw request:
- Prior art (how mature tools solve this; adopt or justify deviation):
- Product value:
- Trusted workflow slice:
- Non-goals:

Current State
- Existing truth owners:
- Existing models/API paths:
- Existing parsers/generated outputs:
- Existing UI surfaces:
- Existing tests/proof:

SSOT
- Truth owner:
- Lie-prone layers:
- New/changed semantic rules:
- Duplicate truth to delete:

Implementation
- CLI surface (`alln` command(s) + args + JSON + exit codes):
- Teaching surface (help topics + search terms + bootstrap/decision-tree impact):
- Retired grammar swept + deny-listed (for retirements):
- Model/package impact:
- Mac app impact:
- iOS app impact:
- WebSocket/protocol impact:
- Agent driver impact:
- Auth/privacy/permissions impact:

Proof
- Works Test:
- User gesture:
- Fixture/scenario:
- Exact command:
- Missing proof / waiver:

Done When
- User-visible claim:
- CLI contract shipped + tested (not GUI-only):
- Teaching surface updated (help finds it; nothing dead taught):
- Proof:
- Docs/logs:
```

## Inference Bans

For cross-layer features, add one row per layer junction.

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |

The ban should be specific enough to become a test or lint rule.
