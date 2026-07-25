import Foundation

/// `alln doctor handoff` — can this terminal get work run by the Allnighter app?
///
/// The question a caller inside a sandboxed host actually has is not "is the app
/// installed" but "if I hand something off right now, will anything pick it up and
/// write me an answer?". Nothing else answers that: `alln doctor` reports this
/// machine's tools, and a real run costs minutes and quota to find out.
///
/// So this drops one `ping` in the mailbox and reports what was OBSERVED — never a
/// guess. The three failing verdicts are deliberately distinct, because they used to
/// be indistinguishable from a single wrong sentence ("Allnighter isn't open"):
/// nothing claimed it, something claimed it and went quiet, or the mailbox itself
/// could not be written.
public struct HandoffDoctorJSON: Codable, Sendable, Equatable {
    public enum Verdict: String, Codable, Sendable {
        /// A host claimed the ping and wrote its terminal journal. Hand-off works.
        case healthy
        /// The ping was never claimed. Nothing is watching the mailbox — the app is
        /// not open, or its hand-off host never started.
        case hostNotRunning
        /// A host claimed the ping and never settled it. It is alive but stuck or
        /// died mid-request; the claim is orphaned.
        case claimedButSilent
        /// The mailbox could not be written at all, so no hand-off is possible from
        /// this terminal regardless of what the app is doing.
        case mailboxUnwritable
    }

    public var schemaVersion: Int
    public var contractVersion: String
    public var verdict: Verdict
    /// Plain sentence for a human; states what was observed, not what it means.
    public var detail: String
    /// The ping's run id — readable afterwards with `alln show <id>`.
    public var runId: String
    public var waitedMs: Int
    /// Which host claimed the ping, when one did.
    public var claimedBy: String?

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        verdict: Verdict,
        detail: String,
        runId: String,
        waitedMs: Int,
        claimedBy: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.verdict = verdict
        self.detail = detail
        self.runId = runId
        self.waitedMs = waitedMs
        self.claimedBy = claimedBy
    }

    /// True only for `healthy` — callers gate on this rather than string-matching.
    public var isHealthy: Bool { verdict == .healthy }
}
