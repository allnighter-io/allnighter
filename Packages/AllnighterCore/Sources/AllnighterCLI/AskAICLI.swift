import Foundation
import AllnighterCore
import AllnighterEngine

/// Undocumented developer door for Ask AI. Not in `alln menu`, not in help,
/// not in ContractRegistry — so it does not ship as a customer surface.
///
///     alln dev ask-ai --probes
///     alln dev ask-ai "question" --print-prompt
///     alln dev ask-ai --probe boost_window --print-prompt
///     alln dev ask-ai "question" --run --json
enum AskAICLI {
    static let usage = """
        usage: alln dev ask-ai --probes
               alln dev ask-ai \"<question>\" [--print-prompt]
               alln dev ask-ai --probe <id> [--print-prompt]
               alln dev ask-ai \"<question>\" --run [--project <id|path>] [--json] [--dry-run] [--no-wait]
        Developer only. Same Auto + inward preamble as the Mac title-bar Ask AI.
        Default is --print-prompt (no quota). --run spends a read-only Auto turn.
        --project is required for --run when cwd is not a registered project.
        """

    struct Parsed: Equatable {
        var probes: Bool = false
        var printPrompt: Bool = false
        var run: Bool = false
        var json: Bool = false
        var dryRun: Bool = false
        var noWait: Bool = false
        var probeId: String?
        var project: String?
        var question: String?
        var unknownFlag: String?
    }

    static func parse(_ args: [String]) -> Parsed {
        var parsed = Parsed()
        var i = 0
        var positionals: [String] = []
        while i < args.count {
            let a = args[i]
            if a == "--probes" {
                parsed.probes = true
                i += 1
            } else if a == "--print-prompt" {
                parsed.printPrompt = true
                i += 1
            } else if a == "--run" {
                parsed.run = true
                i += 1
            } else if a == "--json" {
                parsed.json = true
                i += 1
            } else if a == "--dry-run" {
                parsed.dryRun = true
                i += 1
            } else if a == "--no-wait" {
                parsed.noWait = true
                i += 1
            } else if a == "--probe", i + 1 < args.count {
                parsed.probeId = args[i + 1]
                i += 2
            } else if a == "--project", i + 1 < args.count {
                parsed.project = args[i + 1]
                i += 2
            } else if a.hasPrefix("--") {
                parsed.unknownFlag = a
                i += 1
            } else {
                positionals.append(a)
                i += 1
            }
        }
        if parsed.question == nil, let joined = positionals.joined(separator: " ").nilIfEmpty {
            parsed.question = joined
        }
        return parsed
    }

    static func resolvedQuestion(_ parsed: Parsed) -> (question: String?, error: String?) {
        if let id = parsed.probeId {
            guard let probe = AskAIPrompt.probe(id: id) else {
                let known = AskAIPrompt.probes.map(\.id).joined(separator: ", ")
                return (nil, "unknown probe '\(id)'. Known: \(known)")
            }
            return (probe.question, nil)
        }
        if let q = parsed.question?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            return (q, nil)
        }
        return (nil, "missing question")
    }

    static func probesJSON() -> String {
        struct Payload: Encodable {
            let schemaVersion = 1
            let supportEmail = AskAIPrompt.supportEmail
            let probes: [AskAIPrompt.Probe]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(Payload(probes: AskAIPrompt.probes))) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func assembledPrompt(question: String, context: AskAIPrompt.Context = .fromThisMac()) -> String {
        AskAIPrompt.assemble(question: question, context: context)
    }

    /// PATH/version from this process plus cached bench tally. Never probes vendors.
    static func contextFromRuntime(_ runtime: ToolRuntime) -> AskAIPrompt.Context {
        var ctx = AskAIPrompt.Context.fromThisMac()
        let setup = SetupStore().load()
        let tally = BenchTallyProjector.tally(
            registry: runtime.registry,
            records: setup.records,
            parked: setup.parkedSet
        )
        ctx.benchHeadline = tally.headline.rawValue
        ctx.benchReady = tally.ready
        ctx.benchNeedsStep = tally.needsStep
        ctx.benchSupported = tally.supported
        return ctx
    }

    static func run(_ args: [String], runtime: ToolRuntime) async {
        if args.contains("--help") || args.contains("-h") || args.isEmpty {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(args.isEmpty ? 2 : 0)
        }
        let parsed = parse(args)
        if let flag = parsed.unknownFlag {
            FileHandle.standardError.write(Data("unknown flag: \(flag)\n\(usage)\n".utf8))
            exit(2)
        }
        if parsed.probes {
            print(probesJSON())
            return
        }
        let resolved = resolvedQuestion(parsed)
        guard let question = resolved.question else {
            FileHandle.standardError.write(Data("\(resolved.error ?? "missing question")\n\(usage)\n".utf8))
            exit(2)
        }
        let prompt = assembledPrompt(question: question, context: contextFromRuntime(runtime))
        if parsed.run {
            var runArgs = [prompt, "--read-only"]
            if let project = parsed.project {
                runArgs.append(contentsOf: ["--project", project])
            }
            if parsed.json { runArgs.append("--json") }
            if parsed.dryRun { runArgs.append("--dry-run") }
            if parsed.noWait { runArgs.append("--no-wait") }
            await RunCLI.run(runArgs, runtime: runtime)
            return
        }
        print(prompt)
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
