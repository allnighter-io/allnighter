import Foundation
// AgentOS runtime seam. Allnighter consumes shared runtime primitives from
// AgentOSCLI (roadmap P1). Re-exported so existing call sites resolve moved types
// (e.g. `JSONValue`) unqualified, without churn. As more primitives migrate, they
// travel through this same seam.
@_exported import AgentOSCLI
// AgentOSTeam — the opt-in fan-out layer. Exports `WorkerPrompt`, `TeamMember`,
// `TeamAnswer`, `AgentOSTeam`. Allnighter has no local `TeamMember`/`TeamAnswer`;
// `TeamRun.workerAnswers` is `[TeamAnswer]` (F2_B.3c cutover — the local
// `WorkerAnswer` struct and its file were deleted).
// NOTE: plain (non-`@_exported`) import — `AgentOSTeam` already imports
// `AgentOSCLI`, and a second `@_exported` re-export path was a known trigger
// for Xcode's "'Model'/'DriverManifest' is ambiguous for type lookup" batch-mode
// errors. Files that reference `TeamAnswer`/`TeamMember`/`WorkerPrompt` must
// `import AgentOSTeam` explicitly.
import AgentOSTeam
