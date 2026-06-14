import Foundation

enum TextUtil {
    /// Strips ANSI/VT100 escape sequences (colors, cursor moves) that CLIs emit
    /// even in headless mode, so captured answers are clean Markdown/text.
    static func stripANSI(_ input: String) -> String {
        // CSI sequences: ESC [ ... final-byte ; plus standalone ESC ] ... BEL (OSC).
        let patterns = [
            "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",  // CSI
            "\u{1B}\\][^\u{07}]*\u{07}",       // OSC terminated by BEL
            "\u{1B}[@-Z\\\\-_]"                  // single-char escapes
        ]
        var output = input
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(output.startIndex..., in: output)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "")
            }
        }
        return output
    }
}

/// Splits a trusted command-line string (from a driver manifest's
/// `detectCommand`/`smokeTestCommand`) into argv, honoring single/double
/// quotes. NEVER used on user prompt content — prompts always flow through
/// structured argv (`DriverManifest.resolvedArgs`).
enum ShellWords {
    static func split(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var hasToken = false

        var iterator = input.makeIterator()
        while let char = iterator.next() {
            if char == "'" && !inDouble {
                inSingle.toggle()
                hasToken = true
                continue
            }
            if char == "\"" && !inSingle {
                inDouble.toggle()
                hasToken = true
                continue
            }
            if (char == " " || char == "\t" || char == "\n") && !inSingle && !inDouble {
                if hasToken {
                    words.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }
            current.append(char)
            hasToken = true
        }
        if hasToken {
            words.append(current)
        }
        return words
    }
}
