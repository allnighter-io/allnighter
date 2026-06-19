import Foundation

// First-run Setup / CLI-detection types. The canonical truth that Doctor, the
// Setup flow, and the health badge all read. See docs/phases/setup/01 §2, §4–§6.

// MARK: - Manifest setup metadata (additive `setup` block on DriverManifest)

/// How to find, install, sign in to, and display a tool's CLI. Different churn
/// rate than `invoke`, so it lives in its own optional block. Additive — absent
/// on every pre-existing manifest.
public struct SetupBlock: Codable, Sendable, Equatable {
    /// Candidate command names to resolve (`["claude"]`, `["agy"]`). First match wins.
    public var bins: [String]
    /// Fallback install locations probed when the login shell can't resolve a bin
    /// (homebrew, `~/.local/bin`, version-manager shims, app bundles). `~` expands.
    public var knownPaths: [String]
    /// One-line install + where to learn more, shown only when `notInstalled`.
    public var installHint: String?
    public var docsURL: String?
    /// How to authenticate, shown when `installedNotSignedIn`.
    public var loginFlow: LoginFlow?
    /// Headless mutation/trust posture for CLIs that require flags such as
    /// `--trust`. Surfaced in doctor and `alln models --json`, not hidden in setup.
    public var headlessTrust: HeadlessTrustPolicy?

    public init(
        bins: [String],
        knownPaths: [String] = [],
        installHint: String? = nil,
        docsURL: String? = nil,
        loginFlow: LoginFlow? = nil,
        headlessTrust: HeadlessTrustPolicy? = nil
    ) {
        self.bins = bins
        self.knownPaths = knownPaths
        self.installHint = installHint
        self.docsURL = docsURL
        self.loginFlow = loginFlow
        self.headlessTrust = headlessTrust
    }
}

/// Explicit headless trust/mutation posture for a source CLI (e.g. Cursor `--trust`).
public struct HeadlessTrustPolicy: Codable, Sendable, Equatable {
    public var required: Bool
    public var cliFlag: String
    public var disclosure: String

    public init(required: Bool, cliFlag: String, disclosure: String) {
        self.required = required
        self.cliFlag = cliFlag
        self.disclosure = disclosure
    }
}

/// A driver-owned, **non-mutating** probe for whether this worker can run inside
/// a specific Project root right now (PRJ-S05). There is no universal "can this
/// CLI work here?" command, so each driver declares its own safe probe — or
/// declares it cannot be probed safely. A missing block, `mode: .none`, or
/// `declaredNonMutating == false` means the worker reports `unsafeToProbe` for
/// silent detection; readiness then only changes from an explicit user-initiated
/// run. Probes must never accept trust prompts, log in, write vendor
/// authorization, or configure a Project — they only observe. Additive; absent on
/// every pre-existing manifest. See docs/phases/Project_Spine_And_Project_Manager.md §PRJ-S05.
public struct ProjectProbe: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        /// Run a declared, bounded, non-mutating command in the Project root.
        case safeCommand
        /// No safe silent probe exists — always report `unsafeToProbe`.
        case none
    }

    public var mode: Mode
    /// Executable to run (resolved on PATH / known paths by the command runner).
    /// `nil` when `mode == .none`.
    public var command: String?
    /// argv passed verbatim, each as its own element (no shell). May include a
    /// CLI-specific safe flag (e.g. "do not require a git repo") only where safe.
    public var args: [String]
    public var timeoutSeconds: Int
    /// Lowercased substring expected in stdout on a successful (exit 0) probe to
    /// confirm `ready`. `nil` = exit 0 alone is sufficient.
    public var readyExpectation: String?
    /// Lowercased substrings meaning the CLI is installed but not signed in.
    public var authErrorPatterns: [String]
    /// Lowercased substrings meaning the CLI needs a per-Project trust/authorization
    /// prompt completed (e.g. "do you trust the files in this folder").
    public var projectAuthorizationPatterns: [String]
    /// Lowercased substrings meaning the worker is otherwise blocked here
    /// (quota exhausted, policy block, unsupported root).
    public var blockedPatterns: [String]
    /// MUST be true for Allnighter to run this probe silently in the background.
    public var declaredNonMutating: Bool

    public init(
        mode: Mode,
        command: String? = nil,
        args: [String] = [],
        timeoutSeconds: Int = 20,
        readyExpectation: String? = nil,
        authErrorPatterns: [String] = [],
        projectAuthorizationPatterns: [String] = [],
        blockedPatterns: [String] = [],
        declaredNonMutating: Bool = false
    ) {
        self.mode = mode
        self.command = command
        self.args = args
        self.timeoutSeconds = timeoutSeconds
        self.readyExpectation = readyExpectation
        self.authErrorPatterns = authErrorPatterns
        self.projectAuthorizationPatterns = projectAuthorizationPatterns
        self.blockedPatterns = blockedPatterns
        self.declaredNonMutating = declaredNonMutating
    }

    /// True only when this declares a safe command we may run silently.
    public var isSilentlyProbable: Bool {
        mode == .safeCommand && declaredNonMutating && command != nil
    }

    /// A human label for the probe command, for `probeCommandLabel`.
    public var commandLabel: String? {
        guard let command else { return nil }
        return ([command] + args).joined(separator: " ")
    }
}

/// A tool's sign-in flow. Rarely a clean `foo login` — Claude Code signs in via
/// `/login` inside an interactive `claude`; Codex prompts on first run.
public struct LoginFlow: Codable, Sendable, Equatable {
    /// The command to launch in Terminal to start sign-in (e.g. `claude`, `codex`).
    public var interactiveCommand: String
    /// Human steps, sentence case (e.g. "Run `claude`, then use `/login`.").
    public var instructions: String
    /// Lowercased substrings in stderr/stdout that mean "not signed in" — used to
    /// classify a failed smoke as `installedNotSignedIn` vs `probeFailed`.
    public var authErrorPatterns: [String]
    public var docsURL: String?

    public init(
        interactiveCommand: String,
        instructions: String,
        authErrorPatterns: [String] = [],
        docsURL: String? = nil
    ) {
        self.interactiveCommand = interactiveCommand
        self.instructions = instructions
        self.authErrorPatterns = authErrorPatterns
        self.docsURL = docsURL
    }
}

// MARK: - Resolution (how the detector will invoke the tool)

/// How a resolved tool should be launched. Health checks and runs must use the
/// SAME plan, so a tool that passes Setup actually runs. (`01` §4.3)
public enum ToolInvocation: Codable, Sendable, Equatable {
    /// Absolute path to a plain executable — today's fast path.
    case direct(path: String)
    /// Absolute path resolved from a version-manager shim / symlink.
    case shim(path: String)
    /// An alias/function that only the login shell can resolve — run via
    /// `"$SHELL" -lic`, preserving argv (never a concatenated shell string).
    case loginShell(commandName: String)

    /// The concrete executable path when one exists (direct/shim).
    public var resolvedPath: String? {
        switch self {
        case .direct(let p), .shim(let p): return p
        case .loginShell: return nil
        }
    }
}

/// What `command -v` resolved for a tool, plus whether it needs user confirmation.
public struct ToolResolution: Codable, Sendable, Equatable {
    public var invocation: ToolInvocation
    /// Raw `command -v` output (a path, or `claude: aliased to …`, or a function line).
    public var rawCommandV: String
    /// True for ambiguous aliases/functions that should ask before use (`01` §4.3).
    public var isAmbiguous: Bool

    public init(invocation: ToolInvocation, rawCommandV: String, isAmbiguous: Bool) {
        self.invocation = invocation
        self.rawCommandV = rawCommandV
        self.isAmbiguous = isAmbiguous
    }
}

// MARK: - Canonical status (one enum for Doctor + Setup + badge)

/// The single classification a tool can be in. `ready` is the ONLY status that
/// lets a worker run, set only when the smoke probe returned the token. Transient
/// UI phases (queued/detecting/re-probing) live in the view layer, not here.
public enum ModelSetupStatus: Sendable, Equatable {
    /// No bin resolved anywhere.
    case notInstalled
    /// Found, but as an ambiguous alias/function — needs a one-click confirm.
    case shimmedNeedsConfirm(ToolResolution)
    /// Detect ok, but the smoke run failed with an auth-shaped error.
    case installedNotSignedIn(LoginFlow)
    /// Detect ok, smoke failed for another reason (flag/model/timeout).
    case probeFailed(reason: String)
    /// Detect ok AND the smoke run returned the expected token.
    case ready(version: String)
    /// Detect ok (resolved + version), but the smoke probe was deliberately not
    /// run — the quota-free `alln doctor` path. Honest "installed, readiness not
    /// checked"; never treated as ready. Confirm with `alln doctor --full`.
    case installedNotProbed(version: String)

    /// Only `ready` may run.
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Stable kind label for persistence, tallies, and analytics.
    public var kind: Kind {
        switch self {
        case .notInstalled: return .notInstalled
        case .shimmedNeedsConfirm: return .shimmedNeedsConfirm
        case .installedNotSignedIn: return .installedNotSignedIn
        case .probeFailed: return .probeFailed
        case .ready: return .ready
        case .installedNotProbed: return .installedNotProbed
        }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case notInstalled, shimmedNeedsConfirm, installedNotSignedIn, probeFailed, ready, installedNotProbed
    }
}

// MARK: - Codable (flat representation for the persisted probe cache)

extension ModelSetupStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, version, reason, resolution, loginFlow
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .notInstalled: break
        case .shimmedNeedsConfirm(let r): try c.encode(r, forKey: .resolution)
        case .installedNotSignedIn(let f): try c.encode(f, forKey: .loginFlow)
        case .probeFailed(let reason): try c.encode(reason, forKey: .reason)
        case .ready(let version): try c.encode(version, forKey: .version)
        case .installedNotProbed(let version): try c.encode(version, forKey: .version)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .notInstalled: self = .notInstalled
        case .shimmedNeedsConfirm: self = .shimmedNeedsConfirm(try c.decode(ToolResolution.self, forKey: .resolution))
        case .installedNotSignedIn: self = .installedNotSignedIn(try c.decode(LoginFlow.self, forKey: .loginFlow))
        case .probeFailed: self = .probeFailed(reason: try c.decode(String.self, forKey: .reason))
        case .ready: self = .ready(version: try c.decode(String.self, forKey: .version))
        case .installedNotProbed: self = .installedNotProbed(version: try c.decode(String.self, forKey: .version))
        }
    }
}

// MARK: - Persisted probe record (the detector's cache, one per tool)

/// The cached outcome of probing one tool, persisted under
/// `AllnighterPaths.config` so the badge can populate instantly on launch and
/// runs can reuse the resolved invocation. (`01` §9)
public struct ToolProbeRecord: Codable, Sendable, Equatable, Identifiable {
    public var driverId: String
    public var status: ModelSetupStatus
    public var invocation: ToolInvocation?
    public var version: String?
    public var lastProbeAt: Date

    public var id: String { driverId }

    public init(
        driverId: String,
        status: ModelSetupStatus,
        invocation: ToolInvocation? = nil,
        version: String? = nil,
        lastProbeAt: Date
    ) {
        self.driverId = driverId
        self.status = status
        self.invocation = invocation
        self.version = version
        self.lastProbeAt = lastProbeAt
    }
}
