import Foundation
import AllnighterCore
import AllnighterEngine

enum StalledCLI {
    static func run(_ subcommand: String?, _ args: [String]) {
        switch subcommand {
        case "list":
            runList(args)
        case nil:
            FileHandle.standardError.write(Data("usage: alln stalled list --all [--json]\n".utf8))
            exit(2)
        default:
            FileHandle.standardError.write(Data("unknown stalled subcommand: \(subcommand!)\n".utf8))
            exit(2)
        }
    }

    private static func runList(_ args: [String]) {
        let opts = Options(args)
        guard opts.flag("all") else {
            usageError("usage: alln stalled list --all [--json]")
        }
        let service = StalledWorkService()
        _ = try? service.scanAndRefresh()
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
        _ = try? service.scanAndRefresh()
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
