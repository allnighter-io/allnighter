import Foundation

/// Mac owner-action catalog. Sibling of `MenuCatalog`: capability rows, not
/// articles. Ask AI answers "where is that control?" from these rows. The
/// model writes the sentence.
public enum ChromeScreen: String, Sendable, Codable, CaseIterable {
    case home
    case settings = "settings"
    case settingsBoost = "settings.boost"
    case settingsAbout = "settings.about"
    case settingsDefaultModel = "settings.default_model"
    case settingsUseFromCLI = "settings.use_from_cli"
    case settingsCLIs = "settings.clis"
    case settingsPlan = "settings.plan"
    case settingsTeams = "settings.teams"
}

public struct ChromeActionRow: Sendable, Equatable, Codable {
    public var id: String
    public var screen: String
    public var controlLabel: String
    public var whereInApp: String
    public var facts: [String]

    public init(
        id: String,
        screen: String,
        controlLabel: String,
        whereInApp: String,
        facts: [String]
    ) {
        self.id = id
        self.screen = screen
        self.controlLabel = controlLabel
        self.whereInApp = whereInApp
        self.facts = facts
    }

    enum CodingKeys: String, CodingKey {
        case id, screen, controlLabel, facts
        case whereInApp = "where"
    }
}

public struct ChromeLiveFacts: Sendable, Equatable {
    public var boostEnabled: Bool?
    public var boostWindowStart: String?
    public var benchChromeLabel: String?
    public var benchReady: Int?
    public var benchNeedsStep: Int?
    public var benchSupported: Int?
    public var pathStandaloneHome: String?
    public var pathResolved: String?
    public var pathConflict: Bool?

    public init(
        boostEnabled: Bool? = nil,
        boostWindowStart: String? = nil,
        benchChromeLabel: String? = nil,
        benchReady: Int? = nil,
        benchNeedsStep: Int? = nil,
        benchSupported: Int? = nil,
        pathStandaloneHome: String? = nil,
        pathResolved: String? = nil,
        pathConflict: Bool? = nil
    ) {
        self.boostEnabled = boostEnabled
        self.boostWindowStart = boostWindowStart
        self.benchChromeLabel = benchChromeLabel
        self.benchReady = benchReady
        self.benchNeedsStep = benchNeedsStep
        self.benchSupported = benchSupported
        self.pathStandaloneHome = pathStandaloneHome
        self.pathResolved = pathResolved
        self.pathConflict = pathConflict
    }

    public static let empty = ChromeLiveFacts()
}

public struct ChromeCatalogJSON: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var screen: String?
    public var actions: [ChromeActionRow]

    public init(schemaVersion: Int = 1, screen: String? = nil, actions: [ChromeActionRow]) {
        self.schemaVersion = schemaVersion
        self.screen = screen
        self.actions = actions
    }
}

public enum ChromeCatalog {
    public static let firstSliceIds: [String] = [
        "ask_ai", "teams", "models", "bench_health", "boost_window",
        "default_model", "use_from_cli", "about_path", "capacity", "support_hatch",
    ]

    public static func project(
        screen: String? = nil,
        live: ChromeLiveFacts = .empty
    ) -> ChromeCatalogJSON {
        let rows = firstSliceRows(live: live)
        let filtered = rows.filter { matches(rowScreen: $0.screen, requested: screen) }
        let sorted = filtered.sorted { a, b in
            let aHit = exactScreen(a.screen, requested: screen)
            let bHit = exactScreen(b.screen, requested: screen)
            if aHit != bHit { return aHit && !bHit }
            return a.id < b.id
        }
        return ChromeCatalogJSON(screen: screen, actions: sorted)
    }

    public static func encode(_ json: ChromeCatalogJSON) throws -> String {
        String(decoding: try CoreJSON.encode(json), as: UTF8.self)
    }

    private static func matches(rowScreen: String, requested: String?) -> Bool {
        guard let requested, !requested.isEmpty else { return true }
        if rowScreen == requested { return true }
        if requested == ChromeScreen.settings.rawValue {
            return rowScreen.hasPrefix("settings.") || rowScreen == "settings"
        }
        return false
    }

    private static func exactScreen(_ rowScreen: String, requested: String?) -> Bool {
        guard let requested, !requested.isEmpty else { return false }
        return rowScreen == requested
    }

    private static func firstSliceRows(live: ChromeLiveFacts) -> [ChromeActionRow] {
        [
            ChromeActionRow(
                id: "ask_ai",
                screen: ChromeScreen.home.rawValue,
                controlLabel: ChromeCopy.askAI,
                whereInApp: "Title bar",
                facts: [
                    "Control label: \(ChromeCopy.askAI)",
                    "Deck: \(AskAIPrompt.deck)",
                ]
            ),
            ChromeActionRow(
                id: "teams",
                screen: ChromeScreen.home.rawValue,
                controlLabel: ChromeCopy.teams,
                whereInApp: "Title bar › Inbox | Teams",
                facts: [
                    "Control label: \(ChromeCopy.teams)",
                    "Paired with: \(ChromeCopy.inbox)",
                ]
            ),
            ChromeActionRow(
                id: "models",
                screen: ChromeScreen.home.rawValue,
                controlLabel: ChromeCopy.models,
                whereInApp: "Title bar",
                facts: [
                    "Control label: \(ChromeCopy.models)",
                ]
            ),
            ChromeActionRow(
                id: "bench_health",
                screen: ChromeScreen.home.rawValue,
                controlLabel: live.benchChromeLabel ?? ChromeCopy.needAStep,
                whereInApp: "Title bar",
                facts: benchFacts(live)
            ),
            ChromeActionRow(
                id: "boost_window",
                screen: ChromeScreen.settingsBoost.rawValue,
                controlLabel: ChromeCopy.boostWindow,
                whereInApp: "Settings › \(ChromeCopy.boostWindow)",
                facts: boostFacts(live)
            ),
            ChromeActionRow(
                id: "default_model",
                screen: ChromeScreen.settingsDefaultModel.rawValue,
                controlLabel: ChromeCopy.defaultModel,
                whereInApp: "Settings › \(ChromeCopy.defaultModel)",
                facts: [
                    "Control label: \(ChromeCopy.defaultModel)",
                    ChromeCopy.defaultModelDeck,
                ]
            ),
            ChromeActionRow(
                id: "use_from_cli",
                screen: ChromeScreen.settingsUseFromCLI.rawValue,
                controlLabel: ChromeCopy.useFromCLI,
                whereInApp: "Settings › \(ChromeCopy.useFromCLI)",
                facts: [
                    "Control label: \(ChromeCopy.useFromCLI)",
                ]
            ),
            ChromeActionRow(
                id: "about_path",
                screen: ChromeScreen.settingsAbout.rawValue,
                controlLabel: ChromeCopy.cliOnPATH,
                whereInApp: "Settings › \(ChromeCopy.aboutUpdates)",
                facts: aboutPathFacts(live)
            ),
            ChromeActionRow(
                id: "capacity",
                screen: ChromeScreen.home.rawValue,
                controlLabel: ChromeCopy.capacityIdleHero,
                whereInApp: "Home",
                facts: [
                    "Hero (room): \(ChromeCopy.capacityIdleHero)",
                    "Hero (expiring): \(ChromeCopy.capacityExpiringHero)",
                ]
            ),
            ChromeActionRow(
                id: "support_hatch",
                screen: ChromeScreen.home.rawValue,
                controlLabel: ChromeCopy.emailAPerson,
                whereInApp: "Ask AI panel footer",
                facts: [
                    "Control label: \(ChromeCopy.emailAPerson)",
                    "Email: \(AskAIPrompt.supportEmail)",
                ]
            ),
        ]
    }

    private static func boostFacts(_ live: ChromeLiveFacts) -> [String] {
        var facts = [
            "Control label: \(ChromeCopy.boostWindow)",
            ChromeCopy.boostHeadline,
            ChromeCopy.boostHow,
        ]
        if let enabled = live.boostEnabled {
            facts.append("On this Mac: \(enabled ? "On" : "Off")")
        }
        if let start = live.boostWindowStart {
            facts.append("Window start: \(start)")
        }
        return facts
    }

    private static func benchFacts(_ live: ChromeLiveFacts) -> [String] {
        var facts = [
            "Phrase on the tally: \(ChromeCopy.needAStep)",
        ]
        if let label = live.benchChromeLabel {
            facts.append("Title-bar badge right now: \(label)")
        }
        if let ready = live.benchReady, let needs = live.benchNeedsStep, let supported = live.benchSupported {
            facts.append("Counts: \(ready) ready, \(needs) \(ChromeCopy.needAStep), of \(supported)")
        }
        return facts
    }

    private static func aboutPathFacts(_ live: ChromeLiveFacts) -> [String] {
        var facts = [
            "Section: \(ChromeCopy.cliOnPATH)",
            "Row: \(ChromeCopy.standaloneHome)",
            "Row: \(ChromeCopy.resolvesTo)",
            ChromeCopy.pathRepair,
        ]
        if let home = live.pathStandaloneHome {
            facts.append("\(ChromeCopy.standaloneHome): \(home)")
        }
        if let resolved = live.pathResolved {
            facts.append("\(ChromeCopy.resolvesTo): \(resolved)")
        } else if live.pathResolved == nil, live.pathStandaloneHome != nil {
            facts.append("\(ChromeCopy.resolvesTo): \(ChromeCopy.notOnPATH)")
        }
        if live.pathConflict == true {
            facts.append(ChromeCopy.pathConflict)
        }
        return facts
    }
}
