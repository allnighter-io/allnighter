import XCTest
@testable import AllnighterCore

/// CONT-S1a: manifest-driven resume/first-turn argv. These are the argv kill tests — the
/// proof that turn 2 carries the stored resume id and never the global `--continue`.
final class DriverManifestSessionArgsTests: XCTestCase {

    private func manifest(_ session: DriverManifest.Session) -> DriverManifest {
        DriverManifest(
            id: "x", displayName: "X", kind: .headlessCLI,
            invoke: .init(command: "x", args: ["-p", "{{prompt}}", "--model", "{{model}}"]),
            session: session)
    }

    private func ctx(prompt: String = "hi", model: String = "m", sessionId: String? = nil) -> DriverManifest.ResolveContext {
        DriverManifest.ResolveContext(prompt: prompt, model: model, resumeSessionId: sessionId)
    }

    // claude shape — we MINT the id on turn 1, resume by it after.
    private let claudeSession = DriverManifest.Session(
        continuity: .vendorSession, acquire: .set,
        firstTurnArgs: ["-p", "{{prompt}}", "--model", "{{model}}", "--session-id", "{{sessionId}}"],
        resumeArgs: ["-p", "{{prompt}}", "--model", "{{model}}", "--resume", "{{sessionId}}"])

    func testFirstTurnMintsSessionId() {
        let args = manifest(claudeSession).resolvedSessionArgs(ctx(sessionId: "uuid-1"), resuming: false)
        XCTAssertEqual(args, ["-p", "hi", "--model", "m", "--session-id", "uuid-1"])
    }

    func testResumeUsesStoredIdAndNeverContinue() {
        let args = manifest(claudeSession).resolvedSessionArgs(ctx(prompt: "turn2", sessionId: "stored-id"), resuming: true)
        XCTAssertEqual(args, ["-p", "turn2", "--model", "m", "--resume", "stored-id"])
        XCTAssertFalse(args!.contains("--continue"), "thread continuity must never use global --continue")
        XCTAssertFalse(args!.contains("-c"))
    }

    func testPromptStaysOneArgvElement() {
        // Injection-safe: a prompt with spaces/flags is ONE element, can't inject args.
        let args = manifest(claudeSession).resolvedSessionArgs(ctx(prompt: "rm -rf / --now", sessionId: "id"), resuming: true)
        XCTAssertTrue(args!.contains("rm -rf / --now"), "the whole prompt is a single argv element")
    }

    func testCodexResumeReshapesArgv() {
        let codex = DriverManifest.Session(
            continuity: .vendorSession, acquire: .capture,
            resumeArgs: ["exec", "resume", "{{sessionId}}", "--skip-git-repo-check", "{{prompt}}"],
            capture: .init(from: .stdout, field: "session_id: ([0-9a-f-]+)"))
        let args = manifest(codex).resolvedSessionArgs(ctx(prompt: "p2", sessionId: "cx-1"), resuming: true)
        XCTAssertEqual(args, ["exec", "resume", "cx-1", "--skip-git-repo-check", "p2"])
    }

    func testCaptureFirstTurnReturnsNil() {
        // acquire=capture: turn 1 has no minted id — caller runs base args + captures from output.
        let grok = DriverManifest.Session(
            continuity: .vendorSession, acquire: .capture,
            resumeArgs: ["-p", "{{prompt}}", "--resume", "{{sessionId}}"],
            capture: .init(from: .streamJson, field: "session_id"))
        XCTAssertNil(manifest(grok).resolvedSessionArgs(ctx(), resuming: false),
                     "capture first turn uses base args, not a session template")
    }

    func testNoVendorSessionReturnsNil() {
        let agy = DriverManifest.Session(continuity: .promptContextOnly)
        XCTAssertNil(manifest(agy).resolvedSessionArgs(ctx(sessionId: "x"), resuming: true))
        // and a manifest with no session block at all:
        let plain = DriverManifest(id: "y", displayName: "Y", kind: .headlessCLI,
                                   invoke: .init(command: "y", args: ["{{prompt}}"]))
        XCTAssertNil(plain.resolvedSessionArgs(ctx(sessionId: "x"), resuming: true))
    }
}
