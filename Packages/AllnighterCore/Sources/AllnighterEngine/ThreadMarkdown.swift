import Foundation
import AllnighterCore

/// Renders a work thread to a Markdown transcript for viewing and export.
/// `thread.json` is the only truth; `transcript.md` is derived (regenerated on
/// each save). Heavy turns are shown as links into their run, never inlined.
public enum ThreadMarkdown {
    public static func transcript(_ thread: WorkThread) -> String {
        var lines: [String] = ["# \(thread.title)", ""]
        if let dir = thread.workingDir {
            lines.append("_workingDir: \(dir)_")
            lines.append("")
        }

        for turn in thread.turns {
            lines.append(header(for: turn))
            if let text = turn.text, !text.isEmpty {
                lines.append("")
                lines.append(text)
            }
            for ref in turn.artifactRefs {
                lines.append("")
                lines.append("- \(artifactLine(ref))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func header(for turn: ThreadTurn) -> String {
        let who: String
        switch turn.author {
        case .user: who = "User"
        case .worker: who = turn.workerId ?? "Agent"
        case .system: who = "System"
        }
        var label = "## \(who) · \(turn.kind.rawValue)"
        if turn.status != .done {
            label += " · \(turn.status.rawValue)"
        }
        if let runId = turn.runId {
            label += " → run \(runId)"
        }
        return label
    }

    private static func artifactLine(_ ref: ArtifactRef) -> String {
        var parts = [ref.kind.rawValue]
        if let runId = ref.runId { parts.append("run \(runId)") }
        if let path = ref.path { parts.append(path) }
        if let excerpt = ref.excerpt, !excerpt.isEmpty { parts.append("“\(excerpt)”") }
        return parts.joined(separator: " — ")
    }
}
