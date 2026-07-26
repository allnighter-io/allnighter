# TRR-S00 — Growth measure scorecard

Status: **awaiting founder disposition** (scaffold only — not Done)

SSOT: `docs/archive/phases/Team_Run_Receipt.md` §TRR-S00  
Work order: `TRR-S00-scorecard-wo.md`

## Purpose

Measure whether founder **growth packaging / series** is worth effort.
Does **not** gate the product artifact path (TRR-S01).

Kill condition (growth packaging only): fewer than **3**/20 score
stranger-worthy **for series** → kill growth packaging; keep S01 product path.

## Rubric classes (annotator guess)

| Class | Meaning |
| --- | --- |
| **a** | disagreement-with-a-call |
| **b** | consensus-with-a-call |
| **c** | lead-vs-seat reversal |
| **none** | no clear series story |

`rubric_guess` = implementer annotation only. **stranger-worthy** = founder fills (Y/N).

## Sample (N = 20)

Source: local terminal multi-seat CLI runs (prefer `plan` / `specReview`),
newest first; filled to 20 with recent `bugPacket` multi-seat runs.
Collected 2026-07-25 from Application Support run journal (not projector).

| # | run id | team | outputKind | seats | rubric_guess | stranger-worthy |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `902A3C9F-6021-4E4F-B4FF-F0BB7C75721B` | `custom_spec_review_min_cursor_gck` | specReview | 4 | a | |
| 2 | `EC1DCCAF-BBFC-40DE-96C5-9467B8C333D1` | `custom_spec_review_min_cursor_k3` | specReview | 4 | a | |
| 3 | `E900A4BC-9D7A-41CE-93F0-37F5206FACEC` | `custom_growth_min_cursor_k3` | plan | 5 | c | |
| 4 | `C1C6315E-BEE5-4BFC-93C5-0BC7D8E43C83` | `custom_spec_review_min_cursor_k3` | specReview | 4 | a | |
| 5 | `258357B8-6E2A-4272-8EF7-3571CBE9AAFC` | `custom_growth_min_cursor_k3` | plan | 5 | b | |
| 6 | `26BC77F5-80BF-4E9E-818B-82B54AA988A8` | `code_plan` | plan | 2 | none | |
| 7 | `5043DD6B-6259-4A9A-812E-DD3BCA5C9564` | `custom_code_spec_review_min_cursor_ofs` | specReview | 4 | a | |
| 8 | `B64742C5-1465-4FE6-95F7-D2FBB8D418FC` | `custom_growth_min_c3` | plan | 5 | b | |
| 9 | `1F991E7B-9DA7-47A8-8E41-B33E8006B634` | `custom_code_spec_review_min_cursor4` | specReview | 4 | a | |
| 10 | `927B8CD4-A99A-4B68-AE25-262BF52BB338` | `custom_code_spec_review_min_cursor` | specReview | 4 | a | |
| 11 | `DCE9AE48-55A9-41FD-A701-060F89C82654` | `code_spec_review_min` | specReview | 4 | b | |
| 12 | `3B00A1A7-C281-415D-96FB-058874504746` | `code_spec_review_max` | specReview | 9 | a | |
| 13 | `0644EB7A-45FE-4DBE-AF0D-E162377179EB` | `code_plan` | plan | 2 | none | |
| 14 | `19EC2189-EDD7-4B50-9B70-5513A2B74EA8` | `code_plan` | plan | 2 | none | |
| 15 | `E8443FA2-4F94-4940-AFF4-9D72C4F6D32B` | `code_plan` | plan | 2 | none | |
| 16 | `3583B913-FCB3-43B7-96CA-0A4DB9F94E2E` | `code_plan` | plan | 2 | none | |
| 17 | `19E065E8-C9F5-440D-A94F-BBFC098CF268` | `code_spec_review` | specReview | 6 | b | |
| 18 | `7409F5EB-314F-4B62-A9A9-3AF508BEC6AC` | `code_bug_hunt` | bugPacket | 5 | none | |
| 19 | `72E4B217-C28C-424D-9900-9B49A0A4AD60` | `code_bug_hunt` | bugPacket | 5 | none | |
| 20 | `752B365A-AECA-4404-9A38-D0B92980D306` | `code_bug_hunt` | bugPacket | 5 | none | |

Tally (founder fills after scoring): stranger-worthy **Y** count = ___ / 20

## Hand-renders (throwaway — NOT the projector)

Minimal HTML stubs using `docs/design-system/tokens` via `styles.css`.
Open locally in a browser. Do not promote into ArtifactProjector.

| # | file | source run | why picked |
| --- | --- | --- | --- |
| 1 | [hand-renders/01-e900a4bc-growth-reshape.html](hand-renders/01-e900a4bc-growth-reshape.html) | `E900A4BC-…` | class **c** — Lead disagreed with all four seats on pre-launch user-share loop |
| 2 | [hand-renders/02-ec1dccaf-spec-trr.html](hand-renders/02-ec1dccaf-spec-trr.html) | `EC1DCCAF-…` | class **a** — Spec Review split + Scope Steward conduct note |
| 3 | [hand-renders/03-902a3c9f-idle-hf.html](hand-renders/03-902a3c9f-idle-hf.html) | `902A3C9F-…` | class **a** — seats disagreed on facts; Lead verified and locked call |

## Founder disposition (FOUNDER FILLS)

Status remains **awaiting founder disposition**. Do **not** mark TRR-S00 Done
until one line below is written.

Choose one:

- [ ] **kill growth packaging** — fewer than 3/20 stranger-worthy for series; keep S01 product path
- [ ] **proceed with series** — optional founder growth series / packaging may continue

Disposition (one line):

```text
FOUNDER DISPOSITION: _______________________________________________
DATE: _______________
```

## Notes

- Scaffold only: no ContractRegistry, Mac, CLI, or ArtifactProjector changes.
- Phase packet §TRR-S00 stays open until disposition is recorded here or in the
  packet review log.
