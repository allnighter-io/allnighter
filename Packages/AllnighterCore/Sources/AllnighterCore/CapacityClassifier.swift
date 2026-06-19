import Foundation

/// Pure classifier: worker stdout/stderr/JSONL/RPC text + exit code → optional sourced capacity fact.
public enum CapacityClassifier {
    public struct Input: Sendable {
        public var workerId: String
        public var sourceId: String
        public var stdout: String
        public var stderr: String
        public var exitCode: Int32?
        public var observedAt: Date

        public init(
            workerId: String,
            sourceId: String,
            stdout: String = "",
            stderr: String = "",
            exitCode: Int32? = nil,
            observedAt: Date = Date()
        ) {
            self.workerId = workerId
            self.sourceId = sourceId
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
            self.observedAt = observedAt
        }
    }

    private static let providerBusyBackoffSeconds = 60
    private static let unknownBackoffSeconds = 3_600

    public static func classify(_ input: Input) -> CapacityObservation? {
        let combined = [input.stderr, input.stdout].joined(separator: "\n")
        if let structured = classifyStructured(combined, input: input) { return structured }
        if let agy = classifyAGYCooldown(combined, input: input) { return agy }
        if let blocker = classifyBlockers(combined, input: input) { return blocker }
        if let fallback = classifyMessageFallback(combined, input: input) { return fallback }
        return nil
    }

    // MARK: - Structured

    private static func classifyStructured(_ text: String, input: Input) -> CapacityObservation? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let obs = classifyClaudeJSON(json, line: trimmed, input: input) { return obs }
            if let obs = classifyCodexJSON(json, line: trimmed, input: input) { return obs }
        }
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let obs = classifyClaudeJSON(json, line: text, input: input) { return obs }
            if let obs = classifyCodexJSON(json, line: text, input: input) { return obs }
        }
        return nil
    }

    private static func classifyClaudeJSON(_ json: [String: Any], line: String, input: Input) -> CapacityObservation? {
        let error = (json["error"] as? [String: Any]) ?? json
        guard let type = error["type"] as? String else { return nil }
        let message = (error["message"] as? String) ?? type
        let snippet = CapacityObservationSanitizer.snippet(from: message)
        switch type {
        case "rate_limit_error":
            let retry = retryAfterSeconds(from: error) ?? retryAfterSeconds(fromMessage: message)
            return makeObservation(
                kind: .accountRateLimit,
                input: input,
                confidence: .structured,
                snippet: snippet,
                retryAfterSeconds: retry
            )
        case "overloaded_error":
            let retry = retryAfterSeconds(from: error) ?? providerBusyBackoffSeconds
            return makeObservation(
                kind: .providerBusy,
                input: input,
                confidence: .structured,
                snippet: snippet,
                retryAfterSeconds: retry,
                allowObservedReset: retryAfterSeconds(from: error) != nil
            )
        default:
            return nil
        }
    }

    private static func classifyCodexJSON(_ json: [String: Any], line: String, input: Input) -> CapacityObservation? {
        let type = json["type"] as? String
        if type == "error" || type == "turn.failed" {
            let message = codexMessage(from: json)
            let lower = message.lowercased()
            guard lower.contains("usage") && (lower.contains("limit") || lower.contains("reached") || lower.contains("cap"))
                || lower.contains("spend cap") || lower.contains("credits") else { return nil }
            let resetsAt = parseISO8601(json["resetsAt"] as? String)
                ?? parseISO8601((json["error"] as? [String: Any])?["resetsAt"] as? String)
            let retry = retryAfterSeconds(from: json)
                ?? resetsAt.map { Int($0.timeIntervalSince(input.observedAt)) }
            return makeObservation(
                kind: .accountRateLimit,
                input: input,
                confidence: .structured,
                snippet: CapacityObservationSanitizer.snippet(from: message),
                retryAfterSeconds: retry,
                observedResetAt: resetsAt
            )
        }
        return nil
    }

    private static func codexMessage(from json: [String: Any]) -> String {
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["code"] as? String) ?? "turn.failed"
        }
        return "turn.failed"
    }

    // MARK: - AGY

    private static func classifyAGYCooldown(_ text: String, input: Input) -> CapacityObservation? {
        let pattern = #"capacity exhausted:\s*cooldown active until\s+([0-9T:\-\.Z\+]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let timestamp = String(text[range])
        guard let resetAt = parseISO8601(timestamp) else { return nil }
        let retry = max(1, Int(resetAt.timeIntervalSince(input.observedAt)))
        return makeObservation(
            kind: .cooldown,
            input: input,
            confidence: .structured,
            snippet: CapacityObservationSanitizer.snippet(from: "capacity exhausted: cooldown active until \(timestamp)"),
            retryAfterSeconds: retry,
            observedResetAt: resetAt
        )
    }

    // MARK: - Blockers

    private static func classifyBlockers(_ text: String, input: Input) -> CapacityObservation? {
        let lower = text.lowercased()
        if matchesAny(lower, patterns: manualPatterns) {
            return makeObservation(
                kind: .manualRequired,
                input: input,
                confidence: .messageFallback,
                snippet: CapacityObservationSanitizer.snippet(from: firstNonEmptyLine(text) ?? "manual action required"),
                retryAfterSeconds: nil,
                observedResetAt: nil,
                wakeAfter: nil
            )
        }
        if matchesAny(lower, patterns: authPatterns) {
            return makeObservation(
                kind: .authRequired,
                input: input,
                confidence: .messageFallback,
                snippet: CapacityObservationSanitizer.snippet(from: firstNonEmptyLine(text) ?? "authentication required"),
                retryAfterSeconds: nil,
                observedResetAt: nil,
                wakeAfter: nil
            )
        }
        return nil
    }

    // MARK: - Message fallback

    private static func classifyMessageFallback(_ text: String, input: Input) -> CapacityObservation? {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }
        if let retry = retryAfterSeconds(fromMessage: text) {
            return makeObservation(
                kind: .accountRateLimit,
                input: input,
                confidence: .messageFallback,
                snippet: CapacityObservationSanitizer.snippet(from: firstNonEmptyLine(text) ?? "rate limited"),
                retryAfterSeconds: retry,
                allowObservedReset: false
            )
        }
        if matchesAny(lower, patterns: capacityPatterns), !matchesAny(lower, patterns: negativePatterns) {
            return makeObservation(
                kind: .unknownCapacity,
                input: input,
                confidence: .localPolicy,
                snippet: CapacityObservationSanitizer.snippet(from: firstNonEmptyLine(text) ?? "capacity blocked"),
                retryAfterSeconds: unknownBackoffSeconds,
                allowObservedReset: false
            )
        }
        if matchesAny(lower, patterns: overloadPatterns) {
            return makeObservation(
                kind: .providerBusy,
                input: input,
                confidence: .messageFallback,
                snippet: CapacityObservationSanitizer.snippet(from: firstNonEmptyLine(text) ?? "provider busy"),
                retryAfterSeconds: providerBusyBackoffSeconds,
                allowObservedReset: false
            )
        }
        return nil
    }

    // MARK: - Helpers

    private static func makeObservation(
        kind: CapacityObservationKind,
        input: Input,
        confidence: CapacitySourceConfidence,
        snippet: String,
        retryAfterSeconds: Int?,
        observedResetAt: Date? = nil,
        allowObservedReset: Bool = true,
        wakeAfter: Date? = nil
    ) -> CapacityObservation {
        let sourcedReset: Date?
        if kind == .authRequired || kind == .manualRequired {
            sourcedReset = nil
        } else if allowObservedReset {
            sourcedReset = observedResetAt ?? retryAfterSeconds.map { input.observedAt.addingTimeInterval(TimeInterval($0)) }
        } else {
            sourcedReset = observedResetAt
        }

        let wake: Date?
        if kind == .authRequired || kind == .manualRequired {
            wake = nil
        } else if let wakeAfter {
            wake = wakeAfter
        } else if let sourcedReset {
            wake = sourcedReset
        } else if let retryAfterSeconds {
            wake = input.observedAt.addingTimeInterval(TimeInterval(retryAfterSeconds))
        } else {
            wake = nil
        }

        let effectiveConfidence: CapacitySourceConfidence
        if sourcedReset == nil, wake != nil, confidence != .structured {
            effectiveConfidence = .localPolicy
        } else {
            effectiveConfidence = confidence
        }

        return CapacityObservation(
            kind: kind,
            source: input.sourceId,
            sourceConfidence: effectiveConfidence,
            rawSnippet: snippet,
            observedAt: input.observedAt,
            observedResetAt: sourcedReset,
            retryAfterSeconds: retryAfterSeconds,
            wakeAfter: wake
        )
    }

    private static func retryAfterSeconds(from json: [String: Any]) -> Int? {
        for key in ["retry_after", "retryAfter", "retry_after_seconds", "retryAfterSeconds"] {
            if let value = json[key] as? Int { return value }
            if let value = json[key] as? Double { return Int(value) }
            if let value = json[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    private static func retryAfterSeconds(fromMessage text: String) -> Int? {
        let patterns = [
            #"retry(?:\s+|-)?after[:\s]+(\d+)\s*(?:s|sec|seconds)?"#,
            #"wait\s+(\d+)\s*(?:s|sec|seconds)"#,
        ]
        let lower = text.lowercased()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range(at: 1), in: lower),
                  let value = Int(lower[range]) else { continue }
            return value
        }
        return nil
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func firstNonEmptyLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0) }
    }

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private static let authPatterns = [
        "auth required", "authentication required", "not signed in", "please run /login",
        "run /login", "sign in required", "login required", "unauthorized", "invalid api key",
    ]
    private static let manualPatterns = [
        "manual paste", "awaiting manual", "paste required", "manual action required",
        "requires manual", "human input required",
    ]
    private static let overloadPatterns = [
        "overloaded", "server busy", "provider busy", "temporarily unavailable", "try again later",
    ]
    private static let capacityPatterns = [
        "rate limit", "usage limit", "capacity exhausted", "quota", "too many requests", "cooldown",
    ]
    private static let negativePatterns = [
        "weird failure", "syntax error", "file not found", "command not found",
    ]
}

enum CapacityObservationSanitizer {
    static let maxSnippetLength = 200

    private static let redactionPatterns: [String] = [
        #"(?i)bearer\s+[a-z0-9\-_\.]+"#,
        #"(?i)api[_-]?key[=:\s]+[a-z0-9\-_]+"#,
        #"(?i)sk-[a-z0-9]{8,}"#,
        #"(?i)token[=:\s]+[a-z0-9\-_\.]{8,}"#,
        #"(?i)cookie[=:\s]+[^;\s]+"#,
        #"(?i)authorization:\s*[^\s]+"#,
    ]

    static func snippet(from text: String) -> String {
        var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in redactionPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: "[redacted]"
            )
        }
        sanitized = sanitized.replacingOccurrences(of: "\n", with: " ")
        if sanitized.count > maxSnippetLength {
            sanitized = String(sanitized.prefix(maxSnippetLength - 1)) + "…"
        }
        return sanitized
    }
}
