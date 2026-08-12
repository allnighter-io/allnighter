import Foundation

/// `alln run --dry-run` probe. Resolves project/worker/auth/write policy and
/// write-lock state without dispatch. Exit 0 always; `canStart` carries the
/// verdict. Effects describe the spend twin the preview validates — not a
/// prediction that the prompt will or will not write (Law 7).
public struct RunDryRunJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var canStart: Bool
    public var blockedReason: String?
    public var projectId: String?
    public var projectRoot: String?
    public var teamPresetId: String?
    public var teamDisplayName: String?
    public var modelId: String?
    /// Catalog pin `modelId` resolved to when it is a family latest-pointer.
    public var resolvedPinModelId: String?
    /// Vendor label that would be passed to the driver.
    public var resolvedModelLabel: String?
    /// `readOnly` or `mutating` — permission after selectors resolve (Law 7).
    public var writePolicy: String
    /// Resolved effect booleans for the spend twin.
    public var effects: Effects
    public var lane: String?
    public var counts: Counts
    public var writeLockHeld: Bool?
    public var warnings: [String]
    public var nextAction: AgentNextAction
    /// ADP-S02 — additive OPTIONAL teaching field. When the resolution is a bare
    /// prompt ask (no `--team`) that lands mutating-allowed, this carries the ready
    /// research-team invocation the caller can run for observational input. This is
    /// advisory (Menu-Not-Router: alln discloses, caller chooses — no auto-routing,
    /// no write-policy change). Omitted (nil) whenever there is nothing to teach, so
    /// the field is additive and does not change the shape for existing callers.
    public var alternatives: [Alternative]?
    /// Resolved seats for team runs (capability-only + lead + scout).
    /// Omitted when empty or for bare execution/default-chat single-seat previews
    /// that do not project crew seating.
    public var seats: [Seat]?

    /// One resolved seat after team staffing (dry-run visibility only).
    public struct Seat: Codable, Sendable, Equatable {
        public var modelId: String
        public var family: String
        public var driverId: String
        public var skillId: String?
        public var stage: String
        /// Why this model won the seat, e.g. `preferred`, `band+unusedFamily`.
        public var reason: String

        public init(
            modelId: String,
            family: String,
            driverId: String,
            skillId: String? = nil,
            stage: String,
            reason: String
        ) {
            self.modelId = modelId
            self.family = family
            self.driverId = driverId
            self.skillId = skillId
            self.stage = stage
            self.reason = reason
        }
    }

    /// One ready-to-run alternative invocation. Same tokenized-argv teaching shape
    /// as `ResolvedRunInvocation` (`argvTemplate` + `templateVariables`), plus the
    /// shell-joined `command` for direct display.
    public struct Alternative: Codable, Sendable, Equatable {
        /// Stable machine tag for the alternative, e.g. `readOnlyAnswerTeam`.
        public var kind: String
        public var label: String
        /// Shell-joined teaching command (sensitive prose stays a `{name}` token).
        public var command: String
        /// Tokenized replay argv; callers substitute `templateVariables`.
        public var argvTemplate: [String]
        /// Declared sensitive placeholders referenced by `argvTemplate` tokens.
        public var templateVariables: [String: String]

        public init(
            kind: String,
            label: String,
            command: String,
            argvTemplate: [String],
            templateVariables: [String: String]
        ) {
            self.kind = kind
            self.label = label
            self.command = command
            self.argvTemplate = argvTemplate
            self.templateVariables = templateVariables
        }
    }

    /// Boolean effects after flags + selection resolve. `repoWrite` is permission
    /// (may write / uses write safety), not an observed `repoDelta`.
    public struct Effects: Codable, Sendable, Equatable {
        public var workerStart: Bool
        public var quotaSpend: Bool
        public var repoWrite: Bool
        public var destructive: Bool
        public var humanInteraction: Bool

        public init(
            workerStart: Bool,
            quotaSpend: Bool,
            repoWrite: Bool,
            destructive: Bool,
            humanInteraction: Bool
        ) {
            self.workerStart = workerStart
            self.quotaSpend = quotaSpend
            self.repoWrite = repoWrite
            self.destructive = destructive
            self.humanInteraction = humanInteraction
        }
    }

    public struct Counts: Codable, Sendable, Equatable {
        public var readyWorkers: Int
        public var blockedWorkers: Int
        public var resolvedSourceIds: Int
        public var seatCount: Int

        public init(readyWorkers: Int, blockedWorkers: Int, resolvedSourceIds: Int, seatCount: Int) {
            self.readyWorkers = readyWorkers
            self.blockedWorkers = blockedWorkers
            self.resolvedSourceIds = resolvedSourceIds
            self.seatCount = seatCount
        }
    }

    public init(
        schemaVersion: Int = 2,
        canStart: Bool,
        blockedReason: String? = nil,
        projectId: String? = nil,
        projectRoot: String? = nil,
        teamPresetId: String? = nil,
        teamDisplayName: String? = nil,
        modelId: String? = nil,
        resolvedPinModelId: String? = nil,
        resolvedModelLabel: String? = nil,
        writePolicy: RunWritePolicy = .readOnly,
        effects: Effects,
        lane: String? = nil,
        counts: Counts = .init(readyWorkers: 0, blockedWorkers: 0, resolvedSourceIds: 0, seatCount: 0),
        writeLockHeld: Bool? = nil,
        warnings: [String] = [],
        nextAction: AgentNextAction,
        alternatives: [Alternative]? = nil,
        seats: [Seat]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.canStart = canStart
        self.blockedReason = blockedReason
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.teamPresetId = teamPresetId
        self.teamDisplayName = teamDisplayName
        self.modelId = modelId
        self.resolvedPinModelId = resolvedPinModelId
        self.resolvedModelLabel = resolvedModelLabel
        self.writePolicy = writePolicy.rawValue
        self.effects = effects
        self.lane = lane
        self.counts = counts
        self.writeLockHeld = writeLockHeld
        self.warnings = warnings
        self.nextAction = nextAction
        self.alternatives = alternatives
        self.seats = seats
    }
}

public extension ContractRegistry.EffectProfile {
    /// Resolve registry effect levels into dry-run booleans.
    /// - `spending`: false for the free twin (`--dry-run`); true for the spend path.
    /// - `repoWritePermitted`: selection write policy (`mutating` → true).
    func resolve(spending: Bool, repoWritePermitted: Bool) -> RunDryRunJSON.Effects {
        func bool(_ level: ContractRegistry.EffectLevel) -> Bool {
            switch level {
            case .never: return false
            case .always: return true
            case .dependsOnFlags: return spending
            case .dependsOnSelection: return repoWritePermitted
            }
        }
        return RunDryRunJSON.Effects(
            workerStart: bool(workerStart),
            quotaSpend: bool(quotaSpend),
            repoWrite: bool(repoWrite),
            destructive: bool(destructive),
            humanInteraction: bool(humanInteraction)
        )
    }
}
