//
//  ConversationHomeCache.swift
//  AllnighteriOS
//
//  Plain Codable cache for the conversation home — not durable run truth.
//

import Foundation

struct ConversationHomeCacheEntry: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var accountId: String
    var macAgentId: String
    var serverTime: Date
    var cachedAt: Date
    var snapshot: ConversationListSnapshot

    init(
        accountId: String,
        macAgentId: String,
        serverTime: Date,
        cachedAt: Date = Date(),
        snapshot: ConversationListSnapshot
    ) {
        version = Self.currentVersion
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.serverTime = serverTime
        self.cachedAt = cachedAt
        self.snapshot = snapshot
    }
}

struct ConversationHomeCache {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> ConversationHomeCacheEntry? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        let entry = try decoder.decode(ConversationHomeCacheEntry.self, from: data)
        guard entry.version == ConversationHomeCacheEntry.currentVersion else {
            return nil
        }
        return entry
    }

    func save(_ entry: ConversationHomeCacheEntry) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(entry)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support
            .appendingPathComponent("Allnighter", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("conversation_home.json", isDirectory: false)
    }
}
