import SwiftUI

/// The two top-level workspaces (Send-to-team handoff §Global shell). `inbox` is
/// today's chat/conversation home; `teams` is the Send-to-team launcher.
enum WorkspaceMode: String, CaseIterable {
    case inbox, teams

    var label: String { self == .inbox ? "Inbox" : "Teams" }
    /// SF Symbol — Lucide `inbox`→`tray`, `users-round`→`person.2`.
    var symbol: String { self == .inbox ? "tray" : "person.2" }
}

/// `Inbox | Teams` top-bar control (handoff `.modeswitch`). Flat — no container box
/// and no selected fill. The active workspace reads as **brighter text**; a subtle
/// box appears only on hover. Inbox carries an unread badge.
struct InboxTeamsSwitch: View {
    @Binding var mode: WorkspaceMode
    var unread: Int = 0
    @State private var hovered: WorkspaceMode?

    var body: some View {
        HStack(spacing: 4) {
            segment(.inbox)
            segment(.teams)
        }
    }

    @ViewBuilder
    private func segment(_ item: WorkspaceMode) -> some View {
        let isActive = mode == item
        let isHovered = hovered == item
        Button { mode = item } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 12, weight: .medium))
                Text(item.label).font(ALFont.label.weight(.semibold))
                if item == .inbox, unread > 0 {
                    Text("\(unread)")
                        .font(ALFont.monoSm.weight(.semibold))
                        .foregroundStyle(ALColor.accentText)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ALColor.accentSurface, in: Capsule())
                }
            }
            .foregroundStyle(isActive ? ALColor.textPrimary : ALColor.textMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ALRadius.sm)
                    .fill(isHovered ? ALColor.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hovered = hovering ? item : (hovered == item ? nil : hovered) }
        .help("\(item.label) (\u{2318}\(item == .inbox ? "1" : "2"))")
    }
}
