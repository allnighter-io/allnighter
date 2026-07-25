import Foundation

/// Read-time silence lines for ownership / status surfaces (IDLE-HF-S04).
/// Reuses `lastProgressAt` age — no second idle clock.
public enum OwnershipSilencePresentation {
    /// `nil` when the owner is not identity-alive. Otherwise a compact line such as
    /// `alive, no stream for 120s` (or `alive, no stream yet` before first activity).
    public static func silenceStatusLine(
        identityAlive: Bool,
        lastProgressAt: Date?,
        now: Date = Date()
    ) -> String? {
        guard identityAlive else { return nil }
        guard let last = lastProgressAt else { return "alive, no stream yet" }
        let seconds = max(0, Int(now.timeIntervalSince(last).rounded()))
        return "alive, no stream for \(seconds)s"
    }
}
