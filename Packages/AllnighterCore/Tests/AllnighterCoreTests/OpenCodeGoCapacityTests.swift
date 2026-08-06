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
}

final class OpenCodeGoDogfoodGateTests: XCTestCase {

    func testOpenCodeGoRejectedWithoutDogfoodFlag() {
        XCTAssertNotNil(CapacityAcquisition.validateRefreshSourceId("opencode_go", dogfood: false))
    }

    func testOpenCodeGoAcceptedWithDogfoodFlag() {
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("opencode_go", dogfood: true))
    }
}
