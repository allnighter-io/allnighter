import Foundation
import AllnighterCore
import AllnighterEngine

enum PendingCLI {
    static func run(_ subcommand: String?, _ args: [String], runtime: ToolRuntime) async {
        switch subcommand {
        case "add": runAdd(args, runtime)
        case "list": runList(args, runtime)
        case "show": runShow(args, runtime)
        case "submit": runSubmit(args, runtime)
        case "edit": runEdit(args, runtime)
        case "reorder": runReorder(args, runtime)
        case "cancel": runCancel(args, runtime)
        case "run": await runRun(args, runtime)
        case nil:
            FileHandle.standardError.write(Data("usage: alln pending <add|list|show|submit|edit|reorder|cancel|run> ...\n".utf8))
            exit(2)
        default:
            FileHandle.standardError.write(Data("unknown pending subcommand: \(subcommand!)\n".utf8))
            exit(2)
        }
    }

    // MARK: - Commands

    private static func runAdd(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let prompt = loadPrompt(opts)
        guard !prompt.isEmpty else {
            usageError("pending add requires a prompt (positional or --file)")
        }
        let service = makeService(runtime)
        let drainMode = parseWhen(opts.value("when"))
        let fallbacks = opts.value("fallback").map { [$0] } ?? []
        do {
            let item = try service.add(.init(
                prompt: prompt,
                workerToken: opts.value("worker"),
                teamPresetId: opts.value("team"),
                fallbackTokens: fallbacks,
                drainMode: drainMode,
                workingDir: opts.value("cwd"),
                submit: opts.flag("submit")
            ))
            emit(item, service: service, json: opts.flag("json"))
        } catch {
            emitPendingError(error)
        }
    }

    private static func runList(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let service = makeService(runtime)
        do {
            let items = try service.list()
            if opts.flag("json") {
                let projections = try items.map { try service.mapJSON($0) }
                print(AllnighterCLI.jsonString(PendingListJSON(contractVersion: ContractRegistry.contractVersion, items: projections)))
            } else {
                for item in items {
                    print("\(item.id)\t\(item.status.rawValue)\t\(item.title)")
                }
            }
        } catch {
            emitPendingError(error)
        }
    }

    private static func runShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else { usageError("usage: alln pending show <pending-id> [--json]") }
        let service = makeService(runtime)
        do {
            guard let item = try service.store.load(id: id) else {
                AllnighterCLI.fail(code: "RUN_NOT_FOUND", message: "pending item not found: \(id)")
            }
            emit(item, service: service, json: opts.flag("json"))
        } catch {
            emitPendingError(error)
        }
    }

    private static func runSubmit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else { usageError("usage: alln pending submit <pending-id> [--json]") }
        let service = makeService(runtime)
        do {
            let item = try service.submit(id: id)
            emit(item, service: service, json: opts.flag("json"))
        } catch {
            emitPendingError(error)
        }
    }

    private static func runEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usageError("usage: alln pending edit <pending-id> [--prompt <text> | --file <path>] ...")
        }
        let service = makeService(runtime)
        let prompt = opts.value("prompt") ?? opts.value("file").flatMap { try? String(contentsOfFile: $0) }
        let fallbacks = opts.value("fallback").map { [$0] }
        do {
            let item = try service.edit(id: id, .init(
                prompt: prompt,
                workerToken: opts.value("worker"),
                teamPresetId: opts.value("team"),
                fallbackTokens: fallbacks,
                drainMode: opts.value("when").map { parseWhen($0) },
                workingDir: opts.value("cwd")
            ))
            emit(item, service: service, json: opts.flag("json"))
        } catch {
            emitPendingError(error)
        }
    }

    private static func runReorder(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usageError("usage: alln pending reorder <pending-id> [--before <id> | --after <id> | --position <n>] [--json]")
        }
        let anchor: PendingService.ReorderAnchor
        if let before = opts.value("before") {
            anchor = .before(before)
        } else if let after = opts.value("after") {
            anchor = .after(after)
        } else if let pos = opts.value("position"), let n = Int(pos) {
            anchor = .position(n)
        } else {
            usageError("reorder requires --before, --after, or --position")
        }
        let service = makeService(runtime)
        do {
            let item = try service.reorder(id: id, anchor: anchor)
            emit(item, service: service, json: opts.flag("json"), userReordered: true)
        } catch let error as PendingServiceError {
            if case .reorderInvalid = error {
                AllnighterCLI.emitFailure(code: "PENDING_REORDER_INVALID", message: String(describing: error))
                exit(1)
            }
            emitPendingError(error)
        } catch {
            emitPendingError(error)
        }
    }

    private static func runCancel(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else { usageError("usage: alln pending cancel <pending-id> [--json]") }
        let service = makeService(runtime)
        do {
            let item = try service.cancel(id: id)
            emit(item, service: service, json: opts.flag("json"))
        } catch {
            emitPendingError(error)
        }
    }

    private static func runRun(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        if opts.flag("json") && opts.flag("stream") {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--json and --stream are mutually exclusive")
        }
        guard let id = opts.positional.first else { usageError("usage: alln pending run <pending-id> [--json]") }
        let executor = makeExecutor(runtime)
        do {
            let item = try await executor.run(id: id)
            emit(item, service: executor.service, json: opts.flag("json"))
        } catch let error as PendingServiceError {
            if case .mutationDeferred = error {
                AllnighterCLI.fail(code: "PENDING_MUTATION_DEFERRED", message: "mutating runs are outside Pending M1")
            }
            if case .unsupportedKind(let kind) = error {
                AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "pending kind \(kind) is not runnable in this milestone; only workerChat is supported")
            }
            emitPendingError(error)
        } catch {
            emitPendingError(error)
        }
    }

    // MARK: - Helpers

    private static func makeService(_ runtime: ToolRuntime) -> PendingService {
        PendingService(store: PendingStore(), models: runtime.models)
    }

    private static func makeExecutor(_ runtime: ToolRuntime) -> PendingRunExecutor {
        let service = makeService(runtime)
        return PendingRunExecutor(
            service: service,
            registry: runtime.registry,
            commandRunner: SubprocessCommandRunner(),
            invocations: runtime.invocations
        )
    }

    private static func loadPrompt(_ opts: Options) -> String {
        if let file = opts.value("file"), let text = try? String(contentsOfFile: file) { return text }
        return opts.positional.joined(separator: " ")
    }

    private static func parseWhen(_ raw: String?) -> PendingDrainMode {
        switch raw?.lowercased() {
        case "ready": return .drainWhenReady
        case "away": return .drainAway
        case "manual": return .manualStart
        default: return .manualStart
        }
    }

    private static func emit(_ item: PendingItem, service: PendingService, json: Bool, userReordered: Bool? = nil) {
        if json {
            do {
                print(AllnighterCLI.jsonString(try service.mapJSON(item, userReordered: userReordered)))
            } catch {
                emitPendingError(error)
            }
        } else {
            print("\(item.id)\t\(item.status.rawValue)\t\(item.title)")
        }
    }

    private static func emitPendingError(_ error: Error) -> Never {
        let code: String
        let message: String
        if let err = error as? PendingServiceError {
            switch err {
            case .notFound(let id):
                (code, message) = ("RUN_NOT_FOUND", "pending item not found: \(id)")
            case .invalidWorker(let token):
                (code, message) = ("MODEL_UNAVAILABLE", "unknown worker: \(token)")
            case .invalidState(let detail):
                (code, message) = ("CLI_USAGE_ERROR", detail)
            case .reorderInvalid(let detail):
                (code, message) = ("PENDING_REORDER_INVALID", detail)
            case .mutationDeferred:
                (code, message) = ("PENDING_MUTATION_DEFERRED", "mutating runs are outside Pending M1")
            case .sourceGateBlocked(let blocker):
                (code, message) = (blocker.code, blocker.message)
            case .unsupportedKind(let kind):
                (code, message) = ("CLI_USAGE_ERROR", "pending kind \(kind) is not runnable in this milestone; only workerChat is supported")
            }
        } else {
            (code, message) = ("INTERNAL_ERROR", String(describing: error))
        }
        // Exit code is derived from the catalog (usage → 2, operational → 1).
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func usageError(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(2)
    }
}
