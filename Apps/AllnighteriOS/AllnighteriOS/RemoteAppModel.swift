//
//  RemoteAppModel.swift
//  AllnighteriOS
//
//  Owns the live or preview remote client and drives the conversation home store.
//

import AllnighterCore
import CryptoKit
import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
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

enum RemoteAppUnauthenticatedFallback: Equatable {
    case onboarding
    case preview
}

#if DEBUG
private func isIOSUITestingPreview() -> Bool {
    if ProcessInfo.processInfo.arguments.contains("-ui_testing_preview") { return true }
    if ProcessInfo.processInfo.environment["ALLNIGHTER_UI_TESTING_PREVIEW"] == "1" { return true }
    return false
}
#else
private func isIOSUITestingPreview() -> Bool { false }
#endif

@MainActor
@Observable
final class RemoteAppModel {
    private(set) var homeSnapshot: ConversationListSnapshot = .empty
    private(set) var homeStatus: ConversationHomeLoadStatus = .idle
    private(set) var connectionPhase: RemoteAppConnectionPhase = isIOSUITestingPreview() ? .preview : .idle
    private(set) var workRequestSendPhase: WorkRequestSendPhase = .idle
    private(set) var killSwitchPhase: KillSwitchPhase = .idle
    private(set) var threadSnapshot: ConversationThreadSnapshot?
    private(set) var threadLoadStatus: ConversationThreadLoadStatus = .idle
    private(set) var stopRunPhase: StopRunPhase = .idle
    private(set) var connectionDiagnosisLine: String?
    private(set) var homeFreshnessLabel: String?
    private(set) var pendingOpenThreadId: String?

    var composerDraft = IOSComposerDraft()

    private let homeCache = ConversationHomeCache()
    private let threadDetailCache = ConversationThreadDetailCache()
    private var cachedAccountId: String?

    var connectionStatusText: String {
        switch connectionPhase {
        case .idle, .connecting:
            "Connecting to your Mac…"
        case .preview:
            Self.isDebugBuild
                ? "Preview data — configure Supabase to connect live."
                : "Preview mode — sign-in is not wired yet."
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

    private(set) var pendingQueue: PendingQueueJSON = .empty
    private var pendingPromptsByID: [String: String] = [:]

    var armedPendingCount: Int { pendingQueue.totalPending }

    func pendingPrompt(for id: String) -> String {
        pendingPromptsByID[id] ?? ""
    }

    func refreshPendingQueue() async {
        await refreshHome()
    }

    func removePendingItem(id: String) {
        if case .preview = connectionPhase {
            mutatePreviewPending { queue, prompts in
                removePendingItemLocally(id: id, from: &queue, prompts: &prompts)
            }
            return
        }
        Task { await mutateLivePendingItem(id: id, action: .cancel) }
    }

    /// Un-arm (Pending → Draft): drops from armed queue until re-submitted.
    func unarmPendingItem(id: String) {
        if case .preview = connectionPhase {
            mutatePreviewPending { queue, prompts in
                removePendingItemLocally(id: id, from: &queue, prompts: &prompts)
            }
            return
        }
        Task { await mutateLivePendingItem(id: id, action: .unarm) }
    }

    func rearmPendingItem(id: String, prompt: String, draft: IOSComposerDraft) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .preview = connectionPhase {
            mutatePreviewPending { queue, prompts in
                rearmPreviewPendingItem(
                    id: id,
                    prompt: trimmed,
                    draft: draft,
                    queue: &queue,
                    prompts: &prompts
                )
            }
            return
        }
        Task {
            await mutateLivePendingItem(
                id: id,
                action: .rearm(prompt: trimmed, draft: draft)
            )
        }
    }

    private enum LivePendingAction {
        case cancel
        case unarm
        case rearm(prompt: String, draft: IOSComposerDraft)
    }

    private func mutateLivePendingItem(id: String, action: LivePendingAction) async {
        guard let session = deviceSession else { return }
        let sender = RemoteControlSender(
            client: session.client,
            deviceId: session.deviceId,
            deviceSigningKey: session.deviceSigningKey
        )
        do {
            switch action {
            case .cancel:
                let result = try await sender.cancelPendingItem(id: id)
                guard result.commandResult.ack.accepted else { return }
            case .unarm:
                let result = try await sender.editPendingItem(id: id)
                guard result.commandResult.ack.accepted else { return }
            case let .rearm(prompt, draft):
                let edit = try await sender.editPendingItem(
                    id: id,
                    prompt: prompt,
                    workerToken: draft.selectedModelId,
                    teamPresetId: draft.selectedTeam.presetId
                )
                guard edit.commandResult.ack.accepted else { return }
                let submit = try await sender.submitPendingItem(id: id)
                guard submit.commandResult.ack.accepted else { return }
                pendingPromptsByID[id] = prompt
            }
            await refreshHome()
        } catch {
            return
        }
    }

    private func removePendingItemLocally(
        id: String,
        from queue: inout PendingQueueJSON,
        prompts: inout [String: String]
    ) {
        var projects: [PendingQueueJSON.ProjectQueue] = []
        var total = 0
        for var group in queue.projects {
            group.pending.removeAll { $0.pendingItem.id == id }
            if group.running?.pendingItem.id == id {
                group.running = nil
            }
            total += group.pending.count
            if group.running != nil || !group.pending.isEmpty {
                projects.append(group)
            }
        }
        prompts.removeValue(forKey: id)
        queue = PendingQueueJSON(
            contractVersion: queue.contractVersion,
            totalPending: total,
            projects: projects
        )
    }

    private func rearmPreviewPendingItem(
        id: String,
        prompt: String,
        draft: IOSComposerDraft,
        queue: inout PendingQueueJSON,
        prompts: inout [String: String]
    ) {
        prompts[id] = prompt
        var projects = queue.projects
        let title = Self.previewThreadTitle(from: prompt)
        let excerpt = String(prompt.prefix(72))
        if let projectIndex = projects.firstIndex(where: { group in
            group.pending.contains { $0.pendingItem.id == id }
        }) {
            var group = projects[projectIndex]
            if let itemIndex = group.pending.firstIndex(where: { $0.pendingItem.id == id }) {
                var item = group.pending[itemIndex]
                item.pendingItem.promptExcerpt = excerpt
                item.pendingItem.title = title
                item.target.teamPresetId = draft.selectedTeam.presetId
                if let modelId = draft.selectedModelId {
                    item.target.modelIds = [modelId]
                    item.target.preferredModelIds = [modelId]
                }
                group.pending[itemIndex] = item
                projects[projectIndex] = group
            }
        } else if let firstProject = projects.first {
            var group = firstProject
            let item = Self.previewPendingItem(
                id: id,
                prompt: prompt,
                projectId: group.projectId,
                teamPresetId: draft.selectedTeam.presetId,
                modelId: draft.selectedModelId
            )
            group.pending.append(item)
            projects[0] = group
        }
        let total = projects.reduce(0) { $0 + $1.pending.count }
        queue = PendingQueueJSON(
            contractVersion: queue.contractVersion,
            totalPending: total,
            projects: projects
        )
    }

    private func mutatePreviewPending(
        _ transform: (inout PendingQueueJSON, inout [String: String]) -> Void
    ) {
        guard case .preview = connectionPhase else { return }
        transform(&pendingQueue, &pendingPromptsByID)
    }

    private func applyPendingQueueFromRelay(_ queue: PendingQueueJSON?) {
        guard case .connected = connectionPhase else { return }
        pendingQueue = queue ?? .empty
        cachePendingPromptExcerpts(from: pendingQueue)
    }

    private func cachePendingPromptExcerpts(from queue: PendingQueueJSON) {
        for group in queue.projects {
            let items = group.pending + [group.running].compactMap { $0 }
            for item in items where pendingPromptsByID[item.pendingItem.id] == nil {
                pendingPromptsByID[item.pendingItem.id] = item.pendingItem.promptExcerpt
            }
        }
    }

    private func seedPreviewPendingQueue() {
        let item1 = Self.previewPendingItem(
            id: "pending_preview_1",
            prompt: "Review the iOS pending screen when Opus is ready.",
            projectId: "proj_allnighter",
            teamPresetId: nil,
            modelId: "model_opus"
        )
        let item2 = Self.previewPendingItem(
            id: "pending_preview_2",
            prompt: "Write release notes for the inbox MVP.",
            projectId: "proj_allnighter",
            teamPresetId: "copy_landing",
            modelId: nil
        )
        let running = Self.previewPendingItem(
            id: "pending_preview_running",
            prompt: "Fix the layout bug in the header",
            projectId: "proj_allnighter",
            teamPresetId: nil,
            modelId: "model_sonnet",
            status: .running
        )
        pendingPromptsByID = [
            item1.pendingItem.id: "Review the iOS pending screen when Opus is ready.",
            item2.pendingItem.id: "Write release notes for the inbox MVP.",
            running.pendingItem.id: "Fix the layout bug in the header",
        ]
        pendingQueue = PendingQueueJSON(
            contractVersion: ContractRegistry.contractVersion,
            totalPending: 2,
            projects: [
                PendingQueueJSON.ProjectQueue(
                    projectId: "proj_allnighter",
                    projectName: "Allnighter",
                    running: running,
                    pending: [item1, item2]
                ),
            ]
        )
    }

    private static func previewPendingItem(
        id: String,
        prompt: String,
        projectId: String,
        teamPresetId: String?,
        modelId: String?,
        status: PendingItemJSON.ItemInfo.Status = .pending
    ) -> PendingItemJSON {
        PendingItemJSONMapper.previewItem(
            id: id,
            prompt: prompt,
            status: status,
            modelId: modelId,
            teamPresetId: teamPresetId
        )
    }

    private var homeStore: ConversationHomeStore?
    private var connectedClient: RemoteCloudClientAssembly.ConnectedClient?
    private var previewClient: MockiOSClient?
    private var deviceSession: DeviceSession?
    private var threadStore: ConversationThreadStore?
    private var activationSequence = 0
    private var previewCompletionGeneration = 0
    private var homePollTask: Task<Void, Never>?
    private var threadPollTask: Task<Void, Never>?

    private static let previewDoneMessage = "Done — open on your Mac for the full transcript."
    var composerThreadId: String?

    struct ComposerContinuationAgent: Equatable {
        var modelId: String
        var driverId: String
        var title: String
    }

    var composerContinuationAgent: ComposerContinuationAgent? {
        guard let threadId = composerThreadId,
              let snapshot = threadSnapshot,
              snapshot.id == threadId else {
            return nil
        }
        if let workerTurn = snapshot.turns.last(where: { $0.role == .assistant }),
           let workerId = workerTurn.modelId {
            return ComposerContinuationAgent(
                modelId: workerId,
                driverId: workerTurn.driverId ?? ConversationAgentPresentation.driverId(for: workerId),
                title: workerTurn.agentTitle ?? ConversationAgentPresentation.agentTitle(for: workerId)
            )
        }
        if case .preview = connectionPhase {
            let workerId = ConversationAgentPresentation.previewWorkerId
            return ComposerContinuationAgent(
                modelId: workerId,
                driverId: ConversationAgentPresentation.driverId(for: workerId),
                title: ConversationAgentPresentation.agentTitle(for: workerId)
            )
        }
        return nil
    }

    private static var isUITestingPreview: Bool { isIOSUITestingPreview() }

    static func unauthenticatedFallback() -> RemoteAppUnauthenticatedFallback {
        unauthenticatedFallback(isRemoteSignInEnabled: isRemoteSignInEnabled)
    }

    static func unauthenticatedFallback(
        isRemoteSignInEnabled: Bool
    ) -> RemoteAppUnauthenticatedFallback {
        isRemoteSignInEnabled ? .onboarding : .preview
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var isRemoteSignInEnabled: Bool {
        true
    }

    #if canImport(AuthenticationServices)
    private let appleSignInPresenter = RemoteAppleSignInPresenter()
    #endif
    private let supabaseSessionStore = RemoteSupabaseSessionStore()

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
        stopLivePolling()

        #if DEBUG
        if Self.isUITestingPreview {
            connectionPhase = .preview
            guard currentActivation == activationSequence else { return }
            await installPreviewClient()
            stopLivePolling()
            await refreshHome()
            await refreshConnectionDiagnosis()
            startLiveHomePolling()
            if let fixtureThreadId = IOSTestFixture.openThreadId {
                pendingOpenThreadId = fixtureThreadId
            }
            return
        }
        #endif

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
                startLiveHomePolling()
                return
            } catch {
                guard currentActivation == activationSequence else { return }
                connectionPhase = Self.connectionPhase(from: error)
            }
        }

        guard currentActivation == activationSequence else { return }
        switch Self.unauthenticatedFallback() {
        case .preview:
            await installPreviewClient()
            connectionPhase = .preview
            stopLivePolling()
            await refreshHome()
            await refreshConnectionDiagnosis()
            startLiveHomePolling()
            #if DEBUG
            if let fixtureThreadId = IOSTestFixture.openThreadId {
                pendingOpenThreadId = fixtureThreadId
            }
            #endif
        case .onboarding:
            connectionPhase = .needsConfiguration
            homeSnapshot = .empty
            homeStatus = .idle
        }
    }

    func signInWithApple() async {
        #if canImport(AuthenticationServices)
        guard let publicConfig = RemoteSupabasePublicConfig.load() else {
            connectionPhase = .failed("Remote relay is not configured — ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY is missing from this build.")
            return
        }

        connectionPhase = .connecting
        do {
            let deviceStore = RemoteDeviceCredentialStore()
            let material = try deviceStore.loadOrCreate(displayName: Self.defaultDeviceDisplayName())
            _ = try await RemoteAppleSignInService.signIn(
                presenter: appleSignInPresenter,
                publicConfig: publicConfig,
                role: .device(
                    deviceId: material.credentials.deviceId,
                    displayName: material.credentials.displayName
                ),
                sessionStore: supabaseSessionStore
            )
            await activate()
        } catch RemoteAppleSignInError.cancelled {
            connectionPhase = .needsConfiguration
        } catch {
            connectionPhase = .failed(Self.signInFailureMessage(for: error))
        }
        #else
        connectionPhase = .failed("Sign in with Apple is unavailable on this platform.")
        #endif
    }

    private static func signInFailureMessage(for error: Error) -> String {
        if let authError = error as? RemoteSupabaseAuthError {
            switch authError {
            case .http(let statusCode, _):
                if statusCode == 400 || statusCode == 401 {
                    return "Apple sign-in is not enabled for this app yet. Confirm Supabase Apple auth is configured."
                }
                return "Could not sign in (\(statusCode))."
            default:
                return "Could not sign in."
            }
        }
        return error.localizedDescription
    }

    func beginNewConversation() {
        composerThreadId = nil
        composerDraft = IOSComposerDraft()
    }

    func consumePendingOpenThread() {
        pendingOpenThreadId = nil
    }

    func setThreadPolling(threadId: String?, enabled: Bool) {
        threadPollTask?.cancel()
        threadPollTask = nil
        guard enabled, let threadId, showsHome else { return }
        threadPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard composerThreadId == threadId else { return }
                await loadThread(threadId: threadId)
                if threadSnapshot?.isActive != true, case .connected = connectionPhase { return }
            }
        }
    }

    private func startLiveHomePolling() {
        homePollTask?.cancel()
        guard showsHome else { return }
        homePollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await refreshHome()
            }
        }
    }

    private func stopLivePolling() {
        homePollTask?.cancel()
        homePollTask = nil
        threadPollTask?.cancel()
        threadPollTask = nil
    }

    func refreshHome() async {
        guard let homeStore else { return }
        await homeStore.refresh()
        homeSnapshot = homeStore.state.snapshot
        homeStatus = homeStore.state.status
        applyPendingQueueFromRelay(homeStore.state.pendingQueue)

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
        if case .connected = connectionPhase {
            // Live: Mac is truth. Do not flash stale disk cache before each fetch.
        } else {
            _ = restoreThreadCache(threadId: threadId)
        }
        await store.load(threadId: threadId)
        threadSnapshot = store.state.snapshot
        threadLoadStatus = store.state.status

        switch threadLoadStatus {
        case .loaded(let loadedId) where loadedId == threadId:
            if let snapshot = threadSnapshot {
                persistThreadCache(snapshot: snapshot, threadId: threadId)
                if snapshot.hasUnread {
                    homeSnapshot = homeSnapshot.clearingUnread(for: threadId)
                    if let throughTurnId = snapshot.readThroughTurnId {
                        await markThreadRead(threadId: threadId, throughTurnId: throughTurnId)
                    }
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
        guard !snapshot.turns.contains(where: { $0.id.hasPrefix("optimistic_") }) else {
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

    private func invalidateThreadCache(threadId: String) {
        guard let session = deviceSession else { return }
        try? threadDetailCache.clear(macAgentId: session.mac.macAgentId, threadId: threadId)
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
                if case .preview = connectionPhase {
                    settlePreviewActiveRun(threadId: snapshot.id, cancelled: true)
                } else {
                    await loadThread(threadId: snapshot.id)
                    await refreshHome()
                }
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
        let team = composerDraft.selectedTeam
        let existingThreadId = composerThreadId
        let knownThreadIds = existingThreadId == nil ? allThreadIds(in: homeSnapshot) : []
        let draft = WorkRequestDraft(
            prompt: trimmed,
            threadId: existingThreadId,
            teamPresetId: team.presetId,
            lane: team.lane,
            effort: composerDraft.effort,
            modelId: composerDraft.modelIdForSend(
                continuationWorkerId: composerContinuationAgent?.modelId
            )
        )

        do {
            _ = try await sender.send(draft)
            workRequestSendPhase = .idle

            if let threadId = existingThreadId {
                if case .preview = connectionPhase {
                    let workerTurnId = appendOptimisticSend(prompt: trimmed, threadId: threadId)
                    if let workerTurnId {
                        schedulePreviewRunCompletion(threadId: threadId, workerTurnId: workerTurnId)
                    }
                } else {
                    invalidateThreadCache(threadId: threadId)
                    await refreshHome()
                    await loadThread(threadId: threadId)
                }
            } else if case .preview = connectionPhase {
                let threadId = await appendPreviewNewThread(prompt: trimmed)
                composerThreadId = threadId
                await refreshHome()
                await loadThread(threadId: threadId)
                pendingOpenThreadId = threadId
                schedulePreviewRunCompletion(threadId: threadId, workerTurnId: "\(threadId)_worker")
            } else {
                if let threadId = await resolveLiveNewThreadId(knownIds: knownThreadIds, prompt: trimmed) {
                    composerThreadId = threadId
                    await loadThread(threadId: threadId)
                    pendingOpenThreadId = threadId
                }
            }
        } catch let error as WorkRequestSenderError where error == .emptyPrompt {
            workRequestSendPhase = .idle
        } catch {
            workRequestSendPhase = .failed(Self.workRequestFailureMessage(from: error))
        }
    }

    private func allThreadIds(in snapshot: ConversationListSnapshot) -> Set<String> {
        Set((snapshot.pinned + snapshot.projects.flatMap(\.conversations)).map(\.id))
    }

    private func resolveLiveNewThreadId(knownIds: Set<String>, prompt: String) async -> String? {
        let titleHint = Self.previewThreadTitle(from: prompt)
        for attempt in 0..<6 {
            await refreshHome()
            if let threadId = matchNewThread(knownIds: knownIds, titleHint: titleHint) {
                return threadId
            }
            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        return nil
    }

    private func matchNewThread(knownIds: Set<String>, titleHint: String) -> String? {
        let conversations = homeSnapshot.pinned + homeSnapshot.projects.flatMap(\.conversations)
        if let titled = conversations.first(where: { !knownIds.contains($0.id) && $0.title == titleHint }) {
            return titled.id
        }
        return conversations.first(where: { !knownIds.contains($0.id) })?.id
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

    private func appendOptimisticSend(prompt: String, threadId: String) -> String? {
        guard var snapshot = threadSnapshot, snapshot.id == threadId else { return nil }
        let workerId = composerDraft.workerIdForSend(
            continuationWorkerId: composerContinuationAgent?.modelId
        )
        let suffix = UUID().uuidString.prefix(8)
        let userTurn = ConversationThreadTurn(
            id: "optimistic_user_\(suffix)",
            role: .user,
            text: prompt,
            runId: nil,
            modelId: nil,
            driverId: nil,
            agentTitle: nil,
            isPending: false,
            isFailed: false,
            isTruncated: false,
            hasAttachments: false,
            hasFileReferences: false
        )
        let runId = "run_preview_optimistic_\(suffix)"
        let workerTurn = ConversationThreadTurn(
            id: "optimistic_worker_\(suffix)",
            role: .assistant,
            text: "Working on this on your Mac…",
            runId: runId,
            modelId: workerId,
            driverId: ConversationAgentPresentation.driverId(for: workerId),
            agentTitle: ConversationAgentPresentation.agentTitle(for: workerId),
            isPending: true,
            isFailed: false,
            isTruncated: false,
            hasAttachments: false,
            hasFileReferences: false
        )
        snapshot.turns.append(userTurn)
        snapshot.turns.append(workerTurn)
        snapshot.isActive = true
        snapshot.statusLabel = "Running on your Mac"
        threadSnapshot = snapshot
        threadStore?.applySnapshot(snapshot, threadId: threadId)
        return workerTurn.id
    }

    private func schedulePreviewRunCompletion(threadId: String, workerTurnId: String) {
        previewCompletionGeneration += 1
        let generation = previewCompletionGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard generation == previewCompletionGeneration else { return }
            completePreviewWorkerTurn(threadId: threadId, workerTurnId: workerTurnId)
        }
    }

    private func completePreviewWorkerTurn(threadId: String, workerTurnId: String) {
        guard case .preview = connectionPhase else { return }
        applyPreviewWorkerSettlement(
            threadId: threadId,
            workerTurnId: workerTurnId,
            text: Self.previewDoneMessage,
            cancelled: false
        )
    }

    private func settlePreviewActiveRun(threadId: String, cancelled: Bool) {
        guard let workerTurnId = threadSnapshot?.turns.last(where: \.isPending)?.id else { return }
        applyPreviewWorkerSettlement(
            threadId: threadId,
            workerTurnId: workerTurnId,
            text: cancelled ? "Stopped on your Mac." : Self.previewDoneMessage,
            cancelled: cancelled
        )
    }

    private func applyPreviewWorkerSettlement(
        threadId: String,
        workerTurnId: String,
        text: String,
        cancelled: Bool
    ) {
        guard var snapshot = threadSnapshot, snapshot.id == threadId else { return }
        guard let index = snapshot.turns.firstIndex(where: { $0.id == workerTurnId }) else { return }
        let turn = snapshot.turns[index]
        guard turn.isPending else { return }

        snapshot.turns[index] = ConversationThreadTurn(
            id: turn.id,
            role: turn.role,
            text: text,
            runId: cancelled ? nil : turn.runId,
            modelId: turn.modelId,
            driverId: turn.driverId,
            agentTitle: turn.agentTitle,
            isPending: false,
            isFailed: false,
            isTruncated: turn.isTruncated,
            hasAttachments: turn.hasAttachments,
            hasFileReferences: turn.hasFileReferences
        )
        snapshot.isActive = snapshot.turns.contains(where: \.isPending)
        snapshot.statusLabel = snapshot.isActive ? "Running on your Mac" : nil
        threadSnapshot = snapshot
        threadStore?.applySnapshot(snapshot, threadId: threadId)
    }

    private func appendPreviewNewThread(prompt: String) async -> String {
        guard let session = deviceSession,
              let client = previewClient else {
            return "preview-new-\(UUID().uuidString.prefix(8))"
        }

        let now = Date()
        let threadId = "preview-new-\(UUID().uuidString.prefix(8))"
        let title = Self.previewThreadTitle(from: prompt)
        let workerId = composerDraft.workerIdForSend(continuationWorkerId: nil)
        let runId = "run_preview_\(threadId)"

        let summary = RemoteThreadSummary(
            id: threadId,
            title: title,
            status: .active,
            projectId: "proj_allnighter",
            createdAt: now,
            updatedAt: now,
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

        do {
            let envelope = try await client.threadSnapshot(macId: session.mac.macAgentId)
            var threads = envelope.threads
            threads.insert(summary, at: 0)
            await client.setThreadSnapshot(
                RemoteThreadSnapshotEnvelope(threads: threads, serverTime: now),
                macId: session.mac.macAgentId
            )

            let detail = RemoteThreadDetail(
                summary: summary,
                turns: [
                    RemoteThreadTurnDetail(
                        id: "\(threadId)_user",
                        kind: .userMessage,
                        status: .done,
                        author: .user,
                        createdAt: now,
                        completedAt: now,
                        text: prompt
                    ),
                    RemoteThreadTurnDetail(
                        id: "\(threadId)_worker",
                        kind: .workerChat,
                        status: .running,
                        author: .worker,
                        createdAt: now,
                        text: "Working on this on your Mac…",
                        modelId: workerId,
                        runId: runId,
                        partialOutputTruncated: false
                    ),
                ]
            )
            let blob = try RemoteCrypto.seal(
                CoreJSON.encode(detail),
                to: RemoteCrypto.sealingPublicKeyBase64(session.deviceSealingKey.publicKey),
                sealedForKeyId: session.deviceId,
                contentType: RemoteThreadDetail.sealedContentType
            )
            await client.setSealedThreadDetail(
                blob,
                macId: session.mac.macAgentId,
                threadId: threadId,
                deviceId: session.deviceId
            )
        } catch {
            return threadId
        }

        return threadId
    }

    private static func previewThreadTitle(from prompt: String) -> String {
        let collapsed = prompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? prompt
        if collapsed.count <= 72 { return collapsed }
        return String(collapsed.prefix(69)) + "…"
    }

    private func installPreviewClient() async {
        let now = Date()
        let signingKey = Curve25519.Signing.PrivateKey()
        let sealingKey = Curve25519.KeyAgreement.PrivateKey()
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let macSigningPubkey = RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        let macSealingPubkey = RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
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

        var threadDetails: [String: [String: SealedBlob]] = [:]
        if let envelope = Self.previewThreadSnapshot(now: now)["mac_preview"] {
            for thread in envelope.threads {
                if let blob = try? Self.previewSealedThreadDetail(
                    summary: thread,
                    deviceId: deviceId,
                    sealingKey: sealingKey,
                    now: now
                ) {
                    threadDetails[thread.id] = [deviceId: blob]
                }
            }
        }

        let client = MockiOSClient(
            macs: [
                MacAgentRef(
                    macAgentId: macAgentId,
                    displayName: "Studio Mac",
                    agentSigningPubkey: macSigningPubkey,
                    agentSealingPubkey: macSealingPubkey,
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
                agentSigningPubkey: macSigningPubkey,
                agentSealingPubkey: macSealingPubkey,
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
        #if DEBUG
        if let envelope = Self.previewThreadSnapshot(now: now)["mac_preview"] {
            homeSnapshot = ConversationHomeMapper(projectNames: [
                "proj_allnighter": "Allnighter",
                "proj_inbox": "Inbox",
            ]).snapshot(from: envelope, now: now)
        }
        #endif
        try? await client.connect(
            account: RemoteAccountSession(accountId: accountId, provider: .apple),
            mode: ConnectionMode.cloudRelay
        )
        seedPreviewPendingQueue()
    }

    private static func previewSealedThreadDetail(
        summary: RemoteThreadSummary,
        deviceId: String,
        sealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: Date
    ) throws -> SealedBlob {
        let isRunning = summary.displayState == .running || summary.displayState == .pending
        let runId = isRunning ? "run_preview_\(summary.id)" : nil
        let detail = RemoteThreadDetail(
            summary: summary,
            turns: [
                RemoteThreadTurnDetail(
                    id: "\(summary.id)_user",
                    kind: .userMessage,
                    status: .done,
                    author: .user,
                    createdAt: summary.createdAt,
                    completedAt: summary.createdAt,
                    text: summary.title
                ),
                RemoteThreadTurnDetail(
                    id: "\(summary.id)_worker",
                    kind: .workerChat,
                    status: isRunning ? .running : .done,
                    author: .worker,
                    createdAt: summary.updatedAt,
                    completedAt: isRunning ? nil : summary.updatedAt,
                    text: isRunning
                        ? "Working on this on your Mac…"
                        : "Done — open on your Mac for the full transcript.",
                    modelId: ConversationAgentPresentation.previewWorkerId,
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
