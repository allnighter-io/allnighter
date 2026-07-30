import SwiftUI
import AllnighterCore

/// Shared rail row chrome for Home + legacy Threads (07). Unread light uses Core
/// derivation only — never GUI-local unread flags. ATL-S05: pass store-backed
/// `relayStatus` for relay threads so terminal loops never keep a stale amber.
enum ThreadRailComponents {

    struct UnreadLight: View {
        let thread: WorkThread
        /// `RelayState.status` from the store when this row is a relay; nil otherwise.
        var relayStatus: RelayState.Status? = nil

        var body: some View {
            let attention = ThreadsPresenter.railAttention(thread, relayStatus: relayStatus)
            if showsLight(attention) {
                Circle()
                    .fill(lightColor(attention))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
                    .accessibilityValue(
                        attention == .needsYou || ThreadsPresenter.unreadNeedsAttention(thread, relayStatus: relayStatus)
                            ? "Unread, needs attention"
                            : "Unread"
                    )
            }
        }

        private func showsLight(_ attention: UnreadDerivation.RailAttention) -> Bool {
            switch attention {
            case .needsYou, .ordinaryUnread: return true
            case .none:
                // Relay terminal/running: no attention colour even with unread turns.
                // Ordinary threads still use the plain unread light.
                return relayStatus == nil && ThreadsPresenter.showsUnreadLight(thread)
            }
        }

        private func lightColor(_ attention: UnreadDerivation.RailAttention) -> Color {
            // Needs-you loop → reserved amber. Ordinary failed/blocking unread → red.
            // Ordinary plain unread → soft amber (#FFD79E, founder spec).
            switch attention {
            case .needsYou:
                return ALPalette.amber300
            case .ordinaryUnread, .none:
                return ThreadsPresenter.unreadNeedsAttention(thread, relayStatus: relayStatus)
                    ? ALColor.statusFailed
                    : ALPalette.amber300
            }
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
