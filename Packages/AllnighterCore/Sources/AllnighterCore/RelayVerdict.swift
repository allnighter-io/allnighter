import Foundation

/// The only structured artifact in the PM Relay loop (docs/phases/PM_Relay.md §4).
/// Every PM turn ends with one small JSON block; everything else is prose. `done` is
/// **declared, never inferred** — the loop only ends happily on `verdict == .done`.
public struct RelayVerdict: Sendable, Codable, Equatable {
    /// The three ways a PM turn can end. `continueRelay` is the Swift-safe name for
    /// the wire value `"continue"` — `continue` itself is a reserved word.
    public enum Verdict: String, Sendable, Codable, CaseIterable {
        case continueRelay = "continue"
        case done
        case escalate
    }

    public var verdict: Verdict
    /// Required when `verdict == .continueRelay` — the verbatim text for the dev's next
    /// turn. Missing/empty is the parser's re-ask trigger (§4.1); the coordinator, not
    /// this type, owns the one-re-ask policy.
    public var handover: String?
    /// `done`: closing summary. `escalate`: what the human must decide.
    public var note: String?

    public init(verdict: Verdict, handover: String? = nil, note: String? = nil) {
        self.verdict = verdict
        self.handover = handover
        self.note = note
    }
}

/// Tolerant tail-extraction of a `RelayVerdict` from a PM turn's raw output (§4.1).
/// The PM may emit other JSON earlier in its answer (analysis, artifacts) — the verdict
/// is always the LAST JSON object in the output that carries a `verdict` key, fenced in
/// a ```json block or bare. This lifts it, validates it, and returns the PM's prose with
/// the verdict block removed — exactly what the founder would have pasted to the dev.
public enum RelayVerdictParser {
    /// The parsed verdict plus the handover-ready prose (verdict block stripped).
    public struct Extraction: Sendable, Equatable {
        public var verdict: RelayVerdict
        public var strippedOutput: String

        public init(verdict: RelayVerdict, strippedOutput: String) {
            self.verdict = verdict
            self.strippedOutput = strippedOutput
        }
    }

    /// Precise failure reasons — the coordinator decides what to do with each (re-ask,
    /// escalate); this type only reports.
    public enum ExtractError: Swift.Error, Sendable, Equatable {
        /// No JSON object anywhere in the output carried a `verdict` key.
        case noVerdictFound
        /// A verdict block was found but its `verdict` value isn't `continue`/`done`/`escalate`.
        case unknownVerdict(String)
        /// `verdict: "continue"` with a missing or empty `handover` — the re-ask trigger.
        case continueWithoutHandover
    }

    public static func extract(from pmOutput: String) -> Result<Extraction, ExtractError> {
        let fenced = fencedBlocks(in: pmOutput)
        let bareRanges = topLevelObjectRanges(in: pmOutput, excluding: fenced.map(\.fullRange))

        var candidates: [(start: String.Index, removalRange: Range<String.Index>, jsonText: String)] =
            fenced.map { ($0.fullRange.lowerBound, $0.fullRange, $0.inner) }
        candidates += bareRanges.map { ($0.lowerBound, $0, String(pmOutput[$0])) }
        candidates.sort { $0.start < $1.start }

        // Walk in document order, keeping the LAST candidate whose JSON is an object
        // carrying a "verdict" key — that's the tail, whatever else the PM emitted.
        var winner: (removalRange: Range<String.Index>, object: [String: Any])?
        for candidate in candidates {
            guard let data = candidate.jsonText.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  object["verdict"] != nil else { continue }
            winner = (candidate.removalRange, object)
        }

        guard let (removalRange, object) = winner else {
            return .failure(.noVerdictFound)
        }

        let rawVerdict = object["verdict"] as? String
        guard let rawVerdict, let verdict = RelayVerdict.Verdict(rawValue: rawVerdict) else {
            return .failure(.unknownVerdict(rawVerdict ?? String(describing: object["verdict"] as Any)))
        }

        let handover = object["handover"] as? String
        let note = object["note"] as? String

        if verdict == .continueRelay,
           handover?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            return .failure(.continueWithoutHandover)
        }

        let extraction = Extraction(
            verdict: RelayVerdict(verdict: verdict, handover: handover, note: note),
            strippedOutput: strippedText(pmOutput, removing: removalRange)
        )
        return .success(extraction)
    }

    // MARK: - Scanning

    private struct FencedMatch {
        var fullRange: Range<String.Index>
        var inner: String
    }

    /// All ```<lang>\n…\n``` fenced blocks in document order (lang tag optional/blank).
    private static func fencedBlocks(in text: String) -> [FencedMatch] {
        guard let regex = try? NSRegularExpression(pattern: "```[^\\n]*\\n([\\s\\S]*?)```") else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard let fullRange = Range(match.range, in: text),
                  let innerRange = Range(match.range(at: 1), in: text) else { return nil }
            return FencedMatch(fullRange: fullRange, inner: String(text[innerRange]))
        }
    }

    /// Top-level balanced `{ … }` spans outside any excluded (fenced) range, quote-aware
    /// so braces inside JSON string values never break the depth count.
    private static func topLevelObjectRanges(
        in text: String, excluding excluded: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            if let hit = excluded.first(where: { $0.contains(idx) }) {
                idx = hit.upperBound
                continue
            }
            if text[idx] == "{", let end = matchingBraceEnd(in: text, openAt: idx) {
                ranges.append(idx..<end)
                idx = end
                continue
            }
            idx = text.index(after: idx)
        }
        return ranges
    }

    private static func matchingBraceEnd(in text: String, openAt start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { return text.index(after: idx) }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    /// Removes the winning range and collapses the blank-line seam it leaves behind, so
    /// the dev sees clean prose rather than a hole where the JSON block used to be.
    private static func strippedText(_ text: String, removing range: Range<String.Index>) -> String {
        var result = text
        result.removeSubrange(range)
        while let tripleNewline = result.range(of: "\n\n\n") {
            result.replaceSubrange(tripleNewline, with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
