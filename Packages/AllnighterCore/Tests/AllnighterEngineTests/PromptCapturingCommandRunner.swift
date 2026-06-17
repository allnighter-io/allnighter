import Foundation
import AllnighterCore
@testable import AllnighterEngine

/// CI fake vision worker: captures prompts and asserts image path blocks (CIA-S01).
public final class PromptCapturingCommandRunner: CommandRunner, @unchecked Sendable {
    private final class Box: @unchecked Sendable {
        var prompts: [String] = []
    }
    private let box = Box()

    public init() {}

    public func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        let prompt: String
        if let index = args.firstIndex(of: "-p"), index + 1 < args.count {
            prompt = args[index + 1]
        } else {
            prompt = stdin ?? args.joined(separator: " ")
        }
        box.prompts.append(prompt)
        return CommandResult(stdout: "FAKE_VISION_OK", stderr: "", exitCode: 0)
    }

    public func lastPrompt() -> String? {
        box.prompts.last
    }
}

extension TestSupport {
    static func visionManifest(id: String, command: String, timeout: Int = 2) -> DriverManifest {
        var manifest = headlessManifest(id: id, command: command, timeout: timeout)
        manifest.readsImages = true
        return manifest
    }
}
