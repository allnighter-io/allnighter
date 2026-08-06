import XCTest
@testable import AllnighterCore

final class OpenCodeGoCredentialStoreTests: XCTestCase {

    func testBothEnvVarsRequired() {
        let result = OpenCodeGoCredentialStore.loadFromEnvironment(environment: [
            OpenCodeGoCredentialStore.workspaceIdEnv: "wrk_test",
        ])
        XCTAssertEqual(result, .failure(.partialEnvironment))
    }

    func testLoadsWhenBothSet() {
        let result = OpenCodeGoCredentialStore.loadFromEnvironment(environment: [
            OpenCodeGoCredentialStore.workspaceIdEnv: "wrk_test",
            OpenCodeGoCredentialStore.authCookieEnv: "cookie_value",
        ])
        XCTAssertEqual(
            result,
            .success(.init(workspaceId: "wrk_test", authCookie: "cookie_value"))
        )
    }
}

final class OpenCodeGoCapacityExecutorTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)

    private struct FixtureTransport: OpenCodeGoCapacityClient.Transport {
        let html: String
        func data(for request: URLRequest) throws -> (Data, URLResponse) {
            let url = request.url!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            return (html.data(using: .utf8)!, response)
        }
    }

    func testExecuteWithInjectedHTML() {
        let html = """
        rollingUsage:$R[0]={usagePercent:5,resetInSec:300}
        weeklyUsage:$R[1]={usagePercent:10,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:15,resetInSec:7200}
        """
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(workspaceId: "wrk_test", authCookie: "secret"),
            transport: FixtureTransport(html: html)
        )
        XCTAssertTrue(outcome.diagnostics.ok)
        XCTAssertEqual(outcome.diagnostics.parserStrategy, "solid_ssr_v1")
        XCTAssertEqual(outcome.windows.count, 3)
        XCTAssertTrue(outcome.windows.allSatisfy { $0.unknownReason == nil })
    }

    func testMissingCredentialsNeverSampled() {
        unsetenv(OpenCodeGoCredentialStore.workspaceIdEnv)
        unsetenv(OpenCodeGoCredentialStore.authCookieEnv)
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: nil,
            transport: FixtureTransport(html: "")
        )
        XCTAssertFalse(outcome.diagnostics.attempted)
        XCTAssertFalse(outcome.diagnostics.ok)
        XCTAssertTrue(outcome.windows.allSatisfy { $0.unknownReason == .neverSampled })
    }

    func testAuthHTTPStatusMapsToAuthRequired() {
        struct AuthTransport: OpenCodeGoCapacityClient.Transport {
            func data(for request: URLRequest) throws -> (Data, URLResponse) {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (Data(), response)
            }
        }
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(workspaceId: "wrk_test", authCookie: "secret"),
            transport: AuthTransport()
        )
        XCTAssertEqual(outcome.diagnostics.failureKind, "auth_required")
        XCTAssertTrue(outcome.windows.allSatisfy {
            $0.unknownReason == .authRequired(observedAt: observedAt)
        })
    }

    func testSchemaDriftRecordsMissingFields() {
        let html = "<html><body><h1>Dashboard</h1></body></html>"
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(workspaceId: "wrk_test", authCookie: "secret"),
            transport: FixtureTransport(html: html)
        )
        XCTAssertFalse(outcome.diagnostics.ok)
        XCTAssertEqual(outcome.diagnostics.failureKind, "schema_drift")
        XCTAssertTrue(outcome.diagnostics.missingFields.contains("rolling"))
        XCTAssertTrue(outcome.diagnostics.missingFields.contains("weekly"))
        XCTAssertTrue(outcome.diagnostics.missingFields.contains("monthly"))
    }

    func testSuccessfulScrapeRecordsContentTypeAndFingerprint() {
        let html = """
        rollingUsage:$R[0]={usagePercent:5,resetInSec:300}
        weeklyUsage:$R[1]={usagePercent:10,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:15,resetInSec:7200}
        """
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(workspaceId: "wrk_test", authCookie: "secret"),
            transport: FixtureTransport(html: html)
        )
        XCTAssertEqual(outcome.diagnostics.contentType, "text/html; charset=utf-8")
        XCTAssertNotNil(outcome.diagnostics.bodyFingerprint)
        XCTAssertFalse(outcome.diagnostics.bodyFingerprint?.isEmpty ?? true)
    }

    func testEncodedDiagnosticsExcludeCookieAndHTML() {
        let html = """
        rollingUsage:$R[0]={usagePercent:5,resetInSec:300}
        weeklyUsage:$R[1]={usagePercent:10,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:15,resetInSec:7200}
        <div class="dashboard">Go usage dashboard</div>
        """
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(workspaceId: "wrk_test", authCookie: "super_secret_cookie"),
            transport: FixtureTransport(html: html)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(outcome.diagnostics)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertFalse(json.contains("super_secret_cookie"),
                       "Encoded diagnostics must not contain the auth cookie value")
        XCTAssertFalse(json.contains("dashboard"),
                       "Encoded diagnostics must not contain HTML fragments")
        XCTAssertFalse(json.contains("rollingUsage"),
                       "Encoded diagnostics must not contain raw HTML markers")
    }

    func testBodyFingerprintStableAcrossValueChanges() {
        let htmlA = """
        rollingUsage:$R[0]={usagePercent:5,resetInSec:300}
        weeklyUsage:$R[1]={usagePercent:10,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:15,resetInSec:7200}
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling</span>
          <span data-slot="usage-value">5%</span>
          <span data-slot="reset-time">Resets in 5 min</span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly</span>
          <span data-slot="usage-value">10%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly</span>
          <span data-slot="usage-value">15%</span>
          <span data-slot="reset-time">Resets in 6 days</span>
        </div>
        """
        let htmlB = """
        rollingUsage:$R[0]={usagePercent:99,resetInSec:1}
        weeklyUsage:$R[1]={usagePercent:0,resetInSec:86400}
        monthlyUsage:$R[2]={usagePercent:50,resetInSec:999}
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling</span>
          <span data-slot="usage-value">99%</span>
          <span data-slot="reset-time">Resets in 1 sec</span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly</span>
          <span data-slot="usage-value">0%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly</span>
          <span data-slot="usage-value">50%</span>
          <span data-slot="reset-time">Resets in 16 min</span>
        </div>
        <script nonce="abc123xyz">window.__INIT__={...}</script>
        """
        let fpA = OpenCodeGoCapacityExecutor.bodyFingerprint(from: htmlA)
        let fpB = OpenCodeGoCapacityExecutor.bodyFingerprint(from: htmlB)
        XCTAssertNotNil(fpA)
        XCTAssertNotNil(fpB)
        XCTAssertEqual(fpA, fpB, "Fingerprints must match when markup shape is identical regardless of values")
    }

    func testBodyFingerprintChangesWhenMarkupShapeChanges() {
        let htmlOriginal = """
        rollingUsage:$R[0]={usagePercent:5,resetInSec:300}
        weeklyUsage:$R[1]={usagePercent:10,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:15,resetInSec:7200}
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling</span>
          <span data-slot="usage-value">5%</span>
          <span data-slot="reset-time">Resets in 5 min</span>
        </div>
        """
        let htmlShapeChanged = """
        rollingUsage:$R[0]={usagePercent:5,resetInSec:300}
        weeklyUsage:$R[1]={usagePercent:10,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:15,resetInSec:7200}
        <div data-slot="usage-card">
          <span data-slot="usage-label">Rolling</span>
          <span data-slot="usage-value">5%</span>
          <span data-slot="reset-time">Resets in 5 min</span>
          <span data-slot="usage-trend">stable</span>
        </div>
        """
        let fpOriginal = OpenCodeGoCapacityExecutor.bodyFingerprint(from: htmlOriginal)
        let fpChanged = OpenCodeGoCapacityExecutor.bodyFingerprint(from: htmlShapeChanged)
        XCTAssertNotNil(fpOriginal)
        XCTAssertNotNil(fpChanged)
        XCTAssertNotEqual(fpOriginal, fpChanged, "Fingerprints must differ when markup shape changes")
    }
}

final class OpenCodeGoCapacityTransportTests: XCTestCase {

    func testDefaultTransportHasBoundedResourceTimeout() {
        let transport = OpenCodeGoCapacityClient.URLSessionTransport()
        let config = transport.configuration

        XCTAssertEqual(
            config.timeoutIntervalForRequest,
            OpenCodeGoCapacityClient.defaultTimeout,
            "request timeout should match the configured default"
        )

        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        XCTAssertLessThan(
            config.timeoutIntervalForResource,
            sevenDays,
            "resource timeout must be far below the 7-day URLSession.shared default"
        )

        XCTAssertEqual(
            config.timeoutIntervalForResource,
            OpenCodeGoCapacityClient.defaultTimeout * 2,
            "resource ceiling should be a small fixed multiple of the request timeout"
        )
    }
}

final class OpenCodeGoDogfoodGateTests: XCTestCase {

    func testOpenCodeGoRejectedWithoutDogfoodFlag() {
        XCTAssertNotNil(CapacityAcquisition.validateRefreshSourceId("opencode_go", dogfood: false))
    }

    func testOpenCodeGoAcceptedWithDogfoodFlag() {
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("opencode_go", dogfood: true))
    }
}
