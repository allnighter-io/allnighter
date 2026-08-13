import AllnighterCore
import Foundation

/// `alln claude-local status` — disclose per-run isolation. Never writes the
/// user shell, Claude settings, or Keychain. Seating is `alln models add`
/// with label `ollama/<tag>`.
enum ClaudeLocalCLI {
    static func run(_ args: [String]) {
        let sub = args.first
        let rest = Array(args.dropFirst())
        switch sub {
        case "status": status(rest)
        default:
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln claude-local status [--json]"
            )
        }
    }

    private static func status(_ args: [String]) {
        let opts = Options(args)
        let report = ClaudeLocalIsolation.statusReport()
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(report))
            return
        }
        print("Claude-local isolation is per-run only.")
        print("Base URL: \(report.anthropicBaseURL)")
        print("Auth token: \(report.anthropicAuthToken) (not a stored credential)")
        print("API key: empty overlay (overrides inherited paid key for this spawn)")
        print("Signal source: \(report.signalSourceId)")
        print("Seat with: \(report.seating)")
        print("Does not write shell profiles or Claude settings. Does not read Keychain.")
        print("A local failure is not an Anthropic limit.")
        print("Verify uses local evidence (binary + Ollama tag), not Claude invoke smoke.")
        print("Served context window env (\(report.contextWindowEnvKey)) is set only when observed.")
    }
}
