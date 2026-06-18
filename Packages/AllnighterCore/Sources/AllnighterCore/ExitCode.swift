import Foundation

/// The single source of truth for `alln` process exit codes (M-C). Shells and
/// non-JSON callers branch on these without parsing output. Exit codes above `2`
/// are reserved — do not introduce new ones (see
/// `docs/phases/CLI_Implementation_Contract.md` §Process exit codes).
public enum ExitCode {
    /// The command completed. Under `--json` the envelope is a success payload.
    public static let success: Int32 = 0
    /// Well-formed command, but the operation failed or an entity was unavailable.
    public static let operationalFailure: Int32 = 1
    /// The command/subcommand/flag/argument was invalid before any work started.
    public static let usageError: Int32 = 2
}

public extension ContractRegistry {
    /// The catalog row for an error code, or `nil` if the code is not registered.
    func errorSpec(for code: String) -> ErrorSpec? {
        errors.first { $0.code == code }
    }

    /// The process exit code for an emitted error code, derived from the catalog so
    /// the code and its exit class can never drift apart. An unregistered code is
    /// treated as `operational` (never crash on emit); `ContractRegistryTests`
    /// asserts every code the CLI can emit is in the catalog.
    func processExitCode(forErrorCode code: String) -> Int32 {
        (errorSpec(for: code)?.exitClass ?? .operational).processExitCode
    }
}
