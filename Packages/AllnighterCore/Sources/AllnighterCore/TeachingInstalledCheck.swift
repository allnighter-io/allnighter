import Foundation

/// Doctor probe: is the Allnighter teaching snippet installed in each GLOBAL
/// host instructions file? (`docs/archive/phases/Agent_Onboarding.md` ONB-S01).
///
/// Pure Core — reads only. Project-scoped files are NEVER probed. Unit tests
/// inject contents / a fake home; they must not touch real `~/.claude` or
/// `~/.cursor`.
public enum TeachingInstalledCheck {
    public static let checkName = "teaching.installed"

    /// Frozen v1 GLOBAL host support matrix. Do not invent paths hosts won't load.
    ///
    /// - `claude`: `~/.claude/CLAUDE.md` — Claude Code's user-level default instructions.
    /// - `cursor`: `~/.cursor/rules/allnighter.mdc` — Cursor loads user-global rules from
    ///   `~/.cursor/rules/` across projects; a dedicated `allnighter.mdc` keeps the
    ///   teaching block findable without touching project `.cursor/rules`.
    /// - `codex`: unsupported in v1 — there is no well-known *global* AGENTS.md loader;
    ///   paste via `alln bootstrap --host codex` into a project AGENTS.md instead.
    public enum HostKind: String, Sendable, CaseIterable {
        case claude
        case cursor
        case codex
    }

    public enum HostSupport: Sendable, Equatable {
        case supported(relativePath: String)
        case unsupported(reason: String)
    }

    public struct HostTarget: Sendable, Equatable {
        public var host: HostKind
        public var support: HostSupport

        public init(host: HostKind, support: HostSupport) {
            self.host = host
            self.support = support
        }

        public var id: String { host.rawValue }
    }

    /// v1 matrix — freeze here; S03 installer enumerates the same paths.
    public static let hostMatrix: [HostTarget] = [
        HostTarget(host: .claude, support: .supported(relativePath: ".claude/CLAUDE.md")),
        HostTarget(
            host: .cursor,
            support: .supported(relativePath: ".cursor/rules/allnighter.mdc")
        ),
        HostTarget(
            host: .codex,
            support: .unsupported(
                reason: "no global instruction file for Codex in v1 — paste via `alln bootstrap --host codex` into project AGENTS.md"
            )
        ),
    ]

    public struct TargetResult: Sendable, Equatable {
        public var hostId: String
        public var state: TeachingSnippet.InstallState
        /// For unsupported hosts, state is `.absent` and this explains why (notChecked semantics).
        public var unsupported: Bool
        public var detail: String
        public var path: String?

        public init(
            hostId: String,
            state: TeachingSnippet.InstallState,
            unsupported: Bool = false,
            detail: String,
            path: String? = nil
        ) {
            self.hostId = hostId
            self.state = state
            self.unsupported = unsupported
            self.detail = detail
            self.path = path
        }
    }

    /// How to obtain file bytes for a supported host (tests inject; live reads path).
    public enum FileSource: Sendable, Equatable {
        /// Read `path` from disk.
        case path
        /// File is absent (no disk touch).
        case absent
        /// Exact file contents (no disk touch).
        case contents(String)
    }

    /// Injectable probe input: either raw contents (tests) or a URL to read.
    public struct TargetInput: Sendable {
        public var hostId: String
        public var unsupported: Bool
        public var unsupportedReason: String?
        public var path: String?
        public var source: FileSource

        public init(
            hostId: String,
            unsupported: Bool = false,
            unsupportedReason: String? = nil,
            path: String? = nil,
            source: FileSource = .path
        ) {
            self.hostId = hostId
            self.unsupported = unsupported
            self.unsupportedReason = unsupportedReason
            self.path = path
            self.source = source
        }
    }

    /// Build default injectable inputs under `homeDirectory` (no I/O yet).
    public static func defaultInputs(homeDirectory: URL) -> [TargetInput] {
        hostMatrix.map { target in
            switch target.support {
            case .supported(let relative):
                let url = homeDirectory.appendingPathComponent(relative)
                return TargetInput(hostId: target.id, path: url.path)
            case .unsupported(let reason):
                return TargetInput(
                    hostId: target.id,
                    unsupported: true,
                    unsupportedReason: reason
                )
            }
        }
    }

    /// Probe each target. When `inputs` is nil → `notChecked` (unit-test default).
    public static func check(
        inputs: [TargetInput]?,
        fileManager: FileManager = .default
    ) -> DoctorResult.Check {
        guard let inputs else {
            return .init(
                name: checkName,
                status: .notChecked,
                detail: "teaching install not checked (no host paths)"
            )
        }

        let results = inputs.map { probe($0, fileManager: fileManager) }
        return aggregate(results)
    }

    public static func probe(
        _ input: TargetInput,
        fileManager: FileManager = .default
    ) -> TargetResult {
        if input.unsupported {
            return TargetResult(
                hostId: input.hostId,
                state: .absent,
                unsupported: true,
                detail: input.unsupportedReason
                    ?? "unsupported host in v1",
                path: input.path
            )
        }

        let contents: String?
        switch input.source {
        case .absent:
            contents = nil
        case .contents(let text):
            contents = text
        case .path:
            guard let path = input.path else {
                return TargetResult(
                    hostId: input.hostId,
                    state: .absent,
                    detail: "no path for \(input.hostId)",
                    path: nil
                )
            }
            if fileManager.fileExists(atPath: path) {
                guard let data = fileManager.contents(atPath: path),
                      let text = String(data: data, encoding: .utf8) else {
                    return TargetResult(
                        hostId: input.hostId,
                        state: .malformed,
                        detail: "teaching file unreadable at \(path)",
                        path: path
                    )
                }
                contents = text
            } else {
                contents = nil
            }
        }

        let parsed = TeachingSnippet.parse(contents)
        return TargetResult(
            hostId: input.hostId,
            state: parsed.state,
            detail: parsed.detail,
            path: input.path
        )
    }

    public static func aggregate(_ results: [TargetResult]) -> DoctorResult.Check {
        let supported = results.filter { !$0.unsupported }
        let unsupported = results.filter(\.unsupported)

        var parts: [String] = supported.map { "\($0.hostId)=\($0.state.rawValue)" }
        for u in unsupported {
            parts.append("\(u.hostId)=unsupported")
        }
        let summary = parts.joined(separator: "; ")

        let problem = supported.first { $0.state != .installed }
        if supported.allSatisfy({ $0.state == .installed }) {
            return .init(
                name: checkName,
                status: .ok,
                detail: "teaching installed (\(summary))"
            )
        }

        // Absent / stale / modified / malformed on any supported host → degraded.
        // Unsupported hosts never fail the aggregate by themselves.
        let worst = supported.map(\.state)
        let fix: String?
        if worst.contains(.modified) || worst.contains(.malformed) {
            // S03 owns repair-with-diff; S01 points at bootstrap paste.
            fix = "alln bootstrap"
        } else if worst.contains(.stale) || worst.contains(.absent) {
            fix = "alln bootstrap"
        } else {
            fix = nil
        }

        let lead: String
        if let problem {
            lead = "teaching \(problem.state.rawValue) on \(problem.hostId)"
        } else {
            lead = "teaching not fully installed"
        }

        return .init(
            name: checkName,
            status: .degraded,
            detail: "\(lead) (\(summary))",
            fixCommand: fix,
            requiresManual: true
        )
    }
}
