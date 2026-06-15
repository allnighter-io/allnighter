import Foundation
import AllnighterCore

/// Assembles the exact context a worker will see for one turn, as a
/// `ThreadContextPacket`. Pure and deterministic: file reads go through an
/// injectable reader so tests need no disk.
///
/// The MLP measures context in bytes/characters and surfaces visible
/// truncation — never an estimated token count (no usage theater).
public struct ThreadContextBuilder: Sendable {
    public struct Options: Sendable {
        public var strategy: ContextStrategy
        /// Hard cap on the rendered body, in UTF-8 bytes.
        public var byteCap: Int
        /// `recent_turns`: keep at most this many text-bearing turns (newest).
        public var maxTurns: Int
        /// `explicit_selection`: the turns the user chose to quote.
        public var selectedTurnIds: [String]
        /// File paths to attach (absolute, or relative to `thread.workingDir`).
        public var attachedFiles: [String]
        /// Per-file cap, in UTF-8 bytes.
        public var fileByteCap: Int

        public init(
            strategy: ContextStrategy = .recentTurns,
            byteCap: Int = 16_000,
            maxTurns: Int = 12,
            selectedTurnIds: [String] = [],
            attachedFiles: [String] = [],
            fileByteCap: Int = 4_000
        ) {
            self.strategy = strategy
            self.byteCap = byteCap
            self.maxTurns = maxTurns
            self.selectedTurnIds = selectedTurnIds
            self.attachedFiles = attachedFiles
            self.fileByteCap = fileByteCap
        }
    }

    /// Reads an absolute file path, returning its contents or nil if unreadable.
    private let fileReader: @Sendable (String) -> String?

    public init(fileReader: @escaping @Sendable (String) -> String? = ThreadContextBuilder.defaultFileReader) {
        self.fileReader = fileReader
    }

    public static let defaultFileReader: @Sendable (String) -> String? = { path in
        try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    /// Builds a packet for `latestMessage` against `thread`'s prior turns.
    public func build(
        thread: WorkThread,
        latestMessage: String,
        turnId: String,
        packetId: String,
        now: Date,
        options: Options = Options()
    ) -> ThreadContextPacket {
        var includedTurnIds: [String] = []
        var includedRunIds: [String] = []
        var includedFiles: [String] = []
        var truncated = false
        var notes: [String] = []

        var sections: [String] = []

        // Header.
        if let dir = thread.workingDir, !dir.isEmpty {
            sections.append("Thread: \(thread.title) (workingDir: \(dir))")
        } else {
            sections.append("Thread: \(thread.title)")
        }

        // Turn context, selected by strategy.
        let textTurns = thread.turns.filter { ($0.text?.isEmpty == false) && $0.family != .system }
        switch options.strategy {
        case .recentTurns:
            let kept = Array(textTurns.suffix(options.maxTurns))
            let omitted = textTurns.count - kept.count
            if omitted > 0 {
                truncated = true
                notes.append("included last \(kept.count) turns; \(omitted) older omitted")
            }
            if !kept.isEmpty {
                var lines = ["Recent turns:"]
                for (i, turn) in kept.enumerated() {
                    lines.append("\(i + 1). \(label(for: turn)): \(turn.text ?? "")")
                    includedTurnIds.append(turn.id)
                }
                sections.append(lines.joined(separator: "\n"))
            }
        case .explicitSelection:
            let selected = options.selectedTurnIds.compactMap { id in textTurns.first { $0.id == id } }
            if !selected.isEmpty {
                var lines = ["Quoted / selected:"]
                for turn in selected {
                    lines.append("- \(label(for: turn)): \(turn.text ?? "")")
                    includedTurnIds.append(turn.id)
                }
                sections.append(lines.joined(separator: "\n"))
            }
        }

        // Attached files, resolved against workingDir and capped.
        if !options.attachedFiles.isEmpty {
            var lines = ["Attached files:"]
            for path in options.attachedFiles {
                let resolved = resolve(path, workingDir: thread.workingDir)
                guard let raw = fileReader(resolved) else {
                    lines.append("- \(path): (unreadable)")
                    continue
                }
                let (capped, wasCut) = cap(raw, toBytes: options.fileByteCap)
                if wasCut {
                    truncated = true
                    notes.append("file \(path) truncated to \(options.fileByteCap) bytes")
                }
                lines.append("- \(path):\n\(capped)")
                includedFiles.append(path)
            }
            sections.append(lines.joined(separator: "\n"))
        }

        // In-thread artifacts only (never pull artifacts from outside the thread
        // unless explicitly attached above).
        let artifacts = thread.turns.flatMap { turn in turn.artifactRefs.map { (turn, $0) } }
        if !artifacts.isEmpty {
            var lines = ["Relevant artifacts:"]
            for (_, ref) in artifacts {
                lines.append("- \(artifactLine(ref))")
                if let runId = ref.runId { includedRunIds.append(runId) }
            }
            sections.append(lines.joined(separator: "\n"))
        }

        // The new message always closes the packet.
        sections.append("Latest user message:\n\(latestMessage)")

        // Assemble, then enforce the overall byte cap by dropping whole context
        // sections from the top (header + latest message are always preserved).
        var body = sections.joined(separator: "\n\n")
        if body.utf8.count > options.byteCap {
            truncated = true
            notes.append("context trimmed to \(options.byteCap) bytes")
            body = trimToCap(sections: sections, byteCap: options.byteCap)
        }

        let note = notes.isEmpty ? nil : notes.joined(separator: "; ")
        return ThreadContextPacket(
            id: packetId,
            threadId: thread.id,
            turnId: turnId,
            createdAt: now,
            strategy: options.strategy,
            includedTurnIds: includedTurnIds,
            includedRunIds: includedRunIds.dedupedPreservingOrder(),
            includedFiles: includedFiles,
            text: body,
            truncated: truncated,
            truncationNote: note
        )
    }

    // MARK: - Rendering helpers

    private func label(for turn: ThreadTurn) -> String {
        switch turn.author {
        case .user: return "User"
        case .worker: return turn.workerId ?? "Worker"
        case .system: return "System"
        }
    }

    private func artifactLine(_ ref: ArtifactRef) -> String {
        var parts = [ref.kind.rawValue]
        if let runId = ref.runId { parts.append("from run \(runId)") }
        if let path = ref.path { parts.append(path) }
        if let excerpt = ref.excerpt, !excerpt.isEmpty { parts.append("“\(excerpt)”") }
        return parts.joined(separator: " — ")
    }

    private func resolve(_ path: String, workingDir: String?) -> String {
        if path.hasPrefix("/") { return path }
        guard let dir = workingDir, !dir.isEmpty else { return path }
        return URL(fileURLWithPath: dir).appendingPathComponent(path).path
    }

    /// Caps a string to a byte budget on a UTF-8 boundary, returning whether it
    /// was cut.
    private func cap(_ text: String, toBytes limit: Int) -> (String, Bool) {
        if text.utf8.count <= limit { return (text, false) }
        var result = ""
        var used = 0
        for char in text {
            let size = String(char).utf8.count
            if used + size > limit { break }
            result.append(char)
            used += size
        }
        return (result + "\n… (truncated)", true)
    }

    /// Keeps the header (first section) and latest message (last section), then
    /// adds middle sections until the cap is hit.
    private func trimToCap(sections: [String], byteCap: Int) -> String {
        guard sections.count > 2 else {
            return cap(sections.joined(separator: "\n\n"), toBytes: byteCap).0
        }
        let header = sections.first!
        let latest = sections.last!
        let middle = Array(sections.dropFirst().dropLast())
        var kept: [String] = [header]
        let reserved = "\n\n".utf8.count + latest.utf8.count
        var used = header.utf8.count + reserved
        for section in middle {
            let cost = "\n\n".utf8.count + section.utf8.count
            if used + cost > byteCap { break }
            kept.append(section)
            used += cost
        }
        kept.append(latest)
        return kept.joined(separator: "\n\n")
    }
}

private extension Array where Element == String {
    func dedupedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
