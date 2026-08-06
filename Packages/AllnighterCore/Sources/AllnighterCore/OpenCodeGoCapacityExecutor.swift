import Foundation

/// Orchestrates OpenCode Go dashboard scrape → parse for the dogfood spike.
public enum OpenCodeGoCapacityExecutor {

    public struct ScrapeDiagnostics: Sendable, Equatable, Codable {
        public let attempted: Bool
        public let ok: Bool
        public let parserStrategy: String?
        public let httpStatus: Int?
        public let failureKind: String?
        public let contentBytes: Int?
        public let observedAt: Date

        public init(
            attempted: Bool,
            ok: Bool,
            parserStrategy: String? = nil,
            httpStatus: Int? = nil,
            failureKind: String? = nil,
            contentBytes: Int? = nil,
            observedAt: Date
        ) {
            self.attempted = attempted
            self.ok = ok
            self.parserStrategy = parserStrategy
            self.httpStatus = httpStatus
            self.failureKind = failureKind
            self.contentBytes = contentBytes
            self.observedAt = observedAt
        }
    }

    public struct Outcome: Sendable, Equatable {
        public let windows: [CapacityWindow]
        public let diagnostics: ScrapeDiagnostics
    }

    public static func execute(
        now: Date,
        credentials: OpenCodeGoCredentialStore.Credentials? = nil,
        transport: (any OpenCodeGoCapacityClient.Transport)? = nil
    ) -> Outcome {
        let credsResult = credentials.map { Result.success($0) }
            ?? OpenCodeGoCredentialStore.loadFromEnvironment()
        guard case .success(let creds) = credsResult else {
            let failure = credentialFailureKind(credsResult)
            let windows = neverSampledWindows(at: now)
            let diagnostics = ScrapeDiagnostics(
                attempted: false,
                ok: false,
                failureKind: failure,
                observedAt: now
            )
            OpenCodeGoQualificationLedger.append(diagnostics)
            return Outcome(windows: windows, diagnostics: diagnostics)
        }

        let clientTransport = transport ?? OpenCodeGoCapacityClient.URLSessionTransport()
        let fetch = OpenCodeGoCapacityClient.fetch(
            workspaceId: creds.workspaceId,
            authCookie: creds.authCookie,
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
            OpenCodeGoQualificationLedger.append(diagnostics)
            return Outcome(windows: windows, diagnostics: diagnostics)

        case .success(let success):
            let parsed = OpenCodeGoCapacityProbe.parseSample(html: success.html)
            let windows = OpenCodeGoCapacityProbe.capacityWindows(html: success.html, observedAt: now)
            let ok = parsed.success != nil && windows.allSatisfy { $0.unknownReason == nil }
            let strategy = parsed.success?.strategy.rawValue
            let diagnostics = ScrapeDiagnostics(
                attempted: true,
                ok: ok,
                parserStrategy: strategy,
                httpStatus: success.statusCode,
                failureKind: ok ? nil : (parsed.failure.map(describe) ?? "parse_failed"),
                contentBytes: success.byteCount,
                observedAt: now
            )
            OpenCodeGoQualificationLedger.append(diagnostics)
            return Outcome(windows: windows, diagnostics: diagnostics)
        }
    }

    // MARK: - Internals

    private static func neverSampledWindows(at now: Date) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        return [CapacityWindowScope.fiveHour, .weekly, .monthly].map {
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: OpenCodeGoCapacityProbe.sourceId,
                scope: $0,
                observedAt: now,
                sourceTier: tier,
                planTier: "Go"
            )
        }
    }

    private static func unknownWindows(
        for failure: OpenCodeGoCapacityClient.FetchFailure,
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
        let tier = CapacityAcquisitionTier.dashboardScrape
        return [CapacityWindowScope.fiveHour, .weekly, .monthly].map {
            CapacityWindow.unknown(
                reason: reason,
                source: OpenCodeGoCapacityProbe.sourceId,
                scope: $0,
                observedAt: now,
                sourceTier: tier,
                planTier: "Go"
            )
        }
    }

    private static func credentialFailureKind(
        _ result: Result<OpenCodeGoCredentialStore.Credentials, OpenCodeGoCredentialStore.LoadError>
    ) -> String {
        switch result {
        case .success: return "configured"
        case .failure(.partialEnvironment): return "partial_env"
        case .failure(.missingWorkspaceId): return "missing_workspace_id"
        case .failure(.missingAuthCookie): return "missing_auth_cookie"
        }
    }

    private static func httpStatus(for failure: OpenCodeGoCapacityClient.FetchFailure) -> Int? {
        switch failure {
        case .authRequired(let code), .httpError(let code): return code
        default: return nil
        }
    }

    private static func describe(_ failure: OpenCodeGoCapacityClient.FetchFailure) -> String {
        switch failure {
        case .authRequired: return "auth_required"
        case .httpError: return "http_error"
        case .timeout: return "timeout"
        case .network: return "network"
        case .responseTooLarge: return "response_too_large"
        case .unexpectedContentType: return "unexpected_content_type"
        case .finalURLMismatch: return "final_url_mismatch"
        }
    }

    private static func describe(_ failure: OpenCodeGoCapacityProbe.ParseFailure) -> String {
        switch failure {
        case .authRequired: return "auth_required"
        case .schemaDrift: return "schema_drift"
        case .strategyMismatch: return "strategy_mismatch"
        case .invalidValue: return "invalid_value"
        case .duplicateWindow: return "duplicate_window"
        }
    }
}

private extension Result where Success == OpenCodeGoCapacityProbe.ParsedSample, Failure == OpenCodeGoCapacityProbe.ParseFailure {
    var success: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    var failure: Failure? {
        if case .failure(let value) = self { return value }
        return nil
    }
}

/// Redacted dogfood qualification ledger (no HTML, no cookies).
enum OpenCodeGoQualificationLedger {
    static func append(_ entry: OpenCodeGoCapacityExecutor.ScrapeDiagnostics) {
        let url = ledgerURL()
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
            // Best-effort dogfood telemetry — never block capacity display.
        }
    }

    private static func ledgerURL() -> URL {
        AllnighterSupportRoot.support
            .appendingPathComponent("Capacity", isDirectory: true)
            .appendingPathComponent("opencode-go-qualification.jsonl")
    }
}
