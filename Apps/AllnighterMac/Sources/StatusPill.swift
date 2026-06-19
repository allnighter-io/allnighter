import SwiftUI
import AppKit

// Allnighter signature SwiftUI components — see docs/design-system/components/.

// MARK: - StatusPill
//
// The signature run-status chip: dot + label. The `running` dot PULSES
// (ALMotion.pulse). Spec: handoff §StatusPill, components/product/StatusPill.

struct StatusPill: View {
    enum Kind: Sendable, CaseIterable { case queued, running, done, failed, timedOut }

    let kind: Kind
    var label: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .opacity(kind == .running && pulsing ? 0.45 : 1)
            Text(label ?? defaultLabel)
                .font(ALFont.caption.weight(.semibold))
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 20)
        .foregroundStyle(textColor)
        .background(fillColor, in: Capsule())
        .onAppear {
            guard kind == .running, !reduceMotion else { return }
            withAnimation(ALMotion.pulse) { pulsing = true }
        }
    }

    private var defaultLabel: String {
        switch kind {
        case .queued: "Queued"
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .timedOut: "Timed out"
        }
    }
    private var dotColor: Color {
        switch kind {
        case .queued: ALColor.statusQueued
        case .running: ALColor.statusRunning
        case .done: ALColor.statusDone
        case .failed: ALColor.statusFailed
        case .timedOut: ALColor.statusTimeout
        }
    }
    private var fillColor: Color {
        switch kind {
        case .queued: ALColor.active
        case .running: ALColor.infoSurface
        case .done: ALColor.successSurface
        case .failed: ALColor.dangerSurface
        case .timedOut: ALColor.warningSurface
        }
    }
    private var textColor: Color {
        switch kind {
        case .queued: ALColor.textMuted
        case .running: ALPalette.blue400
        case .done: ALPalette.green400
        case .failed: ALPalette.red400
        case .timedOut: ALPalette.yellow400
        }
    }
}

