import Foundation

// MARK: - Stalled work contract (SWW-S00)

public enum StallTargetKind: String, Codable, Sendable, CaseIterable {
    case workerTurn
    case teamRun
}

public enum StallEpisodeStatus: String, Codable, Sendable, CaseIterable {
    case active, snoozed, cleared
}

public enum StallReason: String, Codable, Sendable, CaseIterable {
    case queuedNoStart
    case runningNoProgress
    case statusUnknownNoProgress
}

public enum StallClearedBy: String, Codable, Sendable, CaseIterable {
    case terminalResult, userCancel, userRetry, userDismiss, refreshedOut, targetDeleted
}

public struct StallObservableEvent: Codable, Sendable, Equatable {
    public var at: Date
    public var kind: String
    public var source: String
    public var summary: String

    public init(at: Date, kind: String, source: String, summary: String) {
        self.at = at; self.kind = kind; self.source = source; self.summary = summary
    }
}

public struct StallEpisode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var targetKind: StallTargetKind
    public var targetId: String
    public var threadId: String
    public var runId: String?
    public var status: StallEpisodeStatus
    public var reason: StallReason
    public var firstDetectedAt: Date
    public var deadlineAnchorAt: Date
    public var thresholdSeconds: Int
    public var lastObservableEvent: StallObservableEvent
    public var lastRefreshAt: Date?
    public var lastNudgeTurnId: String?
    public var lastNudgeAt: Date?
    public var snoozedUntil: Date?
    public var clearedAt: Date?
    public var clearedBy: StallClearedBy?
    public var primaryAction: String
    public var secondaryActions: [String]

    public init(
        id: String,
        projectId: String,
        targetKind: StallTargetKind,
        targetId: String,
        threadId: String,
        runId: String? = nil,
        status: StallEpisodeStatus = .active,
        reason: StallReason,
        firstDetectedAt: Date,
        deadlineAnchorAt: Date,
        thresholdSeconds: Int,
        lastObservableEvent: StallObservableEvent,
        lastRefreshAt: Date? = nil,
        lastNudgeTurnId: String? = nil,
        lastNudgeAt: Date? = nil,
        snoozedUntil: Date? = nil,
        clearedAt: Date? = nil,
        clearedBy: StallClearedBy? = nil,
        primaryAction: String,
        secondaryActions: [String] = []
    ) {
        self.id = id
        self.projectId = projectId
        self.targetKind = targetKind
        self.targetId = targetId
        self.threadId = threadId
        self.runId = runId
        self.status = status
        self.reason = reason
        self.firstDetectedAt = firstDetectedAt
        self.deadlineAnchorAt = deadlineAnchorAt
        self.thresholdSeconds = thresholdSeconds
        self.lastObservableEvent = lastObservableEvent
        self.lastRefreshAt = lastRefreshAt
        self.lastNudgeTurnId = lastNudgeTurnId
        self.lastNudgeAt = lastNudgeAt
        self.snoozedUntil = snoozedUntil
        self.clearedAt = clearedAt
        self.clearedBy = clearedBy
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }
}

public struct StallEpisodeListJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projectId: String?
    public var episodes: [StallEpisode]

    public init(schemaVersion: Int = 1, contractVersion: String, projectId: String? = nil, episodes: [StallEpisode]) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.projectId = projectId
        self.episodes = episodes
    }
}

public struct StallListJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projects: [StallProjectGroup]

    public init(schemaVersion: Int = 1, contractVersion: String, projects: [StallProjectGroup]) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.projects = projects
    }
}

public struct StallProjectGroup: Codable, Sendable, Equatable {
    public var projectId: String
    public var projectName: String?
    public var episodes: [StallEpisode]

    public init(projectId: String, projectName: String? = nil, episodes: [StallEpisode]) {
        self.projectId = projectId
        self.projectName = projectName
        self.episodes = episodes
    }
}
