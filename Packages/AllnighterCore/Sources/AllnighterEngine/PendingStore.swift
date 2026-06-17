import Foundation
import AllnighterCore

/// Local persistence for Pending items beside thread/run history.
public final class PendingStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.pending, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public var indexURL: URL { rootDirectory.appendingPathComponent("index.json") }

    public func itemURL(for id: String) -> URL {
        rootDirectory.appendingPathComponent("\(id).json")
    }

    public func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public func isWritable() -> Bool {
        (try? ensureRoot()) != nil && fileManager.isWritableFile(atPath: rootDirectory.path)
    }

    public func loadIndex() throws -> PendingStoreIndex {
        try ensureRoot()
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return PendingStoreIndex()
        }
        return try CoreJSON.decode(PendingStoreIndex.self, from: Data(contentsOf: indexURL))
    }

    public func saveIndex(_ index: PendingStoreIndex) throws {
        try ensureRoot()
        try CoreJSON.encode(index).write(to: indexURL)
    }

    public func load(id: String) throws -> PendingItem? {
        let url = itemURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try CoreJSON.decode(PendingItem.self, from: Data(contentsOf: url))
    }

    public func save(_ item: PendingItem) throws {
        try ensureRoot()
        try CoreJSON.encode(item).write(to: itemURL(for: item.id))
    }

    public func delete(id: String) throws {
        try? fileManager.removeItem(at: itemURL(for: id))
    }

    public func loadAll() throws -> [PendingItem] {
        var index = try loadIndex()
        if index.itemOrder.isEmpty {
            let ids = try listItemIdsOnDisk()
            index.itemOrder = ids
            if !ids.isEmpty { try saveIndex(index) }
        }
        return index.itemOrder.compactMap { try? load(id: $0) }
    }

    public func loadOrdered(index: PendingStoreIndex? = nil) throws -> (items: [PendingItem], index: PendingStoreIndex) {
        var idx = try index ?? loadIndex()
        let onDisk = try listItemIdsOnDisk()
        for id in onDisk where !idx.itemOrder.contains(id) {
            idx.itemOrder.append(id)
        }
        idx.itemOrder.removeAll { !onDisk.contains($0) }
        let items = idx.itemOrder.compactMap { try? load(id: $0) }
        return (items, idx)
    }

    private func listItemIdsOnDisk() throws -> [String] {
        try ensureRoot()
        let urls = try fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
