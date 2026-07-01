import Foundation

// First-run Setup / CLI-detection types. The canonical truth that Doctor, the
// Setup flow, and the health badge all read. See docs/phases/setup/01 §2, §4–§6.
//
// The driver-capability descriptors (SetupBlock, HeadlessTrustPolicy, LoginFlow,
// ProjectProbe) moved to AgentOSCLI (AgentOS runtime seam, roadmap P1.3); they
// resolve here via `@_exported import AgentOSCLI` in AgentOSReexports.swift.

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
