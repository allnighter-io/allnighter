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
    /// Present in Tier-1, where per-row templates are normalised away.
    public var modelInvocation: Invocation?
    /// Same normalisation for teams; `{team}` substitutes a row's `id`.
    public var teamInvocation: Invocation?
    /// Present only when Tier-1 filtered disabled seats out of `models`.
    public var blocked: OmittedSeats?
    public var recipes: [Recipe]
    public var effectProfiles: [String: ContractRegistry.EffectProfile]
    public var defaults: Defaults
    public var completeness: Completeness
    /// QABC-S00c — plan-time capacity snapshot, injected downward from a
    /// caller that already acquired it. Absent (not `null`) when omitted.
    public var capacity: Capacity?
    /// OPC-S06 — release-channel announcement when a newer CLI is known.
    /// Absent (not `null`) when omitted. Never carries remote notes/command.
    public var update: ReleaseUpdateInfo?
    /// FCS-S02 — shared bench tally (Core `BenchTallyProjector`). Always present
    /// when projected from a live registry. `nextAction` is set when the agent
    /// must run a command before spend (`alln detect` or `alln doctor --full --json`).
    public var benchTally: BenchTallyPayload?

    /// Wire shape for `BenchTally` — no ready/total ratio field by design.
    public struct BenchTallyPayload: Codable, Sendable, Equatable {
        public var headline: String
        public var supported: Int
        public var measured: Int
        public var ready: Int
        public var needsStep: Int
        public var notInstalled: Int
        public var needsCheck: Int
        public var nextAction: AgentSurfaceNextAction?

        public init(
            headline: String,
            supported: Int,
            measured: Int,
            ready: Int,
            needsStep: Int,
            notInstalled: Int,
            needsCheck: Int,
            nextAction: AgentSurfaceNextAction? = nil
        ) {
            self.headline = headline
            self.supported = supported
            self.measured = measured
            self.ready = ready
            self.needsStep = needsStep
            self.notInstalled = notInstalled
            self.needsCheck = needsCheck
            self.nextAction = nextAction
        }

        public init(tally: BenchTally) {
            headline = tally.headline.rawValue
            supported = tally.supported
            measured = tally.measured
            ready = tally.ready
            needsStep = tally.needsStep
            notInstalled = tally.notInstalled
            needsCheck = tally.needsCheck
            switch tally.headline {
            case .neverScanned:
                nextAction = AgentSurfaceNextAction(
                    kind: "detectCLIs",
                    label: "Find CLIs on this Mac",
                    command: BenchTallyProjector.detectCommand
                )
            case .noneReady, .partial:
                if tally.needsStep > 0 || tally.notInstalled > 0 || tally.needsCheck > 0 {
                    nextAction = AgentSurfaceNextAction(
                        kind: "runDoctorFull",
                        label: "Diagnose CLI setup",
                        command: "alln doctor --full --json"
                    )
                } else {
                    nextAction = nil
                }
            case .configurationMissing:
                nextAction = AgentSurfaceNextAction(
                    kind: "runDoctor",
                    label: "Check setup and sources",
                    command: "alln doctor --json"
                )
            case .allReady:
                nextAction = nil
            }
        }
    }

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

    /// A Team is Allnighter-specific: its roster, skills and posture exist
    /// nowhere else, so unlike a model its `useWhen`/`dontUseWhen` cannot be
    /// looked up and stay in Tier-1. They also carry routing value — several
    /// name the team to use INSTEAD ("Not mutating; build_slice").
    public struct Team: Codable, Sendable, Equatable {
        public var ref: String?
        public var id: String
        public var displayName: String
        public var useWhen: String
        public var dontUseWhen: String
        public var shape: String
        public var mutating: Bool
        public var seatCount: Int
        public var isDefault: Bool
        /// Emitted ONLY when a team is switched off (`TeamVisibility`), which is
        /// a real runtime state. Omitted when active, where it said `true` on
        /// every row and carried nothing. It must never be silently absent: an
        /// agent asked for a switched-off team has to be able to say so instead
        /// of failing to find it.
        public var active: Bool?
        public var blockedReason: String?
        public var runTemplate: String?
        public var validateTemplate: String?
    }

    /// A selectable seat. Tier-1 carries only what selection needs — identity,
    /// which CLI owns it, and whether it can run now. `ref`, `useWhen` and
    /// `dontUseWhen` are `--detailed` only: `ref` is `"model:" + id` (derivable,
    /// so it is not information), and the prose is advisory, never required to
    /// construct a call. `runTemplate`/`validateTemplate` stay in Tier-1 on
    /// purpose — the surface teaches by example, and the example must be in
    /// front of the caller, not assembled from elsewhere.
    public struct Model: Codable, Sendable, Equatable {
        public var ref: String?
        public var id: String
        public var displayName: String
        public var driverId: String
        public var enabled: Bool
        public var ready: Bool
        public var blockedReason: String?
        /// Present only when `ready` is false, where it separates `parked` from
        /// `notReady` — a distinction that changes what a caller should do.
        /// Omitted when ready, because there it only restates `ready`.
        public var status: String?
        /// `--detailed`: what this seat is configured FOR. Facts from the
        /// catalog, not a quality claim — `strengthRank` is deliberately not
        /// surfaced here (see `Scarcity_Aware_Routing.md`: rank did not predict
        /// outcome, and publishing it invites exactly that inference).
        /// `alln menu show model:<id>` carries the full record for anyone who
        /// genuinely wants it.
        public var capabilityTags: [String]?
        public var runTemplate: String?
        public var validateTemplate: String?
        /// PF-S04 — the one decision an agent makes from a model row's
        /// evidence: trust `ready`/`status` or not. A model is never
        /// independently smoke-probed, so the full disclosure (`checkedAt`,
        /// `ageMinutes`, `evidenceSource`, `nextAction`) lives once on the
        /// owning driver row (`alln drivers --json`, via this row's own
        /// `driverId`) instead of being copied onto every model that shares
        /// it — see `ModelListJSON.Entry.stale` for the full rationale.
        public var stale: Bool
        /// Catalog pin this latest-pointer resolved to. Omitted on pins and aliases.
        public var resolvesTo: String? = nil

        private enum CodingKeys: String, CodingKey {
            case ref, id, displayName, driverId, enabled, ready, blockedReason
            case status, capabilityTags, runTemplate, validateTemplate, stale, resolvesTo
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(ref, forKey: .ref)
            try c.encode(id, forKey: .id)
            try c.encode(displayName, forKey: .displayName)
            try c.encode(driverId, forKey: .driverId)
            try c.encode(enabled, forKey: .enabled)
            try c.encode(ready, forKey: .ready)
            try c.encodeIfPresent(blockedReason, forKey: .blockedReason)
            try c.encodeIfPresent(status, forKey: .status)
            try c.encodeIfPresent(capabilityTags, forKey: .capabilityTags)
            try c.encodeIfPresent(runTemplate, forKey: .runTemplate)
            try c.encodeIfPresent(validateTemplate, forKey: .validateTemplate)
            try c.encode(stale, forKey: .stale)
            try c.encodeIfPresent(resolvesTo, forKey: .resolvesTo)
        }
    }

    /// How to invoke any seat, stated once instead of per row.
    ///
    /// The surface still teaches by example — `worked` is a complete, runnable
    /// command with a real id in it. What stage 2 removes is the 39 further
    /// copies of that same shape, which stored bytes without teaching anything
    /// the first one did not. `{model}` is substituted from a row's `id`, the
    /// same operation callers already perform on `{message}` throughout this
    /// payload.
    public struct Invocation: Codable, Sendable, Equatable {
        public var run: String
        public var validate: String
        public var worked: String
    }

    /// Seats omitted from a Tier-1 menu because they are off the bench, plus how
    /// to see them. Without this an agent told to use an off-bench id finds
    /// nothing in the menu and either invents an id or reports the tool broken.
    public struct OmittedSeats: Codable, Sendable, Equatable {
        public var count: Int
        public var see: String
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
        modelInvocation: Invocation? = nil,
        teamInvocation: Invocation? = nil,
        blocked: OmittedSeats? = nil,
        recipes: [Recipe],
        effectProfiles: [String: ContractRegistry.EffectProfile],
        defaults: Defaults,
        completeness: Completeness,
        capacity: Capacity? = nil,
        update: ReleaseUpdateInfo? = nil,
        benchTally: BenchTallyPayload? = nil
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
        self.modelInvocation = modelInvocation
        self.teamInvocation = teamInvocation
        self.blocked = blocked
        self.recipes = recipes
        self.effectProfiles = effectProfiles
        self.defaults = defaults
        self.completeness = completeness
        self.capacity = capacity
        self.update = update
        self.benchTally = benchTally
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, contractVersion, contractHash, catalogRevision, truncated,
            detailTemplate, actions, commands, teams, teamInvocation, models, modelInvocation,
            blocked, recipes,
            effectProfiles,
            defaults, completeness, capacity, update, benchTally
    }

    /// Swift's synthesized `Encodable` writes `Optional` properties as explicit
    /// `null` rather than omitting the key — this packet requires an absent key
    /// when `capacity` / `update` is nil, so encoding is hand-written; decoding
    /// stays synthesized (a matching `CodingKeys` is enough for that half).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(contractVersion, forKey: .contractVersion)
        try container.encode(contractHash, forKey: .contractHash)
        try container.encode(catalogRevision, forKey: .catalogRevision)
        try container.encode(truncated, forKey: .truncated)
        try container.encode(detailTemplate, forKey: .detailTemplate)
        try container.encode(actions, forKey: .actions)
        try container.encode(commands, forKey: .commands)
        try container.encode(teams, forKey: .teams)
        try container.encodeIfPresent(teamInvocation, forKey: .teamInvocation)
        try container.encode(models, forKey: .models)
        try container.encodeIfPresent(modelInvocation, forKey: .modelInvocation)
        try container.encodeIfPresent(blocked, forKey: .blocked)
        try container.encode(recipes, forKey: .recipes)
        try container.encode(effectProfiles, forKey: .effectProfiles)
        try container.encode(defaults, forKey: .defaults)
        try container.encode(completeness, forKey: .completeness)
        try container.encodeIfPresent(capacity, forKey: .capacity)
        try container.encodeIfPresent(update, forKey: .update)
        try container.encodeIfPresent(benchTally, forKey: .benchTally)
    }
}

extension MenuJSON {
    /// Lean plan-time capacity decision row (QABC-S00b) — narrowed from the
    /// display-oriented `CapacityStripJSON` so `alln menu` and `alln capacity`
    /// share one derivation path and never disagree. See
    /// docs/archive/phases/Quota_Aware_Bench_Continuity.md "Corrections against live
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
        public var modelLabel: String?
        public var resolvesTo: String?
        /// QABC-S00d — rows from the injected menu capacity narrowed to this
        /// model's source only. Nil when no capacity was injected or no row
        /// matches this model's driver.
        public var capacity: MenuJSON.Capacity?

        public init(
            ref: String,
            id: String,
            displayName: String,
            driverId: String,
            driverName: String,
            enabled: Bool,
            ready: Bool,
            status: String,
            blockedReason: String?,
            capabilities: ModelCapabilities,
            runTemplate: String,
            validateTemplate: String,
            modelLabel: String? = nil,
            resolvesTo: String? = nil,
            capacity: MenuJSON.Capacity? = nil
        ) {
            self.ref = ref
            self.id = id
            self.displayName = displayName
            self.driverId = driverId
            self.driverName = driverName
            self.enabled = enabled
            self.ready = ready
            self.status = status
            self.blockedReason = blockedReason
            self.capabilities = capabilities
            self.runTemplate = runTemplate
            self.validateTemplate = validateTemplate
            self.modelLabel = modelLabel
            self.resolvesTo = resolvesTo
            self.capacity = capacity
        }
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
