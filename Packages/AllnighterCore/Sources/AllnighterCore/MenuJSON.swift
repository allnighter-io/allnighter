import Foundation

/// Tier-1 compact agent menu (`alln menu --json`) — MR-S01 / Menu_Not_Router.md.
public struct MenuJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var contractHash: String
    /// Hash of the dynamic team/model/recipe snapshot (not the static contract).
    public var catalogRevision: String
    public var truncated: Bool
    public var detailTemplate: String
    public var actions: [Action]
    public var commands: [Command]
    public var teams: [Team]
    public var models: [Model]
    public var recipes: [Recipe]
    public var effectProfiles: [String: ContractRegistry.EffectProfile]
    public var defaults: Defaults
    public var completeness: Completeness

    public struct Action: Codable, Sendable, Equatable {
        public var id: String
        public var useWhen: String
        public var dontUseWhen: String
        public var effectsRef: String
        public var example: String
        public var validateExample: String
    }

    public struct Command: Codable, Sendable, Equatable {
        public var ref: String
        public var name: String
        public var effectsRef: String
    }

    public struct Team: Codable, Sendable, Equatable {
        public var ref: String
        public var id: String
        public var displayName: String
        public var useWhen: String
        public var dontUseWhen: String
        public var shape: String
        public var mutating: Bool
        public var seatCount: Int
        public var isDefault: Bool
        public var active: Bool
        public var blockedReason: String?
        public var runTemplate: String
        public var validateTemplate: String
    }

    public struct Model: Codable, Sendable, Equatable {
        public var ref: String
        public var id: String
        public var displayName: String
        public var driverId: String
        public var enabled: Bool
        public var ready: Bool
        public var blockedReason: String?
        public var useWhen: String
        public var dontUseWhen: String
        public var runTemplate: String
        public var validateTemplate: String
    }

    public struct Recipe: Codable, Sendable, Equatable {
        public var ref: String
        public var id: String
        public var title: String
        public var useWhen: String
        public var dontUseWhen: String
    }

    public struct Defaults: Codable, Sendable, Equatable {
        public var defaultTeamRef: String
        public var defaultModelId: String?
    }

    public struct CollectionCompleteness: Codable, Sendable, Equatable {
        public var count: Int
        public var complete: Bool
    }

    public struct Completeness: Codable, Sendable, Equatable {
        public var actions: CollectionCompleteness
        public var commands: CollectionCompleteness
        public var teams: CollectionCompleteness
        public var models: CollectionCompleteness
        public var recipes: CollectionCompleteness
        public var effectProfiles: CollectionCompleteness
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        contractHash: String,
        catalogRevision: String,
        truncated: Bool = false,
        detailTemplate: String = "alln menu show {ref} --json",
        actions: [Action],
        commands: [Command],
        teams: [Team],
        models: [Model],
        recipes: [Recipe],
        effectProfiles: [String: ContractRegistry.EffectProfile],
        defaults: Defaults,
        completeness: Completeness
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.catalogRevision = catalogRevision
        self.truncated = truncated
        self.detailTemplate = detailTemplate
        self.actions = actions
        self.commands = commands
        self.teams = teams
        self.models = models
        self.recipes = recipes
        self.effectProfiles = effectProfiles
        self.defaults = defaults
        self.completeness = completeness
    }
}

extension MenuJSON {
    /// Lean plan-time capacity decision row (QABC-S00b) — narrowed from the
    /// display-oriented `CapacityStripJSON` so `alln menu` and `alln capacity`
    /// share one derivation path and never disagree. See
    /// docs/phases/Quota_Aware_Bench_Continuity.md "Corrections against live
    /// code" item 3 for the byte-budget rationale.
    public struct Capacity: Sendable, Equatable, Codable {
        public let generatedAt: Date
        public let rows: [Row]

        public init(generatedAt: Date, rows: [Row]) {
            self.generatedAt = generatedAt
            self.rows = rows
        }

        public struct Row: Sendable, Equatable, Codable {
            public let source: String
            public let effectiveRemainingPercent: Int?
            public let resetAt: Date?
            public let scope: CapacityWindowScope?
            public let shortRemainingPercent: Int?
            /// Nil when never observed. A sentinel (e.g. `Int.max`) would cost
            /// ~19 bytes per row on the wire and fabricate a duration that was
            /// never measured — nil is both cheaper and honest here.
            public let observedAgeSeconds: Int?
            public let unknownReason: String?

            public init(
                source: String,
                effectiveRemainingPercent: Int?,
                resetAt: Date?,
                scope: CapacityWindowScope?,
                shortRemainingPercent: Int?,
                observedAgeSeconds: Int?,
                unknownReason: String?
            ) {
                self.source = source
                self.effectiveRemainingPercent = effectiveRemainingPercent
                self.resetAt = resetAt
                self.scope = scope
                self.shortRemainingPercent = shortRemainingPercent
                self.observedAgeSeconds = observedAgeSeconds
                self.unknownReason = unknownReason
            }
        }

        public init(strip: CapacityStripJSON) {
            generatedAt = strip.generatedAt
            rows = strip.rows.map(Row.init(stripRow:))
        }
    }
}

extension MenuJSON.Capacity.Row {
    fileprivate init(stripRow row: CapacityStripJSONRow) {
        self.init(
            source: row.source,
            effectiveRemainingPercent: row.effectiveRemainingPercent.map { Int($0.rounded()) },
            resetAt: row.dashboardResetAt,
            scope: row.dashboardScope,
            shortRemainingPercent: row.shortRemainingPercent.map { Int($0.rounded()) },
            observedAgeSeconds: row.observedAgeSeconds.map { Int($0.rounded()) },
            unknownReason: row.unknownReason?.rawValue
        )
    }
}

/// Tier-2 hydrate payload (`alln menu show <ref> --json`).
public struct MenuShowJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var ref: String
    public var kind: String
    public var command: CommandDetail?
    public var team: TeamDetail?
    public var model: ModelDetail?
    public var recipe: RecipeDetail?

    public struct CommandDetail: Codable, Sendable, Equatable {
        public var ref: String
        public var name: String
        public var summary: String
        public var trigger: String
        public var example: String
        public var antiExample: String
        public var spendsQuota: Bool
        public var freeTwinCommand: String?
        public var effects: ContractRegistry.EffectProfile
        public var args: [ContractRegistry.ArgSpec]
        public var flags: [ContractRegistry.FlagSpec]
        public var mutuallyExclusiveFlags: [[String]]
        public var flagConstraints: [ContractRegistry.FlagConstraint]
    }

    public struct TeamDetail: Codable, Sendable, Equatable {
        public var ref: String
        public var id: String
        public var displayName: String
        public var description: String
        public var lane: String
        public var outputKind: String
        public var shape: String
        public var mutating: Bool
        public var seatCount: Int
        public var isDefault: Bool
        public var active: Bool
        public var blockedReason: String?
        public var runTemplate: String
        public var validateTemplate: String
        public var purposeTags: [String]
    }

    public struct ModelDetail: Codable, Sendable, Equatable {
        public var ref: String
        public var id: String
        public var displayName: String
        public var driverId: String
        public var driverName: String
        public var enabled: Bool
        public var ready: Bool
        public var status: String
        public var blockedReason: String?
        public var capabilities: ModelCapabilities
        public var runTemplate: String
        public var validateTemplate: String
    }

    public struct RecipeDetail: Codable, Sendable, Equatable {
        public var ref: String
        public var id: String
        public var title: String
        public var useWhen: String
        public var dontUseWhen: String
        public var markdown: String
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        ref: String,
        kind: String,
        command: CommandDetail? = nil,
        team: TeamDetail? = nil,
        model: ModelDetail? = nil,
        recipe: RecipeDetail? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.ref = ref
        self.kind = kind
        self.command = command
        self.team = team
        self.model = model
        self.recipe = recipe
    }
}

/// Structured failure for unknown typed refs (same-kind suggestions).
public struct MenuRefError: Error, Equatable, Sendable {
    public var ref: String
    public var kind: String?
    public var message: String
    public var suggestions: [String]

    public init(ref: String, kind: String?, message: String, suggestions: [String]) {
        self.ref = ref
        self.kind = kind
        self.message = message
        self.suggestions = suggestions
    }
}
