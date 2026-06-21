import Foundation

/// Pure extraction of a worker CLI's OWN session id from its first-run output, per the
/// driver manifest's `session.capture` rule (Worker_Session_Continuity, acquire == .capture).
/// claude doesn't need this (we mint via `--session-id`); cursor/codex/grok do — they emit
/// the id in a stream-json event, a stdout line, or the JSON output file.
public enum WorkerSessionCapture {

    /// The vendor session id, or nil if the rule found nothing. `stdout` is the raw process
    /// stdout (JSONL for stream-json); `outputFileContents` is the `-o`/file-capture JSON.
    public static func extract(
        capture: DriverManifest.Session.Capture,
        stdout: String,
        outputFileContents: String? = nil
    ) -> String? {
        switch capture.from {
        case .stdout:
            return firstRegexGroup(pattern: capture.field, in: stdout)
        case .streamJson:
            return firstJSONLFieldValue(field: capture.field, jsonl: stdout)
        case .outputFile:
            guard let contents = outputFileContents else { return nil }
            return firstJSONFieldValue(field: capture.field, json: contents)
        }
    }

    // MARK: - stream-json (JSONL): scan each line for the field

    private static func firstJSONLFieldValue(field: String, jsonl: String) -> String? {
        for line in jsonl.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{") else { continue }
            if let value = firstJSONFieldValue(field: field, json: trimmed) { return value }
        }
        return nil
    }

    // MARK: - JSON object: find the field (top level, then one level into nested objects)

    private static func firstJSONFieldValue(field: String, json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return search(field: field, in: object)
    }

    private static func search(field: String, in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if let s = dict[field] as? String, !s.isEmpty { return s }
            // One level of nesting (e.g. {"session": {"id": ...}} keyed by the leaf field).
            for value in dict.values {
                if let nested = value as? [String: Any], let s = nested[field] as? String, !s.isEmpty {
                    return s
                }
            }
        }
        return nil
    }

    // MARK: - stdout regex (capture group 1)

    private static func firstRegexGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let groupRange = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[groupRange])
        return value.isEmpty ? nil : value
    }
}
