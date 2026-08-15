import XCTest
@testable import AllnighterCore

/// LR-S05b — LOCAL RUNTIME section presenter (Mac half projection).
final class LocalRuntimeSurfacePresenterTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_754_000_000)
  private let registry = DriverRegistry([
    DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
    DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
  ])

  private let tagsPayload = """
  {"models":[
    {"name":"qwen3.8:27b-mlx","capabilities":["completion","tools"]},
    {"name":"qwen2.5-coder:7b","capabilities":["completion","tools"]},
    {"name":"qwen2.5-coder:1.5b","capabilities":["completion"]}
  ]}
  """

  func testBothBodiesShowsSelectorAndReadyDot() throws {
    let snapshot = try snapshotFromPayload()
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: readyProbeRecords(),
      parkedDriverIds: [],
      definitions: [],
      now: now,
      ollamaLocal: snapshot
    )
    XCTAssertEqual(surface.installedBodies, .both)
    XCTAssertTrue(surface.showsBodySelector)
    XCTAssertTrue(surface.showsReadyDot)
    XCTAssertEqual(surface.harnessLine, ChromeCopy.localRuntimeViaBoth)
    XCTAssertEqual(surface.tags.count, 3)
    XCTAssertTrue(surface.tags.allSatisfy { !$0.enabled })
    XCTAssertEqual(surface.defaultBody, "opencode")
  }

  func testPersistedDefaultBodyDoesNotRemintSeatedRows() throws {
    let snapshot = try snapshotFromPayload()
    let seated = ModelDefinition(
      id: OllamaLocalModelDiscoveryProvider.seatedID(tag: "qwen3.8:27b-mlx", bodyDriverId: "opencode"),
      displayName: "Qwen seated",
      modelLabel: "ollama/qwen3.8:27b-mlx",
      driverId: "opencode",
      role: .answerer,
      origin: .discovered,
      defaultEnabled: true,
      capabilities: ModelCapabilities()
    )
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: readyProbeRecords(),
      parkedDriverIds: [],
      definitions: [seated],
      now: now,
      ollamaLocal: snapshot,
      defaultBody: "claude_code"
    )
    XCTAssertEqual(surface.defaultBody, "claude_code")
    let row = try XCTUnwrap(surface.tags.first { $0.seated })
    XCTAssertEqual(row.id, seated.id)
  }

  func testOpenCodeOnlyOmitsSelector() throws {
    let snapshot = try snapshotFromPayload()
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: [
        readyRecord("opencode"),
        notInstalledRecord("claude_code"),
      ],
      parkedDriverIds: [],
      definitions: [],
      now: now,
      ollamaLocal: snapshot
    )
    XCTAssertEqual(surface.installedBodies, .opencodeOnly)
    XCTAssertFalse(surface.showsBodySelector)
    XCTAssertEqual(surface.harnessLine, ChromeCopy.localRuntimeViaOpenCode)
  }

  func testClaudeOnlyHarness() throws {
    let snapshot = try snapshotFromPayload()
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: [
        notInstalledRecord("opencode"),
        readyRecord("claude_code"),
      ],
      parkedDriverIds: [],
      definitions: [],
      now: now,
      ollamaLocal: snapshot
    )
    XCTAssertEqual(surface.installedBodies, .claudeCodeOnly)
    XCTAssertEqual(surface.harnessLine, ChromeCopy.localRuntimeViaClaudeCode)
  }

  func testNeitherStateHasNoReadyDotAndInstallTarget() throws {
    let snapshot = try snapshotFromPayload()
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: [
        notInstalledRecord("opencode"),
        notInstalledRecord("claude_code"),
      ],
      parkedDriverIds: [],
      definitions: [],
      now: now,
      ollamaLocal: snapshot
    )
    XCTAssertEqual(surface.installedBodies, .neither)
    XCTAssertFalse(surface.showsReadyDot)
    XCTAssertTrue(surface.showsInstallAction)
    XCTAssertEqual(surface.installDriverId, "opencode")
    XCTAssertTrue(surface.harnessLine.contains(ChromeCopy.localRuntimeNeedsBody))
  }

  func testUnobservedDoesNotClaimZeroModels() {
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: readyProbeRecords(),
      parkedDriverIds: [],
      definitions: [],
      now: now,
      ollamaLocal: nil
    )
    XCTAssertTrue(surface.unobserved)
    XCTAssertFalse(surface.emptyObserved)
    XCTAssertTrue(surface.tags.isEmpty)
  }

  func testAdvisoriesHonestUnknowns() throws {
    let tags = try XCTUnwrap(OllamaLocalRuntimeObserver.parseTags(Data(tagsPayload.utf8)))
    let snapshot = OllamaLocalRuntimeObserver.snapshot(
      observedAt: now,
      ollamaVersion: "0.32.12",
      localTags: tags,
      residentModels: [
        .init(name: "qwen2.5-coder:7b", servedContextWindow: 4096),
      ]
    )
    let surface = LocalRuntimeSurfacePresenter.build(
      registry: registry,
      probeRecords: readyProbeRecords(),
      parkedDriverIds: [],
      definitions: [],
      now: now,
      ollamaLocal: snapshot,
      g1Passed: nil
    )
    let g1Unknown = try XCTUnwrap(surface.tags.first { $0.displayName.contains("qwen2.5-coder:7b") })
    XCTAssertEqual(g1Unknown.advisory, LocalRuntimeAdvisory.g1Unknown)
    let windowLow = try XCTUnwrap(surface.tags.first { $0.displayName.contains("qwen2.5-coder:1.5b") })
    XCTAssertEqual(windowLow.advisory, LocalRuntimeAdvisory.g1Unknown)
    XCTAssertFalse(surface.tags.contains { $0.advisory?.contains("text-fakes") == true })
    XCTAssertFalse(surface.tags.contains { $0.advisory?.contains("too small") == true })
  }

  func testChromeCatalogProjectsLocalRuntimeRow() {
    let json = ChromeCatalog.project(screen: ChromeScreen.settingsCLIs.rawValue)
    let row = json.actions.first { $0.id == "local_runtime" }
    XCTAssertEqual(row?.controlLabel, ChromeCopy.localRuntimeSection)
    XCTAssertTrue(row?.facts.contains(where: { $0.contains(ChromeCopy.localRuntimePointerLabel(count: 3)) }) == true)
  }

  // MARK: - Helpers

  private func snapshotFromPayload() throws -> OllamaLocalRuntimeObserver.Snapshot {
    let tags = try XCTUnwrap(OllamaLocalRuntimeObserver.parseTags(Data(tagsPayload.utf8)))
    return OllamaLocalRuntimeObserver.snapshot(
      observedAt: now,
      ollamaVersion: "0.32.12",
      localTags: tags,
      residentModels: []
    )
  }

  private func readyProbeRecords() -> [ToolProbeRecord] {
    [readyRecord("opencode"), readyRecord("claude_code")]
  }

  private func readyRecord(_ driverId: String) -> ToolProbeRecord {
    ToolProbeRecord(driverId: driverId, status: .ready(version: "1.0"), version: "1.0", lastProbeAt: now)
  }

  private func notInstalledRecord(_ driverId: String) -> ToolProbeRecord {
    ToolProbeRecord(driverId: driverId, status: .notInstalled, version: nil, lastProbeAt: now)
  }
}
