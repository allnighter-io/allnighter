import Foundation

/// Router-shaped `mcp_hello` payload (MCP_Tool_Upgrade.md §6.4). No tool roster,
/// no help sitemap — agents route through `nextToolPlan` + `workflows`.
public enum AgentHello {
    public struct NextToolPlan: Codable, Sendable, Equatable {
        public var tool: String
        public var args: [String: String]
        public var reason: String
        public init(tool: String, args: [String: String] = [:], reason: String) {
            self.tool = tool; self.args = args; self.reason = reason
        }
    }

    public struct Workflow: Codable, Sendable, Equatable {
        public var id: String
        public var steps: [String]
        public init(id: String, steps: [String]) { self.id = id; self.steps = steps }
    }

    public struct Readiness: Codable, Sendable, Equatable {
        public var readyTeams: [ReadyTeam]
        public var blockedReason: String?
        public init(readyTeams: [ReadyTeam], blockedReason: String?) {
            self.readyTeams = readyTeams; self.blockedReason = blockedReason
        }
    }

    public struct Payload: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var contractVersion: String
        public var contractHash: String
        public var binaryVersion: String
        public var canStartTeamRun: Bool
        public var nextToolPlan: NextToolPlan
        public var workflows: [Workflow]
        public var readiness: Readiness
        public var routingLaw: String
        public init(
            schemaVersion: Int = 2,
            contractVersion: String,
            contractHash: String,
            binaryVersion: String,
            canStartTeamRun: Bool,
            nextToolPlan: NextToolPlan,
            workflows: [Workflow],
            readiness: Readiness,
            routingLaw: String = HelpService.routingLaw
        ) {
            self.schemaVersion = schemaVersion
            self.contractVersion = contractVersion
            self.contractHash = contractHash
            self.binaryVersion = binaryVersion
            self.canStartTeamRun = canStartTeamRun
            self.nextToolPlan = nextToolPlan
            self.workflows = workflows
            self.readiness = readiness
            self.routingLaw = routingLaw
        }
    }

    public static func build(
        verdict: AgentReadiness.Verdict,
        contractHash: String,
        binaryVersion: String
    ) -> Payload {
        let plan: NextToolPlan
        if verdict.canStartTeamRun {
            plan = NextToolPlan(
                tool: "team_start",
                args: ["dryRun": "true"],
                reason: "Validate the bench before spending quota; then call team_start without dryRun."
            )
        } else {
            plan = NextToolPlan(
                tool: "doctor",
                args: [:],
                reason: verdict.blockedReason ?? "Machine not ready to start team runs."
            )
        }
        return Payload(
            contractVersion: ContractRegistry.contractVersion,
            contractHash: contractHash,
            binaryVersion: binaryVersion,
            canStartTeamRun: verdict.canStartTeamRun,
            nextToolPlan: plan,
            workflows: defaultWorkflows,
            readiness: Readiness(readyTeams: verdict.readyTeams, blockedReason: verdict.blockedReason)
        )
    }

    public static let defaultWorkflows: [Workflow] = [
        Workflow(id: "run_async", steps: ["team_start", "team_result", "run_get"]),
        Workflow(id: "diagnose", steps: ["doctor", "error_explain"]),
        Workflow(id: "resolve_stalls", steps: ["stalled_list", "stalled_update"]),
    ]

    public static func jsonString(
        verdict: AgentReadiness.Verdict,
        tools: [ContractRegistry.MCPToolSpec],
        binaryVersion: String
    ) -> String {
        let payload = build(
            verdict: verdict,
            contractHash: MCPWire.contractHash(tools: tools),
            binaryVersion: binaryVersion
        )
        let data = (try? CoreJSON.encode(payload)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
