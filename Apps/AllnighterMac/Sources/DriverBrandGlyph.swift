import SwiftUI

// Monochrome AI brand marks for CLI / bench surfaces. Template SVGs in Assets.xcassets;
// always rendered in ALColor.textPrimary (no per-seat accent tints here).

enum DriverBrandAsset {
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

struct DriverBrandGlyph: View {
    let driverId: String
    var boxSize: CGFloat = 40
    var iconSize: CGFloat? = nil
    var cornerRadius: CGFloat? = nil
    var muted: Bool = false

    private var resolvedIconSize: CGFloat { iconSize ?? boxSize * 0.575 }
    private var resolvedCorner: CGFloat { cornerRadius ?? (boxSize > 24 ? 10 : (boxSize > 20 ? 7 : 5)) }
    private var tint: Color { muted ? ALColor.textFaint : ALColor.textPrimary }

    var body: some View {
        RoundedRectangle(cornerRadius: resolvedCorner)
            .fill(ALColor.active)
            .frame(width: boxSize, height: boxSize)
            .overlay { mark }
            .opacity(muted ? 0.5 : 1)
    }

    @ViewBuilder private var mark: some View {
        if let name = DriverBrandAsset.imageName(for: driverId) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: resolvedIconSize, height: resolvedIconSize)
                .foregroundStyle(tint)
        } else {
            Image(systemName: "cpu")
                .font(.system(size: resolvedIconSize * 0.85))
                .foregroundStyle(tint)
        }
    }
}
