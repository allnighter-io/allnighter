import Foundation

public enum RemoteSupabaseSessionStoreError: Error, Equatable, Sendable {
    case corruptFile(String)
}

public final class RemoteSupabaseSessionStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base
                .appendingPathComponent("Allnighter", isDirectory: true)
                .appendingPathComponent("Config", isDirectory: true)
                .appendingPathComponent("Remote", isDirectory: true)
                .appendingPathComponent("supabase_session.json")
        }
        self.fileManager = fileManager
    }

    public func load() throws -> RemoteSupabaseSession? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try CoreJSON.decode(RemoteSupabaseSession.self, from: Data(contentsOf: fileURL))
        } catch {
            throw RemoteSupabaseSessionStoreError.corruptFile(fileURL.lastPathComponent)
        }
    }

    @discardableResult
    public func save(_ session: RemoteSupabaseSession) throws -> URL {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CoreJSON.encode(session).write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}

public extension RemoteSupabaseSession {
    func makeEnvironment(
        publicConfig: RemoteSupabasePublicConfig.Values,
        macAgentId: String? = nil,
        macDisplayName: String? = nil,
        deviceAccessToken: String? = nil
    ) -> RemoteSupabaseEnvironment {
        RemoteSupabaseEnvironment(
            supabaseURL: publicConfig.supabaseURL,
            publishableKey: publicConfig.publishableKey,
            accessToken: accessToken,
            accountId: userId,
            accountProvider: provider,
            macAgentId: macAgentId,
            macDisplayName: macDisplayName,
            deviceAccessToken: deviceAccessToken ?? accessToken
        )
    }
}
