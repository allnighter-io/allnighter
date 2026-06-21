import Foundation

public enum RemoteRunStateSynchronizerError: Error, Equatable, Sendable {
    case unsupportedProtocolVersion(expected: Int, actual: Int)
}

public struct RemoteRunStateSyncResult: Equatable, Sendable {
    public var state: RemoteRunViewState
    public var fetchedSnapshot: Bool
    public var receivedEventCount: Int
    public var appliedEventCount: Int

    public init(
        state: RemoteRunViewState,
        fetchedSnapshot: Bool,
        receivedEventCount: Int,
        appliedEventCount: Int
    ) {
        self.state = state
        self.fetchedSnapshot = fetchedSnapshot
        self.receivedEventCount = receivedEventCount
        self.appliedEventCount = appliedEventCount
    }
}

public enum RemoteRunStateSynchronizer {
    public static func sync(
        client: any RemoteClient,
        macId: String,
        current: RemoteRunViewState? = nil,
        forceSnapshot: Bool = false
    ) async throws -> RemoteRunStateSyncResult {
        var fetchedSnapshot = false
        var state: RemoteRunViewState
        let currentSeq = current?.lastSeq ?? 0

        if forceSnapshot || currentSeq <= 0 {
            let snapshot = try await client.snapshot(macId: macId, since: currentSeq)
            try validateProtocolVersion(snapshot.protocolVersion)
            state = RemoteRunViewState(snapshot: snapshot)
            fetchedSnapshot = true
        } else {
            state = current!
            try validateProtocolVersion(state.protocolVersion)
        }

        let appliedBefore = state.appliedEventIds.count
        var receivedEventCount = 0
        for await envelope in await client.stream(macId: macId, since: state.lastSeq) {
            receivedEventCount += 1
            RemoteRunReducer.apply(envelope, to: &state)
        }

        return RemoteRunStateSyncResult(
            state: state,
            fetchedSnapshot: fetchedSnapshot,
            receivedEventCount: receivedEventCount,
            appliedEventCount: state.appliedEventIds.count - appliedBefore
        )
    }

    private static func validateProtocolVersion(_ protocolVersion: Int) throws {
        guard protocolVersion == RemoteProtocol.currentMajor else {
            throw RemoteRunStateSynchronizerError.unsupportedProtocolVersion(
                expected: RemoteProtocol.currentMajor,
                actual: protocolVersion
            )
        }
    }
}
