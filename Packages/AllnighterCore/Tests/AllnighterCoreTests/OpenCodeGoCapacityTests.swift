import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

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
            transport: FixtureTransport(html: ""),
            credentialsResolver: { .failure(.notConfigured) }
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

    /// Promoted (OCG-S08): a normal `--source`, accepted with or without the
    /// retired --dogfood gate. A typo is still refused.
    func testOpenCodeGoAcceptedAsNormalSource() {
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("opencode_go", dogfood: false))
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("opencode_go", dogfood: true))
        XCTAssertNotNil(CapacityAcquisition.validateRefreshSourceId("opencode_goo", dogfood: false))
    }

    func testFullRefreshPTYSourcesExcludeDogfoodSource() {
        let sources = CapacityAcquisition.sourcesProbed(refresh: true)
        XCTAssertFalse(
            sources.contains(CapacityAcquisition.dogfoodSourceId),
            "The Go dashboard seat is a browser scrape and must never be sent through the PTY probe path"
        )
    }

    func testTargetedRefreshOfDogfoodSourceProbesNoPTYSeat() {
        let sources = CapacityAcquisition.sourcesProbed(
            refresh: true,
            refreshSource: CapacityAcquisition.dogfoodSourceId
        )
        XCTAssertTrue(
            sources.isEmpty,
            "Asking to refresh the Go seat must probe no PTY seat at all, not fall back to the full bench"
        )
    }

    func testBenchSourceOrderKeepsDogfoodSourceExcludedAtSix() {
        XCTAssertFalse(
            CapacityAcquisition.ptySourceOrder.contains(CapacityAcquisition.dogfoodSourceId),
            "the Go seat is a browser scrape and must never appear in the PTY roster"
        )
        XCTAssertTrue(
            CapacityAcquisition.benchSourceOrder.contains(CapacityAcquisition.dogfoodSourceId),
            "promoted (OCG-S08): the Go seat is a normal bench seat"
        )
        XCTAssertEqual(
            CapacityAcquisition.ptySourceOrder.count, 6,
            "promotion must not have added a seat to the PTY roster"
        )
        XCTAssertEqual(
            CapacityStripRenderer.displayOrder,
            CapacityAcquisition.benchSourceOrder,
            "strip order must not drift from the bench roster"
        )
    }

    func testValidateRefreshSourceIdDogfoodConstant() {
        // Promoted (OCG-S08): accepted either way. The --dogfood gate is gone,
        // but the PTY exclusion above is NOT — that one still has to hold.
        XCTAssertNil(
            CapacityAcquisition.validateRefreshSourceId(CapacityAcquisition.dogfoodSourceId, dogfood: false)
        )
        XCTAssertNil(
            CapacityAcquisition.validateRefreshSourceId(CapacityAcquisition.dogfoodSourceId, dogfood: true)
        )
    }
}

final class OpenCodeGoDogfoodFeatureGateTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)

    func testFeatureDisabledReturnsDisabledRowsNotNeverSampled() {
        let result = CapacityFetch.dogfoodOpenCodeGoSnapshot(
            now: observedAt,
            featureEnabled: false
        )
        XCTAssertTrue(
            result.snapshot.rows.allSatisfy { $0.unknownReason == .disabled },
            "Feature OFF must produce .disabled rows, not .neverSampled — the gate must be honoured"
        )
        XCTAssertFalse(
            result.diagnostics.attempted,
            "Feature OFF must not attempt a network scrape"
        )
        XCTAssertFalse(result.diagnostics.ok)
    }

    func testFeatureDisabledDoesNotCallExecutor() {
        let result = CapacityFetch.dogfoodOpenCodeGoSnapshot(
            now: observedAt,
            featureEnabled: false
        )
        XCTAssertEqual(result.diagnostics.failureKind, "feature_disabled")
        XCTAssertNil(result.diagnostics.httpStatus)
        XCTAssertNil(result.diagnostics.parserStrategy)
        XCTAssertEqual(
            result.snapshot.rows.count,
            CapacityAcquisition.benchSourceOrder.count,
            "Feature OFF must return only the six bench rows, no dogfood seat"
        )
    }

    func testFeatureEnabledCallsExecutor() {
        unsetenv(OpenCodeGoCredentialStore.workspaceIdEnv)
        unsetenv(OpenCodeGoCredentialStore.authCookieEnv)
        let result = CapacityFetch.dogfoodOpenCodeGoSnapshot(
            now: observedAt,
            featureEnabled: true,
            credentialsResolver: { .failure(.notConfigured) }
        )
        XCTAssertTrue(
            result.snapshot.rows.contains { $0.source == CapacityAcquisition.dogfoodSourceId },
            "Feature ON must include the Go seat row"
        )
        XCTAssertFalse(
            result.diagnostics.attempted,
            "Without credentials the executor must not attempt a scrape"
        )
    }
}

/// OCG-S05 — the qualification ledger is the founder's promotion evidence. It
/// had no test isolation, so 45 fabricated `ok:true` rows (all stamped with the
/// hardcoded test date) were written into the real file. Two independent
/// guards now prevent that.
final class OpenCodeGoLedgerIsolationTests: XCTestCase {

    private final class RecordingSink: OpenCodeGoLedgerSink, @unchecked Sendable {
        private(set) var entries: [OpenCodeGoCapacityExecutor.ScrapeDiagnostics] = []
        func append(_ entry: OpenCodeGoCapacityExecutor.ScrapeDiagnostics) {
            entries.append(entry)
        }
    }

    /// Guard 1: execute() routes diagnostics to the injected sink.
    func testExecuteRecordsToInjectedSink() {
        let sink = RecordingSink()
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: Date(timeIntervalSince1970: 1_754_000_000),
            credentials: nil,
            ledger: sink
        )
        XCTAssertEqual(sink.entries.count, 1)
        XCTAssertEqual(sink.entries.first, outcome.diagnostics)
    }

    /// Guard 2, the backstop: the file sink writes nothing under the test
    /// runner even when it is handed a path it owns. This is what protects the
    /// real ledger from a future test that forgets to inject.
    func testFileSinkWritesNothingUnderTestRunner() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-ledger-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("qualification.jsonl")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(
            OpenCodeGoQualificationLedger.isRunningUnderTestRunner,
            "this test is meaningless if the runner is not detected"
        )
        OpenCodeGoQualificationLedger.FileSink(url: url).append(
            OpenCodeGoCapacityExecutor.ScrapeDiagnostics(
                attempted: true, ok: true, observedAt: Date(timeIntervalSince1970: 1_754_000_000)
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "the file sink must not write while under a test runner"
        )
    }

    /// The default stays the file sink, so production behavior is unchanged.
    func testDefaultSinkIsFileSink() {
        XCTAssertTrue(OpenCodeGoQualificationLedger.fileSink is OpenCodeGoQualificationLedger.FileSink)
    }
}

/// OCG-S06 — encrypted credential persistence.
final class OpenCodeGoCredentialPersistenceTests: XCTestCase {

    private var dir: URL!
    private var credURL: URL!
    private var keyURL: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-creds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        credURL = dir.appendingPathComponent("opencode_go.enc")
        keyURL = dir.appendingPathComponent("machine.key")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let sample = OpenCodeGoCredentialStore.Credentials(
        workspaceId: "wrk_TESTONLY", authCookie: "cookie-value-testonly"
    )

    func testRoundTrip() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        let loaded = OpenCodeGoCredentialStore.loadFromFile(credentialURL: credURL, keyURL: keyURL)
        XCTAssertEqual(try loaded.get(), sample)
    }

    /// The cookie is a full web session. It must not be recoverable from the
    /// file by anything that does not hold the machine key.
    func testCookieIsNotPresentInPlaintextOnDisk() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        let raw = try Data(contentsOf: credURL)
        XCTAssertNil(
            raw.range(of: Data(sample.authCookie.utf8)),
            "the auth cookie must never appear as plaintext bytes on disk"
        )
        XCTAssertNil(raw.range(of: Data(sample.workspaceId.utf8)))
    }

    func testCredentialAndKeyAreOwnerOnly() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        for url in [credURL!, keyURL!] {
            let perms = try FileManager.default
                .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(perms?.intValue, 0o600, "\(url.lastPathComponent) must be owner-only")
        }
    }

    /// A rotated or corrupt key must be distinguishable from "never configured",
    /// so the strip can say auth-required instead of inviting a fresh setup.
    func testWrongKeyIsDecryptFailedNotNotConfigured() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        try Data(RemoteMediaCrypto.randomContentKey()).write(to: keyURL)
        let result = OpenCodeGoCredentialStore.loadFromFile(credentialURL: credURL, keyURL: keyURL)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .decryptFailed)
    }

    func testAbsentFileIsNotConfigured() {
        let result = OpenCodeGoCredentialStore.loadFromFile(credentialURL: credURL, keyURL: keyURL)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notConfigured)
    }

    func testEnvironmentOverridesStoredFile() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        let resolved = try OpenCodeGoCredentialStore.load(
            environment: [
                OpenCodeGoCredentialStore.workspaceIdEnv: "wrk_FROM_ENV",
                OpenCodeGoCredentialStore.authCookieEnv: "env-cookie",
            ],
            credentialURL: credURL,
            keyURL: keyURL
        ).get()
        XCTAssertEqual(resolved.source, .environment)
        XCTAssertEqual(resolved.credentials.workspaceId, "wrk_FROM_ENV")
    }

    /// Half-set env is a mistake, not an intention. It must refuse rather than
    /// quietly scrape with the stored credential the caller was overriding.
    func testPartialEnvironmentRefusesAndDoesNotFallBackToFile() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        let result = OpenCodeGoCredentialStore.load(
            environment: [OpenCodeGoCredentialStore.workspaceIdEnv: "wrk_ONLY"],
            credentialURL: credURL,
            keyURL: keyURL
        )
        guard case .failure(let error) = result else { return XCTFail("expected refusal") }
        XCTAssertEqual(error, .partialEnvironment)
    }

    func testFallsBackToFileWhenEnvironmentEmpty() throws {
        try OpenCodeGoCredentialStore.save(sample, credentialURL: credURL, keyURL: keyURL)
        let resolved = try OpenCodeGoCredentialStore.load(
            environment: [:], credentialURL: credURL, keyURL: keyURL
        ).get()
        XCTAssertEqual(resolved.source, .encryptedFile)
        XCTAssertEqual(resolved.credentials, sample)
    }
}

/// The dashboard result must REPLACE the acquisition placeholder for the Go
/// seat, never sit behind it. CapacityAcquisition emits a `neverSampled` row
/// for every bench member including Go, and the projection takes the FIRST
/// unknownReason per source — so appending let the placeholder win and painted
/// a real auth failure as "never sampled". That invents the cause: the owner
/// reads "not set up yet" while the actual problem is a dead cookie.
final class OpenCodeGoPlaceholderMaskingTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)

    private struct AuthFailingTransport: OpenCodeGoCapacityClient.Transport {
        func data(for request: URLRequest) throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (Data(), response)
        }
    }

    private final class DiscardingSink: OpenCodeGoLedgerSink, @unchecked Sendable {
        func append(_ entry: OpenCodeGoCapacityExecutor.ScrapeDiagnostics) {}
    }

    func testRealAuthFailureIsNotMaskedByTheAcquisitionPlaceholder() throws {
        let outcome = OpenCodeGoCapacityExecutor.execute(
            now: observedAt,
            credentials: .init(workspaceId: "wrk_TESTONLY", authCookie: "testonly"),
            transport: AuthFailingTransport(),
            ledger: DiscardingSink()
        )
        // The executor itself must report the real cause.
        XCTAssertTrue(outcome.windows.allSatisfy { $0.unknownReason == .authRequired(observedAt: observedAt) })

        // And after merging with a full bench acquisition (which contributes a
        // neverSampled placeholder for the same source), the real cause must
        // still be what the projection reports.
        let bench = CapacityAcquisition.windows(now: observedAt, refresh: false)
        let merged = bench.filter { $0.source != CapacityAcquisition.dogfoodSourceId } + outcome.windows
        let rows = CapacityBenchProjection.rows(from: merged, now: observedAt)
        let go = try XCTUnwrap(rows.first { $0.source == CapacityAcquisition.dogfoodSourceId })
        XCTAssertEqual(
            go.unknownReason, .authRequired(observedAt: observedAt),
            "a real auth failure must not be reported as neverSampled"
        )

        // Proof this test can fail: the OLD merge order (append, do not filter)
        // really does mask the cause. Without this, the assertion above could
        // be passing for reasons unrelated to the fix.
        let maskedRows = CapacityBenchProjection.rows(
            from: bench + outcome.windows, now: observedAt
        )
        let masked = try XCTUnwrap(maskedRows.first { $0.source == CapacityAcquisition.dogfoodSourceId })
        XCTAssertEqual(
            masked.unknownReason, .neverSampled,
            "if this ever stops masking, the filter in CapacityFetch is no longer load-bearing and this test should be revisited"
        )
    }
}

final class OpenCodeGoCookieLeakDefenseTests: XCTestCase {

    private struct SameHostTransport: OpenCodeGoCapacityClient.Transport {
        func data(for request: URLRequest) throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            return ("<html><body>ok</body></html>".data(using: .utf8)!, response)
        }
    }

    private struct CrossHostTransport: OpenCodeGoCapacityClient.Transport {
        func data(for request: URLRequest) throws -> (Data, URLResponse) {
            let foreignURL = URL(string: "https://evil.example.com/go")!
            let response = HTTPURLResponse(
                url: foreignURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            return ("<html><body>stolen</body></html>".data(using: .utf8)!, response)
        }
    }

    func testSameHostSuccessReturnsSuccess() {
        let result = OpenCodeGoCapacityClient.fetch(
            workspaceId: "wrk_test",
            authCookie: "test-cookie-value",
            transport: SameHostTransport()
        )
        guard case .success(let s) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(s.statusCode, 200)
        XCTAssertEqual(s.finalURL.host, OpenCodeGoCapacityClient.expectedHost)
    }

    func testCrossHostRedirectFailsClosed() {
        let result = OpenCodeGoCapacityClient.fetch(
            workspaceId: "wrk_test",
            authCookie: "test-cookie-value",
            transport: CrossHostTransport()
        )
        XCTAssertEqual(result, .failure(.finalURLHostMismatch))
    }
}

/// Workspace discovery — the id is a URL path segment, not a secret, and the
/// machine already knows it, so setup should not ask for it.
final class OpenCodeGoWorkspaceDiscoveryTests: XCTestCase {

    func testFindsIdInArbitraryBytes() {
        let data = Data("\u{0}\u{1}garbage wrk_01KZAKC3FS66DE4V0CG7YESNC3 more".utf8)
        XCTAssertEqual(
            OpenCodeGoCredentialStore.workspaceIds(in: data),
            ["wrk_01KZAKC3FS66DE4V0CG7YESNC3"]
        )
    }

    /// Short runs are noise, not ids — a bare `wrk_` marker in a schema string
    /// must not be mistaken for a workspace.
    func testIgnoresShortNoiseTokens() {
        XCTAssertTrue(OpenCodeGoCredentialStore.workspaceIds(in: Data("wrk_ wrk_abc".utf8)).isEmpty)
    }

    /// Two workspaces is a genuine choice. Guessing which one to meter is the
    /// silent inference this project bans, so discovery must decline.
    func testDeclinesWhenAmbiguous() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-home-\(UUID().uuidString)", isDirectory: true)
        let state = dir.appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("wrk_01KZAKC3FS66DE4V0CG7YESNC3 wrk_01AAAAAAAAAAAAAAAAAAAAAAAA".utf8)
            .write(to: state.appendingPathComponent("auth.json"))
        XCTAssertNil(OpenCodeGoCredentialStore.discoverWorkspaceId(home: dir))
    }

    func testReturnsNilWhenNoLocalState() {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-empty-\(UUID().uuidString)", isDirectory: true)
        XCTAssertNil(OpenCodeGoCredentialStore.discoverWorkspaceId(home: empty))
    }
}

/// The capacity feature toggle. `saveEnabled` had no caller, so the only way to
/// turn capacity off was hand-editing JSON — which blocked the trust-gate row
/// "Feature OFF: zero timer probes".
final class CapacityFeatureToggleTests: XCTestCase {

    private func store() throws -> (CapacityFeatureSettingsPersistence, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cap-toggle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("capacity_feature.json")
        return (CapacityFeatureSettingsPersistence(fileURL: url), dir)
    }

    /// A fresh install must be ON without any file being written.
    func testDefaultIsEnabledWithNoFile() throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(s.loadEnabled())
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("capacity_feature.json").path),
            "reading the default must not create a file"
        )
    }

    func testRoundTripDisableThenEnable() throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try s.saveEnabled(false)
        XCTAssertFalse(s.loadEnabled(), "disable must persist")
        try s.saveEnabled(true)
        XCTAssertTrue(s.loadEnabled(), "enable must persist")
    }
}
