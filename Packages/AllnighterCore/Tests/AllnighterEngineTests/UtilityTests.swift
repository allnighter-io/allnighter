import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class UtilityTests: XCTestCase {

    func testShellWordsHonorsQuotes() {
        XCTAssertEqual(
            ShellWords.split(#"claude -p "Reply with ALLNIGHTER_READY" --model opus"#),
            ["claude", "-p", "Reply with ALLNIGHTER_READY", "--model", "opus"]
        )
    }

    func testShellWordsSingleQuotes() {
        XCTAssertEqual(
            ShellWords.split("grok smoke 'Grok Composer 2.5 Fast'"),
            ["grok", "smoke", "Grok Composer 2.5 Fast"]
        )
    }

    func testStripANSIRemovesColorCodes() {
        XCTAssertEqual(TextUtil.stripANSI("\u{1B}[1;32mok\u{1B}[0m"), "ok")
    }

    func testStripANSILeavesPlainText() {
        XCTAssertEqual(TextUtil.stripANSI("plain text"), "plain text")
    }

    func testDriverRegistryOverrideById() {
        let original = TestSupport.headlessManifest(id: "grok", command: "grok")
        var override = original
        override.displayName = "Overridden"
        let registry = DriverRegistry([original, override])
        XCTAssertEqual(registry.manifest(id: "grok")?.displayName, "Overridden")
    }

    func testHealthChecker() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let healthy = ModelHealthChecker(commandRunner: MockCommandRunner(scripts: [
            "claude": .init(stdout: "READY", exitCode: 0)
        ]))
        let health = await healthy.smokeTest(manifest, model: "opus")
        XCTAssertEqual(health, .healthy)

        let unauthed = ModelHealthChecker(commandRunner: MockCommandRunner(scripts: [
            "claude": .init(stderr: "please login", exitCode: 1)
        ]))
        let bad = await unauthed.smokeTest(manifest, model: "opus")
        XCTAssertEqual(bad, .unhealthy(reason: "please login"))
    }

    func testHealthCheckerManualPasteIsUnknown() async {
        let manual = DriverManifest(id: "manual_paste", displayName: "Manual", kind: .manualPaste)
        let checker = ModelHealthChecker(commandRunner: MockCommandRunner(scripts: [:]))
        let health = await checker.smokeTest(manual, model: "m")
        XCTAssertEqual(health, .unknown)
    }
}
