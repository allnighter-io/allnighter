import Foundation
import AllnighterCore
import AllnighterEngine

enum UtilizationBoostCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        let sub = args.first
        let rest = Array(args.dropFirst())
        switch sub {
        case "set": set(rest, runtime)
        case "seed": await seed(rest, runtime)
        case "observations": observations(rest)
        case "show", "status", nil: show(rest, runtime)
        default: show(args, runtime)
        }
    }

    private static func show(_ args: [String], _ runtime: ToolRuntime) {
        emit(projection(runtime), Options(args), runtime)
    }

    private static func set(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        var s = persistence().load()
        if let raw = opts.value("enabled") {
            guard let on = Bool(raw.lowercased()) else {
                AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--enabled must be true or false")
            }
            s.enabled = on
        }
        if let raw = opts.value("window-start") {
            s.windowStart = parseWindowStart(raw)
        }
        if let raw = opts.value("applies-to") {
            s.appliesTo = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        save(s)
        emit(projection(runtime, settings: s), opts, runtime)
    }

    private static func seed(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let sourceId = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln utilization boost seed <source-id> [--json]")
        }
        guard runtime.registry.manifest(id: sourceId) != nil else {
            AllnighterCLI.fail(code: "UTILIZATION_SOURCE_NOT_FOUND", message: "unknown source: \(sourceId)")
        }
        let settings = persistence().load()
        guard settings.appliesToSet.contains(sourceId) else {
            AllnighterCLI.fail(code: "UTILIZATION_SOURCE_UNCONFIGURED", message: "\(sourceId) is not in appliesTo")
        }
        let seedMinutes = BoostWindowTiming.seedFiresAt(settings.windowStart)
        let outcome: UtilizationSeedOutcome = BoostWindowTiming.seedIsOvernightIdle(seedMinutes) ? .skipped : .noQuietRunUp
        let event = UtilizationSeedEvent(sourceId: sourceId, outcome: outcome, rawSnippet: "manual seed via CLI")
        try? UtilizationSeedLedger().append(event)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(event))
        } else {
            print("seed \(sourceId): \(outcome.rawValue)")
        }
    }

    private static func observations(_ args: [String]) {
        let opts = Options(args)
        if opts.positional.first == "clear" {
            let source = opts.value("source")
            try? UtilizationSeedLedger().clear(sourceId: source)
            if opts.flag("json") { print("{\"cleared\":true}") }
            else { print(source.map { "cleared observations for \($0)" } ?? "cleared all seed observations") }
            return
        }
        AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln utilization boost observations clear [--source <id>] [--json]")
    }

    private static func parseWindowStart(_ raw: String) -> Int {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--window-start must be HH:MM (got: \(raw))")
        }
        return BoostWindowTiming.snap15(h * 60 + m)
    }

    private static func projection(_ runtime: ToolRuntime, settings: BoostWindowSettings? = nil) -> BoostWindowSettingsJSON {
        let s = settings ?? persistence().load()
        let providers = providerStates(settings: s, runtime: runtime)
        return BoostWindowProjector.build(
            settings: s,
            providers: providers,
            contractVersion: ContractRegistry.contractVersion
        )
    }

    private static func providerStates(settings: BoostWindowSettings, runtime: ToolRuntime) -> [ProviderBoostState] {
        let ready = Set(runtime.readyModels.map(\.driverId))
        let records = SetupStore().load().records
        return runtime.registry.all
            .filter { ["claude_code", "codex"].contains($0.id) }
            .map { manifest in
                let rec = records.first { $0.driverId == manifest.id }
                let signedIn = rec?.status.isReady == true
                let needsAttention: Bool = {
                    if case .installedNotSignedIn = rec?.status { return true }
                    return false
                }()
                return ProviderBoostState(
                    id: manifest.id,
                    displayName: manifest.displayName,
                    connected: ready.contains(manifest.id) || rec != nil,
                    signedIn: signedIn,
                    included: settings.appliesToSet.contains(manifest.id),
                    lastObservedReset: nil,
                    needsAttention: needsAttention
                )
            }
    }

    private static func persistence() -> BoostWindowSettingsPersistence { BoostWindowSettingsPersistence() }

    private static func save(_ s: BoostWindowSettings) {
        do { try persistence().save(s) }
        catch { AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    private static func emit(_ json: BoostWindowSettingsJSON, _ opts: Options, _ runtime: ToolRuntime) {
        if opts.flag("json") { print(AllnighterCLI.jsonString(json)) }
        else {
            print("boost \(json.enabled ? "on" : "off") · window \(BoostWindowTiming.formatWindowRange(start: json.windowStart)) · \(json.displayState)")
            for p in json.providers where p.included {
                print("  \(p.sourceId)\t\(p.signedIn ? "ready" : "needs setup")")
            }
            _ = runtime
        }
    }
}
