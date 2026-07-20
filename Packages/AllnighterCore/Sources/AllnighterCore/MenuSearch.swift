import Foundation

/// One lexical hit from `MenuCatalog.search` / `alln help search` (MR-S05).
/// Zero or many cards; never a selected winner, confidence, or recommendation.
public struct MenuSearchHit: Codable, Sendable, Equatable {
    public var kind: String
    public var ref: String
    public var id: String
    public var title: String
    public var useWhen: String?
    public var dontUseWhen: String?
    public var runTemplate: String?
    public var validateTemplate: String?
    public var example: String?
    public var validateExample: String?
    public var active: Bool?
    public var blockedReason: String?
    public var enabled: Bool?
    public var ready: Bool?
    public var mutating: Bool?
    public var shape: String?

    public init(
        kind: String,
        ref: String,
        id: String,
        title: String,
        useWhen: String? = nil,
        dontUseWhen: String? = nil,
        runTemplate: String? = nil,
        validateTemplate: String? = nil,
        example: String? = nil,
        validateExample: String? = nil,
        active: Bool? = nil,
        blockedReason: String? = nil,
        enabled: Bool? = nil,
        ready: Bool? = nil,
        mutating: Bool? = nil,
        shape: String? = nil
    ) {
        self.kind = kind
        self.ref = ref
        self.id = id
        self.title = title
        self.useWhen = useWhen
        self.dontUseWhen = dontUseWhen
        self.runTemplate = runTemplate
        self.validateTemplate = validateTemplate
        self.example = example
        self.validateExample = validateExample
        self.active = active
        self.blockedReason = blockedReason
        self.enabled = enabled
        self.ready = ready
        self.mutating = mutating
        self.shape = shape
    }
}

/// Lexical retrieval over `MenuCatalog` records (MR-S05 / Menu_Not_Router Law 2).
public struct MenuSearchResult: Codable, Sendable, Equatable {
    public var query: String
    public var catalogRevision: String
    public var results: [MenuSearchHit]

    public init(query: String, catalogRevision: String, results: [MenuSearchHit]) {
        self.query = query
        self.catalogRevision = catalogRevision
        self.results = results
    }
}

/// CLI/agent envelope for `alln help search --json`. Same records as the live menu;
/// no suggested answer, next-tool plan, score, selected, confidence, or recommended.
public struct HelpSearchJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var catalogRevision: String
    public var query: String
    public var results: [MenuSearchHit]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        catalogRevision: String,
        query: String,
        results: [MenuSearchHit]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.catalogRevision = catalogRevision
        self.query = query
        self.results = results
    }
}
