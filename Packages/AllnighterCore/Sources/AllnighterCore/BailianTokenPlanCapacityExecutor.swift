#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Orchestrates Bailian Token Plan Personal usage fetch → parse for the dogfood spike.
public enum BailianTokenPlanCapacityExecutor {

    public typealias ScrapeDiagnostics = OpenCodeGoCapacityExecutor.ScrapeDiagnostics

    public struct Outcome: Sendable, Equatable {
        public let windows: [CapacityWindow]
        public let diagnostics: ScrapeDiagnostics
    }

    public static func execute(
        now: Date,
        credentials: BailianTokenPlanCredentialStore.Credentials? = nil,
        transport: (any BailianTokenPlanCapacityClient.Transport)? = nil,
        ledger: (any BailianTokenPlanLedgerSink)? = nil,
        // Injectable so a test can state "not configured" as a fact instead of
        // hoping the developer's machine has no stored credential. Reading the
        // real store made these tests pass only until the feature was actually
        // set up - the same contamination class as the qualification ledger.
        credentialsResolver: (() -> Result<BailianTokenPlanCredentialStore.Credentials, BailianTokenPlanCredentialStore.LoadError>)? = nil
    ) -> Outcome {
        let ledger = ledger ?? BailianTokenPlanQualificationLedger.fileSink
        let credsResult: Result<BailianTokenPlanCredentialStore.Credentials, BailianTokenPlanCredentialStore.LoadError> =
            credentials.map { Result.success($0) }
                ?? (credentialsResolver ?? { BailianTokenPlanCredentialStore.load().map(\.credentials) })()
        guard case .success(let creds) = credsResult else {
            let failure = credentialFailureKind(credsResult)
            let windows: [CapacityWindow]
            if case .failure(.decryptFailed) = credsResult {
                windows = unknownWindows(reason: .authRequired(observedAt: now), at: now)
            } else {
                windows = neverSampledWindows(at: now)
            }
            let diagnostics = ScrapeDiagnostics(
                attempted: false,
                ok: false,
                failureKind: failure,
                observedAt: now
            )
            ledger.append(diagnostics)
            return Outcome(windows: windows, diagnostics: diagnostics)
        }

        let clientTransport = transport ?? BailianTokenPlanCapacityClient.URLSessionTransport()
        let fetch = BailianTokenPlanCapacityClient.fetch(
            cookieHeader: creds.cookieHeader,
            transport: clientTransport
        )

        switch fetch {
        case .failure(let failure):
            let windows = unknownWindows(for: failure, at: now)
            let diagnostics = ScrapeDiagnostics(
                attempted: true,
                ok: false,
                httpStatus: httpStatus(for: failure),
                failureKind: describe(failure),
                observedAt: now
            )
            ledger.append(diagnostics)
            return Outcome(windows: windows, diagnostics: diagnostics)

        case .success(let success):
            let parsed = BailianTokenPlanCapacityProbe.parseSample(usageJSON: success.json)
            let windows = BailianTokenPlanCapacityProbe.capacityWindows(
                usageJSON: success.json,
                observedAt: now
            )
            let ok = parsed.success != nil && windows.contains {
                $0.scope == .weekly && $0.unknownReason == nil
            }
            let diagnostics = ScrapeDiagnostics(
                attempted: true,
                ok: ok,
                parserStrategy: ok ? BailianTokenPlanCapacityProbe.parseStrategy : nil,
                httpStatus: success.statusCode,
                failureKind: ok ? nil : (parsed.failure.map(describe) ?? "parse_failed"),
                contentBytes: success.byteCount,
                contentType: success.contentType,
                finalURLClass: redactURLClass(success.finalURL),
                missingFields: missingFields(from: parsed),
                bodyFingerprint: BailianTokenPlanCapacityProbe.bodyFingerprint(from: success.json),
                observedAt: now
            )
            ledger.append(diagnostics)
            return Outcome(windows: windows, diagnostics: diagnostics)
        }
    }

    // MARK: - Internals

    private static func neverSampledWindows(at now: Date) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        return [CapacityWindowScope.fiveHour, .weekly].map {
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: BailianTokenPlanCapacityProbe.sourceId,
                scope: $0,
                observedAt: now,
                sourceTier: tier,
                planTier: "Personal"
            )
        }
    }

    private static func unknownWindows(
        reason: CapacityUnknownReason,
        at now: Date
    ) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        return [CapacityWindowScope.fiveHour, .weekly].map {
            CapacityWindow.unknown(
                reason: reason,
                source: BailianTokenPlanCapacityProbe.sourceId,
                scope: $0,
                observedAt: now,
                sourceTier: tier,
                planTier: "Personal"
            )
        }
    }

    private static func unknownWindows(
        for failure: BailianTokenPlanCapacityClient.FetchFailure,
        at now: Date
    ) -> [CapacityWindow] {
        let reason: CapacityUnknownReason
        switch failure {
        case .authRequired:
            reason = .authRequired(observedAt: now)
        case .timeout:
            reason = .probeTimeout(observedAt: now)
        default:
            reason = .parserFailed(observedAt: now)
        }
        return unknownWindows(reason: reason, at: now)
    }

    private static func credentialFailureKind(
        _ result: Result<BailianTokenPlanCredentialStore.Credentials, BailianTokenPlanCredentialStore.LoadError>
    ) -> String {
        switch result {
        case .success: return "configured"
        case .failure(.missingCookie): return "missing_cookie"
        case .failure(.decryptFailed): return "decrypt_failed"
        case .failure(.notConfigured): return "not_configured"
        }
    }

    private static func httpStatus(for failure: BailianTokenPlanCapacityClient.FetchFailure) -> Int? {
        switch failure {
        case .authRequired(let code), .httpError(let code): return code
        default: return nil
        }
    }

    private static func describe(_ failure: BailianTokenPlanCapacityClient.FetchFailure) -> String {
        switch failure {
        case .authRequired: return "auth_required"
        case .httpError: return "http_error"
        case .timeout: return "timeout"
        case .network: return "network"
        case .responseTooLarge: return "response_too_large"
        case .unexpectedContentType: return "unexpected_content_type"
        case .finalURLHostMismatch: return "final_url_host_mismatch"
        }
    }

    private static func describe(_ failure: BailianTokenPlanCapacityProbe.ParseFailure) -> String {
        switch failure {
        case .authRequired: return "auth_required"
        case .schemaDrift: return "schema_drift"
        case .invalidValue: return "invalid_value"
        }
    }

    private static func redactURLClass(_ url: URL) -> String? {
        guard let host = url.host else { return nil }
        return "\(host)\(url.path)"
    }

    private static func missingFields(
        from result: Result<BailianTokenPlanCapacityProbe.ParsedSample, BailianTokenPlanCapacityProbe.ParseFailure>
    ) -> [String] {
        if case .failure(.schemaDrift(let missing)) = result {
            return missing
        }
        return []
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

public protocol BailianTokenPlanLedgerSink: Sendable {
    func append(_ entry: BailianTokenPlanCapacityExecutor.ScrapeDiagnostics)
}

enum BailianTokenPlanQualificationLedger {
    struct FileSink: BailianTokenPlanLedgerSink {
        let url: URL

        init(url: URL = BailianTokenPlanQualificationLedger.ledgerURL()) {
            self.url = url
        }

        func append(_ entry: BailianTokenPlanCapacityExecutor.ScrapeDiagnostics) {
            guard !BailianTokenPlanQualificationLedger.isRunningUnderTestRunner else { return }
            BailianTokenPlanQualificationLedger.write(entry, to: url)
        }
    }

    static var isRunningUnderTestRunner: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        if env["SWIFT_TESTING_ENABLED"] != nil { return true }
        if Bundle.main.bundlePath.contains(".xctest") { return true }
        if ProcessInfo.processInfo.arguments.first?.contains(".xctest") == true { return true }
        return false
    }

    static let fileSink: any BailianTokenPlanLedgerSink = FileSink()

    static func write(_ entry: BailianTokenPlanCapacityExecutor.ScrapeDiagnostics, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(entry)
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url)
            }
        } catch {
            // Best-effort dogfood telemetry.
        }
    }

    static func ledgerURL() -> URL {
        AllnighterSupportRoot.support
            .appendingPathComponent("Capacity", isDirectory: true)
            .appendingPathComponent("bailian-token-plan-qualification.jsonl")
    }
}
