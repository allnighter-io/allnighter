import Foundation
import AllnighterCore
import AllnighterEngine

enum ModelsCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else {
            await runList(args, runtime)
            return
        }
        switch sub {
        case "enable": runEnable(Array(args.dropFirst()), runtime)
        case "disable": runDisable(Array(args.dropFirst()), runtime)
        case "add": runAdd(Array(args.dropFirst()), runtime)
        case "update": runUpdate(Array(args.dropFirst()), runtime)
        case "delete": runDelete(Array(args.dropFirst()), runtime)
        case "verify": await runVerify(Array(args.dropFirst()), runtime)
        default: await runList(args, runtime)
        }
    }

    /// Single resolution path for human + `--json` (Agent_Front_Door.md §F3).
    static func modelListJSON(
        runtime: ToolRuntime,
        driverId: String? = nil,
        benchOnly: Bool = false,
        now: Date = Date(),
        ollamaLocal: OllamaLocalRuntimeObserver.Snapshot? = nil,
        observeOllamaReadiness: Bool = false
    ) -> ModelListJSON {
        var defs = ModelCatalog.list(driverId: driverId)
        if benchOnly {
            let enabled = Set(ModelCatalog.benchModels(registry: runtime.registry).map(\.id))
            defs = defs.filter { enabled.contains($0.id) }
        }
        let records = SetupStore().load().records
        let parked = SetupStore().load().parkedSet
        let snapshot = ollamaLocal ?? (observeOllamaReadiness
            ? OllamaLocalDoctorReport.snapshotIfAllowed(
                transport: nil,
                observedAt: now,
                isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
            )
            : nil)
        return ModelListProjector.build(
            registry: runtime.registry,
            definitions: defs,
            probeRecords: records,
            now: now,
            diagnostics: ModelCatalog.diagnostics(registry: runtime.registry),
            benchOnly: benchOnly,
            driverId: driverId,
            parkedDriverIds: parked,
            ollamaLocal: snapshot
        )
    }

    private static func runList(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        let driver = opts.value("driver")
        let bench = opts.flag("bench")
        let list = modelListJSON(
            runtime: runtime, driverId: driver, benchOnly: bench, observeOllamaReadiness: true)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(list))
        } else {
            printHuman(list)
        }
    }

    static func printHuman(_ list: ModelListJSON) {
        if list.models.isEmpty {
            if let counsel = list.counsel { print(counsel) }
            for action in list.nextActions { print("→ \(action.command)") }
            return
        }
        for m in list.models {
            let benchMark = m.enabled ? "onBench" : "available"
            let readyMark = m.ready ? "ready" : m.status
            var line = "\(m.id)\t\(m.displayName)\t\(m.driverId)\t\(benchMark)\t\(readyMark)"
            if let readiness = m.readiness {
                line += "\t\(readiness)"
            }
            if let def = ModelCatalog.get(m.id), def.origin == .custom,
               let smoke = def.modelSmokeStatus {
                line += "\t\(smoke)"
            }
            print(line)
        }
    }

    private static func runEnable(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usage("enable <model-id> [--body claude_code|opencode]"); return
        }
        do {
            if let body = opts.value("body") {
                let now = Date()
                let snapshot = OllamaLocalDoctorReport.snapshotIfAllowed(
                    transport: nil,
                    observedAt: now,
                    isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
                )
                let assessment = try LocalRuntimeSeatMint.enable(
                    candidateID: id,
                    bodyDriverId: body,
                    snapshot: snapshot,
                    now: now
                )
                // Policy already writes the strings (including nil-G1). Do not
                // invent a fail line. stderr keeps `--json` ModelListJSON intact.
                for line in assessment.disclosures {
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                }
            } else {
                try ModelCatalog.setEnabled(id, true)
            }
            emitList(opts, runtime)
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func runDisable(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usage("disable <model-id>"); return
        }
        do {
            try ModelCatalog.setEnabled(id, false)
            emitList(opts, runtime)
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func runAdd(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let driver = opts.value("driver"),
              let name = opts.value("name"),
              let label = opts.value("model-label") else {
            usage("add --driver <driverId> --name <display-name> --model-label <label> [--role answerer|planWriter|both] [--disabled] [--json] (then: alln models verify <id>)")
            return
        }
        let role = opts.value("role").flatMap(ModelRole.init(rawValue:)) ?? .answerer
        let enabled = !opts.flag("disabled")
        do {
            let created = try ModelCatalog.createCustom(
                driverId: driver, displayName: name, modelLabel: label,
                role: role, enabled: enabled, registry: runtime.registry)
            emitList(opts, runtime)
            if !opts.flag("json") {
                print("Added as Unrated — seats last.")
                print("saved as unverified — run: alln models verify \(created.id)")
            }
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func runUpdate(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usage("update <custom-model-id> [--name <display-name>] [--model-label <label>] [--role ...] [--json]")
            return
        }
        guard var def = ModelCatalog.get(id), def.origin == .custom else {
            emitModelError(.builtInImmutable); return
        }
        if let name = opts.value("name") { def.displayName = name }
        if let label = opts.value("model-label") { def.modelLabel = label }
        if let roleRaw = opts.value("role"), let role = ModelRole(rawValue: roleRaw) { def.role = role }
        if opts.value("driver") != nil {
            emitFailure("MODEL_INVALID", "driverId cannot change; delete and recreate"); return
        }
        do {
            try ModelCatalog.updateCustom(def)
            emitList(opts, runtime)
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func runDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usage("delete <custom-model-id>"); return
        }
        do {
            let outcome = try LocalRuntimeSeatDelete.delete(id: id)
            for line in outcome.disclosures {
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
            emitList(opts, runtime)
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func runVerify(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usage("verify <custom-model-id>"); return
        }
        do {
            let smoke = try await ModelCatalog.verifyModelSmoke(
                id: id,
                registry: runtime.registry,
                probeRecords: SetupStore().load().records,
                ollamaSnapshot: OllamaLocalDoctorReport.snapshotIfAllowed(
                    transport: nil,
                    observedAt: Date(),
                    isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
                )
            )
            if opts.flag("json") {
                struct Payload: Encodable {
                    var id: String
                    var status: String
                    var detail: String?
                    var driverId: String
                    var label: String
                }
                print(AllnighterCLI.jsonString(Payload(
                    id: id,
                    status: smoke.status.rawValue,
                    detail: smoke.detail,
                    driverId: smoke.driverId,
                    label: smoke.label
                )))
            } else {
                var line = "\(id)\t\(smoke.status.rawValue)"
                if let detail = smoke.detail { line += "\t\(detail)" }
                print(line)
            }
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func emitList(_ opts: Options, _ runtime: ToolRuntime) {
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(modelListJSON(runtime: runtime, observeOllamaReadiness: true)))
        }
    }

    private static func usage(_ detail: String) {
        FileHandle.standardError.write(Data("usage: alln models \(detail) [--json]\n".utf8))
        exit(2)
    }

    private static func emitFailure(_ code: String, _ message: String) -> Never {
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func emitModelError(_ error: ModelCatalogError) -> Never {
        let (code, message) = AllnighterCLI.modelCatalogErrorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }
}
