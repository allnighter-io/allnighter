import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class InvocationKindStampingWorkerRunnerTests: XCTestCase {
    private func innerWithDiagnostics() -> MockWorkerInvoking {
        let diagnostics = WorkerSpawnDiagnostics(
            command: "claude", argCount: 2, workingDirectory: nil, timeoutSeconds: 60,
            timeoutKind: .idle, stdoutBytes: 0, stderrBytes: 0, stderrTail: nil, invocationKind: nil)
        return MockWorkerInvoking(events: [
            .started(workerId: "mock", modelId: "mock", sourceId: "claude_code"),
            .completed(WorkerRunResult(status: .done, output: "hi", spawnDiagnostics: diagnostics)),
        ])
    }

    func testStampsDirectInvocationKind() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let stamping = InvocationKindStampingWorkerRunner(
            inner: innerWithDiagnostics(), invocations: ["claude": .direct(path: "/opt/test/claude")])

        let result = await stamping.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.spawnDiagnostics?.invocationKind, "direct")
    }

    func testStampsLoginShellInvocationKind() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let stamping = InvocationKindStampingWorkerRunner(
            inner: innerWithDiagnostics(), invocations: ["claude": .loginShell(commandName: "claude")])

        let result = await stamping.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.spawnDiagnostics?.invocationKind, "login_shell")
    }

    func testStampsAmbientWhenCommandIsUnmapped() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let stamping = InvocationKindStampingWorkerRunner(inner: innerWithDiagnostics(), invocations: [:])

        let result = await stamping.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.spawnDiagnostics?.invocationKind, "ambient")
    }
}
