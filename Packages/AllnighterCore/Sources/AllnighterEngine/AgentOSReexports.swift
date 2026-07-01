import Foundation
// AgentOS runtime seam (engine layer). The command-runner + streaming primitives
// live in AgentOSCLI (roadmap P1.4). Re-exported so engine call sites and engine
// tests resolve them (CommandRunner, SubprocessCommandRunner, MockCommandRunner,
// StreamingCommandRunner, CommandEvent, CommandResult) unqualified, without churn.
@_exported import AgentOSCLI
