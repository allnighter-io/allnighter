//
//  WorkRequestSender.swift
//  AllnighteriOS
//
//  Sends a phone-authored work request through Core's typed remote command seam.
//

import AllnighterCore
import CryptoKit
import Foundation

struct WorkRequestDraft: Equatable, Sendable {
    var prompt: String
    var threadId: String?
    var originConversationId: String?
    var originMessageId: String?

    init(
        prompt: String,
        threadId: String? = nil,
        originConversationId: String? = nil,
        originMessageId: String? = nil
    ) {
        self.prompt = prompt
        self.threadId = threadId
        self.originConversationId = originConversationId
        self.originMessageId = originMessageId
    }
}

struct WorkRequestSendResult: Equatable, Sendable {
    var requestId: String
    var commandResult: RemoteCommandSendResult
}

enum WorkRequestSenderError: Error, Equatable, Sendable {
    case emptyPrompt
}

struct WorkRequestSender {
    private let client: any RemoteClient
    private let mac: MacAgentRef
    private let deviceId: String
    private let deviceSigningKey: Curve25519.Signing.PrivateKey
    private let requestIdProvider: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        client: any RemoteClient,
        mac: MacAgentRef,
        deviceId: String,
        deviceSigningKey: Curve25519.Signing.PrivateKey,
        requestId: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.mac = mac
        self.deviceId = deviceId
        self.deviceSigningKey = deviceSigningKey
        self.requestIdProvider = requestId
        self.now = now
    }

    func send(_ draft: WorkRequestDraft) async throws -> WorkRequestSendResult {
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw WorkRequestSenderError.emptyPrompt
        }

        let requestId = requestIdProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = RemoteStartRunPayload(
            prompt: prompt,
            threadId: normalizedOptional(draft.threadId),
            originConversationId: normalizedOptional(draft.originConversationId),
            originMessageId: normalizedOptional(draft.originMessageId)
        )
        let result = try await RemoteCommandSender.sendWithClockSkewRetry(
            client: client,
            initialNow: now()
        ) { signingTime in
            try RemoteCommandFactory(
                deviceId: deviceId,
                signingKey: deviceSigningKey,
                now: { signingTime }
            ).startRun(
                requestId: requestId,
                payload: payload,
                mac: mac
            )
        }

        return WorkRequestSendResult(requestId: requestId, commandResult: result)
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
