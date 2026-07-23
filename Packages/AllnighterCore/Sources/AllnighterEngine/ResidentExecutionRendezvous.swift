#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Security
import AllnighterCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Hardened, same-user file rendezvous between a restricted foreground client
/// and the unsandboxed resident coordinator. The directory is intentionally in
/// the per-user temporary area, not Application Support: Codex may write the
/// former but not the latter. It carries only typed, HMAC-authenticated broker
/// messages; vendor credentials never enter this transport.
public final class ResidentExecutionRendezvous: @unchecked Sendable {
    public static let maximumRequestBytes = 1_048_576

    public struct Identity: Codable, Equatable, Sendable {
        public var coordinatorId: String
        public var nonce: String
        public var binaryVersion: String
        public var contractVersion: String

        public init(coordinatorId: String, nonce: String, binaryVersion: String, contractVersion: String) {
            self.coordinatorId = coordinatorId
            self.nonce = nonce
            self.binaryVersion = binaryVersion
            self.contractVersion = contractVersion
        }
    }

    public struct Claim: Equatable, Sendable {
        public var request: ResidentExecutionRequest
        public var fileURL: URL
    }

    public let root: URL
    private let fileManager: FileManager

    public init(root: URL? = nil, fileManager: FileManager = .default) {
        self.root = root ?? Self.defaultRoot()
        self.fileManager = fileManager
    }

    public var inbox: URL { root.appendingPathComponent("inbox", isDirectory: true) }
    public var claimed: URL { root.appendingPathComponent("claimed", isDirectory: true) }
    public var receipts: URL { root.appendingPathComponent("receipts", isDirectory: true) }
    public var acceptance: URL { root.appendingPathComponent("acceptance", isDirectory: true) }
    private var identityFile: URL { root.appendingPathComponent("identity.json") }
    private var secretFile: URL { root.appendingPathComponent("client-proof.key") }

    /// Coordinator-only bootstrap. Existing hostile, symlinked, wrong-owner, or
    /// group/world-readable paths fail closed rather than being adopted.
    @discardableResult
    public func prepareCoordinator(
        coordinatorId: String,
        binaryVersion: String,
        contractVersion: String,
        nonce: String = UUID().uuidString.lowercased()
    ) throws -> Identity {
        try ensureDirectory(root)
        try ensureDirectory(inbox)
        try ensureDirectory(claimed)
        try ensureDirectory(receipts)
        try ensureDirectory(acceptance)
        _ = try loadOrCreateSecret()
        let identity = Identity(
            coordinatorId: coordinatorId,
            nonce: nonce,
            binaryVersion: binaryVersion,
            contractVersion: contractVersion
        )
        try secureWrite(CoreJSON.encode(identity), to: identityFile, mode: 0o600, replace: true)
        return identity
    }

    public func currentIdentity() throws -> Identity {
        try validateExistingFile(identityFile, mode: 0o600)
        return try CoreJSON.decode(Identity.self, from: Data(contentsOf: identityFile))
    }

    public func isReady(
        coordinatorId: String,
        binaryVersion: String,
        contractVersion: String
    ) -> Bool {
        guard let identity = try? currentIdentity() else { return false }
        return identity.coordinatorId == coordinatorId
            && identity.binaryVersion == binaryVersion
            && identity.contractVersion == contractVersion
    }

    /// Coordinator shutdown makes the endpoint unavailable without deleting the
    /// per-install secret. The next legitimate coordinator bootstrap reuses the
    /// secret and rotates the signed nonce.
    public func deactivateCoordinator() {
        try? fileManager.removeItem(at: identityFile)
    }

    /// Creates and atomically deposits one signed typed request. The return is
    /// only inbox delivery; durable acceptance is represented by a receipt.
    @discardableResult
    public func submit(
        operation: ResidentExecutionOperation,
        idempotencyKey: String,
        requestId: String = UUID().uuidString.lowercased(),
        submittedAt: Date = Date()
    ) throws -> ResidentExecutionRequest {
        try validateClientSurface()
        let identity = try currentIdentity()
        let unsigned = ResidentExecutionRequest(
            requestId: requestId,
            idempotencyKey: idempotencyKey,
            submittedAt: submittedAt,
            coordinatorId: identity.coordinatorId,
            coordinatorNonce: identity.nonce,
            operation: operation,
            clientProof: ResidentClientProof(signature: "")
        )
        var request = unsigned
        request.clientProof = ResidentClientProof(signature: try signature(for: unsigned, secret: loadSecret()))
        let data = try CoreJSON.encode(request)
        guard data.count <= Self.maximumRequestBytes else { throw Error.requestTooLarge(data.count) }
        try atomicCreate(data, at: inbox.appendingPathComponent("\(safeIdentifier(requestId)).json"), mode: 0o600)
        return request
    }

    /// Returns a claimed request for coordinator processing. Claimed work is
    /// scanned before inbox work, so a coordinator crash after claim but before
    /// acceptance is recoverable without client resubmission.
    public func claimNext() throws -> Claim? {
        try validateCoordinatorSurface()
        if let recovered = try firstRequest(in: claimed) {
            return try decodeClaim(at: recovered)
        }
        guard let incoming = try firstRequest(in: inbox) else { return nil }
        let destination = claimed.appendingPathComponent(incoming.lastPathComponent)
        if link(incoming.path, destination.path) != 0 {
            if errno == EEXIST { return try claimNext() }
            throw Error.claimFailed(errno)
        }
        try? fileManager.removeItem(at: incoming)
        return try decodeClaim(at: destination)
    }

    /// Records an acceptance atomically and implements same-key replay/conflict.
    /// The caller owns process creation only after this returns `.accepted`.
    public func accept(
        _ claim: Claim,
        canonicalId: String,
        result: ResidentExecutionResult? = nil,
        at date: Date = Date()
    ) throws -> ResidentExecutionReceipt {
        let digest = try payloadDigest(for: claim.request)
        let indexURL = acceptance.appendingPathComponent("\(digestKey(claim.request.idempotencyKey)).json")
        if fileManager.fileExists(atPath: indexURL.path) {
            let existing = try CoreJSON.decode(Acceptance.self, from: Data(contentsOf: indexURL))
            if existing.payloadDigest != digest { throw Error.idempotencyConflict }
            let receipt = try replay(existing.receipt, for: claim.request.requestId)
            complete(claim)
            return receipt
        }
        let receipt = ResidentExecutionReceipt(
            requestId: claim.request.requestId,
            canonicalId: canonicalId,
            state: .accepted,
            acceptedAt: date,
            result: result
        )
        let record = Acceptance(payloadDigest: digest, receipt: receipt)
        do {
            try atomicCreate(CoreJSON.encode(record), at: indexURL, mode: 0o600)
        } catch Error.destinationExists {
            let existing = try CoreJSON.decode(Acceptance.self, from: Data(contentsOf: indexURL))
            if existing.payloadDigest != digest { throw Error.idempotencyConflict }
            let receipt = try replay(existing.receipt, for: claim.request.requestId)
            complete(claim)
            return receipt
        }
        try recordReceipt(receipt)
        complete(claim)
        return receipt
    }

    public func reject(_ claim: Claim, code: String, message: String, at date: Date = Date()) throws {
        try recordReceipt(.init(
            requestId: claim.request.requestId,
            state: .rejected,
            acceptedAt: date,
            rejection: .init(code: code, message: message)
        ))
        complete(claim)
    }

    public func receipt(requestId: String) throws -> ResidentExecutionReceipt? {
        try validateClientSurface()
        let url = receipts.appendingPathComponent("\(safeIdentifier(requestId)).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try validateExistingFile(url, mode: 0o600)
        return try CoreJSON.decode(ResidentExecutionReceipt.self, from: Data(contentsOf: url))
    }

    public func waitForReceipt(
        requestId: String,
        timeout: TimeInterval = 10,
        pollNanoseconds: UInt64 = 100_000_000
    ) async throws -> ResidentExecutionReceipt? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let receipt = try receipt(requestId: requestId) { return receipt }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return try receipt(requestId: requestId)
    }

    public func verify(_ request: ResidentExecutionRequest) throws {
        let identity = try currentIdentity()
        guard request.schemaVersion == 1 else { throw Error.unsupportedSchema(request.schemaVersion) }
        guard request.coordinatorId == identity.coordinatorId,
              request.coordinatorNonce == identity.nonce else { throw Error.coordinatorMismatch }
        guard request.clientProof.keyId == "resident-v1" else { throw Error.invalidProof }
        let expected = try signature(for: request, secret: loadSecret())
        guard constantTimeEqual(expected, request.clientProof.signature) else { throw Error.invalidProof }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case unsafePath(String)
        case unavailable
        case invalidProof
        case coordinatorMismatch
        case unsupportedSchema(Int)
        case requestTooLarge(Int)
        case malformedRequest
        case claimFailed(Int32)
        case destinationExists
        case idempotencyConflict
    }

    private struct SigningPayload: Codable {
        var schemaVersion: Int
        var requestId: String
        var idempotencyKey: String
        var submittedAt: Date
        var coordinatorId: String
        var coordinatorNonce: String
        var operation: ResidentExecutionOperation

        init(_ request: ResidentExecutionRequest) {
            schemaVersion = request.schemaVersion
            requestId = request.requestId
            idempotencyKey = request.idempotencyKey
            submittedAt = request.submittedAt
            coordinatorId = request.coordinatorId
            coordinatorNonce = request.coordinatorNonce
            operation = request.operation
        }
    }

    private struct Acceptance: Codable {
        var payloadDigest: String
        var receipt: ResidentExecutionReceipt
    }

    /// Idempotency is scoped to the semantic operation, not its delivery
    /// envelope. A retry necessarily has a new request id and timestamp.
    private struct IdempotencyPayload: Codable {
        var schemaVersion: Int
        var operation: ResidentExecutionOperation

        init(_ request: ResidentExecutionRequest) {
            schemaVersion = request.schemaVersion
            operation = request.operation
        }
    }

    private static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_RENDEZVOUS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("allnighter-resident-\(getuid())", isDirectory: true)
    }

    private func validateClientSurface() throws {
        guard fileManager.fileExists(atPath: root.path) else { throw Error.unavailable }
        try validateDirectory(root)
        try validateDirectory(inbox)
        try validateDirectory(receipts)
    }

    private func validateCoordinatorSurface() throws {
        try validateClientSurface()
        try validateDirectory(claimed)
        try validateDirectory(acceptance)
    }

    private func ensureDirectory(_ url: URL) throws {
        if mkdir(url.path, 0o700) != 0 && errno != EEXIST { throw Error.unsafePath(url.path) }
        try validateDirectory(url)
    }

    private func validateDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0 else { throw Error.unsafePath(url.path) }
    }

    private func validateExistingFile(_ url: URL, mode: mode_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0,
              (info.st_mode & 0o777) == mode else { throw Error.unsafePath(url.path) }
    }

    private func loadOrCreateSecret() throws -> Data {
        if fileManager.fileExists(atPath: secretFile.path) { return try loadSecret() }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Error.unavailable
        }
        do {
            try atomicCreate(Data(bytes), at: secretFile, mode: 0o600)
        } catch Error.destinationExists {
            // A concurrent legitimate bootstrap won; validate its result.
        }
        return try loadSecret()
    }

    private func loadSecret() throws -> Data {
        try validateExistingFile(secretFile, mode: 0o600)
        let secret = try Data(contentsOf: secretFile)
        guard secret.count == 32 else { throw Error.unsafePath(secretFile.path) }
        return secret
    }

    private func firstRequest(in directory: URL) throws -> URL? {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.first
    }

    private func decodeClaim(at url: URL) throws -> Claim {
        try validateExistingFile(url, mode: 0o600)
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumRequestBytes else { throw Error.requestTooLarge(data.count) }
        guard let request = try? CoreJSON.decode(ResidentExecutionRequest.self, from: data) else {
            throw Error.malformedRequest
        }
        try verify(request)
        return Claim(request: request, fileURL: url)
    }

    private func recordReceipt(_ receipt: ResidentExecutionReceipt) throws {
        try atomicCreate(
            CoreJSON.encode(receipt),
            at: receipts.appendingPathComponent("\(safeIdentifier(receipt.requestId)).json"),
            mode: 0o600
        )
    }

    private func replay(_ accepted: ResidentExecutionReceipt, for requestId: String) throws -> ResidentExecutionReceipt {
        let receipt = ResidentExecutionReceipt(
            requestId: requestId,
            canonicalId: accepted.canonicalId,
            state: accepted.state,
            acceptedAt: accepted.acceptedAt,
            result: accepted.result,
            rejection: accepted.rejection
        )
        try recordReceipt(receipt)
        return receipt
    }

    private func complete(_ claim: Claim) {
        try? fileManager.removeItem(at: claim.fileURL)
    }

    private func signature(for request: ResidentExecutionRequest, secret: Data) throws -> String {
        let key = SymmetricKey(data: secret)
        let data = try CoreJSON.encode(SigningPayload(request))
        let code = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(code).base64EncodedString()
    }

    private func payloadDigest(for request: ResidentExecutionRequest) throws -> String {
        let data = try CoreJSON.encode(IdempotencyPayload(request))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func digestKey(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func safeIdentifier(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 97...122: return Character(String(scalar))
            default: return "_"
            }
        }.reduce(into: "") { $0.append($1) }
    }

    private func atomicCreate(_ data: Data, at destination: URL, mode: mode_t) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try secureWrite(data, to: temporary, mode: mode, replace: false)
        defer { try? fileManager.removeItem(at: temporary) }
        guard link(temporary.path, destination.path) == 0 else {
            if errno == EEXIST { throw Error.destinationExists }
            throw Error.unsafePath(destination.path)
        }
    }

    private func secureWrite(_ data: Data, to url: URL, mode: mode_t, replace: Bool) throws {
        if replace && fileManager.fileExists(atPath: url.path) {
            try validateExistingFile(url, mode: mode)
        }
        let flags = O_WRONLY | O_CREAT | O_NOFOLLOW | (replace ? O_TRUNC : O_EXCL)
        let fd = open(url.path, flags, mode)
        guard fd >= 0 else {
            if errno == EEXIST { throw Error.destinationExists }
            throw Error.unsafePath(url.path)
        }
        defer { close(fd) }
        let result = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard result == data.count else { throw Error.unsafePath(url.path) }
        guard fsync(fd) == 0 else { throw Error.unsafePath(url.path) }
        try validateExistingFile(url, mode: mode)
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        var difference = a.count ^ b.count
        for index in 0..<max(a.count, b.count) {
            difference |= Int((index < a.count ? a[index] : 0) ^ (index < b.count ? b[index] : 0))
        }
        return difference == 0
    }
}
