import Foundation
import AllnighterCore
import AllnighterEngine

enum PairCLI {
    static func run(_ args: [String], runtime: ToolRuntime, store: TrustedRemoteStore = TrustedRemoteStore()) {
        guard let sub = args.first else {
            runList([], store: store)
            return
        }
        switch sub {
        case "list": runList(Array(args.dropFirst()), store: store)
        case "approve": runApprove(Array(args.dropFirst()), store: store)
        case "revoke": runRevoke(Array(args.dropFirst()), store: store)
        default: usage()
        }
    }

    static func listJSON(store: TrustedRemoteStore, now: Date = Date()) -> TrustedRemoteListJSON {
        let registry = store.list(now: now)
        return TrustedRemoteListJSON(
            contractVersion: ContractRegistry.contractVersion,
            pendingRequests: registry.pendingRequests,
            trustedDevices: registry.trustedDevices
        )
    }

    private static func runList(_ args: [String], store: TrustedRemoteStore) {
        let opts = Options(args)
        let payload = listJSON(store: store)
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

    private static func usage(_ detail: String = "list|approve|revoke") -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
