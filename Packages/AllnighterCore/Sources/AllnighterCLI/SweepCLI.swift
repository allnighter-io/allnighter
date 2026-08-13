import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln sweep start|resume|status` — one order × N targets, checkpointed, resumable.
enum SweepCLI {
    static let implementedSubcommands = ["start", "resume", "status"]

    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        let rest = Array(args.dropFirst())
        switch sub {
        case "start": await runStart(rest, runtime: runtime)
        case "resume": await runResume(rest, runtime: runtime)
        case "status": runStatus(rest)
        default:
            let known = implementedSubcommands.joined(separator: "|")
            FileHandle.standardError.write(Data("sweep \(sub): not recognized — \(known).\n".utf8))
            exit(2)
        }
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(Data(
            "usage: alln sweep start \"<order>\" --target <id> [--target <id> ...] [--targets <csv>] [--targets-file <path>] [--model <id>] [--project <id>] [--dry-run] [--json]\n"
                .utf8))
        exit(2)
    }

    private static func runStart(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        let order = opts.positional.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !order.isEmpty else { usage() }
        let project = resolveProject(opts: opts)
        let targetIds: [String]
        do {
            targetIds = try parseTargets(opts)
        } catch let error as SweepError {
            AllnighterCLI.fail(code: error.errorCode, message: error.message)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error.localizedDescription)
        }

        let store = SweepStateStore()
        let engine = SweepEngine(store: store)
        do {
            if opts.flag("dry-run") {
                let preview = SweepState(
                    id: "dry-run",
                    order: order,
                    projectRoot: project.normalizedRootPath,
                    modelId: opts.value("model"),
                    targets: targetIds.map { SweepTargetRecord(id: $0) },
                    status: .running,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                emit(preview, json: opts.flag("json"))
                return
            }
            let created = try engine.create(
                order: order,
                targetIds: targetIds,
                projectRoot: project.normalizedRootPath,
                modelId: opts.value("model")
            )
            let executor = SweepRunExecutor(
                runService: RunService(
                    models: runtime.models,
                    registry: runtime.registry,
                    teams: runtime.teams,
                    invocations: runtime.invocations
                ),
                repoRoot: project.normalizedRootPath,
                projectId: project.id,
                modelId: opts.value("model")
            )
            let settled = try await engine.advance(id: created.id, executor: executor)
            emit(settled, json: opts.flag("json"))
            if !SweepHonesty.canReportComplete(settled) {
                exit(ContractRegistry.milestone1.processExitCode(forErrorCode: "SWEEP_INCOMPLETE"))
            }
        } catch let error as SweepError {
            AllnighterCLI.fail(code: error.errorCode, message: error.message)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: error.localizedDescription)
        }
    }

    private static func runResume(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let sweepId = opts.positional.first, !sweepId.isEmpty else {
            FileHandle.standardError.write(Data("usage: alln sweep resume <sweep-id> [--json]\n".utf8))
            exit(2)
        }
        let store = SweepStateStore()
        let engine = SweepEngine(store: store)
        do {
            guard var state = try store.load(id: sweepId) else {
                throw SweepError.notFound(id: sweepId)
            }
            if state.status == .running, store.isOwnerDead(id: sweepId) {
                state = try engine.reconcileKill(state)
            }
            let executor = SweepRunExecutor(
                runService: RunService(
                    models: runtime.models,
                    registry: runtime.registry,
                    teams: runtime.teams,
                    invocations: runtime.invocations
                ),
                repoRoot: state.projectRoot,
                modelId: state.modelId
            )
            let settled = try await engine.advance(id: sweepId, executor: executor)
            emit(settled, json: opts.flag("json"))
            if !SweepHonesty.canReportComplete(settled) {
                exit(ContractRegistry.milestone1.processExitCode(forErrorCode: "SWEEP_INCOMPLETE"))
            }
        } catch let error as SweepError {
            AllnighterCLI.fail(code: error.errorCode, message: error.message)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: error.localizedDescription)
        }
    }

    private static func runStatus(_ args: [String]) {
        let opts = Options(args)
        guard let sweepId = opts.positional.first, !sweepId.isEmpty else {
            FileHandle.standardError.write(Data("usage: alln sweep status <sweep-id> [--json]\n".utf8))
            exit(2)
        }
        let store = SweepStateStore()
        let engine = SweepEngine(store: store)
        do {
            guard var state = try store.load(id: sweepId) else {
                throw SweepError.notFound(id: sweepId)
            }
            if state.status == .running, store.isOwnerDead(id: sweepId) {
                state = try engine.reconcileKill(state)
            }
            emit(state, json: opts.flag("json"))
        } catch let error as SweepError {
            AllnighterCLI.fail(code: error.errorCode, message: error.message)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: error.localizedDescription)
        }
    }

    static func parseTargets(_ opts: Options) throws -> [String] {
        var fileLines: [String] = []
        if let path = opts.value("targets-file") {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            fileLines = text.components(separatedBy: .newlines)
        }
        return try SweepTargetList.parse(
            repeated: opts.repeatedValues["target"] ?? [],
            csv: opts.value("targets"),
            fileLines: fileLines
        )
    }

    private static func emit(_ state: SweepState, json: Bool) {
        let payload = SweepJSON.project(state)
        if json {
            print(AllnighterCLI.jsonString(payload))
            return
        }
        print("sweep \(payload.sweepId)  status=\(payload.status)  complete=\(payload.complete)")
        print("done \(payload.doneCount)  failed \(payload.failedCount)  not-attempted \(payload.notAttemptedCount)")
        for target in payload.targets {
            var line = "  \(target.outcome.rawValue)  \(target.id)"
            if let runId = target.runId { line += "  run=\(runId)" }
            if let reason = target.reason { line += "  \(reason)" }
            print(line)
        }
        if let path = payload.artifactPath {
            print("artifact: \(path)")
        }
        if let next = payload.nextAction {
            print("next: \(next)")
        }
    }

    private static func resolveProject(opts: Options, store: ProjectStore = ProjectStore()) -> Project {
        if let projectToken = opts.value("project") {
            guard let resolved = AllnighterCLI.resolveProject(projectToken, store: store) else {
                AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
            }
            return resolved
        }
        if let resolved = AllnighterCLI.resolveProjectFromCwd(store: store) {
            return resolved
        }
        let cwd = FileManager.default.currentDirectoryPath
        let gitRoot = GitObserver().repoTopLevel(forPath: cwd) ?? cwd
        AllnighterCLI.fail(
            code: "PROJECT_NOT_FOUND",
            message: "no registered project for \(gitRoot) — run `alln project add \(gitRoot)`"
        )
    }
}
