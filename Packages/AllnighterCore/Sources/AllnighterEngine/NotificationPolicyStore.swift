import Foundation
import AllnighterCore

/// Persists notification preferences under `AllnighterPaths.config` (NOTIF-S01).
public struct NotificationPolicyStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.config.appendingPathComponent("notification_policy.json")
    }

    public func load() -> NotificationPolicy {
        guard let data = try? Data(contentsOf: fileURL),
              let policy = try? CoreJSON.decode(NotificationPolicy.self, from: data) else {
            return NotificationPolicy()
        }
        return policy
    }

    @discardableResult
    public func save(_ policy: NotificationPolicy) throws -> URL {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try CoreJSON.encode(policy).write(to: fileURL)
        return fileURL
    }
}
