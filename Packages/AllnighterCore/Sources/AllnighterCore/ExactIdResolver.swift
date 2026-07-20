import Foundation

/// MR-S04 — one honor-or-fail choke point for every explicit identifier selector
/// (`--worker`, `--team`, `--dev-worker`, panel `--team` / `--seat`, …).
///
/// Canonical ids only. Display names and fuzzy matches never authorize dispatch.
/// Unknown values return same-kind candidates + a paste-ready discovery command;
/// suggestions repair spelling only and never auto-select.
public enum ExactIdResolver {

    public enum Kind: String, Sendable, Codable, Equatable {
        case worker
        case team
    }

    /// Same-kind repair row (never auto-dispatched).
    public struct Candidate: Codable, Sendable, Equatable {
        public var id: String
        public var displayName: String
        public var driverId: String?
        public var state: String

        public init(id: String, displayName: String, driverId: String? = nil, state: String) {
            self.id = id
            self.displayName = displayName
            self.driverId = driverId
            self.state = state
        }
    }

    public struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        public var code: String
        public var kind: Kind
        public var flag: String
        public var provided: String
        public var message: String
        public var candidates: [Candidate]
        public var discoveryCommand: String

        public var suggestionIds: [String] { candidates.map(\.id) }

        public var description: String { message }

        public init(
            code: String,
            kind: Kind,
            flag: String,
            provided: String,
            message: String,
            candidates: [Candidate],
            discoveryCommand: String
        ) {
            self.code = code
            self.kind = kind
            self.flag = flag
            self.provided = provided
            self.message = message
            self.candidates = candidates
            self.discoveryCommand = discoveryCommand
        }
    }

    // MARK: - Workers (`--worker`, `--dev-worker`, …)

    /// Honor an exact model id, or fail closed. Never matches `displayName`.
    public static func resolveWorker(
        _ raw: String,
        flag: String = "--worker",
        models: [Model],
        readyModelIds: Set<String>? = nil
    ) -> Result<Model, Failure> {
        let provided = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provided.isEmpty else {
            return .failure(workerFailure(
                provided: raw,
                flag: flag,
                models: models,
                readyModelIds: readyModelIds,
                reason: "empty"
            ))
        }
        if let exact = models.first(where: { $0.id == provided }) {
            return .success(exact)
        }
        // Case-insensitive id only (canonical ids are lowercase); never displayName.
        let lowered = provided.lowercased()
        if let exact = models.first(where: { $0.id.lowercased() == lowered }) {
            return .success(exact)
        }
        return .failure(workerFailure(
            provided: provided,
            flag: flag,
            models: models,
            readyModelIds: readyModelIds,
            reason: displayNameHit(provided, models: models) ? "displayName" : "unknown"
        ))
    }

    // MARK: - Teams (`--team`, …)

    /// Honor an exact team id, or fail closed. Never matches `displayName`.
    public static func resolveTeam(
        _ raw: String,
        flag: String = "--team",
        teams: [TeamPreset]
    ) -> Result<TeamPreset, Failure> {
        let provided = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provided.isEmpty else {
            return .failure(teamFailure(provided: raw, flag: flag, teams: teams, reason: "empty"))
        }
        if let exact = teams.first(where: { $0.id == provided }) {
            return .success(exact)
        }
        let lowered = provided.lowercased()
        if let exact = teams.first(where: { $0.id.lowercased() == lowered }) {
            return .success(exact)
        }
        return .failure(teamFailure(
            provided: provided,
            flag: flag,
            teams: teams,
            reason: displayNameHit(provided, teams: teams) ? "displayName" : "unknown"
        ))
    }

    // MARK: - Failure builders

    private static func workerFailure(
        provided: String,
        flag: String,
        models: [Model],
        readyModelIds: Set<String>?,
        reason: String
    ) -> Failure {
        let candidates = nearestWorkerCandidates(
            query: provided, models: models, readyModelIds: readyModelIds)
        let message: String
        switch reason {
        case "displayName":
            message =
                "\(flag) rejects display names — pass a canonical model id (got '\(provided)'). "
                + "Run `alln menu --json` and use a model_* id."
        case "empty":
            message = "\(flag) requires a canonical model id"
        default:
            message =
                "unknown worker id '\(provided)' for \(flag) — pass a canonical model_* id; "
                + "see `alln menu --json` / `alln menu show model:<id>`."
        }
        return Failure(
            code: "WORKER_NOT_AVAILABLE",
            kind: .worker,
            flag: flag,
            provided: provided,
            message: message,
            candidates: candidates,
            discoveryCommand: "alln menu --json"
        )
    }

    private static func teamFailure(
        provided: String,
        flag: String,
        teams: [TeamPreset],
        reason: String
    ) -> Failure {
        let candidates = nearestTeamCandidates(query: provided, teams: teams)
        let message: String
        switch reason {
        case "displayName":
            message =
                "\(flag) rejects display names — pass a canonical team id (got '\(provided)'). "
                + "Run `alln menu --json` and use an exact team id."
        case "empty":
            message = "\(flag) requires a canonical team id"
        default:
            message =
                "unknown team '\(provided)' for \(flag) — pass a canonical team id; "
                + "see `alln menu --json` / `alln menu show team:<id>`."
        }
        return Failure(
            code: "TEAM_NOT_FOUND",
            kind: .team,
            flag: flag,
            provided: provided,
            message: message,
            candidates: candidates,
            discoveryCommand: "alln menu --json"
        )
    }

    private static func nearestWorkerCandidates(
        query: String,
        models: [Model],
        readyModelIds: Set<String>?,
        limit: Int = 5
    ) -> [Candidate] {
        let lowered = query.lowercased()
        var ordered: [String] = []
        // Exact display-name hit is the strongest spelling-repair hint (never auto-selected).
        for model in models where model.displayName.lowercased() == lowered {
            ordered.append(model.id)
        }
        let ids = models.map(\.id)
        for id in ErrorDiscovery.nearestMatches(to: query, in: ids, limit: limit) where !ordered.contains(id) {
            ordered.append(id)
        }
        let byName = models
            .map { ($0, CLIUsage.editDistance(lowered, $0.displayName.lowercased())) }
            .filter { $0.1 > 0 && $0.1 <= max(2, query.count / 2) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0.id)
        for id in byName where !ordered.contains(id) {
            ordered.append(id)
        }
        if ordered.isEmpty {
            ordered = Array(models.map(\.id).sorted().prefix(limit))
        }
        let byId = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        return ordered.prefix(limit).compactMap { id -> Candidate? in
            guard let model = byId[id] else { return nil }
            return Candidate(
                id: model.id,
                displayName: model.displayName,
                driverId: model.driverId,
                state: workerState(model, readyModelIds: readyModelIds)
            )
        }
    }

    private static func nearestTeamCandidates(
        query: String,
        teams: [TeamPreset],
        limit: Int = 5
    ) -> [Candidate] {
        let lowered = query.lowercased()
        var ordered: [String] = []
        for team in teams where team.displayName.lowercased() == lowered {
            ordered.append(team.id)
        }
        let ids = teams.map(\.id)
        for id in ErrorDiscovery.nearestMatches(to: query, in: ids, limit: limit) where !ordered.contains(id) {
            ordered.append(id)
        }
        let byName = teams
            .map { ($0, CLIUsage.editDistance(lowered, $0.displayName.lowercased())) }
            .filter { $0.1 > 0 && $0.1 <= max(2, query.count / 2) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0.id)
        for id in byName where !ordered.contains(id) {
            ordered.append(id)
        }
        if ordered.isEmpty {
            ordered = Array(teams.map(\.id).sorted().prefix(limit))
        }
        let byId = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        return ordered.prefix(limit).compactMap { id -> Candidate? in
            guard let team = byId[id] else { return nil }
            return Candidate(
                id: team.id,
                displayName: team.displayName,
                driverId: nil,
                state: TeamVisibility.isEnabled(team.id) ? "active" : "inactive"
            )
        }
    }

    private static func workerState(_ model: Model, readyModelIds: Set<String>?) -> String {
        if !model.enabled { return "disabled" }
        if let ready = readyModelIds {
            return ready.contains(model.id) ? "ready" : "notReady"
        }
        return "enabled"
    }

    private static func displayNameHit(_ provided: String, models: [Model]) -> Bool {
        let lowered = provided.lowercased()
        return models.contains { $0.displayName.lowercased() == lowered }
    }

    private static func displayNameHit(_ provided: String, teams: [TeamPreset]) -> Bool {
        let lowered = provided.lowercased()
        return teams.contains { $0.displayName.lowercased() == lowered }
    }
}
