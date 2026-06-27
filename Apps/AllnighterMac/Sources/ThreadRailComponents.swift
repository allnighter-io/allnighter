import SwiftUI
import AllnighterCore

/// Shared rail row chrome for Home + legacy Threads (07). Unread light uses Core
/// derivation only — never GUI-local unread flags.
enum ThreadRailComponents {

    struct UnreadLight: View {
        let thread: WorkThread

        var body: some View {
            if ThreadsPresenter.showsUnreadLight(thread) {
                Circle()
                    .fill(lightColor)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
                    .accessibilityValue(
                        ThreadsPresenter.unreadNeedsAttention(thread) ? "Unread, needs attention" : "Unread"
                    )
            }
        }

        private var lightColor: Color {
            // Normal unread = the soft amber (#FFD79E, founder spec); a failed /
            // blocking unread escalates to red.
            ThreadsPresenter.unreadNeedsAttention(thread) ? ALColor.statusFailed : ALPalette.amber300
        }
    }

    struct PinMarker: View {
        let pinned: Bool

        var body: some View {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(ALColor.textFaint)
                    .accessibilityLabel("Pinned")
            }
        }
    }
}

struct ThreadRowContextMenu: ViewModifier {
    @Environment(ThreadsViewModel.self) private var threads
    let threadId: String
    let isPinned: Bool
    let isArchived: Bool
    var inArchiveView: Bool = false
    var onRename: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Open") { threads.select(threadId: threadId) }
            if isArchived {
                Button("Unarchive") { threads.unarchiveThread(threadId) }
            } else if !inArchiveView {
                if isPinned {
                    Button("Unpin") { threads.setPinned(threadId, pinned: false) }
                } else {
                    Button("Pin") { threads.setPinned(threadId, pinned: true) }
                }
                Button("Rename…") { onRename?() }
                Button("Archive") { threads.archiveThread(threadId) }
                Divider()
                if threads.isThreadNotificationsMuted(threadId) {
                    Button("Unmute notifications") {
                        threads.setThreadNotificationsMuted(threadId, muted: false)
                    }
                } else {
                    Button("Mute notifications") {
                        threads.setThreadNotificationsMuted(threadId, muted: true)
                    }
                }
            }
        }
    }
}

extension View {
    func threadRowContextMenu(
        threadId: String, isPinned: Bool, isArchived: Bool,
        inArchiveView: Bool = false, onRename: (() -> Void)? = nil
    ) -> some View {
        modifier(ThreadRowContextMenu(threadId: threadId, isPinned: isPinned, isArchived: isArchived,
                                      inArchiveView: inArchiveView, onRename: onRename))
    }

    /// Convenience for call sites that still hold a full `WorkThread` (e.g. the archive rail).
    func threadRowContextMenu(
        thread: WorkThread, inArchiveView: Bool = false, onRename: (() -> Void)? = nil
    ) -> some View {
        threadRowContextMenu(threadId: thread.id, isPinned: thread.isPinned, isArchived: thread.isArchived,
                             inArchiveView: inArchiveView, onRename: onRename)
    }
}
