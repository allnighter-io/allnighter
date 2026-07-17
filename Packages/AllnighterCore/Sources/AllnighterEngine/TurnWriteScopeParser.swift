import Foundation
import AllnighterCore

/// Parses `writeScope` + `needsBuildLane` from a relay/pilot dev-turn deliverable
/// (`docs/phases/Process_Ownership.md` PO-S06).
///
/// Same surface as `HarnessProofCommandsParser` (PO-S04): turn state wins when set;
/// otherwise fenced blocks and JSON objects in the report tail.
///
/// ## Formats
///
/// Fenced paths (one prefix per line, or a JSON array body):
///
/// ````
/// ```writeScope
/// docs/
/// docs/phases/
/// ```
/// ````
///
/// Fenced build-lane flag:
///
/// ````
/// ```needsBuildLane
/// false
/// ```
/// ````
///
/// JSON object (last match wins) anywhere in the report:
///
/// ```json
/// {"writeScope": ["docs/"], "needsBuildLane": false}
/// ```
///
/// **Absent declaration** → `TurnWriteScope.legacyFullBuild` (full scope + build lane).
public enum TurnWriteScopeParser {
    /// Resolve: non-nil `turnState` wins entirely; else parse `report`.
    public static func resolve(turnState: TurnWriteScope?, report: String?) -> TurnWriteScope {
        if let turnState { return turnState }
        return parse(from: report ?? "") ?? .legacyFullBuild
    }

    /// Parse a declaration from free-form report text. `nil` when nothing declared
    /// (caller should treat as legacy full-build).
    public static func parse(from report: String) -> TurnWriteScope? {
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var prefixes: [String]?
        var needsBuild: Bool?
        var sawAnything = false

        if let fromFence = parseWriteScopeFence(in: trimmed) {
            prefixes = fromFence
            sawAnything = true
        }
        if let flag = parseNeedsBuildLaneFence(in: trimmed) {
            needsBuild = flag
            sawAnything = true
        }
        if let obj = parseScopeObject(in: trimmed) {
            if let p = obj.writeScope {
                prefixes = p
                sawAnything = true
            }
            if let n = obj.needsBuildLane {
                needsBuild = n
                sawAnything = true
            }
        }

        guard sawAnything else { return nil }
        return TurnWriteScope(
            pathPrefixes: prefixes ?? [],
            needsBuildLane: needsBuild ?? true
        )
    }

    // MARK: - Fences

    private static func parseWriteScopeFence(in text: String) -> [String]? {
        guard let body = fenceBody(named: "writeScope", in: text) else { return nil }
        guard !body.isEmpty else { return [] }
        if body.hasPrefix("[") {
            if let data = body.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                return arr.map { TurnWriteScope.normalizePrefix($0) }.filter { !$0.isEmpty }
            }
        }
        return body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { stripListMarker($0) }
            .map { TurnWriteScope.normalizePrefix($0) }
            .filter { !$0.isEmpty }
    }

    private static func parseNeedsBuildLaneFence(in text: String) -> Bool? {
        // Accept needsBuildLane or buildLane fence names.
        let body = fenceBody(named: "needsBuildLane", in: text)
            ?? fenceBody(named: "buildLane", in: text)
        guard let body, !body.isEmpty else { return nil }
        let line = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { stripListMarker($0) }
        guard let line else { return nil }
        return parseBool(line)
    }

    private static func fenceBody(named name: String, in text: String) -> String? {
        guard let openRange = text.range(
            of: "```\(name)",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else { return nil }
        let afterOpen = text[openRange.upperBound...]
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
        return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripListMarker(_ line: String) -> String {
        var s = line
        if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
        else if s.hasPrefix("* ") { s = String(s.dropFirst(2)) }
        if s.hasPrefix("`"), s.hasSuffix("`"), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "true", "yes", "1", "on": return true
        case "false", "no", "0", "off": return false
        default: return nil
        }
    }

    // MARK: - JSON object

    private struct ScopeEnvelope: Decodable {
        var writeScope: [String]?
        var needsBuildLane: Bool?
        // Alias some agents may emit.
        var buildLane: Bool?

        var resolvedNeedsBuild: Bool? { needsBuildLane ?? buildLane }
    }

    private static func parseScopeObject(in text: String) -> (
        writeScope: [String]?, needsBuildLane: Bool?
    )? {
        var last: (writeScope: [String]?, needsBuildLane: Bool?)?
        var search = text.startIndex
        while search < text.endIndex {
            let nextWrite = text.range(of: "\"writeScope\"", range: search..<text.endIndex)
            let nextNeeds = text.range(of: "\"needsBuildLane\"", range: search..<text.endIndex)
            let nextBuild = text.range(of: "\"buildLane\"", range: search..<text.endIndex)
            let candidates = [nextWrite, nextNeeds, nextBuild].compactMap { $0 }
            guard let keyRange = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else {
                break
            }
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
            if let start = found,
               let json = extractBalancedObject(from: text, startingAt: start),
               let data = json.data(using: .utf8),
               let obj = try? JSONDecoder().decode(ScopeEnvelope.self, from: data) {
                let prefixes = obj.writeScope.map {
                    $0.map { TurnWriteScope.normalizePrefix($0) }.filter { !$0.isEmpty }
                }
                last = (writeScope: prefixes, needsBuildLane: obj.resolvedNeedsBuild)
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
}
