# ASR-S04c — the serve-spawn gate must catch spawning, not mentioning

Status: **ready**
Priority: **P1 — the architecture gate is RED, which blocks closeout.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.3
("an ordinary command never starts an unsupervised `alln serve` child"), §8
ASR-S04's gate requirement, §8 ASR-S05's teaching requirement.

## 1. The collision, measured

`bash scripts/check_architecture_policy.sh` → **exit 1**:

```text
architecture-policy: forbidden serve spawn pattern 'alln serve' in
  Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift
```

and, after `uninstall` landed, also in `AllnighterCLI.swift`.

Neither is a spawn.

- `HelpTopicRegistry.swift` contains the **help topic** added by ASR-S05b. Its
  body markdown says things like "check `alln serve status --json`". That is the
  teaching §8 ASR-S05 explicitly requires.
- `AllnighterCLI.swift` contains the **usage string**:
  `"usage: alln serve [--health --json] | alln serve status [--json] | …"`.

The rule in `config/architecture-policy.json` is
`forbiddenServeProcessPattern: "alln serve"`, allow-listed to exactly one file
(`ServeLifecycle.swift`). `validate_architecture_policy.py` strips comments and
then does a plain substring match, so any **string literal** mentioning the
command trips it.

So ASR-S04's ban and ASR-S05's teaching mandate are in direct conflict, and the
ban currently wins by accident.

## 2. Why the blunt fixes are wrong

**Do not just add the two files to `serveSpawnAllowedFiles`.** `AllnighterCLI.swift`
is exactly where an unsupervised spawn would most plausibly be added — allow-listing
it removes the gate from the file it most needs to guard. That trades a false
positive for a false negative, which is worse: §7's negative-proof rule exists
because a gate that cannot fail is not a gate.

## 3. What the rule should actually catch

§2.3 bans *starting a process*. The signal is a spawn construct — a `Process`,
`posix_spawn`/`exec`, or a command-argument array — whose target is the serve
subcommand. A string handed to a user, a help body, or a usage message is not
that.

## 4. Copy-paste prompt

> The architecture policy's `forbiddenServeProcessPattern` matches any Swift
> string containing `alln serve`, so the ASR-S05 help topic and the CLI usage
> message now fail the gate even though neither spawns anything. Make the rule
> detect a serve **spawn** — a process/exec construct targeting the serve
> subcommand — rather than a mention. Keep it able to fail: the seeded-violation
> fixtures must still catch a real spawn added to a non-lifecycle file.

## 5. Read only

- `scripts/validate_architecture_policy.py` — `forbiddenServeProcessPattern`
  handling around lines 113–123, and the seeded-violation fixture machinery
  (the positive and negative fixtures near lines 105–130).
- `config/architecture-policy.json` — the rule and `serveSpawnAllowedFiles`.
- `Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift` and
  `AllnighterCLI.swift` — the two legitimate mentions that must stop failing.
  **Do not change either file to appease the gate.**

## 6. Touch only

```text
scripts/validate_architecture_policy.py
config/architecture-policy.json
```

## 7. Do not touch

Any Swift source. The fix is in the rule, not in the code it inspects. If you
find yourself editing a `.swift` file, stop — that is the gate winning an
argument it should lose.

## 8. Steps

1. **Define spawn, not mention.** A violation needs a process-construction
   context — `Process(`, `.executableURL`, `.arguments`, `posix_spawn`, `execv`,
   a shell invocation — associated with the serve subcommand. A bare string
   literal is not enough.

2. **Keep the gate able to fail — this is the whole point.** The existing seeded
   violation must still be caught. Add fixtures for the two new cases:
   - a **real spawn** of `alln serve` in a non-lifecycle file → must FAIL;
   - a **help/usage string** mentioning `alln serve` → must PASS.
   Both directions, or the rule is untested.

3. **Do not widen `serveSpawnAllowedFiles`** to include `AllnighterCLI.swift`.
   That file is precisely where a bad spawn would appear.

4. **State the residual risk** in the commit message. A pattern-based rule can
   still be evaded (string concatenation, a variable holding the subcommand).
   Say what this catches and what it does not, rather than implying it is
   airtight.

## 9. Works Test

```bash
bash scripts/check_architecture_policy.sh          # must PASS
python3 scripts/validate_architecture_policy.py    # seeded violations must still be caught
```

Both are read-only. Run them and paste real output, including the seeded-failure
proof.

## 10. Done when

- [ ] `check_architecture_policy.sh` passes with the ASR-S05 help topic and the
      CLI usage string in place, unmodified.
- [ ] A seeded real spawn in a non-lifecycle file still FAILS the gate.
- [ ] A seeded help/usage mention PASSES.
- [ ] `AllnighterCLI.swift` is **not** added to the spawn allowlist.
- [ ] No Swift source changed.
- [ ] Residual evasion risk stated in the commit message.
- [ ] One commit.

## 11. Host-state invariant

Tooling only. No product behaviour changes.
