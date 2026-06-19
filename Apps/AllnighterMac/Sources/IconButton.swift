import SwiftUI
import AppKit

// MARK: - IconButton

struct IconButton: View {
    let systemImage: String
    var accessibilityLabel: String
    var small: Bool = false
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: small ? 12 : 13))
                .foregroundStyle(hover ? ALColor.textPrimary : ALColor.textSecondary)
                .frame(width: small ? ALControl.heightSm : ALControl.height,
                       height: small ? ALControl.heightSm : ALControl.height)
                .background(hover ? ALColor.hover : .clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

