import Foundation

/// Tolerant tail-extraction of a panel seat's finding schema from raw report prose
/// (`docs/phases/Pilot_Panel.md` decision 3 / PN-S02). Lineage of `RelayVerdictParser`:
/// last fenced-or-bare JSON object carrying findings keys wins; fence-on-own-line so an
/// embedded ```json mention inside a string never terminates early (d96f332a).
///
/// Unparseable → the caller keeps the verbatim report, findings nil, flags unstructured
/// (never discard). "No material findings" with a reason is first-class valid.
public enum PanelFindingsParser {
    public struct Extraction: Sendable, Equatable {
        public var findings: [Finding]
        public var noMaterialFindings: Bool
        public var reason: String?
        /// Prose with the winning findings block stripped (for display if wanted).
        public var strippedReport: String

        public init(
            findings: [Finding],
            noMaterialFindings: Bool,
            reason: String? = nil,
            strippedReport: String
        ) {
            self.findings = findings
            self.noMaterialFindings = noMaterialFindings
            self.reason = reason
            self.strippedReport = strippedReport
        }
    }

    public enum ExtractError: Swift.Error, Sendable, Equatable {
        /// No JSON object carried findings / noMaterialFindings keys.
        case noFindingsBlock
        /// A block was found but could not be mapped into the finding schema.
        case invalidShape(String)
    }

    public static func extract(from report: String) -> Result<Extraction, ExtractError> {
        let fenced = fencedBlocks(in: report)
        let bareRanges = topLevelObjectRanges(in: report, excluding: fenced.map(\.fullRange))

        var candidates: [(start: String.Index, removalRange: Range<String.Index>, jsonText: String)] =
            fenced.map { ($0.fullRange.lowerBound, $0.fullRange, $0.inner) }
        candidates += bareRanges.map { ($0.lowerBound, $0, String(report[$0])) }
        candidates.sort { $0.start < $1.start }

        // Walk in document order; keep the LAST object that looks like a findings block.
        var winner: (removalRange: Range<String.Index>, object: [String: Any])?
        for candidate in candidates {
            guard let data = candidate.jsonText.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  isFindingsObject(object) else { continue }
            winner = (candidate.removalRange, object)
        }

        guard let (removalRange, object) = winner else {
            return .failure(.noFindingsBlock)
        }

        do {
            let findings = try parseFindings(object["findings"])
            let noMaterial = (object["noMaterialFindings"] as? Bool) ?? findings.isEmpty
            let reason = object["reason"] as? String
            // First-class empty: empty findings + noMaterialFindings true is valid even
            // without a reason; reason is encouraged but not required by the decoder.
            return .success(Extraction(
                findings: findings,
                noMaterialFindings: noMaterial,
                reason: reason,
                strippedReport: strippedText(report, removing: removalRange)
            ))
        } catch let err as ExtractError {
            return .failure(err)
        } catch {
            return .failure(.invalidShape(error.localizedDescription))
        }
    }

    /// Map a successful extraction (or failure) onto a `SeatResult` while always
    /// preserving the verbatim report. Unparseable → status `.done`, findings nil.
    public static func seatResult(
        workerId: String,
        lens: String,
        report: String,
        runId: String? = nil,
        dispatchStatus: SeatResult.Status = .done
    ) -> SeatResult {
        // Non-success dispatch outcomes keep the report but do not attempt schema parse
        // as the primary truth (failed/timedOut/empty stay honest).
        guard dispatchStatus == .done else {
            return SeatResult(
                workerId: workerId, lens: lens, status: dispatchStatus,
                findings: nil, noMaterialFindings: false,
                reason: nil, report: report, runId: runId
            )
        }
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return SeatResult(
                workerId: workerId, lens: lens, status: .empty,
                findings: nil, noMaterialFindings: false,
                reason: "empty seat report", report: report, runId: runId
            )
        }
        switch extract(from: report) {
        case .success(let extraction):
            return SeatResult(
                workerId: workerId, lens: lens, status: .done,
                findings: extraction.findings,
                noMaterialFindings: extraction.noMaterialFindings,
                reason: extraction.reason,
                report: report,
                runId: runId
            )
        case .failure:
            // done-but-unstructured: keep verbatim report, findings nil, flag via reason.
            return SeatResult(
                workerId: workerId, lens: lens, status: .done,
                findings: nil,
                noMaterialFindings: false,
                reason: "unstructured report (no parseable findings block)",
                report: report,
                runId: runId
            )
        }
    }

    // MARK: - Object mapping

    private static func isFindingsObject(_ object: [String: Any]) -> Bool {
        object["findings"] != nil || object["noMaterialFindings"] != nil
    }

    private static func parseFindings(_ raw: Any?) throws -> [Finding] {
        guard let raw else { return [] }
        guard let array = raw as? [[String: Any]] else {
            throw ExtractError.invalidShape("findings must be an array of objects")
        }
        return try array.map { item in
            guard let claim = item["claim"] as? String, !claim.isEmpty else {
                throw ExtractError.invalidShape("finding missing claim")
            }
            guard let severityRaw = item["severity"] as? String,
                  let severity = Finding.Severity(rawValue: severityRaw) else {
                throw ExtractError.invalidShape("finding severity must be low|medium|high")
            }
            guard let evidence = item["evidence"] as? String else {
                throw ExtractError.invalidShape("finding missing evidence")
            }
            let proposed = item["proposedChange"] as? String
            return Finding(
                claim: claim, severity: severity, evidence: evidence, proposedChange: proposed
            )
        }
    }

    // MARK: - Scanning (RelayVerdictParser lineage)

    private struct FencedMatch {
        var fullRange: Range<String.Index>
        var inner: String
    }

    /// Closing fences must start on their own line — otherwise a ```json mention inside a
    /// JSON string value terminates the block early (d96f332a).
    private static func fencedBlocks(in text: String) -> [FencedMatch] {
        guard let regex = try? NSRegularExpression(pattern: "```[^\\n]*\\n([\\s\\S]*?)\\n```") else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard let fullRange = Range(match.range, in: text),
                  let innerRange = Range(match.range(at: 1), in: text) else { return nil }
            return FencedMatch(fullRange: fullRange, inner: String(text[innerRange]))
        }
    }

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

    private static func strippedText(_ text: String, removing range: Range<String.Index>) -> String {
        var result = text
        result.removeSubrange(range)
        while let tripleNewline = result.range(of: "\n\n\n") {
            result.replaceSubrange(tripleNewline, with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
