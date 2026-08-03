import SwiftUI
import AllnighterCore
import AllnighterEngine

// @ file-reference session — scan, rank, palette (CM-S04). State owner: RoutingComposer.

extension RoutingComposer {

    // MARK: @ file references

    /// Proof-only: force the file-reference panel rendered so its ranking/highlight can
    /// be captured in-process (the panel is inline, but the open-state can race the
    /// fixture's async project load).
    var fileReferenceFixtureOpen: Bool {
        #if DEBUG
        return GUIFixture.composeFileReferenceOpen
        #else
        return false
        #endif
    }

    var fileReferenceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedFileReferences) { ref in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(ALColor.textMuted)
                        // Cursor-style: once added, show just the filename. The full
                        // root-relative path stays available on hover (the chip's help).
                        Text(fileReferenceName(ref.path))
                            .font(ALFont.monoSm)
                            .foregroundStyle(ALColor.textSecondary)
                            .lineLimit(1)
                            .help(ref.path)
                        Button { removeFileReference(ref.path) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ALColor.textFaint)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(ALColor.subtle, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 5)
            .padding(.bottom, 1)
        }
    }
    /// Show the floating suggestions only when there's something to pick — an open @
    /// query with matches. No matches ⇒ nothing floats (no empty box).
    // Show the panel whenever an @ query is open — NEVER silently nothing. It shows the
    // matches, or an honest status (scanning / no project / no matches).
    var showsFileSuggestions: Bool {
        fileSearchOpen || fileReferenceFixtureOpen
    }

    /// Why the suggestion list is empty — so we never fail silently.
    var fileEmptyReason: String {
        if fileScanning { return "Scanning project files…" }
        if activeFileSearchRoot() == nil { return "Open a project to reference its files." }
        return fileSearchQuery.isEmpty ? "No files in this project." : "No files match “\(fileSearchQuery)”."
    }

    // A floating autocomplete that sits ABOVE the composer (no search box): a compact
    // list of root-relative paths with matched chars highlighted, the top row selected,
    // ↑/↓ to move, ⏎ to insert, Esc to dismiss — exactly the editor-grade @ pattern.
    var fileSuggestions: some View {
        VStack(spacing: 0) {
            // Quiet scope count, top-right (e.g. "6 / 1469" of project files).
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(fileSearchQuery.isEmpty ? "\(fileCandidates.count)" : "\(fileCandidates.count) / \(fileTotalCount)")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 3)
            if fileCandidates.isEmpty {
                HStack(spacing: 7) {
                    if fileScanning { ProgressView().controlSize(.small) }
                    Text(fileEmptyReason).font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                // Hug the rows (candidates are capped at 12) — no over-expanding scroll
                // area, so the popup stays compact like a real autocomplete.
                VStack(spacing: 1) {
                    ForEach(Array(fileCandidates.enumerated()), id: \.element.path) { index, candidate in
                        fileCandidateRow(candidate, index: index)
                    }
                }
                .padding(.horizontal, 5).padding(.bottom, 5)
            }
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    // One compact row: a chevron marks the selected row, then the root-relative FULL path
    // with the matched characters highlighted (Grok-Build style), middle-truncated so the
    // basename stays visible. No icon, no card, no preview.
    func fileCandidateRow(_ candidate: ProjectFileCatalog.Candidate, index: Int) -> some View {
        let active = index == highlightedFileIndex
        return Button { selectFileReference(candidate.path) } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? ALColor.textSecondary : .clear)
                    .frame(width: 10)
                Text(highlightedPath(candidate.path, query: fileSearchQuery))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlightedFileIndex = index } }
    }

    /// Root-relative path with the query's matched characters emphasized — a contiguous
    /// substring when present, else the fuzzy subsequence (mirrors the catalog's match).
    func highlightedPath(_ path: String, query: String) -> AttributedString {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = Set(Self.matchOffsets(query: q, in: path.lowercased()))
        var result = AttributedString()
        for (i, ch) in path.enumerated() {
            var piece = AttributedString(String(ch))
            if matched.contains(i) {
                piece.foregroundColor = ALColor.accent
                piece.font = .system(size: 12.5, weight: .semibold)
            } else {
                piece.foregroundColor = ALColor.textMuted
                piece.font = .system(size: 12.5)
            }
            result += piece
        }
        return result
    }

    static func matchOffsets(query q: String, in lowerPath: String) -> [Int] {
        guard !q.isEmpty else { return [] }
        if let r = lowerPath.range(of: q) {
            let start = lowerPath.distance(from: lowerPath.startIndex, to: r.lowerBound)
            return Array(start..<(start + q.count))
        }
        var offsets: [Int] = []
        var qi = q.startIndex
        for (i, ch) in lowerPath.enumerated() where qi < q.endIndex && ch == q[qi] {
            offsets.append(i)
            qi = q.index(after: qi)
        }
        return qi == q.endIndex ? offsets : []
    }
    func handleEditorCommand(_ command: ALTextEditorCommand) -> Bool {
        guard fileSearchOpen else { return false }
        switch command {
        case .returnKey:
            guard fileCandidates.indices.contains(highlightedFileIndex) else { return false }
            selectFileReference(fileCandidates[highlightedFileIndex].path)
            return true
        case .escape:
            closeFileSearch()
            return true
        case .moveUp:
            moveFileHighlight(-1)
            return true
        case .moveDown:
            moveFileHighlight(1)
            return true
        }
    }

    func moveFileHighlight(_ delta: Int) {
        guard !fileCandidates.isEmpty else { return }
        highlightedFileIndex = (highlightedFileIndex + delta + fileCandidates.count) % fileCandidates.count
    }

    func updateFileSearchFromText() {
        guard let trigger = activeFileTrigger(in: text) else {
            closeFileSearch()
            return
        }
        if selectedFileReferences.contains(where: { $0.path == trigger.query }) {
            closeFileSearch()
            return
        }
        fileSearchQuery = trigger.query
        fileSearchOpen = true
        refreshFileCandidates()
    }

    func activeFileSearchRoot() -> String? {
        #if DEBUG
        if let fxRoot = GUIFixture.fileReferenceFixtureRoot() { return fxRoot }
        #endif
        guard let project = projects.activeProject else { return nil }
        let root = project.normalizedRootPath.isEmpty ? project.localRootPath : project.normalizedRootPath
        // A stamped-but-wrong path resolves to nothing — treat it as no root so the
        // honest empty state shows instead of a silent blank.
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else { return nil }
        return root
    }

    func refreshFileCandidates() {
        guard let root = activeFileSearchRoot() else {
            fileCandidates = []; fileScanning = false; highlightedFileIndex = 0; return
        }
        // Cached snapshot for this root → rank in-memory, instantly.
        if let snap = fileSnapshot, fileScanRoot == root {
            rankFileCandidates(snap)
            return
        }
        // A scan for this root is already in flight — let it finish and rank.
        if fileScanRoot == root, fileScanning { return }
        // First @ in this session: scan ONCE off the main thread (git subprocesses), then
        // back on the main actor cache + rank. Typing never blocks on this.
        fileScanRoot = root
        fileScanning = true
        fileCandidates = []
        Task { @MainActor in
            let snap = await Task.detached(priority: .userInitiated) {
                ProjectFileCatalog().snapshot(rootPath: root)
            }.value
            guard fileSearchOpen || fileReferenceFixtureOpen, fileScanRoot == root else { fileScanning = false; return }
            fileSnapshot = snap
            fileTotalCount = snap.paths.count
            fileScanning = false
            FileHandle.standardError.write(Data("[@refs] root=\(root) paths=\(snap.paths.count) dirty=\(snap.dirty.count)\n".utf8))
            rankFileCandidates(snap)
        }
    }

    func rankFileCandidates(_ snapshot: ProjectFileCatalog.Snapshot) {
        let selectedPaths = Set(selectedFileReferences.map(\.path))
        fileCandidates = ProjectFileCatalog()
            .rank(snapshot, query: fileSearchQuery, limit: 12,
                  recentlyReferenced: selectedFileReferences.map(\.path))
            .filter { !selectedPaths.contains($0.path) }
        highlightedFileIndex = min(highlightedFileIndex, max(fileCandidates.count - 1, 0))
    }

    func closeFileSearch() {
        fileSearchOpen = false
        fileSearchQuery = ""
        fileCandidates = []
        fileTotalCount = 0
        fileSnapshot = nil
        fileScanRoot = nil
        fileScanning = false
        highlightedFileIndex = 0
    }

    func selectFileReference(_ path: String) {
        if !selectedFileReferences.contains(where: { $0.path == path }) {
            selectedFileReferences.append(ComposeFileReference(path: path))
        }
        // The chip is the durable attachment — drop the typed "@query" from the editor so
        // the file isn't shown twice (no leftover @path text + chip).
        if let range = activeFileTrigger(in: text)?.range {
            text.removeSubrange(range)
            text = text.replacingOccurrences(of: "  ", with: " ")
            if text == " " { text = "" }
        }
        closeFileSearch()
        composerFocused = true
    }

    func removeFileReference(_ path: String) {
        // The @path no longer lives in the text (the chip owns it), so just drop the chip.
        selectedFileReferences.removeAll { $0.path == path }
    }

    /// The chip label for a referenced file — just the filename (Cursor-style). The full
    /// root-relative path is still resolved/sent; only the display is shortened.
    func fileReferenceName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    func activeFileTrigger(in value: String) -> (range: Range<String.Index>, query: String)? {
        var start = value.endIndex
        while start > value.startIndex {
            let previous = value.index(before: start)
            if value[previous].isWhitespace { break }
            start = previous
        }
        let token = value[start..<value.endIndex]
        guard token.first == "@", !token.dropFirst().contains("@") else { return nil }
        return (start..<value.endIndex, String(token.dropFirst()))
    }
}
