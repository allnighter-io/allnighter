import SwiftUI
import AppKit

// MARK: - Buttons
//
// primary (amber) · secondary · ghost · danger. Pressed scales; primary glows
// on hover. Spec: handoff §Button, components/core/Button.

// `light` is the F2F4FA action button (send / commit). It carries the primary
// affordance WITHOUT amber, so yellow stays a rare accent rather than the whole
// UI. Reach for `.light` for the main action; keep `.primary` (amber) sparing.
enum ALButtonVariant: Sendable { case primary, light, secondary, ghost, danger }

struct AllnighterButtonStyle: ButtonStyle {
    var variant: ALButtonVariant = .primary
    var small: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ALButtonSurface(variant: variant, small: small, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == AllnighterButtonStyle {
    static var alPrimary: Self { .init(variant: .primary) }
    static var alLight: Self { .init(variant: .light) }
    static var alSecondary: Self { .init(variant: .secondary) }
    static var alGhost: Self { .init(variant: .ghost) }
    static var alDanger: Self { .init(variant: .danger) }
    static func alPrimary(small: Bool) -> Self { .init(variant: .primary, small: small) }
    static func alSecondary(small: Bool) -> Self { .init(variant: .secondary, small: small) }
}

private struct ALButtonSurface<Label: View>: View {
    let variant: ALButtonVariant
    var small: Bool = false
    let isPressed: Bool
    @ViewBuilder var label: Label

    @State private var hover = false

    var body: some View {
        label
            .font((small ? ALFont.label : ALFont.body).weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? ALControl.heightSm : ALControl.height)
            .background(background, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .overlay {
                if let border = borderColor {
                    RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(border, lineWidth: 1)
                }
            }
            .modifier(GlowIf(active: hover && variant == .primary))
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(ALMotion.fast, value: isPressed)
            .animation(ALMotion.fast, value: hover)
            .onHover { hover = $0 }
    }

    private var foreground: Color {
        switch variant {
        case .primary: ALColor.textOnAmber
        case .light: ALColor.textOnLight
        case .secondary: ALColor.textPrimary
        case .ghost: hover ? ALColor.textPrimary : ALColor.textSecondary
        case .danger: Color(hex: 0x220707)
        }
    }
    private var background: Color {
        switch variant {
        case .primary: hover ? ALColor.accentHover : ALColor.accent
        case .light: hover ? ALPalette.ink100 : ALColor.actionLight
        case .secondary: hover ? ALColor.hover : ALColor.surface
        case .ghost: hover ? ALColor.hover : .clear
        case .danger: hover ? ALPalette.red400 : ALPalette.red500
        }
    }
    private var borderColor: Color? {
        switch variant {
        case .secondary: hover ? ALColor.borderStrong : ALColor.borderDefault
        default: nil
        }
    }
}

private struct GlowIf: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        active ? AnyView(content.alGlowAmber()) : AnyView(content)
    }
}

