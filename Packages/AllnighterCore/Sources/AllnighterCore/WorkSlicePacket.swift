import Foundation

/// Typed order the pair-programming control plane dispatches (Pair_Programming_Team §6).
/// Authored by the planner outside Allnighter; carried, gated, executed, and checked here.
public struct WorkSlicePacket: Codable, Sendable, Equatable {
    public struct ReadAnchor: Codable, Sendable, Equatable {
        public var path: String
        public var symbol: String?
        public var lineRange: String?

        public init(path: String, symbol: String? = nil, lineRange: String? = nil) {
            self.path = path
            self.symbol = symbol
            self.lineRange = lineRange
        }
    }

    public struct ResolvedSymbol: Codable, Sendable, Equatable {
        public var name: String
        public var signature: String
        public var definedAt: String

        public init(name: String, signature: String, definedAt: String) {
            self.name = name
            self.signature = signature
            self.definedAt = definedAt
        }
    }

    public struct Check: Codable, Sendable, Equatable {
        public var method: FixPacket.ProofMethod
        public var command: String?
        public var fixture: String?

        public init(method: FixPacket.ProofMethod, command: String? = nil, fixture: String? = nil) {
            self.method = method
            self.command = command
            self.fixture = fixture
        }
    }

    public enum Mode: String, Codable, Sendable {
        case implement
        case review
        case reviewVerify
    }

    /// Pre-inlined file chunks so the executor never tool-reads (Pair F4 / code_review).
    public struct InlinedSource: Codable, Sendable, Equatable {
        public var path: String
        public var lineRange: String?
        public var content: String

        public init(path: String, lineRange: String? = nil, content: String) {
            self.path = path
            self.lineRange = lineRange
            self.content = content
        }
    }

    public var schemaVersion: Int
    public var sliceId: String
    public var title: String
    public var readPaths: [ReadAnchor]
    public var resolvedSymbols: [ResolvedSymbol]
    public var estReadTokens: Int?
    public var intent: String
    public var skeleton: String?
    public var touchAllowlist: [String]
    public var check: Check
    public var maxRetries: Int
    public var stallTimeoutSeconds: Int
    public var compactionGraceSeconds: Int
    public var dangerFlags: [String]
    public var mode: Mode
    public var inlinedSources: [InlinedSource]
    /// Findings markdown inlined for verify pass (mode reviewVerify).
    public var inlinedFindings: String?

    /// Advisory code-review slice (initial or verify) — disjoint findings writes only.
    public var isAdvisoryReview: Bool { mode == .review || mode == .reviewVerify }
    public var isReviewMode: Bool { isAdvisoryReview }

    public init(
        schemaVersion: Int = 1,
        sliceId: String,
        title: String = "",
        readPaths: [ReadAnchor] = [],
        resolvedSymbols: [ResolvedSymbol] = [],
        estReadTokens: Int? = nil,
        intent: String = "",
        skeleton: String? = nil,
        touchAllowlist: [String] = [],
        check: Check = .init(method: .command),
        maxRetries: Int = 2,
        stallTimeoutSeconds: Int = 300,
        compactionGraceSeconds: Int = 180,
        dangerFlags: [String] = [],
        mode: Mode = .implement,
        inlinedSources: [InlinedSource] = [],
        inlinedFindings: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sliceId = sliceId
        self.title = title
        self.readPaths = readPaths
        self.resolvedSymbols = resolvedSymbols
        self.estReadTokens = estReadTokens
        self.intent = intent
        self.skeleton = skeleton
        self.touchAllowlist = touchAllowlist
        self.check = check
        self.maxRetries = maxRetries
        self.stallTimeoutSeconds = stallTimeoutSeconds
        self.compactionGraceSeconds = compactionGraceSeconds
        self.dangerFlags = dangerFlags
        self.mode = mode
        self.inlinedSources = inlinedSources
        self.inlinedFindings = inlinedFindings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sliceId = try c.decodeIfPresent(String.self, forKey: .sliceId) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        readPaths = try c.decodeIfPresent([ReadAnchor].self, forKey: .readPaths) ?? []
        resolvedSymbols = try c.decodeIfPresent([ResolvedSymbol].self, forKey: .resolvedSymbols) ?? []
        estReadTokens = try c.decodeIfPresent(Int.self, forKey: .estReadTokens)
        intent = try c.decodeIfPresent(String.self, forKey: .intent) ?? ""
        skeleton = try c.decodeIfPresent(String.self, forKey: .skeleton)
        touchAllowlist = try c.decodeIfPresent([String].self, forKey: .touchAllowlist) ?? []
        check = try c.decodeIfPresent(Check.self, forKey: .check) ?? .init(method: .command)
        maxRetries = try c.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 2
        stallTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .stallTimeoutSeconds) ?? 300
        compactionGraceSeconds = try c.decodeIfPresent(Int.self, forKey: .compactionGraceSeconds) ?? 180
        dangerFlags = try c.decodeIfPresent([String].self, forKey: .dangerFlags) ?? []
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .implement
        inlinedSources = try c.decodeIfPresent([InlinedSource].self, forKey: .inlinedSources) ?? []
        inlinedFindings = try c.decodeIfPresent(String.self, forKey: .inlinedFindings)
    }
}

/// Lifts a `WorkSlicePacket` from JSON on disk or a fenced ```work-slice-packet block.
public enum WorkSlicePacketParser {
    public enum Error: Swift.Error, Equatable {
        case fileNotFound(String)
        case unreadable(String)
        case noPacket
        case invalidJSON(String)
    }

    public static func parseFile(at path: String) throws -> WorkSlicePacket {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.fileNotFound(path)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        if url.pathExtension.lowercased() == "json" {
            return try decodeJSON(text)
        }
        if let packet = parse(fromMarkdown: text) { return packet }
        return try decodeJSON(text)
    }

    public static func parse(fromMarkdown markdown: String?) -> WorkSlicePacket? {
        guard let markdown else { return nil }
        if let json = FencedBlock.extract(from: markdown, fence: "work-slice-packet") {
            return try? CoreJSON.decode(WorkSlicePacket.self, from: Data(json.utf8))
        }
        return nil
    }

    private static func decodeJSON(_ text: String) throws -> WorkSlicePacket {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.noPacket }
        do {
            return try CoreJSON.decode(WorkSlicePacket.self, from: Data(trimmed.utf8))
        } catch {
            throw Error.invalidJSON(String(describing: error))
        }
    }
}
