import AllnighterCore
import AllnighterEngine
import Foundation
import Observation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

@MainActor
@Observable
final class RemoteAccountModel {
    private(set) var isSignedIn = false
    private(set) var accountLabel: String?
    private(set) var statusLine: String?
    private(set) var pendingPairingRequests: [RemotePairRequest] = []
    private(set) var relayState: RemoteRelayLaunchState = .idle

    private let sessionStore = RemoteSupabaseSessionStore()
    private let macCredentialStore = RemoteMacAgentCredentialStore()
    private let trustedStore = TrustedRemoteStore()
    #if canImport(AuthenticationServices)
    private let appleSignInPresenter = RemoteAppleSignInPresenter()
    #endif
    private var refreshTask: Task<Void, Never>?
    private var relayTask: Task<Void, Never>?

    func bootstrap() async {
        // Process-quiet launch (Launch Authority TCC): a persisted session is
        // prior intent, not consent to spawn a bash/swift/serve tree under the
        // Dock app's TCC identity on every open. Refresh account + pairing
        // state only; relay start is explicit (sign-in or Settings).
        refreshSignedInState()
        guard isSignedIn else { return }
        await refreshPendingPairingRequests()
    }

    func signInWithApple() async {
        guard let publicConfig = RemoteSupabasePublicConfig.load() else {
            statusLine = "Remote relay is not configured — ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY is missing from this build."
            return
        }

        statusLine = "Signing in…"
        do {
            let macAgentId = try existingOrNewMacAgentId()
            let displayName = Host.current().localizedName ?? "My Mac"
            #if canImport(AuthenticationServices)
            let session = try await RemoteAppleSignInService.signIn(
                presenter: appleSignInPresenter,
                publicConfig: publicConfig,
                role: .macAgent(macAgentId: macAgentId, displayName: displayName),
                sessionStore: sessionStore
            )
            try saveMacCredentials(
                accountId: session.userId,
                macAgentId: macAgentId,
                displayName: displayName,
                provider: session.provider
            )
            refreshSignedInState()
            statusLine = "Signed in. Starting remote relay…"
            await refreshPendingPairingRequests()
            await ensureRelayRunning()
            #else
            statusLine = "Sign in with Apple is unavailable on this platform."
            #endif
        } catch RemoteAppleSignInError.cancelled {
            statusLine = nil
        } catch {
            statusLine = signInFailureMessage(for: error)
        }
    }

    func approvePairing(deviceId: String) async {
        do {
            _ = try trustedStore.approve(deviceId: deviceId)
            await refreshPendingPairingRequests()
            statusLine = "Approved this iPhone."
        } catch {
            statusLine = "Could not approve this device."
        }
    }

    func signOut() async {
        refreshTask?.cancel()
        relayTask?.cancel()
        relayTask = nil
        try? sessionStore.clear()
        isSignedIn = false
        accountLabel = nil
        pendingPairingRequests = []
        relayState = .idle
        statusLine = nil
        RemoteMacRelayLauncher.stopIfRunning()
    }

    private func refreshSignedInState() {
        isSignedIn = (try? sessionStore.load()) != nil
        accountLabel = isSignedIn ? "Apple account connected" : nil
    }

    private func refreshPendingPairingRequests() async {
        do {
            let registry = try trustedStore.list()
            pendingPairingRequests = registry.pendingRequests.filter {
                $0.status == .pending
            }
        } catch {
            pendingPairingRequests = []
        }
    }

    private func ensureRelayRunning() async {
        relayState = .starting
        relayTask?.cancel()
        relayTask = Task {
            let result = await RemoteMacRelayLauncher.ensureRunning()
            await MainActor.run {
                relayState = result
                if case .running = result {
                    statusLine = "Remote relay is active on this Mac."
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await refreshPendingPairingRequests()
            }
        }
    }

    private func existingOrNewMacAgentId() throws -> String {
        if let existing = try macCredentialStore.load() {
            return existing.macAgentId
        }
        return UUID().uuidString.lowercased()
    }

    private func saveMacCredentials(
        accountId: String,
        macAgentId: String,
        displayName: String,
        provider: RemoteAccountSession.Provider
    ) throws {
        if let existing = try macCredentialStore.load(),
           existing.accountId == accountId,
           existing.macAgentId == macAgentId {
            return
        }
        let keys = RemoteStoredKeyPair.generate()
        try macCredentialStore.save(RemoteMacAgentCredentials(
            macAgentId: macAgentId,
            displayName: displayName,
            accountId: accountId,
            accountProvider: provider,
            keys: keys.material
        ))
    }

    private func signInFailureMessage(for error: Error) -> String {
        if let authError = error as? RemoteSupabaseAuthError {
            switch authError {
            case .http(let statusCode, _):
                if statusCode == 400 || statusCode == 401 {
                    return "Apple sign-in is not enabled yet. Confirm Supabase Apple auth is configured."
                }
                return "Could not sign in (\(statusCode))."
            default:
                return "Could not sign in."
            }
        }
        return error.localizedDescription
    }
}

enum RemoteRelayLaunchState: Equatable {
    case idle
    case starting
    case running
    case failed(String)
}
