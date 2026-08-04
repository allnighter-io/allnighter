import SwiftUI
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

struct ThreadTurnTimeline: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread
    /// RLS-S04: true while the user is parked at the bottom — gates live follow-scroll so a
    /// streaming answer keeps itself in view, but a manual scroll-up is never fought.
    @State private var atBottom = true
    private static let bottomAnchorId = "__timeline_bottom__"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(thread.turns) { turn in
                            ThreadTurnRow(turn: turn, isLastTurn: turn.id == thread.turns.last?.id)
                                .id(turn.id)
                                .timelineTurnFrame(turnId: turn.id)
                        }
                        // Bottom sentinel — reports the content's bottom edge so live
                        // follow-scroll only fires when the user is already at the bottom.
                        Color.clear.frame(height: 1)
                            .id(Self.bottomAnchorId)
                            .background(GeometryReader { g in
                                Color.clear.preference(
                                    key: TimelineBottomSentinelKey.self,
                                    value: g.frame(in: .global).maxY)
                            })
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .timelineVisibilityTracking(thread: thread)
                .onPreferenceChange(TimelineBottomSentinelKey.self) { sentinelMaxY in
                    atBottom = TimelineScrollPolicy.isAtBottom(
                        contentBottomY: sentinelMaxY, viewportBottomY: outer.frame(in: .global).maxY)
                }
                .onAppear { scrollTimelineToOpenPosition(proxy: proxy) }
                .onChange(of: thread.id) { _, _ in scrollTimelineToOpenPosition(proxy: proxy) }
                .onChange(of: thread.turns.count) { _, _ in
                    TimelineScrollPolicy.scrollOnTurnCountChange(
                        proxy: proxy,
                        thread: thread,
                        suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll,
                        forceScrollToBottomAfterSend: threads.forceScrollToBottomAfterSendActive(),
                        bottomAnchorId: Self.bottomAnchorId
                    )
                }
                .onChange(of: TimelineScrollPolicy.liveContentSignal(for: thread)) { _, _ in
                    // RLS-S04: follow the streaming answer as it grows — but only when the
                    // user is at the bottom, and without animation so the follow stays tight.
                    guard !GUIFixture.suppressUnreadAutoScroll else { return }
                    if threads.forceScrollToBottomAfterSendActive() || atBottom {
                        TimelineScrollPolicy.scrollToBottom(
                            proxy: proxy,
                            bottomAnchorId: Self.bottomAnchorId,
                            animated: false
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollTimelineToOpenPosition(proxy: ScrollViewProxy) {
        TimelineScrollPolicy.scrollOnThreadOpen(
            proxy: proxy,
            pendingTarget: threads.consumePendingScrollTarget(),
            suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll,
            bottomAnchorId: Self.bottomAnchorId
        )
    }
}
