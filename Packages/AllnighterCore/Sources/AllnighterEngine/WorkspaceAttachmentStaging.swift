import Foundation
import AllnighterCore

/// Workspace mirror staging and git hygiene (law §6–7).
public struct WorkspaceAttachmentStaging: Sendable {
    public struct StageResult: Sendable, Equatable {
        public var deliveries: [IncludedAttachmentDelivery]
        public var warnings: [String]
    }

    public static let mirrorGrace: TimeInterval = 24 * 60 * 60

    /// Stage canonical attachments into `<workingDir>/.allnighter/attachments/thread_<id>/`.
    public static func stage(
        attachments: [TurnAttachment],
        deliveries: inout [IncludedAttachmentDelivery],
        threadId: String,
        workingDir: String,
        canonicalURL: (TurnAttachment) -> URL
    ) throws -> [String] {
        let mirrorRoot = URL(fileURLWithPath: workingDir)
            .appendingPathComponent(".allnighter/attachments/thread_\(threadId)", isDirectory: true)
        try FileManager.default.createDirectory(at: mirrorRoot, withIntermediateDirectories: true)
        var warnings: [String] = []

        for index in deliveries.indices {
            let attachment = attachments.first { $0.id == deliveries[index].attachmentId }
            guard let attachment else { continue }
            let source = canonicalURL(attachment)
            let dest = mirrorRoot.appendingPathComponent("\(attachment.id).png")
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: source, to: dest)
                let relative = ".allnighter/attachments/thread_\(threadId)/\(attachment.id).png"
                deliveries[index].deliveredPathUsed = relative
            } catch {
                throw AttachmentError.stageFailed
            }
        }

        warnings.append(contentsOf: GitAttachmentHygiene.ensureIgnored(workingDir: workingDir))
        return warnings
    }

    /// Remove mirror files older than terminal + grace. Never touches canonical store.
    @discardableResult
    public static func cleanupMirrors(
        workingDir: String,
        threadId: String,
        terminalBefore: Date,
        now: Date = Date()
    ) throws -> [String] {
        let cutoff = terminalBefore.addingTimeInterval(mirrorGrace)
        guard now >= cutoff else { return [] }
        let mirrorRoot = URL(fileURLWithPath: workingDir)
            .appendingPathComponent(".allnighter/attachments/thread_\(threadId)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: mirrorRoot.path) else { return [] }
        var removed: [String] = []
        let files = try FileManager.default.contentsOfDirectory(at: mirrorRoot, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.removeItem(at: file)
            removed.append(file.lastPathComponent)
        }
        if files.isEmpty == false {
            try? FileManager.default.removeItem(at: mirrorRoot)
        }
        return removed
    }
}

public enum GitAttachmentHygiene {
    private static let ignoreLine = ".allnighter/"

    /// Idempotently append `.allnighter/` to gitignore or info/exclude (law §7).
    @discardableResult
    public static func ensureIgnored(workingDir: String) -> [String] {
        let root = URL(fileURLWithPath: workingDir)
        let gitignore = root.appendingPathComponent(".gitignore")
        let gitDir = root.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else { return [] }

        if FileManager.default.fileExists(atPath: gitignore.path) {
            if appendLineIfNeeded(to: gitignore) { return [] }
            return ["ATTACHMENT_STAGE_UNIGNORED"]
        }

        let exclude = gitDir.appendingPathComponent("info/exclude")
        if appendLineIfNeeded(to: exclude) { return [] }
        return ["ATTACHMENT_STAGE_UNIGNORED"]
    }

    private static func appendLineIfNeeded(to url: URL) -> Bool {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if existing.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == ignoreLine }) {
            return true
        }
        var text = existing
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += ignoreLine + "\n"
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
