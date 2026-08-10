import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln menu` / `alln menu show` — live agent front door (MR-S01).
enum MenuCLI {
    static func run(_ args: [String], runtime: ToolRuntime) {
        let opts = Options(args) // --json accepted like peers; always machine JSON
        // Tier-1 is the hot path: teaching rule 1 sends EVERY agent here before
        // first spend, so the default carries only what selection needs.
        // `--detailed` restores per-seat ref/prose and off-bench rows.
        let detailed = opts.flag("detailed")
        let setup = SetupStore().load()
        let tally = BenchTallyProjector.tally(
            registry: runtime.registry,
            records: setup.records,
            parked: setup.parkedSet
        )
        let menu = MenuCatalog.project(
            teams: runtime.teams.filter { !$0.isLabTeam },
            modelEntries: ModelsCLI.modelListJSON(runtime: runtime).models,
            detailed: detailed,
            capacity: AllnighterCLI.menuCapacity(now: Date()),
            update: AllnighterCLI.menuUpdate(now: Date()),
            benchTally: MenuJSON.BenchTallyPayload(tally: tally)
        )
        do {
            print(String(decoding: try MenuCatalog.encodeCompact(menu), as: UTF8.self))
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "failed to encode MenuJSON: \(error)")
        }
    }

    static func runShow(_ args: [String], runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln menu show <ref> --json  (ref = command:… | team:… | model:… | recipe:…)"
            )
        }
        do {
            let detail = try MenuCatalog.show(
                ref: ref,
                teams: runtime.teams.filter { !$0.isLabTeam },
                modelEntries: ModelsCLI.modelListJSON(runtime: runtime).models,
                capacity: AllnighterCLI.menuCapacity(now: Date())
            )
            print(String(decoding: try MenuCatalog.encodeCompact(detail), as: UTF8.self))
        } catch let error as MenuRefError {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: error.message,
                suggestions: error.suggestions
            )
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error.localizedDescription)
        }
    }
}
