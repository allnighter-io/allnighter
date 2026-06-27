import Foundation
import AllnighterCore

// First-run CLI detection (docs/phases/setup/01 §4). Resolves each tool the way
// the user's terminal does (login-shell `command -v`), version-checks it, smoke-
// tests it, and classifies it into the canonical `ModelSetupStatus`. The same
// resolved `ToolInvocation` is reused for runs so health == runs.

// MARK: - ShellResolver

/// Resolves command names through the user's login+interactive shell — catching
/// aliases, functions, and version-manager shims a bare PATH scan misses. Batched
/// (one shell session for all bins) and sentinel-guarded so noisy `.zshrc` stdout
/// can't corrupt the answer. zsh/bash supported; fish best-effort.
public struct ShellResolver: Sendable {
    private let commandRunner: CommandRunner
    private let shellPath: String
    private let timeout: Duration
    /// Neutral CWD for the resolve shell so it never inherits the repo/Documents
    /// working dir (Launch Authority TCC hotfix, slice H3).
    private let workingDirectory: String?
    /// When true, resolve through an INTERACTIVE login shell (`-lic`) so the
    /// user's `.zshrc` PATH (bun/asdf/custom prefixes set only there) is seen —
    /// the explicit-setup path the founder accepts a one-time TCC prompt for.
    /// Default false (`-lc`): TCC-safe, used everywhere that is not explicit
    /// setup intent. NEVER set true on a launch/background path. (Track 0.1)
    private let interactive: Bool

    public init(
        commandRunner: CommandRunner,
        shellPath: String? = nil,
        timeout: Duration = .seconds(5),
        workingDirectory: String? = AllnighterPaths.ensuredProbeScratchPath(),
        interactive: Bool = false
    ) {
        self.commandRunner = commandRunner
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.timeout = timeout
        self.workingDirectory = workingDirectory
        self.interactive = interactive
    }

    public struct Resolution: Sendable, Equatable {
        public var bin: String
        /// Trimmed `command -v` output: an absolute path, an alias/function line, or "".
        public var raw: String
        public var found: Bool { !raw.isEmpty }
        public var isPath: Bool { raw.hasPrefix("/") }
    }

    public func resolve(_ bins: [String]) async -> [String: Resolution] {
        var out: [String: Resolution] = [:]
        for b in bins { out[b] = Resolution(bin: b, raw: "") }
        guard !bins.isEmpty else { return out }

        // One login shell; sentinel-wrapped `command -v` per bin.
        let list = bins.joined(separator: " ")
        let script = "for b in \(list); do printf '<<<ALR:%s|%s>>>\\n' \"$b\" \"$(command -v \"$b\" 2>/dev/null)\"; done"
        // `-lc` (default): non-interactive login shell — login profiles only, NOT
        // the interactive `.zshrc` whose dev tools touch protected folders and
        // raise TCC prompts attributed to the GUI app. TCC-safe.
        // `-lic` (interactive, explicit setup only): also sources `.zshrc`, so the
        // user's interactive PATH (bun/asdf/custom prefixes) resolves — closing the
        // ".zshrc PATH" gap. The founder accepts the one-time setup prompt for this;
        // it MUST NOT be reached on a launch/background path. (Track 0.1)
        let loginFlag = interactive ? "-lic" : "-lc"
        let result = await commandRunner.run(
            command: shellPath, args: [loginFlag, script],
            stdin: nil, env: [:], workingDirectory: workingDirectory, timeout: timeout
        )

        guard let regex = try? NSRegularExpression(pattern: #"<<<ALR:([^|]*)\|(.*?)>>>"#) else { return out }
        let ns = result.stdout as NSString
        regex.enumerateMatches(in: result.stdout, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges == 3 else { return }
            let bin = ns.substring(with: match.range(at: 1))
            let val = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if out[bin] != nil { out[bin] = Resolution(bin: bin, raw: val) }
        }
        return out
    }
}

// MARK: - CLIDetector

public struct CLIDetector: Sendable {
    private let commandRunner: CommandRunner
    private let resolver: ShellResolver
    private let shellPath: String
    private let home: String
    private let detectTimeout: Duration
    private let smokeTimeout: Duration
    /// Neutral CWD for every detect/version/smoke child process so they never
    /// inherit the repo/Documents working dir (Launch Authority TCC hotfix, H3).
    private let workingDirectory: String?
    /// Shared install dirs scanned (in addition to a manifest's own knownPaths)
    /// when the shell can't resolve a bin — the free net before Spotlight/agent.
    private let commonBinDirs: [String]

    /// Common CLI install locations across managers, `~` expands against `home`.
    public static let defaultCommonBinDirs: [String] = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
        "~/.local/bin", "~/.local/share/bin", "~/bin",
        "~/.bun/bin", "~/.deno/bin", "~/.cargo/bin",
        "~/.npm-global/bin", "~/.yarn/bin", "~/Library/pnpm",
        "~/.asdf/shims", "~/.local/share/mise/shims", "~/.volta/bin",
        "~/.grok/bin", "~/.antigravity/antigravity/bin",
    ]

    public init(
        commandRunner: CommandRunner,
        resolver: ShellResolver? = nil,
        shellPath: String? = nil,
        home: String? = nil,
        detectTimeout: Duration = .seconds(8),
        smokeTimeout: Duration = .seconds(60),
        workingDirectory: String? = AllnighterPaths.ensuredProbeScratchPath(),
        interactive: Bool = false,
        commonBinDirs: [String] = CLIDetector.defaultCommonBinDirs
    ) {
        self.commandRunner = commandRunner
        let sh = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellPath = sh
        self.resolver = resolver ?? ShellResolver(commandRunner: commandRunner, shellPath: sh, workingDirectory: workingDirectory, interactive: interactive)
        self.home = home ?? NSHomeDirectory()
        self.detectTimeout = detectTimeout
        self.smokeTimeout = smokeTimeout
        self.workingDirectory = workingDirectory
        self.commonBinDirs = commonBinDirs
    }

    /// Probe every headless-CLI tool (one resolve batch, then per-tool detect+smoke).
    /// `smoke: false` is the quota-free path (resolve + version only, no model
    /// call) used by default `alln doctor`; `true` (the default) keeps the full
    /// `alln detect` / `doctor --full` behavior.
    public func probeAll(_ manifests: [DriverManifest], models: [String: String], now: Date, smoke: Bool = true) async -> [ToolProbeRecord] {
        let tools = manifests.filter { $0.kind == .headlessCLI }
        let resolutions = await resolver.resolve(Array(Set(tools.flatMap(bins(for:)))))
        var records: [ToolProbeRecord] = []
        for tool in tools {
            records.append(await probe(tool, model: models[tool.id] ?? "", resolutions: resolutions, now: now, smoke: smoke))
        }
        return records
    }

    public func probe(
        _ manifest: DriverManifest,
        model: String,
        resolutions: [String: ShellResolver.Resolution]? = nil,
        now: Date,
        smoke: Bool = true
    ) async -> ToolProbeRecord {
        let bins = bins(for: manifest)
        let res: [String: ShellResolver.Resolution]
        if let resolutions { res = resolutions } else { res = await resolver.resolve(bins) }

        // 1. Resolve to an invocation (path → direct; bare-path alias → shim;
        // alias-with-flags / function → confirm).
        var invocation: ToolInvocation?
        for b in bins {
            guard let r = res[b], r.found else { continue }
            if r.isPath {
                invocation = .direct(path: r.raw)
            } else if let aliasPath = Self.barePathAliasTarget(fromCommandV: r.raw) {
                // The alias is exactly an absolute executable with no extra args —
                // functionally a symlink. Resolve it directly so runs never
                // re-enter the login shell (quiet, no per-run -lic), with no
                // behavior change (we'd be dropping flags otherwise → confirm).
                invocation = .shim(path: aliasPath)
            } else {
                let resolution = ToolResolution(
                    invocation: .loginShell(commandName: b), rawCommandV: r.raw, isAmbiguous: true
                )
                return record(manifest, .shimmedNeedsConfirm(resolution), resolution.invocation, nil, now)
            }
            break
        }
        // 2. Known-paths fallback: per-manifest dirs + shared common install dirs
        // (Homebrew, ~/.local/bin, bun/pnpm/asdf/mise/volta, …). Closes the
        // "installed in a standard manager dir we didn't list per-tool" gap.
        if invocation == nil, let path = probeKnownPaths(manifest) {
            invocation = .direct(path: path)
        }
        // 2.5 Spotlight fallback: locate the binary anywhere the index knows it.
        // Closes the long-tail "installed somewhere non-standard" gap without an
        // agent (Track 0.2). Only when nothing cheaper resolved it.
        if invocation == nil, let path = await spotlightResolve(manifest) {
            invocation = .direct(path: path)
        }
        guard let inv = invocation else {
            return record(manifest, .notInstalled, nil, nil, now)
        }

        return await classify(manifest, model: model, invocation: inv, now: now, smoke: smoke)
    }

    /// Given a concrete invocation, run version (+ optional smoke) and classify.
    /// Shared by shell-resolved probes and census verification so both honor the
    /// same `health == runs` contract.
    private func classify(_ manifest: DriverManifest, model: String, invocation inv: ToolInvocation, now: Date, smoke: Bool) async -> ToolProbeRecord {
        // Detect (version).
        guard let version = await detectVersion(manifest, invocation: inv) else {
            return record(manifest, .probeFailed(reason: "could not run \(manifest.setup?.bins.first ?? "the CLI") --version"), inv, nil, now)
        }
        // Smoke → classify (skipped in quota-free detect-only mode: report
        // installed-but-not-probed rather than inferring readiness).
        guard smoke else {
            return record(manifest, .installedNotProbed(version: version), inv, version, now)
        }
        let status = await smokeClassify(manifest, model: model, invocation: inv, version: version)
        return record(manifest, status, inv, version, now)
    }

    /// Verify an agent-discovered census by actually RUNNING each candidate path
    /// — the census is a hint, never trusted (`health == runs`). When the census
    /// path is upgrade-fragile (`looksEphemeral`), a stable launcher from the
    /// manifest's `knownPaths` is tried first and the ephemeral path only as a
    /// fallback, so we never cache a `/versions/<n>/…` blob that 404s on upgrade.
    /// Returns one record per matched headless-CLI driver.
    public func ingestCensus(
        _ census: ToolCensus,
        manifests: [DriverManifest],
        models: [String: String],
        now: Date,
        smoke: Bool = true
    ) async -> [ToolProbeRecord] {
        let byId = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var records: [ToolProbeRecord] = []
        for candidate in census.candidates(for: manifests) {
            guard let manifest = byId[candidate.driverId] else { continue }
            let stableAlt = candidate.looksEphemeral ? probeKnownPaths(manifest) : nil
            // Prefer the stable launcher; fall back to the (ephemeral) census path.
            let ordered = (candidate.looksEphemeral ? [stableAlt, candidate.path] : [candidate.path])
                .compactMap { $0 }
            var chosen: ToolProbeRecord?
            for path in ordered where FileManager.default.isExecutableFile(atPath: path) {
                let rec = await classify(manifest, model: models[manifest.id] ?? "", invocation: .direct(path: path), now: now, smoke: smoke)
                chosen = rec
                if rec.version != nil { break } // a real, runnable binary — stop here
            }
            records.append(chosen ?? record(manifest, .notInstalled, nil, nil, now))
        }
        return records
    }

    // MARK: helpers

    private func record(_ m: DriverManifest, _ status: ModelSetupStatus, _ inv: ToolInvocation?, _ version: String?, _ now: Date) -> ToolProbeRecord {
        ToolProbeRecord(driverId: m.id, status: status, invocation: inv, version: version, lastProbeAt: now)
    }

    /// Extracts the target of a "name → /abs/path" alias from `command -v` output,
    /// but ONLY when the alias is exactly one absolute executable path with no
    /// extra arguments (zsh `name: aliased to /p`, bash ``name is aliased to `/p'``).
    /// Such an alias is functionally a symlink, so resolving it to the path is a
    /// no-behavior-change quiet-run win. Aliases that add flags, same-name
    /// wrappers, and functions return nil — we must not silently drop their args.
    static func barePathAliasTarget(fromCommandV raw: String, fileManager: FileManager = .default) -> String? {
        guard let r = raw.range(of: "aliased to ", options: .caseInsensitive) else { return nil }
        let rest = String(raw[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " `'\"\n"))
        let tokens = ShellWords.split(rest)
        guard tokens.count == 1, let path = tokens.first, path.hasPrefix("/"),
              fileManager.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    private func bins(for manifest: DriverManifest) -> [String] {
        if let bins = manifest.setup?.bins, !bins.isEmpty { return bins }
        if let command = manifest.invoke?.command { return [command] }
        return []
    }

    private func probeKnownPaths(_ manifest: DriverManifest) -> String? {
        let bins = bins(for: manifest)
        // Per-manifest dirs first (most specific), then the shared common dirs.
        for dir in (manifest.setup?.knownPaths ?? []) + commonBinDirs {
            let expanded = dir.hasPrefix("~") ? home + dir.dropFirst() : dir
            for bin in bins {
                let candidate = (expanded as NSString).appendingPathComponent(bin)
                if isExecutableFile(candidate) { return candidate }
            }
        }
        return nil
    }

    /// Spotlight (`mdfind`) fallback — locates a bin anywhere the index knows it,
    /// for genuinely non-standard installs. Filters to an exact-name executable
    /// file (not a dir, not a name-contains match) and prefers a stable launcher
    /// over an upgrade-fragile versioned path. Returns nil if Spotlight is off or
    /// finds nothing. (Track 0.2)
    private func spotlightResolve(_ manifest: DriverManifest) async -> String? {
        var candidates: [String] = []
        for bin in bins(for: manifest) {
            let result = await commandRunner.run(
                command: "/usr/bin/mdfind", args: ["-name", bin],
                stdin: nil, env: [:], workingDirectory: workingDirectory, timeout: .seconds(5)
            )
            guard result.launchError == nil else { continue }
            for line in result.stdout.split(whereSeparator: \.isNewline) {
                let path = line.trimmingCharacters(in: .whitespaces)
                guard (path as NSString).lastPathComponent == bin, isExecutableFile(path) else { continue }
                candidates.append(path)
            }
        }
        // Prefer a stable launcher; an ephemeral/versioned hit only as last resort.
        return candidates.first(where: { !CensusPath.looksEphemeral($0) }) ?? candidates.first
    }

    /// Executable FILE check (rejects directories, which carry the execute bit).
    private func isExecutableFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private func detectVersion(_ manifest: DriverManifest, invocation: ToolInvocation) async -> String? {
        guard let raw = manifest.detectCommand else { return nil }
        let result = await runResolved(raw, invocation: invocation, timeout: detectTimeout)
        guard result.launchError == nil, result.exitCode == 0 else { return nil }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
    }

    private func smokeClassify(_ manifest: DriverManifest, model: String, invocation: ToolInvocation, version: String) async -> ModelSetupStatus {
        // OpenCode answers over its serve HTTP API, never stdout (`opencode run` is a
        // TTY-only client that emits nothing when piped). See
        // OpenCode_Smoke_Probe_Blocker.md (RESOLUTION).
        if manifest.id == "opencode" {
            if let reason = await OpenCodeServeClient.smokeReason(manifest: manifest, modelLabel: model) {
                return .probeFailed(reason: reason)
            }
            return .ready(version: version)
        }
        guard let raw = manifest.resolvedCommandString(
            manifest.smokeTestCommand, model: model, workingDir: workingDirectory
        ) else {
            return .ready(version: version) // no smoke contract → presence is all we can assert
        }
        let result = await runResolved(raw, invocation: invocation, timeout: smokeTimeout)
        let haystack = (result.stdout + "\n" + result.stderr).lowercased()

        // Ready: clean exit + the expected token came back.
        if result.launchError == nil, result.exitCode == 0,
           let expect = manifest.smokeTestExpect {
            if result.stdout.contains(expect) {
                return .ready(version: version)
            }
        }

        // Auth-shaped failure → guided sign-in (only when we know the flow).
        if let loginFlow = manifest.setup?.loginFlow,
           loginFlow.authErrorPatterns.contains(where: { !$0.isEmpty && haystack.contains($0.lowercased()) }) {
            return .installedNotSignedIn(loginFlow)
        }

        // Otherwise an honest probe failure with the real reason.
        let reason: String
        if let launchError = result.launchError { reason = launchError }
        else if result.timedOut { reason = "smoke test timed out" }
        else if let code = result.exitCode, code != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            reason = stderr.isEmpty ? "smoke exited \(code)" : String(stderr.prefix(200))
        } else { reason = smokeTokenMissReason(manifest: manifest, result: result) }
        return .probeFailed(reason: reason)
    }

    private func smokeTokenMissReason(manifest: DriverManifest, result: CommandResult) -> String {
        let expect = manifest.smokeTestExpect ?? "the expected token"
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var reason = "smoke did not return \(expect)"
        if trimmed.isEmpty {
            reason += " (stdout empty)"
        } else {
            reason += " · stdout: \(String(trimmed.prefix(400)))"
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { reason += " · stderr: \(String(stderr.prefix(200)))" }
        return reason
    }

    /// Runs an author-controlled command string through the resolved invocation.
    /// `direct`/`shim` swap the bare bin for the absolute path (argv preserved);
    /// `loginShell` re-runs it under `$SHELL -lic` so an alias/function resolves.
    private func runResolved(_ raw: String, invocation: ToolInvocation, timeout: Duration) async -> CommandResult {
        let tokens = ShellWords.split(raw)
        guard let bin = tokens.first else { return CommandResult(launchError: "empty command") }
        let args = Array(tokens.dropFirst())
        switch invocation {
        case .direct(let path), .shim(let path):
            return await commandRunner.run(command: path, args: args, stdin: nil, env: [:], workingDirectory: workingDirectory, timeout: timeout)
        case .loginShell:
            _ = bin
            return await commandRunner.run(command: shellPath, args: ["-lic", raw], stdin: nil, env: [:], workingDirectory: workingDirectory, timeout: timeout)
        }
    }
}
