import Foundation

/// The single source of truth for `alln` process exit codes (M-C + PO-F3).
/// Shells and non-JSON callers branch on these without parsing output.
///
/// **Stable table — never renumber silently.** Drift is gated by
/// `ExitCodeContractTests.testStableExitCodeTableNeverRenumbered` and the
/// generated `exit-codes.json` artifact. See
/// `docs/phases/CLI_Implementation_Contract.md` §Process exit codes and
/// `docs/phases/Process_Ownership.md` PO-F3.
public enum ExitCode {
    /// The command completed. Under `--json` the envelope is a success payload.
    public static let success: Int32 = 0
    /// Well-formed command, but the operation failed or an entity was unavailable
    /// (run-failed class).
    public static let runFailed: Int32 = 1
    /// Alias kept for pre-PO-F3 call sites; same value as `runFailed`.
    public static let operationalFailure: Int32 = 1
    /// The command/subcommand/flag/argument was invalid before any work started.
    public static let usageError: Int32 = 2
    /// A bounded wait expired before the target condition (status wait, team run
    /// timeout class).
    public static let timeout: Int32 = 3
    /// The per-root execution / write lane stayed busy past the wait bound.
    public static let laneBusy: Int32 = 4

    /// Frozen rows for export + drift tests. Order is the contract; codes are
    /// identity — adding a row is allowed only by extending this list and the
    /// docs table together; renumbering any existing row is a contract break.
    public static let stableTable: [(code: Int32, name: String, meaning: String)] = [
        (0, "success", "Command completed; under --json the envelope is a success payload."),
        (1, "runFailed", "Well-formed command, but the operation failed or the requested entity/state was unavailable."),
        (2, "usageError", "Command/subcommand/flag/argument was invalid before any work started."),
        (3, "timeout", "A bounded wait expired before the target condition (team status --wait-for, team-run time budget)."),
        (4, "laneBusy", "Per-root execution/write lane stayed busy past the wait bound (EXECUTION_LANE_BUSY / RUN_WRITE_LOCK_BUSY)."),
    ]
}

/// Codable projection of `ExitCode.stableTable` for `exit-codes.json` (PO-F3).
public enum ExitCodeExport {
    public struct Row: Codable, Sendable, Equatable {
        public var code: Int
        public var name: String
        public var meaning: String
    }

    public static var rows: [Row] {
        ExitCode.stableTable.map {
            Row(code: Int($0.code), name: $0.name, meaning: $0.meaning)
        }
    }
}

public extension ContractRegistry {
    /// The catalog row for an error code, or `nil` if the code is not registered.
    func errorSpec(for code: String) -> ErrorSpec? {
        errors.first { $0.code == code }
    }

    /// The process exit code for an emitted error code, derived from the catalog so
    /// the code and its exit class can never drift apart. An unregistered code is
    /// treated as `runFailed` / operational (never crash on emit); `ContractRegistryTests`
    /// asserts every code the CLI can emit is in the catalog.
    func processExitCode(forErrorCode code: String) -> Int32 {
        (errorSpec(for: code)?.exitClass ?? .operational).processExitCode
    }
}
