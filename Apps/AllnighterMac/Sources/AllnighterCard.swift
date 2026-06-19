import SwiftUI
import AppKit

// MARK: - Card

enum ALCardVariant: Sendable { case `default`, accent, flush }

extension View {
    func alCard(_ variant: ALCardVariant = .default, pad: Bool = true) -> some View {
        modifier(AllnighterCard(variant: variant, pad: pad))
    }
}

struct AllnighterCard: ViewModifier {
    var variant: ALCardVariant = .default
    var pad: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(pad ? ALSpace.s4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(baseFill, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .background(
                variant == .accent ? ALColor.accentSurface : .clear,
                in: RoundedRectangle(cornerRadius: ALRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(borderColor, lineWidth: 1)
            }
            .modifier(ShadowIf(on: variant != .flush))
    }

    private var baseFill: Color { variant == .flush ? ALColor.surface : ALColor.raised }
    private var borderColor: Color { variant == .accent ? ALColor.accentBorder : ALColor.borderSubtle }
}

private struct ShadowIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        on ? AnyView(content.alShadowSm()) : AnyView(content)
    }
}

