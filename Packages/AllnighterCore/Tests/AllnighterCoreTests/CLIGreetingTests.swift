import XCTest
@testable import AllnighterCore

final class CLIGreetingTests: XCTestCase {
    func testCardIsCommandThenBenefitCheatSheet() {
        let card = CLIGreeting.render(version: "1.1.12", color: false)
        XCTAssertTrue(card.contains("allnighter"))
        XCTAssertTrue(card.contains("1.1.12"))
        XCTAssertTrue(card.contains(#"alln run "review this diff" --model model_grok"#))
        XCTAssertTrue(card.contains("From this terminal, send it to Grok."))
        XCTAssertTrue(card.contains(#"alln run "review this diff" --team spec_review"#))
        XCTAssertTrue(card.contains("Several models. One answer."))
        XCTAssertTrue(card.contains("alln capacity"))
        XCTAssertTrue(card.contains("Remaining usage on every CLI."))
        XCTAssertTrue(card.contains(#"alln loop start "fix the failing test""#))
        XCTAssertTrue(card.contains("You brief once. A lead runs it. One worker writes."))
        XCTAssertTrue(card.contains("alln --help"))
        XCTAssertTrue(card.contains(SupportHatch.email))
        XCTAssertFalse(card.contains("alln bootstrap"))
        XCTAssertFalse(card.contains("alln menu --json"))
        XCTAssertFalse(card.contains("bench"))
        XCTAssertFalse(card.contains("Headroom"))
        XCTAssertFalse(card.contains("Run a team"))
        XCTAssertFalse(card.contains("team reconcile"), "card is not the command catalog")
        XCTAssertFalse(card.contains("\u{1B}"))
    }

    func testColorCardPaintsMarkHotAndCommandsQuieterAmber() {
        let painted = CLIGreeting.render(version: "1.1.12", color: true)
        XCTAssertTrue(painted.contains("\u{1B}[1;38;2;255;166;48m"), "wordmark uses amber-500")
        XCTAssertTrue(painted.contains("\u{1B}[38;2;255;193;105m"), "commands use amber-400")
        XCTAssertFalse(painted.contains("\u{1B}[48;2;255;166;48m"), "greeting has no cursor block")
        XCTAssertTrue(painted.contains("alln capacity"))
    }
}
