import XCTest
@testable import AllnighterCore

/// AE-S07: *_NOT_FOUND / *_NOT_AVAILABLE nextAction routes to discovery, not doctor.
final class ErrorDiscoveryTests: XCTestCase {
    func testNotFoundCodesRouteToDiscoveryNotDoctor() {
        let codes = ContractRegistry.milestone1.errors
            .map(\.code)
            .filter { $0.hasSuffix("_NOT_FOUND") || $0.hasSuffix("_NOT_AVAILABLE") }
        XCTAssertFalse(codes.isEmpty)
        var bad: [String] = []
        for code in codes {
            guard let next = ErrorDiscovery.nextAction(forErrorCode: code) else {
                // Some codes (e.g. ATTACHMENT_NOT_FOUND) may lack a list surface —
                // only fail when doctor is the wrong default and we claimed a map.
                continue
            }
            if next.command.contains("doctor") && code != "SOURCE_NOT_FOUND" {
                bad.append("\(code) → \(next.command)")
            }
            XCTAssertTrue(next.command.hasPrefix("alln "), "\(code) nextAction must be an alln command")
        }
        XCTAssertTrue(bad.isEmpty, "NOT_FOUND nextAction must not be doctor:\n\(bad.joined(separator: "\n"))")
    }

    func testTeamNotFoundDiscoveryIsMenu() {
        let cmd = ErrorDiscovery.discoveryCommand(forErrorCode: "TEAM_NOT_FOUND", lane: "code")
        XCTAssertEqual(cmd, "alln menu --json")
        XCTAssertFalse(cmd?.contains("doctor") == true)
    }

    func testNearMatchesForTypo() {
        let ids = ["code_bug_hunt", "code_bug_hunt_min", "code_plan", "code_growth"]
        let hits = ErrorDiscovery.nearestMatches(to: "code_bug_hunt_typo", in: ids)
        XCTAssertTrue(hits.contains("code_bug_hunt") || hits.contains("code_bug_hunt_min"),
                      "expected near match for typo, got \(hits)")
        XCTAssertLessThanOrEqual(hits.count, 3)
    }

    func testErrorEnvelopeCarriesNextActionForTeamNotFound() {
        let env = ErrorEnvelope(
            code: "TEAM_NOT_FOUND",
            message: "unknown team: x",
            requiresManual: true,
            retryable: false,
            suggestions: ["code_bug_hunt"]
        )
        XCTAssertEqual(env.suggestions, ["code_bug_hunt"])
        XCTAssertEqual(env.nextAction?.command, "alln menu --json")
        XCTAssertFalse(env.nextAction?.command.contains("doctor") == true)
        XCTAssertNil(env.tellHuman)
    }

    func testFailedJSONFallsBackToPersonHatchWhenNoRecovery() {
        let hatch = SupportHatch.decorate(code: "SOURCE_AUTH_EXPIRED", nextAction: nil)
        XCTAssertEqual(hatch.nextAction?.kind, "emailSupport")
        XCTAssertEqual(hatch.nextAction?.label, SupportHatch.tellHuman)
        XCTAssertEqual(hatch.nextAction?.command, "alln version --json")
        XCTAssertEqual(hatch.tellHuman, SupportHatch.tellHuman)
        XCTAssertTrue(hatch.nextAction?.command.hasPrefix("alln ") == true)

        let env = ErrorEnvelope(
            code: "SOURCE_AUTH_EXPIRED",
            message: "Claude Code authentication expired.",
            requiresManual: true,
            retryable: false,
            nextAction: hatch.nextAction,
            tellHuman: hatch.tellHuman
        )
        XCTAssertEqual(env.nextAction?.kind, "emailSupport")
        XCTAssertEqual(env.tellHuman, SupportHatch.tellHuman)
        XCTAssertTrue(env.tellHuman?.contains(AskAIPrompt.supportEmail) == true)
    }

    func testFailedJSONDoesNotStealDiscoveryNextAction() {
        let hatch = SupportHatch.decorate(code: "TEAM_NOT_FOUND", nextAction: nil)
        XCTAssertEqual(hatch.nextAction?.command, "alln menu --json")
        XCTAssertNil(hatch.tellHuman)
        XCTAssertNotEqual(hatch.nextAction?.kind, "emailSupport")
    }

    func testFailedJSONDoesNotStealEntitlementNextAction() {
        let hatch = SupportHatch.decorate(code: "ENTITLEMENT_LIMIT", nextAction: nil)
        XCTAssertEqual(hatch.nextAction?.command, EntitlementPolicy.checkoutCommand)
        XCTAssertNil(hatch.tellHuman)
        let env = ErrorEnvelope(
            code: "ENTITLEMENT_LIMIT",
            message: EntitlementCopy.tellHuman,
            requiresManual: true,
            retryable: false,
            nextAction: hatch.nextAction,
            tellHuman: hatch.tellHuman
        )
        XCTAssertEqual(env.tellHuman, EntitlementCopy.tellHuman)
        XCTAssertEqual(env.nextAction?.command, EntitlementPolicy.checkoutCommand)
    }

    func testUsageErrorIsNotAPersonHatch() {
        let hatch = SupportHatch.decorate(code: "CLI_USAGE_ERROR", nextAction: nil)
        XCTAssertNil(hatch.nextAction)
        XCTAssertNil(hatch.tellHuman)
    }

    func testFeedbackUnavailableGetsPersonHatch() {
        let hatch = SupportHatch.decorate(code: "FEEDBACK_UNAVAILABLE", nextAction: nil)
        XCTAssertEqual(hatch.nextAction?.kind, "emailSupport")
        XCTAssertEqual(hatch.tellHuman, SupportHatch.tellHuman)
        XCTAssertEqual(
            SupportHatch.decorate(code: "FEEDBACK_RATE_LIMITED", nextAction: nil).tellHuman,
            SupportHatch.tellHuman
        )
        XCTAssertEqual(
            SupportHatch.decorate(code: "FEEDBACK_REJECTED", nextAction: nil).tellHuman,
            SupportHatch.tellHuman
        )
    }
}
