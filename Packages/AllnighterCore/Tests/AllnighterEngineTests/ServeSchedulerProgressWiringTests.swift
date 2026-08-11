import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Progress-wiring proofs for serve schedulers (ASR-S03e2b / ASR-S03e2c).
final class ServeSchedulerProgressWiringTests: XCTestCase {

  private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

  /// Must match `progress.registered(id:)` in `ServeDaemon.run` for wired schedulers.
  private let serveDaemonRegisteredIds: Set<String> = [
    "pendingWake",
    "pmTurnWake",
    "boostSeed",
    "vendorBackoff",
    "notifications",
    "capacityRefresh",
    "probeRecordRefresh",
  ]

  private final class RecordingSleeper: PendingWakeSleeper, @unchecked Sendable {
    var sleepCalls: [Date] = []

    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
      sleepCalls.append(until)
    }
  }

  private final class ThrowingSleeper: PendingWakeSleeper, @unchecked Sendable {
    let error: Error

    init(error: Error) {
      self.error = error
    }

    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
      throw error
    }
  }

  private final class AlwaysFailingFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
      at url: URL,
      withIntermediateDirectories createIntermediates: Bool,
      attributes: [FileAttributeKey: Any]? = nil
    ) throws {
      throw NSError(
        domain: "TestWriteFailure",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "injected write failure"]
      )
    }
  }

  private func tempCoordDir() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("progress-wiring-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func progressPair(
    coordDir: URL,
    fileManager: FileManager = .default
  ) -> (ServeRuntimeReceipts, ServeSchedulerProgress) {
    let receipts = ServeRuntimeReceipts(directory: coordDir)
    let progress = ServeSchedulerProgress(
      receipts: receipts,
      daemonId: "d-wiring",
      pid: 42,
      startedAt: t0,
      clock: { [t0] in t0 },
      fileManager: fileManager
    )
    return (receipts, progress)
  }

  private func rowState(
    receipts: ServeRuntimeReceipts,
    id: String
  ) -> ServeRuntimeReceipts.SchedulerState? {
    switch receipts.read() {
    case .present(_, _, _, let rows):
      return rows.first { $0.id == id }?.state
    default:
      return nil
    }
  }

  func testSchedulerProgressIdsMatchServeDaemonRegistration() {
    let schedulerIds: Set<String> = [
      PendingWakeScheduler.progressId,
      PMTurnWakeScheduler.progressId,
      BoostSeedScheduler.progressId,
      VendorBackoffReconciler.progressId,
      NotificationScheduler.progressId,
      CapacityRefreshScheduler.progressId,
      ProbeRecordRefreshScheduler.progressId,
    ]
    XCTAssertEqual(schedulerIds, serveDaemonRegisteredIds)
  }

  /// ASR-S03e2c §8 kill test — written first against e1e7448d catch-as-failed.
  /// Cancelling a running scheduler must leave its row not `failed`.
  func testCancellationDoesNotReportFailed() async throws {
    let coordDir = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: coordDir) }

    let settingsFile = coordDir.appendingPathComponent("boost_window_settings.json")
    let disabled = BoostWindowSettings(enabled: false)
    try CoreJSON.encode(disabled).write(to: settingsFile, options: .atomic)

    let (receipts, progress) = progressPair(coordDir: coordDir)
    progress.registered(id: BoostSeedScheduler.progressId)
    progress.waiting(id: BoostSeedScheduler.progressId, until: t0.addingTimeInterval(60))

    let scheduler = BoostSeedScheduler(
      settingsPersistence: BoostWindowSettingsPersistence(fileURL: settingsFile),
      registry: DriverRegistry([]),
      now: { [t0] in t0 },
      sleeper: ThrowingSleeper(error: CancellationError()),
      progress: progress
    )

    await scheduler.run { false }

    let state = rowState(receipts: receipts, id: BoostSeedScheduler.progressId)
    XCTAssertNotEqual(
      state,
      .failed,
      "cancellation must not be recorded as scheduler failure; got \(String(describing: state))"
    )
    XCTAssertEqual(state, .stopped)
  }

  /// Twin of the kill test: a genuine (non-cancellation) sleep error still reports `failed`.
  func testGenuineSleepErrorReportsFailed() async throws {
    let coordDir = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: coordDir) }

    let settingsFile = coordDir.appendingPathComponent("boost_window_settings.json")
    let disabled = BoostWindowSettings(enabled: false)
    try CoreJSON.encode(disabled).write(to: settingsFile, options: .atomic)

    let (receipts, progress) = progressPair(coordDir: coordDir)
    progress.registered(id: BoostSeedScheduler.progressId)

    let genuine = NSError(
      domain: "TestSleepFailure",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "disk full"]
    )
    let scheduler = BoostSeedScheduler(
      settingsPersistence: BoostWindowSettingsPersistence(fileURL: settingsFile),
      registry: DriverRegistry([]),
      now: { [t0] in t0 },
      sleeper: ThrowingSleeper(error: genuine),
      progress: progress
    )

    await scheduler.run { false }

    let row: ServeRuntimeReceipts.SchedulerRow?
    switch receipts.read() {
    case .present(_, _, _, let rows):
      row = rows.first { $0.id == BoostSeedScheduler.progressId }
    default:
      row = nil
    }
    XCTAssertEqual(row?.state, .failed)
    XCTAssertEqual(row?.lastError, "boostSeed sleep failed: disk full")
  }

  /// Real ServeDaemon exit path must not leave rows claiming a live working daemon.
  func testServeDaemonExitLeavesHonestReceipt() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
    try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)

    let store = ServeDaemonStore(directory: coordDir)
    let receipts = ServeRuntimeReceipts(directory: coordDir)
    let scheduler = PMTurnWakeScheduler(
      runsRootDirectory: root.appendingPathComponent("Runs", isDirectory: true),
      loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true),
      configurationStore: PMTurnWakeConfigurationStore(
        fileURL: root.appendingPathComponent("pm_turn_delivery.json")
      ),
      ledgerStore: PMTurnWakeReceiptLedgerStore(
        fileURL: root.appendingPathComponent("pm_turn_wake_receipts.json")
      ),
      pollInterval: 0.01
    )

    try await ServeDaemon(
      binaryVersion: "0.1.0",
      store: store,
      receipts: receipts,
      pmTurnWakeScheduler: scheduler
    ).run(untilShutdown: {})

    switch receipts.read() {
    case .present(_, _, _, let rows):
      XCTAssertFalse(rows.isEmpty, "registration rows should still be present")
      for row in rows {
        XCTAssertEqual(
          row.state,
          .stopped,
          "\(row.id) must be stopped after clean exit, got \(row.state)"
        )
      }
    case .absent:
      XCTFail("chose mark-all-stopped over clear; expected present stopped rows")
    case .unreadable(let reason):
      XCTFail("runtime.json unreadable after exit: \(reason)")
    }
  }

  /// cloudRelay stays `registered` while the daemon is alive — no invented passes.
  func testCloudRelayStaysRegisteredWhileAlive() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
    try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)

    let store = ServeDaemonStore(directory: coordDir)
    let receipts = ServeRuntimeReceipts(directory: coordDir)
    let remote = WiringRecordingRemoteCoordinator()
    let midRun = MidRunCloudRelayBox()

    try await ServeDaemon(
      binaryVersion: "0.1.0",
      store: store,
      receipts: receipts,
      remoteDependencies: .init(coordinator: remote)
    ).run(untilShutdown: {
      for _ in 0..<200 {
        if case .present(_, _, _, let rows) = receipts.read(),
           let cloud = rows.first(where: { $0.id == "cloudRelay" }) {
          midRun.state = cloud.state
          midRun.lastAttemptAt = cloud.lastAttemptAt
          midRun.lastSuccessAt = cloud.lastSuccessAt
          midRun.lastError = cloud.lastError
          break
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
    })

    XCTAssertEqual(midRun.state, .registered)
    XCTAssertNil(midRun.lastAttemptAt)
    XCTAssertNil(midRun.lastSuccessAt)
    XCTAssertNil(midRun.lastError)
  }

  func testPMTurnWakeReportsNonRegisteredState() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let (receipts, progress) = progressPair(coordDir: root)
    progress.registered(id: PMTurnWakeScheduler.progressId)

    let sleepUntil = t0.addingTimeInterval(5)
    let sleeper = RecordingSleeper()
    let scheduler = PMTurnWakeScheduler(
      runsRootDirectory: root.appendingPathComponent("Runs", isDirectory: true),
      loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true),
      configurationStore: PMTurnWakeConfigurationStore(
        fileURL: root.appendingPathComponent("pm_turn_delivery.json")
      ),
      ledgerStore: PMTurnWakeReceiptLedgerStore(
        fileURL: root.appendingPathComponent("pm_turn_wake_receipts.json")
      ),
      now: { [t0] in t0 },
      sleeper: sleeper,
      pollInterval: 5,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 50_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertEqual(sleeper.sleepCalls.first, sleepUntil)
    let state = rowState(receipts: receipts, id: PMTurnWakeScheduler.progressId)
    XCTAssertNotEqual(state, .registered)
    XCTAssertNotNil(state)
    XCTAssertEqual(PMTurnWakeScheduler.progressId, "pmTurnWake")
  }

  func testNotificationSchedulerReportsNonRegisteredState() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let (receipts, progress) = progressPair(coordDir: root)
    progress.registered(id: NotificationScheduler.progressId)

    let sleepUntil = t0.addingTimeInterval(10)
    let sleeper = RecordingSleeper()
    let scheduler = NotificationScheduler(
      threadStore: ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true)),
      runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
      loopStore: LoopStateStore(rootDirectory: root.appendingPathComponent("loops", isDirectory: true)),
      policyStore: NotificationPolicyStore(fileURL: root.appendingPathComponent("policy.json")),
      ledgerStore: DeliveredNotificationLedgerStore(fileURL: root.appendingPathComponent("delivered.json")),
      models: [],
      registry: DriverRegistry([]),
      now: { [t0] in t0 },
      sleeper: sleeper,
      pollInterval: 10,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 50_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertEqual(sleeper.sleepCalls.first, sleepUntil)
    let state = rowState(receipts: receipts, id: NotificationScheduler.progressId)
    XCTAssertNotEqual(state, .registered)
    XCTAssertNotNil(state)
    XCTAssertEqual(NotificationScheduler.progressId, "notifications")
  }

  func testBoostSeedReportsNonRegisteredState() async throws {
    let coordDir = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: coordDir) }

    let settingsFile = coordDir.appendingPathComponent("boost_window_settings.json")
    let disabled = BoostWindowSettings(enabled: false)
    try CoreJSON.encode(disabled).write(to: settingsFile, options: .atomic)

    let (receipts, progress) = progressPair(coordDir: coordDir)
    progress.registered(id: BoostSeedScheduler.progressId)

    let fallbackUntil = t0.addingTimeInterval(60)
    let sleeper = RecordingSleeper()
    let scheduler = BoostSeedScheduler(
      settingsPersistence: BoostWindowSettingsPersistence(fileURL: settingsFile),
      registry: DriverRegistry([]),
      now: { [t0] in t0 },
      sleeper: sleeper,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 50_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertEqual(sleeper.sleepCalls.first, fallbackUntil)
    let state = rowState(receipts: receipts, id: BoostSeedScheduler.progressId)
    XCTAssertEqual(state, .waiting)
  }

  func testVendorBackoffReportsNonRegisteredState() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let runsDir = root.appendingPathComponent("runs", isDirectory: true)
    try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
    let store = RunStore(rootDirectory: runsDir)
    let service = RunService(
      models: [],
      registry: DriverRegistry([]),
      runStore: store
    )

    let (receipts, progress) = progressPair(coordDir: root)
    progress.registered(id: VendorBackoffReconciler.progressId)

    let target = t0.addingTimeInterval(60)
    let sleeper = RecordingSleeper()
    let reconciler = VendorBackoffReconciler(
      runStore: store,
      runService: service,
      coordinatorId: "serve-test",
      now: { [t0] in t0 },
      sleeper: sleeper,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 50_000_000)
      flag.fire()
    }
    await reconciler.run { flag.isCancelled }

    XCTAssertEqual(sleeper.sleepCalls.first, target)
    let state = rowState(receipts: receipts, id: VendorBackoffReconciler.progressId)
    XCTAssertEqual(state, .waiting)
  }

  func testCapacityRefreshReportsNonRegisteredState() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let (receipts, progress) = progressPair(coordDir: root)
    progress.registered(id: CapacityRefreshScheduler.progressId)

    let sleepUntil = t0.addingTimeInterval(CapacityRefreshScheduler.tickInterval)
    let sleeper = RecordingSleeper()
    let scheduler = CapacityRefreshScheduler(
      featureSettings: CapacityFeatureSettingsPersistence(
        fileURL: root.appendingPathComponent("capacity_feature.json")
      ),
      historyStore: CapacityHistoryStore(rootDirectory: root),
      refresh: { _ in .durableSuccess },
      now: { [t0] in t0 },
      sleeper: sleeper,
      tickJitterSeconds: 0,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 50_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertEqual(sleeper.sleepCalls.first, sleepUntil)
    let state = rowState(receipts: receipts, id: CapacityRefreshScheduler.progressId)
    XCTAssertNotEqual(state, .registered)
    XCTAssertNotNil(state)
  }

  func testProbeRecordRefreshReportsNonRegisteredState() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let (receipts, progress) = progressPair(coordDir: root)
    progress.registered(id: ProbeRecordRefreshScheduler.progressId)

    let stale = ToolProbeRecord(
      driverId: "claude_code",
      status: .ready(version: "1"),
      lastProbeAt: t0.addingTimeInterval(-ProbeFreshnessGate.gateInterval - 1)
    )
    let sleepUntil = t0.addingTimeInterval(ProbeRecordRefreshScheduler.tickInterval)
    let sleeper = RecordingSleeper()
    let scheduler = ProbeRecordRefreshScheduler(
      recordLoader: { [stale] },
      smoke: {},
      now: { [t0] in t0 },
      sleeper: sleeper,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 50_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertEqual(sleeper.sleepCalls.first, sleepUntil)
    let state = rowState(receipts: receipts, id: ProbeRecordRefreshScheduler.progressId)
    XCTAssertNotEqual(state, .registered)
    XCTAssertNotNil(state)
  }

  func testBoostSeedFailingReporterDoesNotStopLoop() async throws {
    let coordDir = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: coordDir) }

    let settingsFile = coordDir.appendingPathComponent("boost_window_settings.json")
    let disabled = BoostWindowSettings(enabled: false)
    try CoreJSON.encode(disabled).write(to: settingsFile, options: .atomic)

    let (_, progress) = progressPair(
      coordDir: coordDir,
      fileManager: AlwaysFailingFileManager()
    )

    let fallbackUntil = t0.addingTimeInterval(60)
    let sleeper = RecordingSleeper()
    let scheduler = BoostSeedScheduler(
      settingsPersistence: BoostWindowSettingsPersistence(fileURL: settingsFile),
      registry: DriverRegistry([]),
      now: { [t0] in t0 },
      sleeper: sleeper,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 80_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertFalse(sleeper.sleepCalls.isEmpty)
    XCTAssertEqual(sleeper.sleepCalls.first, fallbackUntil)
  }

  func testVendorBackoffFailingReporterDoesNotStopLoop() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let runsDir = root.appendingPathComponent("runs", isDirectory: true)
    try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
    let store = RunStore(rootDirectory: runsDir)
    let service = RunService(
      models: [],
      registry: DriverRegistry([]),
      runStore: store
    )

    let (_, progress) = progressPair(
      coordDir: root,
      fileManager: AlwaysFailingFileManager()
    )

    let target = t0.addingTimeInterval(60)
    let sleeper = RecordingSleeper()
    let reconciler = VendorBackoffReconciler(
      runStore: store,
      runService: service,
      coordinatorId: "serve-test",
      now: { [t0] in t0 },
      sleeper: sleeper,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 80_000_000)
      flag.fire()
    }
    await reconciler.run { flag.isCancelled }

    XCTAssertFalse(sleeper.sleepCalls.isEmpty)
    XCTAssertEqual(sleeper.sleepCalls.first, target)
  }

  func testCapacityRefreshFailingReporterDoesNotStopLoop() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let (_, progress) = progressPair(
      coordDir: root,
      fileManager: AlwaysFailingFileManager()
    )

    let sleepUntil = t0.addingTimeInterval(CapacityRefreshScheduler.tickInterval)
    let sleeper = RecordingSleeper()
    let scheduler = CapacityRefreshScheduler(
      featureSettings: CapacityFeatureSettingsPersistence(
        fileURL: root.appendingPathComponent("capacity_feature.json")
      ),
      historyStore: CapacityHistoryStore(rootDirectory: root),
      refresh: { _ in .durableSuccess },
      now: { [t0] in t0 },
      sleeper: sleeper,
      tickJitterSeconds: 0,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 80_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertFalse(sleeper.sleepCalls.isEmpty)
    XCTAssertEqual(sleeper.sleepCalls.first, sleepUntil)
  }

  func testProbeRecordRefreshFailingReporterDoesNotStopLoop() async throws {
    let root = try tempCoordDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let (_, progress) = progressPair(
      coordDir: root,
      fileManager: AlwaysFailingFileManager()
    )

    let stale = ToolProbeRecord(
      driverId: "claude_code",
      status: .ready(version: "1"),
      lastProbeAt: t0.addingTimeInterval(-ProbeFreshnessGate.gateInterval - 1)
    )
    let sleepUntil = t0.addingTimeInterval(ProbeRecordRefreshScheduler.tickInterval)
    let sleeper = RecordingSleeper()
    let scheduler = ProbeRecordRefreshScheduler(
      recordLoader: { [stale] },
      smoke: {},
      now: { [t0] in t0 },
      sleeper: sleeper,
      progress: progress
    )

    let flag = ShutdownFlag()
    Task {
      try? await Task.sleep(nanoseconds: 80_000_000)
      flag.fire()
    }
    await scheduler.run { flag.isCancelled }

    XCTAssertFalse(sleeper.sleepCalls.isEmpty)
    XCTAssertEqual(sleeper.sleepCalls.first, sleepUntil)
  }
}

// MARK: - Local stubs (file-private)

private final class MidRunCloudRelayBox: @unchecked Sendable {
  var state: ServeRuntimeReceipts.SchedulerState?
  var lastAttemptAt: Date?
  var lastSuccessAt: Date?
  var lastError: String?
}

private final class WiringRecordingRemoteCoordinator: RemoteMacAgentCoordinating, @unchecked Sendable {
  private(set) var started = false

  func run(isCancelled: @escaping @Sendable () -> Bool) async {
    started = true
    while !isCancelled() && !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}
