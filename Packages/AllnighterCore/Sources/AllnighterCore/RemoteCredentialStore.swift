import CryptoKit
import Foundation

public enum RemoteCredentialStoreError: Error, Equatable, Sendable {
    case corruptFile(String)
}

private enum RemoteCredentialPaths {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Allnighter", isDirectory: true)
            .appendingPathComponent("Config", isDirectory: true)
            .appendingPathComponent("Remote", isDirectory: true)
    }
}

public final class RemoteMacAgentCredentialStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? RemoteCredentialPaths.directory
            .appendingPathComponent("mac_agent_credentials.json")
        self.fileManager = fileManager
    }

    public func load() throws -> RemoteMacAgentCredentials? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try CoreJSON.decode(RemoteMacAgentCredentials.self, from: Data(contentsOf: fileURL))
        } catch {
            throw RemoteCredentialStoreError.corruptFile(fileURL.lastPathComponent)
        }
    }

    @discardableResult
    public func save(_ credentials: RemoteMacAgentCredentials) throws -> URL {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CoreJSON.encode(credentials).write(to: fileURL, options: .atomic)
        return fileURL
    }
}

public final class RemoteDeviceCredentialStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? RemoteCredentialPaths.directory
            .appendingPathComponent("device_credentials.json")
        self.fileManager = fileManager
    }

    public func load() throws -> RemoteDeviceCredentials? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try CoreJSON.decode(RemoteDeviceCredentials.self, from: Data(contentsOf: fileURL))
        } catch {
            throw RemoteCredentialStoreError.corruptFile(fileURL.lastPathComponent)
        }
    }

    @discardableResult
    public func save(_ credentials: RemoteDeviceCredentials) throws -> URL {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CoreJSON.encode(credentials).write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func loadOrCreate(displayName: String, deviceId: String? = nil) throws -> (
        credentials: RemoteDeviceCredentials,
        signingKey: Curve25519.Signing.PrivateKey,
        sealingKey: Curve25519.KeyAgreement.PrivateKey
    ) {
        if let existing = try load() {
            return (
                existing,
                try existing.keys.signingKey(),
                try existing.keys.sealingKey()
            )
        }

        let generated = RemoteStoredKeyPair.generate()
        let credentials = RemoteDeviceCredentials(
            deviceId: deviceId ?? UUID().uuidString.lowercased(),
            displayName: displayName,
            keys: generated.material
        )
        try save(credentials)
        return (credentials, generated.signingKey, generated.sealingKey)
    }
}
