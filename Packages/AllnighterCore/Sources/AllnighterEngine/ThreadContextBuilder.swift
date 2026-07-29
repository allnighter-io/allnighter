import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Assembles the exact context a worker will see for one turn, as a
/// `ThreadContextPacket`. Pure and deterministic: file reads go through an
/// injectable reader so tests need no disk.
///
/// The MLP measures context in bytes/characters and surfaces visible
/// truncation — never an estimated token count (no usage theater).
public struct ThreadContextBuilder: Sendable {
    public struct Options: Sendable {
        public struct AttachedFileInput: Sendable, Equatable {
            public var path: String
            public var referenceId: String?
            public var sequence: Int?
            public var projectId: String?
            public var rootRelativePath: String?
            public var resolvedPath: String?
            public var lineRange: FileLineRange?
            public var preloadedText: String?
            public var storedSha256: String?
            public var byteSize: Int?
            public var languageHint: String?

            public init(
                path: String,
                referenceId: String? = nil,
                sequence: Int? = nil,
                projectId: String? = nil,
                rootRelativePath: String? = nil,
                resolvedPath: String? = nil,
                lineRange: FileLineRange? = nil,
                preloadedText: String? = nil,
                storedSha256: String? = nil,
                byteSize: Int? = nil,
                languageHint: String? = nil
            ) {
                self.path = path
                self.referenceId = referenceId
                self.sequence = sequence
                self.projectId = projectId
                self.rootRelativePath = rootRelativePath
                self.resolvedPath = resolvedPath
                self.lineRange = lineRange
                self.preloadedText = preloadedText
                self.storedSha256 = storedSha256
                self.byteSize = byteSize
                self.languageHint = languageHint
            }
        }

        public var strategy: ContextStrategy
        /// Hard cap on the rendered body, in UTF-8 bytes.
        public var byteCap: Int
        /// `recent_turns`: keep at most this many text-bearing turns (newest).
        public var maxTurns: Int
        /// `explicit_selection`: the turns the user chose to quote.
        public var selectedTurnIds: [String]
        /// File paths/text to attach (absolute, or relative to `thread.workingDir`).
        public var attachedFiles: [AttachedFileInput]
        /// Per-file cap, in UTF-8 bytes.
        public var fileByteCap: Int
        /// Optional total cap for all attached file contents, in UTF-8 bytes.
        public var attachedFilesTotalByteCap: Int?

        public init(
            strategy: ContextStrategy = .recentTurns,
            byteCap: Int = 16_000,
            maxTurns: Int = 12,
            selectedTurnIds: [String] = [],
            attachedFiles: [String] = [],
            attachedFileInputs: [AttachedFileInput] = [],
            fileByteCap: Int = 4_000,
            attachedFilesTotalByteCap: Int? = nil
        ) {
            self.strategy = strategy
            self.byteCap = byteCap
            self.maxTurns = maxTurns
            self.selectedTurnIds = selectedTurnIds
            self.attachedFiles = attachedFileInputs + attachedFiles.map { AttachedFileInput(path: $0) }
            self.fileByteCap = fileByteCap
            self.attachedFilesTotalByteCap = attachedFilesTotalByteCap
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
        var includedFileReferences: [IncludedFileReferenceDelivery] = []
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
            var lines = ["Referenced files:"]
            var remainingFileBytes = options.attachedFilesTotalByteCap
            for (offset, input) in options.attachedFiles.enumerated().sorted(by: { lhs, rhs in
                let left = lhs.element.sequence ?? lhs.offset
                let right = rhs.element.sequence ?? rhs.offset
                return left == right ? lhs.offset < rhs.offset : left < right
            }) {
                let displayPath = input.rootRelativePath ?? input.path
                let resolved = input.resolvedPath ?? resolve(input.path, workingDir: thread.workingDir)
                guard let loaded = loadFileText(input: input, resolvedPath: resolved) else {
                    lines.append("- \(displayPath): (unreadable)")
                    continue
                }
                let capLimit = min(options.fileByteCap, remainingFileBytes ?? options.fileByteCap)
                let capResult: (String, Bool)
                if capLimit <= 0 {
                    capResult = ("(not delivered: file reference budget exhausted)", true)
                } else {
                    capResult = cap(loaded.text, toBytes: capLimit)
                }
                let capped = capResult.0
                let wasCut = capResult.1
                if wasCut {
                    truncated = true
                    notes.append("file \(displayPath) truncated to \(capLimit) bytes")
                }
                lines.append(fileReferenceBlockHeader(displayPath: displayPath, input: input) + "\n\(capped)")
                if let remaining = remainingFileBytes {
                    remainingFileBytes = max(0, remaining - min(loaded.text.utf8.count, max(0, capLimit)))
                }
                includedFiles.append(displayPath)
                includedFileReferences.append(IncludedFileReferenceDelivery(
                    referenceId: input.referenceId ?? "file-ref-\(offset)",
                    sequence: input.sequence ?? offset,
                    projectId: input.projectId,
                    rootRelativePath: displayPath,
                    lineRange: input.lineRange,
                    resolvedAbsolutePath: resolved,
                    deliveredPathUsed: displayPath,
                    storedSha256: input.storedSha256 ?? sha256Hex(Data(loaded.fullText.utf8)),
                    byteSize: input.byteSize ?? loaded.fullText.utf8.count,
                    deliveredByteCount: capped.utf8.count,
                    truncated: wasCut,
                    languageHint: input.languageHint ?? languageHint(for: displayPath),
                    deliveryMode: .attachedFileBlock
                ))
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
            truncationNote: note,
            includedFileReferences: includedFileReferences
        )
    }

    // MARK: - Rendering helpers

    private func label(for turn: ThreadTurn) -> String {
        switch turn.author {
        case .user: return "User"
        case .worker:
            let agentLabel = ThreadAgentPresentation.make(
                threadId: turn.threadId,
                turnId: turn.id,
                modelId: turn.modelId,
                modelDisplayName: nil,
                driverId: nil
            )
            if let secondary = agentLabel.secondary {
                return "\(agentLabel.primary) · \(secondary)"
            }
            return agentLabel.primary
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

    private func fileReferenceBlockHeader(
        displayPath: String,
        input: Options.AttachedFileInput
    ) -> String {
        var suffix: [String] = []
        if let range = input.lineRange {
            suffix.append("lines \(range.startLine)-\(range.endLine)")
        }
        if let language = input.languageHint, !language.isEmpty {
            suffix.append(language)
        }
        if suffix.isEmpty {
            return "- \(displayPath):"
        }
        return "- \(displayPath) (\(suffix.joined(separator: ", "))):"
    }

    private struct LoadedFileText {
        var text: String
        var fullText: String
    }

    private func loadFileText(input: Options.AttachedFileInput, resolvedPath: String) -> LoadedFileText? {
        if let preloaded = input.preloadedText {
            return LoadedFileText(text: preloaded, fullText: preloaded)
        }
        guard let raw = fileReader(resolvedPath) else { return nil }
        if let range = input.lineRange {
            guard let sliced = slice(raw, lineRange: range) else { return nil }
            return LoadedFileText(text: sliced, fullText: raw)
        }
        return LoadedFileText(text: raw, fullText: raw)
    }

    private func slice(_ text: String, lineRange: FileLineRange) -> String? {
        guard lineRange.startLine >= 1, lineRange.endLine >= lineRange.startLine else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lineRange.endLine <= lines.count else { return nil }
        return lines[(lineRange.startLine - 1)...(lineRange.endLine - 1)].joined(separator: "\n")
    }

    private func languageHint(for path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        let prioritized = middle.filter { $0.hasPrefix("Referenced files:") }
            + middle.filter { !$0.hasPrefix("Referenced files:") }
        var kept: [String] = [header]
        let reserved = "\n\n".utf8.count + latest.utf8.count
        var used = header.utf8.count + reserved
        for section in prioritized {
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
