import Foundation
// AgentOS runtime seam (engine layer). The command-runner + streaming primitives
// live in AgentOSCLI (roadmap P1.4). Re-exported so engine call sites and engine
// tests resolve them (CommandRunner, SubprocessCommandRunner, MockCommandRunner,
// StreamingCommandRunner, CommandEvent, CommandResult) unqualified, without churn.
@_exported import AgentOSCLI
// AgentOSTeam — the opt-in fan-out layer (F2_B.3b prep). See the Core-layer
// AgentOSReexports.swift for the collision note (Allnighter's dead local
// `WorkerPrompt` was deleted so AgentOSTeam's resolves unqualified).
// NOTE: plain (non-`@_exported`) import — see Core-layer file for why the
// second `@_exported` re-export path was removed. Files referencing
// `TeamAnswer`/`TeamMember`/`WorkerPrompt` must `import AgentOSTeam` explicitly.
import AgentOSTeam
