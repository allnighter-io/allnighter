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

    /// How to emit color when `colorEnabled` is true.
    public enum ColorMode: Sendable, Equatable {
        /// 24-bit foreground/background (`38;2` / `48;2`).
        case truecolor
        /// xterm-256 palette (`38;5` / `48;5`) — safe on macOS Terminal.app.
        case indexed256
    }

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

    /// Resolve paint mode for a color-capable TTY.
    public static func colorMode(
        stdoutIsTTY: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ColorMode? {
        guard colorEnabled(stdoutIsTTY: stdoutIsTTY, environment: environment) else { return nil }
        if usesIndexed256(environment: environment) { return .indexed256 }
        return .truecolor
    }

    /// macOS Terminal.app misparses semicolon truecolor (`38;2;r;g;b`), often as
    /// pink 256-color backgrounds when G or B collide with legacy SGR codes.
    private static func usesIndexed256(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "Apple_Terminal"
    }

    public static func paint(
        _ text: String,
        _ rgb: RGB,
        bold: Bool = false,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        guard color, !text.isEmpty else { return text }
        guard let mode = colorMode(stdoutIsTTY: true, environment: environment) else { return text }
        return "\(escapeForeground(rgb, bold: bold, mode: mode))\(text)\u{1B}[0m"
    }

    public static func accent(
        _ text: String,
        bold: Bool = true,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        paint(text, Self.accent, bold: bold, color: color, environment: environment)
    }

    /// Command lines on the greeting card — lighter amber so the mark stays the hot signal.
    public static func command(
        _ text: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        paint(text, accentText, bold: false, color: color, environment: environment)
    }

    public static func primary(
        _ text: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        paint(text, textPrimary, color: color, environment: environment)
    }

    public static func muted(
        _ text: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        paint(text, textMuted, color: color, environment: environment)
    }

    public static func faint(
        _ text: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        paint(text, textFaint, color: color, environment: environment)
    }

    public static func done(
        _ text: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        paint(text, statusDone, color: color, environment: environment)
    }

    /// Solid amber cell — the live-mark cursor block, idle (not blinking).
    public static func cursorBlock(
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        guard color, let mode = colorMode(stdoutIsTTY: true, environment: environment) else { return "" }
        return " \(escapeBackground(accent, mode: mode)) \u{1B}[0m"
    }

    /// Aligned `label  value` row. Label column is 11 characters.
    public static func row(
        label: String,
        value: String,
        color: Bool,
        continuation: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let labelText: String
        if continuation {
            labelText = String(repeating: " ", count: 11)
        } else {
            labelText = muted(pad(label, 11), color: color, environment: environment)
        }
        return "  \(labelText)  \(value)"
    }

    public static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }

    /// Wordmark + identity lines used by the install receipt and bare `alln` card.
    public static func banner(
        version: String,
        status: String? = nil,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let mark = accent("allnighter", color: color, environment: environment)
            + cursorBlock(color: color, environment: environment)
        var identity = primary("alln \(version)", color: color, environment: environment)
        if let status {
            identity += faint(" · ", color: color, environment: environment)
                + done(status, color: color, environment: environment)
        }
        return ["", "  \(mark)", "  \(identity)", ""]
    }

    /// Compact greeting header: `allnighter  1.1.12`
    public static func wordmarkLine(
        version: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        "  \(accent("allnighter", color: color, environment: environment))  \(faint(version, color: color, environment: environment))"
    }

    /// Command + benefit. No titles.
    public static func lesson(
        command: String,
        benefit: String,
        color: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        [
            "  \(Self.command(command, color: color, environment: environment))",
            "    \(muted(benefit, color: color, environment: environment))",
            "",
        ]
    }

    private static func escapeForeground(_ rgb: RGB, bold: Bool, mode: ColorMode) -> String {
        var codes = [String]()
        if bold { codes.append("1") }
        switch mode {
        case .truecolor:
            codes.append("38;2;\(rgb.r);\(rgb.g);\(rgb.b)")
        case .indexed256:
            codes.append("38;5;\(indexed256(rgb))")
        }
        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }

    private static func escapeBackground(_ rgb: RGB, mode: ColorMode) -> String {
        switch mode {
        case .truecolor:
            return "\u{1B}[48;2;\(rgb.r);\(rgb.g);\(rgb.b)m"
        case .indexed256:
            return "\u{1B}[48;5;\(indexed256(rgb))m"
        }
    }

    /// Nearest xterm-256 index for an sRGB token.
    static func indexed256(_ rgb: RGB) -> Int {
        if rgb.r == rgb.g, rgb.g == rgb.b {
            if rgb.r < 8 { return 16 }
            if rgb.r > 248 { return 231 }
            return 232 + Int((Double(rgb.r - 8) / 247.0 * 23.0).rounded())
        }
        let r = Int((Double(rgb.r) / 255.0 * 5.0).rounded())
        let g = Int((Double(rgb.g) / 255.0 * 5.0).rounded())
        let b = Int((Double(rgb.b) / 255.0 * 5.0).rounded())
        return 16 + 36 * r + 6 * g + b
    }
}
