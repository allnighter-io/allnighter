import SwiftUI
import AppKit

struct TitleBar: View {
    @Binding var showTeamDropdown: Bool
    @Binding var showDoctor: Bool
    @Binding var workspaceMode: WorkspaceMode
    /// Inbox unread badge count. Real unread truth wires with the Projects sidebar
    /// (G-T4); 0 until then (no fabricated count).
    var unread: Int = 0
    /// Armed-pending count — drives the conditional amber pill (shown only when > 0).
    var pendingCount: Int = 0
    var onRepair: (String) -> Void
    var onManageTeam: () -> Void
    var onOpenPending: () -> Void = {}
    var devSimActive: String?
    var onSettings: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: ALControl.trafficLightInset)
            LiveMark(state: model.isRunning ? .running : .idle, size: 16)
            InboxTeamsSwitch(mode: $workspaceMode, unread: unread)
            if let devSimActive {
                Badge(text: devSimActive, tone: .warning, dot: true, mono: true)
            }
            Spacer()
            HStack(spacing: 6) {
                if pendingCount > 0 {
                    PendingPill(count: pendingCount, action: onOpenPending)
                }
                BenchHealthBadge(isOpen: $showDoctor)
                TeamControlView(
                    isOpen: $showTeamDropdown,
                    onRepair: onRepair,
                    onManageTeam: onManageTeam
                )
                IconButton(systemImage: "clock.arrow.circlepath", accessibilityLabel: "History", small: true) {}
                IconButton(systemImage: "slider.horizontal.3", accessibilityLabel: settingsLabel, small: true, action: onSettings)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: ALControl.titleBarHeight)
        .background(WindowDragArea())
        .background(ALColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var settingsLabel: String {
        #if DEBUG
        return "Developer — GUI routes"
        #else
        return "Settings"
        #endif
    }
}

/// Conditional `N pending` entry point — appears in the title bar only when armed work
/// exists ("Pending is a condition, not a destination"). Amber is earned here; click
/// opens the Pending screen.
private struct PendingPill: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(ALColor.accent).frame(width: 6, height: 6)
                Text("\(count) pending")
                    .font(ALFont.sans(12, .semibold))
                    .foregroundStyle(ALColor.accent)
            }
            .padding(.vertical, 4).padding(.horizontal, 9)
            .background(Capsule().fill(ALColor.accent.opacity(hovering ? 0.18 : 0.12)))
            .overlay(Capsule().stroke(ALColor.accent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Pending work — open the queue")
    }
}

/// Makes an area drag the window (hidden title bar needs an explicit drag region).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
