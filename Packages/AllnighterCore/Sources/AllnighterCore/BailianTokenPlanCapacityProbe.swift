#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Pure JSON parser for Alibaba Token Plan Personal (intl) rolling-window usage.
///
/// Atomic rule: the 7-day window must parse or the whole sample fails. The
/// 5-hour window may be absent when Alibaba lifts the limit ("Limit
/// Temporarily Removed" in the console).
public enum BailianTokenPlanCapacityProbe {

    public static let sourceId = "bailian_token_plan"
    public static let parseStrategy = "personal_api_v1"

    public struct WindowSample: Sendable, Equatable {
        public let usedPercent: Double
        public let resetAt: Date
    }

    public enum FiveHourState: Sendable, Equatable {
        case limited(WindowSample)
        case limitRemoved
    }

    public struct ParsedSample: Sendable, Equatable {
        public let fiveHour: FiveHourState
        public let sevenDay: WindowSample
        public let planTier: String?
    }

    public enum ParseFailure: Sendable, Equatable, Error {
        case authRequired
        case schemaDrift(missing: [String])
        case invalidValue(field: String)
    }

    /// Parse usage JSON into capacity windows for `observedAt`.
    public static func capacityWindows(
        usageJSON: Data,
        observedAt: Date
    ) -> [CapacityWindow] {
        if looksLikeLoginPage(usageJSON) {
            return unknownWindows(reason: .authRequired(observedAt: observedAt), at: observedAt)
        }
        switch parseSample(usageJSON: usageJSON) {
        case .success(let sample):
            return windows(from: sample, observedAt: observedAt)
        case .failure(let failure):
            let reason: CapacityUnknownReason
            switch failure {
            case .authRequired:
                reason = .authRequired(observedAt: observedAt)
            default:
                reason = .parserFailed(observedAt: observedAt)
            }
            return unknownWindows(reason: reason, at: observedAt)
        }
    }

    public static func parseSample(usageJSON: Data) -> Result<ParsedSample, ParseFailure> {
        if looksLikeLoginPage(usageJSON) {
            return .failure(.authRequired)
        }
        guard !usageJSON.isEmpty else {
            return .failure(.schemaDrift(missing: ["sevenDay"]))
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: usageJSON)
        } catch {
            return .failure(.schemaDrift(missing: ["sevenDay"]))
        }

        let expanded = expandEmbeddedJSON(root)
        if let error = apiErrorMessage(in: expanded) {
            let lowered = error.lowercased()
            if lowered.contains("login") || lowered.contains("notlogined") || lowered.contains("unauthorized") {
                return .failure(.authRequired)
            }
            return .failure(.schemaDrift(missing: ["sevenDay"]))
        }

        guard let usage = findObject(
            containingAnyOf: ["per5HourPercentage", "per1WeekPercentage", "per5HourLimitRemoved"],
            in: expanded
        ) else {
            return .failure(.schemaDrift(missing: ["sevenDay"]))
        }

        let planTier = planTier(from: expanded)

        let fiveHour: FiveHourState
        if isTruthy(usage["per5HourLimitRemoved"]) || isLimitRemovedText(usage["per5HourStatus"]) {
            fiveHour = .limitRemoved
        } else if let ratio = number(usage["per5HourPercentage"]),
                  let resetMs = number(usage["per5HourResetTime"]),
                  let used = percentPoints(fromRatio: ratio),
                  let resetAt = date(fromMilliseconds: resetMs)
        {
            guard isValidPercent(used), isValidReset(resetAt) else {
                return .failure(.invalidValue(field: "fiveHour"))
            }
            fiveHour = .limited(.init(usedPercent: used, resetAt: resetAt))
        } else if usage["per5HourPercentage"] == nil || usage["per5HourPercentage"] is NSNull {
            fiveHour = .limitRemoved
        } else {
            return .failure(.schemaDrift(missing: ["fiveHour"]))
        }

        guard let weekRatio = number(usage["per1WeekPercentage"]),
              let weekResetMs = number(usage["per1WeekResetTime"]),
              let weekUsed = percentPoints(fromRatio: weekRatio),
              let weekResetAt = date(fromMilliseconds: weekResetMs)
        else {
            return .failure(.schemaDrift(missing: ["sevenDay"]))
        }
        guard isValidPercent(weekUsed), isValidReset(weekResetAt) else {
            return .failure(.invalidValue(field: "sevenDay"))
        }

        return .success(
            ParsedSample(
                fiveHour: fiveHour,
                sevenDay: .init(usedPercent: weekUsed, resetAt: weekResetAt),
                planTier: planTier
            )
        )
    }

    // MARK: - Window construction

    private static func windows(
        from sample: ParsedSample,
        observedAt: Date
    ) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        let plan = sample.planTier ?? "Personal"
        var out: [CapacityWindow] = []
        switch sample.fiveHour {
        case .limited(let window):
            out.append(
                CapacityWindow(
                    used: window.usedPercent,
                    source: sourceId,
                    scope: .fiveHour,
                    resetAt: window.resetAt,
                    resetPrecision: .minute,
                    observedAt: observedAt,
                    sourceTier: tier,
                    planTier: plan
                )
            )
        case .limitRemoved:
            out.append(
                CapacityWindow.unknown(
                    reason: .vendorExposesNothing,
                    source: sourceId,
                    scope: .fiveHour,
                    observedAt: observedAt,
                    sourceTier: tier,
                    planTier: plan
                )
            )
        }
        out.append(
            CapacityWindow(
                used: sample.sevenDay.usedPercent,
                source: sourceId,
                scope: .weekly,
                resetAt: sample.sevenDay.resetAt,
                resetPrecision: .minute,
                observedAt: observedAt,
                sourceTier: tier,
                planTier: plan
            )
        )
        return out
    }

    private static func unknownWindows(
        reason: CapacityUnknownReason,
        at observedAt: Date
    ) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        return [CapacityWindowScope.fiveHour, .weekly].map {
            CapacityWindow.unknown(
                reason: reason,
                source: sourceId,
                scope: $0,
                observedAt: observedAt,
                sourceTier: tier,
                planTier: "Personal"
            )
        }
    }

    // MARK: - JSON helpers

    static func expandEmbeddedJSON(_ value: Any) -> Any {
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data)
        {
            return expandEmbeddedJSON(parsed)
        }
        if let array = value as? [Any] {
            return array.map { expandEmbeddedJSON($0) }
        }
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                out[key] = expandEmbeddedJSON(nested)
            }
            return out
        }
        return value
    }

    static func findObject(
        containingAnyOf keys: [String],
        in value: Any
    ) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if keys.contains(where: { dict[$0] != nil }) {
                return dict
            }
            for nested in dict.values {
                if let found = findObject(containingAnyOf: keys, in: nested) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findObject(containingAnyOf: keys, in: nested) {
                    return found
                }
            }
        }
        return nil
    }

    static func apiErrorMessage(in value: Any) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let success = dict["success"] as? Bool, success == false {
            return string(dict["message"]) ?? string(dict["errorMsg"]) ?? "api_error"
        }
        if let successResponse = dict["successResponse"] as? Bool, successResponse == false {
            return string(dict["message"]) ?? "api_error"
        }
        if let code = string(dict["code"]), code != "200", let message = string(dict["message"]) {
            return message
        }
        for nested in dict.values {
            if let message = apiErrorMessage(in: nested) { return message }
        }
        return nil
    }

    static func planTier(from value: Any) -> String? {
        guard let plan = findObject(
            containingAnyOf: ["specCode", "spec_code", "planName", "plan_name"],
            in: value
        ) else { return nil }
        for key in ["specCode", "spec_code", "planName", "plan_name"] {
            if let raw = string(plan[key])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty
            {
                switch raw.lowercased() {
                case "lite": return "Lite"
                case "standard": return "Standard"
                case "pro": return "Pro"
                case "max": return "Max"
                default: return raw
                }
            }
        }
        return nil
    }

    static func looksLikeLoginPage(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        guard text.contains("<html") else { return false }
        return text.contains("login") || text.contains("sign in") || text.contains("signin")
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "true", "1", "yes": return true
            default: return false
            }
        default: return false
        }
    }

    static func isLimitRemovedText(_ value: Any?) -> Bool {
        guard let text = string(value)?.lowercased() else { return false }
        return text.contains("limit temporarily removed") || text.contains("limit_removed")
    }

    static func percentPoints(fromRatio ratio: Double) -> Double? {
        guard ratio.isFinite else { return nil }
        let points = ratio <= 1 ? ratio * 100 : ratio
        return points.isFinite ? points : nil
    }

    static func date(fromMilliseconds ms: Double) -> Date? {
        guard ms.isFinite, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    static func isValidPercent(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 200
    }

    static func isValidReset(_ resetAt: Date) -> Bool {
        resetAt.timeIntervalSince1970 > 1_000_000_000
    }

    static func bodyFingerprint(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let expanded = expandEmbeddedJSON(root)
        guard let usage = findObject(
            containingAnyOf: ["per5HourPercentage", "per1WeekPercentage", "per5HourLimitRemoved"],
            in: expanded
        ) else { return nil }
        let keys = [
            "per5HourPercentage", "per1WeekPercentage", "per5HourResetTime",
            "per1WeekResetTime", "per5HourLimitRemoved", "per5HourStatus",
        ]
        let canonical = keys
            .map { key in "\(key)=\(usage[key] != nil)" }
            .joined(separator: "|")
        guard let bytes = canonical.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
