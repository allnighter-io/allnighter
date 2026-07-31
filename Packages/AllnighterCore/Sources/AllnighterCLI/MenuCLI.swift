import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln menu` / `alln menu show` — live agent front door (MR-S01).
enum MenuCLI {
    static func run(_ args: [String], runtime: ToolRuntime) {
        _ = Options(args) // accept --json like peers; always emit machine JSON
        let menu = MenuCatalog.project(
            teams: runtime.teams.filter { !$0.isLabTeam },
            modelEntries: ModelsCLI.modelListJSON(runtime: runtime).models,
            capacity: AllnighterCLI.menuCapacity(now: Date())
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
