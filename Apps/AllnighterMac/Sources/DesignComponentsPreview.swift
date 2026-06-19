import SwiftUI
import AppKit

// MARK: - Preview

#Preview("Foundation — tokens & components") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 14) {
            LiveMark(state: .idle)
            LiveMark(state: .running)
            LiveMark(state: .done)
            Text("alln").font(ALFont.h2).foregroundStyle(ALColor.textPrimary)
            Badge(text: "5/5 healthy", tone: .positive, dot: true)
        }
        HStack(spacing: 8) {
            ForEach(StatusPill.Kind.allCases, id: \.self) { StatusPill(kind: $0) }
        }
        HStack(spacing: 10) {
            Button("Run team") {}.buttonStyle(.alPrimary)
            Button("Export Markdown") {}.buttonStyle(.alSecondary)
            Button("Copy") {}.buttonStyle(.alGhost)
            Button("Stop") {}.buttonStyle(.alDanger)
            IconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
        }
        SegmentedTabs(items: [.init(id: "plan", label: "Plan"),
                              .init(id: "members", label: "Worker answers", count: 6)],
                      selection: .constant("plan"))
        VStack(spacing: 8) {
            WorkerChip(name: "Opus 4.8", model: "via claude-code", driverId: "claude_code",
                       status: .running, meta: "00:04",
                       selectable: true, selected: true)
            WorkerChip(name: "Grok Build", model: "via grok-cli", driverId: "grok",
                       status: .failed, meta: "auth expired")
        }
        Text("Plan ready").font(ALFont.title).foregroundStyle(ALColor.textPrimary).alCard(.accent)
    }
    .padding(24)
    .frame(width: 480)
    .background(ALColor.base)
}
