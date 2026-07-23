import Foundation

/// ADP-S05: single source of truth for the alln binary version. Everything
/// that discloses a version string for the binary itself — `AllnighterCLI.
/// binaryVersion`, the Codex `clientInfo` handshake, `doctor`, `version
/// --json` — projects this constant. Never hardcode a second semver literal
/// for a binary-version/clientInfo field; `VersionIdentityTests` gates it.
///
/// Bump rule (docs/phases/Agent_Dogfood_Papercuts.md §Version rule): patch
/// (+0.0.1) on every shipped batch of behavior/teaching changes; minor
/// (+0.1.0) only when `contractVersion` takes a major cut. Distinct from
/// `ContractRegistry.contractVersion`, which is schema-shape governed and
/// never substitutes for this.
public enum AllnighterVersionIdentity {
    public static let binaryVersion = "0.9.4"
}

/// `alln version` / `alln --version` machine contract.
public struct VersionJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var binaryVersion: String
    public var contractVersion: String
    public var contractHash: String
    /// Short or full git SHA embedded at build time (`unknown` when unavailable).
    public var gitSha: String?
    /// UTC build timestamp (`YYYY-MM-DDTHH:MM:SSZ`), or `unknown`.
    public var buildTime: String?
    /// Absolute path of the running binary (AE-S08).
    public var binaryPath: String?

    public init(
        schemaVersion: Int = 1,
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        contractHash: String = ContractRegistry.contractHash(),
        gitSha: String? = nil,
        buildTime: String? = nil,
        binaryPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.gitSha = gitSha
        self.buildTime = buildTime
        self.binaryPath = binaryPath
    }
}
