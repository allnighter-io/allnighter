import Foundation

/// One typed-ref grammar (Law 5). Every ref emitted by menu/docs/errors resolves
/// on its stated consumer; near-miss spellings suggest the canonical form and
/// never become aliases.
public enum TypedRef {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case command, team, model, recipe
    }

    /// Surfaces that consume typed refs (or human command names for docs).
    public enum Consumer: String, Sendable, Equatable, CaseIterable {
        case menuShow
        case docs
    }

    public struct Emitted: Equatable, Sendable {
        public let ref: String
        public let kind: Kind
        public let consumers: [Consumer]
        public let source: String

        public init(ref: String, kind: Kind, consumers: [Consumer], source: String) {
            self.ref = ref
            self.kind = kind
            self.consumers = consumers
            self.source = source
        }
    }

    public enum DocsResolution: Equatable, Sendable {
        /// Help-topic markdown (same as `alln help get`).
        case helpMarkdown(String)
        /// One or more registry command specs (exact name or family prefix).
        case commands([ContractRegistry.CommandSpec])
        /// Bare dotted id that matches a command after `.`→` ` — suggest, do not alias.
        case nearMiss(query: String, suggestions: [String])
        /// Unknown topic; optional edit-distance suggestions.
        case notFound(query: String, suggestions: [String])
    }

    // MARK: - Parse

    /// Parse `command:teams.duplicate` → `(.command, "teams.duplicate")`.
    public static func parse(_ raw: String) -> (kind: Kind, id: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let kindRaw = String(trimmed[..<colon])
        let id = String(trimmed[trimmed.index(after: colon)...])
        guard let kind = Kind(rawValue: kindRaw), !id.isEmpty else { return nil }
        return (kind, id)
    }

    public static func commandRef(forCommandName name: String) -> String {
        MenuCatalog.commandRef(name)
    }

    public static func commandName(fromRefSuffix dots: String) -> String {
        MenuCatalog.commandName(fromRefSuffix: dots)
    }

    // MARK: - Docs topic resolution

    /// Resolve an `alln docs <topic>` selector: typed `command:` ref, quoted/spaced
    /// human command name, help topic id, or bare-dotted near-miss.
    public static func resolveDocsTopic(
        _ topic: String,
        registry: ContractRegistry = .milestone1
    ) -> DocsResolution {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .notFound(query: topic, suggestions: [])
        }

        if let parsed = parse(trimmed) {
            switch parsed.kind {
            case .command:
                let name = commandName(fromRefSuffix: parsed.id)
                let cmds = matchingCommands(name, registry: registry)
                if !cmds.isEmpty { return .commands(cmds) }
                return .notFound(
                    query: trimmed,
                    suggestions: nearestCommandSuggestions(to: name, registry: registry)
                )
            case .team, .model, .recipe:
                // Docs is not a consumer for non-command refs.
                return .notFound(query: trimmed, suggestions: [])
            }
        }

        if let markdown = HelpService.docsMarkdown(topic: trimmed) {
            return .helpMarkdown(markdown)
        }

        let cmds = matchingCommands(trimmed, registry: registry)
        if !cmds.isEmpty { return .commands(cmds) }

        if isBareDottedCommandNearMiss(trimmed, registry: registry) {
            let name = commandName(fromRefSuffix: trimmed)
            return .nearMiss(
                query: trimmed,
                suggestions: [commandRef(forCommandName: name), name]
            )
        }

        return .notFound(
            query: trimmed,
            suggestions: nearestCommandSuggestions(to: trimmed, registry: registry)
        )
    }

    /// Commands whose name equals `topic` or is a subcommand family (`topic ` prefix).
    public static func matchingCommands(
        _ topic: String,
        registry: ContractRegistry = .milestone1
    ) -> [ContractRegistry.CommandSpec] {
        registry.commands.filter {
            $0.milestone == .m1 && ($0.name == topic || $0.name.hasPrefix(topic + " "))
        }
    }

    /// Bare `teams.duplicate` (dots, no colon/space) that maps to a real command name.
    public static func isBareDottedCommandNearMiss(
        _ topic: String,
        registry: ContractRegistry = .milestone1
    ) -> Bool {
        guard topic.contains("."),
              !topic.contains(":"),
              !topic.contains(" ") else { return false }
        let name = commandName(fromRefSuffix: topic)
        return registry.commands.contains { $0.milestone == .m1 && $0.name == name }
    }

    // MARK: - Emitted-ref walker

    /// Collect concrete typed refs emitted by menu rows, registry examples, and
    /// error prose, with the consumers each kind must resolve on.
    public static func collectEmitted(
        registry: ContractRegistry = .milestone1,
        menu: MenuJSON? = nil
    ) -> [Emitted] {
        let projected = menu ?? MenuCatalog.project(registry: registry)
        var out: [Emitted] = []
        var seen = Set<String>()

        func append(_ ref: String, kind: Kind, consumers: [Consumer], source: String) {
            let key = "\(kind.rawValue)|\(ref)|\(source)"
            guard seen.insert(key).inserted else { return }
            out.append(Emitted(ref: ref, kind: kind, consumers: consumers, source: source))
        }

        for cmd in projected.commands {
            append(cmd.ref, kind: .command, consumers: [.menuShow, .docs], source: "menu.commands")
        }
        for team in projected.teams {
            append(team.ref, kind: .team, consumers: [.menuShow], source: "menu.teams")
        }
        for model in projected.models {
            append(model.ref, kind: .model, consumers: [.menuShow], source: "menu.models")
        }
        for recipe in projected.recipes {
            append(recipe.ref, kind: .recipe, consumers: [.menuShow], source: "menu.recipes")
        }
        append(
            projected.defaults.defaultTeamRef,
            kind: .team,
            consumers: [.menuShow],
            source: "menu.defaults"
        )

        for cmd in registry.commands where cmd.milestone == .m1 {
            if let example = cmd.example {
                for extracted in extractTypedRefs(from: example) {
                    append(
                        extracted.ref,
                        kind: extracted.kind,
                        consumers: consumers(for: extracted.kind),
                        source: "commands.\(cmd.name).example"
                    )
                }
            }
        }

        for example in registry.examples {
            for extracted in extractTypedRefs(from: example.command) {
                append(
                    extracted.ref,
                    kind: extracted.kind,
                    consumers: consumers(for: extracted.kind),
                    source: "examples.\(example.id)"
                )
            }
        }

        for error in registry.errors {
            for field in [error.agentAction, error.explain] {
                for extracted in extractTypedRefs(from: field) {
                    append(
                        extracted.ref,
                        kind: extracted.kind,
                        consumers: consumers(for: extracted.kind),
                        source: "errors.\(error.code)"
                    )
                }
            }
        }

        return out
    }

    /// Resolve `ref` on `consumer`. Throws `MenuRefError` for menu failures;
    /// returns false when docs cannot resolve the ref.
    @discardableResult
    public static func resolve(
        _ ref: String,
        on consumer: Consumer,
        registry: ContractRegistry = .milestone1
    ) throws -> Bool {
        switch consumer {
        case .menuShow:
            _ = try MenuCatalog.show(ref: ref, registry: registry)
            return true
        case .docs:
            switch resolveDocsTopic(ref, registry: registry) {
            case .commands(let cmds):
                return !cmds.isEmpty
            case .helpMarkdown:
                return true
            case .nearMiss, .notFound:
                return false
            }
        }
    }

    // MARK: - Internals

    private static func consumers(for kind: Kind) -> [Consumer] {
        switch kind {
        case .command: return [.menuShow, .docs]
        case .team, .model, .recipe: return [.menuShow]
        }
    }

    private static func nearestCommandSuggestions(
        to query: String,
        registry: ContractRegistry,
        limit: Int = 3
    ) -> [String] {
        let names = registry.commands.filter { $0.milestone == .m1 }.map(\.name)
        let near = ErrorDiscovery.nearestMatches(to: query, in: names, limit: limit)
        // Prefer typed ref + human name for each near match.
        var out: [String] = []
        for name in near {
            out.append(commandRef(forCommandName: name))
            out.append(name)
        }
        return Array(out.prefix(limit * 2))
    }

    /// Pull concrete `kind:id` tokens from prose/templates. Placeholders such as
    /// `team:<id>` are excluded by the id character class.
    public static func extractTypedRefs(from text: String) -> [(kind: Kind, ref: String)] {
        var results: [(Kind, String)] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        typedRefPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let kindRange = Range(match.range(at: 1), in: text),
                  let idRange = Range(match.range(at: 2), in: text),
                  let kind = Kind(rawValue: String(text[kindRange])) else { return }
            let id = String(text[idRange])
            results.append((kind, "\(kind.rawValue):\(id)"))
        }
        return results
    }

    private static let typedRefPattern = try! NSRegularExpression(
        pattern: #"(command|team|model|recipe):([A-Za-z0-9][A-Za-z0-9_.-]*)"#
    )
}
