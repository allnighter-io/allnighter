import Foundation

/// LR-S05 — Mac LOCAL RUNTIME section projection. Consumes the same overlay
/// path as `alln menu --json` / `alln models --json`; never doctor tag lists.
public enum LocalRuntimeSurfacePresenter {
  public enum InstalledBodies: String, Equatable, Sendable {
    case both
    case opencodeOnly
    case claudeCodeOnly
    case neither
  }

  public struct TagRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var modelLabel: String
    public var enabled: Bool
    public var seated: Bool
    public var readiness: String?
    public var advisory: String?
    public var capabilityUnknown: Bool

    public init(
      id: String,
      displayName: String,
      modelLabel: String,
      enabled: Bool,
      seated: Bool,
      readiness: String? = nil,
      advisory: String? = nil,
      capabilityUnknown: Bool = false
    ) {
      self.id = id
      self.displayName = displayName
      self.modelLabel = modelLabel
      self.enabled = enabled
      self.seated = seated
      self.readiness = readiness
      self.advisory = advisory
      self.capabilityUnknown = capabilityUnknown
    }
  }

  public struct Snapshot: Equatable, Sendable {
    public var sectionTitle: String
    public var installedBodies: InstalledBodies
    public var harnessLine: String
    public var detailLine: String?
    public var showsReadyDot: Bool
    public var showsBodySelector: Bool
    public var defaultBody: String
    public var defaultBodyLabel: String
    public var loading: Bool
    public var unobserved: Bool
    public var emptyObserved: Bool
    public var showsInstallAction: Bool
    public var installDriverId: String?
    /// Set when every visible row would print the same advisory. Per-row
    /// `TagRow.advisory` is then nil so the column is not three copies of one sentence.
    public var sharedAdvisory: String?
    public var tags: [TagRow]

    public init(
      sectionTitle: String,
      installedBodies: InstalledBodies,
      harnessLine: String,
      detailLine: String? = nil,
      showsReadyDot: Bool,
      showsBodySelector: Bool,
      defaultBody: String,
      defaultBodyLabel: String,
      loading: Bool,
      unobserved: Bool,
      emptyObserved: Bool,
      showsInstallAction: Bool,
      installDriverId: String? = nil,
      sharedAdvisory: String? = nil,
      tags: [TagRow]
    ) {
      self.sectionTitle = sectionTitle
      self.installedBodies = installedBodies
      self.harnessLine = harnessLine
      self.detailLine = detailLine
      self.showsReadyDot = showsReadyDot
      self.showsBodySelector = showsBodySelector
      self.defaultBody = defaultBody
      self.defaultBodyLabel = defaultBodyLabel
      self.loading = loading
      self.unobserved = unobserved
      self.emptyObserved = emptyObserved
      self.showsInstallAction = showsInstallAction
      self.installDriverId = installDriverId
      self.sharedAdvisory = sharedAdvisory
      self.tags = tags
    }
  }

  public static func build(
    registry: DriverRegistry,
    probeRecords: [ToolProbeRecord],
    parkedDriverIds: Set<String>,
    definitions: [ModelDefinition],
    now: Date = Date(),
    ollamaLocal: OllamaLocalRuntimeObserver.Snapshot? = nil,
    defaultBody: String? = nil,
    isLoading: Bool = false,
    g1Passed: Bool? = nil,
    g1PassedByTag: [String: Bool] = [:]
  ) -> Snapshot {
    let modelList = ModelListProjector.build(
      registry: registry,
      definitions: definitions,
      probeRecords: probeRecords,
      now: now,
      diagnostics: [],
      parkedDriverIds: parkedDriverIds,
      ollamaLocal: ollamaLocal
    )
    let menu = MenuCatalog.project(
      modelEntries: modelList.models,
      ollamaLocal: ollamaLocal,
      defaultBody: defaultBody
    )
    let installed = installedBodies(from: probeRecords)
    let resolvedDefault = defaultBody ?? menu.localRuntime?.defaultBody
      ?? LocalRuntimeDefaultBody.resolved()
    let defaultLabel = bodyLabel(resolvedDefault, registry: registry)
    let observed = menu.localRuntime != nil
    let tagCount = menu.localRuntime?.tags.count
    let neither = installed == .neither

    let harness = harnessLine(installed: installed, tagCount: tagCount, neither: neither)
    let detail = detailLine(
      snapshot: ollamaLocal,
      tagCount: tagCount,
      observed: observed,
      neither: neither
    )
    let rawTags = tagRows(
      menu: menu.localRuntime,
      modelEntries: modelList.models,
      snapshot: ollamaLocal,
      g1Passed: g1Passed,
      g1PassedByTag: g1PassedByTag
    )
    let shared = collapsedAdvisory(from: rawTags)
    let tags: [TagRow]
    if shared != nil {
      tags = rawTags.map { row in
        var copy = row
        copy.advisory = nil
        return copy
      }
    } else {
      tags = rawTags
    }
    let installTarget = neither ? firstMissingBody(from: probeRecords) : nil

    return Snapshot(
      sectionTitle: ChromeCopy.localRuntimeSection,
      installedBodies: installed,
      harnessLine: harness,
      detailLine: detail,
      showsReadyDot: observed && !neither,
      showsBodySelector: installed == .both,
      defaultBody: resolvedDefault,
      defaultBodyLabel: defaultLabel,
      loading: isLoading && !observed,
      unobserved: !observed && !isLoading,
      emptyObserved: observed && (tagCount == 0),
      showsInstallAction: neither,
      installDriverId: installTarget,
      sharedAdvisory: shared,
      tags: tags
    )
  }

  // MARK: - Private

  private static func installedBodies(
    from records: [ToolProbeRecord]
  ) -> InstalledBodies {
    let opencode = isBodyInstalled("opencode", records: records)
    let claude = isBodyInstalled("claude_code", records: records)
    switch (opencode, claude) {
    case (true, true): return .both
    case (true, false): return .opencodeOnly
    case (false, true): return .claudeCodeOnly
    case (false, false): return .neither
    }
  }

  private static func isBodyInstalled(
    _ driverId: String,
    records: [ToolProbeRecord]
  ) -> Bool {
    guard let record = records.first(where: { $0.driverId == driverId }) else {
      return false
    }
    if case .notInstalled = record.status { return false }
    return true
  }

  private static func firstMissingBody(from records: [ToolProbeRecord]) -> String {
    if !isBodyInstalled("opencode", records: records) { return "opencode" }
    return "claude_code"
  }

  private static func harnessLine(
    installed: InstalledBodies,
    tagCount: Int?,
    neither: Bool
  ) -> String {
    if neither {
      let count = tagCount.map { "\($0) models" } ?? ChromeCopy.localRuntimeModelsUnknown
      return "\(ChromeCopy.localRuntimeOllama) · \(count) · \(ChromeCopy.localRuntimeNeedsBody)"
    }
    switch installed {
    case .both: return ChromeCopy.localRuntimeViaBoth
    case .opencodeOnly: return ChromeCopy.localRuntimeViaOpenCode
    case .claudeCodeOnly: return ChromeCopy.localRuntimeViaClaudeCode
    case .neither: return ChromeCopy.localRuntimeNeedsBody
    }
  }

  private static func detailLine(
    snapshot: OllamaLocalRuntimeObserver.Snapshot?,
    tagCount: Int?,
    observed: Bool,
    neither: Bool
  ) -> String? {
    guard observed, !neither else { return nil }
    guard let version = snapshot?.ollamaVersion, let count = tagCount else { return nil }
    let noun = count == 1 ? "model" : "models"
    return "\(ChromeCopy.localRuntimeOllama) · \(version) · \(count) \(noun)"
  }

  private static func bodyLabel(_ driverId: String, registry: DriverRegistry) -> String {
    registry.manifest(id: driverId)?.displayName ?? driverId
  }

  /// Collapse only when every row would print the same sentence. Mixed
  /// G1 / window / unknown lines stay per-row — those are per-model facts.
  private static func collapsedAdvisory(from tags: [TagRow]) -> String? {
    guard tags.count >= 2 else { return nil }
    let reasons = tags.map(\.advisory)
    guard let first = reasons.first, let first else { return nil }
    return reasons.allSatisfy({ $0 == first }) ? first : nil
  }

  private static func tagRows(
    menu: MenuJSON.LocalRuntime?,
    modelEntries: [ModelListJSON.Entry],
    snapshot: OllamaLocalRuntimeObserver.Snapshot?,
    g1Passed: Bool?,
    g1PassedByTag: [String: Bool]
  ) -> [TagRow] {
    let entriesById = Dictionary(uniqueKeysWithValues: modelEntries.map { ($0.id, $0) })
    let residents = Dictionary(
      uniqueKeysWithValues: (snapshot?.residentModels ?? []).map { ($0.name, $0) }
    )
    let observed = snapshot != nil
    if let menu {
      return menu.tags.map { tag in
        let entry = entriesById[tag.id]
        let tagName = OpenCodeLocalSeatReadiness.ollamaTag(from: tag.label)
          ?? OpenCodeLocalSeatReadiness.ollamaTag(from: entry?.modelLabel ?? "")
        return makeTagRow(
          id: tag.id,
          tagName: tagName,
          modelLabel: entry?.modelLabel ?? tag.label,
          enabled: tag.enabled,
          seated: tag.seated,
          readiness: entry?.readiness,
          capabilityUnknown: tag.capabilityUnknown == true,
          observed: observed,
          residents: residents,
          g1Passed: g1Passed,
          g1PassedByTag: g1PassedByTag
        )
      }
    }
    // Unobserved: menu.localRuntime is absent. Seated local rows still paint
    // Unavailable — not "0 models" / "no tags".
    return modelEntries.compactMap { entry -> TagRow? in
      guard entry.seated == true,
            LocalRuntimePointerPresenter.isLocalRuntimeSeat(
              driverId: entry.driverId, modelLabel: entry.modelLabel)
      else { return nil }
      let tagName = OpenCodeLocalSeatReadiness.ollamaTag(from: entry.modelLabel)
      return makeTagRow(
        id: entry.id,
        tagName: tagName,
        modelLabel: entry.modelLabel,
        enabled: entry.enabled,
        seated: true,
        readiness: entry.readiness,
        capabilityUnknown: entry.capabilityUnknown == true,
        observed: false,
        residents: [:],
        g1Passed: g1Passed,
        g1PassedByTag: g1PassedByTag
      )
    }
  }

  private static func makeTagRow(
    id: String,
    tagName: String?,
    modelLabel: String,
    enabled: Bool,
    seated: Bool,
    readiness: String?,
    capabilityUnknown: Bool,
    observed: Bool,
    residents: [String: OllamaLocalRuntimeObserver.ResidentModel],
    g1Passed: Bool?,
    g1PassedByTag: [String: Bool]
  ) -> TagRow {
    let resident = tagName.flatMap { residents[$0] }
    let tagG1: Bool?
    if let tagName, let explicit = g1PassedByTag[tagName] {
      tagG1 = explicit
    } else {
      tagG1 = g1Passed
    }
    let advisory = LocalRuntimeAdvisory.reason(
      g1Passed: tagG1,
      servedContextWindow: resident?.servedContextWindow,
      tagObservedInPS: resident != nil
    )
    let rawTag = tagName
      ?? modelLabel.replacingOccurrences(of: "ollama/", with: "")
    let paintedReadiness: String?
    if !observed, seated {
      paintedReadiness = readiness ?? OllamaLocalDoctorReport.unavailableWord
    } else {
      paintedReadiness = readiness
    }
    return TagRow(
      id: id,
      displayName: OllamaLocalDisplayName.from(tag: rawTag),
      modelLabel: modelLabel,
      enabled: enabled,
      seated: seated,
      readiness: paintedReadiness,
      advisory: advisory,
      capabilityUnknown: capabilityUnknown
    )
  }
}
