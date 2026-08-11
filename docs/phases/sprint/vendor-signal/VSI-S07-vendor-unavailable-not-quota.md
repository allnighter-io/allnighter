# VSI-S07 — say "vendor unavailable", not a word that sounds like a quota verdict

Status: **ready**
Priority: **P1 — a wrong read of this cost a real delegation today.**
SSOT: [`docs/phases/Vendor_Signal_Isolation.md`](../../Vendor_Signal_Isolation.md)
— the packet whose stated purpose is to "stop the bench lying about why
delegation failed."
Laws in play (`AGENTS.md` § Project Laws, promoted out of that packet):

- A derived signal is attributed to the source that produced it.
- Absence of a declared signal yields no observation, never an inferred one.
- **A locally computed value is never presented as a vendor-stated fact.**

## 1. What happened, measured 2026-08-11

Composer 2.5 runs failed. `alln` reported, verbatim:

```text
AGENT_FAILED · RetriableError: [resource_exhausted] Error
```

At that same moment:

| Fact | Value |
| --- | --- |
| `alln capacity`, Cursor row | **Ultra plan, 51% remaining** (46% API pool) |
| `cursor-agent --model composer-2.5` **direct** | failed ~5 of 6, after **6 internal retries** |
| `cursor-agent --model sonnet-4.5` direct, same account | **worked instantly** |

So: Cursor's Composer backend was down. The user's quota was fine. The two are
not related.

**Allnighter did nothing wrong at the attribution layer.** The string
`resource_exhausted` appears nowhere in Allnighter or AgentOS source — it is
Cursor's own text, relayed unaltered. That is the correct behaviour and this
slice must not break it.

## 2. So what is the defect?

The word. "Resource exhausted" reads as *you are out of quota*, and a reader who
believes it stops delegating. The PM agent did exactly that on this host: it
concluded the plan was exhausted, stopped using the seat, and completed the work
itself. The founder, who could see 50% of an Ultra plan remaining, correctly
called it out.

Allnighter **knew both facts** — the vendor's error and its own fresh capacity
observation — and showed only the one that misleads.

This is the packet's own defect class pointed one notch sideways: not a matcher
firing on the wrong vendor, but a true vendor string presented without the
context that makes it readable.

## 3. Copy-paste prompt

> When a run fails because a vendor's own backend is unavailable, say so in those
> words, and keep the vendor's raw text alongside rather than instead. Do not
> invent a verdict: only the source that produced the error may be named, the
> raw string must remain visible, and any capacity figure shown must be labelled
> as the vendor's own reading with its observation time. When no known
> unavailability shape matches, change nothing — relay exactly what is relayed
> today.

## 4. Read only

- `docs/phases/Vendor_Signal_Isolation.md` §12.1–12.3 — what VSI-S01/S02 already
  scoped, and the three promoted laws. Do not re-litigate them.
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
  around the `AGENT_FAILED` `ErrorSpec` (~line 1356) — the `explain` text and
  `retryable` flag a caller sees.
- `../AgentOS/Sources/AgentOSCLI/CapacityClassifier.swift` — the house pattern
  for a **source-scoped** classifier. Copy its discipline; note §12.1's open
  finding that `classifyAGYCooldown` is the one matcher that is *not* scoped, and
  do not repeat that mistake here.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
Packages/AllnighterCore/Sources/AllnighterCore/NDJSONStreamProjector.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/VendorUnavailableTests.swift   (new)
```

If the honest place to classify this turns out to be in AgentOS rather than
Allnighter, **stop and say so** with the file you need. A cross-repo change is a
separate slice.

## 6. Do not touch

`CapacityClassifier` itself, any driver, `VendorBackoffReconciler`,
`VendorSubstitutionPolicy`, the capacity probe, any scheduler, any script.

Do **not** make this failure trigger a park, a backoff, or a substitution. This
slice changes **words only**. Routing is `VendorSubstitutionPolicy`'s job and is
out of scope.

## 7. Steps

1. **A vendor-unavailable reading is source-scoped or it does not exist.** The
   pattern that recognises Cursor's shape may only ever be consulted for
   `sourceId == cursor_agent`. No shared "looks like exhaustion" matcher across
   vendors. This is the law that the whole packet exists to enforce.

2. **Fail closed on no match.** If nothing matches, emit exactly what is emitted
   today. An unrecognised failure is not "probably the vendor" — absence of a
   declared signal yields no observation.

3. **Never delete the vendor's words.** The raw string stays in the payload. A
   human debugging a driver needs the literal text; a reader skimming a failure
   needs the plain-English line. Both, not one.

4. **Any capacity figure is quoted, not computed.** If a recent capacity
   observation is shown next to the failure, it must carry the source and the
   observation time, and be worded as the vendor's own reading. Never assert
   "your quota is fine" as an Allnighter conclusion — that is the third law,
   exactly.

5. **Do not claim the vendor is down globally.** One model's backend failing is
   not the vendor being down. If the failure is scoped to a model, say the model.

6. **Failing-first.** Write the test that shows today's output reading as a quota
   verdict, watch it fail, then fix. Record the observed failure in the commit
   message.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'VendorUnavailableTests|ContractRegistryTests|NDJSONStreamProjectorTests'
```

Note: `xcode-select` now points at Xcode.app on this host, so tests **do** run.
There is no excuse for committing an unverified or non-compiling change; `bash
scripts/rebuild_cli.sh` must also succeed before you commit.

## 9. Done when

- [ ] A Cursor-shaped unavailability failure reads as the vendor being
      unavailable, in plain English, naming the model where the failure is
      model-scoped.
- [ ] The vendor's raw text is still present in the payload.
- [ ] The recogniser is consulted only for the source that produced the output —
      proven by a test where the same string on a different source classifies as
      nothing.
- [ ] An unmatched failure is byte-for-byte what it is today.
- [ ] Any capacity figure shown is attributed to the vendor with its observation
      time; no Allnighter-computed quota claim.
- [ ] No park, backoff, or substitution behaviour changed.
- [ ] Failing-first observed and recorded.
- [ ] `rebuild_cli.sh` succeeds and the focused tests pass. One commit.

## 10. Host-state invariant

Words only. No lifecycle, scheduling, routing, or capacity behaviour changes.

## 11. Why this is worth a slice

The packet's priority note already argues it: *"Teaching a caller to trust a
surface that misreports vendor state is worse than not teaching it at all."*
Today that cost one delegation and an argument about whether the bench could
count. The bench could count — it just showed the wrong number.
