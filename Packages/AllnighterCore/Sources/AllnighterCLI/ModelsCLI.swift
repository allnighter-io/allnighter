import Foundation
import AllnighterCore
import AllnighterEngine

enum ModelListProjector {
    static func build(
        registry: DriverRegistry,
        definitions: [ModelDefinition],
        probeRecords: [ToolProbeRecord],
        diagnostics: [ModelCatalogDiagnostic]
    ) -> ModelListJSON {
        let recordsByDriver = Dictionary(uniqueKeysWithValues: probeRecords.map { ($0.driverId, $0) })
        let manifestIDs = Set(registry.all.map(\.id))
        let resolved = ModelCatalog.resolvedModels(registry: registry)
        let enabledMap = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0.enabled) })
        let entries = definitions.sorted { $0.id < $1.id }.map { def -> ModelListJSON.Entry in
            let enabled = enabledMap[def.id] ?? def.defaultEnabled
            let driverMissing = !manifestIDs.contains(def.driverId)
            let record = recordsByDriver[def.driverId]
            let ready = !driverMissing && (record?.status.isReady ?? false)
            let status: String
            if driverMissing {
                status = "driverMissing"
            } else if let record {
                status = record.status.isReady ? "ready" : "notReady"
            } else {
                status = "notChecked"
            }
            let driverName = registry.manifest(id: def.driverId)?.displayName ?? def.driverId
            return ModelListJSON.Entry(
                id: def.id,
                displayName: def.displayName,
                modelLabel: def.modelLabel,
                driverId: def.driverId,
                driverName: driverName,
                role: def.role.rawValue,
                origin: def.origin.rawValue,
                enabled: enabled,
                ready: ready,
                status: status,
                state: enabled ? "onBench" : "available",
                capabilities: ModelCatalog.capabilities(def.id)
            )
        }
        return ModelListJSON(
            contractVersion: ContractRegistry.contractVersion,
            models: entries,
            diagnostics: diagnostics
        )
    }
}

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
        default: await runList(args, runtime)
        }
    }

    static func modelListJSON(
        runtime: ToolRuntime,
        driverId: String? = nil,
        benchOnly: Bool = false
    ) -> ModelListJSON {
        var defs = ModelCatalog.list(driverId: driverId)
        if benchOnly {
            let enabled = Set(ModelCatalog.benchModels(registry: runtime.registry).map(\.id))
            defs = defs.filter { enabled.contains($0.id) }
        }
        let records = SetupStore().load().records
        return ModelListProjector.build(
            registry: runtime.registry,
            definitions: defs,
            probeRecords: records,
            diagnostics: ModelCatalog.diagnostics(registry: runtime.registry)
        )
    }

    private static func runList(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        let driver = opts.value("driver")
        let bench = opts.flag("bench")
        let list = modelListJSON(runtime: runtime, driverId: driver, benchOnly: bench)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(list))
        } else {
            for m in list.models {
                let benchMark = m.enabled ? "onBench" : "available"
                let readyMark = m.ready ? "ready" : m.status
                print("\(m.id)\t\(m.displayName)\t\(m.driverId)\t\(benchMark)\t\(readyMark)")
            }
        }
    }

    private static func runEnable(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            usage("enable <model-id>"); return
        }
        do {
            try ModelCatalog.setEnabled(id, true)
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
            usage("add --driver <driverId> --name <display-name> --model-label <label> [--role answerer|planWriter|both] [--disabled] [--json]")
            return
        }
        let role = opts.value("role").flatMap(ModelRole.init(rawValue:)) ?? .answerer
        let enabled = !opts.flag("disabled")
        do {
            _ = try ModelCatalog.createCustom(
                driverId: driver, displayName: name, modelLabel: label,
                role: role, enabled: enabled, registry: runtime.registry)
            emitList(opts, runtime)
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
            try ModelCatalog.deleteCustom(id)
            emitList(opts, runtime)
        } catch let error as ModelCatalogError {
            emitModelError(error)
        } catch {
            emitFailure("MODEL_INVALID", error.localizedDescription)
        }
    }

    private static func emitList(_ opts: Options, _ runtime: ToolRuntime) {
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(modelListJSON(runtime: runtime)))
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
