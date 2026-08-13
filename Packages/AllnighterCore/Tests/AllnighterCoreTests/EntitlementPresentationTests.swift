import XCTest
@testable import AllnighterCore

final class EntitlementPresentationTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDailyCapMessageIsTellHuman() {
        XCTAssertEqual(EntitlementRefusal.dailyCap.message, EntitlementCopy.tellHuman)
        XCTAssertTrue(EntitlementCopy.tellHuman.contains("That's today's three."))
        XCTAssertTrue(EntitlementCopy.tellHuman.contains("After you pay, tell me"))
        XCTAssertFalse(EntitlementCopy.tellHuman.contains("Upgrade App"))
        XCTAssertFalse(EntitlementCopy.tellHuman.contains("allowance"))
    }

    func testErrorEnvelopeFillsTellHumanForLimit() {
        let env = ErrorEnvelope(
            code: "ENTITLEMENT_LIMIT",
            message: EntitlementCopy.tellHuman,
            requiresManual: true,
            retryable: false
        )
        XCTAssertEqual(env.tellHuman, EntitlementCopy.tellHuman)
        XCTAssertEqual(env.message, EntitlementCopy.tellHuman)
        XCTAssertEqual(env.nextAction?.command, EntitlementPolicy.checkoutCommand)
        XCTAssertFalse(env.nextAction?.command.contains("http") ?? true)
    }

    func testHeaderChipSilentDuringEarlyTrial() {
        let end = now.addingTimeInterval(11 * 86400)
        let status = BillingJSON(plan: "trial", paid: false, trialEndsAt: iso(end))
        XCTAssertEqual(EntitlementChrome.headerChip(status: status, now: now, calendar: utc), .none)
    }

    func testHeaderChipLastThreeTrialDays() {
        let end = now.addingTimeInterval(2 * 86400)
        let status = BillingJSON(plan: "trial", paid: false, trialEndsAt: iso(end))
        XCTAssertEqual(
            EntitlementChrome.headerChip(status: status, now: now, calendar: utc),
            .trial(daysLeft: 2)
        )
        XCTAssertEqual(
            EntitlementChrome.headerChip(status: status, now: now, calendar: utc).label,
            "Trial · 2 days left"
        )
    }

    func testHeaderChipKeepGoingAtCap() {
        let status = BillingJSON(
            plan: "free",
            paid: false,
            runsUsedToday: 3,
            runsAllowedToday: 3,
            tellHuman: EntitlementCopy.tellHuman
        )
        XCTAssertEqual(
            EntitlementChrome.headerChip(status: status, now: now, calendar: utc),
            .keepGoing
        )
        XCTAssertEqual(
            EntitlementChrome.headerChip(status: status, now: now, calendar: utc).label,
            "Keep going"
        )
    }

    func testHeaderChipHiddenWhenPaid() {
        let status = BillingJSON(plan: "monthly", paid: true)
        XCTAssertEqual(EntitlementChrome.headerChip(status: status, now: now, calendar: utc), .none)
        XCTAssertEqual(
            EntitlementChrome.planRow(status: status, now: now, calendar: utc).subtitle,
            "Builder"
        )
        XCTAssertFalse(EntitlementChrome.planRow(status: status, now: now, calendar: utc).showsUpgrade)
    }

    func testPlanRowFreeAtCap() {
        let status = BillingJSON(plan: "free", paid: false, runsUsedToday: 3, runsAllowedToday: 3)
        let row = EntitlementChrome.planRow(status: status, now: now, calendar: utc)
        XCTAssertEqual(row.subtitle, "Free · back tomorrow")
        XCTAssertTrue(row.showsUpgrade)
    }

    func testCheckoutTellHumanCarriesUrlAndNotACommand() {
        let url = "https://checkout.stripe.com/c/pay/cs_test_1"
        let text = EntitlementCopy.checkoutTellHuman(url: url)
        XCTAssertTrue(text.contains(url))
        XCTAssertTrue(text.contains("Safari or Chrome"))
        XCTAssertFalse(text.contains("alln billing checkout"))
    }

    func testAgentActionForbidsParaphraseAndExec() {
        XCTAssertTrue(EntitlementCopy.agentAction.contains("verbatim"))
        XCTAssertTrue(EntitlementCopy.agentAction.contains("Do not exec the url"))
        XCTAssertTrue(EntitlementCopy.agentAction.contains("nextAction.command"))
        XCTAssertTrue(EntitlementCopy.agentAction.contains("tellHuman"))
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
