// ============================================================
//  AllnighterTokens.swift
//  Token → SwiftUI mapping for the Allnighter "Council" macOS app.
//  Dark-mode only ("amber phosphor on midnight").
//
//  This is the single source of truth for color, type, spacing,
//  radius, elevation, and motion in the native app. It is a direct
//  port of the design-system CSS custom properties — keep the names
//  aligned so design and code stay in lockstep.
//
//  Target: macOS 14+, SwiftUI. No external dependencies.
// ============================================================

import SwiftUI

// MARK: - Hex helper

extension Color {
    /// `Color(hex: 0xFFA630)` — opaque. Use `.opacity()` for alpha.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Palette (raw ramps — prefer the semantic aliases below)

enum ALPalette {
    // Midnight / ink ramp (blue-tinted). 50 = lightest text → 950 = deepest void.
    static let ink50  = Color(hex: 0xF2F4FA)
    static let ink100 = Color(hex: 0xE1E5F0)
    static let ink150 = Color(hex: 0xCBD1E0)
    static let ink200 = Color(hex: 0xAEB5C9)
    static let ink300 = Color(hex: 0x7E869E)
    static let ink400 = Color(hex: 0x555C74)
    static let ink450 = Color(hex: 0x454C62)
    static let ink500 = Color(hex: 0x373D51)
    static let ink600 = Color(hex: 0x252A39)
    static let ink650 = Color(hex: 0x1F2331)
    static let ink700 = Color(hex: 0x1A1E2A)
    static let ink750 = Color(hex: 0x151822)   // raised surface
    static let ink800 = Color(hex: 0x111420)   // surface
    static let ink850 = Color(hex: 0x0D101A)   // subtle bg
    static let ink900 = Color(hex: 0x090B13)   // app base
    static let ink950 = Color(hex: 0x05060C)   // void

    // Signature amber phosphor.
    static let amber300 = Color(hex: 0xFFD79E)
    static let amber400 = Color(hex: 0xFFC169)
    static let amber500 = Color(hex: 0xFFA630)  // PRIMARY brand amber
    static let amber600 = Color(hex: 0xF08D1C)
    static let amber700 = Color(hex: 0xC26F12)

    // Status hues (muted, calm).
    static let green400 = Color(hex: 0x5BDBA0)
    static let green500 = Color(hex: 0x3FD18B)  // done / healthy
    static let red400   = Color(hex: 0xFF8585)
    static let red500   = Color(hex: 0xF76B6B)  // failed / destructive
    static let blue400  = Color(hex: 0x7DB2FF)
    static let blue500  = Color(hex: 0x5B9DFF)  // running / info
    static let yellow400 = Color(hex: 0xFCD66A)
    static let yellow500 = Color(hex: 0xF5C84B) // warning / timed-out
}

// MARK: - Semantic colors (USE THESE in views)

enum ALColor {
    // Backgrounds (deep → raised)
    static let void     = ALPalette.ink950   // behind the window
    static let base     = ALPalette.ink900   // app background / main canvas
    static let subtle   = ALPalette.ink850   // sidebar / sunken
    static let surface  = ALPalette.ink800   // title bar, panels, toolbars
    static let raised   = ALPalette.ink750   // cards, popovers, menus
    static let hover    = ALPalette.ink700   // row / control hover
    static let active   = ALPalette.ink650   // pressed / selected
    static let input    = Color(hex: 0x13161F)
    static let overlay  = ALPalette.ink950.opacity(0.66) // modal scrim
    static let scrimSubtle = ALPalette.ink950.opacity(0.28) // dropdown dismiss — content only

    // Borders — white-alpha so they read on any surface
    static let borderSubtle  = Color.white.opacity(0.06)
    static let borderDefault = Color.white.opacity(0.10)
    static let borderStrong  = Color.white.opacity(0.16)

    // Text
    static let textPrimary   = ALPalette.ink100
    static let textSecondary = ALPalette.ink200
    static let textMuted     = ALPalette.ink300
    static let textFaint     = ALPalette.ink400
    static let textOnAmber   = Color(hex: 0x1A1203) // near-black ink on amber fills
    static let textOnLight   = ALPalette.ink900      // near-black ink on light fills

    // Light "action" fill — the primary affordance color used SPARINGLY for the
    // send / commit actions so amber stays a rare accent, not the whole UI.
    static let actionLight   = ALPalette.ink50

    // Accent (amber)
    static let accent        = ALPalette.amber500
    static let accentHover   = ALPalette.amber400  // dark-mode hover LIGHTENS
    static let accentPress   = ALPalette.amber600
    static let accentText    = ALPalette.amber400  // amber AS text (lighter, legible)
    static let accentSurface = ALPalette.amber500.opacity(0.12)
    static let accentBorder  = ALPalette.amber500.opacity(0.32)

    // Status — semantic (map StatusPill states to these)
    static let statusQueued  = ALPalette.ink400
    static let statusRunning = ALPalette.blue500
    static let statusDone    = ALPalette.green500
    static let statusFailed  = ALPalette.red500
    static let statusTimeout = ALPalette.yellow500

    // Tinted status surfaces (12% fills behind pills/section icons)
    static let successSurface = ALPalette.green500.opacity(0.12)
    static let dangerSurface  = ALPalette.red500.opacity(0.12)
    static let infoSurface    = ALPalette.blue500.opacity(0.12)
    static let warningSurface = ALPalette.yellow500.opacity(0.12)
}

// MARK: - Typography
//
// SF Pro is the macOS system face → use `.system(...)`. SF Mono is the
// monospaced system face → `.system(..., design: .monospaced)`.
// Weight map:  400 .regular · 500 .medium · 600 .semibold · 700 .bold · 800 .heavy
//
// IMPORTANT conversions from CSS:
//  • letter-spacing (em) → SwiftUI `.tracking(points)` = em × fontSize.
//  • line-height (unitless) → `.lineSpacing(extra)` where
//    extra ≈ (lineHeight − 1) × fontSize. SF runs tight; values below are baked in.

enum ALFont {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Named ramp (size, weight, tracking-pts, lineSpacing-extra)
    static let display = sans(40, .heavy)     // tracking -0.88,  marketing only
    static let h1      = sans(28, .bold)      // tracking -0.39
    static let h2      = sans(22, .bold)      // tracking -0.31 — "Team run" title
    static let h3      = sans(17, .semibold)
    static let title   = sans(15, .semibold)  // section titles, sidebar plan writer
    static let bodyLg  = sans(15, .regular)   // comfortable reading body
    static let body    = sans(13, .regular)   // macOS body — DEFAULT
    static let label   = sans(12, .medium)    // control labels, history rows
    static let caption = sans(11, .regular)   // metadata, eyebrows
    static let monoSm  = mono(11, .medium)    // slugs, counts, timings
    static let mono    = mono(12, .medium)    // model IDs, token counts
}

// Tracking values to apply alongside the fonts above (points):
//   display -0.88 · h1 -0.39 · h2 -0.31 · body/title -0.08 · eyebrow/caps +0.9
enum ALTracking {
    static let display: CGFloat = -0.88
    static let heading: CGFloat = -0.31
    static let normal:  CGFloat = -0.08
    static let caps:    CGFloat = 0.9   // uppercase eyebrows / section headers
}

// MARK: - Spacing (4px base grid)

enum ALSpace {
    static let s1: CGFloat = 4
    static let s1_5: CGFloat = 6
    static let s2: CGFloat = 8
    static let s2_5: CGFloat = 10
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 28
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
}

// MARK: - Radii

enum ALRadius {
    static let xs: CGFloat = 4    // tags
    static let sm: CGFloat = 6    // buttons, inputs, controls
    static let md: CGFloat = 8    // small cards, menu items, worker glyph
    static let lg: CGFloat = 10   // cards
    static let xl: CGFloat = 14   // panels, the prompt composer
    static let xxl: CGFloat = 18  // modals
    static let window: CGFloat = 12
    static let pill: CGFloat = 999 // status pills, history dots
}

// MARK: - Control heights (macOS-native)

enum ALControl {
    static let heightSm: CGFloat = 24
    static let height:   CGFloat = 30   // default button / input
    static let heightLg: CGFloat = 36
    static let sidebarWidth: CGFloat = 264
    static let titleBarHeight: CGFloat = 44
    static let readingMax: CGFloat = 680 // composer column cap
}

// MARK: - Elevation & glow
//
// SwiftUI `.shadow` has no spread radius (the CSS "-Npx" 4th value).
// Approximate by reducing radius slightly. Dark-mode shadows are pure
// black, low opacity, generous blur. The amber glow marks "alive".

extension View {
    func alShadowSm() -> some View { shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2) }
    func alShadowMd() -> some View { shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8) }
    func alShadowXl() -> some View { shadow(color: .black.opacity(0.70), radius: 40, x: 0, y: 24) }
    /// Amber glow for the primary button on hover and "alive" elements.
    func alGlowAmber() -> some View { shadow(color: ALColor.accent.opacity(0.35), radius: 12, x: 0, y: 0) }
}

// MARK: - Motion
//
// Quick, confident: 120–280ms, ease-out for almost everything.
// One restrained spring for "alive" moments (worker done, toast).

enum ALMotion {
    static let fast    = Animation.easeOut(duration: 0.14)
    static let normal  = Animation.easeOut(duration: 0.20)
    static let slow    = Animation.easeOut(duration: 0.28)
    static let spring  = Animation.spring(response: 0.34, dampingFraction: 0.7)
    /// The "working" pulse — opacity 1 → 0.45 → 1, ~1.4s, used on live dots.
    static let pulse   = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    /// The cursor-block blink on the live mark — hard on/off, 1.05s.
    static let blink   = Animation.linear(duration: 1.05).repeatForever(autoreverses: false)
}
