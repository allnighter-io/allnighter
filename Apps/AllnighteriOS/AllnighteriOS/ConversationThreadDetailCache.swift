//
//  ConversationThreadDetailCache.swift
//  AllnighteriOS
//
//  Plain Codable cache for decrypted thread presentation snapshots.
//

import Foundation

struct ConversationThreadDetailCacheEntry: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var macAgentId: String
    var threadId: String
    var serverTime: Date
    var cachedAt: Date
    var snapshot: ConversationThreadSnapshot

    init(
        macAgentId: String,
        threadId: String,
        serverTime: Date,
        cachedAt: Date = Date(),
        snapshot: ConversationThreadSnapshot
    ) {
        version = Self.currentVersion
        self.macAgentId = macAgentId
        self.threadId = threadId
        self.serverTime = serverTime
        self.cachedAt = cachedAt
        self.snapshot = snapshot
    }
}

struct ConversationThreadDetailCache {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL()
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load(macAgentId: String, threadId: String) throws -> ConversationThreadDetailCacheEntry? {
        let fileURL = fileURL(macAgentId: macAgentId, threadId: threadId)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        let entry = try decoder.decode(ConversationThreadDetailCacheEntry.self, from: data)
        guard entry.version == ConversationThreadDetailCacheEntry.currentVersion,
              entry.macAgentId == macAgentId,
              entry.threadId == threadId else {
            return nil
        }
        return entry
    }

    func save(_ entry: ConversationThreadDetailCacheEntry) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(entry)
        try data.write(to: fileURL(macAgentId: entry.macAgentId, threadId: entry.threadId), options: .atomic)
    }

    func clear(macAgentId: String, threadId: String) throws {
        let fileURL = fileURL(macAgentId: macAgentId, threadId: threadId)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func fileURL(macAgentId: String, threadId: String) -> URL {
        let safeMac = macAgentId.replacingOccurrences(of: "/", with: "_")
        let safeThread = threadId.replacingOccurrences(of: "/", with: "_")
        return directoryURL.appendingPathComponent("\(safeMac)__\(safeThread).json", isDirectory: false)
    }

    static func defaultDirectoryURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support
            .appendingPathComponent("Allnighter", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("thread_details", isDirectory: true)
    }
}
