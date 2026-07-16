import Foundation

/// Router-shaped `alln team hello` payload. No tool roster, no help sitemap —
/// agents route through `nextCommandPlan` + `workflows`.
public enum AgentHello {
    public struct NextCommandPlan: Codable, Sendable, Equatable {
        public var command: String
        public var reason: String
        public init(command: String, reason: String) {
            self.command = command; self.reason = reason
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
        public var nextCommandPlan: NextCommandPlan
        public var workflows: [Workflow]
        public var readiness: Readiness
        public var routingLaw: String
        public init(
            schemaVersion: Int = 3,
            contractVersion: String,
            contractHash: String,
            binaryVersion: String,
            canStartTeamRun: Bool,
            nextCommandPlan: NextCommandPlan,
            workflows: [Workflow],
            readiness: Readiness,
            routingLaw: String = HelpService.routingLaw
        ) {
            self.schemaVersion = schemaVersion
            self.contractVersion = contractVersion
            self.contractHash = contractHash
            self.binaryVersion = binaryVersion
            self.canStartTeamRun = canStartTeamRun
            self.nextCommandPlan = nextCommandPlan
            self.workflows = workflows
            self.readiness = readiness
            self.routingLaw = routingLaw
        }
    }

    /// Every runnable command string embedded in a hello payload (plan + workflow steps).
    public static func commandInvocations(in payload: Payload) -> [String] {
        [payload.nextCommandPlan.command] + payload.workflows.flatMap(\.steps)
    }

    public static func build(
        verdict: AgentReadiness.Verdict,
        contractHash: String,
        binaryVersion: String
    ) -> Payload {
        let plan: NextCommandPlan
        if verdict.canStartTeamRun {
            plan = NextCommandPlan(
                command: "alln team preflight --team <team-id> --json",
                reason: "Validate the bench before spending quota; then start with `alln team start`."
            )
        } else {
            plan = NextCommandPlan(
                command: "alln doctor --json",
                reason: verdict.blockedReason ?? "Machine not ready to start team runs."
            )
        }
        return Payload(
            contractVersion: ContractRegistry.contractVersion,
            contractHash: contractHash,
            binaryVersion: binaryVersion,
            canStartTeamRun: verdict.canStartTeamRun,
            nextCommandPlan: plan,
            workflows: defaultWorkflows,
            readiness: Readiness(readyTeams: verdict.readyTeams, blockedReason: verdict.blockedReason)
        )
    }

    public static let defaultWorkflows: [Workflow] = [
        Workflow(id: "run_async", steps: [
            "alln team preflight --team <team-id> --json",
            "alln team start --team <team-id> --json \"<message>\"",
            "alln team result <run-id> --json",
            "alln show <run-id> --json",
        ]),
        Workflow(id: "diagnose", steps: [
            "alln doctor --json",
            "alln doctor explain <code> --json",
        ]),
        Workflow(id: "resolve_stalls", steps: [
            "alln stalled list --json",
            "alln stalled check <episode-id> --json",
        ]),
    ]

    public static func jsonString(
        verdict: AgentReadiness.Verdict,
        binaryVersion: String
    ) -> String {
        let payload = build(
            verdict: verdict,
            contractHash: ContractRegistry.contractHash(),
            binaryVersion: binaryVersion
        )
        let data = (try? CoreJSON.encode(payload)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
