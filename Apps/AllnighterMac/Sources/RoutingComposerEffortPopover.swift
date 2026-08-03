import SwiftUI
import AllnighterCore
import AllnighterEngine

// Effort popover — reasoning level picker (CM-S06). State owner: RoutingComposer.

extension RoutingComposer {

    // MARK: effort popover

    // Team runs only — model routes show effort in the target chip + row pill.
    var effortChip: some View {
        Button { effortOpen.toggle() } label: {
            HStack(spacing: 5) {
                Text(effort.label).font(ALFont.mono).foregroundStyle(ALColor.textSecondary)
                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Reasoning effort")
        .alPopover(isPresented: $effortOpen, arrowEdge: .top) {
            effortEditPanel(onDismiss: { effortOpen = false })
        }
    }

    func effortEditPanel(onDismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reasoning effort")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ALColor.textFaint)
                .padding(.horizontal, 4)
            effortPickerRows(onDismiss: onDismiss)
        }
        .padding(6)
        .frame(width: 150)
        .background(ALColor.surface)
        .overlay(effortKeyMonitor(onDismiss: onDismiss).allowsHitTesting(false))
        .onAppear { effortHighlight = nil }
    }

    func effortPickerRows(onDismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ComposeEffort.allCases, id: \.self) { e in
                let highlighted = (effortHighlight ?? effort) == e
                Button {
                    effort = e
                    onDismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(e.label).font(.system(size: 13, weight: .medium)).foregroundStyle(ALColor.textPrimary)
                        Spacer(minLength: 8)
                        if e == effort { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(highlighted ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { effortHighlight = e } }
            }
        }
    }

    /// ↑/↓ move through Low/Med/High, ⏎ selects, esc closes — same AppKit key monitor
    /// the target popover uses (SwiftUI key focus doesn't fire inside an NSPopover).
    func effortKeyMonitor(onDismiss: @escaping () -> Void) -> some View {
        let all = ComposeEffort.allCases
        return PopoverKeyCatcher { action in
            let current = effortHighlight ?? effort
            let idx = all.firstIndex(of: current) ?? 0
            switch action {
            case .up: effortHighlight = all[(idx - 1 + all.count) % all.count]
            case .down: effortHighlight = all[(idx + 1) % all.count]
            case .enter: effort = effortHighlight ?? effort; onDismiss()
            case .escape: onDismiss()
            case .tab: return false
            }
            return true
        }
    }
}
