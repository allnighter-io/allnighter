import Foundation
// AgentOS runtime seam. Allnighter consumes shared runtime primitives from
// AgentOSCLI (roadmap P1). Re-exported so existing call sites resolve moved types
// (e.g. `JSONValue`) unqualified, without churn. As more primitives migrate, they
// travel through this same seam.
@_exported import AgentOSCLI
// AgentOSTeam — the opt-in fan-out layer (F2_B.3b prep). Exports `WorkerPrompt`,
// `TeamMember`, `TeamAnswer`, `AgentOSTeam`. Allnighter has no local `TeamMember`/
// `TeamAnswer`; its dead local `WorkerPrompt` (zero constructors) was deleted from
// `WorkerAnswer.swift` so this one resolves unqualified without ambiguity.
@_exported import AgentOSTeam
