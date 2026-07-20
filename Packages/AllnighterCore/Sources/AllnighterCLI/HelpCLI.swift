import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln help …` — the installed product guide (search/get/topics), the one help
/// surface any calling agent uses via `HelpProjector`. `alln docs` stays the raw
/// generated contract reference; `alln help` is the friendly retrieval surface.
enum HelpCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        switch args.first {
        case "search": search(Array(args.dropFirst()))
        case "get": get(Array(args.dropFirst()))
        case "topics": topics(Array(args.dropFirst()))
        case nil: topics([])
        default: get(args)   // friendly: `alln help pending` == `alln help get pending`
        }
    }

    private static var cv: String { ContractRegistry.contractVersion }

    private static func search(_ args: [String]) {
        let opts = Options(args)
        let query = opts.positional.joined(separator: " ")
        guard !query.isEmpty else { usage("search <query> [--limit N] [--json]") }
        let limit = opts.value("limit").flatMap(Int.init) ?? 5
        let json = HelpProjector.search(query, limit: limit, contractVersion: cv)
        if opts.flag("json") { print(AllnighterCLI.jsonString(json)); return }
        if let answer = json.suggestedAnswerMarkdown { print(answer + "\n") }
        for hit in json.results {
            let live = hit.needsLiveCheck ? "  (needs live check)" : ""
            print("\(hit.topicId)\t\(String(format: "%.2f", hit.score))\t\(hit.title)\(live)")
            print("  \(hit.summary)")
        }
        if let step = json.nextToolPlan.first {
            print("\nnext: \(step.command)")
        }
    }

    private static func get(_ args: [String]) {
        let opts = Options(args)
        let topic = opts.positional.first
        let json = HelpProjector.get(
            topic: topic, ref: opts.value("ref"), error: opts.value("error"), contractVersion: cv)

        if opts.flag("json") { print(AllnighterCLI.jsonString(json)); return }

        guard let t = json.topic else {
            // Not found: close matches + sitemap, never a dead end.
            print("No topic for that selector.")
            if !json.closeMatches.isEmpty { print("did you mean: " + json.closeMatches.joined(separator: ", ")) }
            print("topics: " + json.sitemap.map(\.topicId).joined(separator: ", "))
            if let step = json.nextToolPlan.first {
                print("\nnext: \(step.command)")
            }
            return
        }

        if opts.value("format") == "md" {
            print(HelpService.topicMarkdown(t))
            return
        }
        print("\(t.title)\n\(t.summary)\n")
        print(t.bodyMarkdown)
        if !t.relatedCommandNames.isEmpty {
            print("\ncommands: " + t.relatedCommandNames.map { "alln \($0)" }.joined(separator: ", "))
        }
        if t.needsLiveCheck { print("\n(this answer depends on live state — run `alln doctor` / `alln menu --json`)") }
        if let step = json.nextToolPlan.first {
            print("\nnext: \(step.command)")
        }
    }

    private static func topics(_ args: [String]) {
        let opts = Options(args)
        let json = HelpProjector.topics(contractVersion: cv)
        if opts.flag("json") { print(AllnighterCLI.jsonString(json)); return }
        print(json.routingLaw + "\n")
        for t in json.topics { print("\(t.topicId)\t\(t.title)\n  \(t.summary)") }
    }

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln help \(detail)\n".utf8))
        exit(2)
    }
}
