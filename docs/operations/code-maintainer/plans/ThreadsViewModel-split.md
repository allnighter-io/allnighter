# ThreadsViewModel split plan

Status: **CM-S07 complete (scout plan)** — decomposition proposed for CM-S08+.
Updated: 2026-08-03
Owner: code-maintainer Structure lens

## Current layout

| MARK Section / Area | LOC | Job |
| --- | ---: | --- |
| Header & State / Inits | ~220 | Stored properties, `PendingComposerContext`, convenience & designated inits |
| `MARK: - Derived` | ~20 | Computed list views (`triagedThreads`, `archivedThreads`), driver naming |
| `MARK: - List / selection` | ~217 | Coalesced store reloads (`reloadAsync`), publish generations, `applyLiveDelta` |
| `MARK: - Timeline visibility / read clear` | ~27 | Debounced visibility reporting and read-state updates |
| `MARK: - Rail controls` | ~138 | Thread creation, renaming, pinning, archiving, and project scope resolution |
| `MARK: - Routing composer` (Run execution & caching) | ~390 | `runViaRunService`, live artifact updates, `RunDecodeCache`, vendor park/resume |
| `MARK: - Routing composer` (Send & Context prep) | ~285 | `sendRouting`, `runChat`, quick capture, file ref resolution, attachment staging |
| `MARK: - Routing composer` (Attachments & Desktop) | ~112 | Attachment resolution, worker output image harvesting, thumb caching, Finder actions |
| `MARK: - GUI fixtures` | ~116 | Debug fixture seeding (`ThreadsFixtureSeeder`, live artifact fixture) |
| `MARK: - Notifications` | ~101 | Candidate detection, policy enforcement, suppression, and Mac notification delivery |

**Total:** ~1,627 LOC in one file (`Apps/AllnighterMac/Sources/ThreadsViewModel.swift`).

## Proposed layout & batches (CM-S08+)

| Batch | File | LOC | Status | Job |
| --- | --- | ---: | --- | --- |
| CM-S08 | `ThreadsViewModel+Notifications.swift` | ~101 | proposed | Notification candidates, policy filtering, suppression, and delivery |
| CM-S09 | `ThreadsViewModel+Fixtures.swift` | ~116 | proposed | GUI fixture application and live artifact debug state seeding |
| CM-S10 | `ThreadsViewModel+RailControls.swift` | ~165 | proposed | Rail operations (rename, pin, archive, new thread, project scope) & visibility reporting |
| CM-S11 | `ThreadsViewModel+Attachments.swift` | ~112 | proposed | Attachment resolution, worker output image harvesting/cleaning, thumb cache, Finder actions |
| CM-S12 | `ThreadsViewModel+RunService.swift` | ~390 | proposed | `RunService` execution, `RunDecodeCache`, live artifact projector updates, vendor park/resume |
| CM-S13 | `ThreadsViewModel+RoutingSend.swift` | ~285 | proposed | `sendRouting`, `runChat`, quick capture, file reference context, attachment staging |
| Shell | `ThreadsViewModel.swift` | ~400 | proposed | Core shell: stored properties, init, store reload/coalescing, streaming deltas |

## Natural seams

1. **Notifications**: Self-contained logic in `MARK: - Notifications` using `NotificationPolicy`, `NotificationCandidateDetection`, and `MacNotificationDelivery`.
2. **Fixtures**: Fully gated behind `#if DEBUG` in `MARK: - GUI fixtures`, calling `ThreadsFixtureSeeder`.
3. **Rail & Visibility Controls**: Thread CRUD (rename/pin/archive/new) and project binding helpers (`projectScope`), plus timeline visibility reporting.
4. **Attachments & Desktop**: Pure attachment resolution, worker image harvest/clean logic, thumbnail caching, and Finder desktop integration.
5. **Run Execution & Vendor Control**: High-level run orchestration via `RunService`, `RunDecodeCache`, live artifact state, and vendor pause/resume/substitution.
6. **Routing Composer & Send**: User turn construction, file reference context building (`ProjectFileReferenceResolver`), attachment staging (`RunAttachmentStager`), and dispatch (`sendRouting` / `runChat`).

## Risks

1. **Access control (`private` vs `package`/`internal`)**: Extracting methods to extension files requires widening `private` stored properties and helper methods to `internal` / package visibility across `ThreadsViewModel`.
2. **Shared `@Observable` state**: `ThreadsViewModel` is annotated with `@Observable` and `@MainActor`. Methods in extension files must remain `@MainActor` to avoid thread hopping and reactive state races.
3. **In-memory cache mutation**: `runCache` (`RunDecodeCache`) and `attachmentThumbCache` must be handled safely when accessed across extensions.

## First extraction batch recommendation

Recommend **CM-S08 (`ThreadsViewModel+Notifications.swift`)** as the first extraction batch:
- **Low risk**: ~101 LOC of highly isolated domain logic at the bottom of the file.
- **Clean boundary**: Self-contained interaction with `NotificationPolicy`, `MacNotificationDelivery`, and candidates.
- **Immediate gain**: Begins reducing file size while establishing the extension pattern for subsequent batches.

## Done when (for future extraction)

- [ ] `ThreadsViewModel.swift` shell ≤ 500 LOC orchestrating child extensions
- [ ] Each extension file ≤ 500 LOC, focused on one job
- [ ] Green `xcodebuild build -scheme AllnighterMac`
