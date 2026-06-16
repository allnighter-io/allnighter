import Foundation

/// Projects the `ContractRegistry` into the checked-in generated artifacts
/// (docs/phases/CLI_Implementation_Contract.md §Generated Artifacts).
///
/// These are *derived* — change the registry, then regenerate; never hand-edit
/// the artifacts. `alln dev export-contracts --check` fails when the on-disk
/// artifacts drift from the registry.
///
/// This slice projects the registry-backed JSON artifacts. The JSON-Schema files
/// (team-run.schema.json, doctor-result.schema.json) and the human markdown spec
/// are a follow-on generator slice.
public enum ContractExport {
    public struct Artifact: Sendable, Equatable {
        public let filename: String   // relative to docs/generated/alln/
        public let contents: String
        public init(filename: String, contents: String) {
            self.filename = filename; self.contents = contents
        }
    }

    /// The directory (relative to the repo root) the artifacts live under.
    public static let generatedDir = "docs/generated/alln"

    public static func artifacts(_ registry: ContractRegistry = .milestone1) throws -> [Artifact] {
        [
            Artifact(filename: "alln-contract.json", contents: try jsonString(registry)),
            Artifact(filename: "error-codes.json", contents: try jsonString(registry.errors)),
            Artifact(filename: "ndjson-events.json", contents: try jsonString(registry.events)),
            Artifact(filename: "example-recipes.json", contents: try jsonString(registry.examples)),
        ]
    }

    /// Canonical serialization: CoreJSON (pretty + sorted keys) with a trailing
    /// newline. Export and `--check` must use this exact form so byte comparison
    /// is meaningful.
    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try CoreJSON.encode(value), as: UTF8.self) + "\n"
    }
}
