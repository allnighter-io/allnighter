//
//  IOSDriverBrandGlyph.swift
//  AllnighteriOS
//
//  Monochrome AI brand marks — template SVGs shared with the Mac app catalog.
//

import SwiftUI

enum IOSDriverBrandAsset {
    static let onboardingStackDriverIds = [
        "claude_code",
        "codex",
        "cursor_agent",
        "grok",
        "antigravity",
    ]

    static func imageName(for driverId: String) -> String? {
        switch driverId {
        case "claude_code": "claude"
        case "antigravity": "googlegemini"
        case "grok": "grok"
        case "codex": "openai"
        case "cursor_agent": "cursor"
        default: nil
        }
    }
}

struct IOSDriverBrandGlyphView: View {
    let driverId: String
    var boxSize: CGFloat = 28
    var iconSize: CGFloat? = nil
    var cornerRadius: CGFloat? = nil
    var muted: Bool = false

    private var resolvedIconSize: CGFloat { iconSize ?? boxSize * 0.575 }
    private var resolvedCorner: CGFloat { cornerRadius ?? (boxSize > 24 ? 10 : (boxSize > 20 ? 7 : 5)) }
    private var tint: Color { muted ? IOSColor.textFaint : IOSColor.textPrimary }

    var body: some View {
        RoundedRectangle(cornerRadius: resolvedCorner, style: .continuous)
            .fill(IOSColor.active)
            .frame(width: boxSize, height: boxSize)
            .overlay { mark }
            .opacity(muted ? 0.5 : 1)
    }

    @ViewBuilder
    private var mark: some View {
        if let name = IOSDriverBrandAsset.imageName(for: driverId) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: resolvedIconSize, height: resolvedIconSize)
                .foregroundStyle(tint)
        } else {
            Image(systemName: "cpu")
                .font(.system(size: resolvedIconSize * 0.85, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

struct IOSTeamBrandGlyphStack: View {
    var driverIds: [String] = IOSDriverBrandAsset.onboardingStackDriverIds
    var tileSize: CGFloat = 44
    var overlap: CGFloat = 14

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(driverIds.enumerated()), id: \.offset) { index, driverId in
                IOSDriverBrandGlyphView(
                    driverId: driverId,
                    boxSize: tileSize,
                    iconSize: tileSize * 0.52,
                    cornerRadius: 11
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(IOSColor.surface, lineWidth: 2)
                }
                .zIndex(Double(index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude, Codex, Cursor, Grok, and Gemini")
    }
}
