import Foundation

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
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(trimmed)\(DirectModeCommandServer.commandPath)"
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
