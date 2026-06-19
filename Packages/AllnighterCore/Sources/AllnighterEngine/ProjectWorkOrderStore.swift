import Foundation
import AllnighterCore

/// PRJ-S10: durable per-project work orders derived from approved proposals. One
/// JSON file per project. The work order is the dispatchable payload; dispatch
/// itself (S11) re-validates gates before invoking a worker.
public final class ProjectWorkOrderStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectWorkOrders, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId).json")
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public func load(projectId: String) -> [WorkOrder] {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let orders = try? CoreJSON.decode([WorkOrder].self, from: data)
        else { return [] }
        return orders
    }

    /// Resolve by work-order id across all projects (dispatch takes only an id).
    public func find(id: String) -> WorkOrder? {
        guard let entries = try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else { return nil }
        for url in entries where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let orders = try? CoreJSON.decode([WorkOrder].self, from: data),
               let match = orders.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    @discardableResult
    public func upsert(_ order: WorkOrder) throws -> WorkOrder {
        try ensureRoot()
        var all = load(projectId: order.projectId)
        if let idx = all.firstIndex(where: { $0.id == order.id }) { all[idx] = order } else { all.append(order) }
        try CoreJSON.encode(all).write(to: fileURL(projectId: order.projectId), options: .atomic)
        return order
    }
}
