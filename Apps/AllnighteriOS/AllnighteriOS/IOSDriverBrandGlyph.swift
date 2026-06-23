//
//  IOSDriverBrandGlyph.swift
//  AllnighteriOS
//
//  Monochrome driver mark for thread + composer (SF Symbol fallback).
//

import SwiftUI

enum IOSDriverBrandGlyph {
    static func systemImage(for driverId: String) -> String {
        switch driverId {
        case "claude_code": "sparkles"
        case "codex": "circle.hexagongrid.fill"
        case "grok": "bolt.fill"
        case "antigravity": "globe.americas.fill"
        case "cursor_agent": "cursorarrow.rays"
        default: "cpu"
        }
    }
}

struct IOSDriverBrandGlyphView: View {
    let driverId: String
    var boxSize: CGFloat = 28
    var iconSize: CGFloat? = nil

    private var resolvedIconSize: CGFloat { iconSize ?? boxSize * 0.5 }

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(IOSColor.active)
            .frame(width: boxSize, height: boxSize)
            .overlay {
                Image(systemName: IOSDriverBrandGlyph.systemImage(for: driverId))
                    .font(.system(size: resolvedIconSize, weight: .semibold))
                    .foregroundStyle(IOSColor.textSecondary)
            }
    }
}
