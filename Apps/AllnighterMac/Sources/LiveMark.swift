import SwiftUI
import AppKit

// MARK: - LiveMark
//
// The brand mark: an amber crescent + a cursor block. Only the block animates:
// idle solid · running blinks · done turns green. Geometry per handoff
// §"The live mark" (100×100 box). NOTE: native rebuild of the brand glyph;
// swap for the bundled vector asset in a later polish pass.

struct LiveMark: View {
    enum Phase: Sendable { case idle, running, done }

    var state: Phase = .idle
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinkOn = true

    var body: some View {
        // Render the FINAL brand FILE (solid white crescent) — never a drawn shape
        // (a stroked/eo-filled crescent reads as a ring; allnighter-logo-FINAL
        // README). "Live" is a gentle opacity pulse, not color.
        AllnighterGlyph(size: size)
            .opacity(state == .running && !blinkOn ? 0.45 : 1)
            .onAppear {
                guard state == .running, !reduceMotion else { return }
                withAnimation(ALMotion.blink) { blinkOn = false }
            }
    }
}

/// The Allnighter brand mark — the FINAL solid white crescent FILE
/// (`AllnighterLogoWhite` asset), used for every avatar/empty-state. Do not draw
/// it as a shape and do not recolor it through the icon system
/// (allnighter-logo-FINAL README).
struct AllnighterGlyph: View {
    var size: CGFloat = 28

    var body: some View {
        Image("AllnighterLogoWhite")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

