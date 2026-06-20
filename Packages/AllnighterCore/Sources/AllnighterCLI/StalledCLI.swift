import Foundation
import AllnighterCore
import AllnighterEngine

enum StalledCLI {
    static func run(_ subcommand: String?, _ args: [String]) {
        switch subcommand {
        case "list":
            runList(args)
        case "check":
            runRecovery(args, usage: "stalled check <episode-id> [--json]") { try $0.checkStatus(episodeId: $1) }
        case "wait":
            let minutes = Options(args).value("minutes").flatMap(Int.init) ?? 30
            runRecovery(args, usage: "stalled wait <episode-id> [--minutes N] [--json]") { try $0.keepWaiting(episodeId: $1, minutes: minutes) }
        case "dismiss":
            runRecovery(args, usage: "stalled dismiss <episode-id> [--json]") { try $0.dismiss(episodeId: $1) }
        case nil:
            FileHandle.standardError.write(Data("usage: alln stalled list --all [--json] | stalled check|wait|dismiss <episode-id>\n".utf8))
            exit(2)
        default:
            FileHandle.standardError.write(Data("unknown stalled subcommand: \(subcommand!)\n".utf8))
            exit(2)
        }
    }

    private static func runRecovery(_ args: [String], usage: String,
                                    _ act: (StallRecoveryService, String) throws -> StallEpisode) {
        let opts = Options(args)
        guard let id = opts.positional.first else { usageError("usage: alln \(usage)") }
        do {
            let episode = try act(StallRecoveryService(), id)
            let payload = StallEpisodeJSON(contractVersion: ContractRegistry.contractVersion, episode: episode)
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(payload))
            } else {
                print("\(episode.id)\t\(episode.status.rawValue)\(episode.clearedBy.map { " · \($0.rawValue)" } ?? "")")
            }
        } catch StallRecoveryService.RecoveryError.episodeNotFound(let missing) {
            AllnighterCLI.fail(code: "STALL_EPISODE_NOT_FOUND", message: "no stall episode: \(missing)")
        } catch StallRecoveryService.RecoveryError.invalidMinutes {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--minutes must be a positive integer")
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error.localizedDescription)
        }
    }

    private static func runList(_ args: [String]) {
        let opts = Options(args)
        guard opts.flag("all") else {
            usageError("usage: alln stalled list --all [--json]")
        }
        let service = StalledWorkService()
        _ = try? service.scanAndRefresh()   // best-effort refresh; on failure we list last-known episodes
        let payload = service.aggregateStalledJSON()
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
        } else if payload.projects.isEmpty {
            print("(no stalled work)")
        } else {
            for group in payload.projects {
                print("\(group.projectId)\t\(group.episodes.count) episode(s)")
            }
        }
    }

    private static func usageError(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(2)
    }
}

extension ProjectCLI {
    static func runStalled(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln project stalled <project-id-or-name> [--include-cleared] [--json]\n".utf8))
            exit(2)
        }
        let projectStore = ProjectStore()
        guard let project = try? projectStore.get(idOrName) else {
            AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(idOrName)")
        }
        let service = StalledWorkService()
        _ = try? service.scanAndRefresh()   // best-effort refresh; on failure we list last-known episodes
        let payload = service.projectStalledJSON(
            projectId: project.id,
            includeCleared: opts.flag("include-cleared")
        )
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
        } else if payload.episodes.isEmpty {
            print("(no stalled work in \(project.displayName))")
        } else {
            for ep in payload.episodes {
                print("\(ep.id)\t\(ep.status.rawValue)\t\(ep.reason.rawValue)\t\(ep.targetKind.rawValue):\(ep.targetId)")
            }
        }
    }
}
