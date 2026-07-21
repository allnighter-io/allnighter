#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

public enum RemoteThreadReaderError: Error, Equatable, Sendable {
    case unsupportedProtocolVersion(expected: Int, actual: Int)
    case sealedDetailEnvelopeMismatch(
        expectedDeviceId: String,
        actualDeviceId: String,
        expectedContentType: String,
        actualContentType: String
    )
    case detailThreadMismatch(expectedThreadId: String, actualThreadId: String)
}

public struct RemoteThreadDetailBundle: Equatable, Sendable {
    public var macId: String
    public var threadId: String
    public var deviceId: String
    public var sealedDetail: SealedBlob
    public var detail: RemoteThreadDetail

    public init(
        macId: String,
        threadId: String,
        deviceId: String,
        sealedDetail: SealedBlob,
        detail: RemoteThreadDetail
    ) {
        self.macId = macId
        self.threadId = threadId
        self.deviceId = deviceId
        self.sealedDetail = sealedDetail
        self.detail = detail
    }
}

public enum RemoteThreadReader {
    public static func fetchSnapshot(
        client: any RemoteClient,
        macId: String
    ) async throws -> RemoteThreadSnapshotEnvelope {
        let snapshot = try await client.threadSnapshot(macId: macId)
        try validateProtocolVersion(snapshot.protocolVersion)
        return snapshot
    }

    public static func fetchDetailBundle(
        client: any RemoteClient,
        macId: String,
        threadId: String,
        deviceId: String,
        deviceSealingKey: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> RemoteThreadDetailBundle {
        let sealedDetail = try await client.sealedThreadDetail(
            macId: macId,
            threadId: threadId,
            deviceId: deviceId
        )
        try validateSealedDetail(sealedDetail, deviceId: deviceId)
        let plaintext = try RemoteCrypto.open(sealedDetail, with: deviceSealingKey)
        let detail = try CoreJSON.decode(RemoteThreadDetail.self, from: plaintext)
        guard detail.id == threadId else {
            throw RemoteThreadReaderError.detailThreadMismatch(
                expectedThreadId: threadId,
                actualThreadId: detail.id
            )
        }
        return RemoteThreadDetailBundle(
            macId: macId,
            threadId: threadId,
            deviceId: deviceId,
            sealedDetail: sealedDetail,
            detail: detail
        )
    }

    public static func fetchDetail(
        client: any RemoteClient,
        macId: String,
        threadId: String,
        deviceId: String,
        deviceSealingKey: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> RemoteThreadDetail {
        try await fetchDetailBundle(
            client: client,
            macId: macId,
            threadId: threadId,
            deviceId: deviceId,
            deviceSealingKey: deviceSealingKey
        ).detail
    }

    private static func validateProtocolVersion(_ protocolVersion: Int) throws {
        guard protocolVersion == RemoteProtocol.currentMajor else {
            throw RemoteThreadReaderError.unsupportedProtocolVersion(
                expected: RemoteProtocol.currentMajor,
                actual: protocolVersion
            )
        }
    }

    private static func validateSealedDetail(_ sealedDetail: SealedBlob, deviceId: String) throws {
        guard sealedDetail.sealedForKeyId == deviceId,
              sealedDetail.contentType == RemoteThreadDetail.sealedContentType else {
            throw RemoteThreadReaderError.sealedDetailEnvelopeMismatch(
                expectedDeviceId: deviceId,
                actualDeviceId: sealedDetail.sealedForKeyId,
                expectedContentType: RemoteThreadDetail.sealedContentType,
                actualContentType: sealedDetail.contentType
            )
        }
    }
}
