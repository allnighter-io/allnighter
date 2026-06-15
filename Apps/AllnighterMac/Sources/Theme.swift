import SwiftUI

// Allnighter design tokens — the single Swift source of truth for the app's
// visual layer. Mirrors `docs/design-system/tokens/*`. Per
// `docs/design-system/production.md` §1, views consume these named tokens; do
// not hard-code hex in views. "Amber phosphor on midnight," dark mode only.

// MARK: - Color tokens

extension Color {
    /// Hex literal initializer, e.g. `Color(hex: 0xFFA630)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    // --- Midnight / ink ramp (50 = lightest text → 950 = deepest void) ---
    static let alInk50 = Color(hex: 0xF2F4FA)
    static let alInk100 = Color(hex: 0xE1E5F0)
    static let alInk200 = Color(hex: 0xAEB5C9)
    static let alInk300 = Color(hex: 0x7E869E)
    static let alInk400 = Color(hex: 0x555C74)
    static let alInk450 = Color(hex: 0x454C62)
    static let alInk500 = Color(hex: 0x373D51)
    static let alInk600 = Color(hex: 0x252A39)
    static let alInk650 = Color(hex: 0x1F2331)
    static let alInk700 = Color(hex: 0x1A1E2A)
    static let alInk750 = Color(hex: 0x151822)
    static let alInk800 = Color(hex: 0x111420)
    static let alInk850 = Color(hex: 0x0D101A)
    static let alInk900 = Color(hex: 0x090B13)
    static let alInk950 = Color(hex: 0x05060C)

    // --- Signature amber phosphor ---
    static let alAmber300 = Color(hex: 0xFFD79E)
    static let alAmber400 = Color(hex: 0xFFC169)
    static let alAmber500 = Color(hex: 0xFFA630) // PRIMARY brand amber
    static let alAmber600 = Color(hex: 0xF08D1C)

    // --- Status hues (muted, dev-tool calm) ---
    static let alGreen400 = Color(hex: 0x5BDBA0)
    static let alGreen500 = Color(hex: 0x3FD18B)
    static let alRed400 = Color(hex: 0xFF8585)
    static let alRed500 = Color(hex: 0xF76B6B)
    static let alBlue400 = Color(hex: 0x7DB2FF)
    static let alBlue500 = Color(hex: 0x5B9DFF)
    static let alYellow400 = Color(hex: 0xFCD66A)
    static let alYellow500 = Color(hex: 0xF5C84B)

    // --- Semantic: backgrounds (deep → raised) ---
    static let alBgVoid = alInk950
    static let alBgBase = alInk900
    static let alBgSubtle = alInk850
    static let alBgSurface = alInk800
    static let alBgRaised = alInk750
    static let alBgHover = alInk700
    static let alBgActive = alInk650
    static let alBgInput = Color(hex: 0x13161F)
    static let alBgOverlay = Color(hex: 0x05060C, opacity: 0.66)

    // --- Semantic: borders (white-alpha, read on any surface) ---
    static let alBorderSubtle = Color.white.opacity(0.06)
    static let alBorderDefault = Color.white.opacity(0.10)
    static let alBorderStrong = Color.white.opacity(0.16)
    static let alBorderSolid = alInk600

    // --- Semantic: text ---
    static let alTextPrimary = alInk100
    static let alTextSecondary = alInk200
    static let alTextMuted = alInk300
    static let alTextFaint = alInk400
    static let alTextDisabled = alInk450
    static let alTextOnAmber = Color(hex: 0x1A1203)

    // --- Semantic: accent (amber) ---
    static let alAccent = alAmber500
    static let alAccentHover = alAmber400
    static let alAccentPress = alAmber600
    static let alAccentText = alAmber400
    static let alAccentSurface = Color(hex: 0xFFA630, opacity: 0.12)
    static let alAccentBorder = Color(hex: 0xFFA630, opacity: 0.32)

    // --- Semantic: status ---
    static let alStatusQueued = alInk400
    static let alStatusRunning = alBlue500
    static let alStatusDone = alGreen500
    static let alStatusFailed = alRed500
    static let alStatusTimeout = alYellow500

    // --- Semantic: status surfaces (12% tints) ---
    static let alInfoSurface = Color(hex: 0x5B9DFF, opacity: 0.12)
    static let alSuccessSurface = Color(hex: 0x3FD18B, opacity: 0.12)
    static let alDangerSurface = Color(hex: 0xF76B6B, opacity: 0.12)
    static let alWarningSurface = Color(hex: 0xF5C84B, opacity: 0.12)
}

// MARK: - Font tokens
//
// Native: SF Pro (sans) + SF Mono. macOS app density → 13px base body.
// Weights: regular 400 · medium 500 · semibold 600 · bold 700 · extrabold ≈ heavy.

extension Font {
    static let alDisplay = Font.system(size: 40, weight: .heavy)
    static let alH1 = Font.system(size: 28, weight: .bold)
    static let alH2 = Font.system(size: 22, weight: .bold)
    static let alH3 = Font.system(size: 17, weight: .semibold)
    static let alTitle = Font.system(size: 15, weight: .semibold)
    static let alBody = Font.system(size: 13, weight: .regular)
    static let alBodyLg = Font.system(size: 15, weight: .regular)
    static let alLabel = Font.system(size: 12, weight: .medium)
    static let alCaption = Font.system(size: 11, weight: .regular)
    static let alMono = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let alMonoSm = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// Uppercase eyebrow / section label.
    static let alEyebrow = Font.system(size: 11, weight: .semibold)
}

// MARK: - Scalars (spacing · radii · control sizing · layout)

enum Theme {
    enum Space {
        static let s1: CGFloat = 4
        static let s1_5: CGFloat = 6
        static let s2: CGFloat = 8
        static let s2_5: CGFloat = 10
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
        static let window: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Control {
        static let hSm: CGFloat = 24
        static let h: CGFloat = 30
        static let hLg: CGFloat = 36
    }

    enum Layout {
        static let sidebarW: CGFloat = 248
        static let inspectorW: CGFloat = 300
    }

    enum Motion {
        static let fast: Double = 0.14
        static let normal: Double = 0.20
        static let slow: Double = 0.28
        /// The "working" heartbeat — the same blink the live mark uses.
        static let blink = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }
}

// MARK: - Elevation & glow modifiers
//
// Dark-mode depth = lighter surfaces + hairline borders + deep-black shadows.
// Amber glow marks "alive" / primary moments. (Blur radii ≈ CSS blur / 2.)

extension View {
    func alShadowSm() -> some View { shadow(color: .black.opacity(0.45), radius: 3, y: 2) }
    func alShadowMd() -> some View { shadow(color: .black.opacity(0.55), radius: 10, y: 8) }

    /// Amber glow for hover/primary/live moments. `active` drives it on.
    func alGlowAmber(_ active: Bool = true, strong: Bool = false) -> some View {
        shadow(color: Color.alAmber500.opacity(active ? (strong ? 0.45 : 0.30) : 0),
               radius: active ? (strong ? 24 : 12) : 0)
    }
}
