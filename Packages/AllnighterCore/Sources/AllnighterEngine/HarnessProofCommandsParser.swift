import Foundation
import AllnighterCore

/// Parses `proofCommands: [string]` from a relay/pilot dev-turn deliverable
/// (`docs/phases/Process_Ownership.md` PO-S04).
///
/// ## Documented format (dev report tail)
///
/// Prefer a fenced `proofCommands` block at the end of the report:
///
/// ````
/// ```proofCommands
/// ["swift test --filter Foo", "true"]
/// ```
/// ````
///
/// Line-oriented form (one shell command per non-empty, non-`#` line):
///
/// ````
/// ```proofCommands
/// swift test --filter Foo
/// true
/// ```
/// ````
///
/// Or a JSON object (last match wins) anywhere in the report:
///
/// ```json
/// {"proofCommands": ["sleep 300"]}
/// ```
///
/// Turn state (`RelayRound.proofCommands`) wins when already non-empty — the
/// harness never re-parses over an explicit declaration.
public enum HarnessProofCommandsParser {
    /// Resolve the command list: non-empty `turnState` wins; else parse `report`.
    public static func resolve(turnState: [String], report: String?) -> [String] {
        let declared = turnState.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !declared.isEmpty { return declared }
        return parse(from: report ?? "")
    }

    /// Parse proof commands from a free-form dev report.
    public static func parse(from report: String) -> [String] {
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let fromFence = parseProofCommandsFence(in: trimmed), !fromFence.isEmpty {
            return fromFence
        }
        if let fromObject = parseProofCommandsObject(in: trimmed), !fromObject.isEmpty {
            return fromObject
        }
        return []
    }

    // MARK: - Fence

    /// ```proofCommands … ```
    private static func parseProofCommandsFence(in text: String) -> [String]? {
        // Case-insensitive open fence; body until closing ```.
        guard let openRange = text.range(
            of: "```proofCommands",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else { return nil }
        let afterOpen = text[openRange.upperBound...]
        // Optional language trailer on same line (none expected) → skip to newline.
        let bodyStart: String.Index
        if let nl = afterOpen.firstIndex(of: "\n") {
            bodyStart = afterOpen.index(after: nl)
        } else {
            bodyStart = afterOpen.startIndex
        }
        let rest = afterOpen[bodyStart...]
        let body: Substring
        if let close = rest.range(of: "```") {
            body = rest[..<close.lowerBound]
        } else {
            body = rest
        }
        let bodyText = String(body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bodyText.isEmpty else { return [] }

        // Prefer JSON array body.
        if bodyText.hasPrefix("[") {
            if let data = bodyText.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        // Line-oriented.
        return bodyText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { stripListMarker($0) }
            .filter { !$0.isEmpty }
    }

    private static func stripListMarker(_ line: String) -> String {
        var s = line
        if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
        else if s.hasPrefix("* ") { s = String(s.dropFirst(2)) }
        // Strip surrounding backticks: `cmd`
        if s.hasPrefix("`"), s.hasSuffix("`"), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON object

    /// Last `{"proofCommands":[...]}` object found in the text.
    private static func parseProofCommandsObject(in text: String) -> [String]? {
        // Scan for the key; try decoding from each candidate `{` backward.
        var last: [String]?
        var search = text.startIndex
        while search < text.endIndex,
              let keyRange = text.range(of: "\"proofCommands\"", range: search..<text.endIndex) {
            // Walk left to nearest `{`.
            var brace = keyRange.lowerBound
            var found: String.Index?
            while brace > text.startIndex {
                brace = text.index(before: brace)
                if text[brace] == "{" {
                    found = brace
                    break
                }
                if text[brace] == "}" { break }
            }
            if let start = found {
                // Expand to a balanced JSON object (best-effort).
                if let json = extractBalancedObject(from: text, startingAt: start),
                   let data = json.data(using: .utf8),
                   let obj = try? JSONDecoder().decode(ProofCommandsEnvelope.self, from: data),
                   !obj.proofCommands.isEmpty {
                    last = obj.proofCommands
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
            search = keyRange.upperBound
        }
        return last
    }

    private static func extractBalancedObject(from text: String, startingAt: String.Index) -> String? {
        var depth = 0
        var i = startingAt
        var inString = false
        var escape = false
        while i < text.endIndex {
            let ch = text[i]
            if inString {
                if escape { escape = false }
                else if ch == "\\" { escape = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[startingAt...i])
                    }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    private struct ProofCommandsEnvelope: Decodable {
        var proofCommands: [String]
    }
}
