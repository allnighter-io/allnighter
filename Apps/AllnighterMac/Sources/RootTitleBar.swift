import SwiftUI
import AppKit

struct TitleBar: View {
    @Binding var showTeamDropdown: Bool
    @Binding var showDoctor: Bool
    @Binding var workspaceMode: WorkspaceMode
    /// Inbox unread badge count. Real unread truth wires with the Projects sidebar
    /// (G-T4); 0 until then (no fabricated count).
    var unread: Int = 0
    var onRepair: (String) -> Void
    var onManageTeam: () -> Void
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
        .frame(minHeight: ALControl.titleBarHeight, alignment: .top)
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

/// Makes an area drag the window (hidden title bar needs an explicit drag region).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
