import Foundation
import AllnighterCore

/// What a design seat needs to generate one image: the user's instruction, the
/// persona it wears (id + its style direction), the render target, and the
/// attached "before" screenshot (absolute path) when redesigning.
public struct DesignSeatRequest: Sendable, Equatable {
    public var userPrompt: String
    public var personaId: String
    public var personaDirection: String
    public var targetShape: TargetShape
    /// Absolute path of the attached screenshot, or `nil` for greenfield.
    public var screenshotPath: String?

    public init(
        userPrompt: String,
        personaId: String,
        personaDirection: String,
        targetShape: TargetShape,
        screenshotPath: String? = nil
    ) {
        self.userPrompt = userPrompt
        self.personaId = personaId
        self.personaDirection = personaDirection
        self.targetShape = targetShape
        self.screenshotPath = screenshotPath
    }
}

/// Runs one design seat: builds the image-gen instruction, invokes the worker's
/// `imageGen` capability headlessly, then **captures and normalizes** the result to
/// a validated local image file in the run folder. Image gen is an agentic tool
/// call (not an `--out` flag); the image always arrives as a local file (PNG/JPEG,
/// never base64/URL) with the path reported in stdout — `promptDirected` engines
/// honor an explicit save path, `stdoutPath` engines (Antigravity) write to an
/// opaque dir and we parse + copy. See `docs/mvp/Design1`. Pure over a
/// `CommandRunner`, so it is fully testable with `MockCommandRunner`.
public struct DesignImageRunner: Sendable {
    private let commandRunner: CommandRunner
    private let now: @Sendable () -> Date

    public init(commandRunner: CommandRunner, now: @escaping @Sendable () -> Date = Date.init) {
        self.commandRunner = commandRunner
        self.now = now
    }

    /// Generate one option for `seat`, writing its image into `runDir`. Returns a
    /// `DesignOption` (rendered with a relative `imagePath`, or `.failed` with a
    /// reason — never throws; a failed seat is a gray tile, not a blocked board).
    public func run(
        seat: Worker,
        worker: Model,
        manifest: DriverManifest,
        request: DesignSeatRequest,
        runDir: URL
    ) async -> DesignOption {
        func failed(_ reason: String) -> DesignOption {
            DesignOption(workerId: seat.id, modelId: worker.id, persona: request.personaId,
                         status: .failed, failureReason: reason)
        }

        guard manifest.kind == .headlessCLI,
              let imageGen = manifest.imageGen,
              let command = manifest.invoke?.command else {
            return failed("worker '\(worker.id)' cannot generate images headlessly")
        }

        let relativeName = "option_\(Self.sanitize(seat.id)).png"
        let imageOut = runDir.appendingPathComponent(relativeName)
        try? FileManager.default.removeItem(at: imageOut)  // ignore a stale prior render

        let designPrompt = Self.assembleDesignPrompt(request)
        let wrapped = imageGen.promptTemplate
            .replacingOccurrences(of: "{{designPrompt}}", with: designPrompt)
            .replacingOccurrences(of: "{{imageOut}}", with: imageOut.path)
        let args = Self.resolveArgs(imageGen.args, prompt: wrapped, model: worker.modelLabel, runDir: runDir.path)

        let result = await commandRunner.run(
            command: command,
            args: args,
            stdin: imageGen.promptVia == .stdin ? wrapped : nil,
            env: manifest.invoke?.env ?? [:],
            workingDirectory: runDir.path,
            timeout: .seconds(imageGen.timeoutSeconds)
        )

        if let launchError = result.launchError { return failed(launchError) }
        if result.cancelled { return failed("image generation cancelled") }
        if result.timedOut {
            return DesignOption(workerId: seat.id, modelId: worker.id, persona: request.personaId,
                                status: .timedOut, failureReason: "image generation timed out after \(imageGen.timeoutSeconds)s")
        }
        if let code = result.exitCode, code != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return failed(stderr.isEmpty ? "image generation exited \(code)" : stderr)
        }

        let stdout = TextUtil.stripANSI(result.stdout)
        let sessionId = imageGen.sessionIdRegex.flatMap { Self.firstCapture(stdout, pattern: $0) }

        // Capture the image to the canonical local path.
        switch imageGen.arrival {
        case .promptDirected:
            // The model should have saved to imageOut. Fall back to a path parsed
            // from stdout (then copy) if it wrote elsewhere.
            if Self.isValidImage(at: imageOut) {
                break
            }
            guard let parsed = imageGen.stdoutPathRegex.flatMap({ Self.firstCapture(stdout, pattern: $0) }),
                  Self.copyImage(from: parsed, to: imageOut) else {
                return failed("no valid image at the requested path and none parseable from output")
            }
        case .stdoutPath:
            guard let parsed = imageGen.stdoutPathRegex.flatMap({ Self.firstCapture(stdout, pattern: $0) }) else {
                return failed("could not parse an image path from output")
            }
            guard Self.copyImage(from: parsed, to: imageOut) else {
                return failed("parsed image path was not a readable image: \(parsed)")
            }
        }

        return DesignOption(
            workerId: seat.id,
            modelId: worker.id,
            persona: request.personaId,
            imagePath: relativeName,
            sessionId: sessionId,
            status: .done
        )
    }

    // MARK: - Prompt assembly

    /// Builds the design instruction substituted into the engine's prompt template.
    /// Two earned constraints: preserve the screen (don't drift into a different
    /// screen) and pin the shape (so engines don't return random aspect ratios).
    static func assembleDesignPrompt(_ r: DesignSeatRequest) -> String {
        let shape = r.targetShape == .mobile ? "Render as a vertical mobile layout." : "Render as a wide desktop layout."
        var parts: [String] = []
        if let shot = r.screenshotPath {
            parts.append("Redesign the screen in the attached screenshot at \(shot). \(r.userPrompt)")
            parts.append("Keep the same screen and the same information architecture — same sections, nav, and content; change the visual style only.")
        } else {
            parts.append("Design this screen: \(r.userPrompt)")
        }
        parts.append("Design direction — \(r.personaId): \(r.personaDirection)")
        parts.append(shape)
        return parts.joined(separator: " ")
    }

    // MARK: - Arg resolution (injection-safe, per element)

    static func resolveArgs(_ args: [String], prompt: String, model: String, runDir: String) -> [String] {
        args.map { element in
            switch element {
            case "{{prompt}}": return prompt
            case "{{runDir}}": return runDir
            default: return element.replacingOccurrences(of: "{{model}}", with: model)
            }
        }
    }

    // MARK: - Capture helpers

    static func sanitize(_ workerId: String) -> String {
        workerId.replacingOccurrences(of: "#", with: "-")
    }

    /// First capture group of `pattern` in `text`, or the whole match if the
    /// pattern has no group. Trimmed.
    static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let group = match.numberOfRanges > 1 ? 1 : 0
        guard let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Copies a source image into `dest` if it is a readable PNG/JPEG. Returns true
    /// on success.
    static func copyImage(from sourcePath: String, to dest: URL) -> Bool {
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

    /// True if `url` is a non-empty file whose magic bytes are PNG or JPEG. The
    /// only output normalization that matters: no URLs, no base64, no broken tiles.
    static func isValidImage(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count >= 3 else { return false }
        let b = [UInt8](head)
        let isPNG = b.count >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47
        let isJPEG = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF
        return isPNG || isJPEG
    }
}
