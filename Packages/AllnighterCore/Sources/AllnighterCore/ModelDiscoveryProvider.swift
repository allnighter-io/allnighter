import Foundation

/// Per-driver live model discovery adapter. Discovery never runs from catalog load.
public protocol ModelDiscoveryProvider: Sendable {
  var driverId: String { get }
  func discover(invocation: ToolInvocation?) async -> ModelDiscoveryResult
}

public struct ModelDiscoveryResult: Codable, Sendable, Equatable {
  public var driverId: String
  public var candidates: [ModelDefinition]
  public var diagnostics: [ModelCatalogDiagnostic]
  public var discoveredAt: Date

  public init(
    driverId: String,
    candidates: [ModelDefinition] = [],
    diagnostics: [ModelCatalogDiagnostic] = [],
    discoveredAt: Date = Date()
  ) {
    self.driverId = driverId
    self.candidates = candidates
    self.diagnostics = diagnostics
    self.discoveredAt = discoveredAt
  }
}

/// Registry of discovery providers; empty until a driver implements list-models.
public enum ModelDiscoveryRegistry {
  public static func provider(for driverId: String) -> (any ModelDiscoveryProvider)? { nil }
}
