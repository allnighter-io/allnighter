import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteMacAgentServeAssemblyTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_750_400_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-serve-assembly-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAssemblyBuildsRemoteCoordinatorDependencies() async throws {
        let relay = MockRemoteMacRelay()
        let runsRoot = root.appendingPathComponent("runs", isDirectory: true)
        let executor = ServeAssemblyExecutor(now: now)
        let environment = RemoteSupabaseEnvironment(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable",
            accessToken: "mac-token",
            accountId: "acct_1",
            accountProvider: .apple,
            macAgentId: "mac_1",
            macDisplayName: "Studio"
        )

        let dependencies = try RemoteMacAgentServeAssembly.remoteDependencies(
            inputs: RemoteMacAgentServeAssembly.Inputs(
                environment: environment,
                executor: executor,
                readyModels: { [] },
                relay: relay,
                credentialStore: RemoteMacAgentCredentialStore(
                    fileURL: root.appendingPathComponent("mac_agent_credentials.json")
                ),
                trustedStore: TrustedRemoteStore(
                    fileURL: root.appendingPathComponent("trusted_remotes.json")
                ),
                dedupeStore: RemoteRequestDedupeStore(
                    fileURL: root.appendingPathComponent("seen_requests.json")
                ),
                runStore: RunStore(rootDirectory: runsRoot),
                threadStore: ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true)),
                journal: RemoteRunEventJournal(rootDirectory: runsRoot),
                eventCursorStore: RemoteMacAgentEventCursorStore(
                    fileURL: root.appendingPathComponent("event_cursor.json")
                )
            )
        )

        XCTAssertNotNil(dependencies.coordinator)
        let saved = try XCTUnwrap(try RemoteMacAgentCredentialStore(
            fileURL: root.appendingPathComponent("mac_agent_credentials.json")
        ).load())
        XCTAssertEqual(saved.macAgentId, "mac_1")
        XCTAssertEqual(saved.accountId, "acct_1")
    }
}

private actor ServeAssemblyExecutor: RemoteTeamCommandExecuting {
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        .failure(AsyncTeamStartRefusal(code: "TEST", message: "not implemented", preset: request.teamPresetId ?? ""))
    }

    func stopRun(runId: String) async -> TeamCancelResponse? {
        TeamCancelResponse(runId: runId, status: .cancelled, cancelledAt: now)
    }

    func stopAllRuns() async -> StopAllResult {
        StopAllResult(terminated: 0)
    }
}
