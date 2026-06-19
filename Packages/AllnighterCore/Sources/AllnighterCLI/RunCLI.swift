import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln run` — the unified run entrypoint (Unified Run Model).
enum RunCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let message = opts.positional.first ?? opts.value("message") else {
            FileHandle.standardError.write(Data(
                "usage: alln run \"<message>\" --project <id|path> [--team <id>] [--worker <modelId>] [--effort low|med|high] [--lane code|design|copy|signal] [--json | --stream]\n"
                    .utf8))
            exit(2)
        }

        guard let projectToken = opts.value("project") else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--project <id|path> required")
        }
        let store = ProjectStore()
        guard let project = resolveProject(projectToken, store: store) else {
            AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
        }

        let effort = opts.value("effort").flatMap(EffortLevel.init(rawValue:))
        if let raw = opts.value("effort"), effort == nil {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "unknown effort: \(raw)")
        }
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw)")
        }

        let request = RunRequest(
            message: message,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            presetId: opts.value("team") ?? opts.value("preset"),
            workerId: opts.value("worker"),
            effort: effort,
            lane: lane,
            type: opts.value("type"),
            context: opts.value("context")
        )

        let service = RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            invocations: runtime.invocations
        )

        if opts.flag("stream") {
            let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
            let runTask = Task {
                _ = await service.run(request, origin: .cli, originAgent: opts.value("agent"), events: continuation)
            }
            var mapper = NDJSONStreamProjector.LiveMapper()
            for await event in stream {
                if let line = mapper.line(for: event) { print(line) }
            }
            _ = await runTask.value
            return
        }

        let result = await service.run(request, origin: .cli, originAgent: opts.value("agent"))
        switch result {
        case .failure(let error):
            AllnighterCLI.emitFailure(code: error.code, message: error.description)
            exit(1)
        case .success(let run):
            if opts.flag("json") {
                let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?
                    .appendingPathComponent("run.json").path ?? ""
                let context = TeamRunJSONMapper.Context(
                    promptSource: .init(kind: .positional, path: nil),
                    runJournalPath: journalPath,
                    reproduceCommand: reproduceCommand(run, project: project)
                )
                let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: context)
                print(AllnighterCLI.jsonString(trj))
            } else {
                print(run.plan ?? run.workerAnswers.first?.output ?? "(run \(run.status.rawValue))")
                FileHandle.standardError.write(Data("\n[run \(run.id) · \(run.presetId ?? "default")]\n".utf8))
            }
        }
    }

    static func reproduceCommand(_ run: TeamRun, project: Project) -> String {
        var parts = ["alln run", "--project", project.id]
        if let team = run.presetId { parts.append(contentsOf: ["--team", team]) }
        if let effort = run.effort { parts.append(contentsOf: ["--effort", effort.rawValue]) }
        return parts.joined(separator: " ")
    }

    private static func resolveProject(_ token: String, store: ProjectStore) -> Project? {
        if let byId = try? store.get(token) { return byId }
        let key = RootNormalization.normalize(token).key
        return (try? store.activeProjects())?.first { $0.normalizedRootPath == key }
    }
}
