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
//   3. Unattended posture: declare "no human at the keyboard" so common
//      git/ssh terminal prompts fail closed instead of blocking forever.
//
// Limit (honest): these GIT_/SSH_ askpass vars do NOT suppress
// Security.framework / `git-credential-osxkeychain` Keychain modal dialogs.
// They shrink blast radius for terminal-prompt paths only. Stall diagnosis
// (ProcessOwnership) is what names the wedge when a modal still appears.
//
// Lives in AllnighterCore (the lowest target) because it is a common
// dependency of AllnighterEngine (imports AllnighterCore), the CLI targets
// (AllnighterCLI/ProveCLI, which import AllnighterEngine + AllnighterCore),
// and the Mac app (imports both AllnighterCore and AllnighterEngine
// directly) — see Apps/AllnighterMac/project.yml.
public struct AllnighterSpawnEnvironmentPolicy: SpawnEnvironmentPolicy {
    public init() {}

    /// The one definition of unattended-worker environment declarations.
    /// Every alln spawn site must merge these via `environment(for:)` or
    /// `processEnvironment(extra:)` — do not copy this dictionary elsewhere.
    public static let nonInteractiveWorkerEnvironment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "/usr/bin/true",
        "SSH_ASKPASS": "/usr/bin/true",
        "SSH_ASKPASS_REQUIRE": "never",
    ]

    public func environment(for base: [String: String]) -> [String: String] {
        var env = base
        // Recursion guard (RB6): every spawned worker carries depth+1.
        let depth = Int(env["ALLNIGHTER_TEAM_DEPTH"] ?? "0") ?? 0
        env["ALLNIGHTER_TEAM_DEPTH"] = String(depth + 1)
        // Scrub the loopback tool token from deep workers.
        env["ALLNIGHTER_TOOL_TOKEN"] = nil
        // Unattended posture — common git/ssh prompts fail closed (see limit above).
        for (key, value) in Self.nonInteractiveWorkerEnvironment {
            env[key] = value
        }
        return env
    }

    /// Build the env for a `Foundation.Process` spawn site that does not go
    /// through `CommandRunner`. ONE definition — same policy as runners.
    public static func processEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var env = base
        for (key, value) in extra { env[key] = value }
        return AllnighterSpawnEnvironmentPolicy().environment(for: env)
    }
}
