import Foundation

// Help System — H0a: pure Core lookup/search/render over the installed help
// topics. No IO, no network, no live state (topics flagged `needsLiveCheck` route the
// caller to `alln team hello`/`alln doctor`). The `alln help` CLI adapter calls this so
// every caller projects the same truth. Search is deterministic local lexical scoring
// — no embeddings, no network.

/// A parsed `alln://` help selector.
public enum HelpSelector: Equatable, Sendable {
    case topic(String, section: String?)
    case schema(String)
    case error(String)
}

/// Builds + parses stable `alln://` refs an answering agent can cite.
public enum HelpRef {
    public static func help(_ topic: String, _ section: String? = nil) -> String {
        section.map { "alln://help/\(topic)#\($0)" } ?? "alln://help/\(topic)"
    }
    public static func schema(_ id: String) -> String { "alln://schema/\(id)" }
    public static func error(_ code: String) -> String { "alln://error/\(code)" }

    public static func parse(_ ref: String) -> HelpSelector? {
        guard ref.hasPrefix("alln://") else { return nil }
        let rest = String(ref.dropFirst("alln://".count))
        let parts = rest.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "help":
            // parts[1] is non-empty (guarded above), so split always yields ≥1 element →
            // hp[0] is safe. Keep this guarantee if this is ever refactored.
            let hp = parts[1].split(separator: "#", maxSplits: 1).map(String.init)
            return .topic(hp[0], section: hp.count > 1 ? hp[1] : nil)
        case "schema": return .schema(parts[1])
        case "error": return .error(parts[1])
        default: return nil
        }
    }
}

public struct HelpSitemapEntry: Codable, Sendable, Equatable {
    public var topicId: String
    public var title: String
    public var summary: String
    public init(topicId: String, title: String, summary: String) {
        self.topicId = topicId; self.title = title; self.summary = summary
    }
}

public struct HelpSearchHit: Codable, Sendable, Equatable {
    public var topicId: String
    public var sectionId: String?
    public var title: String
    public var summary: String
    public var snippet: String
    public var score: Double              // 0…1, relative to the top hit
    public var refs: [String]
    public var relatedCommands: [String]
    public var needsLiveCheck: Bool
}

public struct HelpSearchResult: Codable, Sendable, Equatable {
    public var query: String
    public var results: [HelpSearchHit]
    /// The top hit's one-line answer, so a host agent can answer without inventing wording.
    public var suggestedAnswerMarkdown: String?
    public var suggestedAnswerRefs: [String]
}

public struct HelpGetResult: Codable, Sendable, Equatable {
    public var found: Bool
    public var topic: HelpTopic?
    public var selectedSectionId: String?
    /// On a miss: nearby topic ids + the full sitemap, so the agent is never stranded.
    public var closeMatches: [String]
    public var sitemap: [HelpSitemapEntry]
}

public enum HelpService {
    public static func sitemap() -> [HelpSitemapEntry] {
        HelpTopicRegistry.topics.map { HelpSitemapEntry(topicId: $0.id, title: $0.title, summary: $0.summary) }
    }

    // MARK: - Search

    public static func search(_ query: String, limit: Int = 5) -> HelpSearchResult {
        let limit = max(1, limit)   // a degenerate limit must not yield an answer with zero hits
        let tokens = tokenize(query)
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliasHit = HelpTopicRegistry.canonicalTopicId(for: phrase)

        var scored: [(HelpTopic, Double)] = []
        for t in HelpTopicRegistry.topics {
            let idTitle = (t.id + " " + t.title).lowercased()
            let aliases = t.aliases.joined(separator: " ").lowercased()
            let summary = t.summary.lowercased()
            let body = t.bodyMarkdown.lowercased()
            var s = 0.0
            for tok in tokens {
                if idTitle.contains(tok) { s += 4 }
                if aliases.contains(tok) { s += 3 }
                if summary.contains(tok) { s += 2 }
                if body.contains(tok) { s += 1 }
                if t.relatedCommandNames.contains(where: { $0.lowercased().contains(tok) }) { s += 2 }
            }
            if t.id == aliasHit { s += 10 }   // exact topic/alias phrase wins decisively
            if s > 0 { scored.append((t, s)) }
        }
        scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }

        let maxScore = scored.first?.1 ?? 1
        let hits = scored.prefix(limit).map { (t, raw) in
            HelpSearchHit(
                topicId: t.id, sectionId: nil, title: t.title, summary: t.summary,
                snippet: snippet(for: t, tokens: tokens),
                score: maxScore > 0 ? (raw / maxScore) : 0,
                refs: [HelpRef.help(t.id)],
                relatedCommands: t.relatedCommandNames, needsLiveCheck: t.needsLiveCheck)
        }
        let top = scored.first?.0
        return HelpSearchResult(
            query: query, results: Array(hits),
            suggestedAnswerMarkdown: top?.summary,
            suggestedAnswerRefs: top.map { [HelpRef.help($0.id)] } ?? [])
    }

    // MARK: - Get

    public static func get(topic: String? = nil, ref: String? = nil, error: String? = nil) -> HelpGetResult {
        if let ref, let selector = HelpRef.parse(ref) { return resolve(selector) }
        if let topic {
            if let selector = HelpRef.parse(topic) { return resolve(selector) }  // topic may carry a ref
            if let id = HelpTopicRegistry.canonicalTopicId(for: topic), let t = HelpTopicRegistry.topic(id: id) {
                return hit(t, section: nil)
            }
            return miss(near: topic)
        }
        if let error { return resolve(.error(error)) }
        return miss(near: "")
    }

    private static func resolve(_ selector: HelpSelector) -> HelpGetResult {
        switch selector {
        case .topic(let id, let section):
            guard let t = HelpTopicRegistry.topic(id: id) else { return miss(near: id) }
            return hit(t, section: section.flatMap { t.section($0) != nil ? $0 : nil })
        case .schema(let id):
            guard let t = HelpTopicRegistry.topics.first(where: { $0.schemaRefs.contains(id) }) else { return miss(near: id) }
            return hit(t, section: nil)
        case .error(let code):
            guard let t = HelpTopicRegistry.topics.first(where: { $0.errorRefs.contains(code) }) else { return miss(near: code) }
            return hit(t, section: nil)
        }
    }

    /// Markdown projection shared by `alln help get --format md` and `alln docs <topic>`.
    public static func topicMarkdown(_ topic: HelpTopic) -> String {
        var out = "# \(topic.title)\n\n\(topic.summary)\n\n\(topic.bodyMarkdown)"
        for section in topic.sections {
            out += "\n\n## \(section.title)\n\n\(section.bodyMarkdown)"
        }
        if !topic.relatedCommandNames.isEmpty {
            out += "\n\n## Related commands\n"
            for command in topic.relatedCommandNames {
                out += "- `alln \(command)`\n"
            }
        }
        return out
    }

    /// Resolve a help topic the same way as `help get` (SSOT for `alln docs <topic>`).
    public static func docsMarkdown(topic: String) -> String? {
        guard let id = HelpTopicRegistry.canonicalTopicId(for: topic),
              let topic = HelpTopicRegistry.topic(id: id) else { return nil }
        return topicMarkdown(topic)
    }

    // MARK: - Helpers

    private static func hit(_ t: HelpTopic, section: String?) -> HelpGetResult {
        HelpGetResult(found: true, topic: t, selectedSectionId: section, closeMatches: [], sitemap: [])
    }

    private static func miss(near term: String) -> HelpGetResult {
        let close = term.isEmpty ? [] : search(term, limit: 3).results.map(\.topicId)
        return HelpGetResult(found: false, topic: nil, selectedSectionId: nil, closeMatches: close, sitemap: sitemap())
    }

    private static func tokenize(_ s: String) -> [String] {
        let stop: Set<String> = ["the", "a", "an", "to", "of", "is", "do", "i", "how", "my", "on", "in", "for", "this", "can", "what", "and", "with", "it"]
        return s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stop.contains($0) }
    }

    private static func snippet(for t: HelpTopic, tokens: [String]) -> String {
        let body = t.bodyMarkdown
        guard let tok = tokens.first(where: { body.lowercased().contains($0) }),
              let r = body.lowercased().range(of: tok) else { return t.summary }
        let start = body.index(r.lowerBound, offsetBy: -40, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(r.upperBound, offsetBy: 80, limitedBy: body.endIndex) ?? body.endIndex
        return "…" + body[start..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
