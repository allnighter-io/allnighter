import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Stall-diagnosis classifier: synthetic process-tree snapshots → named cause.
final class ProcessOwnershipStallDiagnosisTests: XCTestCase {

    func testClassifierNamesCredentialPromptDescendant() throws {
        let tree: [ProcessOwnership.ProcessTreeNode] = [
            .init(pid: 41590, ppid: 41571, name: "cursor-agent", cpuMicroseconds: 1_000_000),
            .init(pid: 46077, ppid: 41590, name: "node", cpuMicroseconds: 500_000),
            .init(pid: 46098, ppid: 46077, name: "git", cpuMicroseconds: 10_000),
            .init(
                pid: 46103, ppid: 46098,
                name: "git-credential-osxkeychain",
                cpuMicroseconds: 0
            ),
            .init(pid: 46105, ppid: 46103, name: "SecurityAgent", cpuMicroseconds: 0),
        ]
        let diagnosis = ProcessOwnership.classifyStallCause(descendants: tree, rootPid: 41590)
        let hit = try XCTUnwrap(diagnosis)
        XCTAssertEqual(hit.kind, .interactiveAuthPrompt)
        XCTAssertEqual(hit.pid, 46103)
        XCTAssertTrue(hit.summary.contains("interactive auth prompt"))
        XCTAssertTrue(hit.summary.contains("git-credential-osxkeychain"))
        XCTAssertTrue(hit.summary.contains("SecurityAgent"))
        XCTAssertTrue(hit.summary.contains("pid 46103"))
        let headline = hit.timeoutHeadline(stalledFor: 32 * 60)
        XCTAssertTrue(headline.hasPrefix("worker turn stalled 32m —"))
        XCTAssertTrue(headline.contains("interactive auth prompt"))
    }

    func testClassifierMatchesTruncatedPCommCredentialHelper() throws {
        // Darwin p_comm is MAXCOMLEN (16) — full helper name truncates.
        let tree: [ProcessOwnership.ProcessTreeNode] = [
            .init(pid: 100, ppid: 1, name: "agent", cpuMicroseconds: 1),
            .init(pid: 101, ppid: 100, name: "git-credential-", cpuMicroseconds: 0),
        ]
        let diagnosis = ProcessOwnership.classifyStallCause(descendants: tree, rootPid: 100)
        let hit = try XCTUnwrap(diagnosis)
        XCTAssertEqual(hit.kind, .interactiveAuthPrompt)
        XCTAssertTrue(hit.summary.contains("git-credential-osxkeychain"))
    }

    func testClassifierMatchesAskpass() {
        let tree: [ProcessOwnership.ProcessTreeNode] = [
            .init(pid: 10, ppid: 1, name: "worker", cpuMicroseconds: 100),
            .init(pid: 11, ppid: 10, name: "ssh-askpass", cpuMicroseconds: 0),
        ]
        let diagnosis = ProcessOwnership.classifyStallCause(descendants: tree, rootPid: 10)
        XCTAssertEqual(diagnosis?.kind, .interactiveAuthPrompt)
        XCTAssertEqual(diagnosis?.pid, 11)
    }

    func testClassifierFrozenZeroCPUDescendant() throws {
        let tree: [ProcessOwnership.ProcessTreeNode] = [
            .init(pid: 50, ppid: 1, name: "worker", cpuMicroseconds: 9_000),
            .init(pid: 51, ppid: 50, name: "swift-build", cpuMicroseconds: 0),
        ]
        let diagnosis = ProcessOwnership.classifyStallCause(descendants: tree, rootPid: 50)
        let hit = try XCTUnwrap(diagnosis)
        XCTAssertEqual(hit.kind, .frozenDescendant)
        XCTAssertEqual(hit.pid, 51)
        XCTAssertTrue(hit.summary.contains("zero CPU"))
        XCTAssertTrue(hit.summary.contains("swift-build"))
    }

    func testClassifierNilWhenOnlyRootPresent() {
        let tree = [ProcessOwnership.ProcessTreeNode(pid: 7, ppid: 1, name: "worker", cpuMicroseconds: 0)]
        XCTAssertNil(ProcessOwnership.classifyStallCause(descendants: tree, rootPid: 7))
    }

    func testClassifierPrefersAuthPromptOverFrozenSibling() {
        let tree: [ProcessOwnership.ProcessTreeNode] = [
            .init(pid: 1, ppid: 0, name: "root", cpuMicroseconds: 1),
            .init(pid: 2, ppid: 1, name: "sleep", cpuMicroseconds: 0),
            .init(pid: 3, ppid: 1, name: "git-credential-osxkeychain", cpuMicroseconds: 0),
        ]
        let diagnosis = ProcessOwnership.classifyStallCause(descendants: tree, rootPid: 1)
        XCTAssertEqual(diagnosis?.kind, .interactiveAuthPrompt)
        XCTAssertEqual(diagnosis?.pid, 3)
    }

    func testIsInteractiveAuthPromptName() {
        XCTAssertTrue(ProcessOwnership.isInteractiveAuthPromptName("SecurityAgent"))
        XCTAssertTrue(ProcessOwnership.isInteractiveAuthPromptName("git-credential-osxkeychain"))
        XCTAssertTrue(ProcessOwnership.isInteractiveAuthPromptName("git-credential-"))
        XCTAssertTrue(ProcessOwnership.isInteractiveAuthPromptName("/usr/libexec/ssh-askpass"))
        XCTAssertFalse(ProcessOwnership.isInteractiveAuthPromptName("git"))
        XCTAssertFalse(ProcessOwnership.isInteractiveAuthPromptName("node"))
    }

    func testSpawnEnvironmentPolicyDeclaresNonInteractiveKeys() {
        let env = AllnighterSpawnEnvironmentPolicy().environment(for: ["PATH": "/usr/bin"])
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(env["GIT_ASKPASS"], "/usr/bin/true")
        XCTAssertEqual(env["SSH_ASKPASS"], "/usr/bin/true")
        XCTAssertEqual(env["SSH_ASKPASS_REQUIRE"], "never")
        XCTAssertEqual(env["ALLNIGHTER_TEAM_DEPTH"], "1")
        XCTAssertNil(env["ALLNIGHTER_TOOL_TOKEN"])
        // Single definition — processEnvironment uses the same policy.
        let viaHelper = AllnighterSpawnEnvironmentPolicy.processEnvironment(extra: ["FOO": "bar"])
        XCTAssertEqual(viaHelper["FOO"], "bar")
        XCTAssertEqual(viaHelper["GIT_TERMINAL_PROMPT"], "0")
    }

    func testSilenceStatusAppendsStallSummary() {
        let line = OwnershipSilencePresentation.silenceStatusLine(
            identityAlive: true,
            lastProgressAt: Date(timeIntervalSince1970: 1_700_000_000),
            now: Date(timeIntervalSince1970: 1_700_000_120),
            stallSummary: "descendant blocked on interactive auth prompt (git-credential-osxkeychain), pid 46103"
        )
        XCTAssertEqual(
            line,
            "alive, no stream for 120s — descendant blocked on interactive auth prompt (git-credential-osxkeychain), pid 46103"
        )
    }

    func testStallDiagnosisRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stall-diag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let diagnosis = ProcessOwnership.StallDiagnosis(
            kind: .interactiveAuthPrompt,
            summary: "descendant blocked on interactive auth prompt (git-credential-osxkeychain), pid 9",
            pid: 9,
            processName: "git-credential-osxkeychain"
        )
        try ProcessOwnership.writeStallDiagnosis(diagnosis, in: dir)
        let loaded = try XCTUnwrap(ProcessOwnership.readStallDiagnosis(in: dir))
        XCTAssertEqual(loaded, diagnosis)
        let headline = try XCTUnwrap(ProcessOwnership.readStallTimeoutHeadline(in: dir))
        XCTAssertTrue(headline.contains("worker turn stalled"))
        XCTAssertTrue(headline.contains("interactive auth prompt"))
    }
}
