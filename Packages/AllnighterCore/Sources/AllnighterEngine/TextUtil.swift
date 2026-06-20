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

    /// Extracts visible assistant text from Grok's `--output-format streaming-json`.
    ///
    /// - Only `{"type":"text","data":"<delta>"}` chunks are collected (incremental deltas).
    /// - `thought`, `end`, `error`, and any other events are ignored (not part of chat answer text).
    /// - Deltas are concatenated in encounter order to form the final visible answer.
    /// - If no `type:text` events are found, returns the original input unchanged (plain output path).
    static func extractGrokStreamingVisibleText(_ input: String) -> String {
        var collected: [String] = []
        for rawLine in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.first == "{" else { continue }
            guard let data = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let type = obj["type"] as? String, type == "text" else { continue }
            if let delta = obj["data"] as? String {
                collected.append(delta)
            }
        }
        if collected.isEmpty {
            return input
        }
        return collected.joined()
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
