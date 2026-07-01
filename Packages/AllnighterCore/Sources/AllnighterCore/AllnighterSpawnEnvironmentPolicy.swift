import Foundation

// Spawn environment policy for every `SubprocessCommandRunner` Allnighter
// constructs (A1 — AgentOS relocation). AgentOS's `SubprocessCommandRunner`
// no longer hardcodes Allnighter's env guards; it takes an injected
// `SpawnEnvironmentPolicy` (default: identity). This type reinstates the two
// behaviors that used to be baked into AgentOS, applied uniformly to every
// spawn so prior behavior is preserved exactly:
//   1. Team-recursion guard (RB6): increment ALLNIGHTER_TEAM_DEPTH so nested
//      team spawns can detect and refuse recursion.
//   2. Security: scrub ALLNIGHTER_TOOL_TOKEN so a deep worker process can't
//      authenticate to the loopback tool server.
//
// Lives in AllnighterCore (the lowest target) because it is a common
// dependency of AllnighterEngine (imports AllnighterCore), the CLI targets
// (AllnighterCLI/ProveCLI, which import AllnighterEngine + AllnighterCore),
// and the Mac app (imports both AllnighterCore and AllnighterEngine
// directly) — see Apps/AllnighterMac/project.yml.
public struct AllnighterSpawnEnvironmentPolicy: SpawnEnvironmentPolicy {
    public init() {}
    public func environment(for base: [String: String]) -> [String: String] {
        var env = base
        // Recursion guard (RB6): every spawned worker carries depth+1.
        let depth = Int(env["ALLNIGHTER_TEAM_DEPTH"] ?? "0") ?? 0
        env["ALLNIGHTER_TEAM_DEPTH"] = String(depth + 1)
        // Scrub the loopback tool token from deep workers.
        env["ALLNIGHTER_TOOL_TOKEN"] = nil
        return env
    }
}
