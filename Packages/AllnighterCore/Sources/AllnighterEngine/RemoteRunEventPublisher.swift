#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import AllnighterCore

public struct RemoteRunEventPublishResult: Equatable, Sendable {
    public var publishedEventCount: Int
    public var lastSeq: Int64
    public var lastPublishedSeq: Int64?

    public init(publishedEventCount: Int, lastSeq: Int64, lastPublishedSeq: Int64? = nil) {
        self.publishedEventCount = publishedEventCount
        self.lastSeq = lastSeq
        self.lastPublishedSeq = lastPublishedSeq
    }
}

public struct RemoteRunEventPublisher: Sendable {
    public let accountId: String
    public let macAgentId: String
    public let journal: RemoteRunEventJournal
    public let relay: RemoteMacRelay
    public let signingKey: Curve25519.Signing.PrivateKey
    public let batchLimit: Int

    public init(
        accountId: String,
        macAgentId: String,
        journal: RemoteRunEventJournal = RemoteRunEventJournal(),
        relay: RemoteMacRelay,
        signingKey: Curve25519.Signing.PrivateKey,
        batchLimit: Int = 100
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.journal = journal
        self.relay = relay
        self.signingKey = signingKey
        self.batchLimit = max(0, batchLimit)
    }

    public func publish(after seq: Int64) async throws -> RemoteRunEventPublishResult {
        let replay = try journal.replay(after: seq, limit: batchLimit)
        let envelopes = try replay.events.map { event in
            try RemoteCrypto.makeRemoteRunEventEnvelope(
                macAgentId: macAgentId,
                event: event,
                signingKey: signingKey
            )
        }

        if !envelopes.isEmpty {
            try await relay.publishEvents(
                accountId: accountId,
                macAgentId: macAgentId,
                events: envelopes
            )
        }

        return RemoteRunEventPublishResult(
            publishedEventCount: envelopes.count,
            lastSeq: replay.lastSeq,
            lastPublishedSeq: envelopes.map(\.event.seq).max()
        )
    }
}
