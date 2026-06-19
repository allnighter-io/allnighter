import SwiftUI

/// The two top-level workspaces (Send-to-team handoff §Global shell). `inbox` is
/// today's chat/conversation home; `teams` is the Send-to-team launcher.
enum WorkspaceMode: String, CaseIterable {
    case inbox, teams

    var label: String { self == .inbox ? "Inbox" : "Teams" }
    /// SF Symbol — Lucide `inbox`→`tray`, `users-round`→`person.2`.
    var symbol: String { self == .inbox ? "tray" : "person.2" }
}

/// `Inbox | Teams` segmented top-bar control (handoff `.modeswitch`). Active
/// segment: `bgActive` fill + inset hairline + `ink50` text; inactive: `textMuted`.
/// Inbox carries an unread badge.
struct InboxTeamsSwitch: View {
    @Binding var mode: WorkspaceMode
    var unread: Int = 0

    var body: some View {
        HStack(spacing: 3) {
            segment(.inbox)
            segment(.teams)
        }
        .padding(3)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay(RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func segment(_ item: WorkspaceMode) -> some View {
        let isActive = mode == item
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
            .background(segmentBackground(isActive))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.label) (\u{2318}\(item == .inbox ? "1" : "2"))")
    }

    @ViewBuilder
    private func segmentBackground(_ isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: ALRadius.sm)
                .fill(ALColor.active)
                .overlay(RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
        }
    }
}
