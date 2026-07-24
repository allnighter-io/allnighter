import Foundation
import AllnighterCore

/// A durable, same-install request for the resident process to drain before
/// launchd replaces its executable image. The request is intentionally local to
/// Allnighter-owned coordinator state; clients never signal the process directly.
public struct ResidentCoordinatorRestartRequest: Codable, Equatable, Sendable {
    public var requestedAt: Date
    public var binaryVersion: String
    public var contractVersion: String

    public init(
        requestedAt: Date = Date(),
        binaryVersion: String,
        contractVersion: String
    ) {
        self.requestedAt = requestedAt
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
    }
}

public struct ResidentCoordinatorRestartStore: Sendable {
    public let directory: URL
    public var requestFile: URL { directory.appendingPathComponent("restart-request.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? AllnighterPaths.coordinator
    }

    public func request(_ request: ResidentCoordinatorRestartRequest) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(request).write(to: requestFile, options: .atomic)
    }

    public func load() -> ResidentCoordinatorRestartRequest? {
        guard let data = try? Data(contentsOf: requestFile) else { return nil }
        return try? CoreJSON.decode(ResidentCoordinatorRestartRequest.self, from: data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: requestFile)
    }
}
