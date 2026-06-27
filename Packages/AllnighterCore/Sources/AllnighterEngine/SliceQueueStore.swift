import Foundation
import AllnighterCore

/// Durable on-disk slice queue (RunStore folder pattern).
public struct SliceQueueStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func load() throws -> SliceQueue {
        let url = queueURL
        guard FileManager.default.fileExists(atPath: url.path) else { return SliceQueue() }
        let data = try Data(contentsOf: url)
        return try CoreJSON.decode(SliceQueue.self, from: data)
    }

    @discardableResult
    public func save(_ queue: SliceQueue) throws -> URL {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try CoreJSON.encode(queue).write(to: queueURL, options: .atomic)
        return queueURL
    }

    /// Load every `*.json` packet in a directory as pending queue entries.
    public static func loadPackets(from directory: URL) throws -> [WorkSlicePacket] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { try WorkSlicePacketParser.parseFile(at: $0.path) }
    }

    public static func bootstrapQueue(from directory: URL) throws -> SliceQueue {
        let packets = try loadPackets(from: directory)
        return SliceQueue(entries: packets.map { SliceQueueEntry(packet: $0) })
    }

    private var queueURL: URL {
        rootDirectory.appendingPathComponent("queue.json")
    }
}
