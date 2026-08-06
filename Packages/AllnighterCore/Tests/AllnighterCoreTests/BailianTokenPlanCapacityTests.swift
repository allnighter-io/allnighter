import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

enum BailianTokenPlanFixture {
    static func loadJSON(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bailian-token-plan/\(name).json")
        return try! Data(contentsOf: url)
    }
}

final class BailianTokenPlanCapacityProbeTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_786_000_000)

    func testParsesStandardUsage() throws {
        let data = BailianTokenPlanFixture.loadJSON("personal-usage-standard")
        let result = BailianTokenPlanCapacityProbe.parseSample(usageJSON: data)
        let sample = try XCTUnwrap(result.success)
        XCTAssertEqual(sample.planTier, "Standard")
        if case .limited(let window) = sample.fiveHour {
            XCTAssertEqual(window.usedPercent, 1.37, accuracy: 0.01)
        } else {
            XCTFail("expected limited five-hour window")
        }
        XCTAssertEqual(sample.sevenDay.usedPercent, 1.37, accuracy: 0.01)

        let windows = BailianTokenPlanCapacityProbe.capacityWindows(
            usageJSON: data,
            observedAt: observedAt
        )
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.first?.scope, .fiveHour)
        XCTAssertNil(windows.first?.unknownReason)
        XCTAssertEqual(windows.last?.scope, .weekly)
        XCTAssertNil(windows.last?.unknownReason)
    }

    func testFiveHourLimitRemovedStillParsesSevenDay() throws {
        let data = BailianTokenPlanFixture.loadJSON("personal-usage-five-hour-removed")
        let result = BailianTokenPlanCapacityProbe.parseSample(usageJSON: data)
        let sample = try XCTUnwrap(result.success)
        XCTAssertEqual(sample.fiveHour, .limitRemoved)
        XCTAssertEqual(sample.sevenDay.usedPercent, 1.37, accuracy: 0.01)

        let windows = BailianTokenPlanCapacityProbe.capacityWindows(
            usageJSON: data,
            observedAt: observedAt
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.scope, .weekly)
        XCTAssertNil(windows.first?.unknownReason)

        let row = CapacityBenchProjection.rows(from: windows, now: observedAt).first
        // Unwrap before matching: `case .none = row?...shortWindow` is ambiguous
        // on an Optional<CapacityShortWindowState> — `.none` binds to
        // Optional.none (nil), not to CapacityShortWindowState.none, so a
        // present pool whose short window is genuinely `.none` (n/a) would
        // wrongly fail this guard.
        guard let shortWindow = row?.pools.first?.shortWindow, case .none = shortWindow else {
            return XCTFail("limit removed → no short window (n/a), got \(String(describing: row?.pools.first?.shortWindow))")
        }
    }

    func testSchemaDriftFailsClosed() {
        let data = Data("{}".utf8)
        let result = BailianTokenPlanCapacityProbe.parseSample(usageJSON: data)
        XCTAssertEqual(result.failure, .schemaDrift(missing: ["sevenDay"]))
        let windows = BailianTokenPlanCapacityProbe.capacityWindows(
            usageJSON: data,
            observedAt: observedAt
        )
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == .parserFailed(observedAt: observedAt) })
    }

    func testLoginHTMLMapsToAuthRequired() {
        let data = Data("<html><body>Please login to continue</body></html>".utf8)
        let result = BailianTokenPlanCapacityProbe.parseSample(usageJSON: data)
        XCTAssertEqual(result.failure, .authRequired)
    }
}

private extension Result where Success == BailianTokenPlanCapacityProbe.ParsedSample, Failure == BailianTokenPlanCapacityProbe.ParseFailure {
    var success: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    var failure: Failure? {
        if case .failure(let value) = self { return value }
        return nil
    }
}

final class BailianTokenPlanCapacityExecutorTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_786_000_000)

    private struct FixtureTransport: BailianTokenPlanCapacityClient.Transport {
        let json: Data
        func data(for request: URLRequest) throws -> (Data, URLResponse) {
            let url = request.url!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (json, response)
        }
    }

    func testExecuteWithInjectedJSON() {
        let json = BailianTokenPlanFixture.loadJSON("personal-usage-standard")
        let outcome = BailianTokenPlanCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(cookieHeader: "session=test"),
            transport: FixtureTransport(json: json)
        )
        XCTAssertTrue(outcome.diagnostics.ok)
        XCTAssertEqual(outcome.diagnostics.parserStrategy, BailianTokenPlanCapacityProbe.parseStrategy)
        XCTAssertEqual(outcome.windows.count, 2)
        XCTAssertNotNil(outcome.windows.first { $0.scope == .weekly && $0.unknownReason == nil })
    }

    func testMissingCredentialsNeverSampled() {
        unsetenv(BailianTokenPlanCredentialStore.cookieEnv)
        let outcome = BailianTokenPlanCapacityExecutor.execute(
            now: observedAt,
            credentials: nil,
            transport: FixtureTransport(json: Data()),
            credentialsResolver: { .failure(.notConfigured) }
        )
        XCTAssertFalse(outcome.diagnostics.attempted)
        XCTAssertTrue(outcome.windows.allSatisfy { $0.unknownReason == .neverSampled })
    }

    func testAuthHTTPStatusMapsToAuthRequired() {
        struct AuthTransport: BailianTokenPlanCapacityClient.Transport {
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
        let outcome = BailianTokenPlanCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(cookieHeader: "session=test"),
            transport: AuthTransport()
        )
        XCTAssertEqual(outcome.diagnostics.failureKind, "auth_required")
        XCTAssertTrue(outcome.windows.allSatisfy {
            $0.unknownReason == .authRequired(observedAt: observedAt)
        })
    }
}

final class BailianTokenPlanDogfoodGateTests: XCTestCase {

    func testOnBenchRosterButNotPTY() {
        XCTAssertTrue(
            CapacityAcquisition.benchSourceOrder.contains(CapacityAcquisition.bailianTokenPlanSourceId)
        )
        XCTAssertFalse(
            CapacityAcquisition.ptySourceOrder.contains(CapacityAcquisition.bailianTokenPlanSourceId)
        )
        XCTAssertEqual(
            CapacityStripRenderer.displayName(for: CapacityAcquisition.bailianTokenPlanSourceId),
            "Qwen"
        )
    }

    func testRequiresDogfoodFlag() {
        XCTAssertNotNil(
            CapacityAcquisition.validateRefreshSourceId(
                CapacityAcquisition.bailianTokenPlanSourceId,
                dogfood: false
            )
        )
        XCTAssertNil(
            CapacityAcquisition.validateRefreshSourceId(
                CapacityAcquisition.bailianTokenPlanSourceId,
                dogfood: true
            )
        )
    }

    func testFeatureGateBlocksNetwork() {
        let result = CapacityFetch.dogfoodBailianTokenPlanSnapshot(
            now: Date(timeIntervalSince1970: 1_786_000_000),
            featureEnabled: false
        )
        XCTAssertFalse(result.diagnostics.attempted)
        XCTAssertEqual(result.diagnostics.failureKind, "feature_disabled")
    }

    func testDogfoodDisabledSnapshotIncludesQwenRow() {
        let snap = CapacityFetch.dogfoodBailianTokenPlanSnapshot(
            now: Date(timeIntervalSince1970: 1_786_000_000),
            featureEnabled: false
        ).snapshot
        XCTAssertEqual(snap.rows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertTrue(snap.rows.contains { $0.source == CapacityAcquisition.bailianTokenPlanSourceId })
    }
}

final class BailianTokenPlanCredentialStoreTests: XCTestCase {

    func testLoadsFromEnvironment() {
        let result = BailianTokenPlanCredentialStore.load(
            environment: [BailianTokenPlanCredentialStore.cookieEnv: "a=b; c=d"]
        )
        XCTAssertEqual(
            result,
            .success(.init(credentials: .init(cookieHeader: "a=b; c=d"), source: .environment))
        )
    }
}
