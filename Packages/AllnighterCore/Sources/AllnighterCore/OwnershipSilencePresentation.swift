import Foundation

/// Read-time silence lines for ownership / status surfaces (IDLE-HF-S04).
/// Reuses `lastProgressAt` age — no second idle clock.
///
/// When a stall diagnosis is available (auth-prompt / frozen descendant), it is
/// appended so `alln ps` names the wedge instead of a bare silence line.
public enum OwnershipSilencePresentation {
    /// `nil` when the owner is not identity-alive. Otherwise a compact line such as
    /// `alive, no stream for 120s` (or `alive, no stream yet` before first activity).
    public static func silenceStatusLine(
        identityAlive: Bool,
        lastProgressAt: Date?,
        now: Date = Date(),
        stallSummary: String? = nil
    ) -> String? {
        guard identityAlive else { return nil }
        let base: String
        if let last = lastProgressAt {
            let seconds = max(0, Int(now.timeIntervalSince(last).rounded()))
            base = "alive, no stream for \(seconds)s"
        } else {
            base = "alive, no stream yet"
        }
        guard let stallSummary, !stallSummary.isEmpty else { return base }
        return "\(base) — \(stallSummary)"
    }
}
