import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// URN-S02 — CLI-side opt-out wiring shared by `pair pilot handoff`, `pair
/// relay`, `pair relay-resume`, `pair relay adopt`. `--no-auto-serve` present
/// → false; `ALLN_NO_AUTO_SERVE` set → false; neither → true (spec's exact
/// three scenarios for the `shouldAutoLaunchServe`-style helper).
final class ServeAutoLaunchCLITests: XCTestCase {

    func testNoAutoServeIsARegisteredBooleanFlag() {
        // `--no-auto-serve` must be a boolean flag (no value consumed), or a
        // trailing `--json` on the same command line would be swallowed as
        // its value instead of parsed as its own flag.
        XCTAssertTrue(Options.booleanFlags.contains("no-auto-serve"))
        let opts = Options(["--relay", "r1", "--no-auto-serve", "--json"])
        XCTAssertTrue(opts.flag("no-auto-serve"))
        XCTAssertTrue(opts.flag("json"))
        XCTAssertEqual(opts.value("relay"), "r1")
    }

    func testShouldAutoLaunchServeTrueWhenNeitherPresent() {
        let opts = Options(["--relay", "r1"])
        XCTAssertTrue(ServeAutoLaunchCLI.shouldAutoLaunchServe(opts, environment: [:]))
    }

    func testShouldAutoLaunchServeFalseWhenFlagPresent() {
        let opts = Options(["--relay", "r1", "--no-auto-serve"])
        XCTAssertFalse(ServeAutoLaunchCLI.shouldAutoLaunchServe(opts, environment: [:]))
    }

    func testShouldAutoLaunchServeFalseWhenEnvSet() {
        let opts = Options(["--relay", "r1"])
        XCTAssertFalse(ServeAutoLaunchCLI.shouldAutoLaunchServe(opts, environment: ["ALLN_NO_AUTO_SERVE": "1"]))
    }

    func testShouldAutoLaunchServeFalseWhenBothPresent() {
        let opts = Options(["--relay", "r1", "--no-auto-serve"])
        XCTAssertFalse(ServeAutoLaunchCLI.shouldAutoLaunchServe(opts, environment: ["ALLN_NO_AUTO_SERVE": "1"]))
    }

    // MARK: - CommandSpec surface

    func testFourDispatchCommandsExposeNoAutoServeFlag() {
        let names = ["pair pilot handoff", "pair relay", "pair relay-resume", "pair relay adopt"]
        for name in names {
            let spec = ContractRegistry.milestone1.commands.first { $0.name == name }
            XCTAssertNotNil(spec, "missing CommandSpec for \(name)")
            XCTAssertTrue(
                spec?.flags.contains { $0.name == "no-auto-serve" && !$0.takesValue } ?? false,
                "\(name) is missing a boolean --no-auto-serve FlagSpec"
            )
        }
    }

    func testPilotStartDoesNotExposeNoAutoServeFlag() {
        // `pilot start` only parks `awaitingPM`; nothing runs, so URN-S02
        // deliberately does not wire it.
        let spec = ContractRegistry.milestone1.commands.first { $0.name == "pair pilot start" }
        XCTAssertNotNil(spec)
        XCTAssertFalse(spec?.flags.contains { $0.name == "no-auto-serve" } ?? true)
    }
}
