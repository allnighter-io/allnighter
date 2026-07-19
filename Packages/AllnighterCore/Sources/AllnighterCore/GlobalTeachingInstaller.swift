import CryptoKit
import Foundation

/// One-click GLOBAL teaching-snippet install for host agent context files
/// (`docs/phases/Agent_Onboarding.md` Decision 3 + ONB-S03).
///
/// Pure Core: injectable home + FileManager. Project-scoped files are NEVER
/// touched. The CLI still never writes vendor files — only the Mac app on an
/// explicit human click calls into this installer.
public enum GlobalTeachingInstaller {
    /// Sentinel content hash when the target file does not exist yet.
    public static let absentContentHash = "absent"

    /// Cross-project scope note shown in preview UI.
    public static let globalScopeNote =
        "This instruction is written to each host's GLOBAL file and applies across all projects on this Mac. Project AGENTS.md / CLAUDE.md files are never touched here."

    // MARK: - Host matrix (UI / doctor)

    /// v1 host support matrix — same freeze as `TeachingInstalledCheck`.
    public static var hostMatrix: [TeachingInstalledCheck.HostTarget] {
        TeachingInstalledCheck.hostMatrix
    }

    public static func displayName(for hostId: String) -> String {
        switch hostId {
        case "claude": return "Claude Code"
        case "cursor": return "Cursor"
        case "codex": return "Codex"
        default: return hostId
        }
    }

    // MARK: - Proposed action

    public enum ProposedAction: String, Sendable, Equatable, CaseIterable {
        /// File absent or no markers — append (or create) the marked block.
        case append
        /// Stale / modified / malformed — replace the marked section only.
        case repair
        /// Markers present — strip them, leave the rest of the file.
        case remove
        /// Already current — nothing to write.
        case noOp
        /// Host has no global path in v1.
        case unsupported
        /// Symlink / permissions / unreadable — do not auto-write.
        case requiresManual
    }

    // MARK: - Preview

    public struct HostPreview: Sendable, Equatable, Identifiable {
        public var id: String { hostId }
        public var hostId: String
        public var path: String?
        public var state: TeachingSnippet.InstallState
        public var unsupported: Bool
        public var unsupportedReason: String?
        /// Primary write action for Install / Repair affordances.
        public var installAction: ProposedAction
        /// Whether Remove is offered (markers present and file writable).
        public var canRemove: Bool
        public var detail: String
        /// SHA256 of current file bytes, or `absentContentHash` when missing.
        public var contentHash: String
        /// Current marked section text (LF), when a single parseable or span-able block exists.
        public var beforeBlock: String?
        /// Proposed marked section after install/repair (LF).
        public var afterBlock: String?
        /// Human-readable before→after for repair of modified/stale/malformed.
        public var diffText: String?
        /// Full file contents that would be written (LF internally; CRLF applied on write).
        public var proposedContents: String?
        public var usesCRLF: Bool
        public var error: String?

        public init(
            hostId: String,
            path: String? = nil,
            state: TeachingSnippet.InstallState,
            unsupported: Bool = false,
            unsupportedReason: String? = nil,
            installAction: ProposedAction,
            canRemove: Bool = false,
            detail: String,
            contentHash: String,
            beforeBlock: String? = nil,
            afterBlock: String? = nil,
            diffText: String? = nil,
            proposedContents: String? = nil,
            usesCRLF: Bool = false,
            error: String? = nil
        ) {
            self.hostId = hostId
            self.path = path
            self.state = state
            self.unsupported = unsupported
            self.unsupportedReason = unsupportedReason
            self.installAction = installAction
            self.canRemove = canRemove
            self.detail = detail
            self.contentHash = contentHash
            self.beforeBlock = beforeBlock
            self.afterBlock = afterBlock
            self.diffText = diffText
            self.proposedContents = proposedContents
            self.usesCRLF = usesCRLF
            self.error = error
        }
    }

    public struct Preview: Sendable, Equatable {
        public var hosts: [HostPreview]
        public var scopeNote: String

        public init(hosts: [HostPreview], scopeNote: String = GlobalTeachingInstaller.globalScopeNote) {
            self.hosts = hosts
            self.scopeNote = scopeNote
        }

        public var supported: [HostPreview] { hosts.filter { !$0.unsupported } }
        public var installable: [HostPreview] {
            supported.filter { $0.installAction == .append || $0.installAction == .repair }
        }
    }

    /// Enumerate every host and preview the exact write for supported ones.
    public static func preview(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Preview {
        let inputs = TeachingInstalledCheck.defaultInputs(homeDirectory: homeDirectory)
        let hosts = inputs.map { previewHost($0, fileManager: fileManager) }
        return Preview(hosts: hosts)
    }

    // MARK: - Apply

    public struct ApplyResult: Sendable, Equatable {
        public var hostId: String
        public var success: Bool
        public var action: ProposedAction
        public var newState: TeachingSnippet.InstallState?
        public var path: String?
        public var detail: String

        public init(
            hostId: String,
            success: Bool,
            action: ProposedAction,
            newState: TeachingSnippet.InstallState? = nil,
            path: String? = nil,
            detail: String
        ) {
            self.hostId = hostId
            self.success = success
            self.action = action
            self.newState = newState
            self.path = path
            self.detail = detail
        }
    }

    /// Apply install (append or repair) for one host. Refuses on preview→click drift.
    public static func applyInstall(
        hostId: String,
        expectedContentHash: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> ApplyResult {
        apply(
            hostId: hostId,
            intent: .install,
            expectedContentHash: expectedContentHash,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }

    /// Strip the marked teaching section for one host. Refuses on drift.
    public static func applyRemove(
        hostId: String,
        expectedContentHash: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> ApplyResult {
        apply(
            hostId: hostId,
            intent: .remove,
            expectedContentHash: expectedContentHash,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }

    /// Install/repair every supported host that needs it (skips no-op / unsupported / manual).
    public static func installAllSupported(
        preview snapshot: Preview,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [ApplyResult] {
        snapshot.installable.map { host in
            applyInstall(
                hostId: host.hostId,
                expectedContentHash: host.contentHash,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        }
    }

    // MARK: - Internals

    private enum Intent {
        case install
        case remove
    }

    private static func apply(
        hostId: String,
        intent: Intent,
        expectedContentHash: String,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> ApplyResult {
        guard let target = hostMatrix.first(where: { $0.id == hostId }) else {
            return ApplyResult(
                hostId: hostId,
                success: false,
                action: .requiresManual,
                detail: "unknown host \(hostId)"
            )
        }

        switch target.support {
        case .unsupported(let reason):
            return ApplyResult(
                hostId: hostId,
                success: false,
                action: .unsupported,
                detail: reason
            )
        case .supported(let relative):
            let url = homeDirectory.appendingPathComponent(relative)
            let path = url.path

            // Fresh preview for action + drift check against the caller's expected hash.
            let input = TeachingInstalledCheck.TargetInput(hostId: hostId, path: path)
            let fresh = previewHost(input, fileManager: fileManager)
            if fresh.contentHash != expectedContentHash {
                return ApplyResult(
                    hostId: hostId,
                    success: false,
                    action: .requiresManual,
                    path: path,
                    detail: "file changed since preview — re-check and try again (drift)"
                )
            }

            let action: ProposedAction
            switch intent {
            case .install:
                action = fresh.installAction
                guard action == .append || action == .repair else {
                    return ApplyResult(
                        hostId: hostId,
                        success: action == .noOp,
                        action: action,
                        newState: fresh.state,
                        path: path,
                        detail: action == .noOp
                            ? "already installed"
                            : (fresh.error ?? fresh.detail)
                    )
                }
            case .remove:
                guard fresh.canRemove else {
                    return ApplyResult(
                        hostId: hostId,
                        success: false,
                        action: fresh.installAction,
                        newState: fresh.state,
                        path: path,
                        detail: fresh.error ?? "nothing to remove"
                    )
                }
                action = .remove
            }

            guard let proposedLF = proposedContents(
                for: intent,
                current: readText(at: path, fileManager: fileManager),
                state: fresh.state
            ) else {
                return ApplyResult(
                    hostId: hostId,
                    success: false,
                    action: .requiresManual,
                    path: path,
                    detail: fresh.error ?? "could not compute write"
                )
            }

            let crlf = fresh.usesCRLF
            let toWrite = crlf ? toCRLF(proposedLF) : proposedLF

            do {
                try atomicWrite(text: toWrite, to: url, fileManager: fileManager)
            } catch {
                return ApplyResult(
                    hostId: hostId,
                    success: false,
                    action: action,
                    path: path,
                    detail: "write failed: \(error.localizedDescription)"
                )
            }

            let after = TeachingSnippet.parse(proposedLF)
            return ApplyResult(
                hostId: hostId,
                success: true,
                action: action,
                newState: after.state,
                path: path,
                detail: intent == .remove
                    ? "teaching block removed"
                    : "teaching \(after.state.rawValue)"
            )
        }
    }

    private static func previewHost(
        _ input: TeachingInstalledCheck.TargetInput,
        fileManager: FileManager
    ) -> HostPreview {
        if input.unsupported {
            return HostPreview(
                hostId: input.hostId,
                path: input.path,
                state: .absent,
                unsupported: true,
                unsupportedReason: input.unsupportedReason,
                installAction: .unsupported,
                detail: input.unsupportedReason ?? "unsupported host in v1",
                contentHash: absentContentHash
            )
        }

        guard let path = input.path else {
            return HostPreview(
                hostId: input.hostId,
                state: .absent,
                installAction: .requiresManual,
                detail: "no path for \(input.hostId)",
                contentHash: absentContentHash,
                error: "no path"
            )
        }

        let url = URL(fileURLWithPath: path)
        if fileManager.fileExists(atPath: path) {
            if let linkErr = symlinkGate(url: url, fileManager: fileManager) {
                return HostPreview(
                    hostId: input.hostId,
                    path: path,
                    state: .malformed,
                    installAction: .requiresManual,
                    detail: linkErr,
                    contentHash: hashFile(at: path, fileManager: fileManager) ?? absentContentHash,
                    error: linkErr
                )
            }
        }

        let raw = readRaw(at: path, fileManager: fileManager)
        let contentHash: String
        let usesCRLF: Bool
        let textLF: String?

        switch raw {
        case .absent:
            contentHash = absentContentHash
            usesCRLF = false
            textLF = nil
        case .unreadable(let reason):
            return HostPreview(
                hostId: input.hostId,
                path: path,
                state: .malformed,
                installAction: .requiresManual,
                detail: reason,
                contentHash: absentContentHash,
                error: reason
            )
        case .present(let data, let string):
            contentHash = sha256Hex(data)
            usesCRLF = string.contains("\r\n")
            textLF = toLF(string)
        }

        let parsed = TeachingSnippet.parse(textLF)
        let canonicalBlock = TeachingSnippet.wrap()

        switch parsed.state {
        case .absent:
            let proposed = appendBlock(to: textLF, block: canonicalBlock)
            return HostPreview(
                hostId: input.hostId,
                path: path,
                state: .absent,
                installAction: .append,
                canRemove: false,
                detail: textLF == nil
                    ? "file missing — will create and write teaching block"
                    : "no teaching block — will append",
                contentHash: contentHash,
                beforeBlock: nil,
                afterBlock: canonicalBlock,
                proposedContents: proposed,
                usesCRLF: usesCRLF
            )

        case .installed:
            return HostPreview(
                hostId: input.hostId,
                path: path,
                state: .installed,
                installAction: .noOp,
                canRemove: true,
                detail: parsed.detail,
                contentHash: contentHash,
                beforeBlock: canonicalBlock,
                afterBlock: canonicalBlock,
                proposedContents: textLF,
                usesCRLF: usesCRLF
            )

        case .stale, .modified:
            guard let text = textLF else {
                return HostPreview(
                    hostId: input.hostId,
                    path: path,
                    state: parsed.state,
                    installAction: .requiresManual,
                    detail: parsed.detail,
                    contentHash: contentHash,
                    error: "file unreadable"
                )
            }
            let before = TeachingSnippet.blockSpan(in: text).map { span in
                (text as NSString).substring(with: span.fullRange)
            }
            let proposed = replaceBlock(in: text, with: canonicalBlock)
            let diff = makeDiff(
                before: before ?? parsed.body ?? "(unreadable block)",
                after: canonicalBlock,
                state: parsed.state
            )
            return HostPreview(
                hostId: input.hostId,
                path: path,
                state: parsed.state,
                installAction: .repair,
                canRemove: true,
                detail: parsed.detail,
                contentHash: contentHash,
                beforeBlock: before,
                afterBlock: canonicalBlock,
                diffText: diff,
                proposedContents: proposed,
                usesCRLF: usesCRLF
            )

        case .malformed:
            // Never append a second block. Offer repair (collapse span → one block)
            // and remove when any markers exist.
            guard let text = textLF,
                  let span = TeachingSnippet.blockSpan(in: text) else {
                let err = "malformed teaching markers — will not append a second block"
                return HostPreview(
                    hostId: input.hostId,
                    path: path,
                    state: .malformed,
                    installAction: .requiresManual,
                    canRemove: false,
                    detail: "\(err); \(parsed.detail)",
                    contentHash: contentHash,
                    usesCRLF: usesCRLF,
                    error: err
                )
            }
            let before = (text as NSString).substring(with: span.fullRange)
            let proposed = replaceBlock(in: text, with: canonicalBlock)
            let diff = makeDiff(before: before, after: canonicalBlock, state: .malformed)
            let err = "malformed teaching markers — will not append a second block"
            return HostPreview(
                hostId: input.hostId,
                path: path,
                state: .malformed,
                installAction: .repair,
                canRemove: true,
                detail: "\(err); \(parsed.detail)",
                contentHash: contentHash,
                beforeBlock: before,
                afterBlock: canonicalBlock,
                diffText: diff,
                proposedContents: proposed,
                usesCRLF: usesCRLF,
                error: err
            )
        }
    }

    private static func proposedContents(
        for intent: Intent,
        current: String?,
        state: TeachingSnippet.InstallState
    ) -> String? {
        let block = TeachingSnippet.wrap()
        switch intent {
        case .install:
            switch state {
            case .absent:
                return appendBlock(to: current, block: block)
            case .stale, .modified, .malformed:
                guard let current else { return block }
                return replaceBlock(in: current, with: block)
            case .installed:
                return current
            }
        case .remove:
            guard let current else { return nil }
            return stripBlock(from: current)
        }
    }

    // MARK: - Text transforms (LF)

    private static func appendBlock(to current: String?, block: String) -> String {
        guard let current, !current.isEmpty else {
            return block.hasSuffix("\n") ? block : block + "\n"
        }
        var base = current
        if !base.hasSuffix("\n") { base += "\n" }
        if !base.hasSuffix("\n\n") { base += "\n" }
        let body = block.hasSuffix("\n") ? block : block + "\n"
        return base + body
    }

    private static func replaceBlock(in current: String, with block: String) -> String {
        guard let span = TeachingSnippet.blockSpan(in: current) else {
            return appendBlock(to: current, block: block)
        }
        let ns = current as NSString
        // `wrap()` already ends with a trailing newline; use it as the replacement body.
        let replacement = block.hasSuffix("\n") ? block : block + "\n"
        // If a newline immediately followed the old close marker, drop it so we don't
        // double-blank after inserting wrap()'s trailing newline.
        var range = span.fullRange
        let end = range.location + range.length
        if end < ns.length, ns.substring(with: NSRange(location: end, length: 1)) == "\n" {
            range.length += 1
        }
        return ns.replacingCharacters(in: range, with: replacement)
    }

    private static func stripBlock(from current: String) -> String? {
        guard let span = TeachingSnippet.blockSpan(in: current) else { return nil }
        let ns = current as NSString
        var next = ns.replacingCharacters(in: span.fullRange, with: "")
        // Collapse a double blank left by removing a block that sat between paragraphs.
        next = next.replacingOccurrences(of: "\n\n\n\n", with: "\n\n")
        if next == "\n" || next == "\r\n" { return "" }
        return next
    }

    private static func makeDiff(before: String, after: String, state: TeachingSnippet.InstallState) -> String {
        """
        --- current (\(state.rawValue))
        +++ proposed (v\(TeachingSnippet.schemaVersion))
        \(before)
        ---
        \(after)
        """
    }

    // MARK: - Filesystem contract

    private enum RawRead {
        case absent
        case unreadable(String)
        case present(Data, String)
    }

    private static func readRaw(at path: String, fileManager: FileManager) -> RawRead {
        guard fileManager.fileExists(atPath: path) else { return .absent }
        guard let data = fileManager.contents(atPath: path) else {
            return .unreadable("teaching file unreadable at \(path)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .unreadable("teaching file is not UTF-8 at \(path)")
        }
        return .present(data, text)
    }

    private static func readText(at path: String, fileManager: FileManager) -> String? {
        switch readRaw(at: path, fileManager: fileManager) {
        case .absent: return nil
        case .unreadable: return nil
        case .present(_, let text): return toLF(text)
        }
    }

    private static func hashFile(at path: String, fileManager: FileManager) -> String? {
        guard let data = fileManager.contents(atPath: path) else { return nil }
        return sha256Hex(data)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func toLF(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func toCRLF(_ s: String) -> String {
        toLF(s).replacingOccurrences(of: "\n", with: "\r\n")
    }

    /// Symlink policy: follow a file symlink to a writable regular file; otherwise fail loud.
    private static func symlinkGate(url: URL, fileManager: FileManager) -> String? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            return "path is a directory, not a file — requires manual fix"
        }

        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attrs[.type] as? FileAttributeType else {
            return nil
        }

        if type == .typeSymbolicLink {
            guard let dest = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
                return "symlink unreadable — requires manual fix"
            }
            let destURL: URL
            if (dest as NSString).isAbsolutePath {
                destURL = URL(fileURLWithPath: dest)
            } else {
                destURL = url.deletingLastPathComponent().appendingPathComponent(dest)
            }
            var destIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: destURL.path, isDirectory: &destIsDir) else {
                return "dangling symlink — requires manual fix"
            }
            if destIsDir.boolValue {
                return "symlink points at a directory — requires manual fix"
            }
            if let destAttrs = try? fileManager.attributesOfItem(atPath: destURL.path),
               let destType = destAttrs[.type] as? FileAttributeType,
               destType == .typeSymbolicLink {
                return "symlink chain — requires manual fix"
            }
            if !fileManager.isWritableFile(atPath: destURL.path) {
                return "symlink target not writable — requires manual fix"
            }
            // Followed: writes go through the symlink path (OS resolves). OK.
            return nil
        }

        if !fileManager.isWritableFile(atPath: url.path) {
            return "file not writable — requires manual fix"
        }
        return nil
    }

    /// Atomic write: temp in the same directory, then replace. Creates parent dirs.
    /// When `url` is a symlink to a writable regular file, writes via replace on the
    /// resolved destination so the symlink itself is preserved.
    private static func atomicWrite(
        text: String,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let writeURL: URL
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           (attrs[.type] as? FileAttributeType) == .typeSymbolicLink,
           let dest = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            if (dest as NSString).isAbsolutePath {
                writeURL = URL(fileURLWithPath: dest)
            } else {
                writeURL = parent.appendingPathComponent(dest)
            }
        } else {
            writeURL = url
        }

        let writeParent = writeURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: writeParent.path) {
            try fileManager.createDirectory(at: writeParent, withIntermediateDirectories: true)
        }

        let temp = writeParent.appendingPathComponent(
            ".\(writeURL.lastPathComponent).alln-teaching-\(UUID().uuidString).tmp"
        )
        guard let data = text.data(using: .utf8) else {
            throw InstallError.encoding
        }
        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: writeURL.path) {
                _ = try fileManager.replaceItemAt(writeURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: writeURL)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    public enum InstallError: Error, LocalizedError {
        case encoding
        public var errorDescription: String? {
            switch self {
            case .encoding: return "could not encode teaching file as UTF-8"
            }
        }
    }
}
