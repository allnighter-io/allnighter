import Foundation
import AllnighterCore

public enum DirectModeExposureTransport: String, Codable, Sendable, CaseIterable {
    case tailscaleHTTPS
    case tailnetHTTP
    case loopback
}

public struct DirectModeExposureRequest: Equatable, Sendable {
    public var loopbackPort: UInt16
    public var transport: DirectModeExposureTransport
    public var host: String?

    public init(
        loopbackPort: UInt16,
        transport: DirectModeExposureTransport,
        host: String? = nil
    ) {
        self.loopbackPort = loopbackPort
        self.transport = transport
        self.host = host
    }
}

public struct DirectModeEndpoint: Codable, Equatable, Sendable {
    public var baseURL: String
    public var commandURL: String
    public var transport: DirectModeExposureTransport
    public var atsExceptionRequired: Bool

    public init(
        baseURL: String,
        commandURL: String,
        transport: DirectModeExposureTransport,
        atsExceptionRequired: Bool
    ) {
        self.baseURL = baseURL
        self.commandURL = commandURL
        self.transport = transport
        self.atsExceptionRequired = atsExceptionRequired
    }

    public var pairingEndpoint: RemotePairingEndpoint {
        RemotePairingEndpoint(url: baseURL, transportMode: transport.connectionMode)
    }

    public var snapshotURL: String {
        url(for: DirectModeCommandServer.snapshotPath)
    }

    public var mediaURL: String {
        url(for: DirectModeCommandServer.mediaPath)
    }

    public var mediaKeyURL: String {
        url(for: DirectModeCommandServer.mediaKeyPath)
    }

    public var eventsURL: String {
        url(for: DirectModeCommandServer.eventsPath)
    }

    public func url(for path: String) -> String {
        Self.routeURL(baseURL: baseURL, path: path)
    }

    public static func routeURL(baseURL: String, path: String) -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return "\(trimmedBase)\(normalizedPath)"
    }
}

public struct DirectModeExposurePlan: Equatable, Sendable {
    public var endpoint: DirectModeEndpoint
    public var serveCommand: [String]
    public var certificateProbeCommand: [String]?

    public init(
        endpoint: DirectModeEndpoint,
        serveCommand: [String],
        certificateProbeCommand: [String]? = nil
    ) {
        self.endpoint = endpoint
        self.serveCommand = serveCommand
        self.certificateProbeCommand = certificateProbeCommand
    }
}

public enum DirectModeExposureError: Error, Equatable, Sendable {
    case invalidLoopbackPort(UInt16)
    case hostRequired(DirectModeExposureTransport)
    case invalidHost(String)
    case unsupportedTransport(DirectModeExposureTransport)
}

public extension DirectModeExposureTransport {
    var connectionMode: ConnectionMode {
        switch self {
        case .tailscaleHTTPS, .tailnetHTTP:
            return .tailscaleDirect
        case .loopback:
            return .loopback
        }
    }
}

public protocol ExposureProvider: Sendable {
    func plan(_ request: DirectModeExposureRequest) throws -> DirectModeExposurePlan
}

public struct LoopbackExposureProvider: ExposureProvider {
    public init() {}

    public func plan(_ request: DirectModeExposureRequest) throws -> DirectModeExposurePlan {
        guard request.transport == .loopback else {
            throw DirectModeExposureError.unsupportedTransport(request.transport)
        }
        try Self.validate(loopbackPort: request.loopbackPort)
        let baseURL = "http://127.0.0.1:\(request.loopbackPort)"
        return DirectModeExposurePlan(
            endpoint: DirectModeEndpoint(
                baseURL: baseURL,
                commandURL: Self.commandURL(baseURL: baseURL),
                transport: .loopback,
                atsExceptionRequired: false
            ),
            serveCommand: []
        )
    }

    private static func validate(loopbackPort: UInt16) throws {
        guard loopbackPort > 0 else {
            throw DirectModeExposureError.invalidLoopbackPort(loopbackPort)
        }
    }

    private static func commandURL(baseURL: String) -> String {
        TailscaleExposureProvider.commandURL(baseURL: baseURL)
    }
}

public struct TailscaleExposureProvider: ExposureProvider {
    public init() {}

    public func plan(_ request: DirectModeExposureRequest) throws -> DirectModeExposurePlan {
        try validate(loopbackPort: request.loopbackPort)
        guard request.transport != .loopback else {
            throw DirectModeExposureError.unsupportedTransport(.loopback)
        }
        let host = try normalizedHost(request.host, transport: request.transport)
        let target = "http://127.0.0.1:\(request.loopbackPort)"

        switch request.transport {
        case .tailscaleHTTPS:
            let baseURL = "https://\(host)"
            return DirectModeExposurePlan(
                endpoint: DirectModeEndpoint(
                    baseURL: baseURL,
                    commandURL: Self.commandURL(baseURL: baseURL),
                    transport: .tailscaleHTTPS,
                    atsExceptionRequired: false
                ),
                serveCommand: ["tailscale", "serve", "--bg", "--https=443", target],
                certificateProbeCommand: ["tailscale", "cert", host]
            )
        case .tailnetHTTP:
            let baseURL = "http://\(host)"
            return DirectModeExposurePlan(
                endpoint: DirectModeEndpoint(
                    baseURL: baseURL,
                    commandURL: Self.commandURL(baseURL: baseURL),
                    transport: .tailnetHTTP,
                    atsExceptionRequired: true
                ),
                serveCommand: ["tailscale", "serve", "--bg", "--http=80", target],
                certificateProbeCommand: nil
            )
        case .loopback:
            throw DirectModeExposureError.unsupportedTransport(.loopback)
        }
    }

    fileprivate static func commandURL(baseURL: String) -> String {
        DirectModeEndpoint.routeURL(baseURL: baseURL, path: DirectModeCommandServer.commandPath)
    }

    private func validate(loopbackPort: UInt16) throws {
        guard loopbackPort > 0 else {
            throw DirectModeExposureError.invalidLoopbackPort(loopbackPort)
        }
    }

    private func normalizedHost(
        _ host: String?,
        transport: DirectModeExposureTransport
    ) throws -> String {
        guard let host else {
            throw DirectModeExposureError.hostRequired(transport)
        }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DirectModeExposureError.hostRequired(transport)
        }
        guard !trimmed.contains("://"),
              !trimmed.contains("/"),
              !trimmed.contains("?"),
              !trimmed.contains("#") else {
            throw DirectModeExposureError.invalidHost(host)
        }
        return trimmed
    }
}

public enum DirectModeReadinessKind: String, Codable, Sendable, CaseIterable {
    case ready
    case loopbackOnly
    case tailnetHTTPFallback
    case tailscaleUnavailable
    case httpsCertificateUnavailable
}

public struct DirectModeReadiness: Equatable, Sendable {
    public var kind: DirectModeReadinessKind
    public var ok: Bool
    public var checkedCommand: [String]?
    public var detail: String?
    public var nextAction: String?

    public init(
        kind: DirectModeReadinessKind,
        ok: Bool,
        checkedCommand: [String]? = nil,
        detail: String? = nil,
        nextAction: String? = nil
    ) {
        self.kind = kind
        self.ok = ok
        self.checkedCommand = checkedCommand
        self.detail = detail.map(Self.capped)
        self.nextAction = nextAction
    }

    private static func capped(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }
}

public struct DirectModeReadinessChecker: Sendable {
    private let commandRunner: any CommandRunner
    private let timeout: Duration

    public init(
        commandRunner: any CommandRunner,
        timeout: Duration = .seconds(5)
    ) {
        self.commandRunner = commandRunner
        self.timeout = timeout
    }

    public func check(_ plan: DirectModeExposurePlan) async -> DirectModeReadiness {
        switch plan.endpoint.transport {
        case .loopback:
            return DirectModeReadiness(kind: .loopbackOnly, ok: true)
        case .tailnetHTTP:
            return DirectModeReadiness(
                kind: .tailnetHTTPFallback,
                ok: true,
                nextAction: "iOS must allow the tailnet HTTP ATS exception before using this fallback."
            )
        case .tailscaleHTTPS:
            break
        }

        guard let command = plan.certificateProbeCommand,
              let executable = command.first else {
            return DirectModeReadiness(
                kind: .httpsCertificateUnavailable,
                ok: false,
                checkedCommand: plan.certificateProbeCommand,
                nextAction: "Enable HTTPS certificates in Tailscale, then re-run the Direct Mode check."
            )
        }

        let args = Array(command.dropFirst())
        let result = await commandRunner.run(
            command: executable,
            args: args,
            stdin: nil,
            env: [:],
            workingDirectory: AllnighterPaths.ensuredProbeScratchPath(),
            timeout: timeout
        )

        if let launchError = result.launchError {
            return DirectModeReadiness(
                kind: .tailscaleUnavailable,
                ok: false,
                checkedCommand: command,
                detail: launchError,
                nextAction: "Install Tailscale, sign in, then re-run the Direct Mode check."
            )
        }

        guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
            return DirectModeReadiness(
                kind: .httpsCertificateUnavailable,
                ok: false,
                checkedCommand: command,
                detail: diagnostic(from: result),
                nextAction: "Enable HTTPS certificates in the Tailscale admin console, then run `tailscale cert` again."
            )
        }

        return DirectModeReadiness(
            kind: .ready,
            ok: true,
            checkedCommand: command,
            detail: diagnostic(from: result)
        )
    }

    private func diagnostic(from result: CommandResult) -> String? {
        let parts = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

public enum DirectModeActivationKind: String, Codable, Sendable, CaseIterable {
    case activated
    case loopbackOnly
    case serveFailed
    case tailscaleUnavailable
}

public struct DirectModeActivationResult: Equatable, Sendable {
    public var kind: DirectModeActivationKind
    public var ok: Bool
    public var endpoint: DirectModeEndpoint
    public var checkedCommand: [String]?
    public var detail: String?
    public var nextAction: String?

    public init(
        kind: DirectModeActivationKind,
        ok: Bool,
        endpoint: DirectModeEndpoint,
        checkedCommand: [String]? = nil,
        detail: String? = nil,
        nextAction: String? = nil
    ) {
        self.kind = kind
        self.ok = ok
        self.endpoint = endpoint
        self.checkedCommand = checkedCommand
        self.detail = detail.map(Self.capped)
        self.nextAction = nextAction
    }

    private static func capped(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }
}

public struct DirectModeExposureActivator: Sendable {
    private let commandRunner: any CommandRunner
    private let timeout: Duration

    public init(
        commandRunner: any CommandRunner,
        timeout: Duration = .seconds(10)
    ) {
        self.commandRunner = commandRunner
        self.timeout = timeout
    }

    public func activate(_ plan: DirectModeExposurePlan) async -> DirectModeActivationResult {
        guard !plan.serveCommand.isEmpty else {
            return DirectModeActivationResult(
                kind: .loopbackOnly,
                ok: true,
                endpoint: plan.endpoint
            )
        }
        guard let executable = plan.serveCommand.first else {
            return DirectModeActivationResult(
                kind: .serveFailed,
                ok: false,
                endpoint: plan.endpoint,
                checkedCommand: plan.serveCommand,
                nextAction: "Recreate the Direct Mode exposure plan, then retry."
            )
        }

        let args = Array(plan.serveCommand.dropFirst())
        let result = await commandRunner.run(
            command: executable,
            args: args,
            stdin: nil,
            env: [:],
            workingDirectory: AllnighterPaths.ensuredProbeScratchPath(),
            timeout: timeout
        )

        if let launchError = result.launchError {
            return DirectModeActivationResult(
                kind: .tailscaleUnavailable,
                ok: false,
                endpoint: plan.endpoint,
                checkedCommand: plan.serveCommand,
                detail: launchError,
                nextAction: "Install Tailscale, sign in, then retry Direct Mode exposure."
            )
        }

        guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
            return DirectModeActivationResult(
                kind: .serveFailed,
                ok: false,
                endpoint: plan.endpoint,
                checkedCommand: plan.serveCommand,
                detail: diagnostic(from: result),
                nextAction: "Check Tailscale Serve status, then retry Direct Mode exposure."
            )
        }

        return DirectModeActivationResult(
            kind: .activated,
            ok: true,
            endpoint: plan.endpoint,
            checkedCommand: plan.serveCommand,
            detail: diagnostic(from: result)
        )
    }

    private func diagnostic(from result: CommandResult) -> String? {
        let parts = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
