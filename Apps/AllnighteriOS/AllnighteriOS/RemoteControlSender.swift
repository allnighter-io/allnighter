//
//  RemoteControlSender.swift
//  AllnighteriOS
//
//  Sends typed remote control commands for stop and read-state actions.
//

import AllnighterCore
import CryptoKit
import Foundation

struct RemoteControlSendResult: Equatable, Sendable {
    var requestId: String
    var commandResult: RemoteCommandSendResult
}

struct RemoteControlSender {
    private let client: any RemoteClient
    private let deviceId: String
    private let deviceSigningKey: Curve25519.Signing.PrivateKey
    private let requestIdProvider: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        client: any RemoteClient,
        deviceId: String,
        deviceSigningKey: Curve25519.Signing.PrivateKey,
        requestId: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.deviceId = deviceId
        self.deviceSigningKey = deviceSigningKey
        self.requestIdProvider = requestId
        self.now = now
    }

    func stopAll() async throws -> RemoteControlSendResult {
        try await send { factory, requestId in
            try factory.stopAll(requestId: requestId)
        }
    }

    func stopRun(runId: String) async throws -> RemoteControlSendResult {
        try await send { factory, requestId in
            try factory.stopRun(requestId: requestId, runId: runId)
        }
    }

    func markThreadRead(threadId: String, throughTurnId: String) async throws -> RemoteControlSendResult {
        try await send { factory, requestId in
            try factory.markThreadRead(
                requestId: requestId,
                threadId: threadId,
                throughTurnId: throughTurnId
            )
        }
    }

    private func send(
        build: @escaping @Sendable (RemoteCommandFactory, String) throws -> RemoteCommand
    ) async throws -> RemoteControlSendResult {
        let requestId = requestIdProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await RemoteCommandSender.sendWithClockSkewRetry(
            client: client,
            initialNow: now()
        ) { signingTime in
            try build(
                RemoteCommandFactory(
                    deviceId: deviceId,
                    signingKey: deviceSigningKey,
                    now: { signingTime }
                ),
                requestId
            )
        }
        return RemoteControlSendResult(requestId: requestId, commandResult: result)
    }
}
