//
//  ConversationThreadStore.swift
//  AllnighteriOS
//
//  Loads sealed remote thread details through Core and exposes decrypted UI state.
//

import AllnighterCore
import CryptoKit
import Foundation

struct ConversationThreadStoreState: Equatable {
    var snapshot: ConversationThreadSnapshot?
    var status: ConversationThreadLoadStatus
}

enum ConversationThreadLoadStatus: Equatable {
    case idle
    case loading(threadId: String)
    case loaded(threadId: String)
    case cached(threadId: String, serverTime: Date, cachedAt: Date)
    case failed(threadId: String, ConversationThreadLoadFailure)
}

enum ConversationThreadLoadFailure: Equatable {
    case sealedDetailEnvelopeMismatch(
        expectedDeviceId: String,
        actualDeviceId: String,
        expectedContentType: String,
        actualContentType: String
    )
    case threadMismatch(expectedThreadId: String, actualThreadId: String)
    case unavailable
}

@MainActor
final class ConversationThreadStore {
    private let client: any RemoteClient
    private let macId: String
    private let deviceId: String
    private let deviceSealingKey: Curve25519.KeyAgreement.PrivateKey
    private let mapper: ConversationThreadMapper
    private var loadSequence = 0

    private(set) var state: ConversationThreadStoreState

    init(
        client: any RemoteClient,
        macId: String,
        deviceId: String,
        deviceSealingKey: Curve25519.KeyAgreement.PrivateKey,
        mapper: ConversationThreadMapper = ConversationThreadMapper(),
        initialSnapshot: ConversationThreadSnapshot? = nil
    ) {
        self.client = client
        self.macId = macId
        self.deviceId = deviceId
        self.deviceSealingKey = deviceSealingKey
        self.mapper = mapper
        self.state = ConversationThreadStoreState(snapshot: initialSnapshot, status: .idle)
    }

    func applySnapshot(_ snapshot: ConversationThreadSnapshot, threadId: String) {
        state = ConversationThreadStoreState(snapshot: snapshot, status: .loaded(threadId: threadId))
    }

    func load(threadId: String) async {
        loadSequence += 1
        let currentLoad = loadSequence
        let previousSnapshot = state.snapshot
        state = ConversationThreadStoreState(snapshot: previousSnapshot, status: .loading(threadId: threadId))

        do {
            let detail = try await RemoteThreadReader.fetchDetail(
                client: client,
                macId: macId,
                threadId: threadId,
                deviceId: deviceId,
                deviceSealingKey: deviceSealingKey
            )
            guard currentLoad == loadSequence else { return }
            state = ConversationThreadStoreState(
                snapshot: mapper.snapshot(from: detail),
                status: .loaded(threadId: threadId)
            )
        } catch {
            guard currentLoad == loadSequence else { return }
            state = ConversationThreadStoreState(
                snapshot: previousSnapshot,
                status: .failed(threadId: threadId, Self.failure(from: error))
            )
        }
    }

    private static func failure(from error: Error) -> ConversationThreadLoadFailure {
        guard let error = error as? RemoteThreadReaderError else {
            return .unavailable
        }

        switch error {
        case let .sealedDetailEnvelopeMismatch(
            expectedDeviceId,
            actualDeviceId,
            expectedContentType,
            actualContentType
        ):
            return .sealedDetailEnvelopeMismatch(
                expectedDeviceId: expectedDeviceId,
                actualDeviceId: actualDeviceId,
                expectedContentType: expectedContentType,
                actualContentType: actualContentType
            )
        case let .detailThreadMismatch(expectedThreadId, actualThreadId):
            return .threadMismatch(expectedThreadId: expectedThreadId, actualThreadId: actualThreadId)
        case .unsupportedProtocolVersion:
            return .unavailable
        }
    }
}
