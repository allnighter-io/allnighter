import CryptoKit
import Foundation
import AllnighterCore

public enum DirectModePairingSessionStoreError: Error, Equatable, Sendable {
    case expiredPayload
    case invalidPairingToken
    case invalidManualCode
    case manualCodeUnavailable
    case sessionExpired(String)
    case sessionConsumed(String)
    case sessionLockedOut(String)
}

public final class DirectModePairingSessionStore: @unchecked Sendable {
    public let fileURL: URL

    private let fileManager: FileManager
    private let idFactory: @Sendable () -> String

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        idFactory: @escaping @Sendable () -> String = {
            "direct_pair_\(UUID().uuidString.lowercased())"
        }
    ) {
        self.fileURL = fileURL ?? AllnighterPaths.config
            .appendingPathComponent("Remote", isDirectory: true)
            .appendingPathComponent("direct_pairing_sessions.json")
        self.fileManager = fileManager
        self.idFactory = idFactory
    }

    public func load() -> DirectModePairingRegistry {
        guard let data = try? Data(contentsOf: fileURL),
              let registry = try? CoreJSON.decode(DirectModePairingRegistry.self, from: data) else {
            return DirectModePairingRegistry()
        }
        return registry
    }

    @discardableResult
    public func save(_ registry: DirectModePairingRegistry) throws -> URL {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CoreJSON.encode(registry).write(to: fileURL, options: .atomic)
        return fileURL
    }

    @discardableResult
    public func arm(
        payload: RemotePairingPayload,
        manualCode: String? = nil,
        now: Date = Date(),
        maxFailedAttempts: Int = 5,
        replaceActive: Bool = true
    ) throws -> DirectModePairingSession {
        guard !payload.isExpired(at: now) else {
            throw DirectModePairingSessionStoreError.expiredPayload
        }
        let pairingToken = payload.pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pairingToken.isEmpty else {
            throw DirectModePairingSessionStoreError.invalidPairingToken
        }
        let normalizedManualCode: String?
        if let manualCode {
            guard let normalized = Self.normalizeManualCode(manualCode) else {
                throw DirectModePairingSessionStoreError.invalidManualCode
            }
            normalizedManualCode = normalized
        } else {
            normalizedManualCode = nil
        }

        var registry = load()
        expireSessions(in: &registry, now: now)
        if replaceActive {
            for index in registry.sessions.indices where registry.sessions[index].isArmed(at: now) {
                registry.sessions[index].status = .expired
            }
        }

        let session = DirectModePairingSession(
            id: idFactory(),
            endpoints: payload.endpoints,
            agentSigningPubkey: payload.agentSigningPubkey,
            agentSealingPubkey: payload.agentSealingPubkey,
            tailnetName: payload.tailnetName,
            protocolVersion: payload.protocolVersion,
            pairingTokenSHA256: Self.sha256Hex(pairingToken),
            manualCodeSHA256: normalizedManualCode.map(Self.sha256Hex),
            createdAt: now,
            expiresAt: payload.expiresAt,
            maxFailedAttempts: max(1, maxFailedAttempts)
        )
        registry.sessions.append(session)
        registry.sessions.sort {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt < $1.createdAt
        }
        try save(registry)
        return session
    }

    public func active(now: Date = Date()) -> [DirectModePairingSession] {
        var registry = load()
        expireSessions(in: &registry, now: now)
        return registry.sessions.filter { $0.isArmed(at: now) }
    }

    @discardableResult
    public func consume(
        pairingToken: String,
        now: Date = Date()
    ) throws -> DirectModePairingSession {
        let token = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw DirectModePairingSessionStoreError.invalidPairingToken
        }
        return try consume(digest: Self.sha256Hex(token), kind: .pairingToken, now: now)
    }

    @discardableResult
    public func consume(
        manualCode: String,
        now: Date = Date()
    ) throws -> DirectModePairingSession {
        guard let normalized = Self.normalizeManualCode(manualCode) else {
            throw DirectModePairingSessionStoreError.invalidManualCode
        }
        return try consume(digest: Self.sha256Hex(normalized), kind: .manualCode, now: now)
    }

    private enum AttemptKind {
        case pairingToken
        case manualCode
    }

    private func consume(
        digest: String,
        kind: AttemptKind,
        now: Date
    ) throws -> DirectModePairingSession {
        var registry = load()
        expireSessions(in: &registry, now: now)

        if kind == .manualCode && !registry.sessions.contains(where: { $0.manualCodeSHA256 != nil }) {
            try save(registry)
            throw DirectModePairingSessionStoreError.manualCodeUnavailable
        }

        if let index = registry.sessions.firstIndex(where: { session in
            switch kind {
            case .pairingToken:
                return session.pairingTokenSHA256 == digest
            case .manualCode:
                return session.manualCodeSHA256 == digest
            }
        }) {
            switch registry.sessions[index].status {
            case .armed:
                guard !registry.sessions[index].isExpired(at: now) else {
                    registry.sessions[index].status = .expired
                    try save(registry)
                    throw DirectModePairingSessionStoreError.sessionExpired(registry.sessions[index].id)
                }
                registry.sessions[index].status = .consumed
                registry.sessions[index].consumedAt = now
                try save(registry)
                return registry.sessions[index]
            case .consumed:
                try save(registry)
                throw DirectModePairingSessionStoreError.sessionConsumed(registry.sessions[index].id)
            case .expired:
                try save(registry)
                throw DirectModePairingSessionStoreError.sessionExpired(registry.sessions[index].id)
            case .lockedOut:
                try save(registry)
                throw DirectModePairingSessionStoreError.sessionLockedOut(registry.sessions[index].id)
            }
        }

        recordFailedAttempt(in: &registry, now: now)
        try save(registry)
        switch kind {
        case .pairingToken:
            throw DirectModePairingSessionStoreError.invalidPairingToken
        case .manualCode:
            throw DirectModePairingSessionStoreError.invalidManualCode
        }
    }

    private func expireSessions(in registry: inout DirectModePairingRegistry, now: Date) {
        for index in registry.sessions.indices
            where registry.sessions[index].status == .armed
                && registry.sessions[index].isExpired(at: now) {
            registry.sessions[index].status = .expired
        }
    }

    private func recordFailedAttempt(in registry: inout DirectModePairingRegistry, now: Date) {
        for index in registry.sessions.indices where registry.sessions[index].isArmed(at: now) {
            registry.sessions[index].failedAttempts += 1
            if registry.sessions[index].failedAttempts >= registry.sessions[index].maxFailedAttempts {
                registry.sessions[index].status = .lockedOut
                registry.sessions[index].lockedOutAt = now
            }
        }
    }

    private static func normalizeManualCode(_ value: String) -> String? {
        let digits = value.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
        guard digits.count == 6 else { return nil }
        return digits
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
