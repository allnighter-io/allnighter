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

    /// Extracts visible assistant text from OpenCode's default formatted stdout.
    ///
    /// OpenCode prints the assistant answer followed by a metadata footer line
    /// like `> Build · model · 1.2s`. This extractor:
    /// 1. Strips ANSI escape sequences.
    /// 2. Drops lines matching `^> Build ·` or `^> .+ · .+ · [\d.]+s$` metadata footers.
    /// 3. Trims leading/trailing whitespace.
    /// 4. If empty after strip, returns the original input (fallback path).
    static func extractOpenCodeVisibleText(_ input: String) -> String {
        let stripped = stripANSI(input)
        let footerPatterns = [
            "^> Build ·.*$",
            "^> .+ · .+ · [0-9.]+s$"
        ]
        var keptLines: [String] = []
        for line in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            var isFooter = false
            for pattern in footerPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                    let range = NSRange(lineText.startIndex..., in: lineText)
                    if regex.firstMatch(in: lineText, range: range) != nil {
                        isFooter = true
                        break
                    }
                }
            }
            if !isFooter { keptLines.append(lineText) }
        }
        let result = keptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? input : result
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

    /// Strips model reasoning/"thinking" blocks from assistant text so only the
    /// visible answer remains. Pure; deterministic.
    static func stripReasoningBlocks(_ input: String) -> String {
        let tagPattern = "</?(?:thinking|think)>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let nsRange = NSRange(input.startIndex..., in: input)
        let matches = regex.matches(in: input, range: nsRange)
        guard !matches.isEmpty else {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var output = ""
        var depth = 0
        var lastEnd = input.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: input) else { continue }
            if depth == 0 {
                output += input[lastEnd..<matchRange.lowerBound]
            }
            let tag = String(input[matchRange])
            if tag.hasPrefix("</") {
                if depth > 0 {
                    depth -= 1
                } else {
                    output += tag
                }
            } else {
                depth += 1
            }
            lastEnd = matchRange.upperBound
        }
        if depth == 0 {
            output += input[lastEnd...]
        }
        if let nlRegex = try? NSRegularExpression(pattern: "\\n{3,}") {
            let r = NSRange(output.startIndex..., in: output)
            output = nlRegex.stringByReplacingMatches(in: output, range: r, withTemplate: "\n\n")
        }
        if let spRegex = try? NSRegularExpression(pattern: " {2,}") {
            let r = NSRange(output.startIndex..., in: output)
            output = spRegex.stringByReplacingMatches(in: output, range: r, withTemplate: " ")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
