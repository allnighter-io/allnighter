import Foundation

#if canImport(Darwin)
import Darwin
#endif

// MARK: - Acquisition-scoped probe registry (CWB-S00a)

/// Per-acquisition registry of probe child process groups.
///
/// Product law: a strip/acquire timeout may kill only the PTYs **its own**
/// acquire spawned — never another in-flight acquire's (timer must never
/// cross-kill an explicit Refresh). Each `CapacityAcquisition.windows(refresh:)`
/// call owns one scope; live probes register their child process group into it
/// while it runs, and on timeout only that scope is terminated.
///
/// Lock-protected — safe across the DispatchQueue probe wave. `terminate()` is
/// idempotent: it drains the tracked set, so a second call is a no-op.
public final class CapacityProbeScope: Equatable, @unchecked Sendable {
    private let lock = NSLock()
    private var pids: Set<pid_t> = []
    private let terminator: @Sendable (pid_t) -> Void

    /// The default terminator (nil) kills the real process group (SIGTERM →
    /// SIGKILL escalation + reap). Tests inject a recorder so scoped-kill
    /// proofs stay deterministic and off live processes.
    public init(terminator: (@Sendable (pid_t) -> Void)? = nil) {
        self.terminator = terminator ?? { pid in
            #if os(macOS)
            CapacityProbe.terminateProcessGroup(pid)
            #endif
        }
    }

    /// Track a child process group spawned under this scope.
    func track(_ pid: pid_t) {
        guard pid > 0 else { return }
        lock.lock(); pids.insert(pid); lock.unlock()
    }

    /// Stop tracking a child that already finished / was reaped by its owner.
    func untrack(_ pid: pid_t) {
        guard pid > 0 else { return }
        lock.lock(); pids.remove(pid); lock.unlock()
    }

    /// Still-tracked process groups (tests / diagnostics).
    var trackedPIDs: Set<pid_t> {
        lock.lock(); defer { lock.unlock() }
        return pids
    }

    /// Kill every process group still tracked by **this** scope only.
    /// Drains the set first, so concurrent late `track`s after a terminate
    /// stay tracked (their owning probe still kills them on exit).
    public func terminate() {
        lock.lock()
        let drained = pids
        pids.removeAll()
        lock.unlock()
        for pid in drained {
            terminator(pid)
        }
    }

    public static func == (lhs: CapacityProbeScope, rhs: CapacityProbeScope) -> Bool {
        lhs === rhs
    }
}

// MARK: - Probe executor seam

/// One tier-3 PTY capture request. Callers pass every clock value — no `Date()` inside.
public struct CapacityProbeRequest: Sendable, Equatable {
    public let source: String
    public let now: Date
    public let timeout: TimeInterval
    /// Acquisition scope this probe registers its child into (CWB-S00a).
    /// Nil for standalone probes outside an acquisition wave.
    public let scope: CapacityProbeScope?

    public init(
        source: String,
        now: Date,
        timeout: TimeInterval = CapacityProbe.defaultTimeout,
        scope: CapacityProbeScope? = nil
    ) {
        self.source = source
        self.now = now
        self.timeout = timeout
        self.scope = scope
    }
}

/// Injectable seam so tests can prove bare `alln capacity` never spawns,
/// and can feed fail-closed / fixture outcomes without a real vendor CLI.
public protocol CapacityProbeExecuting: Sendable {
    /// Capture + parse one source. Always returns at least one window.
    /// Never throws. Always terminates any child it started.
    func execute(_ request: CapacityProbeRequest) -> [CapacityWindow]
}

/// Live PTY probes against vendor CLIs on PATH / known install locations.
public struct LiveCapacityProbeExecutor: CapacityProbeExecuting, Sendable {
    public init() {}

    public func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
        // Prefer per-source budget when caller left the default (20s).
        let budget = request.timeout == CapacityProbe.defaultTimeout
            ? CapacityProbe.timeout(for: request.source)
            : request.timeout
        return CapacityProbe.windows(
            source: request.source,
            now: request.now,
            timeout: budget,
            scope: request.scope
        )
    }
}

// MARK: - CapacityProbe

/// Tier-3 PTY one-shot into a vendor usage TUI.
///
/// Per driver: spawn CLI in a PTY, send `/usage`, capture rendered text, hand
/// to the existing pure parser, always terminate the child (including timeout).
///
/// Fail closed: spawn / timeout / empty / parse → `unknown` with a reason.
/// **Never** invents a percentage. **Never** returns `vendorExposesNothing` for
/// a seat we ship a parser for.
///
/// Lives at the acquisition boundary only — pure types (`CapacityWindow`,
/// projection, strip) take no IO.
public enum CapacityProbe {

    /// Per-probe wall-clock budget. One slow CLI must not hang the strip.
    public static let defaultTimeout: TimeInterval = 20

    /// Claude Usage pane often paints slower than agy/kimi/cursor (CAP-HF-claude).
    public static let claudeTimeout: TimeInterval = 35

    /// Wall-clock budget for a source. Claude gets a longer readiness window.
    public static func timeout(for source: String) -> TimeInterval {
        source == "claude_code" ? claudeTimeout : defaultTimeout
    }

    /// Extra argv for a source's probe launch.
    ///
    /// A capacity probe reads one screen and exits. Anything the vendor boots
    /// for a real coding session — plugins, MCP servers, tool hosts — is pure
    /// cost here, and worse, it is a hang dependency: codex's built-in
    /// `codex_apps` MCP server loads plugin metadata and on this machine never
    /// finishes, spinning at "Starting MCP servers (1/2)" past a 60s budget, so
    /// `/status` was never sent at all.
    ///
    /// Empty for every other source — do not add flags speculatively. Each entry
    /// here must be justified by a measured before/after on the live probe.
    public static func probeArguments(for source: String) -> [String] {
        switch source {
        case "codex":
            // Clears the user's configured MCP servers so the probe does not
            // spawn tool hosts it will never call. Measured: does NOT stop the
            // built-in `codex_apps`, which has no disable flag in 0.147.0 —
            // `--disable plugins` was tried and made no difference to the hang,
            // so it is deliberately not here. `codex_apps` is escaped instead;
            // see `looksLikeCodexMCPStarting`.
            return ["-c", "mcp_servers={}"]
        default:
            return []
        }
    }

    /// Why an empty parse happened — the parser, or the absence of a screen.
    ///
    /// Extracted so the distinction is testable without a live vendor CLI. It is
    /// the whole point of the fix: `parserFailed` means "a surface exists but we
    /// could not read it" and sends someone to a parser; `probeTimeout` is
    /// already documented as "hit the wall-clock budget before a usable screen",
    /// which is what actually happened when codex hung on MCP startup and grok
    /// never left its splash animation.
    static func emptyParseReason(sawUsagePane: Bool, observedAt: Date) -> CapacityUnknownReason {
        sawUsagePane
            ? .parserFailed(observedAt: observedAt)
            : .probeTimeout(observedAt: observedAt)
    }

    /// Codex is blocking on MCP server startup and is advertising the way out.
    ///
    /// The TUI prints "Starting MCP servers (1/2): codex_apps (0s • esc to
    /// interrupt)". On this machine `codex_apps` never completes, so waiting is
    /// unbounded — but pressing Escape aborts it and leaves a usable prompt.
    /// That is not a guess: our own first capture recorded the result,
    /// "⚠ MCP startup interrupted. The following servers were not initialized:
    /// codex_apps", after which the composer accepted input.
    public static func looksLikeCodexMCPStarting(_ text: String) -> Bool {
        let c = collapsedForMatch(recentPaintWindow(text))
        // Already aborted — one Escape is the whole fix. Pressing it again once
        // the composer is live gets read as "edit previous message"
        // ("• No previous message to edit." showed up in the capture that
        // proved this), so the abort confirmation must switch this off.
        if codexMCPAborted(c) { return false }
        return c.contains("startingmcpservers") || c.contains("esctointerrupt")
    }

    /// Codex confirmed it gave up on MCP startup. The capture keeps the old
    /// "esc to interrupt" spinner text in its scrollback forever, so freshness
    /// cannot be judged by that string alone — this is the positive signal that
    /// outranks it.
    static func codexMCPAborted(_ collapsed: String) -> Bool {
        collapsed.contains("mcpstartupinterrupted") || collapsed.contains("notinitialized")
    }

    /// Fail-soft dump directory for unreadable captures (inspectable, no PII required).
    public static var debugDumpDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Allnighter/Capacity/debug",
                isDirectory: true
            )
    }

    /// PTY-only seats this probe knows how to drive (all six bench seats).
    /// Claude Code: `/usage` opens the Usage pane directly (no tab navigation).
    /// Codex: `/status` (remaining-polarity). Grok: `/usage`.
    public static let probeableSources: [String] = [
        "agy",
        "kimi",
        "cursor_agent",
        "claude_code",
        "codex",
        "grok",
    ]

    /// Active probe child process groups — the process-wide PGID ledger for
    /// quit-time reap (CWB-S00a Gap 3). Lock-protected mutable set;
    /// `nonisolated(unsafe)` is required because Swift 6 treats static vars as
    /// global shared state even when locked.
    private final class ActiveProbeRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var pids: Set<pid_t> = []

        func insert(_ pid: pid_t) {
            guard pid > 0 else { return }
            lock.lock(); pids.insert(pid); lock.unlock()
        }

        func remove(_ pid: pid_t) {
            guard pid > 0 else { return }
            lock.lock(); pids.remove(pid); lock.unlock()
        }

        func drain() -> Set<pid_t> {
            lock.lock()
            let out = pids
            pids.removeAll()
            lock.unlock()
            return out
        }
    }

    private static let activeProbes = ActiveProbeRegistry()

    /// **Process shutdown / quit only.** Force-kill every still-running
    /// capacity probe child in this process (process group), regardless of
    /// which acquisition spawned it.
    ///
    /// Never call this for a strip/acquire timeout — that cross-kills another
    /// in-flight acquire's PTYs (CWB-S00a product law). Timeouts terminate the
    /// per-acquire `CapacityProbeScope` instead. This exists for graceful-quit
    /// PGID reap, where acquisition scoping no longer matters because the whole
    /// process is going away. Safe to call when no probes are live.
    public static func terminateAllForProcessShutdown() {
        #if os(macOS)
        for pid in activeProbes.drain() {
            terminateProcessGroup(pid)
        }
        #endif
    }

    private static func trackActiveProbe(_ pid: pid_t) {
        activeProbes.insert(pid)
    }

    private static func untrackActiveProbe(_ pid: pid_t) {
        activeProbes.remove(pid)
    }

    /// Candidate executable names per source (PATH order).
    public static let commandCandidates: [String: [String]] = [
        "agy": ["agy"],
        "kimi": ["kimi"],
        "cursor_agent": ["agent", "cursor-agent"],
        "claude_code": ["claude"],
        "codex": ["codex"],
        "grok": ["grok"],
    ]

    /// Home-relative known install paths (checked when PATH misses).
    public static let knownHomeRelativePaths: [String: [String]] = [
        "agy": [".local/bin/agy"],
        "kimi": [".kimi-code/bin/kimi", ".local/bin/kimi"],
        "cursor_agent": [".local/bin/agent", ".local/bin/cursor-agent"],
        "claude_code": [".local/bin/claude", ".local/share/claude/versions"],
        "codex": [".local/bin/codex"],
        "grok": [".local/bin/grok"],
    ]

    /// Default slash command sent after the TUI is ready.
    /// Claude Code's `/usage` lands on the Usage tab with session/weekly bars.
    public static let usageCommand = "/usage"

    /// Per-source TUI command to invoke the usage surface.
    public static func probeCommand(for source: String) -> String {
        source == "codex" ? "/status" : usageCommand
    }

    // MARK: - Trust / ready matching (space-stripped TUI safe)

    /// Collapse whitespace so space-stripped TUI renders (CSI cursor paint) still match.
    public static func collapsedForMatch(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "\u{00A0}" }
    }

    /// Claude workspace-trust dialog — matches spaced and space-stripped forms.
    /// Real ProbeScratch dumps paint as `Yes,Itrustthisfolder` with no spaces.
    public static func looksLikeWorkspaceTrustDialog(_ text: String) -> Bool {
        let c = collapsedForMatch(text)
        if c.contains("trustthisfolder") { return true }
        if c.contains("yes,itrust") || c.contains("yesitrustthisfolder") { return true }
        if c.contains("accessingworkspace") { return true }
        if c.contains("quicksafetycheck") && c.contains("trust") { return true }
        return false
    }

    /// Codex post-upgrade version nudge — blocks `/status` until dismissed.
    /// Real ProbeScratch dumps paint as `2.Skip` / `skipuntilnextversion` with no spaces.
    public static func looksLikeCodexUpgradePrompt(_ text: String) -> Bool {
        let c = collapsedForMatch(text)
        if c.contains("skipuntilnextversion") { return true }
        if c.contains("updateavailable"), c.contains("brewupgrade") { return true }
        if c.contains("updateavailable"), c.contains("releasenotes"), c.contains("skip") {
            return true
        }
        if c.contains("updatenow"), c.contains("skip"), c.contains("codex") { return true }
        return false
    }

    /// Recent paint window — PTY buffers accumulate; trust dialog text stays in
    /// the head after accept, so readiness must look at the tail.
    public static func recentPaintWindow(_ text: String, maxChars: Int = 2000) -> String {
        guard text.count > maxChars else { return text }
        return String(text.suffix(maxChars))
    }

    /// Interactive prompt / boot chrome after any trust dialog is gone.
    ///
    /// Always evaluates the **recent paint window** so a previously accepted
    /// trust dialog still sitting in the buffer head cannot block readiness
    /// (real dogfood: welcome screen paints under stale "Yes,Itrustthisfolder").
    /// - Parameter source: the driver id, when known. A source that ships its
    ///   own readiness predicate is **authoritative for both answers** — its
    ///   "still booting" must be able to veto generic chrome. Passing `""` means
    ///   "generic chrome only" and is the historical behavior.
    ///
    ///   This parameter exists because the generic marker list below silently
    ///   overrode codex's MCP guard: codex's boot screen prints
    ///   "Tip: Try the Desktop app", the generic `"tip:"` marker matched and
    ///   returned true, and `looksLikeCodexReadyForStatusCommand` — consulted
    ///   only as a positive fallback at the end — never ran. The probe then
    ///   typed `/status` into a busy TUI, codex queued it instead of running it,
    ///   and the unpainted pane was reported as `parserFailed`. Fixing the guard
    ///   itself was not enough; it was being routed around.
    public static func looksReadyForUsageCommand(_ text: String, source: String = "") -> Bool {
        let window = recentPaintWindow(text)
        // If the *recent* paint is still boot chrome, not ready.
        if looksLikeWorkspaceTrustDialog(window) { return false }
        if looksLikeCodexUpgradePrompt(window) { return false }
        // Source-specific readiness wins outright — never fall through to the
        // generic markers, or a source's "not ready" becomes advisory.
        if source == "codex" { return looksLikeCodexReadyForStatusCommand(text) }
        let lower = window.lowercased()
        let collapsed = collapsedForMatch(window)
        let spacedMarkers = [
            "shortcuts", "session:", "cursor agent", "│ > ", "\n> ", "tip:",
            "bypass permissions", "? for shortcuts", "welcome back",
            "tips for getting started", "what's new", "what would you like",
            "try \"", "shift+tab", "haiku", "opus",
        ]
        if spacedMarkers.contains(where: { lower.contains($0) }) { return true }
        let collapsedMarkers = [
            "shortcuts", "session:", "cursoragent", "tip:",
            "bypasspermissions", "?forshortcuts", "welcomeback",
            "tipsforgettingstarted", "what'snew", "whatsnew",
            "whatwouldyoulike", "try\"", "shift+tab",
            "claudecodev", // version banner "Claude Code v…"
        ]
        if collapsedMarkers.contains(where: { collapsed.contains($0) }) { return true }
        if looksLikeCodexReadyForStatusCommand(text) { return true }
        // Product name alone is not enough (trust dialog also says Claude Code).
        return false
    }

    /// Codex interactive boot is ready for `/status` — model loaded, MCP boot done.
    public static func looksLikeCodexReadyForStatusCommand(_ text: String) -> Bool {
        let window = recentPaintWindow(text)
        if looksLikeCodexUpgradePrompt(window) { return false }
        let c = collapsedForMatch(window)
        // "esc to interrupt" collapses to `esctointerrupt`. This read
        // `escrtointerrupt` — one stray `r` — so the guard never fired against a
        // real capture, and it is the ONLY guard that catches the shape that
        // actually broke: model already resolved, MCP servers still starting.
        // Codex then queues `/status` ("tab to queue message") instead of
        // running it, the pane never paints, and the empty parse gets reported
        // as `parserFailed` — sending us to fix a parser that works.
        // Stale spinner text lives in the scrollback for the rest of the
        // session, so the abort confirmation has to win or codex is never ready.
        if codexMCPAborted(c) {
            // Codex prints the abort immediately above a live composer, so this
            // IS readiness. It also has to be a positive and not merely "stop
            // blocking": by this point the boot box has scrolled out of the
            // recent paint window, so the `directory:` + `model:` test below can
            // no longer fire and codex would wait out the whole budget without
            // ever sending /status.
            return true
        }
        if c.contains("startingmcpservers") || c.contains("esctointerrupt") { return false }
        if c.contains("model"), c.contains("loading") { return false }
        // Status pane is already up — do not re-send /status from the boot waiter.
        if looksLikeCodexStatusPane(text) { return true }
        // Boot chrome: directory box painted and model name resolved.
        if c.contains("directory:"), c.contains("model:"), !c.contains("loading") { return true }
        return false
    }

    /// Codex `/status` pane — not the low-quota banner that merely suggests /status.
    public static func looksLikeCodexStatusPane(_ text: String) -> Bool {
        let lower = text.lowercased()
        let c = collapsedForMatch(text)
        if c.contains("weeklylimit"), c.contains("%left") { return true }
        if lower.contains("resets "), lower.contains("% left") { return true }
        if c.contains("chatgpt.com/codex/settings/usage") { return true }
        return false
    }

    /// Neutral CWD for tier-3 probes — mirrors `AllnighterPaths.probeScratch` (Engine
    /// cannot be imported from Core). Capacity probes must not inherit the app/repo
    /// CWD: in dev that is the checkout under `~/Documents`, and a child CLI that
    /// reads its working dir trips a TCC prompt attributed to the GUI app.
    public static func neutralWorkingDirectory(
        fileManager: FileManager = .default
    ) -> String? {
        let support: URL
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"],
           !override.isEmpty
        {
            support = URL(
                fileURLWithPath: (override as NSString).expandingTildeInPath,
                isDirectory: true
            )
        } else {
            let base = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            support = base.appendingPathComponent("Allnighter", isDirectory: true)
        }
        let scratch = support.appendingPathComponent("ProbeScratch", isDirectory: true)
        do {
            try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            return scratch.path
        } catch {
            return nil
        }
    }

    // MARK: Public entry

    /// Probe one source and return normalized windows (or a single unknown).
    ///
    /// - Parameters:
    ///   - source: Bench source id (`agy`, `kimi`, `cursor_agent`, `claude_code`).
    ///   - now: Observation stamp for parse + unknown reasons.
    ///   - timeout: Hard wall-clock budget for the whole probe.
    ///   - workingDirectory: Child cwd. Default is ProbeScratch (never process
    ///     CWD — that is often ~/Documents in Xcode and trips TCC).
    ///   - pathEnvironment: PATH string for binary resolution (default: real PATH).
    ///   - homeDirectory: Home for known-path fallbacks (default: real home).
    ///   - executableOverride: Force a specific binary (tests: `/bin/sleep`).
    ///   - scope: Acquisition scope the spawned child registers into (CWB-S00a).
    ///     The child is always killed by this probe itself on return; the scope
    ///     exists so an acquisition timeout can kill it early — and only it.
    public static func windows(
        source: String,
        now: Date,
        timeout: TimeInterval? = nil,
        workingDirectory: String? = nil,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        executableOverride: String? = nil,
        dumpDirectory: URL? = nil,
        scope: CapacityProbeScope? = nil
    ) -> [CapacityWindow] {
        #if os(macOS)
        let budget = timeout ?? Self.timeout(for: source)
        guard probeableSources.contains(source) else {
            // Unknown seat — honest never-sampled.
            return [unknown(source: source, reason: .neverSampled, now: now)]
        }

        let executable: String
        if let executableOverride {
            executable = executableOverride
        } else if let resolved = resolveExecutable(
            source: source,
            pathEnvironment: pathEnvironment,
            homeDirectory: homeDirectory
        ) {
            executable = resolved
        } else {
            return [unknown(source: source, reason: .spawnFailed(observedAt: now), now: now)]
        }

        // agy's own print-mode JSON channel is the primary acquisition path —
        // headless, ~1-8s measured, zero model tokens, structured
        // `groups[].buckets[]` carrying BOTH the weekly and 5h windows the PTY
        // scrape below drops entirely (Capacity_Native_Channels.md §2). Any
        // error, timeout, non-SUCCESS status, or unrecognized shape here
        // produces no observation (`probeAgyNative` returns nil) and falls
        // through untouched to the existing PTY scrape as agy's fallback.
        if source == "agy", let native = probeAgyNative(executable: executable, now: now) {
            return native
        }

        let cwd = workingDirectory ?? Self.neutralWorkingDirectory()
        guard let cwd else {
            // Never fall back to process CWD — in Xcode/dev that is often the
            // checkout under ~/Documents and trips a TCC prompt on Allnighter.
            return [unknown(source: source, reason: .spawnFailed(observedAt: now), now: now)]
        }
        let capture = captureUsageRender(
            executable: executable,
            workingDirectory: cwd,
            timeout: budget,
            source: source,
            scope: scope
        )

        switch capture {
        case .spawnFailed:
            return [unknown(source: source, reason: .spawnFailed(observedAt: now), now: now)]
        case .timeout:
            return [unknown(source: source, reason: .probeTimeout(observedAt: now), now: now)]
        case .empty:
            return [unknown(source: source, reason: .emptyCapture(observedAt: now), now: now)]
        case .captured(let text, let sawUsagePane):
            let parsed = parse(source: source, renderText: text, now: now)
            if parsed.isEmpty {
                // Two different failures wore the same name. `parserFailed` says
                // "a surface exists but we could not read it" and sends someone
                // to fix a parser. When the pane never rendered there is nothing
                // to parse, and the honest reason already existed:
                // `probeTimeout` is documented as "hit the wall-clock budget
                // before a usable screen".
                //
                // This cost real hours on 2026-08-08: codex and grok both read
                // `parserFailed` while their parsers were fine — codex never got
                // past MCP startup, grok never got past its splash animation.
                // The deterministic parser could not read this capture. Before
                // reporting unknown, let the source's OWN cheapest model read
                // it — measured 10/10 across six vendors' formats, with
                // `confident: false` on every capture that had no usage data
                // (packet §4b). It answers or it declines; it does not invent.
                //
                // Fallback rather than primary for now: the deterministic path
                // is free and already correct on the common case. The trigger is
                // exactly the attribution added earlier today — before that,
                // "could not read it" and "there was nothing to read" printed
                // the same word and this branch could not have existed.
                if CapacityPaneSettings().loadEnabled(),
                   let executable = executable as String?,
                   let read = CapacityPaneReader.read(
                       source: source, capture: text, executable: executable, now: now),
                   !read.isEmpty {
                    return read
                }
                let reason = emptyParseReason(sawUsagePane: sawUsagePane, observedAt: now)
                // Keep the capture either way — the dump is how both of those
                // were actually diagnosed. The tag says which question to ask.
                writeDebugDump(
                    source: source,
                    text: text,
                    tag: sawUsagePane ? "parseFailed" : "paneNeverRendered",
                    directory: dumpDirectory ?? debugDumpDirectory
                )
                return [unknown(source: source, reason: reason, now: now)]
            }
            return parsed
        }
        #else
        // iOS / non-macOS: no PTY vendor CLIs. Fail closed, never invent.
        return [unknown(source: source, reason: .neverSampled, now: now)]
        #endif
    }

    /// Try agy's native print-mode JSON channel. A plain headless pipe, not a
    /// PTY — print mode is non-interactive by definition, and a PTY here would
    /// reintroduce the repaint behavior this channel exists to escape.
    ///
    /// Every failure path returns `nil` — no binary, non-zero exit, timeout,
    /// unparseable output, `status != "SUCCESS"`, or an unrecognized shape —
    /// so the caller falls through to the PTY scrape unchanged. Never reads a
    /// credential: the vendor CLI owns its own auth and refresh in-process.
    private static func probeAgyNative(executable: String, now: Date) -> [CapacityWindow]? {
        guard let output = CapacityPaneReader.runHeadless(
            executable: executable,
            argv: AgyNativeCapacityProbe.argv(),
            timeout: AgyNativeCapacityProbe.processTimeout
        ) else { return nil }
        let windows = AgyNativeCapacityProbe.capacityWindows(fromOutput: output, observedAt: now)
        return windows.isEmpty ? nil : windows
    }

    /// Best-effort write of a failed capture for parser re-fixturing.
    static func writeDebugDump(
        source: String,
        text: String,
        tag: String,
        directory: URL
    ) {
        let safeSource = source
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let name = "\(safeSource)-\(tag).txt"
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Fail-soft: dumps never break the strip.
        }
    }

    /// Parse already-captured render text through the driver's pure extractor.
    /// Public for the Works Test seam (fixture → parser without a live spawn).
    public static func parse(
        source: String,
        renderText: String,
        now: Date
    ) -> [CapacityWindow] {
        switch source {
        case "agy":
            return AgyCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        case "kimi":
            return KimiCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        case "cursor_agent":
            return CursorCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        case "claude_code":
            return ClaudeCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        case "codex":
            return CodexCapacityProbe.capacityWindows(fromRender: renderText, observedAt: now)
        case "grok":
            return GrokCapacityProbe.capacityWindows(fromRender: renderText, observedAt: now)
        default:
            return []
        }
    }

    /// Resolve the vendor binary for a source. Nil → spawn cannot start.
    public static func resolveExecutable(
        source: String,
        pathEnvironment: String?,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) -> String? {
        let names = commandCandidates[source] ?? [source]
        if let pathEnvironment {
            for name in names {
                if let hit = InstallCLI.resolveOnPath(
                    command: name,
                    pathEnvironment: pathEnvironment,
                    fileManager: fileManager
                ) {
                    return hit
                }
            }
        }
        let relatives = knownHomeRelativePaths[source] ?? []
        for rel in relatives {
            let url = homeDirectory.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                // Claude versions dir: pick newest executable child if present.
                if source == "claude_code",
                   let newest = newestExecutable(in: url, fileManager: fileManager)
                {
                    return newest
                }
                continue
            }
            guard fileManager.isExecutableFile(atPath: url.path) else { continue }
            return url.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return nil
    }

    /// Newest regular executable under a directory (for versioned install trees).
    private static func newestExecutable(in directory: URL, fileManager: FileManager) -> String? {
        guard let kids = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var best: (url: URL, date: Date)?
        for kid in kids {
            let values = try? kid.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  fileManager.isExecutableFile(atPath: kid.path)
            else { continue }
            let date = values?.contentModificationDate ?? .distantPast
            if best == nil || date > best!.date {
                best = (kid, date)
            }
        }
        return best?.url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Capture result

    enum CaptureResult: Sendable, Equatable {
        /// `sawUsagePane` records whether the vendor's usage/status screen ever
        /// actually rendered. Without it the caller cannot tell "the parser
        /// could not read this screen" from "there was no screen" — and those
        /// send you to opposite places.
        case captured(String, sawUsagePane: Bool)
        case spawnFailed
        case timeout
        case empty
    }

    // MARK: - PTY capture (macOS)

    #if os(macOS)
    /// Spawn `executable` in a PTY, send `/usage`, capture screen text, always kill.
    /// The child registers into both the process-wide quit ledger and the
    /// caller's acquisition `scope` (CWB-S00a) so a scope terminate can kill
    /// exactly this generation.
    static func captureUsageRender(
        executable: String,
        workingDirectory: String,
        timeout: TimeInterval,
        source: String = "",
        scope: CapacityProbeScope? = nil
    ) -> CaptureResult {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            return .spawnFailed
        }

        // Readable TUI geometry — narrow/short PTYs truncate bars and labels.
        var ws = winsize(ws_row: 45, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &ws)

        // Non-blocking master so select-based drain cannot hang a read.
        let masterFlags = fcntl(master, F_GETFL)
        if masterFlags >= 0 {
            _ = fcntl(master, F_SETFL, masterFlags | O_NONBLOCK)
        }

        let pid: pid_t
        do {
            pid = try spawnPTYChild(
                executable: executable,
                workingDirectory: workingDirectory,
                slave: slave,
                source: source
            )
        } catch {
            close(master)
            close(slave)
            return .spawnFailed
        }

        // Parent keeps master only; child owns slave via dup2.
        close(slave)

        trackActiveProbe(pid)
        scope?.track(pid)
        // Durable note that WE spawned this child, so a later run can prove
        // ownership before signalling anything. In-memory tracking dies with the
        // process, which is exactly the case that left 103 orphans unreapable.
        let owner = CapacityProbeLedger.currentOwner()
        let ledger = CapacityProbeLedger()
        ledger.record(.init(
            childPID: pid, childPGID: pid, ownerPID: owner.pid,
            ownerStartTicks: owner.startTicks, source: source, spawnedAt: Date()))
        defer {
            terminateProcessGroup(pid)
            untrackActiveProbe(pid)
            scope?.untrack(pid)
            ledger.forget(childPID: pid)
            close(master)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var usageSent = false
        var sawReady = false
        var sawUsagePane = false
        var trustAccepts = 0
        var codexUpgradeSkips = 0
        var codexMCPInterrupts = 0

        // 1) Wait for the interactive prompt / boot chrome. Handle Claude's
        // workspace trust dialog — real captures often strip spaces
        // (`Yes,Itrustthisfolder`), so match on collapsed text. Always inspect
        // the *recent paint window* so accepted-trust text left in the buffer
        // head cannot mask the welcome screen that painted after it.
        while Date() < deadline {
            appendAvailable(from: master, into: &buffer)
            let text = decodeAndStrip(buffer)
            let recent = recentPaintWindow(text)
            if looksLikeWorkspaceTrustDialog(recent) {
                // Default selection is option 1 ("Yes, I trust this folder").
                // Send "1" then Enter — plain Enter alone is flaky when focus
                // is not yet on the radio list under a non-TTY host.
                if trustAccepts < 4 {
                    let one: [UInt8] = [UInt8(ascii: "1")]
                    _ = one.withUnsafeBufferPointer { ptr in
                        write(master, ptr.baseAddress!, ptr.count)
                    }
                    _ = waitBrief(0.15)
                    let cr: [UInt8] = [0x0D]
                    _ = cr.withUnsafeBufferPointer { ptr in
                        write(master, ptr.baseAddress!, ptr.count)
                    }
                    trustAccepts += 1
                    _ = waitBrief(0.9)
                } else {
                    _ = waitBrief(0.2)
                }
                continue
            }
            if source == "codex", looksLikeCodexUpgradePrompt(recent) {
                // Option 2 is "Skip" — never run `brew upgrade` from a probe.
                if codexUpgradeSkips < 4 {
                    let two: [UInt8] = [UInt8(ascii: "2")]
                    _ = two.withUnsafeBufferPointer { ptr in
                        write(master, ptr.baseAddress!, ptr.count)
                    }
                    _ = waitBrief(0.15)
                    let cr: [UInt8] = [0x0D]
                    _ = cr.withUnsafeBufferPointer { ptr in
                        write(master, ptr.baseAddress!, ptr.count)
                    }
                    codexUpgradeSkips += 1
                    _ = waitBrief(0.9)
                } else {
                    _ = waitBrief(0.2)
                }
                continue
            }
            // Codex: MCP startup can never finish (built-in `codex_apps`), and
            // the TUI itself offers "esc to interrupt". Take it — a probe reads
            // one screen and has no use for tool hosts. Bounded, so a
            // misdetection cannot turn into an Escape storm.
            if source == "codex", codexMCPInterrupts < 1, looksLikeCodexMCPStarting(text) {
                let esc: [UInt8] = [0x1B]
                _ = esc.withUnsafeBufferPointer { ptr in
                    write(master, ptr.baseAddress!, ptr.count)
                }
                codexMCPInterrupts += 1
                _ = waitBrief(0.7)
                continue
            }
            if looksReadyForUsageCommand(text, source: source) {
                sawReady = true
                break
            }
            if childExited(pid) {
                appendAvailable(from: master, into: &buffer)
                break
            }
            _ = waitBrief(0.05)
        }

        if !sawReady {
            let text = decodeAndStrip(buffer)
            let recent = recentPaintWindow(text)
            if looksLikeWorkspaceTrustDialog(recent) {
                // Still on trust in the recent window — dump; fail closed.
                writeDebugDump(
                    source: source.isEmpty ? "unknown" : source,
                    text: text,
                    tag: "trustStuck",
                    directory: debugDumpDirectory
                )
                return buffer.isEmpty ? .timeout : .empty
            }
            if source == "codex", looksLikeCodexUpgradePrompt(recent) {
                writeDebugDump(
                    source: source,
                    text: text,
                    tag: "upgradeStuck",
                    directory: debugDumpDirectory
                )
                return buffer.isEmpty ? .timeout : .empty
            }
        }

        guard sawReady || !buffer.isEmpty else {
            return buffer.isEmpty ? .timeout : .empty
        }

        // Brief settle so autocomplete / chrome finishes painting.
        _ = waitBrief(0.5)
        appendAvailable(from: master, into: &buffer)

        // Clear any half-typed junk (Claude autocomplete leftovers).
        let clearLine: [UInt8] = [0x15] // Ctrl-U
        _ = clearLine.withUnsafeBufferPointer { ptr in
            write(master, ptr.baseAddress!, ptr.count)
        }
        _ = waitBrief(0.1)

        // 2) Send usage/status command. Claude needs slow typing so the slash
        // menu resolves to /usage instead of leaving the chat chrome painted.
        // Codex uses /status; others use /usage.
        if Date() < deadline, !childExited(pid) {
            sendUsageCommand(master: master, source: source)
            usageSent = true
            _ = waitBrief(source == "claude_code" ? 0.8 : 0.45)
            appendAvailable(from: master, into: &buffer)
            let cr: [UInt8] = [0x0D]
            _ = cr.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
            // Claude slash menus sometimes need a second Enter to open the pane.
            if source == "claude_code" {
                _ = waitBrief(0.35)
                _ = cr.withUnsafeBufferPointer { ptr in
                    write(master, ptr.baseAddress!, ptr.count)
                }
            }
            if source == "codex" {
                _ = waitBrief(0.6)
            }
        }

        // 3) Drain until usage markers appear or budget expires.
        // Claude paints the Usage tab progressively — a single "% used" flash is
        // often a half-painted pane that fails the pure parser. Wait for a
        // parse-stable capture (or deadline) instead of returning the first flash.
        // Markers that indicate a real usage/quota surface — nothing else.
        //
        // "settings", "status", "config", "usage" and "stats" used to live here,
        // labelled "Claude Usage tab chrome". Claude never reaches this list
        // (it has its own `hasClaudeUsage` branch below) and neither does codex,
        // so those five words only ever applied to OTHER vendors' screens, where
        // they are ordinary chat chrome. cursor_agent matched "settings" and
        // "config" on a plain composer, `sawUsagePane` went true with no usage
        // text present, and the run was reported as `parserFailed` — pointing at
        // a parser for a pane that was never open.
        //
        // Same law as source-aware readiness: a generic marker may not speak for
        // a source that has its own answer.
        let usageMarkers = [
            "weekly limit", "five hour", "5h limit", "plan usage",
            "models & quota", "% used", "% remaining", "on-demand",
            "monthly plan", "included", "resets ",
            "current session", "current week",
            // codex: remaining-polarity display
            "% left",
            // grok: credit-based display
            "credit",
        ]
        while Date() < deadline {
            appendAvailable(from: master, into: &buffer)
            let lower = decodeAndStrip(buffer).lowercased()
            // Claude: chat chrome alone is not the usage pane.
            let hasClaudeUsage =
                lower.contains("current session") || lower.contains("current week")
                || (lower.contains("% used") && lower.contains("resets"))
            let hasOther = usageMarkers.contains(where: { lower.contains($0) })
            if source == "claude_code" {
                if hasClaudeUsage {
                    sawUsagePane = true
                    break
                }
            } else if source == "codex" {
                if looksLikeCodexStatusPane(decodeAndStrip(buffer)) {
                    sawUsagePane = true
                    break
                }
            } else if hasOther {
                sawUsagePane = true
                break
            }
            if childExited(pid) {
                appendAvailable(from: master, into: &buffer)
                break
            }
            _ = waitBrief(0.08)
        }

        // Claude fallback: if /usage never painted bars, try /status then look again.
        if source == "claude_code", !sawUsagePane, Date() < deadline, !childExited(pid) {
            let clear: [UInt8] = [0x15]
            _ = clear.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
            _ = waitBrief(0.15)
            let status = Array("/status".utf8)
            for byte in status {
                var b = byte
                _ = write(master, &b, 1)
                _ = waitBrief(0.03)
            }
            let cr: [UInt8] = [0x0D]
            _ = cr.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
            _ = waitBrief(0.5)
            _ = cr.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
            while Date() < deadline {
                appendAvailable(from: master, into: &buffer)
                let lower = decodeAndStrip(buffer).lowercased()
                if lower.contains("current session") || lower.contains("current week")
                    || (lower.contains("% used") && lower.contains("resets"))
                {
                    sawUsagePane = true
                    break
                }
                if childExited(pid) { break }
                _ = waitBrief(0.08)
            }
        }

        // 4) Stabilize Claude multi-pool pane: re-drain until the pure parser
        // would accept at least one window, or the budget ends. Two consecutive
        // equal non-empty parse results count as stable.
        if sawUsagePane || usageSent {
            var lastParseCount = -1
            var stableHits = 0
            while Date() < deadline {
                _ = waitBrief(0.35)
                appendAvailable(from: master, into: &buffer)
                let text = decodeAndStrip(buffer)
                let parsed = parse(source: source, renderText: text, now: Date())
                if !parsed.isEmpty {
                    if parsed.count == lastParseCount {
                        stableHits += 1
                        if stableHits >= 1 { break } // one confirm after first good parse
                    } else {
                        lastParseCount = parsed.count
                        stableHits = 0
                    }
                }
                if childExited(pid) {
                    appendAvailable(from: master, into: &buffer)
                    break
                }
            }
            // Final settle for trailing reset lines.
            _ = waitBrief(0.4)
            appendAvailable(from: master, into: &buffer)
        }

        let finalText = decodeAndStrip(buffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty {
            return usageSent ? .empty : .timeout
        }
        // Still hand text to the parser even without a marker match — the
        // markers are heuristics and the parser is authoritative. But carry the
        // marker verdict out so an empty parse can be attributed honestly.
        return .captured(finalText, sawUsagePane: sawUsagePane)
    }

    /// Type the usage slash command. Claude needs per-keystroke delay so the
    /// slash menu binds to `/usage` instead of leaving bare chat chrome.
    private static func sendUsageCommand(master: Int32, source: String) {
        let cmd = Array(probeCommand(for: source).utf8)
        if source == "claude_code" {
            // Slow typing so the slash menu resolves before Enter.
            for byte in cmd {
                var b = byte
                _ = write(master, &b, 1)
                _ = waitBrief(0.04)
            }
        } else {
            _ = cmd.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
        }
    }

    private static func spawnPTYChild(
        executable: String,
        workingDirectory: String,
        slave: Int32,
        source: String = ""
    ) throws -> pid_t {
        var attr: posix_spawnattr_t?
        var fileActions: posix_spawn_file_actions_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // Own process group so terminate can killpg without orphans.
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attr, &defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setflags(
            &attr,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )
        posix_spawnattr_setpgroup(&attr, 0)

        // stdio → slave PTY
        for fd: Int32 in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            let rc = posix_spawn_file_actions_adddup2(&fileActions, slave, fd)
            if rc != 0 { throw SpawnError(rc: rc, context: "dup2 pty → \(fd)") }
        }
        // Close master/slave extras in child is handled by close-on-exec norms;
        // still close the slave fd number itself after dup.
        _ = posix_spawn_file_actions_addclose(&fileActions, slave)

        if !workingDirectory.isEmpty {
            let rc = posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
            if rc != 0 { throw SpawnError(rc: rc, context: "chdir \(workingDirectory)") }
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
        // Do not force CI/non-interactive — these TUIs need a real interactive session.
        env.removeValue(forKey: "CI")
        env.removeValue(forKey: "NO_COLOR")
        // Claude Code inherits parent-session markers from agent hosts and then
        // starts in child/manual mode with transcript saving off. Scrub them so
        // the probe is a clean interactive session.
        if source == "claude_code" {
            let scrub = env.keys.filter {
                $0.hasPrefix("CLAUDE") || $0 == "CLAUDECODE" || $0.hasPrefix("ANTHROPIC_") || $0 == "AI_AGENT"
            }
            for key in scrub { env.removeValue(forKey: key) }
        }

        var argv: [UnsafeMutablePointer<CChar>?] =
            [strdup(executable)] + probeArguments(for: source).map { strdup($0) } + [nil]
        defer { for p in argv where p != nil { free(p) } }

        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { for p in envp where p != nil { free(p) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &fileActions, &attr, &argv, &envp)
        if rc != 0 { throw SpawnError(rc: rc, context: "posix_spawn \(executable)") }
        return pid
    }

    private struct SpawnError: Error {
        let rc: Int32
        let context: String
    }

    static func terminateProcessGroup(_ pid: pid_t) {
        guard pid > 0 else { return }
        // SIGTERM the group first; escalate to SIGKILL if it lingers.
        _ = killpg(pid, SIGTERM)
        let graceDeadline = Date().addingTimeInterval(0.6)
        while Date() < graceDeadline {
            if childExited(pid) {
                var status: Int32 = 0
                _ = waitpid(pid, &status, WNOHANG)
                return
            }
            _ = waitBrief(0.05)
        }
        _ = killpg(pid, SIGKILL)
        // Reap.
        var status: Int32 = 0
        _ = waitpid(pid, &status, WNOHANG)
        _ = waitBrief(0.05)
        _ = waitpid(pid, &status, WNOHANG)
        // One more killpg in case grandchildren reparented under the group.
        _ = killpg(pid, SIGKILL)
        _ = waitpid(pid, &status, WNOHANG)
    }

    private static func childExited(_ pid: pid_t) -> Bool {
        var status: Int32 = 0
        let rc = waitpid(pid, &status, WNOHANG)
        return rc == pid || (rc < 0 && errno == ECHILD)
    }

    private static func appendAvailable(from master: Int32, into buffer: inout Data) {
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(master, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                continue
            }
            break
        }
    }

    private static func waitBrief(_ seconds: TimeInterval) -> Bool {
        var ts = timespec(
            tv_sec: time_t(seconds),
            tv_nsec: Int((seconds - floor(seconds)) * 1_000_000_000)
        )
        _ = nanosleep(&ts, nil)
        return true
    }

    private static func decodeAndStrip(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return stripANSI(raw)
    }

    private static func stripANSI(_ input: String) -> String {
        guard input.contains("\u{001B}") else { return input }
        var s = input
        // CSI sequences
        s = s.replacingOccurrences(
            of: #"\x1B\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        // OSC sequences (BEL or ST terminated)
        s = s.replacingOccurrences(
            of: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#,
            with: "",
            options: .regularExpression
        )
        // Other ESC-lead singles
        s = s.replacingOccurrences(
            of: #"\x1B."#,
            with: "",
            options: .regularExpression
        )
        return s
    }
    #endif

    // MARK: - Unknown helper

    static func unknown(
        source: String,
        reason: CapacityUnknownReason,
        now: Date
    ) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: reason,
            source: source,
            scope: .weekly,
            observedAt: now,
            sourceTier: .tuiProbe
        )
    }
}
