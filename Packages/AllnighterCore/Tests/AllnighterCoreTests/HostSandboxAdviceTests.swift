import XCTest
@testable import AllnighterCore

/// CR-S05: a run whose seats cannot start inside a sandboxing host must say why
/// in plain language, and must never say it when that is not what happened.
final class HostSandboxAdviceTests: XCTestCase {
    private let sandboxed = ["CODEX_SANDBOX": "workspace-write", "CODEX_THREAD_ID": "t1"]

    /// The exact stderr observed live from codex started inside a Codex sandbox.
    private let codexSignature = """
        WARNING: proceeding, even though we could not create PATH aliases: Operation not permitted (os error 1)
        Error: failed to initialize in-process app-server client: Operation not permitted (os error 1)
        """

    func testDetectsTheObservedSandboxFailureAndBuildsAPasteReadyCommand() throws {
        let advice = try XCTUnwrap(HostSandboxAdvice.detect(
            workerFailureText: [codexSignature],
            prompt: "find the riskiest thing in this repo",
            projectReference: "/Users/me/Code/thing",
            teamId: "code_bug_hunt",
            environment: sandboxed))

        XCTAssertEqual(advice.retryCommand, "codex --sandbox danger-full-access")
        XCTAssertEqual(
            advice.appCommand,
            "alln run \"find the riskiest thing in this repo\" --project /Users/me/Code/thing --team code_bug_hunt")

        // Plain language: no jargon a non-developer would have to look up.
        let body = advice.warningMessage
        for jargon in ["sandbox mode", "Keychain", "spawn", "seatbelt", "TCC", "stderr"] {
            XCTAssertFalse(body.contains(jargon), "message must avoid '\(jargon)': \(body)")
        }
        XCTAssertTrue(body.contains("Nothing is wrong with your setup"))
        XCTAssertTrue(body.contains("affects only that one session"))
        XCTAssertTrue(body.contains(advice.appCommand))
    }

    /// The claude signature only counts alongside a restricted host: in a normal
    /// Terminal "Not logged in" means exactly that, and explaining it away would
    /// send the user chasing a permission problem they do not have.
    func testNotLoggedInAloneIsNotExplainedAwayOutsideARestrictedHost() {
        XCTAssertNil(HostSandboxAdvice.detect(
            workerFailureText: ["Not logged in · Please run /login"],
            prompt: "p", projectReference: "/tmp/x", teamId: "t",
            environment: [:]),
            "a genuine logged-out worker in a normal Terminal must not be masked")

        XCTAssertNotNil(HostSandboxAdvice.detect(
            workerFailureText: ["Not logged in · Please run /login"],
            prompt: "p", projectReference: "/tmp/x", teamId: "t",
            environment: sandboxed))
    }

    /// The trap this design exists to avoid: a Codex session launched with full
    /// access carries the same environment and runs perfectly. Advice keyed off
    /// the environment alone would block work that would have succeeded.
    func testSucceedingRunInsideACodexSessionGetsNoAdvice() {
        XCTAssertNil(HostSandboxAdvice.detect(
            workerFailureText: [],
            prompt: "p", projectReference: "/tmp/x", teamId: "t",
            environment: sandboxed),
            "no failure means no advice, even inside a restricted host")

        XCTAssertNil(HostSandboxAdvice.detect(
            workerFailureText: ["some unrelated vendor error"],
            prompt: "p", projectReference: "/tmp/x", teamId: "t",
            environment: sandboxed),
            "an unrelated failure must not be reported as a permission problem")
    }
}
