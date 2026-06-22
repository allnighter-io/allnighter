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

enum StopRunPhase: Equatable {
    case idle
    case stopping(runId: String)
    case succeeded(runId: String)
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
    private(set) var threadSnapshot: ConversationThreadSnapshot?
    private(set) var threadLoadStatus: ConversationThreadLoadStatus = .idle
    private(set) var stopRunPhase: StopRunPhase = .idle
    private(set) var connectionDiagnosisLine: String?
    private(set) var homeFreshnessLabel: String?

    private let homeCache = ConversationHomeCache()
    private let threadDetailCache = ConversationThreadDetailCache()
    private var cachedAccountId: String?

    var connectionStatusText: String {
        switch connectionPhase {
        case .idle, .connecting:
            "Connecting to your Mac…"
        case .preview:
            "Preview data — configure Supabase to connect live."
        case let .connected(macName):
            connectionDiagnosisLine ?? "Connected to \(macName)"
        case let .awaitingPairingApproval(macName):
            "Approve this iPhone on \(macName)"
        case .needsConfiguration:
            "Sign in to connect to your Mac."
        case .noMacsOnAccount:
            "No Mac registered on this account yet."
        case let .failed(message):
            message
        }
    }

    var connectionStatusTone: IOSStatusBanner.Tone {
        switch connectionPhase {
        case .connected:
            if connectionDiagnosisLine?.contains("Wake") == true
                || connectionDiagnosisLine?.contains("asleep") == true
                || connectionDiagnosisLine?.contains("agent") == true {
                return .warning
            }
            return .positive
        case .preview, .idle, .connecting:
            return .neutral
        case .awaitingPairingApproval, .needsConfiguration, .noMacsOnAccount, .failed:
            return .warning
        }
    }

    var showsHome: Bool {
        switch connectionPhase {
        case .connected, .preview:
            return true
        default:
            return false
        }
    }

    var canSendWorkRequests: Bool {
        deviceSession != nil && workRequestSendPhase != .sending
    }

    var canStopAllWork: Bool {
        deviceSession != nil && killSwitchPhase != .stopping
    }

    var canStopActiveRun: Bool {
        guard deviceSession != nil, threadSnapshot?.activeRunId != nil else { return false }
        if case .stopping = stopRunPhase { return false }
        return true
    }

    var activeWorkCount: Int {
        let conversations = homeSnapshot.pinned
            + homeSnapshot.projects.flatMap(\.conversations)
        return conversations.filter(\.isPending).count
    }

    var pendingDecisionCount: Int {
        let conversations = homeSnapshot.pinned
            + homeSnapshot.projects.flatMap(\.conversations)
        return conversations.filter(\.needsAttention).count
    }

    private var homeStore: ConversationHomeStore?
    private var connectedClient: RemoteCloudClientAssembly.ConnectedClient?
    private var previewClient: MockiOSClient?
    private var deviceSession: DeviceSession?
    private var threadStore: ConversationThreadStore?
    private var activationSequence = 0
    var composerThreadId: String?

    private struct DeviceSession {
        var client: any RemoteClient
        var mac: MacAgentRef
        var accountId: String
        var deviceId: String
        var deviceSigningKey: Curve25519.Signing.PrivateKey
        var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey
    }

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
                deviceSession = DeviceSession(
                    client: connected.client,
                    mac: connected.mac,
                    accountId: connected.account.accountId,
                    deviceId: connected.deviceCredentials.deviceId,
                    deviceSigningKey: connected.deviceSigningKey,
                    deviceSealingKey: connected.deviceSealingKey
                )
                cachedAccountId = connected.account.accountId
                threadStore = nil
                threadSnapshot = nil
                threadLoadStatus = .idle
                seedHomeFromCache(accountId: connected.account.accountId, macAgentId: connected.mac.macAgentId)
                homeStore = ConversationHomeStore(
                    client: connected.client,
                    macId: connected.mac.macAgentId,
                    initialSnapshot: homeSnapshot
                )
                connectionPhase = .connected(macName: connected.mac.displayName)
                await refreshHome()
                await refreshConnectionDiagnosis()
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
        await refreshConnectionDiagnosis()
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

        switch homeStatus {
        case .loaded(let serverTime):
            persistHomeCache(serverTime: serverTime)
            homeFreshnessLabel = nil
        case .failed:
            restoreHomeCacheAfterFailure()
        case .cached, .idle, .loading:
            break
        }

        await refreshConnectionDiagnosis()
    }

    private func seedHomeFromCache(accountId: String, macAgentId: String) {
        guard let entry = try? homeCache.load(),
              entry.accountId == accountId,
              entry.macAgentId == macAgentId else {
            return
        }
        homeSnapshot = entry.snapshot
        homeStatus = .cached(serverTime: entry.serverTime, cachedAt: entry.cachedAt)
        homeFreshnessLabel = ConversationRelativeTime.lastSeen(serverTime: entry.serverTime)
    }

    private func persistHomeCache(serverTime: Date) {
        guard case .connected = connectionPhase,
              let session = deviceSession,
              let accountId = cachedAccountId else {
            return
        }
        let entry = ConversationHomeCacheEntry(
            accountId: accountId,
            macAgentId: session.mac.macAgentId,
            serverTime: serverTime,
            snapshot: homeSnapshot
        )
        try? homeCache.save(entry)
    }

    private func restoreHomeCacheAfterFailure() {
        guard let session = deviceSession,
              let accountId = cachedAccountId,
              let entry = try? homeCache.load(),
              entry.accountId == accountId,
              entry.macAgentId == session.mac.macAgentId else {
            return
        }
        homeSnapshot = entry.snapshot
        homeStatus = .cached(serverTime: entry.serverTime, cachedAt: entry.cachedAt)
        homeFreshnessLabel = ConversationRelativeTime.lastSeen(serverTime: entry.serverTime)
    }

    func refreshConnectionDiagnosis() async {
        guard let session = deviceSession else {
            connectionDiagnosisLine = nil
            return
        }
        let diagnosis = await session.client.diagnose()
        connectionDiagnosisLine = Self.diagnosisLine(
            diagnosis,
            macName: session.mac.displayName,
            connectionPhase: connectionPhase
        )
    }

    func loadThread(threadId: String) async {
        guard let session = deviceSession else { return }
        let store = threadStore ?? ConversationThreadStore(
            client: session.client,
            macId: session.mac.macAgentId,
            deviceId: session.deviceId,
            deviceSealingKey: session.deviceSealingKey
        )
        threadStore = store
        _ = restoreThreadCache(threadId: threadId)
        await store.load(threadId: threadId)
        threadSnapshot = store.state.snapshot
        threadLoadStatus = store.state.status

        switch threadLoadStatus {
        case .loaded(let loadedId) where loadedId == threadId:
            if let snapshot = threadSnapshot {
                persistThreadCache(snapshot: snapshot, threadId: threadId)
                if snapshot.hasUnread, let throughTurnId = snapshot.readThroughTurnId {
                    await markThreadRead(threadId: threadId, throughTurnId: throughTurnId)
                }
            }
        case .failed(let failedId, _) where failedId == threadId:
            _ = restoreThreadCache(threadId: threadId)
        default:
            break
        }
    }

    private func persistThreadCache(snapshot: ConversationThreadSnapshot, threadId: String) {
        guard case .connected = connectionPhase,
              let session = deviceSession else {
            return
        }
        let entry = ConversationThreadDetailCacheEntry(
            macAgentId: session.mac.macAgentId,
            threadId: threadId,
            serverTime: Date(),
            snapshot: snapshot
        )
        try? threadDetailCache.save(entry)
    }

    @discardableResult
    private func restoreThreadCache(threadId: String) -> Bool {
        guard let session = deviceSession,
              let entry = try? threadDetailCache.load(
                macAgentId: session.mac.macAgentId,
                threadId: threadId
              ) else {
            return false
        }
        threadSnapshot = entry.snapshot
        threadLoadStatus = .cached(
            threadId: threadId,
            serverTime: entry.serverTime,
            cachedAt: entry.cachedAt
        )
        return true
    }

    private func markThreadRead(threadId: String, throughTurnId: String) async {
        guard let session = deviceSession else { return }
        let sender = RemoteControlSender(
            client: session.client,
            deviceId: session.deviceId,
            deviceSigningKey: session.deviceSigningKey
        )
        do {
            let result = try await sender.markThreadRead(threadId: threadId, throughTurnId: throughTurnId)
            guard result.commandResult.ack.accepted else { return }
            await refreshHome()
        } catch {
            return
        }
    }

    func stopActiveRun() async {
        guard let session = deviceSession,
              let snapshot = threadSnapshot,
              let runId = snapshot.activeRunId,
              canStopActiveRun else {
            return
        }

        stopRunPhase = .stopping(runId: runId)
        let sender = RemoteControlSender(
            client: session.client,
            deviceId: session.deviceId,
            deviceSigningKey: session.deviceSigningKey
        )

        do {
            let result = try await sender.stopRun(runId: runId)
            if result.commandResult.ack.accepted {
                stopRunPhase = .succeeded(runId: runId)
                await loadThread(threadId: snapshot.id)
                await refreshHome()
            } else {
                stopRunPhase = .failed(Self.killSwitchFailureMessage(from: result.commandResult.ack))
            }
        } catch {
            stopRunPhase = .failed("Could not stop this run on your Mac.")
        }
    }

    func clearStopRunStatus() {
        switch stopRunPhase {
        case .succeeded, .failed:
            stopRunPhase = .idle
        case .idle, .stopping:
            break
        }
    }

    func sendWorkRequest(prompt: String) async {
        guard let session = deviceSession, canSendWorkRequests else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        workRequestSendPhase = .sending
        let sender = WorkRequestSender(
            client: session.client,
            mac: session.mac,
            deviceId: session.deviceId,
            deviceSigningKey: session.deviceSigningKey
        )

        do {
            _ = try await sender.send(WorkRequestDraft(
                prompt: trimmed,
                threadId: composerThreadId
            ))
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
        guard let session = deviceSession, canStopAllWork else { return }

        killSwitchPhase = .stopping
        let sender = RemoteControlSender(
            client: session.client,
            deviceId: session.deviceId,
            deviceSigningKey: session.deviceSigningKey
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
        let signingKey = Curve25519.Signing.PrivateKey()
        let sealingKey = Curve25519.KeyAgreement.PrivateKey()
        let deviceId = "preview_device"
        let accountId = "acct_preview"
        let macAgentId = "mac_preview"

        let trustedDevice = TrustedDevice(
            deviceId: deviceId,
            displayName: "Preview iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now,
            validUntil: now.addingTimeInterval(86_400),
            revoked: false,
            capabilities: [.startRun, .stopRun, .markThreadRead]
        )

        let threadDetails: [String: [String: SealedBlob]]
        do {
            let blob = try Self.previewSealedThreadDetail(
                threadId: "thread-2",
                deviceId: deviceId,
                sealingKey: sealingKey,
                now: now,
                runId: "run_preview_2"
            )
            threadDetails = ["thread-2": [deviceId: blob]]
        } catch {
            threadDetails = [:]
        }

        let client = MockiOSClient(
            macs: [
                MacAgentRef(
                    macAgentId: macAgentId,
                    displayName: "Studio Mac",
                    agentSigningPubkey: "preview-sign",
                    agentSealingPubkey: "preview-seal",
                    lastSeenAt: now
                ),
            ],
            threadSnapshots: Self.previewThreadSnapshot(now: now),
            threadDetails: threadDetails,
            trustedDevices: [trustedDevice],
            serverNow: now
        )
        previewClient = client
        deviceSession = DeviceSession(
            client: client,
            mac: MacAgentRef(
                macAgentId: macAgentId,
                displayName: "Studio Mac",
                agentSigningPubkey: "preview-sign",
                agentSealingPubkey: "preview-seal",
                lastSeenAt: now
            ),
            accountId: accountId,
            deviceId: deviceId,
            deviceSigningKey: signingKey,
            deviceSealingKey: sealingKey
        )
        cachedAccountId = nil
        threadStore = nil
        threadSnapshot = nil
        threadLoadStatus = .idle
        homeStore = ConversationHomeStore(
            client: client,
            macId: macAgentId,
            mapper: ConversationHomeMapper(projectNames: [
                "proj_allnighter": "Allnighter",
                "proj_inbox": "Inbox",
            ])
        )
        Task {
            try? await client.connect(
                account: RemoteAccountSession(accountId: accountId, provider: .apple),
                mode: ConnectionMode.cloudRelay
            )
        }
    }

    private static func previewSealedThreadDetail(
        threadId: String,
        deviceId: String,
        sealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: Date,
        runId: String
    ) throws -> SealedBlob {
        let summary = RemoteThreadSummary(
            id: threadId,
            title: "Fix the layout bug in the header",
            status: .active,
            projectId: "proj_allnighter",
            createdAt: now.addingTimeInterval(-7_200),
            updatedAt: now.addingTimeInterval(-300),
            pinnedAt: nil,
            displayState: .running,
            readState: RemoteThreadReadState(
                readCursor: nil,
                hasUnread: false,
                unreadNeedsAttention: false,
                firstUnreadTurnId: nil,
                latestUnreadTurnId: nil
            ),
            turnCount: 2,
            latestTurn: nil
        )
        let detail = RemoteThreadDetail(
            summary: summary,
            turns: [
                RemoteThreadTurnDetail(
                    id: "turn_user",
                    kind: .userMessage,
                    status: .done,
                    author: .user,
                    createdAt: now.addingTimeInterval(-600),
                    completedAt: now.addingTimeInterval(-600),
                    text: "Fix the layout bug in the header"
                ),
                RemoteThreadTurnDetail(
                    id: "turn_worker",
                    kind: .workerChat,
                    status: .running,
                    author: .worker,
                    createdAt: now.addingTimeInterval(-300),
                    text: "Inspecting the header stack and safe-area insets…",
                    runId: runId,
                    partialOutputTruncated: false
                ),
            ]
        )
        return try RemoteCrypto.seal(
            CoreJSON.encode(detail),
            to: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            sealedForKeyId: deviceId,
            contentType: RemoteThreadDetail.sealedContentType
        )
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

    private static func diagnosisLine(
        _ diagnosis: ConnectionDiagnosis,
        macName: String,
        connectionPhase: RemoteAppConnectionPhase
    ) -> String? {
        guard case .connected = connectionPhase else { return nil }
        if diagnosis.rungs.allSatisfy(\.ok) {
            return "Connected to \(macName)"
        }
        if let unreachable = diagnosis.rungs.first(where: { $0.rung == .macReachable && !$0.ok }) {
            return unreachable.nextAction ?? "Wake your Mac or start the Allnighter agent."
        }
        if let failed = diagnosis.rungs.first(where: { !$0.ok }) {
            return failed.nextAction
        }
        return "Connected to \(macName)"
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
