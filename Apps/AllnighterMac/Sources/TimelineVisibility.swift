import SwiftUI
import AllnighterCore

/// Which turn families may report viewport visibility for read-clear (UNR-S05).
/// Rich team/build/dispatch cards defer to UNR-S08.
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

/// Shared scroll-to-unread behavior for Home + legacy thread timelines.
enum TimelineScrollPolicy {
    static func scrollToUnreadIfNeeded(
        proxy: ScrollViewProxy,
        thread: WorkThread,
        pendingTarget: String?,
        suppressAutoScroll: Bool
    ) {
        guard !suppressAutoScroll else { return }
        if let target = pendingTarget ?? ThreadsPresenter.firstUnreadTurnId(thread) {
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        }
    }

    static func scrollOnTurnCountChange(
        proxy: ScrollViewProxy,
        thread: WorkThread,
        suppressAutoScroll: Bool
    ) {
        guard !suppressAutoScroll else { return }
        if ThreadsPresenter.firstUnreadTurnId(thread) != nil {
            if let target = ThreadsPresenter.firstUnreadTurnId(thread) {
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
            return
        }
        if let last = thread.turns.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}
