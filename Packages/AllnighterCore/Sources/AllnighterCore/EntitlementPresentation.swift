import Foundation

/// Conversion copy and chrome projection for trial / free-cap / Builder.
/// Offer numbers: `docs/marketing/Pricing_Recommendation.md`. Surfaces:
/// CLI `ENTITLEMENT_LIMIT` / `BillingJSON.tellHuman`, Mac Keep going sheet,
/// Settings › Plan, quiet title-bar chip.
public enum EntitlementCopy {
    public static let dailyCapHeadline = "That's today's three."
    public static let dailyCapBody = """
        Tomorrow you get three more — same product, nothing locked.
        Or keep going now. Builder is $8/month.
        """
    public static let keepGoingButton = "Keep going — $8/month"
    public static let notNowButton = "Not now"
    public static let altYearly = "$80/year saves $16"
    public static let altFounding = "Founding Builder $160 once, first 100"
    public static let altPlansLine = "$80/year saves $16 · Founding Builder $160 once, first 100"

    /// Verbatim paragraph an agent must show the human. Same text on
    /// `ErrorEnvelope.message`, `ErrorEnvelope.tellHuman`, and `BillingJSON`
    /// when the daily cap is hit.
    public static let tellHuman = """
        That's today's three.

        Tomorrow you get three more — same product, nothing locked.
        Or keep going now. Builder is $8/month.

        After you pay, tell me and I'll continue.
        """

    /// Registry `agentAction` for `ENTITLEMENT_LIMIT`.
    public static let agentAction = """
        Quote `tellHuman` (same text as `message`) to the human verbatim — do not paraphrase and do not retry the run. Then run nextAction.command once. Paste the returned JSON `url` into the same reply and tell them to open it in Safari or Chrome, not Cursor's preview browser. Do not exec the url. Do not retry until they say they paid.
        """

    public static let checkoutAgentNote =
        "Open this in Safari or Chrome to keep going (not Cursor's preview browser). Do not exec the url."

    public static func checkoutTellHuman(url: String) -> String {
        """
        Open this in Safari or Chrome to keep going (not Cursor's preview browser):

        \(url)

        After you pay, tell me and I'll continue.
        """
    }

    public static let explain =
        "This machine used today's three free runs (full product, 14-day trial then 3/day). Nothing is feature-locked. Builder is $8/month. Checkout is hosted Stripe with email; Sign in with Apple is not required."
}

public enum EntitlementHeaderChip: Equatable, Sendable {
    case none
    /// Calendar days until `trialEndsAt`. `0` means the trial ends today.
    case trial(daysLeft: Int)
    case keepGoing

    public var label: String {
        switch self {
        case .none:
            return ""
        case .trial(let days):
            if days <= 0 { return "Trial · last day" }
            if days == 1 { return "Trial · 1 day left" }
            return "Trial · \(days) days left"
        case .keepGoing:
            return "Keep going"
        }
    }

    public var isKeepGoing: Bool {
        if case .keepGoing = self { return true }
        return false
    }
}

public struct EntitlementPlanRow: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var showsUpgrade: Bool

    public init(title: String = "Plan", subtitle: String, showsUpgrade: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.showsUpgrade = showsUpgrade
    }
}

public enum EntitlementChrome {
    /// Quiet title-bar chip. Hidden during early trial and while paid.
    public static func headerChip(
        status: BillingJSON?,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> EntitlementHeaderChip {
        guard let status, !status.paid, status.plan != "skipped" else { return .none }
        if status.plan == "trial", let end = parseISO(status.trialEndsAt) {
            let days = daysUntil(end, now: now, calendar: calendar)
            if days <= 3 { return .trial(daysLeft: max(0, days)) }
            return .none
        }
        if remainingRuns(status) == 0 { return .keepGoing }
        return .none
    }

    public static func planRow(
        status: BillingJSON?,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> EntitlementPlanRow {
        guard let status else {
            return EntitlementPlanRow(subtitle: "Checking…", showsUpgrade: false)
        }
        if status.paid || EntitlementPlan(rawValue: status.plan)?.isPaid == true {
            return EntitlementPlanRow(subtitle: paidSubtitle(status.plan), showsUpgrade: false)
        }
        if status.plan == "skipped" {
            return EntitlementPlanRow(subtitle: "Not checked", showsUpgrade: false)
        }
        if status.plan == "trial" {
            let days = parseISO(status.trialEndsAt).map { daysUntil($0, now: now, calendar: calendar) }
            let subtitle: String
            if let days {
                if days <= 0 { subtitle = "Trial · last day" }
                else if days == 1 { subtitle = "Trial · 1 day left" }
                else { subtitle = "Trial · \(days) days left" }
            } else {
                subtitle = "Trial"
            }
            return EntitlementPlanRow(subtitle: subtitle, showsUpgrade: true)
        }
        if let left = remainingRuns(status) {
            if left == 0 {
                return EntitlementPlanRow(subtitle: "Free · back tomorrow", showsUpgrade: true)
            }
            return EntitlementPlanRow(
                subtitle: "Free · \(left) of \(status.runsAllowedToday ?? EntitlementPolicy.freeRunsPerDay) left today",
                showsUpgrade: true
            )
        }
        return EntitlementPlanRow(subtitle: "Free · 3 runs a day", showsUpgrade: true)
    }

    public static func remainingRuns(_ status: BillingJSON) -> Int? {
        guard let allowed = status.runsAllowedToday else { return nil }
        let used = status.runsUsedToday ?? 0
        return max(0, allowed - used)
    }

    public static func daysUntil(_ end: Date, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: now)
        let finish = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: start, to: finish).day ?? 0
    }

    public static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func paidSubtitle(_ plan: String) -> String {
        switch plan {
        case "yearly": return "Builder · yearly"
        case "founding": return "Founding Builder"
        default: return "Builder"
        }
    }
}
