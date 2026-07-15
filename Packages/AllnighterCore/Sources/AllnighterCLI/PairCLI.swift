import Foundation
import AllnighterCore
import AllnighterEngine

enum PairCLI {
    static func run(
        _ args: [String],
        runtime: ToolRuntime,
        store: TrustedRemoteStore = TrustedRemoteStore(),
        directSessionStore: DirectModePairingSessionStore = DirectModePairingSessionStore()
    ) async {
        guard let sub = args.first else {
            runList([], store: store)
            return
        }
        switch sub {
        case "list": runList(Array(args.dropFirst()), store: store)
        case "approve": runApprove(Array(args.dropFirst()), store: store)
        case "revoke": runRevoke(Array(args.dropFirst()), store: store)
        case "begin": runBegin(Array(args.dropFirst()), sessionStore: directSessionStore)
        case "slice": await PairProgrammingCLI.runSlice(Array(args.dropFirst()), runtime: runtime)
        case "run": await PairProgrammingCLI.runQueue(Array(args.dropFirst()), runtime: runtime)
        case "status": await PairProgrammingCLI.runStatus(Array(args.dropFirst()), runtime: runtime)
        case "relay": await RelayCLI.runRelay(Array(args.dropFirst()), runtime: runtime)
        case "relay-status": RelayCLI.runStatus(Array(args.dropFirst()))
        case "relay-resume": await RelayCLI.runResume(Array(args.dropFirst()), runtime: runtime)
        default: usage("list|approve|revoke|begin|slice|run|status|relay|relay-status|relay-resume")
        }
    }

    static func listJSON(store: TrustedRemoteStore, now: Date = Date()) throws -> TrustedRemoteListJSON {
        let registry = try store.list(now: now)
        return TrustedRemoteListJSON(
            contractVersion: ContractRegistry.contractVersion,
            pendingRequests: registry.pendingRequests,
            trustedDevices: registry.trustedDevices
        )
    }

    private static func runList(_ args: [String], store: TrustedRemoteStore) {
        let opts = Options(args)
        let payload: TrustedRemoteListJSON
        do {
            payload = try listJSON(store: store)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error.localizedDescription)
        }
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
            return
        }

        print("Pending requests")
        if payload.pendingRequests.isEmpty {
            print("  (none)")
        } else {
            for request in payload.pendingRequests {
                print("  \(request.deviceId)\t\(request.displayName)\t\(request.status.rawValue)\texpires \(iso(request.expiresAt))")
            }
        }

        print("\nTrusted devices")
        if payload.trustedDevices.isEmpty {
            print("  (none)")
        } else {
            for device in payload.trustedDevices {
                let status = device.revoked ? "revoked" : "trusted"
                print("  \(device.deviceId)\t\(device.displayName)\t\(status)\tvalidUntil \(iso(device.validUntil))")
            }
        }
    }

    private static func runApprove(_ args: [String], store: TrustedRemoteStore) {
        let opts = Options(args)
        guard let deviceId = opts.positional.first else {
            usage("approve <deviceId> [--json]")
        }
        do {
            let device = try store.approve(deviceId: deviceId)
            let payload = TrustedRemoteMutationJSON(
                contractVersion: ContractRegistry.contractVersion,
                device: device
            )
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(payload))
            } else {
                print("approved \(device.displayName) (\(device.deviceId))")
            }
        } catch let error as TrustedRemoteStoreError {
            emitStoreError(error)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error.localizedDescription)
        }
    }

    private static func runRevoke(_ args: [String], store: TrustedRemoteStore) {
        let opts = Options(args)
        guard let deviceId = opts.positional.first else {
            usage("revoke <deviceId> [--json]")
        }
        do {
            let device = try store.revoke(deviceId: deviceId)
            let payload = TrustedRemoteMutationJSON(
                contractVersion: ContractRegistry.contractVersion,
                device: device
            )
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(payload))
            } else {
                print("revoked \(device.displayName) (\(device.deviceId))")
            }
        } catch let error as TrustedRemoteStoreError {
            emitStoreError(error)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error.localizedDescription)
        }
    }

    static func beginJSON(
        _ args: [String],
        sessionStore: DirectModePairingSessionStore,
        now: @escaping @Sendable () -> Date = Date.init,
        tokenFactory: @escaping @Sendable () -> String = DirectModePairingBeginService.randomPairingToken,
        manualCodeFactory: @escaping @Sendable () -> String = DirectModePairingBeginService.randomManualCode
    ) throws -> DirectModePairingBeginJSON {
        let opts = Options(args)
        let transport = try beginTransport(opts.value("transport"))
        let port = try beginPort(opts.value("port"))
        let plan = try exposureProvider(for: transport).plan(DirectModeExposureRequest(
            loopbackPort: port,
            transport: transport,
            host: opts.value("host")
        ))
        guard let agentSigningPubkey = opts.value("agent-signing-pubkey") else {
            throw PairCLIError.missingRequired("--agent-signing-pubkey")
        }
        guard let agentSealingPubkey = opts.value("agent-sealing-pubkey") else {
            throw PairCLIError.missingRequired("--agent-sealing-pubkey")
        }
        let ttlSeconds = try beginTTL(opts.value("ttl-seconds"))
        let maxFailedAttempts = try beginMaxFailedAttempts(opts.value("max-failed-attempts"))
        let linkBase = try beginLinkBase(opts.value("link-base"))
        let service = DirectModePairingBeginService(
            sessionStore: sessionStore,
            now: now,
            tokenFactory: tokenFactory,
            manualCodeFactory: manualCodeFactory
        )
        return try service.begin(DirectModePairingBeginRequest(
            exposurePlan: plan,
            agentSigningPubkey: agentSigningPubkey,
            agentSealingPubkey: agentSealingPubkey,
            tailnetName: opts.value("tailnet"),
            ttlSeconds: ttlSeconds,
            maxFailedAttempts: maxFailedAttempts,
            universalLinkBase: linkBase
        )).json(contractVersion: ContractRegistry.contractVersion)
    }

    private static func runBegin(_ args: [String], sessionStore: DirectModePairingSessionStore) {
        let opts = Options(args)
        do {
            let payload = try beginJSON(args, sessionStore: sessionStore)
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(payload))
                return
            }

            print("Direct Mode pairing armed until \(iso(payload.expiresAt))")
            if let link = payload.pairingLink {
                print("Pairing link: \(link)")
            }
            print("Manual code: \(payload.manualCode)")
            if !payload.serveCommand.isEmpty {
                print("Expose command: \(payload.serveCommand.joined(separator: " "))")
            }
            if let certificateProbeCommand = payload.certificateProbeCommand {
                print("Readiness check: \(certificateProbeCommand.joined(separator: " "))")
            }
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: String(describing: error))
        }
    }

    private static func emitStoreError(_ error: TrustedRemoteStoreError) -> Never {
        switch error {
        case .pairRequestNotFound(let deviceId):
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "no pending pair request for \(deviceId)")
        case .pairRequestExpired(let deviceId):
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "pair request expired for \(deviceId)")
        case .trustedDeviceNotFound(let deviceId):
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "no trusted device for \(deviceId)")
        }
    }

    private static func usage(_ detail: String = "list|approve|revoke|begin|slice|run|status|relay|relay-status|relay-resume") -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func beginTransport(_ raw: String?) throws -> DirectModeExposureTransport {
        guard let raw else { return .loopback }
        guard let transport = DirectModeExposureTransport(rawValue: raw) else {
            throw PairCLIError.invalidValue("--transport", raw)
        }
        return transport
    }

    private static func beginPort(_ raw: String?) throws -> UInt16 {
        guard let raw else { return 42123 }
        guard let value = UInt16(raw), value > 0 else {
            throw PairCLIError.invalidValue("--port", raw)
        }
        return value
    }

    private static func beginTTL(_ raw: String?) throws -> TimeInterval {
        guard let raw else { return 5 * 60 }
        guard let value = TimeInterval(raw), value.isFinite, value > 0 else {
            throw PairCLIError.invalidValue("--ttl-seconds", raw)
        }
        return value
    }

    private static func beginMaxFailedAttempts(_ raw: String?) throws -> Int {
        guard let raw else { return 5 }
        guard let value = Int(raw), value > 0 else {
            throw PairCLIError.invalidValue("--max-failed-attempts", raw)
        }
        return value
    }

    private static func beginLinkBase(_ raw: String?) throws -> URL? {
        guard let raw else { return nil }
        guard let url = URL(string: raw) else {
            throw PairCLIError.invalidValue("--link-base", raw)
        }
        return url
    }

    private static func exposureProvider(for transport: DirectModeExposureTransport) -> any ExposureProvider {
        switch transport {
        case .loopback:
            return LoopbackExposureProvider()
        case .tailscaleHTTPS, .tailnetHTTP:
            return TailscaleExposureProvider()
        }
    }
}

private enum PairCLIError: Error, Equatable {
    case missingRequired(String)
    case invalidValue(String, String)
}
