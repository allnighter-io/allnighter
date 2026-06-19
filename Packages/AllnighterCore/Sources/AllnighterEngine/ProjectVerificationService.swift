import Foundation
import AllnighterCore

/// PRJ-S12: turn a `WorkReturn` into a `VerificationRecord`. "Done" requires
/// `verified` or an explicit human waiver — a worker's "done" claim can trigger
/// verification but never completes it.
///
/// Verification runs the work order's DECLARED proof commands as bounded
/// subprocesses at the project root (the user's own shell — Allnighter adds no
/// implicit network, privilege, or commands the user did not declare), captures
/// each exit code / output tail / timeout, and observes git. A non-zero exit, a
/// timeout, or a command Allnighter could not run yields `notVerified`/`needsHuman`
/// — NEVER `verified`. Proof commands never mutate git or clean the tree; this
/// service only runs what was declared and observes — it performs no git writes.
public struct ProjectVerificationService: Sendable {
    private let runner: CommandRunner
    private let perCommandTimeout: Duration
    private let git: GitObserver
    private let now: @Sendable () -> Date

    public init(
        runner: CommandRunner,
        perCommandTimeout: Duration = .seconds(120),
        git: GitObserver = GitObserver(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runner = runner
        self.perCommandTimeout = perCommandTimeout
        self.git = git
        self.now = now
    }

    /// `runProof: false` is reveal-only — the user runs proof themselves; the
    /// outcome is `waived` (if the order carries a waiver) or `needsHuman`.
    public func verify(
        workOrder: WorkOrder,
        workReturn: WorkReturn?,
        project: Project,
        runProof: Bool = true
    ) async -> VerificationRecord {
        let rootPath = workOrder.localRootPathSnapshot.isEmpty ? project.normalizedRootPath : workOrder.localRootPathSnapshot
        let obs = git.observe(rootPath: rootPath)
        let gitObservation = GitObservation(head: obs.head, committed: obs.head != nil, dirty: obs.dirtySummary != nil)

        func record(outcome: VerificationOutcome, proofResults: [ProofResult], missing: [String], recommendation: String) -> VerificationRecord {
            VerificationRecord(
                id: "ver_" + UUID().uuidString.prefix(8).lowercased(),
                projectId: project.id, workOrderId: workOrder.id, returnId: workReturn?.id,
                outcome: outcome, proofResults: proofResults, gitObservation: gitObservation,
                scopeFindings: [], docsDriftFindings: [], missingProof: missing,
                recommendation: recommendation, createdAt: now())
        }

        // Reveal-only: the user runs proof. Waived if the order declared a waiver.
        if !runProof {
            if let waiver = workOrder.proofWaiver, !waiver.isEmpty {
                return record(outcome: .waived, proofResults: [], missing: [], recommendation: "Proof waived (reveal-only): \(waiver)")
            }
            return record(outcome: .needsHuman, proofResults: [], missing: workOrder.proofCommands,
                          recommendation: "Reveal-only: run the proof commands yourself, then re-verify or waive.")
        }

        // No commands → waived (explicit waiver) or needs-human (nothing to run).
        guard !workOrder.proofCommands.isEmpty else {
            if let waiver = workOrder.proofWaiver, !waiver.isEmpty {
                return record(outcome: .waived, proofResults: [], missing: [], recommendation: "Proof waived: \(waiver)")
            }
            return record(outcome: .needsHuman, proofResults: [], missing: [],
                          recommendation: "No proof commands declared and no waiver; a human must confirm or waive.")
        }

        // Run each declared command as a bounded subprocess at the project root.
        var results: [ProofResult] = []
        var couldNotRun: [String] = []
        for cmd in workOrder.proofCommands {
            let result = await runner.run(
                command: "/bin/sh", args: ["-c", cmd], stdin: nil, env: [:],
                workingDirectory: rootPath, timeout: perCommandTimeout)
            if let launchError = result.launchError {
                couldNotRun.append(cmd)
                results.append(ProofResult(command: cmd, exitCode: nil, outputTail: tail(launchError), timedOut: false))
                continue
            }
            results.append(ProofResult(
                command: cmd,
                exitCode: result.exitCode.map(Int.init),
                outputTail: tail(result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr)),
                timedOut: result.timedOut))
        }

        // Allnighter could not execute a declared command → needs a human, not a fail.
        if !couldNotRun.isEmpty {
            return record(outcome: .needsHuman, proofResults: results, missing: couldNotRun,
                          recommendation: "Allnighter could not run \(couldNotRun.count) proof command(s); run them yourself or fix the environment, then re-verify.")
        }
        // Any non-zero exit or timeout → not verified. Never claim done on failure.
        if results.contains(where: { !$0.passed }) {
            let failing = results.filter { !$0.passed }.map { $0.command }
            return record(outcome: .notVerified, proofResults: results, missing: [],
                          recommendation: "Proof failed (\(failing.joined(separator: ", "))). Do not mark done; inspect the failing output.")
        }
        // All declared proof passed.
        let commitNote = gitObservation.committed ? "" : " (no commit observed — proof-verified only, not commit-verified)"
        return record(outcome: .verified, proofResults: results, missing: [],
                      recommendation: "All declared proof passed\(commitNote). Safe to mark done.")
    }

    private func tail(_ s: String, max: Int = 2000) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count <= max ? trimmed : "…" + String(trimmed.suffix(max))
    }
}
