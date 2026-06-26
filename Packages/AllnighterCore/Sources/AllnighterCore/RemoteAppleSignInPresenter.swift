#if canImport(AuthenticationServices) && (os(iOS) || os(macOS))
import AuthenticationServices
import CryptoKit
import Foundation

public enum RemoteAppleSignInError: Error, Equatable, Sendable {
    case cancelled
    case missingIdentityToken
    case missingPublicConfig
    case claimsProvisioningFailed(String)
}

public enum RemoteSignInRole: Sendable {
    case macAgent(macAgentId: String, displayName: String)
    case device(deviceId: String, displayName: String)
}

@MainActor
public final class RemoteAppleSignInPresenter: NSObject {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    public override init() {}

    public func requestCredential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let nonce = Self.randomNonce()
            let hashedNonce = Self.sha256(nonce)
            self.pendingNonce = nonce

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private var pendingNonce: String?

    public func consumeNonce() -> String? {
        defer { pendingNonce = nil }
        return pendingNonce
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset.randomElement()!)
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

extension RemoteAppleSignInPresenter: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: RemoteAppleSignInError.missingIdentityToken)
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            continuation?.resume(throwing: RemoteAppleSignInError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

extension RemoteAppleSignInPresenter: ASAuthorizationControllerPresentationContextProviding {
    #if os(iOS)
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
    #elseif os(macOS)
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
    #endif
}

public enum RemoteAppleSignInService {
    @MainActor
    public static func signIn(
        presenter: RemoteAppleSignInPresenter,
        publicConfig: RemoteSupabasePublicConfig.Values,
        role: RemoteSignInRole,
        sessionStore: RemoteSupabaseSessionStore = RemoteSupabaseSessionStore(),
        authClient: RemoteSupabaseAuthClient? = nil
    ) async throws -> RemoteSupabaseSession {
        let credential = try await presenter.requestCredential()
        guard let nonce = presenter.consumeNonce() else {
            throw RemoteAppleSignInError.missingIdentityToken
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw RemoteAppleSignInError.missingIdentityToken
        }

        let client = authClient ?? RemoteSupabaseAuthClient(
            supabaseURL: publicConfig.supabaseURL,
            publishableKey: publicConfig.publishableKey
        )
        var session = try await client.signInWithApple(idToken: idToken, nonce: nonce)

        switch role {
        case let .macAgent(macAgentId, _):
            session = try await RemoteAuthClaimsProvisioner.provisionMacAgent(
                session: session,
                macAgentId: macAgentId,
                publicConfig: publicConfig,
                authClient: client
            )
        case let .device(deviceId, _):
            session = try await RemoteAuthClaimsProvisioner.provisionDevice(
                session: session,
                deviceId: deviceId,
                publicConfig: publicConfig,
                authClient: client
            )
        }

        try sessionStore.save(session)
        return session
    }
}
#endif

#if canImport(AuthenticationServices) && os(iOS)
import UIKit
#endif

#if canImport(AuthenticationServices) && os(macOS)
import AppKit
#endif
