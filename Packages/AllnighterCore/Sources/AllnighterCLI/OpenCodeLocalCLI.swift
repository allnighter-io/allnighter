import AllnighterCore
import Foundation

/// `alln opencode-local setup | undo | status` — additive OpenCode ↔ local
/// Ollama wiring. Merges into the user's `opencode.json`; never rewrites it
/// from a template. Setup observes `/api/tags` via the OCL-S01a observer
/// (injected transport in tests; never the real config path under XCTest).
enum OpenCodeLocalCLI {
    static func run(_ args: [String]) {
        let sub = args.first
        let rest = Array(args.dropFirst())
        switch sub {
        case "setup": setup(rest)
        case "undo": undo(rest)
        case "status": status(rest)
        default:
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln opencode-local setup [--dry-run] [--json] | alln opencode-local undo [--json] | alln opencode-local status [--json]"
            )
        }
    }

    private static func setup(_ args: [String]) {
        let opts = Options(args)
        let urls = resolveURLs(opts)
        do {
            let report = try OpenCodeOllamaSetup.apply(
                configURL: urls.config,
                receiptURL: urls.receipt,
                now: Date(),
                dryRun: opts.flag("dry-run")
            )
            emit(report, json: opts.flag("json"))
        } catch {
            fail(error)
        }
    }

    private static func undo(_ args: [String]) {
        let opts = Options(args)
        let urls = resolveURLs(opts)
        do {
            let report = try OpenCodeOllamaSetup.undo(
                configURL: urls.config,
                receiptURL: urls.receipt,
                now: Date()
            )
            emit(report, json: opts.flag("json"))
        } catch {
            fail(error)
        }
    }

    private static func status(_ args: [String]) {
        let opts = Options(args)
        let urls = resolveURLs(opts)
        do {
            let report = try OpenCodeOllamaSetup.status(configURL: urls.config)
            emit(report, json: opts.flag("json"))
        } catch {
            fail(error)
        }
    }

    private struct URLs {
        var config: URL
        var receipt: URL
    }

    private static func resolveURLs(_ opts: Options) -> URLs {
        let override = opts.value("config").map { URL(fileURLWithPath: $0) }
        let config: URL
        do {
            config = try OpenCodeOllamaSetup.resolveConfigURL(
                override: override,
                isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
            )
        } catch {
            fail(error)
        }
        let receipt: URL
        if let raw = opts.value("receipt") {
            receipt = URL(fileURLWithPath: raw)
        } else if override != nil {
            receipt = config.deletingLastPathComponent()
                .appendingPathComponent("opencode_ollama_setup.json")
        } else {
            receipt = OpenCodeOllamaSetup.defaultReceiptURL
        }
        return URLs(config: config, receipt: receipt)
    }

    private static func emit(_ report: OpenCodeOllamaSetup.Report, json: Bool) {
        if json {
            print(AllnighterCLI.jsonString(report))
            return
        }
        print(report.message)
        print("Config: \(report.configPath)")
        if let backup = report.backupPath {
            print("Backup: \(backup)")
        }
        if let providers = report.enabledProviders {
            print("enabled_providers: \(providers.joined(separator: ", "))")
        }
        if let url = report.ollamaBaseURL {
            print("ollama baseURL: \(url)")
        }
        if let models = report.ollamaModelIds, !models.isEmpty {
            print("ollama models: \(models.joined(separator: ", "))")
        }
        if !report.addedModelIds.isEmpty {
            print("added models: \(report.addedModelIds.joined(separator: ", "))")
        }
        if report.wrote {
            print("Undo: \(report.undoCommand)")
        }
        if let action = report.leftoverServeAction {
            if let pid = report.leftoverServePID {
                print("Leftover serve: \(action) (pid \(pid))")
            } else {
                print("Leftover serve: \(action)")
            }
        }
    }

    private static func fail(_ error: Error) -> Never {
        let message: String
        if let typed = error as? OpenCodeOllamaSetup.Error {
            message = typed.description
        } else {
            message = error.localizedDescription
        }
        AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: message)
    }
}
