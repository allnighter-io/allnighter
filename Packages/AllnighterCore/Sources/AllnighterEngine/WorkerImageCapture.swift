import Foundation
import AllnighterCore

/// Result of normalizing a worker CLI image output into a validated local file.
public struct WorkerImageCaptureResult: Sendable, Equatable {
    public var normalizedImageURL: URL?
    public var captionText: String?
    public var sessionId: String?
    public var failureReason: String?

    public init(
        normalizedImageURL: URL? = nil,
        captionText: String? = nil,
        sessionId: String? = nil,
        failureReason: String? = nil
    ) {
        self.normalizedImageURL = normalizedImageURL
        self.captionText = captionText
        self.sessionId = sessionId
        self.failureReason = failureReason
    }
}

/// Shared capture/normalize law for design seats and chat worker image replies.
/// Never scrapes vendor session folders — only `promptDirected` and `stdoutPath`
/// arrival modes from the driver manifest.
public enum WorkerImageCapture: Sendable {
    public static func capture(
        imageGen: DriverManifest.ImageGen,
        stdout: String,
        intendedOut: URL
    ) -> WorkerImageCaptureResult {
        let cleaned = TextUtil.stripANSI(stdout)
        let sessionId = imageGen.sessionIdRegex.flatMap { firstCapture(cleaned, pattern: $0) }

        switch imageGen.arrival {
        case .promptDirected:
            if isValidImage(at: intendedOut) {
                return success(intendedOut: intendedOut, stdout: cleaned, imageGen: imageGen, sessionId: sessionId)
            }
            guard let parsed = imageGen.stdoutPathRegex.flatMap({ firstCapture(cleaned, pattern: $0) }),
                  copyImage(from: parsed, to: intendedOut) else {
                return WorkerImageCaptureResult(
                    captionText: stripEmittedPaths(from: cleaned, imageGen: imageGen, intendedOut: intendedOut),
                    sessionId: sessionId,
                    failureReason: "no valid image at the requested path and none parseable from output"
                )
            }
            return success(intendedOut: intendedOut, stdout: cleaned, imageGen: imageGen, sessionId: sessionId)
        case .stdoutPath:
            guard let parsed = imageGen.stdoutPathRegex.flatMap({ firstCapture(cleaned, pattern: $0) }) else {
                return WorkerImageCaptureResult(
                    captionText: stripEmittedPaths(from: cleaned, imageGen: imageGen, intendedOut: intendedOut),
                    sessionId: sessionId,
                    failureReason: "could not parse an image path from output"
                )
            }
            guard copyImage(from: parsed, to: intendedOut) else {
                return WorkerImageCaptureResult(
                    captionText: stripEmittedPaths(from: cleaned, imageGen: imageGen, intendedOut: intendedOut),
                    sessionId: sessionId,
                    failureReason: "parsed image path was not a readable image: \(parsed)"
                )
            }
            return success(intendedOut: intendedOut, stdout: cleaned, imageGen: imageGen, sessionId: sessionId)
        }
    }

    private static func success(
        intendedOut: URL,
        stdout: String,
        imageGen: DriverManifest.ImageGen,
        sessionId: String?
    ) -> WorkerImageCaptureResult {
        WorkerImageCaptureResult(
            normalizedImageURL: intendedOut,
            captionText: stripEmittedPaths(from: stdout, imageGen: imageGen, intendedOut: intendedOut),
            sessionId: sessionId
        )
    }

    /// Removes exact emitted path lines and regex-matched path tokens from stdout prose.
    public static func stripEmittedPaths(
        from stdout: String,
        imageGen: DriverManifest.ImageGen,
        intendedOut: URL
    ) -> String? {
        var lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let intendedPath = intendedOut.path
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == intendedPath { return true }
            if let regex = imageGen.stdoutPathRegex,
               let parsed = firstCapture(trimmed, pattern: regex),
               trimmed == parsed || trimmed.contains(parsed) && trimmed.count < parsed.count + 8 {
                return true
            }
            return false
        }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    public static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let group = match.numberOfRanges > 1 ? 1 : 0
        guard let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func copyImage(from sourcePath: String, to dest: URL) -> Bool {
        let source = URL(fileURLWithPath: sourcePath)
        guard isValidImage(at: source) else { return false }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return isValidImage(at: dest)
        } catch {
            return false
        }
    }

    public static func isValidImage(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count >= 3 else { return false }
        let b = [UInt8](head)
        let isPNG = b.count >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47
        let isJPEG = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF
        return isPNG || isJPEG
    }
}
