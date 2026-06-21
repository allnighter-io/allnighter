import XCTest
@testable import AllnighterEngine

final class DirectModeExposureProviderTests: XCTestCase {
    func testTailscaleHTTPSPlanUsesServeAndCertProbeCommands() throws {
        let plan = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS,
            host: "studio.tail123.ts.net"
        ))

        XCTAssertEqual(plan.endpoint.baseURL, "https://studio.tail123.ts.net")
        XCTAssertEqual(plan.endpoint.commandURL, "https://studio.tail123.ts.net/remote/command")
        XCTAssertEqual(plan.endpoint.transport, .tailscaleHTTPS)
        XCTAssertFalse(plan.endpoint.atsExceptionRequired)
        XCTAssertEqual(plan.serveCommand, [
            "tailscale", "serve", "--bg", "--https=443", "http://127.0.0.1:42123"
        ])
        XCTAssertEqual(plan.certificateProbeCommand, ["tailscale", "cert", "studio.tail123.ts.net"])
    }

    func testTailnetHTTPPlanMarksATSExceptionAndSkipsCertProbe() throws {
        let plan = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailnetHTTP,
            host: "100.100.100.100"
        ))

        XCTAssertEqual(plan.endpoint.baseURL, "http://100.100.100.100")
        XCTAssertEqual(plan.endpoint.commandURL, "http://100.100.100.100/remote/command")
        XCTAssertEqual(plan.endpoint.transport, .tailnetHTTP)
        XCTAssertTrue(plan.endpoint.atsExceptionRequired)
        XCTAssertEqual(plan.serveCommand, [
            "tailscale", "serve", "--bg", "--http=80", "http://127.0.0.1:42123"
        ])
        XCTAssertNil(plan.certificateProbeCommand)
    }

    func testLoopbackProviderNeverPlansTailnetExposure() throws {
        let plan = try LoopbackExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .loopback
        ))

        XCTAssertEqual(plan.endpoint.baseURL, "http://127.0.0.1:42123")
        XCTAssertEqual(plan.endpoint.commandURL, "http://127.0.0.1:42123/remote/command")
        XCTAssertEqual(plan.endpoint.transport, .loopback)
        XCTAssertFalse(plan.endpoint.atsExceptionRequired)
        XCTAssertEqual(plan.serveCommand, [])
        XCTAssertNil(plan.certificateProbeCommand)
    }

    func testExposureEndpointProjectsToPairingEndpoint() throws {
        let https = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS,
            host: "studio.tail123.ts.net"
        )).endpoint.pairingEndpoint
        let loopback = try LoopbackExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .loopback
        )).endpoint.pairingEndpoint

        XCTAssertEqual(https.url, "https://studio.tail123.ts.net")
        XCTAssertEqual(https.transportMode, .tailscaleDirect)
        XCTAssertEqual(loopback.url, "http://127.0.0.1:42123")
        XCTAssertEqual(loopback.transportMode, .loopback)
    }

    func testInvalidPlansAreRejected() throws {
        XCTAssertThrowsError(try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 0,
            transport: .tailscaleHTTPS,
            host: "studio.tail123.ts.net"
        ))) { error in
            XCTAssertEqual(error as? DirectModeExposureError, .invalidLoopbackPort(0))
        }

        XCTAssertThrowsError(try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS
        ))) { error in
            XCTAssertEqual(error as? DirectModeExposureError, .hostRequired(.tailscaleHTTPS))
        }

        XCTAssertThrowsError(try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS,
            host: "https://studio.tail123.ts.net"
        ))) { error in
            XCTAssertEqual(error as? DirectModeExposureError, .invalidHost("https://studio.tail123.ts.net"))
        }

        XCTAssertThrowsError(try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .loopback
        ))) { error in
            XCTAssertEqual(error as? DirectModeExposureError, .unsupportedTransport(.loopback))
        }
    }

    func testReadinessChecksHTTPSCertificateCommandFromProbeScratch() async throws {
        let runner = RecordingDirectModeCommandRunner(result: CommandResult(stdout: "ok", exitCode: 0))
        let plan = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS,
            host: "studio.tail123.ts.net"
        ))

        let readiness = await DirectModeReadinessChecker(commandRunner: runner).check(plan)

        XCTAssertEqual(readiness.kind, .ready)
        XCTAssertTrue(readiness.ok)
        XCTAssertEqual(readiness.checkedCommand, ["tailscale", "cert", "studio.tail123.ts.net"])
        let calls = runner.calls
        XCTAssertEqual(calls.map(\.command), ["tailscale"])
        XCTAssertEqual(calls.first?.args, ["cert", "studio.tail123.ts.net"])
        XCTAssertTrue(calls.first?.workingDirectory?.contains("ProbeScratch") == true)
    }

    func testReadinessReportsHTTPSCertificateSetupFailure() async throws {
        let runner = RecordingDirectModeCommandRunner(result: CommandResult(
            stderr: "HTTPS certificates are not enabled",
            exitCode: 1
        ))
        let plan = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS,
            host: "studio.tail123.ts.net"
        ))

        let readiness = await DirectModeReadinessChecker(commandRunner: runner).check(plan)

        XCTAssertEqual(readiness.kind, .httpsCertificateUnavailable)
        XCTAssertFalse(readiness.ok)
        XCTAssertEqual(readiness.detail, "HTTPS certificates are not enabled")
        XCTAssertEqual(
            readiness.nextAction,
            "Enable HTTPS certificates in the Tailscale admin console, then run `tailscale cert` again."
        )
    }

    func testReadinessReportsMissingTailscale() async throws {
        let runner = RecordingDirectModeCommandRunner(result: CommandResult(
            launchError: "No such file or directory"
        ))
        let plan = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailscaleHTTPS,
            host: "studio.tail123.ts.net"
        ))

        let readiness = await DirectModeReadinessChecker(commandRunner: runner).check(plan)

        XCTAssertEqual(readiness.kind, .tailscaleUnavailable)
        XCTAssertFalse(readiness.ok)
        XCTAssertEqual(readiness.detail, "No such file or directory")
        XCTAssertEqual(readiness.nextAction, "Install Tailscale, sign in, then re-run the Direct Mode check.")
    }

    func testReadinessDoesNotRunCertForLoopbackOrHTTPFallback() async throws {
        let runner = RecordingDirectModeCommandRunner(result: CommandResult(stdout: "should not run", exitCode: 0))
        let loopback = try LoopbackExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .loopback
        ))
        let tailnetHTTP = try TailscaleExposureProvider().plan(DirectModeExposureRequest(
            loopbackPort: 42123,
            transport: .tailnetHTTP,
            host: "100.100.100.100"
        ))

        _ = await DirectModeReadinessChecker(commandRunner: runner).check(loopback)
        _ = await DirectModeReadinessChecker(commandRunner: runner).check(tailnetHTTP)
        XCTAssertTrue(runner.calls.isEmpty)
    }
}

private final class RecordingDirectModeCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        var command: String
        var args: [String]
        var workingDirectory: String?
    }

    private let lock = NSLock()
    private let result: CommandResult
    private var storedCalls: [Call] = []

    init(result: CommandResult) {
        self.result = result
    }

    var calls: [Call] {
        lock.withLock { storedCalls }
    }

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        lock.withLock {
            storedCalls.append(Call(command: command, args: args, workingDirectory: workingDirectory))
        }
        return result
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
