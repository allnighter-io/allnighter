import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln defaults …` — Default model & Substitutions. Mutations load the SSOT
/// (`DefaultModelSettingsPersistence`), apply one many-to-many-aware change, save,
/// and re-emit the whole `DefaultSettingsJSON` (live readiness) so a caller always
/// gets the resolved truth back. No GUI-local or CLI-local truth.
enum DefaultsCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        let sub = args.first
        let rest = Array(args.dropFirst())
        switch sub {
        case "tier": setTier(rest, runtime)
        case "assign": assign(rest, runtime)
        case "unassign": unassign(rest, runtime)
        case "substitutions": substitutions(rest, runtime)
        case "reset": reset(rest, runtime)
        case "show", nil: show(rest, runtime)
        default: show(args, runtime)   // bare/unknown subcommand → show
        }
    }

    // MARK: - Subcommands

    private static func show(_ args: [String], _ runtime: ToolRuntime) {
        emit(persistence().load(), Options(args), runtime)
    }

    private static func setTier(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let raw = opts.positional.first else { usage("tier <frontier|balanced|economy>") }
        guard let tier = SubstitutionTier.parse(raw) else {
            AllnighterCLI.fail(code: "DEFAULTS_TIER_INVALID", message: "unknown tier: \(raw)")
        }
        var s = persistence().load()
        s.defaultTier = tier
        save(s); emit(s, opts, runtime)
    }

    private static func assign(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let model = opts.positional.first else {
            usage("assign <model-id> --tier <frontier|balanced|economy> [--default | --position <n>]")
        }
        guard let tierRaw = opts.value("tier"), let tier = SubstitutionTier.parse(tierRaw) else {
            AllnighterCLI.fail(code: "DEFAULTS_TIER_INVALID", message: "--tier frontier|balanced|economy is required")
        }
        guard ModelCatalog.get(model) != nil else {
            AllnighterCLI.fail(code: "DEFAULTS_MODEL_UNKNOWN", message: "unknown model id: \(model)")
        }
        let position: Int?
        if opts.flag("default") {
            position = 0
        } else if let raw = opts.value("position") {
            guard let p = Int(raw), p >= 0 else {
                AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--position must be a non-negative integer (got: \(raw)); use --default for the top")
            }
            position = p
        } else {
            position = nil   // append
        }
        let s: DefaultModelSettings
        do {
            s = try DefaultModelTierActions.assign(model, to: tier, position: position,
                                                   settingsPersistence: persistence())
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR",
                               message: "could not assign model to tier: \(error.localizedDescription)")
        }
        emit(s, opts, runtime)
    }

    private static func unassign(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let model = opts.positional.first else { usage("unassign <model-id> [--tier <frontier|balanced|economy>]") }
        let tier: SubstitutionTier?
        if let raw = opts.value("tier") {
            guard let t = SubstitutionTier.parse(raw) else {
                AllnighterCLI.fail(code: "DEFAULTS_TIER_INVALID", message: "unknown tier: \(raw)")
            }
            tier = t
        } else {
            tier = nil   // remove from all tiers
        }
        let s: DefaultModelSettings
        do {
            s = try DefaultModelTierActions.unassign(model, from: tier,
                                                     settingsPersistence: persistence())
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR",
                               message: "could not unassign model from tier: \(error.localizedDescription)")
        }
        emit(s, opts, runtime)
    }

    private static func substitutions(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let state = opts.positional.first?.lowercased(), ["on", "off"].contains(state) else {
            usage("substitutions <on|off>")
        }
        var s = persistence().load()
        s.allowHealthySubstitutions = (state == "on")
        save(s); emit(s, opts, runtime)
    }

    private static func reset(_ args: [String], _ runtime: ToolRuntime) {
        let s = (try? persistence().reset()) ?? .fresh
        emit(s, Options(args), runtime)
    }

    // MARK: - Helpers

    private static func persistence() -> DefaultModelSettingsPersistence { DefaultModelSettingsPersistence() }

    private static func save(_ s: DefaultModelSettings) {
        do { try persistence().save(s) }
        catch { AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "could not save default settings: \(error.localizedDescription)") }
    }

    private static func projection(_ s: DefaultModelSettings, _ runtime: ToolRuntime) -> DefaultSettingsJSON {
        DefaultSettingsProjector.build(
            settings: s,
            models: ModelsCLI.modelListJSON(runtime: runtime).models,
            contractVersion: ContractRegistry.contractVersion)
    }

    private static func emit(_ s: DefaultModelSettings, _ opts: Options, _ runtime: ToolRuntime) {
        let proj = projection(s, runtime)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(proj))
        } else {
            printSummary(proj)
        }
    }

    private static func printSummary(_ p: DefaultSettingsJSON) {
        let autoLine: String
        if let name = p.auto.resolvedModelName {
            autoLine = "Auto → \(name)\(p.auto.substituted ? " (substituted)" : "") · tier \(p.defaultTier)"
        } else {
            autoLine = "Auto → \(p.auto.waitsMessage ?? "waits") · tier \(p.defaultTier)"
        }
        print(autoLine)
        print("substitutions: \(p.allowHealthySubstitutions ? "on" : "off")")
        for t in p.tiers {
            let badge = t.isDefaultTier ? " [Auto]" : ""
            print("\(t.displayName)\(badge) — \(t.readyCount)/\(t.members.count) ready")
            for m in t.members {
                let mark = m.isTierDefault ? "*" : " "
                let ready = m.ready ? "ready" : (m.enabled ? "down" : "off")
                print("  \(mark) \(m.displayName)\t\(m.driverId)\t\(ready)")
            }
        }
        if !p.unassigned.isEmpty {
            print("Unassigned: " + p.unassigned.map(\.displayName).joined(separator: ", "))
        }
    }

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln defaults \(detail) [--json]\n".utf8))
        exit(2)
    }
}
