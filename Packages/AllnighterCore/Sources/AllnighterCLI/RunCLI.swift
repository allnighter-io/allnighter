import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln run` — the unified run entrypoint (Unified Run Model).
enum RunCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let message = opts.positional.first ?? opts.value("message") else {
            FileHandle.standardError.write(Data(
                "usage: alln run \"<message>\" --project <id|path> [--team <id>] [--worker <modelId>] [--effort low|med|high] [--lane code|design|copy|signal] [--try-fix [--executor <id>]] [--json | --stream]\n"
                    .utf8))
            exit(2)
        }

        guard let projectToken = opts.value("project") else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--project <id|path> required")
        }
        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
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

        let tryFix = opts.flag("try-fix")
        let request = RunRequest(
            message: message,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            presetId: opts.value("team"),
            workerId: opts.value("worker"),
            effort: effort,
            lane: lane,
            type: opts.value("type"),
            context: opts.value("context"),
            executorTeamId: opts.value("executor")
        )

        let service = RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            invocations: runtime.invocations
        )

        if tryFix {
            await runTryFix(request, service: service, runtime: runtime, project: project, json: opts.flag("json"))
            return
        }

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
                FileHandle.standardError.write(Data("\n[\(RunIdentity.cliFooter(run))]\n".utf8))
            }
        }
    }

    /// `alln run --try-fix`: the elimination-loop chain — a read-only Bug Hunt diagnosis, the
    /// danger-not-doubt gate, and (when allowed) ONE child execution that tries the top
    /// hypothesis. Emits a `TryFixChainJSON` (or a human summary).
    private static func runTryFix(
        _ request: RunRequest, service: RunService, runtime: ToolRuntime, project: Project, json: Bool
    ) async {
        let coordinator = FollowUpCoordinator(runService: service)
        let result = await coordinator.runTryFix(request, origin: .cli)
        guard case .success(let outcome) = result else {
            if case .failure(let error) = result {
                AllnighterCLI.emitFailure(code: error.code, message: error.description)
            }
            exit(1)
        }

        let chain = chainJSON(outcome, runtime: runtime, project: project)
        if json {
            print(AllnighterCLI.jsonString(chain))
        } else {
            print(humanSummary(chain, outcome: outcome))
            FileHandle.standardError.write(Data(
                "\n[diagnosis \(outcome.parentRun.id)\(outcome.childRun.map { " · fix \($0.id)" } ?? "")]\n".utf8))
        }
        // Non-zero exit when the gate refused, so scripts can branch on it.
        if outcome.childRun == nil, case .blocked = outcome.gate { exit(1) }
    }

    private static func chainJSON(
        _ outcome: FollowUpCoordinator.Outcome, runtime: ToolRuntime, project: Project
    ) -> TryFixChainJSON {
        func mapRun(_ run: TeamRun) -> TeamRunJSON {
            TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: AllnighterCLI.defaultRunContext(run))
        }
        let status: TryFixChainJSON.Status =
            outcome.childRun != nil ? .fixAttempted
            : (outcome.packet == nil ? .noPacket : .blocked)
        let next: String
        switch status {
        case .fixAttempted:
            next = "Read the fix attempt. If it's still broken, the report names what this round ruled out — run --try-fix again to narrow."
        case .blocked:
            if case .blocked(_, let reason) = outcome.gate { next = "Gate refused: \(reason). Resolve it, then retry." }
            else { next = "Gate refused. Resolve it, then retry." }
        case .noPacket:
            next = "The diagnosis produced no typed fix packet. Re-run Bug Hunt with a sharper report."
        }
        return TryFixChainJSON(
            contractVersion: ContractRegistry.contractVersion,
            status: status,
            diagnosis: mapRun(outcome.parentRun),
            gate: .from(outcome.gate),
            packet: outcome.packet,
            fixAttempt: outcome.childRun.map(mapRun),
            nextStep: next)
    }

    private static func humanSummary(_ chain: TryFixChainJSON, outcome: FollowUpCoordinator.Outcome) -> String {
        var lines: [String] = []
        lines.append("# Diagnosis (\(outcome.parentRun.status.rawValue))")
        lines.append(outcome.parentRun.plan ?? "(no diagnosis output)")
        switch chain.status {
        case .fixAttempted:
            lines.append("\n# Fix attempt (\(outcome.childRun?.status.rawValue ?? "?"))")
            if case .allowed(let topId) = outcome.gate { lines.append("Tried hypothesis \(topId) within its boundary.") }
            lines.append(outcome.childRun?.plan ?? outcome.childRun?.workerAnswers.first?.output ?? "(no fix output)")
        case .blocked:
            lines.append("\n# No fix attempt — \(chain.gate.code ?? "blocked"): \(chain.gate.reason ?? "")")
        case .noPacket:
            lines.append("\n# No fix attempt — the diagnosis produced no typed fix packet.")
        }
        lines.append("\n→ \(chain.nextStep ?? "")")
        return lines.joined(separator: "\n")
    }

    static func reproduceCommand(_ run: TeamRun, project: Project) -> String {
        var parts = ["alln run", "--project", project.id]
        if let team = run.presetId { parts.append(contentsOf: ["--team", team]) }
        if let effort = run.effort { parts.append(contentsOf: ["--effort", effort.rawValue]) }
        return parts.joined(separator: " ")
    }
}
