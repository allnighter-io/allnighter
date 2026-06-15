import Foundation

/// One prompt fanned out to the panel plus the synthesis that follows.
/// The Mac owns this as truth; the run-event stream (§6) is derived from it.
public struct CouncilRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var prompt: String
    public var status: RunStatus
    /// Worker ids the prompt was sent to, in display order.
    public var panel: [String]
    public var members: [MemberResponse]
    public var synthesis: Synthesis?
    /// The `PanelPreset` this run was launched from, when one was active. Optional
    /// and nil for ad-hoc runs and for runs saved before presets existed (old
    /// `run.json` decodes unchanged). Forward-compatible with RB1's
    /// `workflowPresetId`.
    public var panelPresetId: String?
    public var createdAt: Date

    public init(
        id: String,
        prompt: String,
        status: RunStatus = .draft,
        panel: [String] = [],
        members: [MemberResponse] = [],
        synthesis: Synthesis? = nil,
        panelPresetId: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.panel = panel
        self.members = members
        self.synthesis = synthesis
        self.panelPresetId = panelPresetId
        self.createdAt = createdAt
    }
}

// MARK: - Derived state

public extension CouncilRun {
    var answeredMembers: [MemberResponse] {
        members.filter(\.hasAnswer)
    }

    var failedMembers: [MemberResponse] {
        members.filter { $0.status == .failed || $0.status == .timedOut }
    }

    /// True once every non-skipped member has reached a terminal state.
    var allMembersSettled: Bool {
        members.allSatisfy { $0.status.isTerminal || $0.status == .skipped }
    }
}

// MARK: - Run state machine (single source of truth)

public extension RunStatus {
    var isTerminal: Bool {
        switch self {
        case .complete, .partial, .cancelled, .failed:
            return true
        case .draft, .fanningOut, .answersIn, .synthesizing:
            return false
        }
    }

    /// Legal next states. `failed` is reachable from any non-terminal state;
    /// `cancelled` from any active state.
    func allowedTransitions() -> Set<RunStatus> {
        switch self {
        case .draft:
            return [.fanningOut, .cancelled, .failed]
        case .fanningOut:
            return [.answersIn, .cancelled, .failed]
        case .answersIn:
            return [.synthesizing, .cancelled, .failed]
        case .synthesizing:
            return [.complete, .partial, .cancelled, .failed]
        case .complete, .partial, .cancelled, .failed:
            return []
        }
    }
}

public extension CouncilRun {
    func canTransition(to next: RunStatus) -> Bool {
        status.allowedTransitions().contains(next)
    }
}

// MARK: - Member state machine

public extension MemberStatus {
    var isTerminal: Bool {
        switch self {
        case .done, .failed, .timedOut, .cancelled:
            return true
        case .queued, .running, .skipped:
            return false
        }
    }

    func allowedTransitions() -> Set<MemberStatus> {
        switch self {
        case .queued:
            return [.running, .skipped, .cancelled]
        case .running:
            return [.done, .failed, .timedOut, .cancelled]
        case .skipped:
            // A manual-paste member: pasted answer -> done, or run later, or cancel.
            return [.running, .done, .cancelled]
        case .done, .failed, .timedOut, .cancelled:
            return []
        }
    }
}

public extension MemberResponse {
    func canTransition(to next: MemberStatus) -> Bool {
        status.allowedTransitions().contains(next)
    }
}
