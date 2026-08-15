import Foundation

/// First real `ModelDiscoveryProvider`: pulled local Ollama tags as candidate
/// seats. Body-agnostic — `claude_code` / `opencode` is chosen at enable, not
/// here. Reuses the OCL-S01a observer; does not open its own Ollama client.
///
/// Default posture: discover all local tags, enable none. That is a default,
/// not a gate. Sensors inform; they never refuse a seat on provenance or on
/// our opinion of capability.
public struct OllamaLocalModelDiscoveryProvider: ModelDiscoveryProvider {
    public var driverId: String { OllamaLocalRuntimeClient.sourceId }

    private let transport: (any OllamaLocalRuntimeClient.Transport)?
    private let isTestHost: Bool
    private let now: Date

    public init(
        transport: (any OllamaLocalRuntimeClient.Transport)? = nil,
        isTestHost: Bool = AllnighterSupportRoot.isRunningUnderTestHost,
        now: Date = Date()
    ) {
        self.transport = transport
        self.isTestHost = isTestHost
        self.now = now
    }

    public func discover(invocation: ToolInvocation?) async -> ModelDiscoveryResult {
        let snapshot = OllamaLocalDoctorReport.snapshotIfAllowed(
            transport: transport,
            observedAt: now,
            isTestHost: isTestHost
        )
        return Self.result(from: snapshot, discoveredAt: now)
    }

    /// Pure mapping from an already-observed snapshot. Tests use this so they
    /// never open a socket.
    public static func result(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        discoveredAt: Date
    ) -> ModelDiscoveryResult {
        let source = OllamaLocalRuntimeClient.sourceId
        guard let snapshot else {
            return ModelDiscoveryResult(
                driverId: source,
                candidates: [],
                diagnostics: [
                    ModelCatalogDiagnostic(
                        code: "OLLAMA_LOCAL_UNOBSERVED",
                        driverId: source,
                        message: "Ollama was not observed — no local tags discovered"
                    )
                ],
                discoveredAt: discoveredAt
            )
        }
        if snapshot.ollamaVersion == nil {
            return ModelDiscoveryResult(
                driverId: source,
                candidates: [],
                diagnostics: [
                    ModelCatalogDiagnostic(
                        code: "OLLAMA_LOCAL_UNREACHABLE",
                        driverId: source,
                        message: "Ollama not reachable — no local tags discovered"
                    )
                ],
                discoveredAt: discoveredAt
            )
        }
        let candidates = snapshot.localTags
            .filter(\.isCompletionCandidate)
            .map { candidate(for: $0.name, discoveredAt: discoveredAt) }
        var diagnostics: [ModelCatalogDiagnostic] = []
        if candidates.isEmpty {
            diagnostics.append(
                ModelCatalogDiagnostic(
                    code: "OLLAMA_LOCAL_NO_TAGS",
                    driverId: source,
                    message: "Ollama reachable with no local tags"
                )
            )
        }
        return ModelDiscoveryResult(
            driverId: source,
            candidates: candidates,
            diagnostics: diagnostics,
            discoveredAt: discoveredAt
        )
    }

    public static func candidate(for tag: String, discoveredAt: Date) -> ModelDefinition {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelDefinition(
            id: candidateID(tag: trimmed),
            displayName: trimmed,
            modelLabel: OllamaLocalDoctorReport.catalogLabelPrefix + trimmed,
            driverId: OllamaLocalRuntimeClient.sourceId,
            role: .answerer,
            origin: .discovered,
            defaultEnabled: false,
            capabilities: ModelCapabilities(),
            createdAt: discoveredAt,
            updatedAt: discoveredAt
        )
    }

    public static func candidateID(tag: String) -> ModelID {
        let slug = slugify(tag)
        return String("discovered_ollama_\(slug)".prefix(64))
    }

    /// Packet §0.2 default body. S02 reads `--body`; S01a only prints the string.
    public static let defaultEnableBodyDriverId = "opencode"

    public static func enableCommand(
        candidateID: ModelID,
        bodyDriverId: String = defaultEnableBodyDriverId
    ) -> String {
        "alln models enable \(candidateID) --body \(bodyDriverId)"
    }

    public static func seatedID(tag: String, bodyDriverId: String) -> ModelID {
        let slug = slugify(tag)
        return String("discovered_\(bodyDriverId)_\(slug)".prefix(64))
    }

    static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        for ch in lowered.unicodeScalars {
            if ch.isASCII && (ch.properties.isAlphabetic || ch.properties.numericType == .decimal) {
                out.append(Character(ch))
            } else {
                out.append("_")
            }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if out.isEmpty { out = "item" }
        return String(out.prefix(48))
    }
}
