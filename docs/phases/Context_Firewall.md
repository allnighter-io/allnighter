# Context Firewall — egress policy for the bench

Status: **SPEC / NO CODE AUTHORIZED.** Packet **2 of 3** in the local-work
split (§0.1). Split approved by founder 2026-08-09. Blocked on a design
question of its own (§6 root-less dispatch) and on a sibling packet's honesty
bug (§0.4).
Revised: 2026-08-09 (v1 — split out of `OpenCode_Local_Ollama_Seats.md` v6)
Owner: unassigned (`RunService` dispatch boundary + run journal)
Created: 2026-08-09
Origin: Founder brainstorm 2026-08-08/09. Local seats made a second question
unavoidable — *if a local model can read my repo, can the frontier model be
kept away from it?* Nobody sells that. Everybody sells the ban.

**One line:** a per-root policy that decides **which seats may be dispatched
against your source**, and a verbatim record of everything that crossed.

Companion packets:
[`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md) (packet 1 —
archived; local seats and promoted law),
[`Second_Mac_Bench.md`](Second_Mac_Bench.md) (packet 3),
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (a signal answers
only for the source that produced it),
[`Ambient_Dirty_Run_Outcome.md`](../archive/phases/Ambient_Dirty_Run_Outcome.md) (outcome honesty
— shared ship blocker).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 0. Standing

### 0.1 The split (founder, 2026-08-09)

Build order: **(1) nail Ollama seats → (2) this packet → (3) second Mac.**

This left packet 1 because **it is not Ollama-specific.** The boundary is
valuable behind any local body, and would matter even if Ollama vanished.
Filing it inside an Ollama packet mis-named it and under-scoped it. It is named
for the boundary, not for the runtime.

| Packet | Truth owner | Characteristic failure | Works Test |
| --- | --- | --- | --- |
| Ollama seats | Ollama runtime + agent body | model cannot hold the job; meters lie | a local seat does bounded mutating work, honestly |
| **This packet** | **the dispatch boundary** | **a crossing unrecorded; a silent promotion** | **dispatched payload == ledger, byte for byte** |
| Second Mac | a network + a second host | host identity; remote write lock | a remote seat works under a lock you can prove |

### 0.2 Founder rulings — binding

1. **It is a setting for some users and a policy for others** — and the
   difference is the product (§2). A preference the developer can disable is
   worth nothing to a regulated buyer.
2. **The claim is *auditable egress*, never *sanitisation*** (§4.1). Copy that
   implies redaction or a guarantee is a **defect**, not a stretch.
3. **Build at prosumer rigor; sell to the privacy pragmatist; let regulated
   adoption arrive bottom-up** (§3.3). No enterprise sales motion is authorized.
4. **No easy per-run override in v1** (§11.4). An override that is easy to reach
   is a firewall that does not hold.
5. **Not a prerequisite for packet 1.** Local seats ship first with
   `egress: open`. Nothing here gates them.

### 0.3 Not Ready for Implementation

Two hard blockers, one of them not ours:

1. **Root-less dispatch is undesigned** (§6). A run today is *an agent in the
   repo root* (`RunService.swift`). This packet needs a non-local seat
   dispatched with **no** project root. That is a new run shape.
2. **Outcome honesty (packet 1, §0.5 item 2) — landed `7a7f8117`.** Packet 1
   is archived. Remaining hard blocker is root-less dispatch.

### 0.4 What exists today

Nothing. No egress policy, no ledger, no root-less dispatch. The manual version
is a human with a clipboard (§1).

---

## 1. The claim

The manual version already exists and is done by hand: paste code into a local
model, ask it to genericise, paste the abstraction into the frontier model,
paste the answer back. People do this because the alternative is to give a
vendor their source or give up the good model.

Productised, it is a **per-root egress policy** plus a **ledger**:

```text
local seat     reads the repo, produces an abstraction
   │                    ↓   ← recorded verbatim in the egress ledger
frontier seat  reasons over the abstraction only — never the source
   │                    ↓
local seat     re-grounds the answer onto real files, holds the write lock
```

| Policy | Meaning |
| --- | --- |
| `egress: open` | Today's behaviour. **Default.** Unchanged for everyone who does not care. |
| `egress: abstracted` | Only local-provenance seats are dispatched against the repo root. A non-local seat receives only text a local seat emitted **in this run**. Every crossing is recorded. |
| `egress: local_only` | No paid seat runs in this root at all. |

**Why it is worth building:** every shipping answer for the privacy and
regulated segments is *"go fully on-prem and eat the capability gap."* This one
says **keep the frontier model, deny it the source, prove what crossed.**

---

## 2. Setting vs policy — the distinction that is the product

Two different things wear one name. Conflating them produces a feature nobody
pays for.

| | **Preference** | **Policy** |
| --- | --- | --- |
| Who sets it | the developer, in settings | the repo, checked in |
| Who can turn it off | the developer, when it is inconvenient | nobody, locally |
| Evidence produced | a log they own | an artifact an auditor accepts |
| Worth to a law firm / hospital | **zero** | the entire purchase |

A preference is worthless to a compliance buyer **precisely because it is
convenient to disable.** What they are buying is *something the developer
cannot turn off, that produces evidence.*

Therefore three tiers, one mechanism:

| Tier | Shape |
| --- | --- |
| **Default** | `egress: open`. Nothing changes. No surface, no cost. |
| **Setting** (privacy pragmatist) | The user flips a root to `abstracted`. Ledger exists and is theirs. |
| **Policy** (regulated) | The policy lives **in the repo**. Clone it and alln refuses paid seats *because the repo says so*, not because you configured it. Not locally overridable. Ledger exportable. |

The third row is the only one an auditor accepts, and it is a small delta over
the second — the mechanism is identical; what changes is **where the policy
lives and who may override it.** That is also a clean pricing line, and it is
why §0.2.4 forbids an easy per-run override: the override is the thing that
would collapse row three into row two.

---

## 3. Market read (external research, 2026-08-09 — not SSOT)

### 3.1 What regulated shops actually built: a ban, not a bridge

| What exists | Shape |
| --- | --- |
| On-prem / air-gapped coding assistants (Tabnine on-prem, Bodega One, Cline+Ollama+firewall, in-cluster inference) | *Go fully local, eat the capability gap.* |
| Network DLP / CASB / egress proxies | Inspect traffic. No concept of a coding agent's prompt. |
| IT policy ("the vendor is not approved on this network") | Cheapest, most common, entirely a block. |

Every security team can build a **ban** in an afternoon. **Nobody sells the
hybrid.** The felt experience under the custom solution is *"you are not allowed
to use the good model"* — a real pain with a budget attached.

### 3.2 Who feels it

| Segment | Why they are stuck |
| --- | --- |
| **Privacy pragmatist** (largest, reachable) | No mandate, just refuses to ship proprietary source to a vendor. Today: all-or-nothing, by preference. |
| **Regulated** (ITAR / HIPAA / SOX; law, medical, defense, finance) | Mandate + budget. Today: all-or-nothing, by policy. |
| **Quota-squeezed power user** | Wants the boundary for cost, not privacy — abstraction is cheaper than source. Secondary beneficiary. |

### 3.3 The go-to-market warning (founder ruling §0.2.3)

The regulated segment has the **highest value per seat** and the **worst
possible sales motion for a solo founder with zero funding**: security buyer,
procurement, SOC 2 questionnaires, long cycles. That is a different company than
the one being run.

**The play that survives that:** build the mechanism at prosumer rigor, sell it
to the privacy pragmatist (large, reachable, needs the identical mechanism, buys
with a card), and let regulated adoption arrive **bottom-up** — one developer
runs it on their own machine, security notices, and the enterprise conversation
is *initiated by them*. That is how dev tools enter regulated shops anyway.

**Treat the regulated tier as optionality, not roadmap.** No enterprise sales
motion, no compliance certifications, no procurement surface is authorized by
this packet.

---

## 4. Product law (candidate)

### 4.1 The honesty bound — read this before writing any copy

> **The promise is: you can see precisely what left this machine, verbatim, per
> run. Not: nothing sensitive left.**

A local model can and will leak identifiers into its own summary. The paid CLI
is a process on the user's machine and we do not control everything it can
reach. **We claim auditability, and we claim it exactly.**

Overclaiming here is not a marketing stretch — for a compliance buyer it is a
liability, and for us it is the difference between a defensible product and a
false statement about a security boundary. Any copy, help text, `doctor` output,
or CLI string implying redaction, sanitisation, anonymisation, or a guarantee is
a **defect** (§9).

### 4.2 Policy

1. **Policy is a property of a root.** Three values only:
   `open` (default) · `abstracted` · `local_only`.
2. **The policy never travels.** Not a property of a model, a team, a seat, or
   global config. It cannot be inferred from provenance, and it is never
   silently inherited by another root.
3. **Under `abstracted`, only local-provenance seats are dispatched against the
   repo root.** A non-local seat receives a prompt composed solely of text a
   local seat emitted **in this run**.
4. **Enforcement is dispatch-level, not a sandbox.** The non-local seat is
   simply not pointed at the repo. A mechanical read-only overlay of the real
   tree is forbidden by `scripts/check_architecture_policy.sh` and is not
   reintroduced here (§9).
5. **`local_only` refuses paid seats in that root outright** — including a Team
   whose seats would otherwise resolve to a vendor. The refusal **names the
   policy** as the reason.
6. **Refusal is user intent, not a sensor veto.** It sits with the per-root
   write lock and parked drivers, not with readiness. *Readiness informs, never
   blocks* is untouched — this is not a readiness reading.

### 4.3 Ledger

1. **Every crossing is recorded verbatim** in the run journal and addressable
   from `alln show <id>`.
2. **The ledger is written at the dispatch boundary**, not reconstructed
   afterwards. A record that can drift from what was sent is the one failure
   that makes this product worse than nothing (§9).
3. **A crossing that is not recorded is a bug**, never an optimisation, never a
   size threshold, never a truncation.
4. **Fail closed.** Local seat unavailable under `abstracted` ⇒ the run **fails**
   with a classified reason. Never a silent promotion of the frontier seat to
   repo access; never a substitution.

---

## 5. Rigor ladder — how this gets much stronger, cheaply

v1 is policy + ledger. These are the upgrades that turn "auditable" into
something a compliance officer can operate. **None requires trusting a model**,
which is what makes them defensible.

| Rung | What | Why it is cheap |
| --- | --- | --- |
| **R1 — staged egress with approval** | Hold the crossing, show it, approve, then send. The DLP-review workflow regulated shops already run. | Allnighter already has the machinery: Pending view, execution-lane FIFO, composer-in-modal review. Mostly reuse. |
| **R2 — deterministic leak detection** | Before a payload crosses, mechanically check it for verbatim spans from the source files the local seat read, plus secret/PII patterns. Report *findings*, never edits. | Deterministic; satisfies *prefer deterministic checks over recurring agent judgment*. The local seat built the abstraction from known files, so the comparison set is known. |
| **R3 — signed, exportable ledger** | One artifact per run, hash-chained, exportable. | Auditors want a file they can keep, not a UI. Artifact machinery exists (`ArtifactProjector` / `ArtifactWriter`). |

**R2 is a finding, not a fix.** "These 3 spans in the payload also appear
verbatim in your source" is honest and useful. Silently rewriting the payload
would be sanitisation, which §4.1 forbids.

Ladder order is not a schedule — packets execute end to end. R1–R3 sit in the
slice ladder (§7) as their own slices.

---

## 6. Root-less dispatch — the design blocker

A run today is **an agent in the repo root** (`RunService.swift`). This packet
needs the non-local seat dispatched with **no project root**: prompt in, prose
out, no tree.

Open, and it must be settled in **CF-S00 (design)** before any policy code:

- Is it a new run shape, a dispatch flag, or a scratch root?
- It must **not** become a mechanical read-only overlay (§4.2.4).
- It must **not** weaken or bypass the per-root write lock.
- What does `alln show` report for a run with no root — `repoDelta` is
  meaningless there, and a meaningless field that reads as "no changes" is
  exactly the class of lie in packet 1 §0.3.1.

**Graduation fork.** A no-root, judgment-only run may turn out to be a *general*
`RunService` capability rather than a firewall feature — synthesis seats today
run in the repo root even when they only combine other seats' output. If the
design lands there, it **graduates to code SSOT** and stops being documented
here. Docs are ephemeral; code is SSOT. Let that law decide it rather than
inventing a third packet.

---

## 7. Slice ladder (candidate — **unauthorized**)

Not an implementation allowlist. No slice starts without a founder ruling.

| Id | Intent | Code? |
| --- | --- | --- |
| **CF-S00** | **Design only.** Root-less dispatch shape (§6); ledger schema and where it is written; refusal copy for `abstracted` and `local_only`; `alln show` surface. Design artifact, no code. | None |
| **CF-S01** | `egress` policy on a root: parse, store, report in `doctor`. `open` behaves exactly as today (negative proof). | Core/CLI |
| **CF-S02** | `abstracted`: local-only repo dispatch + **egress ledger** (verbatim, written at the boundary) + fail-closed refusal. **The headline slice.** | Core/CLI |
| **CF-S03** | `local_only`: paid seats refused in that root; refusal names the policy. | Core/CLI |
| **CF-S04** | Policy-in-repo (tier 3, §2): checked-in policy wins over local config; not locally overridable. | Core |
| **CF-S05** | **R1** staged egress with approval — reuse Pending / composer-in-modal review. | Core/GUI |
| **CF-S06** | **R2** deterministic leak detection on the payload — findings only, never edits. | Core |
| **CF-S07** | **R3** signed, exportable ledger artifact. | Core/CLI |

Depends on: packet 1 outcome honesty (**landed** `7a7f8117`) and **at least one honest local
seat** — there is no `abstracted` mode without a local-provenance seat to hold
the repo side.

Out of ladder: sanitisation/redaction of any kind; enterprise compliance
surfaces or certifications; network-level enforcement (we are not a proxy);
per-run overrides (§0.2.4); anything in packets 1 or 3.

---

## 8. Works Test (target)

**A — Policy is inert by default (mandatory first):**

```text
Given: no egress policy set anywhere
Then:  every existing run, team, and Loop behaves exactly as before this
       packet existed — byte-identical dispatch, no new fields asserted
```

**B — `abstracted` holds (the headline; owner-visible):**

```text
Given: a root set egress: abstracted; one local seat; one paid seat
When:  alln run "<question that requires reading the repo>" --json
Then:  the paid seat is dispatched with NO repo root and receives only text the
       local seat emitted in this run;
       alln show <id> prints the egress ledger — every crossing, verbatim;
       the answer is grounded back onto real files by the local seat;
       any write happened under the per-root write lock
```

**C — Negative proofs (this is the whole product):**

```text
- kill the local seat mid-run ⇒ the run FAILS with a classified reason;
  the paid seat is never promoted to repo access, never substituted
- diff the paid seat's ACTUAL dispatched payload against the ledger
  ⇒ byte-identical, or the slice is not shippable
- egress: local_only ⇒ a Team whose seat resolves to a vendor is refused,
  and the refusal names the policy
- a second root with no policy is unaffected (the policy never travels)
```

**The ledger byte-diff is the load-bearing test.** A firewall whose record can
drift from what was actually sent is a compliance liability, not a feature.

**D — Copy review (blocking, not cosmetic):** every user-visible string about
this feature says *auditable* / *what left*, and none says sanitised,
anonymised, redacted, scrubbed, or safe (§4.1).

Proof waiver: none claimed. Nothing here is shipped as product.

---

## 9. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | The dispatch boundary — what was actually handed to the seat process. The run journal is the record; the seat's own report is **not** evidence about what it received. |
| **Lie-prone** | A ledger reconstructed after the fact rather than written at the boundary; truncated or size-capped crossings silently omitted; "firewall" read or written as sanitisation; the refusal reported as a readiness/capacity verdict instead of user intent; `repoDelta` on a root-less run reading as "no changes"; a policy silently inherited by a sibling root; a per-run override quietly added for convenience. |
| **Missing proof** | Everything. Nothing is built. Specifically: byte-diff of dispatched payload vs ledger; fail-closed on local-seat death; `open` roots provably unchanged; policy-in-repo not locally overridable. |

---

## 10. Risks

| Risk | Response |
| --- | --- |
| **Ledger drifts from what was sent** | Written at the dispatch boundary, never reconstructed. Byte-diff is a mandatory test (§8 C). |
| **Marketed as sanitisation** | §4.1 bound; copy review is a blocking Works Test (§8 D), not a polish pass. |
| **Refusal mistaken for a readiness veto** | §4.2.6 — user intent, same class as the write lock; never reported as a sensor reading. |
| **Root-less dispatch weakens the write lock** | §6 design gate; CF-S00 is design-only for this reason. |
| **Read-only overlay creeps back in** | §4.2.4; `scripts/check_architecture_policy.sh` already fails the build. |
| **Enterprise pull drags a solo founder into procurement** | §3.3 — bottom-up only; no compliance surface authorized. |
| **Built on a lying outcome meter** | Packet 1 §0.5 item 2 is a hard dependency (§0.3.2). |
| **`open` users pay a cost for a feature they do not want** | §8 A is the first Works Test: inert by default, byte-identical dispatch. |
| **Convenience override added later** | §0.2.4 — it collapses tier 3 into tier 2 and destroys the only thing regulated buyers are paying for. |

---

## 11. Open questions

1. **Root-less dispatch shape** — new run shape, dispatch flag, or scratch root?
   And the `repoDelta` question for a run with no root (§6). **Blocks CF-S01+.**
2. **Ledger surface** — a distinct `alln show` section, or an artifact? Lean:
   **both** — the journal is truth, the artifact is what a regulated buyer
   keeps (R3, §5).
3. **Policy file format and location** for tier 3 (§2) — checked-in, but where,
   and does it version? Lean: settle in CF-S00 with the ledger schema.
4. **Does `abstracted` need a scoped exception** for the moment a user knowingly
   wants one file to cross? Lean: **no in v1** (§0.2.4). Revisit only on real
   demand, and only as a *recorded, approved crossing* (R1), never as a flag.
5. **Does R2's comparison set include files the local seat read but did not
   quote?** Lean: yes — the local seat's read set is known, and that is the
   whole point of a deterministic check.

---

## 12. Done when (packet exit — future)

- [ ] `egress: open` roots behave exactly as before this packet existed
- [ ] `abstracted` holds: the paid seat never receives source, and the egress
      ledger matches the dispatched payload **byte for byte**
- [ ] Killing the local seat fails the run closed — no promotion, no substitution
- [ ] `local_only` refuses paid seats and names the policy as the reason
- [ ] Policy-in-repo is not locally overridable (tier 3, §2)
- [ ] Every user-visible word says *auditable*, never *sanitised* (§4.1, §8 D)
- [ ] Root-less dispatch either has a design that preserves the write lock, or
      has graduated to code SSOT (§6)
- [ ] No enterprise compliance surface shipped (§3.3)
- [ ] Promote keepable law; archive this packet

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Egress policy, context firewall, "keep the frontier model away from my source" | This packet §4 (law) + §8 (Works Test); **§6 root-less dispatch is undesigned and blocks code** |
| Anyone writing copy for this feature | §4.1 — *auditable*, never *sanitised*. Copy review is a blocking test, not polish. |
| Regulated / law / medical buyer interest | §3.3 — bottom-up only; no enterprise motion authorized |
| A per-run "just this once" egress override | §0.2.4 + §11.4 — refuse; it collapses the only tier regulated buyers pay for |
| Local seats themselves (Ollama, bodies, readiness) | Archived [`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md); law in `docs/operations/Project_Laws.md` §Local Ollama seats |
| Second Mac / LAN / remote host | [`Second_Mac_Bench.md`](Second_Mac_Bench.md) — packet 3 |
