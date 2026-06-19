import SwiftUI
import AppKit

// MARK: - WorkerChip
//
// Two modes: `selectable` (sidebar panel: glyph + name + model + checkbox) and
// `status` (run grid: glyph + name + model + StatusPill + meta).
// Spec: handoff §WorkerChip, components/product/WorkerChip.

struct WorkerChip: View {
    let name: String
    var model: String? = nil
    var driverId: String? = nil
    var systemImage: String = "cpu"
    var glyphTint: Color = ALColor.textSecondary
    var status: StatusPill.Kind? = nil
    var meta: String? = nil
    var selectable: Bool = false
    var selected: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        if selectable {
            Button { onToggle?() } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            WorkerGlyph(driverId: driverId, systemImage: systemImage, tint: glyphTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(ALFont.body.weight(.semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .lineLimit(1)
                if let model {
                    Text(model)
                        .font(ALFont.monoSm)
                        .foregroundStyle(ALColor.textFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                if let meta {
                    Text(meta).font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                }
                if let status { StatusPill(kind: status) }
                if selectable { checkBox }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private var checkBox: some View {
        RoundedRectangle(cornerRadius: ALRadius.xs)
            .fill(selected ? ALColor.accent : .clear)
            .frame(width: 18, height: 18)
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.xs)
                    .strokeBorder(selected ? ALColor.accent : ALColor.borderStrong, lineWidth: 1.5)
            }
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ALColor.textOnAmber)
                }
            }
    }

    private var backgroundColor: Color { ALColor.raised }
    private var borderColor: Color {
        if selected { return ALColor.accentBorder }
        if status == .running { return ALColor.statusRunning.opacity(0.30) }
        return ALColor.borderSubtle
    }
}

