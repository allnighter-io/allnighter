import Foundation

/// Local timing ladder for one run. It is persisted inside `run.json` so a slow
/// dogfood run can be inspected after the fact without replaying logs.
public struct RunTimingReport: Codable, Sendable, Equatable {
    public var events: [RunTimingEvent]
    public var counters: [String: Int]
    public var facts: [String: JSONValue]

    public init(
        events: [RunTimingEvent] = [],
        counters: [String: Int] = [:],
        facts: [String: JSONValue] = [:]
    ) {
        self.events = events
        self.counters = counters
        self.facts = facts
    }

    public mutating func stamp(_ name: String, at: Date = Date(), detail: String? = nil) {
        events.append(RunTimingEvent(name: name, at: at, detail: detail))
    }

    public mutating func stampOnce(_ name: String, at: Date = Date(), detail: String? = nil) {
        guard !events.contains(where: { $0.name == name }) else { return }
        stamp(name, at: at, detail: detail)
    }

    public mutating func count(_ name: String, by amount: Int = 1) {
        counters[name, default: 0] += amount
    }

    public mutating func set(_ name: String, _ value: JSONValue) {
        facts[name] = value
    }

    public mutating func set(_ name: String, string: String?) {
        facts[name] = string.map(JSONValue.string) ?? .null
    }

    public mutating func set(_ name: String, int: Int?) {
        facts[name] = int.map(JSONValue.int) ?? .null
    }

    public mutating func set(_ name: String, bool: Bool) {
        facts[name] = .bool(bool)
    }

    public mutating func merge(_ other: RunTimingReport?) {
        guard let other else { return }
        events.append(contentsOf: other.events)
        for (key, value) in other.counters {
            counters[key, default: 0] += value
        }
        for (key, value) in other.facts {
            facts[key] = value
        }
    }

    public func event(named name: String) -> RunTimingEvent? {
        events.first { $0.name == name }
    }
}

public struct RunTimingEvent: Codable, Sendable, Equatable {
    public var name: String
    public var at: Date
    public var detail: String?

    public init(name: String, at: Date, detail: String? = nil) {
        self.name = name
        self.at = at
        self.detail = detail
    }
}

public enum RunTimingKey {
    public static let composerSubmit = "composer.submit"
    public static let threadUserTurnPersisted = "thread.userTurn.persisted"
    public static let threadWorkerTurnPersisted = "thread.workerTurn.persisted"
    public static let contextBuildStart = "context.build.start"
    public static let contextBuildEnd = "context.build.end"
    public static let runRequested = "run.requested"
    public static let workerResolveStart = "worker.resolve.start"
    public static let workerResolveEnd = "worker.resolve.end"
    public static let driverCommandResolved = "driver.command.resolved"
    public static let processSpawnStart = "process.spawn.start"
    public static let firstStderr = "first.stderr"
    public static let firstStdoutChunk = "first.stdout.chunk"
    public static let firstParsedEvent = "first.parsed.event"
    public static let firstAnswerDelta = "first.answer.delta"
    public static let firstUIPublish = "first.ui.publish"
    public static let lastAnswerDelta = "last.answer.delta"
    public static let processExit = "process.exit"
    public static let runOutcomePersisted = "run.outcome.persisted"
    public static let threadTurnSettlementStart = "thread.turn.settlement.start"
    public static let threadTurnSettlementEnd = "thread.turn.settlement.end"
    public static let threadTurnSettlementError = "thread.turn.settlement.error"

    public static let contextBytes = "context.bytes"
    public static let contextTurnCount = "context.turnCount"
    public static let contextFileReferenceCount = "context.fileReferenceCount"
    public static let modelId = "model.id"
    public static let modelDisplayName = "model.displayName"
    public static let sourceId = "source.id"
    public static let commandModelFlag = "driver.commandModelFlag"
    public static let streamingCapable = "driver.streamingCapable"

    public static let rawStdoutChunks = "raw.stdout.chunks"
    public static let rawStderrChunks = "raw.stderr.chunks"
    public static let parsedStreamEvents = "parsed.stream.events"
    public static let answerDeltaCount = "answer.delta.count"
    public static let reasoningDeltaCount = "reasoning.delta.count"
    public static let uiPublishCount = "ui.publish.count"
    public static let threadStoreGetCount = "ThreadStore.get.count"
    public static let threadStoreUpdateTurnCount = "ThreadStore.updateTurn.count"
    public static let threadStoreListCount = "ThreadStore.list.count"
    public static let runStoreSaveCount = "RunStore.save.count"
}

public actor RunTimingAccumulator {
    private var report: RunTimingReport

    public init(_ report: RunTimingReport = RunTimingReport()) {
        self.report = report
    }

    public func stamp(_ name: String, at: Date = Date(), detail: String? = nil) {
        report.stamp(name, at: at, detail: detail)
    }

    public func stampOnce(_ name: String, at: Date = Date(), detail: String? = nil) {
        report.stampOnce(name, at: at, detail: detail)
    }

    public func count(_ name: String, by amount: Int = 1) {
        report.count(name, by: amount)
    }

    public func set(_ name: String, _ value: JSONValue) {
        report.set(name, value)
    }

    public func snapshot() -> RunTimingReport {
        report
    }
}
