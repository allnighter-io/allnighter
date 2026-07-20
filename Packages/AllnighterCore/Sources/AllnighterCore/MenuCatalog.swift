import CryptoKit
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
        defaultWorkerId: String? = nil
    ) -> MenuJSON {
        let teamList = (teams ?? TeamCatalog.all.filter { !$0.isLabTeam })
            .sorted { $0.id < $1.id }
        let models: [ModelListJSON.Entry]
        if let modelEntries {
            models = modelEntries.sorted { $0.id < $1.id }
        } else {
            models = builtInModelEntries().sorted { $0.id < $1.id }
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
            let example = CommandDescription.example(for: spec, recipes: recipesById)
            let validate = validateExample(for: spec, example: example)
            let key = spec.effects.profileKey
            effectProfiles[key] = spec.effects
            return MenuJSON.Action(
                id: spec.name,
                useWhen: compact(CommandDescription.trigger(for: spec), limit: 40),
                dontUseWhen: compact(CommandDescription.antiExample(for: spec), limit: 40),
                effectsRef: key,
                example: compact(example, limit: 72),
                validateExample: compact(validate, limit: 72)
            )
        }

        let teamRows: [MenuJSON.Team] = teamList.map { team in
            let active = TeamVisibility.isEnabled(team.id)
            let shape = team.mutating ? "execution" : "answer"
            return MenuJSON.Team(
                ref: "team:\(team.id)",
                id: team.id,
                displayName: team.displayName,
                useWhen: compact(teamUseWhen(team), limit: 40),
                dontUseWhen: teamDontUseWhen(team),
                shape: shape,
                mutating: team.mutating,
                workerCount: team.catalogSeatCount,
                isDefault: team.isDefaultForLane || team.id == "default_chat",
                active: active,
                blockedReason: active ? nil : "Switched off (TeamVisibility)",
                runTemplate: "alln run \"{message}\" --team \(team.id) --json",
                validateTemplate: "alln run \"{message}\" --team \(team.id) --dry-run --json"
            )
        }

        let modelRows: [MenuJSON.Model] = models.map { entry in
            MenuJSON.Model(
                ref: "model:\(entry.id)",
                id: entry.id,
                displayName: entry.displayName,
                driverId: entry.driverId,
                enabled: entry.enabled,
                ready: entry.ready,
                blockedReason: modelBlockedReason(entry),
                capabilities: compactCapabilities(entry.capabilities),
                runTemplate: "alln run \"{message}\" --worker \(entry.id) --json",
                validateTemplate: "alln run \"{message}\" --worker \(entry.id) --dry-run --json"
            )
        }

        let recipeRows: [MenuJSON.Recipe] = recipeList.map { recipe in
            MenuJSON.Recipe(
                ref: "recipe:\(recipe.id)",
                id: recipe.id,
                title: recipe.title,
                useWhen: compact(recipe.title, limit: 48),
                dontUseWhen: "Pick from menu.recipes only"
            )
        }

        guard let defaultTeam = teamList.first(where: { $0.id == "default_chat" })
            ?? TeamCatalog.defaultRunTeam()
            ?? teamList.first
        else {
            preconditionFailure("MenuCatalog.project: no effective default team in catalog")
        }
        let resolvedWorker = defaultWorkerId
            ?? defaultTeam.workerSpecs.first?.preferredModelId
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
            models: modelRows,
            recipes: recipeRows,
            effectProfiles: effectProfiles,
            defaults: MenuJSON.Defaults(
                defaultTeamRef: "team:\(defaultTeam.id)",
                defaultWorkerId: resolvedWorker
            ),
            completeness: completeness
        )
    }

    /// Tier-2 hydrate for a typed ref. Unknown refs throw `MenuRefError` with same-kind suggestions.
    public static func show(
        ref: String,
        registry: ContractRegistry = .milestone1,
        teams: [TeamPreset]? = nil,
        modelEntries: [ModelListJSON.Entry]? = nil,
        recipes: [RecipeCatalog.Recipe]? = nil
    ) throws -> MenuShowJSON {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let menu = project(
            registry: registry,
            teams: teams,
            modelEntries: modelEntries,
            recipes: recipes
        )
        guard let colon = trimmed.firstIndex(of: ":") else {
            throw MenuRefError(
                ref: trimmed,
                kind: nil,
                message: "Menu ref must be typed (command:, team:, model:, or recipe:)",
                suggestions: [
                    "command:run",
                    menu.teams.first.map(\.ref) ?? "team:default_chat",
                    menu.models.first.map(\.ref) ?? "model:model_sonnet",
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
            return try showModel(id: id, ref: trimmed, modelEntries: modelEntries, menu: menu)
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

    /// Tier-1 keeps capabilities short: top tags only (full set lives in menu show).
    private static func compactCapabilities(_ caps: ModelCapabilities) -> ModelCapabilities {
        ModelCapabilities(
            laneTags: Array(caps.laneTags.prefix(1)),
            capabilityTags: Array(caps.capabilityTags.prefix(2)),
            strengthRank: caps.strengthRank
        )
    }

    private static func teamUseWhen(_ team: TeamPreset) -> String {
        if !team.description.isEmpty { return team.description }
        if !team.purposeTags.isEmpty {
            return team.purposeTags.prefix(3).joined(separator: ",")
        }
        return team.displayName
    }

    private static func teamDontUseWhen(_ team: TeamPreset) -> String {
        team.mutating ? "Not for parallel judgment" : "Not for mutating/write runs"
    }

    private static func modelBlockedReason(_ entry: ModelListJSON.Entry) -> String? {
        if !entry.enabled { return "Not on Bench" }
        if entry.ready { return nil }
        switch entry.status {
        case "driverMissing": return "Driver missing"
        case "notReady": return "Source not ready"
        case "notChecked": return "Source not checked"
        default: return "Not ready (\(entry.status))"
        }
    }

    private static func validateExample(for spec: ContractRegistry.CommandSpec, example: String) -> String {
        if let twin = spec.freeTwinCommand, !twin.isEmpty {
            return twin.contains("--json") ? twin : "\(twin) --json"
        }
        if spec.name == "run" {
            return "alln run \"{message}\" --dry-run --json"
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
                flags: spec.flags
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
                displayName: team.displayName,
                description: team.description,
                lane: team.lane.rawValue,
                outputKind: team.outputKind.rawValue,
                shape: shape,
                mutating: team.mutating,
                workerCount: team.catalogSeatCount,
                isDefault: team.isDefaultForLane || team.id == "default_chat",
                active: active,
                blockedReason: active ? nil : "Switched off (TeamVisibility)",
                runTemplate: "alln run \"{message}\" --team \(team.id) --json",
                validateTemplate: "alln run \"{message}\" --team \(team.id) --dry-run --json",
                purposeTags: team.purposeTags
            )
        )
    }

    private static func showModel(
        id: String,
        ref: String,
        modelEntries: [ModelListJSON.Entry]?,
        menu: MenuJSON
    ) throws -> MenuShowJSON {
        let entries = (modelEntries ?? builtInModelEntries()).sorted { $0.id < $1.id }
        guard let entry = entries.first(where: { $0.id == id }) else {
            let suggestions = menu.models.map(\.ref).filter { $0.contains(id.prefix(6)) }
            throw MenuRefError(
                ref: ref,
                kind: "model",
                message: "Unknown model ref \(ref)",
                suggestions: Array((suggestions.isEmpty ? menu.models.prefix(5).map(\.ref) : suggestions).prefix(8))
            )
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
                runTemplate: "alln run \"{message}\" --worker \(entry.id) --json",
                validateTemplate: "alln run \"{message}\" --worker \(entry.id) --dry-run --json"
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
        return MenuShowJSON(
            contractVersion: menu.contractVersion,
            ref: ref,
            kind: "recipe",
            recipe: MenuShowJSON.RecipeDetail(
                ref: "recipe:\(recipe.id)",
                id: recipe.id,
                title: recipe.title,
                useWhen: compact(recipe.title, limit: 48),
                dontUseWhen: "Pick from menu.recipes only",
                markdown: recipe.markdown
            )
        )
    }
}
