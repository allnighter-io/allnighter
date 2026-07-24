import Foundation

/// Programmatic help-search index derived from live catalogs (ASF-S03).
/// Feeds `HelpTopicRegistry.aliasRedirects` and boosts `HelpService.search` so
/// product terms like `kimi` / `grok` resolve to the teams/workers topic —
/// never hand-maintained one-off aliases alone.
public enum HelpDiscoveryIndex {
    /// Topic that documents models, teams, and workers.
    public static let discoveryTopicId = "teams_and_workers"

    /// Terms too generic to own a catalog alias (would hijack ordinary help queries).
    private static let genericTerms: Set<String> = [
        "model", "auto", "code", "copy", "design", "signal", "fast", "default",
        "min", "max", "pro", "next", "high", "low", "med", "flash", "org",
        "claude", "gemini", "gpt", "oss", "team", "plan", "core", "build",
        "slice", "hunt", "bug", "review", "growth", "polish", "landing",
        "outside", "what", "to", "the", "a", "an", "and", "or", "of", "in",
        "for", "on", "with", "custom", "both", "answerer",
    ]

    public struct Match: Sendable, Equatable {
        public var topicId: String
        public var modelIds: [String]
        public var driverIds: [String]
        public var teamIds: [String]
        /// Raw score boost applied to the discovery topic (≥ minimum hit threshold).
        public var scoreBoost: Double
    }

    /// Catalog terms → discovery topic. Authored topic aliases must win on merge.
    public static func catalogAliasRedirects() -> [String: String] {
        var map: [String: String] = [:]
        for term in distinctiveTerms() {
            map[term] = discoveryTopicId
        }
        return map
    }

    /// Match a search query against the catalog index.
    public static func match(phrase: String, tokens: [String]) -> Match? {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !phrase.isEmpty else { return nil }

        var modelIds = Set<String>()
        var driverIds = Set<String>()
        var teamIds = Set<String>()
        var boost = 0.0

        for model in ModelCatalog.builtIns {
            let keys = termKeys(
                id: model.id,
                displayName: model.displayName,
                modelLabel: model.modelLabel,
                driverId: model.driverId
            )
            if keys.contains(phrase) || tokens.contains(where: { keys.contains($0) }) {
                modelIds.insert(model.id)
                driverIds.insert(model.driverId)
                boost = max(boost, keys.contains(phrase) ? 12 : 8)
            }
        }

        for team in BuiltInTeams.all {
            let keys = termKeys(
                id: team.id,
                displayName: team.displayName,
                modelLabel: nil,
                driverId: nil
            )
            // Family / lane name as an additional phrase (e.g. "code" alone is
            // generic and skipped; "bug hunt" from displayName still indexes).
            if keys.contains(phrase) || tokens.contains(where: { keys.contains($0) }) {
                teamIds.insert(team.id)
                boost = max(boost, keys.contains(phrase) ? 12 : 8)
            }
        }

        // Bare driver ids (even when no model id tokens matched the phrase alone).
        let drivers = Set(ModelCatalog.builtIns.map(\.driverId))
        if drivers.contains(phrase) {
            driverIds.insert(phrase)
            for model in ModelCatalog.builtIns where model.driverId == phrase {
                modelIds.insert(model.id)
            }
            boost = max(boost, 12)
        } else {
            for tok in tokens where drivers.contains(tok) {
                driverIds.insert(tok)
                for model in ModelCatalog.builtIns where model.driverId == tok {
                    modelIds.insert(model.id)
                }
                boost = max(boost, 8)
            }
        }

        // Family names that are not in the generic denylist (none today — kept
        // for completeness if a future lane is distinctive).
        for lane in WorkLane.allCases {
            let raw = lane.rawValue.lowercased()
            guard !genericTerms.contains(raw) else { continue }
            if phrase == raw || tokens.contains(raw) {
                boost = max(boost, 8)
            }
        }

        guard boost > 0 else { return nil }
        return Match(
            topicId: discoveryTopicId,
            modelIds: modelIds.sorted(),
            driverIds: driverIds.sorted(),
            teamIds: teamIds.sorted(),
            scoreBoost: boost
        )
    }

    // MARK: - Index building

    private static func distinctiveTerms() -> Set<String> {
        var terms = Set<String>()
        for model in ModelCatalog.builtIns {
            for key in termKeys(
                id: model.id,
                displayName: model.displayName,
                modelLabel: model.modelLabel,
                driverId: model.driverId
            ) where isDistinctive(key) {
                terms.insert(key)
            }
        }
        for team in BuiltInTeams.all {
            for key in termKeys(
                id: team.id,
                displayName: team.displayName,
                modelLabel: nil,
                driverId: nil
            ) where isDistinctive(key) {
                terms.insert(key)
            }
        }
        for driver in Set(ModelCatalog.builtIns.map(\.driverId)) where isDistinctive(driver) {
            terms.insert(driver.lowercased())
        }
        return terms
    }

    private static func termKeys(
        id: String,
        displayName: String,
        modelLabel: String?,
        driverId: String?
    ) -> Set<String> {
        var keys = Set<String>()
        let rawParts = [id, displayName, modelLabel, driverId].compactMap { $0 }
        for part in rawParts {
            let lower = part.lowercased()
            keys.insert(lower)
            for tok in tokenize(lower) {
                keys.insert(tok)
            }
        }
        return keys
    }

    private static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private static func isDistinctive(_ term: String) -> Bool {
        let t = term.lowercased()
        guard t.count >= 3 else { return false }
        guard !genericTerms.contains(t) else { return false }
        // Pure numeric fragments ("52", "25") are noise.
        if t.allSatisfy(\.isNumber) { return false }
        return true
    }
}
