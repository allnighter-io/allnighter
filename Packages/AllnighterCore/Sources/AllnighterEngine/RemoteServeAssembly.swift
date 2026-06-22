import CryptoKit
import Foundation
import AllnighterCore

public enum RemoteMacAgentServeAssemblyError: Error, Equatable, Sendable {
    case missingAccessToken
    case missingAccountId
    case invalidSupabaseURL(String)
}

/// Wires the outbound remote Mac agent into `alln serve` when cloud relay env is present.
public enum RemoteMacAgentServeAssembly {
    public struct Inputs: Sendable {
        public var environment: RemoteSupabaseEnvironment
        public var executor: RemoteTeamCommandExecuting
        public var readyModels: @Sendable () -> [Model]
        public var relay: RemoteMacRelay?
        public var credentialStore: RemoteMacAgentCredentialStore
        public var trustedStore: TrustedRemoteStore
        public var dedupeStore: RemoteRequestDedupeStore
        public var runStore: RunStore
        public var threadStore: ThreadStore
        public var journal: RemoteRunEventJournal
        public var eventCursorStore: RemoteMacAgentEventCursorStore
        public var pollPolicy: RemoteMacAgentPollPolicy

        public init(
            environment: RemoteSupabaseEnvironment,
            executor: RemoteTeamCommandExecuting,
            readyModels: @escaping @Sendable () -> [Model],
            relay: RemoteMacRelay? = nil,
            credentialStore: RemoteMacAgentCredentialStore = RemoteMacAgentCredentialStore(),
            trustedStore: TrustedRemoteStore = TrustedRemoteStore(),
            dedupeStore: RemoteRequestDedupeStore = RemoteRequestDedupeStore(),
            runStore: RunStore = RunStore(),
            threadStore: ThreadStore = ThreadStore(),
            journal: RemoteRunEventJournal? = nil,
            eventCursorStore: RemoteMacAgentEventCursorStore? = nil,
            pollPolicy: RemoteMacAgentPollPolicy = RemoteMacAgentPollPolicy()
        ) {
            self.environment = environment
            self.executor = executor
            self.readyModels = readyModels
            self.relay = relay
            self.credentialStore = credentialStore
            self.trustedStore = trustedStore
            self.dedupeStore = dedupeStore
            self.runStore = runStore
            self.threadStore = threadStore
            self.journal = journal ?? RemoteRunEventJournal(rootDirectory: runStore.rootDirectory)
            self.eventCursorStore = eventCursorStore ?? RemoteMacAgentEventCursorStore(
                fileURL: AllnighterPaths.remote.appendingPathComponent("event_cursor.json")
            )
            self.pollPolicy = pollPolicy
        }
    }

    public static func remoteDependencies(
        inputs: Inputs
    ) throws -> ResidentCoordinator.RemoteDependencies {
        guard inputs.environment.hasMacAgentCredentials else {
            throw RemoteMacAgentServeAssemblyError.missingAccessToken
        }
        guard let account = inputs.environment.macAccountSession() else {
            throw RemoteMacAgentServeAssemblyError.missingAccountId
        }
        guard let accessToken = inputs.environment.accessToken else {
            throw RemoteMacAgentServeAssemblyError.missingAccessToken
        }

        let relay: any RemoteMacRelay
        if let injected = inputs.relay {
            relay = injected
        } else {
            relay = try SupabaseRemoteMacRelay(
                supabaseURL: inputs.environment.supabaseURL,
                publishableKey: inputs.environment.publishableKey,
                tokenProvider: StaticSupabaseAccessTokenProvider(token: accessToken)
            )
        }

        let credentials = try loadOrCreateMacCredentials(
            environment: inputs.environment,
            account: account,
            store: inputs.credentialStore
        )
        let signingKey = try credentials.keys.signingKey()
        let sealingKey = try credentials.keys.sealingKey()

        let bootstrap = RemoteMacAgentBootstrap(
            account: credentials.account,
            macAgentId: credentials.macAgentId,
            displayName: credentials.displayName,
            relay: relay,
            trustedStore: inputs.trustedStore,
            dedupeStore: inputs.dedupeStore,
            runStore: inputs.runStore,
            threadStore: inputs.threadStore,
            journal: inputs.journal,
            executor: inputs.executor,
            macSigningKey: signingKey,
            macSealingKey: sealingKey,
            eventCursorStore: inputs.eventCursorStore,
            pollPolicy: inputs.pollPolicy
        )

        let runtime = bootstrap.makeRuntime()
        return ResidentCoordinator.RemoteDependencies(coordinator: runtime.coordinator)
    }

    private static func loadOrCreateMacCredentials(
        environment: RemoteSupabaseEnvironment,
        account: RemoteAccountSession,
        store: RemoteMacAgentCredentialStore
    ) throws -> RemoteMacAgentCredentials {
        if let existing = try store.load(),
           existing.accountId == account.accountId,
           environment.macAgentId == nil || environment.macAgentId == existing.macAgentId {
            return existing
        }

        let generated = RemoteStoredKeyPair.generate()
        let credentials = RemoteMacAgentCredentials(
            macAgentId: environment.macAgentId ?? UUID().uuidString.lowercased(),
            displayName: environment.macDisplayName ?? ProcessInfo.processInfo.hostName,
            accountId: account.accountId,
            accountProvider: account.provider,
            keys: generated.material
        )
        try store.save(credentials)
        return credentials
    }
}
