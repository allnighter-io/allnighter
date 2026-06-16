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

    public init(commandRunner: CommandRunner, shellPath: String? = nil, timeout: Duration = .seconds(5)) {
        self.commandRunner = commandRunner
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.timeout = timeout
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
        // Non-interactive login shell (`-lc`, not `-lic`): resolves PATH binaries
        // from login profiles without sourcing the interactive `.zshrc`, whose dev
        // tools touch Downloads/Photos and make macOS raise TCC prompts attributed
        // to the GUI app. Tools not on the login PATH fall back to `knownPaths`.
        // (Shell-only aliases no longer auto-resolve — locate manually if needed.)
        let result = await commandRunner.run(
            command: shellPath, args: ["-lc", script],
            stdin: nil, env: [:], workingDirectory: nil, timeout: timeout
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

    public init(
        commandRunner: CommandRunner,
        resolver: ShellResolver? = nil,
        shellPath: String? = nil,
        home: String? = nil,
        detectTimeout: Duration = .seconds(8),
        smokeTimeout: Duration = .seconds(60)
    ) {
        self.commandRunner = commandRunner
        let sh = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellPath = sh
        self.resolver = resolver ?? ShellResolver(commandRunner: commandRunner, shellPath: sh)
        self.home = home ?? NSHomeDirectory()
        self.detectTimeout = detectTimeout
        self.smokeTimeout = smokeTimeout
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

        // 1. Resolve to an invocation (path → direct; alias/function → confirm).
        var invocation: ToolInvocation?
        for b in bins {
            guard let r = res[b], r.found else { continue }
            if r.isPath {
                invocation = .direct(path: r.raw)
            } else {
                let resolution = ToolResolution(
                    invocation: .loginShell(commandName: b), rawCommandV: r.raw, isAmbiguous: true
                )
                return record(manifest, .shimmedNeedsConfirm(resolution), resolution.invocation, nil, now)
            }
            break
        }
        // 2. Known-paths fallback when the shell couldn't resolve it.
        if invocation == nil, let path = probeKnownPaths(manifest) {
            invocation = .direct(path: path)
        }
        guard let inv = invocation else {
            return record(manifest, .notInstalled, nil, nil, now)
        }

        // 3. Detect (version).
        guard let version = await detectVersion(manifest, invocation: inv) else {
            return record(manifest, .probeFailed(reason: "could not run \(manifest.setup?.bins.first ?? "the CLI") --version"), inv, nil, now)
        }

        // 4. Smoke → classify (skipped in quota-free detect-only mode: report
        // installed-but-not-probed rather than inferring readiness).
        guard smoke else {
            return record(manifest, .installedNotProbed(version: version), inv, version, now)
        }
        let status = await smokeClassify(manifest, model: model, invocation: inv, version: version)
        return record(manifest, status, inv, version, now)
    }

    // MARK: helpers

    private func record(_ m: DriverManifest, _ status: ModelSetupStatus, _ inv: ToolInvocation?, _ version: String?, _ now: Date) -> ToolProbeRecord {
        ToolProbeRecord(driverId: m.id, status: status, invocation: inv, version: version, lastProbeAt: now)
    }

    private func bins(for manifest: DriverManifest) -> [String] {
        if let bins = manifest.setup?.bins, !bins.isEmpty { return bins }
        if let command = manifest.invoke?.command { return [command] }
        return []
    }

    private func probeKnownPaths(_ manifest: DriverManifest) -> String? {
        let bins = bins(for: manifest)
        for dir in manifest.setup?.knownPaths ?? [] {
            let expanded = dir.hasPrefix("~") ? home + dir.dropFirst() : dir
            for bin in bins {
                let candidate = (expanded as NSString).appendingPathComponent(bin)
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
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
        guard let raw = manifest.resolvedCommandString(manifest.smokeTestCommand, model: model) else {
            return .ready(version: version) // no smoke contract → presence is all we can assert
        }
        let result = await runResolved(raw, invocation: invocation, timeout: smokeTimeout)
        let haystack = (result.stdout + "\n" + result.stderr).lowercased()

        // Ready: clean exit + the expected token came back.
        if result.launchError == nil, result.exitCode == 0,
           let expect = manifest.smokeTestExpect, result.stdout.contains(expect) {
            return .ready(version: version)
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
        } else { reason = "smoke did not return \(manifest.smokeTestExpect ?? "the expected token")" }
        return .probeFailed(reason: reason)
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
            return await commandRunner.run(command: path, args: args, stdin: nil, env: [:], workingDirectory: nil, timeout: timeout)
        case .loginShell:
            _ = bin
            return await commandRunner.run(command: shellPath, args: ["-lic", raw], stdin: nil, env: [:], workingDirectory: nil, timeout: timeout)
        }
    }
}
