import Foundation

/// One harness-owned proof-of-record result (`docs/phases/Process_Ownership.md` PO-S04).
///
/// Surfaced on relay/pilot `roundLog` as `proofResults[]`. The agent never runs
/// these commands; the harness executes them after the dev turn ends.
public struct HarnessProofResult: Codable, Equatable, Sendable {
    /// The declared command as run (after scratch-path injection when applicable).
    public var command: String
    /// Process exit code, or `nil` on timeout / launch failure.
    public var exitCode: Int?
    /// Wall-clock duration of the harness-owned subprocess, milliseconds.
    public var durationMs: Int
    /// Truncated combined stdout+stderr tail (never the full log).
    public var outputTail: String
    /// True when the harness killed the proof on hard timeout.
    public var timedOut: Bool

    public init(
        command: String,
        exitCode: Int?,
        durationMs: Int,
        outputTail: String,
        timedOut: Bool = false
    ) {
        self.command = command
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.outputTail = outputTail
        self.timedOut = timedOut
    }

    /// Exit 0 and not timed out.
    public var passed: Bool {
        !timedOut && exitCode == 0
    }
}
