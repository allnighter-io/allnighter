import Foundation
import AllnighterCore

public enum RemoteRunEventJournalError: Error, Equatable, Sendable {
    case missingRunId(eventId: String)
    case corruptSequence(String)
    case missingIndexedEvent(seq: Int64, runId: String, eventId: String)
    /// Per-run `events.jsonl` hit its explicit retention bound (count or bytes).
    case retentionBoundExceeded(runId: String)
}

public struct RemoteRunEventReplay: Equatable, Sendable {
    public var events: [RunEvent]
    public var lastSeq: Int64

    public init(events: [RunEvent], lastSeq: Int64) {
        self.events = events
        self.lastSeq = lastSeq
    }
}

/// Mac-truth remote event journal. Cloud mirrors may expire; this append-only
/// store owns the monotonic per-Mac sequence used for remote resume.
///
/// ORS-S02a1 — always-on bounded activity history for one run. The journal is
/// derived history of the same run truth owned by `RunStore`; it is never a
/// second run owner and never a public contract surface (no `eventsPath`).
public struct RemoteRunEventJournal: Sendable {
    public let rootDirectory: URL

    /// Max durable event lines per run's `events.jsonl` (ORS binding rule 4).
    /// Status/blocker/stage lifecycle, terminal settlement, and bounded
    /// `worker.tool` summaries (ORS-S02a2) — not a transcript. Tool events are
    /// the highest-frequency durable kind; 512 caps growth. Past the cap further
    /// appends refuse (`retentionBoundExceeded`); the run owner swallows that and
    /// keeps going — history degrades, run truth stays in `RunStore` (rule 8).
    public static let maxEventsPerRun: Int = 512

    /// Max on-disk bytes per run's `events.jsonl` (ORS binding rule 4).
    /// 256 KiB bounds worst-case payload size under a tool-heavy burst.
    public static let maxBytesPerRun: Int = 256 * 1024

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.runs
    }

    /// Minimal durable set (ORS binding rule 2 / ORS-S02a1 + ORS-S02a2):
    /// state transitions and bounded tool summaries that make a run's middle
    /// observable after `--no-wait` reattach. Not a transcript.
    ///
    /// Durable:
    /// - `run.status_changed`, `worker.status_changed` (status/blocker entry and
    ///   terminal settlement)
    /// - `stage.started`, `stage.completed`, `stage.failed`, `stage.reused`
    ///   (stage lifecycle — not transcript)
    /// - `worker.tool` (bounded tool title/name on incremental drivers only)
    ///
    /// Live-only (never persisted): high-frequency / transcript kinds —
    /// `worker.answer_delta`, `worker.reasoning_delta`, `worker.output`, and
    /// `stage.output`. `stage.output` is excluded deliberately: it is stream
    /// body for a stage, not a lifecycle edge; the four stage kinds above are
    /// the edges that mark when a stage begins, ends, fails, or is reused.
    public static func isDurableSemanticEvent(_ kind: String) -> Bool {
        switch kind {
        case RunEventKind.runStatusChanged,
             RunEventKind.workerStatusChanged,
             RunEventKind.workerTool,
             RunEventKind.stageStarted,
             RunEventKind.stageCompleted,
             RunEventKind.stageFailed,
             RunEventKind.stageReused:
            return true
        default:
            return false
        }
    }

    public var globalIndexURL: URL {
        rootDirectory.appendingPathComponent("remote_event_index.jsonl")
    }

    public var sequenceURL: URL {
        rootDirectory.appendingPathComponent("remote_event_seq.txt")
    }

    public var lockURL: URL {
        rootDirectory.appendingPathComponent("remote_event_seq.lock")
    }

    public func append(_ event: RunEvent) throws -> RunEvent {
        let runId = try runId(for: event)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }

        let nextSeq = try lastSeqLocked() + 1
        var persisted = event
        persisted.seq = nextSeq

        try writeLastSeqLocked(nextSeq)
        // ORS-S02a1 rule 4: refuse further durable lines past the per-run cap.
        // Callers that own the always-on path swallow this and keep the run alive.
        let eventsURL = eventsURL(forRunId: runId)
        try enforceRetentionBound(forRunId: runId, eventsURL: eventsURL, nextLine: Self.encodeLine(persisted))
        try appendLine(Self.encodeLine(persisted), to: eventsURL)
        try appendLine(Self.encodeLine(IndexEntry(seq: nextSeq, runId: runId, eventId: event.id)), to: globalIndexURL)
        return persisted
    }

    /// Soft retention gate: refuse further durable lines once count or byte cap
    /// is reached. Callers (RunService) swallow this into a diagnostic and keep
    /// the run alive — history is bounded; run truth lives in `RunStore`.
    private func enforceRetentionBound(forRunId runId: String, eventsURL: URL, nextLine: Data) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: eventsURL.path) else { return }
        let attrs = try fm.attributesOfItem(atPath: eventsURL.path)
        let existingBytes = (attrs[.size] as? NSNumber)?.intValue ?? 0
        // +1 for the trailing newline `appendLine` writes after each record.
        if existingBytes + nextLine.count + 1 > Self.maxBytesPerRun {
            throw RemoteRunEventJournalError.retentionBoundExceeded(runId: runId)
        }
        let raw = try String(contentsOf: eventsURL, encoding: .utf8)
        let existingCount = raw.split(separator: "\n", omittingEmptySubsequences: true).count
        if existingCount >= Self.maxEventsPerRun {
            throw RemoteRunEventJournalError.retentionBoundExceeded(runId: runId)
        }
    }

    public func lastSeq() throws -> Int64 {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }
        return try lastSeqLocked()
    }

    public func events(after seq: Int64, limit: Int? = nil) throws -> [RunEvent] {
        try replay(after: seq, limit: limit).events
    }

    public func replay(after seq: Int64, limit: Int? = nil) throws -> RemoteRunEventReplay {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }

        let entries = try readIndexEntries(after: seq, limit: limit)
        var eventsByRunId: [String: [RunEvent]] = [:]
        var resolvedEvents: [RunEvent] = []

        for entry in entries {
            if eventsByRunId[entry.runId] == nil {
                eventsByRunId[entry.runId] = try events(forRunId: entry.runId, after: seq)
            }
            guard let event = eventsByRunId[entry.runId]?.first(where: {
                $0.seq == entry.seq && $0.id == entry.eventId
            }) else {
                throw RemoteRunEventJournalError.missingIndexedEvent(
                    seq: entry.seq,
                    runId: entry.runId,
                    eventId: entry.eventId
                )
            }
            resolvedEvents.append(event)
        }

        return RemoteRunEventReplay(events: resolvedEvents, lastSeq: try lastSeqLocked())
    }

    public func events(forRunId runId: String, after seq: Int64 = 0, limit: Int? = nil) throws -> [RunEvent] {
        try readEvents(from: eventsURL(forRunId: runId), after: seq, limit: limit)
    }

    public func eventsURL(forRunId runId: String) -> URL {
        rootDirectory
            .appendingPathComponent("run_\(runId)", isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    private func runId(for event: RunEvent) throws -> String {
        guard case let .string(runId)? = event.payload["runId"],
              !runId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteRunEventJournalError.missingRunId(eventId: event.id)
        }
        return runId
    }

    private func lastSeqLocked() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: sequenceURL.path) else { return 0 }
        let raw = try String(contentsOf: sequenceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return 0 }
        guard let seq = Int64(raw), seq >= 0 else {
            throw RemoteRunEventJournalError.corruptSequence(raw)
        }
        return seq
    }

    private func writeLastSeqLocked(_ seq: Int64) throws {
        try Data("\(seq)\n".utf8).write(to: sequenceURL, options: .atomic)
    }

    private func appendLine(_ line: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(line)
        handle.write(Data("\n".utf8))
    }

    private func readEvents(from url: URL, after seq: Int64, limit: Int?) throws -> [RunEvent] {
        if let limit, limit <= 0 { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var events: [RunEvent] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let event = try Self.decodeLine(RunEvent.self, from: Data(line.utf8))
            guard event.seq > seq else { continue }
            events.append(event)
            if let limit, events.count >= limit { break }
        }
        return events
    }

    private func readIndexEntries(after seq: Int64, limit: Int?) throws -> [IndexEntry] {
        if let limit, limit <= 0 { return [] }
        guard FileManager.default.fileExists(atPath: globalIndexURL.path) else { return [] }
        let raw = try String(contentsOf: globalIndexURL, encoding: .utf8)
        var entries: [IndexEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = try Self.decodeLine(IndexEntry.self, from: Data(line.utf8))
            guard entry.seq > seq else { continue }
            entries.append(entry)
            if let limit, entries.count >= limit { break }
        }
        return entries
    }

    private struct IndexEntry: Codable, Equatable, Sendable {
        var seq: Int64
        var runId: String
        var eventId: String
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        try jsonEncoder.encode(value)
    }

    private static func decodeLine<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try jsonDecoder.decode(type, from: data)
    }
}
