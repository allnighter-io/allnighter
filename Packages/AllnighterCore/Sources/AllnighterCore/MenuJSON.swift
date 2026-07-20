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
        public var defaultWorkerId: String?
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
        /// Registry mutual-exclusion groups (SH-S10 teaching projection).
        public var mutuallyExclusiveFlags: [[String]]
        /// Registry `requires` / `onlyWith` constraints (SH-S10 teaching projection).
        public var flagConstraints: [ContractRegistry.FlagConstraint]

        private enum CodingKeys: String, CodingKey {
            case ref, name, summary, trigger, example, antiExample, spendsQuota
            case freeTwinCommand, effects, args, flags
            case mutuallyExclusiveFlags, flagConstraints
        }

        public init(
            ref: String,
            name: String,
            summary: String,
            trigger: String,
            example: String,
            antiExample: String,
            spendsQuota: Bool,
            freeTwinCommand: String?,
            effects: ContractRegistry.EffectProfile,
            args: [ContractRegistry.ArgSpec],
            flags: [ContractRegistry.FlagSpec],
            mutuallyExclusiveFlags: [[String]] = [],
            flagConstraints: [ContractRegistry.FlagConstraint] = []
        ) {
            self.ref = ref
            self.name = name
            self.summary = summary
            self.trigger = trigger
            self.example = example
            self.antiExample = antiExample
            self.spendsQuota = spendsQuota
            self.freeTwinCommand = freeTwinCommand
            self.effects = effects
            self.args = args
            self.flags = flags
            self.mutuallyExclusiveFlags = mutuallyExclusiveFlags
            self.flagConstraints = flagConstraints
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ref = try c.decode(String.self, forKey: .ref)
            name = try c.decode(String.self, forKey: .name)
            summary = try c.decode(String.self, forKey: .summary)
            trigger = try c.decode(String.self, forKey: .trigger)
            example = try c.decode(String.self, forKey: .example)
            antiExample = try c.decode(String.self, forKey: .antiExample)
            spendsQuota = try c.decode(Bool.self, forKey: .spendsQuota)
            freeTwinCommand = try c.decodeIfPresent(String.self, forKey: .freeTwinCommand)
            effects = try c.decode(ContractRegistry.EffectProfile.self, forKey: .effects)
            args = try c.decodeIfPresent([ContractRegistry.ArgSpec].self, forKey: .args) ?? []
            flags = try c.decodeIfPresent([ContractRegistry.FlagSpec].self, forKey: .flags) ?? []
            mutuallyExclusiveFlags = try c.decodeIfPresent([[String]].self, forKey: .mutuallyExclusiveFlags) ?? []
            flagConstraints = try c.decodeIfPresent([ContractRegistry.FlagConstraint].self, forKey: .flagConstraints) ?? []
        }
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
