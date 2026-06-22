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
        emit(UtilizationBoostOperations.projection(runtime: runtime), Options(args), runtime)
    }

    private static func set(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        do {
            var enabled: Bool?
            if let raw = opts.value("enabled") {
                guard let on = Bool(raw.lowercased()) else {
                    AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--enabled must be true or false")
                    return
                }
                enabled = on
            }
            let json = try UtilizationBoostOperations.update(
                runtime: runtime,
                enabled: enabled,
                windowStart: opts.value("window-start"),
                appliesTo: opts.value("applies-to")
            )
            emit(json, opts, runtime)
        } catch let failure as UtilizationBoostOperations.Failure {
            if case .envelope(let env) = failure { fail(env) }
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }
    }

    private static func seed(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let sourceId = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln utilization boost seed <source-id> [--json]")
        }
        do {
            let event = try await UtilizationBoostOperations.seed(runtime: runtime, sourceId: sourceId)
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(event))
            } else {
                print("seed \(sourceId): \(event.outcome.rawValue)")
            }
        } catch let failure as UtilizationBoostOperations.Failure {
            if case .envelope(let env) = failure { fail(env) }
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }
    }

    private static func observations(_ args: [String]) {
        let opts = Options(args)
        if opts.positional.first == "clear" {
            do {
                let json = try UtilizationBoostOperations.clearObservations(sourceId: opts.value("source"))
                if opts.flag("json") { print(AllnighterCLI.jsonString(json)) }
                else {
                    print(json.sourceId.map { "cleared observations for \($0)" } ?? "cleared all seed observations")
                }
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
            }
            return
        }
        AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln utilization boost observations clear [--source <id>] [--json]")
    }

    private static func fail(_ env: ErrorEnvelope) {
        AllnighterCLI.fail(code: env.code, message: env.message)
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
