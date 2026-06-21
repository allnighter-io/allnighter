import CryptoKit
import Foundation
import AllnighterCore

public struct RemoteMacAgentRuntime: Sendable {
    public var agent: RemoteMacAgent
    public var coordinator: RemoteMacAgentCoordinator

    public init(agent: RemoteMacAgent, coordinator: RemoteMacAgentCoordinator) {
        self.agent = agent
        self.coordinator = coordinator
    }
}

public struct RemoteMacAgentBootstrap: Sendable {
    public var account: RemoteAccountSession
    public var macAgentId: String
    public var displayName: String
    public var relay: RemoteMacRelay
    public var trustedStore: TrustedRemoteStore
    public var dedupeStore: RemoteRequestDedupeStore
    public var runStore: RunStore
    public var journal: RemoteRunEventJournal
    public var executor: RemoteTeamCommandExecuting
    public var macSigningKey: Curve25519.Signing.PrivateKey
    public var macSealingKey: Curve25519.KeyAgreement.PrivateKey
    public var auditRecorder: any RemoteAuditRecording
    public var eventCursorStore: RemoteMacAgentEventCursorStore
    public var routerPolicy: RemoteCommandRouterPolicy
    public var pollPolicy: RemoteMacAgentPollPolicy
    public var sleeper: any RemoteMacAgentSleeping
    public var now: @Sendable () -> Date
    public var observe: (@Sendable (RemoteMacAgentPollEvent) -> Void)?
    public var skewWindow: TimeInterval
    public var commandBatchLimit: Int
    public var eventBatchLimit: Int

    public init(
        account: RemoteAccountSession,
        macAgentId: String,
        displayName: String,
        relay: RemoteMacRelay,
        trustedStore: TrustedRemoteStore,
        dedupeStore: RemoteRequestDedupeStore,
        runStore: RunStore,
        journal: RemoteRunEventJournal,
        executor: RemoteTeamCommandExecuting,
        macSigningKey: Curve25519.Signing.PrivateKey,
        macSealingKey: Curve25519.KeyAgreement.PrivateKey,
        auditRecorder: any RemoteAuditRecording = NoopRemoteAuditRecorder(),
        eventCursorStore: RemoteMacAgentEventCursorStore = RemoteMacAgentEventCursorStore(),
        routerPolicy: RemoteCommandRouterPolicy = .default,
        pollPolicy: RemoteMacAgentPollPolicy = RemoteMacAgentPollPolicy(),
        sleeper: any RemoteMacAgentSleeping = DefaultRemoteMacAgentSleeper(),
        now: @escaping @Sendable () -> Date = Date.init,
        observe: (@Sendable (RemoteMacAgentPollEvent) -> Void)? = nil,
        skewWindow: TimeInterval = 300,
        commandBatchLimit: Int = 100,
        eventBatchLimit: Int = 100
    ) {
        self.account = account
        self.macAgentId = macAgentId
        self.displayName = displayName
        self.relay = relay
        self.trustedStore = trustedStore
        self.dedupeStore = dedupeStore
        self.runStore = runStore
        self.journal = journal
        self.executor = executor
        self.macSigningKey = macSigningKey
        self.macSealingKey = macSealingKey
        self.auditRecorder = auditRecorder
        self.eventCursorStore = eventCursorStore
        self.routerPolicy = routerPolicy
        self.pollPolicy = pollPolicy
        self.sleeper = sleeper
        self.now = now
        self.observe = observe
        self.skewWindow = skewWindow
        self.commandBatchLimit = commandBatchLimit
        self.eventBatchLimit = eventBatchLimit
    }

    public func makeRuntime() -> RemoteMacAgentRuntime {
        let identity = RemoteMacAgentIdentity(
            account: account,
            macAgentId: macAgentId,
            displayName: displayName,
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey),
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
        )
        let router = RemoteCommandRouter(
            macAgentId: macAgentId,
            trustedStore: trustedStore,
            dedupeStore: dedupeStore,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: now,
            skewWindow: skewWindow,
            policy: routerPolicy
        )
        let eventSync = RemoteMacAgentEventSync(
            publisher: RemoteRunEventPublisher(
                accountId: account.accountId,
                macAgentId: macAgentId,
                journal: journal,
                relay: relay,
                signingKey: macSigningKey,
                batchLimit: eventBatchLimit
            ),
            cursorStore: eventCursorStore
        )
        let snapshotPublisher = RemoteSnapshotPublisher(
            accountId: account.accountId,
            macAgentId: macAgentId,
            service: RemoteSnapshotService(
                runStore: runStore,
                journal: journal,
                now: now
            ),
            relay: relay
        )
        let agent = RemoteMacAgent(
            identity: identity,
            relay: relay,
            trustedStore: trustedStore,
            router: router,
            auditRecorder: auditRecorder,
            eventSync: eventSync,
            snapshotPublisher: snapshotPublisher,
            now: now,
            commandBatchLimit: commandBatchLimit
        )
        let coordinator = RemoteMacAgentCoordinator(
            agent: agent,
            policy: pollPolicy,
            sleeper: sleeper,
            now: now,
            observe: observe
        )
        return RemoteMacAgentRuntime(agent: agent, coordinator: coordinator)
    }
}
