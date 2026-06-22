//
//  ConversationHomeStore.swift
//  AllnighteriOS
//
//  Loads the Mac-owned remote thread snapshot into the iOS home state.
//

import AllnighterCore
import Foundation

struct ConversationHomeStoreState: Equatable {
    var snapshot: ConversationListSnapshot
    var status: ConversationHomeLoadStatus
}

enum ConversationHomeLoadStatus: Equatable {
    case idle
    case loading
    case loaded(serverTime: Date)
    case failed(ConversationHomeLoadFailure)
}

enum ConversationHomeLoadFailure: Equatable {
    case unsupportedProtocolVersion(expected: Int, actual: Int)
    case unavailable
}

@MainActor
final class ConversationHomeStore {
    private let client: any RemoteClient
    private let macId: String
    private let mapper: ConversationHomeMapper
    private var refreshSequence = 0

    private(set) var state: ConversationHomeStoreState

    init(
        client: any RemoteClient,
        macId: String,
        mapper: ConversationHomeMapper = ConversationHomeMapper(),
        initialSnapshot: ConversationListSnapshot = .empty
    ) {
        self.client = client
        self.macId = macId
        self.mapper = mapper
        self.state = ConversationHomeStoreState(snapshot: initialSnapshot, status: .idle)
    }

    func refresh() async {
        refreshSequence += 1
        let currentRefresh = refreshSequence
        let previousSnapshot = state.snapshot
        state = ConversationHomeStoreState(snapshot: previousSnapshot, status: .loading)

        do {
            let envelope = try await RemoteThreadReader.fetchSnapshot(client: client, macId: macId)
            guard currentRefresh == refreshSequence else { return }
            state = ConversationHomeStoreState(
                snapshot: mapper.snapshot(from: envelope, now: envelope.serverTime),
                status: .loaded(serverTime: envelope.serverTime)
            )
        } catch {
            guard currentRefresh == refreshSequence else { return }
            state = ConversationHomeStoreState(
                snapshot: previousSnapshot,
                status: .failed(Self.failure(from: error))
            )
        }
    }

    private static func failure(from error: Error) -> ConversationHomeLoadFailure {
        guard let error = error as? RemoteThreadReaderError else {
            return .unavailable
        }

        switch error {
        case let .unsupportedProtocolVersion(expected, actual):
            return .unsupportedProtocolVersion(expected: expected, actual: actual)
        case .sealedDetailEnvelopeMismatch, .detailThreadMismatch:
            return .unavailable
        }
    }
}
