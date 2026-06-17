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
        let args = WorkerImageInvoker.resolveArgs(imageGen.args, prompt: wrapped, model: worker.modelLabel, runDir: runDir.path)

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
        let sessionId = imageGen.sessionIdRegex.flatMap { WorkerImageCapture.firstCapture(stdout, pattern: $0) }

        let capture = WorkerImageCapture.capture(imageGen: imageGen, stdout: stdout, intendedOut: imageOut)
        guard capture.normalizedImageURL != nil else {
            return failed(capture.failureReason ?? "no valid image produced")
        }

        return DesignOption(
            workerId: seat.id,
            modelId: worker.id,
            persona: request.personaId,
            imagePath: relativeName,
            sessionId: capture.sessionId ?? sessionId,
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

    static func resolveArgs(_ args: [String], prompt: String, model: String, runDir: String) -> [String] {
        WorkerImageInvoker.resolveArgs(args, prompt: prompt, model: model, runDir: runDir)
    }

    // MARK: - Capture helpers (forwarded to shared `WorkerImageCapture`)

    static func sanitize(_ workerId: String) -> String {
        workerId.replacingOccurrences(of: "#", with: "-")
    }

    static func firstCapture(_ text: String, pattern: String) -> String? {
        WorkerImageCapture.firstCapture(text, pattern: pattern)
    }

    static func copyImage(from sourcePath: String, to dest: URL) -> Bool {
        WorkerImageCapture.copyImage(from: sourcePath, to: dest)
    }

    static func isValidImage(at url: URL) -> Bool {
        WorkerImageCapture.isValidImage(at: url)
    }
}
