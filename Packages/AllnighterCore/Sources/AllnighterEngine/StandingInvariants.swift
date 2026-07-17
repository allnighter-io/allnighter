import Foundation
import AllnighterCore

/// Harness-owned **standing invariants** for the proof phase
/// (`docs/phases/Process_Ownership.md` PO-F4).
///
/// Distinct from the dev's declared `proofCommands`: the harness always injects
/// this list after a delivered dev turn — even when the dev declared zero proofs.
/// The agent cannot omit them. Failures mark the turn not-clean via
/// `standingFailed` on the round; `endReason` is not rewritten (analogous to
/// `scopeViolation`). Allnighter never auto-regenerates or auto-commits.
///
/// Extensible list — ship only contract-freshness for now.
public enum StandingInvariants {
    /// Contract registry vs checked-in `docs/generated/alln/*` drift.
    public static let contractDrift = "contractDrift"

    /// Relative package path for building the turn's `alln` product (repo root).
    public static let defaultPackagePath = "Packages/AllnighterCore"

    /// Ordered harness-owned invariant ids (only `contractDrift` for now).
    public static var all: [String] { [contractDrift] }

    public struct Outcome: Sendable {
        public var results: [HarnessProofResult]
        /// Invariant ids that failed (non-zero exit, timeout, or missing binary).
        public var failed: [String]

        public init(results: [HarnessProofResult] = [], failed: [String] = []) {
            self.results = results
            self.failed = failed
        }
    }

    /// Run every standing invariant under the same bounded proof runner path
    /// (`ProjectVerificationService` / process-group spawn, timeout, captured tail).
    ///
    /// Uses the `alln` product built on the persistent per-root scratch — never the
    /// installed/global binary — so the check judges **this turn's tree**.
    public static func run(
        service: ProjectVerificationService,
        repoRoot: String,
        scratchPath: String,
        packagePath: String = defaultPackagePath
    ) async -> Outcome {
        var results: [HarnessProofResult] = []
        var failed: [String] = []

        // Extensible: append further invariants here.
        let drift = await runContractFreshness(
            service: service,
            repoRoot: repoRoot,
            scratchPath: scratchPath,
            packagePath: packagePath
        )
        results.append(drift)
        if !drift.passed {
            failed.append(contractDrift)
        }

        return Outcome(results: results, failed: failed)
    }

    // MARK: - contractDrift

    /// Build (if needed) the turn tree's `alln` on the scratch, then run
    /// `<built alln> dev export-contracts --check` at the repo root.
    private static func runContractFreshness(
        service: ProjectVerificationService,
        repoRoot: String,
        scratchPath: String,
        packagePath: String
    ) async -> HarnessProofResult {
        let allnPath: String
        if let existing = findAllnProduct(scratchPath: scratchPath) {
            allnPath = existing
        } else {
            // Build the product onto the persistent scratch before checking.
            let buildCmd =
                "swift build --package-path \(shellSingleQuote(packagePath)) --product alln --scratch-path \(shellSingleQuote(scratchPath))"
            let buildResults = await service.runProofs(
                commands: [buildCmd],
                repoRoot: repoRoot,
                scratchPath: scratchPath
            )
            let build = buildResults.first
            if let build, !build.passed {
                return markStanding(
                    build,
                    command: build.command,
                    invariant: contractDrift
                )
            }
            guard let built = findAllnProduct(scratchPath: scratchPath) else {
                let tail = build?.outputTail ?? ""
                return HarnessProofResult(
                    command: buildCmd,
                    exitCode: 1,
                    durationMs: build?.durationMs ?? 0,
                    outputTail: tail.isEmpty
                        ? "standing invariant contractDrift: alln product missing after build under scratch"
                        : tail,
                    timedOut: build?.timedOut ?? false,
                    standing: true,
                    invariant: contractDrift
                )
            }
            allnPath = built
        }

        let checkCmd = "\(shellSingleQuote(allnPath)) dev export-contracts --check"
        let checkResults = await service.runProofs(
            commands: [checkCmd],
            repoRoot: repoRoot,
            scratchPath: scratchPath
        )
        let check = checkResults.first ?? HarnessProofResult(
            command: checkCmd,
            exitCode: 1,
            durationMs: 0,
            outputTail: "standing invariant contractDrift: no result from export-contracts --check",
            standing: true,
            invariant: contractDrift
        )
        return markStanding(check, command: check.command, invariant: contractDrift)
    }

    // MARK: - Product location

    /// Locate the `alln` executable under a SwiftPM `--scratch-path` tree.
    /// Prefers the config symlink (`scratch/debug/alln`), then triple paths.
    public static func findAllnProduct(scratchPath: String) -> String? {
        let fm = FileManager.default
        let candidates = [
            (scratchPath as NSString).appendingPathComponent("debug/alln"),
            (scratchPath as NSString).appendingPathComponent("release/alln"),
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Triple layout: scratch/<triple>/{debug,release}/alln
        guard let entries = try? fm.contentsOfDirectory(atPath: scratchPath) else {
            return nil
        }
        for entry in entries {
            for config in ["debug", "release"] {
                let path = (scratchPath as NSString)
                    .appendingPathComponent("\(entry)/\(config)/alln")
                if fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func markStanding(
        _ result: HarnessProofResult,
        command: String,
        invariant: String
    ) -> HarnessProofResult {
        HarnessProofResult(
            command: command,
            exitCode: result.exitCode,
            durationMs: result.durationMs,
            outputTail: result.outputTail,
            timedOut: result.timedOut,
            standing: true,
            invariant: invariant
        )
    }

    private static func shellSingleQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
