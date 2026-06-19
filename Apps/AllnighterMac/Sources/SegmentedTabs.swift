import SwiftUI
import AppKit

// MARK: - SegmentedTabs

struct SegmentedTabs: View {
    struct Item: Identifiable, Hashable { let id: String; let label: String; var count: Int? = nil }

    let items: [Item]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSel = item.id == selection
                Button { selection = item.id } label: {
                    HStack(spacing: 5) {
                        Text(item.label)
                        if let c = item.count {
                            Text("\(c)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                        }
                    }
                    .font(ALFont.label.weight(.medium))
                    .foregroundStyle(isSel ? ALColor.textPrimary : ALColor.textMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(isSel ? ALColor.raised : .clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

