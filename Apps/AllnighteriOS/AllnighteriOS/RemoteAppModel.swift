//
//  RemoteAppModel.swift
//  AllnighteriOS
//
//  Owns the live or preview remote client and drives the conversation home store.
//

import AllnighterCore
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum RemoteAppConnectionPhase: Equatable {
    case idle
    case connecting
    case preview
    case connected(macName: String)
    case awaitingPairingApproval(macName: String)
    case needsConfiguration
    case noMacsOnAccount
    case failed(String)
}

enum WorkRequestSendPhase: Equatable {
    case idle
    case sending
    case failed(String)
}

enum KillSwitchPhase: Equatable {
    case idle
    case stopping
    case succeeded(String)
    case failed(String)
}

@MainActor
@Observable
final class RemoteAppModel {
    private(set) var homeSnapshot: ConversationListSnapshot = .empty
    private(set) var homeStatus: ConversationHomeLoadStatus = .idle
    private(set) var connectionPhase: RemoteAppConnectionPhase = .idle
    private(set) var workRequestSendPhase: WorkRequestSendPhase = .idle
    private(set) var killSwitchPhase: KillSwitchPhase = .idle

    var showsHome: Bool {
        switch connectionPhase {
        case .connected, .preview:
            return true
        default:
            return false
        }
    }

    var canSendWorkRequests: Bool {
        connectedClient != nil && workRequestSendPhase != .sending
    }

    var canStopAllWork: Bool {
        connectedClient != nil && killSwitchPhase != .stopping
    }

    var activeWorkCount: Int {
        let conversations = homeSnapshot.pinned
            + homeSnapshot.projects.flatMap(\.conversations)
        return conversations.filter(\.isPending).count
    }

    private var homeStore: ConversationHomeStore?
    private var connectedClient: RemoteCloudClientAssembly.ConnectedClient?
    private var previewClient: MockiOSClient?
    private var activationSequence = 0

    func activate() async {
        activationSequence += 1
        let currentActivation = activationSequence
        connectionPhase = .connecting

        if let environment = RemoteSupabaseEnvironment.load(), environment.hasDeviceCredentials {
            let activation = currentActivation
            do {
                let connected = try await RemoteCloudClientAssembly.makeConnectedClient(
                    environment: environment,
                    deviceDisplayName: Self.defaultDeviceDisplayName(),
                    onPairingPhase: { phase in
                        Task { @MainActor [weak self] in
                            guard let self, activation == self.activationSequence else { return }
                            switch phase {
                            case .checkingTrust, .requestingPairing:
                                self.connectionPhase = .connecting
                            case let .awaitingApproval(macDisplayName):
                                self.connectionPhase = .awaitingPairingApproval(macName: macDisplayName)
                            case .approved:
                                break
                            }
                        }
                    }
                )
                guard currentActivation == activationSequence else { return }
                connectedClient = connected
                homeStore = ConversationHomeStore(
                    client: connected.client,
                    macId: connected.mac.macAgentId
                )
                connectionPhase = .connected(macName: connected.mac.displayName)
                await refreshHome()
                return
            } catch {
                guard currentActivation == activationSequence else { return }
                connectionPhase = Self.connectionPhase(from: error)
            }
        }

        #if DEBUG
        guard currentActivation == activationSequence else { return }
        installPreviewClient()
        connectionPhase = .preview
        await refreshHome()
        #else
        guard currentActivation == activationSequence else { return }
        connectionPhase = .needsConfiguration
        homeSnapshot = .empty
        homeStatus = .idle
        #endif
    }

    func refreshHome() async {
        guard let homeStore else { return }
        await homeStore.refresh()
        homeSnapshot = homeStore.state.snapshot
        homeStatus = homeStore.state.status
    }

    func sendWorkRequest(prompt: String) async {
        guard let connectedClient, canSendWorkRequests else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        workRequestSendPhase = .sending
        let sender = WorkRequestSender(
            client: connectedClient.client,
            mac: connectedClient.mac,
            deviceId: connectedClient.deviceCredentials.deviceId,
            deviceSigningKey: connectedClient.deviceSigningKey
        )

        do {
            _ = try await sender.send(WorkRequestDraft(prompt: trimmed))
            workRequestSendPhase = .idle
            await refreshHome()
        } catch let error as WorkRequestSenderError where error == .emptyPrompt {
            workRequestSendPhase = .idle
        } catch {
            workRequestSendPhase = .failed(Self.workRequestFailureMessage(from: error))
        }
    }

    func clearWorkRequestSendFailure() {
        if case .failed = workRequestSendPhase {
            workRequestSendPhase = .idle
        }
    }

    func stopAllWork() async {
        guard let connectedClient, canStopAllWork else { return }

        killSwitchPhase = .stopping
        let sender = RemoteControlSender(
            client: connectedClient.client,
            deviceId: connectedClient.deviceCredentials.deviceId,
            deviceSigningKey: connectedClient.deviceSigningKey
        )

        do {
            let result = try await sender.stopAll()
            if result.commandResult.ack.accepted {
                killSwitchPhase = .succeeded("All active work stopped on your Mac.")
                await refreshHome()
            } else {
                killSwitchPhase = .failed(Self.killSwitchFailureMessage(from: result.commandResult.ack))
            }
        } catch {
            killSwitchPhase = .failed("Could not reach your Mac to stop work.")
        }
    }

    func clearKillSwitchStatus() {
        switch killSwitchPhase {
        case .succeeded, .failed:
            killSwitchPhase = .idle
        case .idle, .stopping:
            break
        }
    }

    private func installPreviewClient() {
        let now = Date()
        let client = MockiOSClient(
            macs: [
                MacAgentRef(
                    macAgentId: "mac_preview",
                    displayName: "Studio Mac",
                    agentSigningPubkey: "preview-sign",
                    agentSealingPubkey: "preview-seal",
                    lastSeenAt: now
                ),
            ],
            threadSnapshots: Self.previewThreadSnapshot(now: now),
            serverNow: now
        )
        previewClient = client
        homeStore = ConversationHomeStore(
            client: client,
            macId: "mac_preview",
            mapper: ConversationHomeMapper(projectNames: [
                "proj_allnighter": "Allnighter",
                "proj_inbox": "Inbox",
            ])
        )
        Task {
            try? await client.connect(
                account: RemoteAccountSession(accountId: "acct_preview", provider: .apple),
                mode: .cloudRelay
            )
        }
    }

    private static func previewThreadSnapshot(now: Date) -> [String: RemoteThreadSnapshotEnvelope] {
        [
            "mac_preview": RemoteThreadSnapshotEnvelope(
                threads: [
                    RemoteThreadSummary(
                        id: "pinned-cat",
                        title: "Give me a picture of a cat",
                        status: .active,
                        projectId: nil,
                        createdAt: now.addingTimeInterval(-3 * 86_400),
                        updatedAt: now.addingTimeInterval(-3 * 86_400),
                        pinnedAt: now.addingTimeInterval(-3 * 86_400),
                        displayState: .idle,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: false,
                            unreadNeedsAttention: false,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 1,
                        latestTurn: nil
                    ),
                    RemoteThreadSummary(
                        id: "thread-1",
                        title: "Add a new feature to the iOS app",
                        status: .active,
                        projectId: "proj_allnighter",
                        createdAt: now.addingTimeInterval(-86_400),
                        updatedAt: now.addingTimeInterval(-86_400),
                        pinnedAt: nil,
                        displayState: .idle,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: true,
                            unreadNeedsAttention: true,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 2,
                        latestTurn: nil
                    ),
                    RemoteThreadSummary(
                        id: "thread-2",
                        title: "Fix the layout bug in the header",
                        status: .active,
                        projectId: "proj_allnighter",
                        createdAt: now.addingTimeInterval(-7_200),
                        updatedAt: now.addingTimeInterval(-7_200),
                        pinnedAt: nil,
                        displayState: .running,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: false,
                            unreadNeedsAttention: false,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 1,
                        latestTurn: nil
                    ),
                    RemoteThreadSummary(
                        id: "thread-3",
                        title: "Write release notes for v1",
                        status: .active,
                        projectId: "proj_allnighter",
                        createdAt: now.addingTimeInterval(-3_600),
                        updatedAt: now.addingTimeInterval(-3_600),
                        pinnedAt: nil,
                        displayState: .idle,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: false,
                            unreadNeedsAttention: false,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 1,
                        latestTurn: nil
                    ),
                    RemoteThreadSummary(
                        id: "thread-4",
                        title: "Review the design board options",
                        status: .active,
                        projectId: "proj_allnighter",
                        createdAt: now.addingTimeInterval(-1_800),
                        updatedAt: now.addingTimeInterval(-1_800),
                        pinnedAt: nil,
                        displayState: .idle,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: true,
                            unreadNeedsAttention: true,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 1,
                        latestTurn: nil
                    ),
                    RemoteThreadSummary(
                        id: "thread-5",
                        title: "Ship the pairing flow",
                        status: .active,
                        projectId: "proj_allnighter",
                        createdAt: now.addingTimeInterval(-900),
                        updatedAt: now.addingTimeInterval(-900),
                        pinnedAt: nil,
                        displayState: .idle,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: false,
                            unreadNeedsAttention: false,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 1,
                        latestTurn: nil
                    ),
                    RemoteThreadSummary(
                        id: "inbox-1",
                        title: "Quick question about quotas",
                        status: .active,
                        projectId: "proj_inbox",
                        createdAt: now.addingTimeInterval(-600),
                        updatedAt: now.addingTimeInterval(-600),
                        pinnedAt: nil,
                        displayState: .idle,
                        readState: RemoteThreadReadState(
                            readCursor: nil,
                            hasUnread: true,
                            unreadNeedsAttention: true,
                            firstUnreadTurnId: nil,
                            latestUnreadTurnId: nil
                        ),
                        turnCount: 1,
                        latestTurn: nil
                    ),
                ],
                serverTime: now
            ),
        ]
    }

    private static func defaultDeviceDisplayName() -> String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }

    private static func connectionPhase(from error: Error) -> RemoteAppConnectionPhase {
        switch error {
        case RemoteCloudClientAssemblyError.macNotSelected:
            return .noMacsOnAccount
        default:
            return .failed(failureMessage(from: error))
        }
    }

    private static func failureMessage(from error: Error) -> String {
        switch error {
        case RemoteCloudClientAssemblyError.missingDeviceAccessToken:
            "Sign in to connect to your Mac."
        case RemoteCloudClientAssemblyError.missingAccountId:
            "Account is not configured for remote access."
        case RemoteCloudClientAssemblyError.macNotSelected:
            "No Mac is available on this account yet."
        case RemoteCloudClientAssemblyError.pairingTimedOut:
            "Pairing timed out. Approve this device on your Mac and try again."
        case RemoteCloudClientAssemblyError.pairingRejected:
            "This device was not approved on your Mac."
        default:
            "Could not connect to your Mac."
        }
    }

    private static func workRequestFailureMessage(from error: Error) -> String {
        switch error {
        case WorkRequestSenderError.emptyPrompt:
            "Enter a work request before sending."
        default:
            "Could not send work request to your Mac."
        }
    }

    private static func killSwitchFailureMessage(from ack: CommandAck) -> String {
        switch ack.reason {
        case .revoked:
            "This device is not authorized to stop work on your Mac."
        case .rateLimited:
            "Too many stop requests. Try again shortly."
        case .clockSkew:
            "Your phone clock is out of sync with your Mac."
        case .unauthorizedKind:
            "This device cannot send stop commands."
        case .replayedRequestId:
            "That stop request was already sent."
        default:
            "Your Mac did not accept the stop request."
        }
    }
}
