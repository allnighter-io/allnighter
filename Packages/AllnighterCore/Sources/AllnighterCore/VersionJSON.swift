import Foundation

/// `alln version` / `alln --version` machine contract.
public struct VersionJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var binaryVersion: String
    public var contractVersion: String
    public var contractHash: String

    public init(
        schemaVersion: Int = 1,
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        contractHash: String = ContractRegistry.contractHash()
    ) {
        self.schemaVersion = schemaVersion
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
    }
}
