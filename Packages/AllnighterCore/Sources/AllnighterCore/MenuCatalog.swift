#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Core-owned live menu projection (MR-S01). One atomic Tier-1 catalog + Tier-2 hydrate.
public enum MenuCatalog {
    public static let detailTemplate = "alln menu show {ref} --json"

    /// Project the compact agent front door from registry + live catalogs.
    public static func project(
        registry: ContractRegistry = .milestone1,
        teams: [TeamPreset]? = nil,
        modelEntries: [ModelListJSON.Entry]? = nil,
        recipes: [RecipeCatalog.Recipe]? = nil,
        detailed: Bool = false,
        defaultModelId: String? = nil,
        capacity: MenuJSON.Capacity? = nil,
        update: ReleaseUpdateInfo? = nil
    ) -> MenuJSON {
        let teamList = (teams ?? TeamCatalog.all.filter { !$0.isLabTeam })
            .sorted { $0.id < $1.id }
        let models: [ModelListJSON.Entry]
        if let modelEntries {
            models = modelEntries.sorted { $0.id < $1.id }
        } else {
            models = builtInModelEntries().filter(\.enabled).sorted { $0.id < $1.id }
        }
        let recipeList = (recipes ?? RecipeCatalog.list()).sorted { $0.id < $1.id }

        let publicCommands = registry.commands
            .filter { $0.milestone == .m1 && $0.visibility == .public }
            .sorted { $0.name < $1.name }

        var effectProfiles: [String: ContractRegistry.EffectProfile] = [:]
        let commandRows: [MenuJSON.Command] = publicCommands.map { spec in
            let key = spec.effects.profileKey
            effectProfiles[key] = spec.effects
            return MenuJSON.Command(
                ref: commandRef(spec.name),
                name: spec.name,
                effectsRef: key
            )
        }

        let recipesById = Dictionary(uniqueKeysWithValues: registry.examples.map { ($0.id, $0) })
        let actionSpecs = publicCommands.filter(\.menuAction)
        let actions: [MenuJSON.Action] = actionSpecs.map { spec in
            guard let authored = MenuSelectionCopy.action(spec.name) else {
                preconditionFailure(
                    "MenuCatalog: menuAction '\(spec.name)' missing MenuSelectionCopy authorship"
                )
            }
            let example = actionExample(for: spec, recipes: recipesById)
            let validate = actionValidateExample(for: spec, example: example)
            let key = spec.effects.profileKey
            effectProfiles[key] = spec.effects
            // Length typos degrade (bound); missing authorship above is structural.
            let copy = enforceSelectionBounds(authored, kind: "action", id: spec.name)
            return MenuJSON.Action(
                id: spec.name,
                useWhen: copy.useWhen,
                dontUseWhen: copy.dontUseWhen,
                effectsRef: key,
                example: compact(example, limit: 96),
                validateExample: compact(validate, limit: 96)
            )
        }

        let teamRows: [MenuJSON.Team] = teamList.map { team in
            let active = TeamVisibility.isEnabled(team.id)
            let shape = team.mutating ? "execution" : "answer"
            // ADP-S03: a custom team saved with a blank display name (e.g.
            // `teams duplicate --name ""`) must still disclose a non-empty,
            // human-readable name next to its canonical id in every catalog
            // row — `disclosedDisplayName` falls back to the id.
            let displayName = team.disclosedDisplayName
            let copy = enforceSelectionBounds(
                MenuSelectionCopy.team(
                    id: team.id,
                    displayName: displayName,
                    description: team.description,
                    mutating: team.mutating
                ),
                kind: "team",
                id: team.id
            )
            let run = "alln run \"{message}\" --team \(team.id) --json"
            let validate = "alln run \"{message}\" --team \(team.id) --dry-run"
            return MenuJSON.Team(
                ref: "team:\(team.id)",
                id: team.id,
                displayName: displayName,
                useWhen: copy.useWhen,
                dontUseWhen: copy.dontUseWhen,
                shape: shape,
                mutating: team.mutating,
                seatCount: team.catalogSeatCount,
                isDefault: team.isDefaultForLane || team.id == "default_chat",
                active: active,
                blockedReason: active ? nil : "Switched off (TeamVisibility)",
                runTemplate: run,
                validateTemplate: validate
            )
        }

        let modelRows: [MenuJSON.Model] = models.map { entry in
            let copy = enforceSelectionBounds(
                MenuSelectionCopy.model(
                    id: entry.id,
                    displayName: entry.displayName,
                    driverId: entry.driverId
                ),
                kind: "model",
                id: entry.id
            )
            return MenuJSON.Model(
                ref: detailed ? "model:\(entry.id)" : nil,
                id: entry.id,
                displayName: entry.displayName,
                driverId: entry.driverId,
                enabled: entry.enabled,
                ready: entry.ready,
                blockedReason: modelBlockedReason(entry),
                useWhen: detailed ? copy.useWhen : nil,
                dontUseWhen: detailed ? copy.dontUseWhen : nil,
                runTemplate: "alln run \"{message}\" --model \(entry.id) --json",
                validateTemplate: "alln run \"{message}\" --model \(entry.id) --dry-run"
            )
        }

        // Tier-1 lists what can be SELECTED right now. An off-bench seat is not
        // selectable, so it is summarised rather than described in full — but it
        // is never silently absent: `blocked` says how many and where to look.
        let selectableRows = detailed ? modelRows : modelRows.filter(\.enabled)
        let omittedCount = modelRows.count - selectableRows.count
        let omitted: MenuJSON.OmittedSeats? = omittedCount > 0
            ? .init(count: omittedCount, see: "alln models")
            : nil

        let recipeRows: [MenuJSON.Recipe] = recipeList.map { recipe in
            let copy = enforceSelectionBounds(
                MenuSelectionCopy.recipe(id: recipe.id, title: recipe.title),
                kind: "recipe",
                id: recipe.id
            )
            return MenuJSON.Recipe(
                ref: "recipe:\(recipe.id)",
                id: recipe.id,
                title: recipe.title,
                useWhen: copy.useWhen,
                dontUseWhen: copy.dontUseWhen
            )
        }

        guard let defaultTeam = teamList.first(where: { $0.id == "default_chat" })
            ?? TeamCatalog.defaultRunTeam()
            ?? teamList.first
        else {
            preconditionFailure("MenuCatalog.project: no effective default team in catalog")
        }
        let resolvedWorker = defaultModelId
            ?? defaultTeam.agentSpecs.first?.preferredModelId
            ?? defaultTeam.lead.preferredModelId

        let revision = catalogRevision(
            teams: teamRows.map { "\($0.id):\($0.active)" },
            models: modelRows.map { "\($0.id):\($0.enabled):\($0.ready)" },
            recipes: recipeRows.map(\.id)
        )

        let completeness = MenuJSON.Completeness(
            actions: .init(count: actions.count, complete: true),
            commands: .init(count: commandRows.count, complete: true),
            teams: .init(count: teamRows.count, complete: true),
            models: .init(count: modelRows.count, complete: true),
            recipes: .init(count: recipeRows.count, complete: true),
            effectProfiles: .init(count: effectProfiles.count, complete: true)
        )

        return MenuJSON(
            contractVersion: registry.contractVersion,
            contractHash: ContractRegistry.contractHash(registry),
            catalogRevision: revision,
            truncated: false,
            detailTemplate: detailTemplate,
            actions: actions,
            commands: commandRows,
            teams: teamRows,
            models: selectableRows,
            blocked: omitted,
            recipes: recipeRows,
            effectProfiles: effectProfiles,
            defaults: MenuJSON.Defaults(
                defaultTeamRef: "team:\(defaultTeam.id)",
                defaultModelId: resolvedWorker
            ),
            completeness: completeness,
            capacity: capacity,
            update: update
        )
    }

    /// Lexical retrieval over projected menu rows (MR-S05). Returns zero or many
    /// cards ordered by match strength; never emits selected/confidence/recommended.
    public static func search(
        _ query: String,
        limit: Int = 5,
        registry: ContractRegistry = .milestone1,
        teams: [TeamPreset]? = nil,
        modelEntries: [ModelListJSON.Entry]? = nil,
        recipes: [RecipeCatalog.Recipe]? = nil,
        menu: MenuJSON? = nil
    ) -> MenuSearchResult {
        let limit = max(0, limit)
        let menu = menu ?? project(
            registry: registry,
            teams: teams,
            modelEntries: modelEntries,
            recipes: recipes
        )
        let tokens = tokenize(query)
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !phrase.isEmpty, limit > 0 else {
            return MenuSearchResult(query: query, catalogRevision: menu.catalogRevision, results: [])
        }

        var scored: [(MenuSearchHit, Double)] = []

        for action in menu.actions {
            let raw = score(
                phrase: phrase,
                tokens: tokens,
                id: action.id,
                title: action.id,
                useWhen: action.useWhen,
                dontUseWhen: action.dontUseWhen,
                extras: [action.example, action.validateExample]
            )
            guard raw >= minimumHitScore else { continue }
            scored.append((
                MenuSearchHit(
                    kind: "action",
                    ref: commandRef(action.id),
                    id: action.id,
                    title: action.id,
                    useWhen: action.useWhen,
                    dontUseWhen: action.dontUseWhen,
                    example: action.example,
                    validateExample: action.validateExample
                ),
                raw
            ))
        }

        for command in menu.commands {
            let raw = score(
                phrase: phrase,
                tokens: tokens,
                id: command.name,
                title: command.name,
                useWhen: nil,
                dontUseWhen: nil,
                extras: [command.ref, command.name]
            )
            guard raw >= minimumHitScore else { continue }
            scored.append((
                MenuSearchHit(
                    kind: "command",
                    ref: command.ref,
                    id: command.name,
                    title: command.name
                ),
                raw
            ))
        }

        for team in menu.teams {
            let raw = score(
                phrase: phrase,
                tokens: tokens,
                id: team.id,
                title: team.displayName,
                useWhen: team.useWhen,
                dontUseWhen: team.dontUseWhen,
                extras: [team.shape, team.runTemplate, team.validateTemplate]
            )
            guard raw >= minimumHitScore else { continue }
            scored.append((
                MenuSearchHit(
                    kind: "team",
                    ref: team.ref,
                    id: team.id,
                    title: team.displayName,
                    useWhen: team.useWhen,
                    dontUseWhen: team.dontUseWhen,
                    runTemplate: team.runTemplate,
                    validateTemplate: team.validateTemplate,
                    active: team.active,
                    blockedReason: team.blockedReason,
                    mutating: team.mutating,
                    shape: team.shape
                ),
                raw
            ))
        }

        for model in menu.models {
            let raw = score(
                phrase: phrase,
                tokens: tokens,
                id: model.id,
                title: model.displayName,
                useWhen: model.useWhen,
                dontUseWhen: model.dontUseWhen,
                extras: [model.driverId, model.runTemplate, model.validateTemplate]
            )
            guard raw >= minimumHitScore else { continue }
            scored.append((
                MenuSearchHit(
                    kind: "model",
                    ref: "model:\(model.id)",
                    id: model.id,
                    title: model.displayName,
                    useWhen: model.useWhen,
                    dontUseWhen: model.dontUseWhen,
                    runTemplate: model.runTemplate,
                    validateTemplate: model.validateTemplate,
                    blockedReason: model.blockedReason,
                    enabled: model.enabled,
                    ready: model.ready
                ),
                raw
            ))
        }

        for recipe in menu.recipes {
            let raw = score(
                phrase: phrase,
                tokens: tokens,
                id: recipe.id,
                title: recipe.title,
                useWhen: recipe.useWhen,
                dontUseWhen: recipe.dontUseWhen,
                extras: []
            )
            guard raw >= minimumHitScore else { continue }
            scored.append((
                MenuSearchHit(
                    kind: "recipe",
                    ref: recipe.ref,
                    id: recipe.id,
                    title: recipe.title,
                    useWhen: recipe.useWhen,
                    dontUseWhen: recipe.dontUseWhen
                ),
                raw
            ))
        }

        scored.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.kind != $1.0.kind { return $0.0.kind < $1.0.kind }
            return $0.0.ref < $1.0.ref
        }
        return MenuSearchResult(
            query: query,
            catalogRevision: menu.catalogRevision,
            results: Array(scored.prefix(limit).map(\.0))
        )
    }

    /// Absolute raw-score floor — weak body-only noise does not become a card.
    public static let minimumHitScore: Double = 3

    // MARK: - Search scoring

    private static func score(
        phrase: String,
        tokens: [String],
        id: String,
        title: String,
        useWhen: String?,
        dontUseWhen: String?,
        extras: [String]
    ) -> Double {
        let idTokens = tokenSet(id)
        let titleTokens = tokenSet(title)
        let useTokens = tokenSet(useWhen ?? "")
        let dontTokens = tokenSet(dontUseWhen ?? "")
        let extraTokens = tokenSet(extras.joined(separator: " "))
        var strong = 0.0
        let idLower = id.lowercased()
        let titleLower = title.lowercased()
        if phrase == idLower || phrase == titleLower { strong += 12 }
        else if idLower.contains(phrase) || titleLower.contains(phrase) { strong += 8 }
        for tok in tokens {
            if idTokens.contains(tok) { strong += 4 }
            if titleTokens.contains(tok) { strong += 4 }
            if useTokens.contains(tok) { strong += 3 }
            if dontTokens.contains(tok) { strong += 2 }
            if extraTokens.contains(tok) { strong += 1 }
        }
        return strong
    }

    private static func tokenize(_ s: String) -> [String] {
        let stop: Set<String> = [
            "the", "a", "an", "to", "of", "is", "do", "i", "how", "my", "on", "in",
            "for", "this", "can", "what", "and", "with", "it", "no",
        ]
        return s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stop.contains($0) }
    }

    private static func tokenSet(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 })
    }

    /// Tier-2 hydrate for a typed ref. Unknown refs throw `MenuRefError` with same-kind suggestions.
    public static func show(
        ref: String,
        registry: ContractRegistry = .milestone1,
        teams: [TeamPreset]? = nil,
        modelEntries: [ModelListJSON.Entry]? = nil,
        recipes: [RecipeCatalog.Recipe]? = nil,
        capacity: MenuJSON.Capacity? = nil
    ) throws -> MenuShowJSON {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let menu = project(
            registry: registry,
            teams: teams,
            modelEntries: modelEntries,
            recipes: recipes,
            capacity: capacity
        )
        guard let colon = trimmed.firstIndex(of: ":") else {
            throw MenuRefError(
                ref: trimmed,
                kind: nil,
                message: "Menu ref must be typed (command:, team:, model:, or recipe:)",
                suggestions: [
                    "command:run",
                    menu.teams.first.map(\.ref) ?? "team:default_chat",
                    menu.models.first.map { "model:\($0.id)" } ?? "model:model_sonnet",
                    menu.recipes.first.map(\.ref) ?? "recipe:ask-several-models-and-compare",
                ]
            )
        }
        let kind = String(trimmed[..<colon])
        let id = String(trimmed[trimmed.index(after: colon)...])
        switch kind {
        case "command":
            return try showCommand(refSuffix: id, ref: trimmed, registry: registry, menu: menu)
        case "team":
            return try showTeam(id: id, ref: trimmed, teams: teams ?? TeamCatalog.all.filter { !$0.isLabTeam }, menu: menu)
        case "model":
            return try showModel(id: id, ref: trimmed, modelEntries: modelEntries, menu: menu, capacity: capacity)
        case "recipe":
            return try showRecipe(id: id, ref: trimmed, recipes: recipes ?? RecipeCatalog.list(), menu: menu)
        default:
            throw MenuRefError(
                ref: trimmed,
                kind: kind,
                message: "Unknown menu ref kind '\(kind)' (expected command|team|model|recipe)",
                suggestions: ["command:run", "team:code_growth", "model:model_sonnet", "recipe:ask-several-models-and-compare"]
            )
        }
    }

    // MARK: - Typed refs

    public static func commandRef(_ name: String) -> String {
        "command:" + name.replacingOccurrences(of: " ", with: ".")
    }

    public static func commandName(fromRefSuffix dots: String) -> String {
        dots.replacingOccurrences(of: ".", with: " ")
    }

    // MARK: - Internals

    private static func builtInModelEntries() -> [ModelListJSON.Entry] {
        ModelCatalog.list().map { def in
            let enabled = ModelCatalog.isEnabled(def.id)
            return ModelListJSON.Entry(
                id: def.id,
                displayName: def.displayName,
                modelLabel: def.modelLabel,
                driverId: def.driverId,
                driverName: def.driverId,
                role: def.role.rawValue,
                origin: def.origin.rawValue,
                enabled: enabled,
                ready: false,
                status: "notChecked",
                state: enabled ? "onBench" : "available",
                capabilities: ModelCatalog.capabilities(def.id)
            )
        }
    }

    /// Compact sorted JSON for the agent front door (size budget; no pretty indent).
    public static func encodeCompact<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func catalogRevision(teams: [String], models: [String], recipes: [String]) -> String {
        let payload = (teams + models + recipes).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func compact(_ text: String, limit: Int = 48) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit - 1)
        return String(trimmed[..<idx]) + "…"
    }

    private static func modelBlockedReason(_ entry: ModelListJSON.Entry) -> String? {
        if !entry.enabled { return "Off bench" }
        if entry.ready { return nil }
        switch entry.status {
        case "driverMissing": return "Driver missing"
        case "notReady": return "Source not ready"
        case "notChecked": return "Source not checked"
        default: return "Not ready (\(entry.status))"
        }
    }

    /// Fast-path action examples prefer `{message}` + dry-run twin for spend paths.
    private static func actionExample(
        for spec: ContractRegistry.CommandSpec,
        recipes: [String: ContractRegistry.ExampleRecipe]
    ) -> String {
        if spec.name == "run" {
            return "alln run \"{message}\" --team code_growth --json"
        }
        return CommandDescription.example(for: spec, recipes: recipes)
    }

    private static func actionValidateExample(
        for spec: ContractRegistry.CommandSpec,
        example: String
    ) -> String {
        if spec.name == "run" {
            return "alln run \"{message}\" --team code_growth --dry-run --json"
        }
        if let twin = spec.freeTwinCommand, !twin.isEmpty {
            return twin.contains("--json") ? twin : "\(twin) --json"
        }
        if example.contains("--json") { return example }
        return example + " --json"
    }

    private static func showCommand(
        refSuffix: String,
        ref: String,
        registry: ContractRegistry,
        menu: MenuJSON
    ) throws -> MenuShowJSON {
        let name = commandName(fromRefSuffix: refSuffix)
        guard let spec = registry.commands.first(where: {
            $0.milestone == .m1 && $0.visibility == .public && $0.name == name
        }) else {
            let suggestions = menu.commands.map(\.ref).filter {
                $0.contains(refSuffix.split(separator: ".").first.map(String.init) ?? refSuffix)
            }
            throw MenuRefError(
                ref: ref,
                kind: "command",
                message: "Unknown command ref \(ref)",
                suggestions: Array((suggestions.isEmpty ? menu.commands.prefix(5).map(\.ref) : suggestions).prefix(8))
            )
        }
        let recipesById = Dictionary(uniqueKeysWithValues: registry.examples.map { ($0.id, $0) })
        return MenuShowJSON(
            contractVersion: registry.contractVersion,
            ref: ref,
            kind: "command",
            command: MenuShowJSON.CommandDetail(
                ref: commandRef(spec.name),
                name: spec.name,
                summary: spec.summary,
                trigger: CommandDescription.trigger(for: spec),
                example: CommandDescription.example(for: spec, recipes: recipesById),
                antiExample: CommandDescription.antiExample(for: spec),
                spendsQuota: spec.spendsQuota,
                freeTwinCommand: spec.freeTwinCommand,
                effects: spec.effects,
                args: spec.args,
                flags: spec.flags,
                mutuallyExclusiveFlags: spec.mutuallyExclusiveFlags,
                flagConstraints: spec.flagConstraints
            )
        )
    }

    private static func showTeam(
        id: String,
        ref: String,
        teams: [TeamPreset],
        menu: MenuJSON
    ) throws -> MenuShowJSON {
        guard let team = teams.first(where: { $0.id == id }) else {
            let suggestions = menu.teams.map(\.ref).filter { $0.contains(id.prefix(4)) }
            throw MenuRefError(
                ref: ref,
                kind: "team",
                message: "Unknown team ref \(ref)",
                suggestions: Array((suggestions.isEmpty ? menu.teams.prefix(5).map(\.ref) : suggestions).prefix(8))
            )
        }
        let active = TeamVisibility.isEnabled(team.id)
        let shape = team.mutating ? "execution" : "answer"
        return MenuShowJSON(
            contractVersion: menu.contractVersion,
            ref: ref,
            kind: "team",
            team: MenuShowJSON.TeamDetail(
                ref: "team:\(team.id)",
                id: team.id,
                displayName: team.disclosedDisplayName,
                description: team.description,
                lane: team.lane.rawValue,
                outputKind: team.outputKind.rawValue,
                shape: shape,
                mutating: team.mutating,
                seatCount: team.catalogSeatCount,
                isDefault: team.isDefaultForLane || team.id == "default_chat",
                active: active,
                blockedReason: active ? nil : "Switched off (TeamVisibility)",
                runTemplate: "alln run \"{message}\" --team \(team.id) --json",
                validateTemplate: "alln run \"{message}\" --team \(team.id) --dry-run",
                purposeTags: team.purposeTags
            )
        )
    }

    private static func showModel(
        id: String,
        ref: String,
        modelEntries: [ModelListJSON.Entry]?,
        menu: MenuJSON,
        capacity: MenuJSON.Capacity? = nil
    ) throws -> MenuShowJSON {
        let entries = (modelEntries ?? builtInModelEntries()).sorted { $0.id < $1.id }
        guard let entry = entries.first(where: { $0.id == id }) else {
            let suggestions = menu.models.map { "model:\($0.id)" }.filter { $0.contains(id.prefix(6)) }
            throw MenuRefError(
                ref: ref,
                kind: "model",
                message: "Unknown model ref \(ref)",
                suggestions: Array((suggestions.isEmpty ? menu.models.prefix(5).map { "model:\($0.id)" } : suggestions).prefix(8))
            )
        }
        let modelCapacity: MenuJSON.Capacity? = capacity.flatMap { cap in
            let rows = cap.rows.filter { $0.source == entry.driverId }
            return rows.isEmpty ? nil : MenuJSON.Capacity(generatedAt: cap.generatedAt, rows: rows)
        }
        return MenuShowJSON(
            contractVersion: menu.contractVersion,
            ref: ref,
            kind: "model",
            model: MenuShowJSON.ModelDetail(
                ref: "model:\(entry.id)",
                id: entry.id,
                displayName: entry.displayName,
                driverId: entry.driverId,
                driverName: entry.driverName,
                enabled: entry.enabled,
                ready: entry.ready,
                status: entry.status,
                blockedReason: modelBlockedReason(entry),
                capabilities: entry.capabilities,
                runTemplate: "alln run \"{message}\" --model \(entry.id) --json",
                validateTemplate: "alln run \"{message}\" --model \(entry.id) --dry-run",
                capacity: modelCapacity
            )
        )
    }

    private static func showRecipe(
        id: String,
        ref: String,
        recipes: [RecipeCatalog.Recipe],
        menu: MenuJSON
    ) throws -> MenuShowJSON {
        guard let recipe = recipes.first(where: { $0.id == id }) else {
            throw MenuRefError(
                ref: ref,
                kind: "recipe",
                message: "Unknown recipe ref \(ref)",
                suggestions: Array(menu.recipes.prefix(8).map(\.ref))
            )
        }
        let copy = MenuSelectionCopy.recipe(id: recipe.id, title: recipe.title)
        return MenuShowJSON(
            contractVersion: menu.contractVersion,
            ref: ref,
            kind: "recipe",
            recipe: MenuShowJSON.RecipeDetail(
                ref: "recipe:\(recipe.id)",
                id: recipe.id,
                title: recipe.title,
                useWhen: copy.useWhen,
                dontUseWhen: copy.dontUseWhen,
                markdown: recipe.markdown
            )
        )
    }

    /// Project selection copy within product bounds. Over-length authored copy
    /// is truncated (same `bound` fallbacks already use) — never a front-door crash.
    /// Structural failures (e.g. missing default team, missing menuAction authorship)
    /// still `preconditionFailure` at their call sites.
    private static func enforceSelectionBounds(
        _ pair: MenuSelectionCopy.Pair,
        kind _: String,
        id _: String
    ) -> MenuSelectionCopy.Pair {
        MenuSelectionCopy.projected(pair)
    }
}
