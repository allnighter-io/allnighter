import Foundation

/// One harness-owned proof-of-record result (`docs/phases/Process_Ownership.md` PO-S04/F4).
///
/// Surfaced on relay/pilot `roundLog` as `proofResults[]`. The agent never runs
/// these commands; the harness executes them after the dev turn ends.
///
/// Standing invariants (PO-F4) are harness-injected and carry `standing: true`
/// plus an `invariant` id (e.g. `contractDrift`). Declared `proofCommands` leave
/// both at their defaults.
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
    /// PO-F4: true when this result is a harness-injected standing invariant
    /// (not a dev-declared proofCommand).
    public var standing: Bool
    /// PO-F4: standing-invariant id when `standing` is true (e.g. `contractDrift`).
    public var invariant: String?

    public init(
        command: String,
        exitCode: Int?,
        durationMs: Int,
        outputTail: String,
        timedOut: Bool = false,
        standing: Bool = false,
        invariant: String? = nil
    ) {
        self.command = command
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.outputTail = outputTail
        self.timedOut = timedOut
        self.standing = standing
        self.invariant = invariant
    }

    /// Exit 0 and not timed out.
    public var passed: Bool {
        !timedOut && exitCode == 0
    }

    // Lenient decode: results persisted before PO-F4 lack standing/invariant.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decode(String.self, forKey: .command)
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        outputTail = try c.decode(String.self, forKey: .outputTail)
        timedOut = try c.decodeIfPresent(Bool.self, forKey: .timedOut) ?? false
        standing = try c.decodeIfPresent(Bool.self, forKey: .standing) ?? false
        invariant = try c.decodeIfPresent(String.self, forKey: .invariant)
    }
}
