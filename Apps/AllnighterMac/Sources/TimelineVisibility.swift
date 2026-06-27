import SwiftUI
import AllnighterCore

/// Which turn families may report viewport visibility for read-clear (UNR-S05).
/// Rich team/build cards defer to UNR-S08.
enum TimelineReadClearance {
    static func countsTowardReadClear(_ turn: ThreadTurn) -> Bool {
        switch turn.kind {
        case .workerChat:
            return true
        case .systemEvent:
            switch turn.systemEvent {
            case .signInRequired, .manualPaste:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    /// Turn ids geometrically visible and eligible to advance the read cursor.
    static func visibleTurnIdsForReadClear(
        thread: WorkThread,
        frames: [String: CGRect],
        viewport: CGRect,
        intersectionThreshold: CGFloat = 0.25
    ) -> [String] {
        let geometricallyVisible = Set(
            Self.geometricallyVisibleTurnIds(frames: frames, viewport: viewport, threshold: intersectionThreshold)
        )
        return thread.turns.map(\.id).filter { id in
            guard geometricallyVisible.contains(id),
                  let turn = thread.turns.first(where: { $0.id == id })
            else { return false }
            if UnreadDerivation.isUnreadEligible(turn) {
                return countsTowardReadClear(turn)
            }
            return true
        }
    }

    private static func geometricallyVisibleTurnIds(
        frames: [String: CGRect],
        viewport: CGRect,
        threshold: CGFloat
    ) -> [String] {
        frames.compactMap { id, frame in
            guard viewport.intersects(frame), frame.height > 0 else { return nil }
            let ratio = viewport.intersection(frame).height / frame.height
            return ratio >= threshold ? id : nil
        }
    }
}

// MARK: - Preference keys

private struct TurnFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, rhs in rhs })
    }
}

private struct ScrollViewportPreference: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - View helpers

extension View {
    /// Reports this row's global frame for timeline viewport intersection.
    func timelineTurnFrame(turnId: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TurnFramePreference.self,
                    value: [turnId: geo.frame(in: .global)]
                )
            }
        )
    }

    /// Tracks scroll-viewport intersection and forwards read-clear visibility to the view model.
    func timelineVisibilityTracking(thread: WorkThread) -> some View {
        modifier(TimelineVisibilityTrackingModifier(thread: thread))
    }
}

private struct TimelineVisibilityTrackingModifier: ViewModifier {
    let thread: WorkThread
    @Environment(ThreadsViewModel.self) private var threads
    @State private var turnFrames: [String: CGRect] = [:]
    @State private var viewport: CGRect = .null

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollViewportPreference.self,
                        value: geo.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(TurnFramePreference.self) { turnFrames = $0 }
            .onPreferenceChange(ScrollViewportPreference.self) { viewport = $0 }
            .onChange(of: turnFrames) { _, _ in report() }
            .onChange(of: viewport) { _, _ in report() }
            .onChange(of: thread.turns.count) { _, _ in report() }
    }

    private func report() {
        guard viewport != .null else { return }
        let visible = TimelineReadClearance.visibleTurnIdsForReadClear(
            thread: thread, frames: turnFrames, viewport: viewport
        )
        threads.reportTimelineVisibility(threadId: thread.id, visibleTurnIds: visible)
    }
}

/// Shared scroll behavior for Home + legacy thread timelines.
enum TimelineScrollPolicy {
    enum ThreadOpenScrollAction: Equatable {
        case scrollToBottom
        case scrollToTurn(String)
    }

    enum TurnCountScrollAction: Equatable {
        case scrollToBottom
        case scrollToFirstUnread(String)
        case scrollToLastTurnBottom(String)
    }

    /// Opening a thread resumes at the latest turns; only an explicit deep-link target
    /// (notification tap) scrolls elsewhere.
    static func threadOpenScrollAction(
        pendingTarget: String?,
        suppressAutoScroll: Bool
    ) -> ThreadOpenScrollAction? {
        guard !suppressAutoScroll else { return nil }
        if let target = pendingTarget { return .scrollToTurn(target) }
        return .scrollToBottom
    }

    /// Pure decision for turn-count scroll — testable without a `ScrollViewProxy`.
    static func turnCountScrollAction(
        thread: WorkThread,
        suppressAutoScroll: Bool,
        forceScrollToBottomAfterSend: Bool
    ) -> TurnCountScrollAction? {
        guard !suppressAutoScroll else { return nil }
        if forceScrollToBottomAfterSend { return .scrollToBottom }
        if let target = ThreadsPresenter.firstUnreadTurnId(thread) {
            return .scrollToFirstUnread(target)
        }
        if let last = thread.turns.last {
            return .scrollToLastTurnBottom(last.id)
        }
        return nil
    }

    static func scrollOnThreadOpen(
        proxy: ScrollViewProxy,
        pendingTarget: String?,
        suppressAutoScroll: Bool,
        bottomAnchorId: String
    ) {
        guard let action = threadOpenScrollAction(
            pendingTarget: pendingTarget,
            suppressAutoScroll: suppressAutoScroll
        ) else { return }
        switch action {
        case .scrollToBottom:
            scrollToBottom(proxy: proxy, bottomAnchorId: bottomAnchorId, animated: false)
        case .scrollToTurn(let turnId):
            withAnimation { proxy.scrollTo(turnId, anchor: .top) }
        }
    }

    static func scrollOnTurnCountChange(
        proxy: ScrollViewProxy,
        thread: WorkThread,
        suppressAutoScroll: Bool,
        forceScrollToBottomAfterSend: Bool,
        bottomAnchorId: String
    ) {
        guard let action = turnCountScrollAction(
            thread: thread,
            suppressAutoScroll: suppressAutoScroll,
            forceScrollToBottomAfterSend: forceScrollToBottomAfterSend
        ) else { return }
        switch action {
        case .scrollToBottom:
            scrollToBottom(proxy: proxy, bottomAnchorId: bottomAnchorId, animated: true)
        case .scrollToFirstUnread(let target):
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        case .scrollToLastTurnBottom(let turnId):
            withAnimation { proxy.scrollTo(turnId, anchor: .bottom) }
        }
    }

    /// After submit the user must see their message — pin to the timeline bottom sentinel
    /// (not merely the last turn id) so the full outgoing bubble is in view.
    static func scrollToBottom(
        proxy: ScrollViewProxy,
        bottomAnchorId: String,
        animated: Bool
    ) {
        let scroll = {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        if animated {
            withAnimation { scroll() }
        } else {
            scroll()
        }
        // A second pass after layout catches the newly appended user row.
        DispatchQueue.main.async { scroll() }
    }

    /// RLS-S04 auto-follow: a streaming answer grows the LAST turn's text without changing
    /// the turn count, so nothing scrolls and the screen looks frozen. While the user is at
    /// the bottom we follow the growing content; once they scroll up we stop fighting them.
    /// `slack` lets "near the bottom" still count as following.
    static func isAtBottom(contentBottomY: CGFloat, viewportBottomY: CGFloat, slack: CGFloat = 120) -> Bool {
        contentBottomY <= viewportBottomY + slack
    }

    /// A monotonic signal that grows as the last turn streams (answer + reasoning length),
    /// or 0 when nothing is running — `onChange` on it drives the live follow-scroll.
    static func liveContentSignal(for thread: WorkThread) -> Int {
        guard let last = thread.turns.last, last.status == .running else { return 0 }
        return (last.text?.count ?? 0) &+ (last.reasoningText?.count ?? 0)
    }
}

/// Reports the global maxY of the timeline content's bottom sentinel, so the timeline can
/// tell whether the user is parked at the bottom (RLS-S04 auto-follow gate).
struct TimelineBottomSentinelKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
