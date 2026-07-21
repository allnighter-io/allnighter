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
    public var workerId: String?
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
    /// answer-team invocation the caller can run instead for a mechanical read-only
    /// guarantee (Menu-Not-Router: alln discloses, caller chooses — no auto-routing,
    /// no write-policy change). Omitted (nil) whenever there is nothing to teach, so
    /// the field is additive and does not change the shape for existing callers.
    public var alternatives: [Alternative]?

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
        workerId: String? = nil,
        writePolicy: RunWritePolicy = .readOnly,
        effects: Effects,
        lane: String? = nil,
        counts: Counts = .init(readyWorkers: 0, blockedWorkers: 0, resolvedSourceIds: 0, seatCount: 0),
        writeLockHeld: Bool? = nil,
        warnings: [String] = [],
        nextAction: AgentNextAction,
        alternatives: [Alternative]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.canStart = canStart
        self.blockedReason = blockedReason
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.teamPresetId = teamPresetId
        self.teamDisplayName = teamDisplayName
        self.workerId = workerId
        self.writePolicy = writePolicy.rawValue
        self.effects = effects
        self.lane = lane
        self.counts = counts
        self.writeLockHeld = writeLockHeld
        self.warnings = warnings
        self.nextAction = nextAction
        self.alternatives = alternatives
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
