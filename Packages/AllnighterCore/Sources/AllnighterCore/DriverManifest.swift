import Foundation

/// A thin, versioned description of how to invoke a worker's CLI and read its
/// output. Workers are described by data (manifests), not hardcoded — this is
/// the churn defense and the extensibility seam. A scoped subset of the
/// constitution's manifest schema (`ON HOLD/00` §9.8).
public struct DriverManifest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var manifestVersion: Int
    public var displayName: String
    public var kind: DriverKind

    /// Presence/version probe, e.g. `claude --version`. Optional for `manual_paste`.
    public var detectCommand: String?
    /// Health probe whose output should contain `smokeTestExpect`.
    public var smokeTestCommand: String?
    public var smokeTestExpect: String?

    /// How to run the CLI. `nil` for `manual_paste` (the user supplies the answer).
    public var invoke: Invoke?
    public var output: OutputSpec?

    /// Headless image generation (design lane, Lane 2). Present only on workers
    /// whose CLI can generate an image at $0 (Grok Imagine, Gemini via Antigravity,
    /// ChatGPT via codex). `nil` on text-only and build-only workers. Additive —
    /// absent on every existing manifest.
    public var imageGen: ImageGen?

    /// First-run Setup metadata — how to find, install, sign in to, and display
    /// this tool's CLI (`docs/phases/setup/01` §6). Additive; absent on legacy
    /// manifests, in which case detection falls back to the bare `invoke.command`.
    public var setup: SetupBlock?

    /// Driver-owned, non-mutating probe for per-Project worker readiness (PRJ-S05).
    /// Additive; absent on every legacy manifest, in which case the worker reports
    /// `unsafeToProbe` for silent detection (readiness only changes from an explicit
    /// user-initiated run). Shipped manifests stay unprobed until a real vendor-safe
    /// probe is confirmed — we never guess a CLI's trust-prompt behavior.
    public var projectProbe: ProjectProbe?

    /// How this worker exposes live output (03_Mac_Streaming). Additive and OPTIONAL:
    /// absent / `supported == false` ⇒ final-output-only via the existing `invoke`
    /// path. Only set once a real-driver Works Test shows text before process exit.
    public var streaming: Streaming?

    public init(
        id: String,
        manifestVersion: Int = 1,
        displayName: String,
        kind: DriverKind,
        detectCommand: String? = nil,
        smokeTestCommand: String? = nil,
        smokeTestExpect: String? = nil,
        invoke: Invoke? = nil,
        output: OutputSpec? = nil,
        imageGen: ImageGen? = nil,
        readsImages: Bool? = nil,
        setup: SetupBlock? = nil,
        projectProbe: ProjectProbe? = nil,
        streaming: Streaming? = nil
    ) {
        self.setup = setup
        self.projectProbe = projectProbe
        self.id = id
        self.manifestVersion = manifestVersion
        self.displayName = displayName
        self.kind = kind
        self.detectCommand = detectCommand
        self.smokeTestCommand = smokeTestCommand
        self.smokeTestExpect = smokeTestExpect
        self.invoke = invoke
        self.output = output
        self.imageGen = imageGen
        self.readsImages = readsImages
        self.streaming = streaming
    }

    /// Whether this worker can stream live partial text (a real, verified mode).
    public var canStream: Bool { streaming?.supported == true && streaming?.mode != DriverManifest.Streaming.Mode.none }

    /// True when this worker can generate a design image headlessly (design seats).
    public var canGenerateImages: Bool { imageGen != nil }

    /// Whether this worker's CLI can READ a local image file (the design build
    /// implementer — Design2 — must see the chosen image). Additive; defaults to
    /// false. The strong coding agents (Claude Code, Codex) set it true.
    public var readsImages: Bool?

    /// True when this worker can read an image headlessly (build-side, Design2).
    public var canReadImages: Bool { readsImages == true }

    /// How a worker's CLI generates an image headlessly — used by design team
    /// seats and by chat turns when `ChatImageIntent` selects the `imageGen`
    /// profile. Image gen is an agentic tool call triggered by the prompt (not an
    /// `--out` flag); the image always arrives as a **local file** (PNG/JPEG,
    /// never base64/URL), with the path reported in stdout. The manifest controls
    /// the destination via the prompt, with a stdout-path-parse fallback. See
    /// `docs/mvp/Design1` and `docs/phases/threads/08_Worker_Image_Output_In_Chat.md`.
    public struct ImageGen: Codable, Sendable, Equatable {
        /// How the model returns the image.
        public enum Arrival: String, Codable, Sendable {
            /// The model honored an explicit save path we put in the prompt
            /// (`{{imageOut}}`) — Grok, Codex.
            case promptDirected = "prompt_directed"
            /// The model wrote to an opaque artifact dir and reported the path in
            /// stdout — we parse it and copy (Antigravity).
            case stdoutPath = "stdout_path"
        }

        /// argv for the headless agentic call (tokens: `{{prompt}}`, `{{model}}`,
        /// `{{runDir}}`). `{{prompt}}` is the wrapped image instruction.
        public var args: [String]
        public var promptVia: PromptVia
        /// Wraps the design prompt into an image instruction. Must contain
        /// `{{designPrompt}}`; for `promptDirected`, also `{{imageOut}}` (the absolute
        /// path the model should save to).
        public var promptTemplate: String
        public var arrival: Arrival
        /// Extracts an absolute image path from stdout (required for `stdoutPath`,
        /// optional fallback for `promptDirected`).
        public var stdoutPathRegex: String?
        /// Captures the engine session id from stdout, for "more like this"
        /// (resume + image edit).
        public var sessionIdRegex: String?
        public var timeoutSeconds: Int

        public init(
            args: [String],
            promptVia: PromptVia = .arg,
            promptTemplate: String,
            arrival: Arrival,
            stdoutPathRegex: String? = nil,
            sessionIdRegex: String? = nil,
            timeoutSeconds: Int = 600
        ) {
            self.args = args
            self.promptVia = promptVia
            self.promptTemplate = promptTemplate
            self.arrival = arrival
            self.stdoutPathRegex = stdoutPathRegex
            self.sessionIdRegex = sessionIdRegex
            self.timeoutSeconds = timeoutSeconds
        }
    }

    /// How the prompt reaches the CLI.
    public enum PromptVia: String, Codable, Sendable {
        case arg
        case stdin
    }

    /// How a driver passes per-call effort as a flag (Claude `--effort medium`).
    /// Drivers that encode effort in the model name (Antigravity) use the model's
    /// `effortVariants` instead and carry no `effortFlag`. `nil` / absent = the
    /// driver has no effort axis (Grok).
    public struct EffortFlag: Codable, Sendable, Equatable {
        public var flag: String
        /// effort rawValue ("low"/"med"/"high") → the CLI's level token.
        public var levels: [String: String]
        public init(flag: String, levels: [String: String]) {
            self.flag = flag
            self.levels = levels
        }
    }

    public struct Invoke: Codable, Sendable, Equatable {
        public var command: String
        public var args: [String]
        public var promptVia: PromptVia
        public var env: [String: String]
        /// MVP: `nil` (no repo). Growth seam: the project execution root.
        public var workingDir: String?
        public var timeoutSeconds: Int
        /// Per-call effort flag (Claude `--effort`). Absent → no effort flag.
        public var effortFlag: EffortFlag?

        public init(
            command: String,
            args: [String],
            promptVia: PromptVia = .arg,
            env: [String: String] = [:],
            workingDir: String? = nil,
            timeoutSeconds: Int = 240,
            effortFlag: EffortFlag? = nil
        ) {
            self.command = command
            self.args = args
            self.promptVia = promptVia
            self.env = env
            self.workingDir = workingDir
            self.timeoutSeconds = timeoutSeconds
            self.effortFlag = effortFlag
        }
    }

    public enum Capture: String, Codable, Sendable {
        case stdout
        case file
    }

    public enum DoneSignal: String, Codable, Sendable {
        case exitCode = "exit_code"
        case sentinel
        case idleTimeout = "idle_timeout"
    }

    public struct OutputSpec: Codable, Sendable, Equatable {
        public var capture: Capture
        public var stripAnsi: Bool
        public var doneSignal: DoneSignal
        public var sentinel: String?

        public init(
            capture: Capture = .stdout,
            stripAnsi: Bool = true,
            doneSignal: DoneSignal = .exitCode,
            sentinel: String? = nil
        ) {
            self.capture = capture
            self.stripAnsi = stripAnsi
            self.doneSignal = doneSignal
            self.sentinel = sentinel
        }
    }

    /// How a worker's CLI exposes live output (03_Mac_Streaming §Driver Capability).
    /// Additive and OPTIONAL: a `nil` `streaming` block (or `supported == false`)
    /// means the worker is final-output-only and runs through the existing
    /// non-streaming `invoke` path. A source can be ready but not stream-capable.
    public struct Streaming: Codable, Sendable, Equatable {
        /// Shape of the live stream. `none` keeps the worker final-output-only even
        /// if a block is present.
        public enum Mode: String, Codable, Sendable {
            case none
            case plainStdout = "plain_stdout"
            case jsonlStdout = "jsonl_stdout"
            case jsonlStderr = "jsonl_stderr"
            case outputFileTail = "output_file_tail"
        }

        /// Where the canonical FINAL answer is read at settlement — independent of
        /// the live deltas, which may be lossy.
        public enum FinalAnswerSource: String, Codable, Sendable {
            case stdout
            case outputFile = "output_file"
            case event
            case parserAccumulator = "parser_accumulator"
        }

        public var supported: Bool
        public var mode: Mode
        /// Streaming-specific argv. Uses the SAME token resolver as `invoke.args`
        /// (`{{prompt}}`, `{{model}}`, `{{workingDir}}`, `{{outputFile}}`,
        /// `{{effortArgs}}`). Empty → reuse `invoke.args`.
        public var args: [String]
        /// Whether this driver emits incremental partial text (vs. final-only events).
        public var partialOutput: Bool
        /// JSON paths the parser reads for visible answer deltas (documentation /
        /// parser config; concrete parsers may hardcode these per driver).
        public var answerDeltaPaths: [String]
        public var finalAnswerSource: FinalAnswerSource
        public var stripAnsi: Bool
        /// Whether reasoning/thought events should ever surface as visible answer
        /// text. V1 is always false — reasoning is audit-only.
        public var visibleReasoning: Bool

        public init(
            supported: Bool = false,
            mode: Mode = .none,
            args: [String] = [],
            partialOutput: Bool = false,
            answerDeltaPaths: [String] = [],
            finalAnswerSource: FinalAnswerSource = .stdout,
            stripAnsi: Bool = true,
            visibleReasoning: Bool = false
        ) {
            self.supported = supported
            self.mode = mode
            self.args = args
            self.partialOutput = partialOutput
            self.answerDeltaPaths = answerDeltaPaths
            self.finalAnswerSource = finalAnswerSource
            self.stripAnsi = stripAnsi
            self.visibleReasoning = visibleReasoning
        }
    }
}

// MARK: - Injection-safe template resolution

public extension DriverManifest {
    /// Tokens a manifest may contain.
    enum Token: String, CaseIterable {
        case prompt = "{{prompt}}"
        case model = "{{model}}"
        case workingDir = "{{workingDir}}"
        /// A temp file the CLI should write its final answer to (file capture).
        case outputFile = "{{outputFile}}"
        /// Expands to the driver's per-call effort flag args (or nothing) at the
        /// exact position the CLI wants them — e.g. Claude `--effort high` at the
        /// end, Codex `-c model_reasoning_effort="high"` BEFORE the positional prompt.
        case effortArgs = "{{effortArgs}}"
    }

    /// Context for resolving template tokens.
    struct ResolveContext: Sendable {
        public var prompt: String
        public var model: String
        public var workingDir: String?
        public var outputFile: String?
        /// The run's effort — applied as a flag for drivers with `effortFlag`.
        public var effort: EffortLevel

        public init(prompt: String, model: String, workingDir: String? = nil, outputFile: String? = nil, effort: EffortLevel = .med) {
            self.prompt = prompt
            self.model = model
            self.workingDir = workingDir
            self.outputFile = outputFile
            self.effort = effort
        }
    }

    /// Resolves `invoke.args` into concrete argv, substituting tokens **per
    /// element**. The prompt is never concatenated into a shell string: an arg
    /// equal to `{{prompt}}` becomes exactly one argv element holding the raw
    /// prompt, so prompt content cannot inject additional arguments or commands.
    func resolvedArgs(_ ctx: ResolveContext) -> [String] {
        guard let invoke else { return [] }
        // `{{effortArgs}}` expands to 0–2 args at its position; every other element
        // resolves 1:1. Effort flags only appear where the manifest places the token.
        return invoke.args.flatMap { element -> [String] in
            element == Token.effortArgs.rawValue ? effortFlagArgs(ctx) : [resolveStandaloneToken(element, ctx)]
        }
    }

    /// Resolves the STREAMING argv (`streaming.args`) the same injection-safe way as
    /// `resolvedArgs`. Falls back to `invoke.args` when the streaming block carries no
    /// args of its own, so a driver can opt into a mode without re-listing argv.
    func resolvedStreamingArgs(_ ctx: ResolveContext) -> [String] {
        let template = (streaming?.args.isEmpty == false) ? streaming!.args : (invoke?.args ?? [])
        return template.flatMap { element -> [String] in
            element == Token.effortArgs.rawValue ? effortFlagArgs(ctx) : [resolveStandaloneToken(element, ctx)]
        }
    }

    /// The driver's per-call effort flag args for the run effort (Claude
    /// `["--effort","high"]`, Codex `["-c", "model_reasoning_effort=\"high\""]`),
    /// or `[]` when the driver has no effort flag or no mapping for this level.
    private func effortFlagArgs(_ ctx: ResolveContext) -> [String] {
        guard let ef = invoke?.effortFlag, let level = ef.levels[ctx.effort.rawValue] else { return [] }
        return [ef.flag, level]
    }

    /// The argv element that should be fed via stdin when `promptVia == .stdin`,
    /// or `nil` when the prompt is passed as an argument.
    func stdinPrompt(_ ctx: ResolveContext) -> String? {
        guard let invoke, invoke.promptVia == .stdin else { return nil }
        return ctx.prompt
    }

    /// Resolves a non-prompt command string (e.g. `smokeTestCommand`) where the
    /// model token may appear. Never substitutes the prompt here.
    func resolvedCommandString(_ raw: String?, model: String) -> String? {
        guard let raw else { return nil }
        return raw.replacingOccurrences(of: Token.model.rawValue, with: model)
    }

    /// Substitutes a token only when the element *is* exactly that token, so the
    /// prompt/workingDir stay isolated as single argv elements. The model token
    /// may also appear inline (it is a safe identifier, not free text).
    private func resolveStandaloneToken(_ element: String, _ ctx: ResolveContext) -> String {
        switch element {
        case Token.prompt.rawValue:
            return ctx.prompt
        case Token.workingDir.rawValue:
            return ctx.workingDir ?? ""
        case Token.outputFile.rawValue:
            return ctx.outputFile ?? ""
        default:
            return element.replacingOccurrences(of: Token.model.rawValue, with: ctx.model)
        }
    }
}
