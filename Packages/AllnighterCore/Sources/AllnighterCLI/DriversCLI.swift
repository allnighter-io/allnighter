import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln drivers` — list / park / unpark headless CLIs.
/// Park is durable setup intent (SetupStore.parkedDriverIds), not delete.
enum DriversCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else {
            runList(args, runtime)
            return
        }
        switch sub {
        case "park": runPark(Array(args.dropFirst()), runtime, park: true)
        case "unpark": runPark(Array(args.dropFirst()), runtime, park: false)
        default: runList(args, runtime)
        }
    }

    private static func runList(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let list = listJSON(runtime: runtime)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(list))
        } else {
            printHuman(list)
        }
    }

    private static func runPark(_ args: [String], _ runtime: ToolRuntime, park: Bool) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: park
                    ? "usage: alln drivers park <driver-id> [--json]"
                    : "usage: alln drivers unpark <driver-id> [--json]"
            )
            return
        }
        let known = Set(runtime.registry.all.filter { $0.kind == .headlessCLI }.map(\.id))
        guard known.contains(id) else {
            AllnighterCLI.fail(
                code: "SOURCE_NOT_FOUND",
                message: "No headless CLI driver '\(id)'. List with `alln drivers --json`.",
                suggestions: known.sorted()
            )
        }
        let store = SetupStore()
        var state = store.load()
        if park {
            state.park(id)
        } else {
            state.unpark(id)
        }
        do {
            _ = try store.save(state)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "Could not save park state: \(error.localizedDescription)")
        }
        let list = listJSON(runtime: runtime)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(list))
        } else {
            let name = runtime.registry.manifest(id: id)?.displayName ?? id
            print(park ? "parked\t\(id)\t\(name)" : "on-bench\t\(id)\t\(name)")
            printHuman(list)
        }
    }

    static func listJSON(runtime: ToolRuntime, now: Date = Date()) -> DriverListJSON {
        let state = SetupStore().load()
        let models = ModelCatalog.resolvedModels(registry: runtime.registry)
        return DriverListProjector.build(
            registry: runtime.registry,
            probeRecords: state.records,
            models: models,
            parkedDriverIds: state.parkedSet,
            vendorResetsBySource: CapacityResetLookup.bySource(now: now)
        )
    }

    static func printHuman(_ list: DriverListJSON) {
        if list.drivers.isEmpty {
            print("No headless CLI drivers in the registry.")
            return
        }
        for d in list.drivers {
            var line = "\(d.driverId)\t\(d.displayName)\t\(d.status)"
            if d.parked { line += "\tparked" }
            if d.modelsOn > 0 { line += "\tmodelsOn=\(d.modelsOn)" }
            if let v = d.version, !v.isEmpty { line += "\t\(v)" }
            if let detail = d.probeDetail { line += "\t\(detail)" }
            print(line)
        }
    }
}
