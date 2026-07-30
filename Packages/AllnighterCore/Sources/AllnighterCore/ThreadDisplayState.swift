import Foundation

// The chat-list row state (PENDQ-S3). One SSOT derivation the contract exposes and the
// GUI rows + the Pending sidebar section both read — never GUI-derived truth.

/// The single state a chat row shows. Four founder states + idle:
/// - `draft`   — unsubmitted, muted (a new chat that hasn't dispatched work)
/// - `pending` — armed in the queue, neutral
/// - `running` — live, the only motion
/// - `replied` — an unread reply, the only amber
/// - `idle`    — has run, read, nothing queued
public enum ThreadDisplayState: String, Codable, Sendable, CaseIterable {
    case draft, pending, running, replied, idle
}

public enum ThreadStateDerivation {
    /// The row state for a thread. Precedence (most-urgent single state wins):
    /// needsYou (relay waiting on human) → running → pending → ordinary unread →
    /// draft → idle. `hasPendingItem` = the thread has an armed (`.pending`) Pending
    /// item queued. Failed/blocking attention is a separate axis
    /// (`WorkThread.needsAttention`), not folded in here.
    ///
    /// ATL-S05: pass store-backed `RelayState.status` for relay threads so terminal
    /// loops never paint amber from stale unread turns.
    public static func displayState(
        thread: WorkThread,
        hasPendingItem: Bool,
        relayStatus: RelayState.Status? = nil
    ) -> ThreadDisplayState {
        let attention = UnreadDerivation.railAttention(thread: thread, relayStatus: relayStatus)
        // Escalated / awaitingPM is "needs you", not a live run — even when an open
        // `relayEscalated` system turn is still `.running` on the timeline.
        if attention == .needsYou { return .replied }
        if thread.isRunning { return .running }
        if hasPendingItem { return .pending }
        if attention == .ordinaryUnread { return .replied }
        if thread.hasNeverRun { return .draft }
        return .idle
    }
}

public extension WorkThread {
    /// No work has ever been dispatched on this thread — a fresh/unsubmitted chat. The
    /// "draft" treatment new chats get before the first send.
    var hasNeverRun: Bool {
        !turns.contains { $0.runId != nil || $0.author == .worker }
    }
}
