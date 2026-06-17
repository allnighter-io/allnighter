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
            ThreadsPresenter.unreadNeedsAttention(thread) ? ALColor.statusFailed : ALColor.accent
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
    let thread: WorkThread
    var inArchiveView: Bool = false
    var onRename: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Open") { threads.select(thread) }
            if inArchiveView {
                Button("Unarchive") { threads.unarchiveThread(thread.id) }
            } else {
                if !thread.isArchived {
                    if thread.isPinned {
                        Button("Unpin") { threads.setPinned(thread.id, pinned: false) }
                    } else {
                        Button("Pin") { threads.setPinned(thread.id, pinned: true) }
                    }
                    Button("Rename…") { onRename?() }
                    Button("Archive") { threads.archiveThread(thread.id) }
                }
            }
        }
    }
}

extension View {
    func threadRowContextMenu(
        thread: WorkThread, inArchiveView: Bool = false, onRename: (() -> Void)? = nil
    ) -> some View {
        modifier(ThreadRowContextMenu(thread: thread, inArchiveView: inArchiveView, onRename: onRename))
    }
}
