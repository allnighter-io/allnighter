import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Progress-wiring proofs for the four simple schedulers (ASR-S03e2b).
final class ServeSchedulerProgressWiringTests: XCTestCase {

  private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

  /// Must match `progress.registered(id:)` in `ServeDaemon.run` for this slice.
  private let serveDaemonRegisteredIds: Set<String> = [
    "boostSeed",
    "vendorBackoff",
    "capacityRefresh",
    "probeRecordRefresh",
  ]

  private final class RecordingSleeper: PendingWakeSleeper, @unchecked Sendable {
    var sleepCalls: [Date] = []

    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
      sleepCalls.append(until)
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
      BoostSeedScheduler.progressId,
      VendorBackoffReconciler.progressId,
      CapacityRefreshScheduler.progressId,
      ProbeRecordRefreshScheduler.progressId,
    ]
    XCTAssertEqual(schedulerIds, serveDaemonRegisteredIds)
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
