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

    // MARK: - Signatures observed live, 2026-07-25

    /// A three-seat team inside Codex: two seats died to the sandbox, one survived.
    /// Neither failure matched the original three signatures, so the hand-off never
    /// fired and the founder silently received one seat of a three-seat team — a
    /// run that reported `partial / completed` and exited 0.
    func testDetectsTheKeychainDenialThatSilentlyDegradedATeam() throws {
        let advice = HostSandboxAdvice.detect(
            workerFailureText: ["ERROR: SecItemCopyMatching failed -67674"],
            prompt: "Run the TEST team.",
            projectReference: "/repo",
            teamId: "custom_test_pipe",
            environment: sandboxed)
        XCTAssertNotNil(advice, "a Keychain denial inside a sandboxed host is a sandbox failure")
    }

    /// The typed signal, which is the one to trust: a classified capacity fact
    /// rather than a string a vendor can reword in its next release.
    func testDetectsATypedAuthRequiredCapacityObservation() throws {
        let advice = HostSandboxAdvice.detect(
            workerFailureText: ["capacity: authRequired"],
            prompt: "Run the TEST team.",
            projectReference: "/repo",
            teamId: "custom_test_pipe",
            capacityAuthRequired: true,
            environment: sandboxed)
        XCTAssertNotNil(advice)
    }

    /// Even with NO usable failure text at all, the typed fact alone must fire.
    func testTheTypedSignalAloneIsEnough() throws {
        XCTAssertNotNil(HostSandboxAdvice.detect(
            workerFailureText: [],
            prompt: "p", projectReference: "/repo", teamId: "t",
            capacityAuthRequired: true,
            environment: sandboxed))
    }

    /// The guard that makes broad matching safe: outside a restricted host these
    /// same failures mean exactly what they say and must NOT be explained away.
    func testNoneOfTheBroadenedSignaturesFireOutsideASandboxedHost() {
        for text in ["ERROR: SecItemCopyMatching failed -67674",
                     "EPERM: operation not permitted",
                     "Permission denied",
                     "Not logged in"] {
            XCTAssertNil(
                HostSandboxAdvice.detect(
                    workerFailureText: [text],
                    prompt: "p", projectReference: "/repo", teamId: "t",
                    environment: [:]),
                "must not explain away \(text) in an ordinary terminal")
        }
        XCTAssertNil(
            HostSandboxAdvice.detect(
                workerFailureText: [], prompt: "p", projectReference: "/repo", teamId: "t",
                capacityAuthRequired: true, environment: [:]),
            "not even the typed signal fires outside a restricted host")
    }

    func testDetectsTheObservedSandboxFailureAndExplainsItWithoutJargon() throws {
        let advice = try XCTUnwrap(HostSandboxAdvice.detect(
            workerFailureText: [codexSignature],
            prompt: "find the riskiest thing in this repo",
            projectReference: "/Users/me/Code/thing",
            teamId: "code_bug_hunt",
            environment: sandboxed))

        // Resume, never restart: a restart would cost the user the session they
        // were working in, which is what made this option look cheap.
        XCTAssertEqual(advice.retryCommand,
                       "codex resume --last -c sandbox_mode=\"danger-full-access\"")
        XCTAssertFalse(advice.warningMessage.contains("Start a new Codex session"))

        // Plain language: no jargon a non-developer would have to look up.
        let body = advice.warningMessage
        for jargon in ["sandbox mode", "Keychain", "spawn", "seatbelt", "TCC", "stderr"] {
            XCTAssertFalse(body.contains(jargon), "message must avoid '\(jargon)': \(body)")
        }
        XCTAssertTrue(body.contains("Nothing is wrong with your setup"))
        XCTAssertTrue(body.contains("nothing is lost"))
        // The hand-off is AUTOMATIC now, so the body must not instruct the user to
        // paste a command the CLI already ran for them — that described a product
        // that had been replaced, and contradicted the "handed this to the app"
        // message printed moments earlier.
        XCTAssertFalse(body.contains("paste this in:"),
                       "the hand-off is automatic; do not ask for a manual paste")
        XCTAssertTrue(body.contains("already handed this to the Mac app"))
        XCTAssertTrue(body.contains("alln run resume"),
                      "the user must be told how to collect the run instead")

        // The option that changes no permissions still leads.
        let appFirst = try XCTUnwrap(body.range(of: "1. If Allnighter is not open"))
        let flagSecond = try XCTUnwrap(body.range(of: "2. Or run it here"))
        XCTAssertTrue(appFirst.lowerBound < flagSecond.lowerBound,
                      "the option that changes no permissions must be offered first")
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
