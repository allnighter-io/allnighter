//
//  AllnighteriOSTheme.swift
//  AllnighteriOS
//
//  Dark-mode native tokens for the iOS companion.
//

import SwiftUI

extension Color {
    init(allnighterHex hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

enum IOSPalette {
    static let ink100 = Color(allnighterHex: 0xE1E5F0)
    static let ink150 = Color(allnighterHex: 0xCBD1E0)
    static let ink300 = Color(allnighterHex: 0x7E869E)
    static let ink400 = Color(allnighterHex: 0x555C74)
    static let ink650 = Color(allnighterHex: 0x242833)
    static let ink750 = Color(allnighterHex: 0x1B1E29)
    static let ink800 = Color(allnighterHex: 0x181B25)
    static let ink850 = Color(allnighterHex: 0x15171F)
    static let ink900 = Color(allnighterHex: 0x13151E)
    static let ink950 = Color(allnighterHex: 0x0C0E14)

    static let amber400 = Color(allnighterHex: 0xFFC169)
    static let amber500 = Color(allnighterHex: 0xFFA630)
}

enum IOSColor {
    static let void = IOSPalette.ink950
    static let subtle = IOSPalette.ink850
    static let surface = IOSPalette.ink800
    static let raised = IOSPalette.ink750
    static let active = IOSPalette.ink650

    static let borderSubtle = Color.white.opacity(0.07)
    static let borderDefault = Color.white.opacity(0.12)
    static let borderStrong = Color.white.opacity(0.18)

    static let textPrimary = IOSPalette.ink100
    static let textSecondary = IOSPalette.ink150
    static let textMuted = IOSPalette.ink300
    static let textFaint = IOSPalette.ink400
    static let textOnLight = IOSPalette.ink900

    static let accent = IOSPalette.amber500
    static let accentText = IOSPalette.amber400
    static let accentSurface = IOSPalette.amber500.opacity(0.14)
    static let accentBorder = IOSPalette.amber500.opacity(0.34)
}

enum IOSFont {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let display = sans(46, .bold)
    static let title = sans(28, .bold)
    static let section = sans(14, .semibold)
    static let body = sans(17, .regular)
    static let bodyStrong = sans(17, .semibold)
    static let label = sans(15, .semibold)
    static let mono = mono(13, .medium)
    static let monoSm = mono(12, .medium)
}

enum IOSSpace {
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s7: CGFloat = 28
    static let s8: CGFloat = 32
}

enum IOSRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
}
