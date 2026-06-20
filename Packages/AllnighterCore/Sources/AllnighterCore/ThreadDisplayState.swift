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
    /// running → pending → replied(unread) → draft → idle. `hasPendingItem` = the thread
    /// has an armed (`.pending`) Pending item queued. Attention (failed/blocked) is a
    /// separate, independent axis (`WorkThread.needsAttention`), not folded in here.
    public static func displayState(thread: WorkThread, hasPendingItem: Bool) -> ThreadDisplayState {
        if thread.isRunning { return .running }
        if hasPendingItem { return .pending }
        if thread.hasUnread { return .replied }
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
