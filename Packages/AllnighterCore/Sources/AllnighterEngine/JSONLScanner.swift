import Foundation

/// One place to scan vendor JSONL logs (Codex rollouts, AGY transcripts, …): split into lines,
/// skip blank / non-object lines, decode each `{…}` line to `[String: Any]`. Each vendor reader
/// used to hand-roll this (split-by-newline → trim → data(using:) → JSONSerialization → cast);
/// factoring it keeps the JSONL hygiene (blank lines, non-`{` lines, malformed lines) in one spot.
enum JSONLScanner {
    /// Call `body` for each JSON-object line in arrival order. Return `false` from `body` to stop
    /// early (e.g. once enough items are collected). Lines that aren't a JSON object are skipped.
    static func forEachObject(_ text: String, _ body: ([String: Any]) -> Bool) {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if !body(obj) { return }
        }
    }

    /// The first JSON-object line (e.g. a session_meta header), or nil if there isn't one.
    static func firstObject(_ text: String) -> [String: Any]? {
        var result: [String: Any]?
        forEachObject(text) { result = $0; return false }
        return result
    }
}
