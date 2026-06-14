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

    public init(
        id: String,
        manifestVersion: Int = 1,
        displayName: String,
        kind: DriverKind,
        detectCommand: String? = nil,
        smokeTestCommand: String? = nil,
        smokeTestExpect: String? = nil,
        invoke: Invoke? = nil,
        output: OutputSpec? = nil
    ) {
        self.id = id
        self.manifestVersion = manifestVersion
        self.displayName = displayName
        self.kind = kind
        self.detectCommand = detectCommand
        self.smokeTestCommand = smokeTestCommand
        self.smokeTestExpect = smokeTestExpect
        self.invoke = invoke
        self.output = output
    }

    /// How the prompt reaches the CLI.
    public enum PromptVia: String, Codable, Sendable {
        case arg
        case stdin
    }

    public struct Invoke: Codable, Sendable, Equatable {
        public var command: String
        public var args: [String]
        public var promptVia: PromptVia
        public var env: [String: String]
        /// MVP: `nil` (no repo). Growth seam: the lane worktree path.
        public var workingDir: String?
        public var timeoutSeconds: Int

        public init(
            command: String,
            args: [String],
            promptVia: PromptVia = .arg,
            env: [String: String] = [:],
            workingDir: String? = nil,
            timeoutSeconds: Int = 240
        ) {
            self.command = command
            self.args = args
            self.promptVia = promptVia
            self.env = env
            self.workingDir = workingDir
            self.timeoutSeconds = timeoutSeconds
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
    }

    /// Context for resolving template tokens.
    struct ResolveContext: Sendable {
        public var prompt: String
        public var model: String
        public var workingDir: String?
        public var outputFile: String?

        public init(prompt: String, model: String, workingDir: String? = nil, outputFile: String? = nil) {
            self.prompt = prompt
            self.model = model
            self.workingDir = workingDir
            self.outputFile = outputFile
        }
    }

    /// Resolves `invoke.args` into concrete argv, substituting tokens **per
    /// element**. The prompt is never concatenated into a shell string: an arg
    /// equal to `{{prompt}}` becomes exactly one argv element holding the raw
    /// prompt, so prompt content cannot inject additional arguments or commands.
    func resolvedArgs(_ ctx: ResolveContext) -> [String] {
        guard let invoke else { return [] }
        return invoke.args.map { resolveStandaloneToken($0, ctx) }
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
