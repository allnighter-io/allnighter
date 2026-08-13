import Foundation

/// Body-agnostic Ollama runtime observation.
///
/// v1 readiness is three words only (`Unavailable` | `Idle` | `Busy`):
/// loaded in `/api/ps` ⇒ Busy; reachable with local tags and nothing loaded ⇒
/// Idle; down, unobserved, or no usable model ⇒ Unavailable.
/// Unobserved never becomes a guessed Busy. Served context is the running
/// model's `/api/ps` `context_length` only — never advertised `context_length`
/// from tags or `details`.
public enum OllamaLocalRuntimeObserver {

    public enum Readiness: String, Sendable, Equatable {
        case unavailable = "Unavailable"
        case idle = "Idle"
        case busy = "Busy"
    }

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

        public init(name: String) {
            self.name = name
        }
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
        public let readiness: Readiness
        public let observedAt: Date
        public let ollamaVersion: String?
        public let localTags: [LocalTag]
        public let residentModels: [ResidentModel]
        public let observeFailure: ObserveFailure?

        public init(
            sourceId: String = OllamaLocalRuntimeClient.sourceId,
            readiness: Readiness,
            observedAt: Date,
            ollamaVersion: String? = nil,
            localTags: [LocalTag] = [],
            residentModels: [ResidentModel] = [],
            observeFailure: ObserveFailure? = nil
        ) {
            self.sourceId = sourceId
            self.readiness = readiness
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
            return unavailable(observedAt: observedAt, failure: .version(failure))
        }
        guard let ollamaVersion = parseVersion(versionBody) else {
            return unavailable(observedAt: observedAt, failure: .unparseableVersion)
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
            return unavailable(
                observedAt: observedAt,
                ollamaVersion: ollamaVersion,
                failure: .tags(failure)
            )
        }
        guard let localTags = parseTags(tagsBody) else {
            return unavailable(
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
            return unavailable(
                observedAt: observedAt,
                ollamaVersion: ollamaVersion,
                localTags: localTags,
                failure: .ps(failure)
            )
        }
        guard let residentModels = parsePs(psBody) else {
            return unavailable(
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

    /// Pure mapping: given already-parsed observations, never guesses Busy.
    public static func snapshot(
        observedAt: Date,
        ollamaVersion: String,
        localTags: [LocalTag],
        residentModels: [ResidentModel]
    ) -> Snapshot {
        let readiness: Readiness
        if !residentModels.isEmpty {
            readiness = .busy
        } else if !localTags.isEmpty {
            readiness = .idle
        } else {
            readiness = .unavailable
        }
        return Snapshot(
            readiness: readiness,
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
            tags.append(LocalTag(name: name))
        }
        return tags
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
            let served = intValue(obj["context_length"])
            residents.append(ResidentModel(name: name, servedContextWindow: served))
        }
        return residents
    }

    private static func unavailable(
        observedAt: Date,
        ollamaVersion: String? = nil,
        localTags: [LocalTag] = [],
        residentModels: [ResidentModel] = [],
        failure: ObserveFailure
    ) -> Snapshot {
        Snapshot(
            readiness: .unavailable,
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
