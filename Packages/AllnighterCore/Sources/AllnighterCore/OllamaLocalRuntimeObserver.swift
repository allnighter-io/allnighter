import Foundation

/// Body-agnostic Ollama runtime observation.
///
/// This type observes; it does not name product readiness. Seat readiness is
/// projected in `OllamaLocalDoctorReport` (Available | Unavailable, per seat).
/// `/api/ps` is still required: served context feeds the §7.3 gate and local
/// `--pm` disclosure. Resident-in-memory is not a readiness word — Busy was
/// cut because it inverted that word's meaning (resident is the fast case,
/// and Ollama queues). Unobserved never becomes a guessed Available.
public enum OllamaLocalRuntimeObserver {

    public enum ObserveFailure: Sendable, Equatable {
        case version(OllamaLocalRuntimeClient.FetchFailure)
        case tags(OllamaLocalRuntimeClient.FetchFailure)
        case ps(OllamaLocalRuntimeClient.FetchFailure)
        case unparseableVersion
        case unparseableTags
        case unparseablePs
    }

    public struct LocalTag: Sendable, Equatable {
        public let name: String
        /// Declared `/api/tags` `capabilities`. `nil` means the field was
        /// absent or unparseable — capability-unknown, not "not completion".
        public let capabilities: [String]?

        public init(name: String, capabilities: [String]? = nil) {
            self.name = name
            self.capabilities = capabilities
        }

        /// Hide only when capabilities are declared and omit `completion`.
        /// Absence of the field stays visible (Local Runtime Surface §2.3).
        public var isCompletionCandidate: Bool {
            guard let capabilities else { return true }
            return capabilities.contains("completion")
        }

        public var capabilityUnknown: Bool { capabilities == nil }
    }

    public struct ResidentModel: Sendable, Equatable {
        public let name: String
        /// Served window from `/api/ps` top-level `context_length`. Nil when
        /// that field is absent — never filled from advertised max.
        public let servedContextWindow: Int?

        public init(name: String, servedContextWindow: Int?) {
            self.name = name
            self.servedContextWindow = servedContextWindow
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public let sourceId: String
        public let observedAt: Date
        public let ollamaVersion: String?
        public let localTags: [LocalTag]
        public let residentModels: [ResidentModel]
        public let observeFailure: ObserveFailure?

        public init(
            sourceId: String = OllamaLocalRuntimeClient.sourceId,
            observedAt: Date,
            ollamaVersion: String? = nil,
            localTags: [LocalTag] = [],
            residentModels: [ResidentModel] = [],
            observeFailure: ObserveFailure? = nil
        ) {
            self.sourceId = sourceId
            self.observedAt = observedAt
            self.ollamaVersion = ollamaVersion
            self.localTags = localTags
            self.residentModels = residentModels
            self.observeFailure = observeFailure
        }
    }

    /// Requires an injected transport. There is no default live session on
    /// this path — tests must not reach a real Ollama.
    public static func observe(
        transport: any OllamaLocalRuntimeClient.Transport,
        timeout: TimeInterval = OllamaLocalRuntimeClient.defaultTimeout,
        observedAt: Date
    ) -> Snapshot {
        let versionResult = OllamaLocalRuntimeClient.get(
            path: OllamaLocalRuntimeClient.versionPath,
            timeout: timeout,
            transport: transport
        )
        let versionBody: Data
        switch versionResult {
        case .success(let success):
            versionBody = success.data
        case .failure(let failure):
            return failed(observedAt: observedAt, failure: .version(failure))
        }
        guard let ollamaVersion = parseVersion(versionBody) else {
            return failed(observedAt: observedAt, failure: .unparseableVersion)
        }

        let tagsResult = OllamaLocalRuntimeClient.get(
            path: OllamaLocalRuntimeClient.tagsPath,
            timeout: timeout,
            transport: transport
        )
        let tagsBody: Data
        switch tagsResult {
        case .success(let success):
            tagsBody = success.data
        case .failure(let failure):
            return failed(
                observedAt: observedAt,
                ollamaVersion: ollamaVersion,
                failure: .tags(failure)
            )
        }
        guard let localTags = parseTags(tagsBody) else {
            return failed(
                observedAt: observedAt,
                ollamaVersion: ollamaVersion,
                failure: .unparseableTags
            )
        }

        let psResult = OllamaLocalRuntimeClient.get(
            path: OllamaLocalRuntimeClient.psPath,
            timeout: timeout,
            transport: transport
        )
        let psBody: Data
        switch psResult {
        case .success(let success):
            psBody = success.data
        case .failure(let failure):
            return failed(
                observedAt: observedAt,
                ollamaVersion: ollamaVersion,
                localTags: localTags,
                failure: .ps(failure)
            )
        }
        guard let residentModels = parsePs(psBody) else {
            return failed(
                observedAt: observedAt,
                ollamaVersion: ollamaVersion,
                localTags: localTags,
                failure: .unparseablePs
            )
        }

        return snapshot(
            observedAt: observedAt,
            ollamaVersion: ollamaVersion,
            localTags: localTags,
            residentModels: residentModels
        )
    }

    /// Pure assembly of already-parsed observations. Does not invent
    /// availability — that is `OllamaLocalDoctorReport.readinessWord`.
    public static func snapshot(
        observedAt: Date,
        ollamaVersion: String,
        localTags: [LocalTag],
        residentModels: [ResidentModel]
    ) -> Snapshot {
        Snapshot(
            observedAt: observedAt,
            ollamaVersion: ollamaVersion,
            localTags: localTags,
            residentModels: residentModels
        )
    }

    public static func parseVersion(_ data: Data) -> String? {
        guard let root = jsonObject(data),
              let version = root["version"] as? String
        else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Local tags only. Advertised context fields on the tag object are ignored.
    /// Cloud entries are dropped when `/api/tags` sets a non-empty `remote_host`
    /// or `remote_model` (Ollama `ListModelResponse`). Name suffixes are not a
    /// locality signal and are not filtered.
    public static func parseTags(_ data: Data) -> [LocalTag]? {
        guard let root = jsonObject(data),
              let models = root["models"] as? [Any]
        else { return nil }
        var tags: [LocalTag] = []
        for entry in models {
            guard let obj = entry as? [String: Any],
                  let name = modelName(obj)
            else { continue }
            if isRemoteTag(obj) { continue }
            tags.append(LocalTag(name: name, capabilities: parseCapabilities(obj)))
        }
        return tags
    }

    /// `nil` when the field is missing or not a JSON array — unobserved, not empty.
    /// A present array (including `[]`) is a declared set.
    static func parseCapabilities(_ obj: [String: Any]) -> [String]? {
        guard obj.keys.contains("capabilities") else { return nil }
        guard let raw = obj["capabilities"] as? [Any] else { return nil }
        return raw.compactMap { $0 as? String }
    }

    /// Resident models. Served context is top-level `context_length` only.
    public static func parsePs(_ data: Data) -> [ResidentModel]? {
        guard let root = jsonObject(data),
              let models = root["models"] as? [Any]
        else { return nil }
        var residents: [ResidentModel] = []
        for entry in models {
            guard let obj = entry as? [String: Any],
                  let name = modelName(obj)
            else { continue }
            if isRemoteTag(obj) { continue }
            let served = intValue(obj["context_length"])
            residents.append(ResidentModel(name: name, servedContextWindow: served))
        }
        return residents
    }

    private static func failed(
        observedAt: Date,
        ollamaVersion: String? = nil,
        localTags: [LocalTag] = [],
        residentModels: [ResidentModel] = [],
        failure: ObserveFailure
    ) -> Snapshot {
        Snapshot(
            observedAt: observedAt,
            ollamaVersion: ollamaVersion,
            localTags: localTags,
            residentModels: residentModels,
            observeFailure: failure
        )
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Ollama 0.32+ marks cloud/remote list rows with these fields. Missing or
    /// empty values are not an observation of locality — only a present
    /// non-empty string is an observation of remote provenance.
    private static func isRemoteTag(_ obj: [String: Any]) -> Bool {
        nonemptyString(obj["remote_host"]) != nil
            || nonemptyString(obj["remote_model"]) != nil
    }

    private static func nonemptyString(_ any: Any?) -> String? {
        guard let value = any as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func modelName(_ obj: [String: Any]) -> String? {
        if let name = obj["name"] as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let model = obj["model"] as? String {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.intValue
        }
        if let i = any as? Int { return i }
        return nil
    }
}
