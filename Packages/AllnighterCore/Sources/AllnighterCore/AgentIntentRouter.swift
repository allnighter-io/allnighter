import Foundation

/// Deterministic intent → team/primitive matcher for `alln team hello --for`
/// (`docs/archive/phases/Agent_Intent_Router.md` IR-S01 / IR-S02; code is SSOT).
///
/// Indexes:
/// - **Family index** — `TeamPreset` `typeTags` / `description` / `starterPrompts` / `lane`
///   (+ displayName). Owner: `BuiltInTeams` / `TeamCatalog`.
/// - **Worker index** — `ModelCatalog` displayName / modelLabel / id across drivers.
/// - **Primitives** — Pilot / Relay / Chat are outside the team catalog.
///
/// # Overlap precedence & tie-breaking
/// Scores are additive keyword matches. When multiple families compete, apply
/// these boosts (in order) before the final sort:
/// 1. **UI-broken → GUI Bug Hunt** — tokens matching UI/visual AND brokenness,
///    without design-direction or usability-friction exclusives, boost
///    `code_gui_bug_hunt` and demote Design / Usability / generic Bug Hunt.
///    Phrase "the UI is broken" therefore resolves to GUI Bug Hunt alone.
/// 2. **Default depth** — Min/Max tiers are never primary unless the intent
///    explicitly asks for min/quick or max/deep/escalation.
/// 3. **Higher score wins**; ties break on lower team id (stable lexicographic).
///
/// # No-match
/// Below `minimumScore`, return `INTENT_NO_MATCH` with concrete `nextActions`
/// (never bare "pick a team").
///
/// # Emitted command grammar (frozen)
/// - Team: `alln team start --team <id> --json` + prompt as final argv element
/// - Chat/run: `alln run --worker <id> --stream` when mutating (progress transport);
///   `--json` only for read-only/advisory final envelopes (+ `--project <id|path>`)
/// - Relay: `alln pair relay --doc <path> --project <id> --pm-worker <id> --dev-worker <id> --json`
/// - Pilot: `alln pair pilot start --doc <path> --project <id> --json`
/// - Lifecycle (IR-S02b): registry-faithful monitor/result/cancel argv sharing `<run-id>`
/// Commands are always `argv` + `display`; intent text is never shell-interpolated.
public enum AgentIntentRouter {

    // MARK: - Public payload

    public struct RunnableCommand: Codable, Sendable, Equatable {
        /// Structured argv — prefer this over parsing `display`.
        public var argv: [String]
        /// Human/agent display form. Does not shell-quote untrusted intent;
        /// when the prompt is present it appears as a final argv element and
        /// `display` shows `<prompt>` in its place.
        public var display: String
        public init(argv: [String], display: String) {
            self.argv = argv; self.display = display
        }
    }

    public struct Recommended: Codable, Sendable, Equatable {
        public var kind: String
        public var teamId: String?
        public var why: String
        public var command: RunnableCommand?
        public var depthAlternates: [String]
        public var modelId: String?
        public var driverId: String?
        public var safetyPosture: String?
        public init(
            kind: String, teamId: String? = nil, why: String,
            command: RunnableCommand? = nil, depthAlternates: [String] = [],
            modelId: String? = nil, driverId: String? = nil, safetyPosture: String? = nil
        ) {
            self.kind = kind; self.teamId = teamId; self.why = why
            self.command = command; self.depthAlternates = depthAlternates
            self.modelId = modelId; self.driverId = driverId
            self.safetyPosture = safetyPosture
        }
    }

    public struct IntentReadiness: Codable, Sendable, Equatable {
        public var ready: Bool
        public var blockedReason: String?
        public var code: String?
        public init(ready: Bool, blockedReason: String? = nil, code: String? = nil) {
            self.ready = ready; self.blockedReason = blockedReason; self.code = code
        }
    }

    public struct RequestedWorker: Codable, Sendable, Equatable {
        public var requestedName: String
        public var resolvedModelId: String?
        public var why: String
        public var alternates: [String]
        public init(requestedName: String, resolvedModelId: String? = nil,
                    why: String, alternates: [String] = []) {
            self.requestedName = requestedName
            self.resolvedModelId = resolvedModelId
            self.why = why; self.alternates = alternates
        }
    }

    public struct Fallback: Codable, Sendable, Equatable {
        public var kind: String
        public var teamId: String?
        public var why: String
        public var command: RunnableCommand?
        public init(kind: String, teamId: String? = nil, why: String,
                    command: RunnableCommand? = nil) {
            self.kind = kind; self.teamId = teamId; self.why = why; self.command = command
        }
    }

    public struct NextAction: Codable, Sendable, Equatable {
        public var command: String
        public var reason: String
        public var code: String?
        public init(command: String, reason: String, code: String? = nil) {
            self.command = command; self.reason = reason; self.code = code
        }
    }

    /// Decision 10 control bundle — monitor / result / cancel for long-running
    /// runnable targets. Each arm is registry-faithful argv; chat may omit
    /// monitor/result when `--stream` (or final-only `--json`) is the transport.
    public struct LifecycleBundle: Codable, Sendable, Equatable {
        public var monitor: RunnableCommand?
        public var result: RunnableCommand?
        public var cancel: RunnableCommand?
        public init(
            monitor: RunnableCommand? = nil,
            result: RunnableCommand? = nil,
            cancel: RunnableCommand? = nil
        ) {
            self.monitor = monitor
            self.result = result
            self.cancel = cancel
        }
    }

    public struct Payload: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var intent: String
        public var recommended: Recommended?
        public var readiness: IntentReadiness
        public var requestedWorker: RequestedWorker?
        public var fallback: Fallback?
        public var lifecycle: LifecycleBundle?
        public var nextActions: [NextAction]
        public init(
            schemaVersion: Int = 1,
            intent: String,
            recommended: Recommended? = nil,
            readiness: IntentReadiness,
            requestedWorker: RequestedWorker? = nil,
            fallback: Fallback? = nil,
            lifecycle: LifecycleBundle? = nil,
            nextActions: [NextAction]
        ) {
            self.schemaVersion = schemaVersion
            self.intent = intent
            self.recommended = recommended
            self.readiness = readiness
            self.requestedWorker = requestedWorker
            self.fallback = fallback
            self.lifecycle = lifecycle
            self.nextActions = nextActions
        }
    }

    // MARK: - Entry

    public static func route(
        intent raw: String,
        teams: [TeamPreset] = BuiltInTeams.all,
        readyTeams: [ReadyTeam] = [],
        readyModels: [Model] = [],
        modelCatalog: [ModelDefinition] = ModelCatalog.builtIns,
        canStartTeamRun: Bool = true,
        machineBlockedReason: String? = nil
    ) -> Payload {
        let intent = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intent.isEmpty else {
            return noMatch(
                intent: intent,
                code: "INTENT_NO_MATCH",
                why: "Empty intent — pass a short phrase of what you want done.",
                next: [
                    NextAction(command: "alln team hello --json",
                               reason: "See ready teams without an intent.",
                               code: "INTENT_NO_MATCH"),
                    NextAction(command: "alln team show --json",
                               reason: "Browse the team catalog by id.",
                               code: "INTENT_NO_MATCH")
                ]
            )
        }

        // Named-worker resolution runs first — an unresolvable name fails the
        // whole route (Decision 8), and a resolved name constrains chat/ask.
        let named = resolveNamedWorker(
            intent: intent, catalog: modelCatalog, readyModels: readyModels
        )
        if case .failure(let fail) = named {
            return workerNameFailure(intent: intent, fail: fail)
        }
        let requestedWorker: RequestedWorker?
        let pinnedModel: ModelDefinition?
        if case .success(let resolved, let echo) = named {
            requestedWorker = echo
            pinnedModel = resolved
        } else {
            requestedWorker = nil
            pinnedModel = nil
        }

        let wantsReadOnly = detectsReadOnlyAsk(intent)
        let primitive = detectPrimitive(intent: intent, namedWorker: pinnedModel != nil)

        // Named + read-only / ask → chat route (Decisions 8–9), not a judgment team.
        if let pinned = pinnedModel, wantsReadOnly || primitive == .chat || detectsAsk(intent) {
            return chatRoute(
                intent: intent,
                pinned: pinned,
                requestedWorker: requestedWorker,
                wantsReadOnly: wantsReadOnly,
                readyModels: readyModels,
                catalog: modelCatalog
            )
        }

        if let primitive, primitive != .chat {
            return primitiveRoute(
                intent: intent,
                primitive: primitive,
                requestedWorker: requestedWorker,
                readyModels: readyModels
            )
        }

        // Pure "ask a model" without a name → Auto / chat default.
        if detectsAsk(intent), pinnedModel == nil, !hasStrongTeamSignals(intent) {
            return chatRoute(
                intent: intent,
                pinned: nil,
                requestedWorker: nil,
                wantsReadOnly: wantsReadOnly,
                readyModels: readyModels,
                catalog: modelCatalog
            )
        }

        return teamRoute(
            intent: intent,
            teams: teams,
            readyTeams: readyTeams,
            readyModels: readyModels,
            requestedWorker: requestedWorker,
            pinnedModel: pinnedModel,
            canStartTeamRun: canStartTeamRun,
            machineBlockedReason: machineBlockedReason
        )
    }

    public static func jsonString(
        intent: String,
        verdict: AgentReadiness.Verdict,
        readyModels: [Model],
        teams: [TeamPreset] = BuiltInTeams.all
    ) -> String {
        let payload = route(
            intent: intent,
            teams: teams,
            readyTeams: verdict.readyTeams,
            readyModels: readyModels,
            canStartTeamRun: verdict.canStartTeamRun,
            machineBlockedReason: verdict.blockedReason
        )
        let data = (try? CoreJSON.encode(payload)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Team matching

    private struct ScoredTeam {
        var team: TeamPreset
        var score: Int
        var matchedTags: [String]
    }

    private static func teamRoute(
        intent: String,
        teams: [TeamPreset],
        readyTeams: [ReadyTeam],
        readyModels: [Model],
        requestedWorker: RequestedWorker?,
        pinnedModel: ModelDefinition?,
        canStartTeamRun: Bool,
        machineBlockedReason: String?
    ) -> Payload {
        let tokens = tokenize(intent)
        let depthHint = depthHint(from: intent)
        let candidates = teams.filter { team in
            guard !team.isLabTeam else { return false }
            switch depthTier(of: team.id) {
            case .min: return depthHint == .min
            case .max: return depthHint == .max
            case .default, .single: return depthHint != .min && depthHint != .max
                    || depthHint == .default || depthHint == .unspecified
            }
        }

        var scored = candidates.map { score(team: $0, intent: intent, tokens: tokens) }
        applyOverlapBoosts(intent: intent, tokens: tokens, scored: &scored)
        applyTaxonomyBoosts(intent: intent, tokens: tokens, scored: &scored)
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.team.id < b.team.id
        }

        guard let best = scored.first, best.score >= minimumScore else {
            return noMatch(
                intent: intent,
                code: "INTENT_NO_MATCH",
                why: "No catalog family matched '\(intent)' strongly enough.",
                next: [
                    NextAction(command: "alln team show --json",
                               reason: "Browse teams and pick an id explicitly.",
                               code: "INTENT_NO_MATCH"),
                    NextAction(command: "alln team hello --for \"find the real cause of this crash\" --json",
                               reason: "Example: Bug Hunt.",
                               code: "INTENT_NO_MATCH"),
                    NextAction(command: "alln doctor --json",
                               reason: "Confirm the bench is healthy before retrying.",
                               code: "INTENT_NO_MATCH")
                ],
                requestedWorker: requestedWorker
            )
        }

        // Near-tie among different families → still pick the sorted winner, but
        // surface runners-up in nextActions (no silent ambiguity).
        let nearTies = scored.filter {
            $0.team.id != best.team.id
                && $0.score >= best.score - nearTieDelta
                && $0.score >= minimumScore
                && familyBase(of: $0.team.id) != familyBase(of: best.team.id)
        }

        let team = best.team
        let readyIds = Set(readyTeams.map(\.team))
        let alternates = depthAlternates(for: team.id, in: teams)
        let why = matchWhy(intent: intent, team: team, matchedTags: best.matchedTags)

        if !canStartTeamRun {
            return Payload(
                intent: intent,
                recommended: Recommended(
                    kind: "team", teamId: team.id, why: why,
                    command: nil, depthAlternates: alternates
                ),
                readiness: IntentReadiness(
                    ready: false,
                    blockedReason: machineBlockedReason ?? "Machine not ready to start team runs.",
                    code: "DOCTOR_CHECK_FAILED"
                ),
                requestedWorker: requestedWorker,
                nextActions: [
                    NextAction(command: "alln doctor --json",
                               reason: "Fix the blocking doctor check, then re-run hello --for.",
                               code: "DOCTOR_CHECK_FAILED"),
                    NextAction(
                        command: teamStartDisplay(teamId: team.id),
                        reason: "Once ready, start \(team.displayName).",
                        code: nil)
                ]
            )
        }

        let teamReady = readyIds.contains(team.id)
        var fallback: Fallback?
        var command: RunnableCommand? = teamReady
            ? teamStartCommand(teamId: team.id, intent: intent)
            : nil

        if !teamReady {
            // Loud fallback to a ready Min/Max alternate in the same family —
            // never a silent swap to an unrelated family.
            if let altId = alternates.first(where: { readyIds.contains($0) }),
               let alt = teams.first(where: { $0.id == altId }) {
                fallback = Fallback(
                    kind: "team",
                    teamId: alt.id,
                    why: "Preferred seats for \(team.displayName) are unavailable; \(alt.displayName) is ready.",
                    command: teamStartCommand(teamId: alt.id, intent: intent)
                )
            }
        }

        // Named worker pins a seat: if the named model is not ready, strip the
        // runnable command (Decision 8 — no silent alternate-as-recommended).
        if let pinned = pinnedModel {
            let readyModelIds = Set(readyModels.map(\.id))
            // readyModels may be empty in unit tests that only care about team id;
            // only enforce when the caller supplied a ready bench.
            if !readyModels.isEmpty && !readyModelIds.contains(pinned.id) {
                command = nil
                return Payload(
                    intent: intent,
                    recommended: Recommended(
                        kind: "team", teamId: team.id, why: why,
                        command: nil, depthAlternates: alternates,
                        modelId: pinned.id, driverId: pinned.driverId
                    ),
                    readiness: IntentReadiness(
                        ready: false,
                        blockedReason: "Requested worker \(pinned.id) is not ready.",
                        code: "WORKER_NOT_AVAILABLE"
                    ),
                    requestedWorker: requestedWorker,
                    fallback: nil,
                    nextActions: [
                        NextAction(command: "alln models --json",
                                   reason: "Confirm \(pinned.displayName) is on-Bench and ready.",
                                   code: "WORKER_NOT_AVAILABLE"),
                        NextAction(command: "alln doctor --json",
                                   reason: "Auth/install the worker's driver if needed.",
                                   code: "WORKER_NOT_AVAILABLE")
                    ]
                )
            }
        }

        var next: [NextAction] = []
        if let command {
            next.append(NextAction(
                command: command.display,
                reason: "Start \(team.displayName) with your intent.",
                code: nil))
        } else if let fallback, let fbCmd = fallback.command {
            next.append(NextAction(
                command: fbCmd.display,
                reason: fallback.why,
                code: "MODEL_UNAVAILABLE"))
        } else {
            next.append(NextAction(
                command: "alln team preflight --team \(team.id) --json",
                reason: "Validate seats for \(team.displayName) before retrying.",
                code: "MODEL_UNAVAILABLE"))
            next.append(NextAction(
                command: "alln doctor --json",
                reason: "Repair the bench if preflight stays blocked.",
                code: "MODEL_UNAVAILABLE"))
        }
        for tie in nearTies.prefix(3) {
            next.append(NextAction(
                command: teamStartDisplay(teamId: tie.team.id),
                reason: "Near match: \(tie.team.displayName) (score \(tie.score)).",
                code: nil))
        }
        for alt in alternates {
            next.append(NextAction(
                command: teamStartDisplay(teamId: alt),
                reason: "Depth alternate in the same family.",
                code: nil))
        }

        let readiness: IntentReadiness
        if teamReady {
            readiness = IntentReadiness(ready: true)
        } else if fallback != nil {
            readiness = IntentReadiness(
                ready: false,
                blockedReason: "Preferred team \(team.id) is not ready; see fallback.",
                code: "MODEL_UNAVAILABLE"
            )
        } else {
            readiness = IntentReadiness(
                ready: false,
                blockedReason: "Team \(team.id) does not resolve on the current bench.",
                code: "MODEL_UNAVAILABLE"
            )
        }

        return attachLifecycle(Payload(
            intent: intent,
            recommended: Recommended(
                kind: "team", teamId: team.id, why: why,
                command: command, depthAlternates: alternates,
                modelId: pinnedModel?.id, driverId: pinnedModel?.driverId
            ),
            readiness: readiness,
            requestedWorker: requestedWorker,
            fallback: fallback,
            nextActions: next
        ))
    }

    private static let minimumScore = 8
    private static let nearTieDelta = 4

    private static func score(team: TeamPreset, intent: String, tokens: Set<String>) -> ScoredTeam {
        var score = 0
        var matchedTags: [String] = []
        let intentLower = intent.lowercased()

        for tag in team.typeTags {
            let tagTokens = tokenize(tag.replacingOccurrences(of: "-", with: " "))
            if tagTokens.count > 1 {
                if tagTokens.isSubset(of: tokens) || intentLower.contains(tag.replacingOccurrences(of: "-", with: " ")) {
                    score += 15
                    matchedTags.append(tag)
                }
            } else if let t = tagTokens.first, tokens.contains(t) {
                score += 12
                matchedTags.append(tag)
            }
        }

        for word in tokenize(team.displayName) where tokens.contains(word) {
            score += 6
        }

        let descTokens = tokenize(team.description)
        let descHits = descTokens.intersection(tokens).count
        score += min(descHits * 2, 10)

        for starter in team.starterPrompts {
            let starterTokens = tokenize(starter)
            let overlap = starterTokens.intersection(tokens).count
            if overlap >= 3 {
                score += min(overlap * 3, 18)
            }
            // Phrase-level: starter without placeholders overlapping the intent.
            let stripped = starter
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .lowercased()
            let significant = stripped.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 2 && !stopwords.contains($0) }
            if significant.count >= 3 {
                let present = significant.filter { intentLower.contains($0) }.count
                if present >= significant.count - 1 {
                    score += 20
                }
            }
        }

        // Lane soft boost when the intent names a craft.
        let laneHints: [WorkLane: Set<String>] = [
            .code: ["code", "bug", "crash", "spec", "build", "repo"],
            .design: ["design", "screen", "ui", "mockup", "layout"],
            .copy: ["copy", "landing", "headline", "messaging", "conversion"],
            .signal: ["signal", "article", "post", "news", "roadmap"]
        ]
        if let hints = laneHints[team.lane], !hints.isDisjoint(with: tokens) {
            score += 2
        }

        return ScoredTeam(team: team, score: score, matchedTags: matchedTags)
    }

    /// Overlap boosts — see file-level "Overlap precedence" docs.
    private static func applyOverlapBoosts(
        intent: String, tokens: Set<String>, scored: inout [ScoredTeam]
    ) {
        let uiSignals: Set<String> = ["ui", "gui", "visual", "layout", "clipping", "rendered", "screen"]
        let brokenSignals: Set<String> = ["broken", "breakage", "bug", "glitch", "wrong", "crash"]
        let designExclusive: Set<String> = ["design", "redesign", "mockup", "directions", "flow", "interface"]
        let usabilityExclusive: Set<String> = ["confusing", "friction", "usability", "ux", "slow"]

        let hasUI = !tokens.isDisjoint(with: uiSignals)
        let hasBroken = !tokens.isDisjoint(with: brokenSignals)
            || intent.lowercased().contains("broken")
        let hasDesignExclusive = !tokens.isDisjoint(with: designExclusive)
        let hasUsabilityExclusive = !tokens.isDisjoint(with: usabilityExclusive)

        if hasUI && hasBroken && !hasDesignExclusive && !hasUsabilityExclusive {
            for i in scored.indices {
                switch scored[i].team.id {
                case "code_gui_bug_hunt":
                    scored[i].score += 40
                case "design_design", "design_design_min", "design_design_max":
                    scored[i].score -= 20
                case "design_usability_review":
                    scored[i].score -= 20
                case "code_bug_hunt", "code_bug_hunt_min", "code_bug_hunt_max":
                    scored[i].score -= 15
                default: break
                }
            }
        }
    }

    /// Explicit taxonomy phrase boosts so the 80% intent table wins even when
    /// typeTags are sparse (e.g. Growth only tags `growth`, but users say
    /// "builders love this").
    private static func applyTaxonomyBoosts(
        intent: String, tokens: Set<String>, scored: inout [ScoredTeam]
    ) {
        let lower = intent.lowercased()
        func boost(_ id: String, by amount: Int) {
            for i in scored.indices where scored[i].team.id == id {
                scored[i].score += amount
            }
        }
        // Growth: builders/users + love/spread/wedge
        let growthPeople: Set<String> = ["builders", "users", "influencers"]
        let growthLove: Set<String> = ["love", "spread", "wedge", "viral", "growth"]
        if !tokens.isDisjoint(with: growthPeople) && !tokens.isDisjoint(with: growthLove) {
            boost("code_growth", by: 30)
        } else if tokens.contains("growth") || lower.contains("love this") {
            boost("code_growth", by: 20)
        }
        // Spec Review
        if tokens.contains("harden") || tokens.contains("spec")
            || lower.contains("before i build") || lower.contains("challenge my plan") {
            boost("code_spec_review", by: 25)
        }
        // Bug Hunt
        if (tokens.contains("cause") || tokens.contains("crash") || tokens.contains("bug"))
            && !tokens.contains("ui") && !tokens.contains("gui") {
            boost("code_bug_hunt", by: 20)
        }
        // Copy Landing
        if tokens.contains("landing") || (tokens.contains("rewrite") && tokens.contains("page")) {
            boost("copy_landing", by: 25)
        }
        // Copy Core
        if tokens.contains("copy") || tokens.contains("persuasive") || tokens.contains("headline") {
            boost("copy_core", by: 15)
        }
    }

    private static func matchWhy(intent: String, team: TeamPreset, matchedTags: [String]) -> String {
        if matchedTags.isEmpty {
            return "Intent '\(intent)' matched \(team.displayName) via description/starters."
        }
        return "Intent '\(intent)' matched typeTags [\(matchedTags.joined(separator: ", "))] → \(team.displayName)."
    }

    // MARK: - Depth / family helpers

    private enum DepthTier { case min, max, `default`, single }
    private enum DepthHint { case min, max, `default`, unspecified }

    private static func depthTier(of id: String) -> DepthTier {
        if id.hasSuffix("_min") { return .min }
        if id.hasSuffix("_max") { return .max }
        let base = familyBase(of: id)
        let hasMin = BuiltInTeams.team("\(base)_min") != nil
        let hasMax = BuiltInTeams.team("\(base)_max") != nil
        if hasMin || hasMax { return .default }
        return .single
    }

    private static func familyBase(of id: String) -> String {
        if id.hasSuffix("_min") { return String(id.dropLast(4)) }
        if id.hasSuffix("_max") { return String(id.dropLast(4)) }
        return id
    }

    private static func depthAlternates(for id: String, in teams: [TeamPreset]) -> [String] {
        let base = familyBase(of: id)
        var alts: [String] = []
        if teams.contains(where: { $0.id == "\(base)_min" }) { alts.append("\(base)_min") }
        if teams.contains(where: { $0.id == "\(base)_max" }) { alts.append("\(base)_max") }
        // When the match itself is Min/Max, also offer the Default.
        if id != base, teams.contains(where: { $0.id == base }) {
            alts.insert(base, at: 0)
        }
        return alts.filter { $0 != id }
    }

    private static func depthHint(from intent: String) -> DepthHint {
        let t = tokenize(intent)
        if t.contains("min") || t.contains("quick") || t.contains("fastest") || t.contains("lite") {
            return .min
        }
        if t.contains("max") || t.contains("deep") || t.contains("escalat") || t.contains("nasty")
            || intent.lowercased().contains("full-depth") || intent.lowercased().contains("full depth") {
            return .max
        }
        return .unspecified
    }

    // MARK: - Primitives (IR-S02)

    private enum PrimitiveKind { case pilot, relay, chat }

    private static func detectPrimitive(intent: String, namedWorker: Bool) -> PrimitiveKind? {
        let lower = intent.lowercased()
        let tokens = tokenize(intent)
        if tokens.contains("relay")
            || lower.contains("overnight")
            || lower.contains("without me")
            || (lower.contains("keep building") && (lower.contains("night") || lower.contains("unattended") || lower.contains("without")))
            || lower.contains("unattended") {
            return .relay
        }
        if tokens.contains("pilot")
            || lower.contains("while i supervise")
            || lower.contains("while i watch")
            || (lower.contains("another model") && (lower.contains("build") || lower.contains("supervise"))) {
            return .pilot
        }
        if namedWorker { return nil }
        return nil
    }

    private static func detectsAsk(_ intent: String) -> Bool {
        let lower = intent.lowercased()
        let tokens = tokenize(intent)
        if tokens.contains("ask") || tokens.contains("question") { return true }
        if lower.hasPrefix("just ask") || lower.contains("what do you think") { return true }
        if lower.contains("for feedback") || lower.contains("for its take")
            || lower.contains("for a take") || lower.contains("for read-only") {
            return true
        }
        return false
    }

    private static func detectsReadOnlyAsk(_ intent: String) -> Bool {
        let lower = intent.lowercased()
        if lower.contains("read-only") || lower.contains("read only") || lower.contains("readonly") {
            return true
        }
        if lower.contains("don't change") || lower.contains("do not change")
            || lower.contains("don't modify") || lower.contains("do not modify")
            || lower.contains("without changing") || lower.contains("no edits") {
            return true
        }
        if lower.contains("feedback") && (lower.contains("ask") || lower.contains("for")) {
            return true
        }
        return false
    }

    private static func hasStrongTeamSignals(_ intent: String) -> Bool {
        let t = tokenize(intent)
        let strong: Set<String> = [
            "bug", "crash", "spec", "harden", "growth", "design", "landing",
            "copy", "security", "proof", "plan", "signal", "usability", "polish"
        ]
        return !t.isDisjoint(with: strong)
    }

    private static func primitiveRoute(
        intent: String,
        primitive: PrimitiveKind,
        requestedWorker: RequestedWorker?,
        readyModels: [Model]
    ) -> Payload {
        switch primitive {
        case .relay:
            let argv = [
                "alln", "pair", "relay",
                "--doc", "<path>",
                "--project", "<id>",
                "--pm-worker", "<pm-model-id>",
                "--dev-worker", "<dev-model-id>",
                "--json"
            ]
            let cmd = RunnableCommand(
                argv: argv,
                display: argv.joined(separator: " ")
            )
            return attachLifecycle(Payload(
                intent: intent,
                recommended: Recommended(
                    kind: "relay",
                    why: "Intent matched the overnight unattended build loop → pair relay.",
                    command: cmd,
                    safetyPosture: "mutating"
                ),
                readiness: IntentReadiness(ready: true),
                requestedWorker: requestedWorker,
                nextActions: [
                    NextAction(command: cmd.display,
                               reason: "Fill --doc / --project / seat ids, then start the relay."),
                    NextAction(command: "alln models --json",
                               reason: "Pick ready pm-worker and dev-worker ids.")
                ]
            ))
        case .pilot:
            let argv = [
                "alln", "pair", "pilot", "start",
                "--doc", "<path>",
                "--project", "<id>",
                "--json"
            ]
            let cmd = RunnableCommand(argv: argv, display: argv.joined(separator: " "))
            return attachLifecycle(Payload(
                intent: intent,
                recommended: Recommended(
                    kind: "pilot",
                    why: "Intent matched supervised build-while-you-PM → pair pilot.",
                    command: cmd,
                    safetyPosture: "mutating"
                ),
                readiness: IntentReadiness(ready: true),
                requestedWorker: requestedWorker,
                nextActions: [
                    NextAction(command: cmd.display,
                               reason: "Fill --doc / --project, then start Pilot.")
                ]
            ))
        case .chat:
            return chatRoute(
                intent: intent, pinned: nil, requestedWorker: requestedWorker,
                wantsReadOnly: detectsReadOnlyAsk(intent),
                readyModels: readyModels, catalog: ModelCatalog.builtIns
            )
        }
    }

    private static func chatRoute(
        intent: String,
        pinned: ModelDefinition?,
        requestedWorker: RequestedWorker?,
        wantsReadOnly: Bool,
        readyModels: [Model],
        catalog: [ModelDefinition]
    ) -> Payload {
        let modelId = pinned?.id
        let driverId = pinned?.driverId
        let enforcesRO = driverEnforcesReadOnly(driverId)
        let posture: String
        let whySuffix: String
        if wantsReadOnly {
            if enforcesRO {
                posture = "readOnly"
                whySuffix = " Driver \(driverId ?? "?") can mechanically enforce read-only."
            } else if driverId != nil {
                posture = "advisoryReadOnly"
                whySuffix = " ADVISORY ONLY: driver \(driverId!) cannot mechanically enforce read-only (no sandbox flag); include a no-mutation instruction in the prompt, or switch to a Codex-backed seat."
            } else {
                posture = "advisoryReadOnly"
                whySuffix = " ADVISORY ONLY: no dedicated read-only ask verb yet; the emitted run route is mutating unless the worker driver sandboxes."
            }
        } else {
            posture = "mutating"
            whySuffix = ""
        }

        var why: String
        if let pinned {
            why = "Intent asked \(pinned.displayName) (\(pinned.id))."
        } else {
            why = "Intent is a quick ask → Auto / chat default."
        }
        why += whySuffix

        // Posture filter refusal: named a driver that cannot honor read-only when
        // a safer same-model driver exists — already handled in resolveNamedWorker.
        // If somehow pinned to a non-RO driver with wantsReadOnly and no alternate
        // was chosen, still emit advisory (loud in why).

        let readyIds = Set(readyModels.map(\.id))
        let seatReady = modelId.map { readyModels.isEmpty || readyIds.contains($0) } ?? true

        let command: RunnableCommand?
        if seatReady {
            command = runCommand(intent: intent, workerId: modelId, wantsReadOnly: wantsReadOnly)
        } else {
            command = nil
        }

        var next: [NextAction] = []
        if let command {
            next.append(NextAction(command: command.display,
                                   reason: "Run the pinned ask (fill --project)."))
        } else if let modelId {
            next.append(NextAction(command: "alln models --json",
                                   reason: "Bring \(modelId) online, or re-choose the worker.",
                                   code: "WORKER_NOT_AVAILABLE"))
            next.append(NextAction(command: "alln doctor --json",
                                   reason: "Auth/install the worker's driver.",
                                   code: "WORKER_NOT_AVAILABLE"))
        }

        if let alt = requestedWorker?.alternates.first {
            next.append(NextAction(
                command: runCommand(intent: intent, workerId: alt, wantsReadOnly: wantsReadOnly).display,
                reason: "Loud alternate driver entry \(alt) — only use after explicit selection."))
        }

        // Suggest Codex alternate when advisory RO on Cursor.
        if wantsReadOnly, !enforcesRO, let pinned,
           let codexAlt = catalog.first(where: {
               $0.driverId == "codex" && sameUnderlyingModel(pinned, $0)
           }) {
            if !(requestedWorker?.alternates.contains(codexAlt.id) ?? false)
                && pinned.id != codexAlt.id {
                next.append(NextAction(
                    command: runCommand(intent: intent, workerId: codexAlt.id, wantsReadOnly: true).display,
                    reason: "Prefer \(codexAlt.id) for mechanical read-only."))
            }
        }

        if next.isEmpty {
            next.append(NextAction(command: "alln team hello --json",
                                   reason: "Inspect readiness without an intent."))
        }

        return attachLifecycle(Payload(
            intent: intent,
            recommended: Recommended(
                kind: "chat",
                teamId: "default_chat",
                why: why,
                command: command,
                modelId: modelId,
                driverId: driverId,
                safetyPosture: posture
            ),
            readiness: IntentReadiness(
                ready: seatReady,
                blockedReason: seatReady ? nil : "Requested worker \(modelId ?? "") is not ready.",
                code: seatReady ? nil : "WORKER_NOT_AVAILABLE"
            ),
            requestedWorker: requestedWorker,
            nextActions: next
        ))
    }

    // MARK: - Named worker resolution (Decision 8)

    private enum NamedWorkerResult {
        case none
        case success(resolved: ModelDefinition, echo: RequestedWorker)
        case failure(WorkerNameFail)
    }

    private struct WorkerNameFail {
        var code: String
        var requestedName: String
        var why: String
        var nearest: [String]
    }

    private static func resolveNamedWorker(
        intent: String,
        catalog: [ModelDefinition],
        readyModels: [Model]
    ) -> NamedWorkerResult {
        guard let extracted = extractWorkerName(intent: intent, catalog: catalog) else {
            return .none
        }
        let name = extracted
        let lower = name.lowercased()
        let wantsRO = detectsReadOnlyAsk(intent)

        // Match against id / displayName / modelLabel (substring + exact).
        var matches = catalog.filter { def in
            def.id.lowercased() == lower
                || def.displayName.lowercased() == lower
                || def.modelLabel.lowercased() == lower
                || def.displayName.lowercased().contains(lower)
                || def.id.lowercased().contains(lower.replacingOccurrences(of: " ", with: "_"))
                || normalizeDisplayName(def.displayName) == normalizeDisplayName(name)
                || tokenize(def.displayName).isSuperset(of: tokenize(name))
                    && tokenize(name).count >= 1
        }

        // Bare short aliases.
        if matches.isEmpty {
            matches = catalog.filter { aliasMatch(lower, def: $0) }
        }

        // Prefer matches where the extracted name covers the significant display tokens.
        if matches.count > 1 {
            let nameTokens = tokenize(name)
            let tight = matches.filter { tokenize(normalizeDisplayName($0.displayName)).isSuperset(of: nameTokens) || nameTokens.isSuperset(of: tokenize(normalizeDisplayName($0.displayName))) }
            if !tight.isEmpty { matches = tight }
        }

        guard !matches.isEmpty else {
            let nearest = nearestNames(to: name, in: catalog, limit: 5)
            return .failure(WorkerNameFail(
                code: "WORKER_NAME_UNKNOWN",
                requestedName: name,
                why: "No catalog model matches '\(name)'.",
                nearest: nearest
            ))
        }

        // Posture filter first (Decision 8).
        let postureFiltered: [ModelDefinition]
        if wantsRO {
            let enforcing = matches.filter { driverEnforcesReadOnly($0.driverId) }
            if enforcing.isEmpty {
                // Named refusal — every match is unsafe for this posture.
                return .failure(WorkerNameFail(
                    code: "WORKER_NAME_POSTURE_UNSAFE",
                    requestedName: name,
                    why: "Matched \(matches.map(\.id).joined(separator: ", ")) but none can mechanically enforce read-only for this ask.",
                    nearest: matches.map(\.id)
                ))
            }
            postureFiltered = enforcing
        } else {
            postureFiltered = matches
        }

        let readyIds = Set(readyModels.map(\.id))
        let ranked = postureFiltered.sorted { a, b in
            let va = vendorDriverRank(a)
            let vb = vendorDriverRank(b)
            if va != vb { return va < vb }
            if !readyModels.isEmpty {
                let ra = readyIds.contains(a.id)
                let rb = readyIds.contains(b.id)
                if ra != rb { return ra && !rb }
            }
            return a.id < b.id
        }

        guard let winner = ranked.first else {
            return .failure(WorkerNameFail(
                code: "WORKER_NAME_UNKNOWN",
                requestedName: name,
                why: "No catalog model matches '\(name)' after filters.",
                nearest: nearestNames(to: name, in: catalog, limit: 5)
            ))
        }

        // Loud alternates: other same-model / other-driver matches (including
        // posture-excluded ones, so Cursor Sol still appears when Codex wins).
        let alternates = matches
            .map(\.id)
            .filter { $0 != winner.id }
            .sorted()

        var why = "Resolved '\(name)' → \(winner.id) (\(winner.displayName))."
        if winner.driverId == "codex" {
            why += " Native vendor CLI (Codex) preferred"
            if matches.contains(where: { $0.driverId == "cursor_agent" }) {
                why += "; also available via Cursor."
            } else {
                why += "."
            }
        } else if wantsRO {
            why += " Posture-filtered to a read-only-capable driver."
        }

        // Ambiguous: two+ winners tied on vendor rank + readiness with different
        // underlying models (not just driver mirrors).
        let topRank = vendorDriverRank(winner)
        let tiedDistinct = ranked.filter {
            vendorDriverRank($0) == topRank
                && !sameUnderlyingModel(winner, $0)
                && $0.id != winner.id
        }
        if tiedDistinct.count >= 1 && tokenize(name).count <= 1 {
            // Short alias that hits unrelated models → ambiguous.
            let candidates = ([winner] + tiedDistinct).map(\.id).sorted()
            return .failure(WorkerNameFail(
                code: "WORKER_NAME_AMBIGUOUS",
                requestedName: name,
                why: "Name '\(name)' matches multiple unrelated models: \(candidates.joined(separator: ", ")).",
                nearest: candidates
            ))
        }

        return .success(
            resolved: winner,
            echo: RequestedWorker(
                requestedName: name,
                resolvedModelId: winner.id,
                why: why,
                alternates: alternates
            )
        )
    }

    private static func extractWorkerName(intent: String, catalog: [ModelDefinition]) -> String? {
        let lower = intent.lowercased()

        // Longest catalog display-name / id hit inside the intent.
        let names = catalog.flatMap { def -> [(String, String)] in
            [
                (normalizeDisplayName(def.displayName).lowercased(), normalizeDisplayName(def.displayName)),
                (def.displayName.lowercased(), def.displayName),
                (def.id.lowercased(), def.id)
            ]
        }
        .sorted { $0.0.count > $1.0.count }

        for (needle, original) in names where needle.count >= 3 {
            if lower.contains(needle) { return original }
        }

        // "ask <name> for/to/about"
        if let match = intent.range(
            of: #"(?i)\bask\s+(.+?)\s+(?:for|to|about|regarding)\b"#,
            options: .regularExpression
        ) {
            let full = String(intent[match])
            if let inner = full.range(
                of: #"(?i)\bask\s+(.+?)\s+(?:for|to|about|regarding)\b"#,
                options: .regularExpression
            ) {
                // Extract capture via NSRegularExpression for group 1.
                if let name = regexGroup1(
                    pattern: #"(?i)\bask\s+(.+?)\s+(?:for|to|about|regarding)\b"#,
                    in: intent
                ) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                _ = inner
            }
        }

        // Bare well-known aliases when preceded by ask/using/with/via.
        let aliases = ["sol", "grok", "opus", "fable", "sonnet", "composer", "chatgpt", "gemini", "kimi"]
        for alias in aliases {
            if lower.range(of: #"\b(?:ask|using|with|via|pin)\s+"# + alias + #"\b"#,
                           options: .regularExpression) != nil {
                return alias
            }
            // "ask ChatGPT 5.6 Sol" already handled by display-name scan.
        }

        // Nonsense probe: "ask <UnknownThing> for" where UnknownThing looks like a name.
        if let g = regexGroup1(
            pattern: #"(?i)\bask\s+([A-Za-z0-9][A-Za-z0-9 ._-]{1,40}?)\s+(?:for|to|about)\b"#,
            in: intent
        ) {
            let trimmed = g.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only treat as a worker name if it isn't a generic English phrase.
            let generic: Set<String> = ["me", "us", "the team", "another model", "a model", "the model"]
            if !generic.contains(trimmed.lowercased()) {
                return trimmed
            }
        }

        return nil
    }

    private static func aliasMatch(_ alias: String, def: ModelDefinition) -> Bool {
        let id = def.id.lowercased()
        let name = normalizeDisplayName(def.displayName).lowercased()
        let label = def.modelLabel.lowercased()
        if alias == "sol" {
            return id.contains("sol") || name.contains("sol") || label.contains("sol")
        }
        if alias == "chatgpt" {
            return id.contains("chatgpt") || name.contains("chatgpt")
        }
        return id.contains(alias) || name.contains(alias) || label.contains(alias)
    }

    private static func normalizeDisplayName(_ name: String) -> String {
        // Strip driver parentheticals: "ChatGPT 5.6 Sol (Codex)" → "ChatGPT 5.6 Sol"
        if let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"),
           open < close {
            return name[..<open].trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    private static func sameUnderlyingModel(_ a: ModelDefinition, _ b: ModelDefinition) -> Bool {
        normalizeDisplayName(a.displayName).lowercased()
            == normalizeDisplayName(b.displayName).lowercased()
    }

    /// Lower is better. Vendor CLIs beat resellers for the same underlying model.
    private static func vendorDriverRank(_ def: ModelDefinition) -> Int {
        switch def.driverId {
        case "codex" where def.id.contains("chatgpt") || def.modelLabel.contains("gpt"):
            return 0
        case "claude_code" where def.id.contains("opus") || def.id.contains("sonnet")
            || def.id.contains("fable"):
            return 0
        case "grok" where def.id.contains("grok") || def.id.contains("composer"):
            return 0
        case "codex", "claude_code", "grok", "kimi":
            return 1
        case "cursor_agent":
            return 2
        case "antigravity":
            return 3
        default:
            return 4
        }
    }

    /// Drivers that can mechanically sandbox / refuse writes for a read-only ask.
    private static func driverEnforcesReadOnly(_ driverId: String?) -> Bool {
        switch driverId {
        case "codex": return true
        default: return false
        }
    }

    private static func nearestNames(to name: String, in catalog: [ModelDefinition], limit: Int) -> [String] {
        let needle = tokenize(name)
        return catalog
            .map { def -> (String, Int) in
                let overlap = tokenize(def.displayName).union(tokenize(def.id)).intersection(needle).count
                return (def.id, overlap)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0 < b.0
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func workerNameFailure(intent: String, fail: WorkerNameFail) -> Payload {
        var next: [NextAction] = [
            NextAction(command: "alln models --json",
                       reason: "List catalog ids and pick an explicit --worker.",
                       code: fail.code)
        ]
        for id in fail.nearest.prefix(5) {
            next.append(NextAction(
                command: "alln team hello --for \"ask \(id) for a read-only take\" --json",
                reason: "Nearest match: \(id).",
                code: fail.code))
        }
        return Payload(
            intent: intent,
            recommended: nil,
            readiness: IntentReadiness(ready: false, blockedReason: fail.why, code: fail.code),
            requestedWorker: RequestedWorker(
                requestedName: fail.requestedName,
                resolvedModelId: nil,
                why: fail.why,
                alternates: fail.nearest
            ),
            nextActions: next
        )
    }

    // MARK: - Command builders

    private static func teamStartCommand(teamId: String, intent: String) -> RunnableCommand {
        // Frozen grammar: flags before the prompt argv element.
        let argv = ["alln", "team", "start", "--team", teamId, "--json", intent]
        let display = "alln team start --team \(teamId) --json <prompt>"
        return RunnableCommand(argv: argv, display: display)
    }

    private static func teamStartDisplay(teamId: String) -> String {
        "alln team start --team \(teamId) --json <prompt>"
    }

    private static func runCommand(intent: String, workerId: String?, wantsReadOnly: Bool) -> RunnableCommand {
        var argv = ["alln", "run", "--project", "<id|path>"]
        if let workerId {
            argv += ["--worker", workerId]
        }
        // Decision 10: mutating routes must not teach final-only `--json` as progress.
        // Read-only / advisory asks keep `--json` (final envelope); mutating uses `--stream`.
        let progressFlag = wantsReadOnly ? "--json" : "--stream"
        argv += [progressFlag, intent]
        var display = "alln run --project <id|path>"
        if let workerId {
            display += " --worker \(workerId)"
        }
        display += " \(progressFlag) <prompt>"
        if wantsReadOnly {
            display += "  # posture: see recommended.safetyPosture"
        }
        return RunnableCommand(argv: argv, display: display)
    }

    /// Attach Decision 10 lifecycle when `recommended.command` is runnable.
    /// No-match / worker-name failures / blocked seats without a command stay bare.
    private static func attachLifecycle(_ payload: Payload) -> Payload {
        guard payload.recommended?.command != nil,
              let kind = payload.recommended?.kind,
              let bundle = lifecycleBundle(for: kind) else {
            return payload
        }
        var out = payload
        out.lifecycle = bundle
        return out
    }

    /// Registry-faithful monitor/result/cancel argv. Canonical id placeholder is
    /// always `<run-id>` (team positional; relay/pilot via `--relay <run-id>`;
    /// kill positional id). Chat omits monitor/result — `--stream` or final
    /// `--json` is the launch transport; cancel via `kill`.
    private static func lifecycleBundle(for kind: String) -> LifecycleBundle? {
        switch kind {
        case "team":
            return LifecycleBundle(
                monitor: registryArgv(["alln", "team", "status", "<run-id>", "--json"]),
                result: registryArgv(["alln", "team", "result", "<run-id>", "--json"]),
                cancel: registryArgv(["alln", "team", "cancel", "<run-id>", "--json"])
            )
        case "relay":
            // `pair relay-status` is both progress and terminal truth owner.
            let status = registryArgv([
                "alln", "pair", "relay-status", "--relay", "<run-id>", "--json"
            ])
            return LifecycleBundle(
                monitor: status,
                result: status,
                cancel: registryArgv(["alln", "kill", "<run-id>", "--json"])
            )
        case "pilot":
            let status = registryArgv([
                "alln", "pair", "pilot", "status", "--relay", "<run-id>", "--json"
            ])
            return LifecycleBundle(
                monitor: status,
                result: status,
                cancel: registryArgv(["alln", "kill", "<run-id>", "--json"])
            )
        case "chat":
            return LifecycleBundle(
                monitor: nil,
                result: nil,
                cancel: registryArgv(["alln", "kill", "<run-id>", "--json"])
            )
        default:
            return nil
        }
    }

    private static func registryArgv(_ argv: [String]) -> RunnableCommand {
        RunnableCommand(argv: argv, display: argv.joined(separator: " "))
    }

    private static func noMatch(
        intent: String, code: String, why: String, next: [NextAction],
        requestedWorker: RequestedWorker? = nil
    ) -> Payload {
        Payload(
            intent: intent,
            recommended: nil,
            readiness: IntentReadiness(ready: false, blockedReason: why, code: code),
            requestedWorker: requestedWorker,
            nextActions: next.isEmpty
                ? [NextAction(command: "alln team show --json", reason: why, code: code)]
                : next
        )
    }

    // MARK: - Tokenization

    private static let stopwords: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "to", "for", "of", "on",
        "in", "at", "by", "with", "from", "into", "my", "our", "we", "i", "me", "us",
        "do", "does", "did", "how", "what", "when", "where", "which", "who", "is",
        "are", "be", "been", "being", "and", "or", "but", "if", "then", "so", "it",
        "its", "as", "than", "too", "very", "just", "about", "before", "after",
        "have", "has", "had", "can", "could", "should", "would", "will", "get",
        "got", "make", "made", "want", "need", "please", "help", "me", "you", "your"
    ]

    private static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        var tokens: Set<String> = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else {
                if current.count > 1, !stopwords.contains(current) {
                    tokens.insert(current)
                }
                current = ""
            }
        }
        if current.count > 1, !stopwords.contains(current) {
            tokens.insert(current)
        }
        return tokens
    }

    private static func regexGroup1(pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
