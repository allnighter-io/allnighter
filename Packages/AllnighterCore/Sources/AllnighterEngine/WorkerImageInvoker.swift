import Foundation
import AllnighterCore

/// Neutral outcome of one `imageGen` profile CLI invocation (before capture).
public struct WorkerImageInvokeOutcome: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var launchError: String?
    public var cancelled: Bool
    public var timedOut: Bool
    public var startedAt: Date
    public var finishedAt: Date
    public var durationMs: Int

    public init(
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = nil,
        launchError: String? = nil,
        cancelled: Bool = false,
        timedOut: Bool = false,
        startedAt: Date,
        finishedAt: Date,
        durationMs: Int
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.launchError = launchError
        self.cancelled = cancelled
        self.timedOut = timedOut
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
    }
}

/// Runs a worker's `imageGen` manifest block with the same spawn/CWD law as `WorkerRunner`.
public struct WorkerImageInvoker: Sendable {
    private let commandRunner: CommandRunner
    private let invocations: [String: ToolInvocation]
    private let shellPath: String
    private let now: @Sendable () -> Date

    public init(
        commandRunner: CommandRunner,
        invocations: [String: ToolInvocation] = [:],
        shellPath: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.commandRunner = commandRunner
        self.invocations = invocations
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.now = now
    }

    public func invoke(
        worker: Model,
        manifest: DriverManifest,
        designPrompt: String,
        scratchDir: URL,
        imageOut: URL,
        workingDirectoryOverride: String? = nil
    ) async -> WorkerImageInvokeOutcome {
        guard manifest.kind == .headlessCLI,
              let imageGen = manifest.imageGen,
              let invoke = manifest.invoke else {
            let t = now()
            return WorkerImageInvokeOutcome(
                launchError: "worker '\(worker.id)' cannot generate images headlessly",
                startedAt: t, finishedAt: t, durationMs: 0
            )
        }

        try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: imageOut)

        let wrapped = imageGen.promptTemplate
            .replacingOccurrences(of: "{{designPrompt}}", with: designPrompt)
            .replacingOccurrences(of: "{{imageOut}}", with: imageOut.path)
        let args = Self.resolveArgs(imageGen.args, prompt: wrapped, model: worker.modelLabel, runDir: scratchDir.path)

        let workingDir = workingDirectoryOverride ?? invoke.workingDir
        let spawnWorkingDir = workingDir ?? AllnighterPaths.ensuredProbeScratchPath()

        let spawnCommand: String
        let spawnArgs: [String]
        switch invocations[manifest.id] {
        case .direct(let path), .shim(let path):
            spawnCommand = path
            spawnArgs = args
        case .loginShell(let name):
            spawnCommand = shellPath
            spawnArgs = ["-lic", "\(name) \"$@\"", name] + args
        case nil:
            spawnCommand = invoke.command
            spawnArgs = args
        }

        let startedAt = now()
        let result = await commandRunner.run(
            command: spawnCommand,
            args: spawnArgs,
            stdin: imageGen.promptVia == .stdin ? wrapped : nil,
            env: invoke.env,
            workingDirectory: spawnWorkingDir,
            timeout: .seconds(imageGen.timeoutSeconds)
        )
        let finishedAt = now()
        let durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)

        return WorkerImageInvokeOutcome(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            launchError: result.launchError,
            cancelled: result.cancelled,
            timedOut: result.timedOut,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationMs: durationMs
        )
    }

    static func resolveArgs(_ args: [String], prompt: String, model: String, runDir: String) -> [String] {
        args.map { element in
            switch element {
            case "{{prompt}}": return prompt
            case "{{runDir}}": return runDir
            default: return element.replacingOccurrences(of: "{{model}}", with: model)
            }
        }
    }
}
