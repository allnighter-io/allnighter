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
}
