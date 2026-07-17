import Foundation

/// Projects the `ContractRegistry` into the checked-in generated artifacts
/// (docs/phases/CLI_Implementation_Contract.md §Generated Artifacts).
///
/// These are *derived* — change the registry, then regenerate; never hand-edit
/// the artifacts. `alln dev export-contracts --check` fails when the on-disk
/// artifacts drift from the registry.
///
/// Projects the registry-backed JSON artifacts, the JSON-Schema files for the
/// public types, and the human markdown reference.
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
            Artifact(filename: "team-run.schema.json", contents: try ContractSchema.json(ContractSchema.teamRunSchema())),
            Artifact(filename: "doctor-result.schema.json", contents: try ContractSchema.json(ContractSchema.doctorResultSchema())),
            Artifact(filename: "coordinator-health.schema.json", contents: try ContractSchema.json(ContractSchema.coordinatorHealthSchema())),
            Artifact(filename: "pending-item.schema.json", contents: try ContractSchema.json(ContractSchema.pendingItemSchema())),
            Artifact(filename: "model-list.schema.json", contents: try ContractSchema.json(ContractSchema.modelListSchema())),
            Artifact(filename: "version.schema.json", contents: try ContractSchema.json(ContractSchema.versionSchema())),
            Artifact(filename: "floor-run.schema.json", contents: try ContractSchema.json(ContractSchema.floorRunSchema())),
            Artifact(filename: "spec-result.schema.json", contents: try ContractSchema.json(ContractSchema.specResultSchema())),
            Artifact(filename: "team-catalog.schema.json", contents: try ContractSchema.json(ContractSchema.teamCatalogSchema())),
            Artifact(filename: "skill-catalog.schema.json", contents: try ContractSchema.json(ContractSchema.skillCatalogSchema())),
            Artifact(filename: "history.schema.json", contents: try ContractSchema.json(ContractSchema.historySchema())),
            Artifact(filename: "thread-status.schema.json", contents: try ContractSchema.json(ContractSchema.threadStatusSchema())),
            Artifact(filename: "thread-get.schema.json", contents: try ContractSchema.json(ContractSchema.threadGetSchema())),
            Artifact(filename: "thread-attachment.schema.json", contents: try ContractSchema.json(ContractSchema.threadAttachmentSchema())),
            Artifact(filename: "ownership-ps.schema.json", contents: try ContractSchema.json(ContractSchema.ownershipPsSchema())),
            Artifact(filename: "ownership-kill.schema.json", contents: try ContractSchema.json(ContractSchema.ownershipKillSchema())),
            Artifact(filename: "help_alln_cli_spec.md", contents: ContractDocs.markdown(registry)),
        ]
    }

    /// Canonical serialization: CoreJSON (pretty + sorted keys) with a trailing
    /// newline. Export and `--check` must use this exact form so byte comparison
    /// is meaningful.
    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try CoreJSON.encode(value), as: UTF8.self) + "\n"
    }
}
