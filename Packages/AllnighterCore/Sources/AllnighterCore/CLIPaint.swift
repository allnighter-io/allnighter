import Foundation

/// Terminal paint for human CLI surfaces. Tokens mirror
/// `docs/design-system/tokens/colors.css` (amber phosphor on midnight).
/// Color is TTY-only: piped / agent-captured output stays plain ASCII+UTF8
/// with zero escapes — same law as `CapacityStripRenderer`.
public enum CLIPaint {
    public static let accent = RGB(r: 255, g: 166, b: 48)       // --amber-500
    public static let accentText = RGB(r: 255, g: 193, b: 105)  // --amber-400, commands
    public static let textPrimary = RGB(r: 225, g: 229, b: 240) // --ink-100
    public static let textMuted = RGB(r: 126, g: 134, b: 158)   // --ink-300
    public static let textFaint = RGB(r: 85, g: 92, b: 116)     // --ink-400
    public static let statusDone = RGB(r: 63, g: 209, b: 139)   // --green-500
    public static let statusFailed = RGB(r: 247, g: 107, b: 107) // --red-500

    public struct RGB: Sendable, Equatable {
        public let r: Int
        public let g: Int
        public let b: Int
        public init(r: Int, g: Int, b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    /// `NO_COLOR` (non-empty) and `TERM=dumb` both force plain. Empty `NO_COLOR`
    /// is treated as unset.
    public static func colorEnabled(
        stdoutIsTTY: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard stdoutIsTTY else { return false }
        if let noColor = environment["NO_COLOR"], !noColor.isEmpty { return false }
        if environment["TERM"] == "dumb" { return false }
        return true
    }

    public static func paint(_ text: String, _ rgb: RGB, bold: Bool = false, color: Bool) -> String {
        guard color, !text.isEmpty else { return text }
        var codes = [String]()
        if bold { codes.append("1") }
        codes.append("38;2;\(rgb.r);\(rgb.g);\(rgb.b)")
        return "\u{1B}[\(codes.joined(separator: ";"))m\(text)\u{1B}[0m"
    }

    public static func accent(_ text: String, bold: Bool = true, color: Bool) -> String {
        paint(text, Self.accent, bold: bold, color: color)
    }

    /// Command lines on the greeting card — lighter amber so the mark stays the hot signal.
    public static func command(_ text: String, color: Bool) -> String {
        paint(text, accentText, bold: false, color: color)
    }

    public static func primary(_ text: String, color: Bool) -> String {
        paint(text, textPrimary, color: color)
    }

    public static func muted(_ text: String, color: Bool) -> String {
        paint(text, textMuted, color: color)
    }

    public static func faint(_ text: String, color: Bool) -> String {
        paint(text, textFaint, color: color)
    }

    public static func done(_ text: String, color: Bool) -> String {
        paint(text, statusDone, color: color)
    }

    /// Solid amber cell — the live-mark cursor block, idle (not blinking).
    public static func cursorBlock(color: Bool) -> String {
        guard color else { return "" }
        return " \u{1B}[48;2;\(accent.r);\(accent.g);\(accent.b)m \u{1B}[0m"
    }

    /// Aligned `label  value` row. Label column is 11 characters.
    public static func row(label: String, value: String, color: Bool, continuation: Bool = false) -> String {
        let labelText: String
        if continuation {
            labelText = String(repeating: " ", count: 11)
        } else {
            labelText = muted(pad(label, 11), color: color)
        }
        return "  \(labelText)  \(value)"
    }

    public static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }

    /// Wordmark + identity lines used by the install receipt and bare `alln` card.
    public static func banner(version: String, status: String? = nil, color: Bool) -> [String] {
        let mark = accent("allnighter", color: color) + cursorBlock(color: color)
        var identity = primary("alln \(version)", color: color)
        if let status {
            identity += faint(" · ", color: color) + done(status, color: color)
        }
        return ["", "  \(mark)", "  \(identity)", ""]
    }

    /// Compact greeting header: `allnighter  1.1.12`
    public static func wordmarkLine(version: String, color: Bool) -> String {
        "  \(accent("allnighter", color: color))  \(faint(version, color: color))"
    }

    /// Command + benefit. No titles.
    public static func lesson(command: String, benefit: String, color: Bool) -> [String] {
        [
            "  \(Self.command(command, color: color))",
            "    \(muted(benefit, color: color))",
            "",
        ]
    }
}
