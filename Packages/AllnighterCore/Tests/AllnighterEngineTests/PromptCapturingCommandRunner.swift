import Foundation
import AllnighterCore
@testable import AllnighterEngine

/// CI fake vision worker: captures prompts and asserts image path blocks (CIA-S01).
public final class PromptCapturingCommandRunner: CommandRunner, @unchecked Sendable {
    private final class Box: @unchecked Sendable {
        var entries: [(command: String, prompt: String)] = []
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
            let afterFlag = args[index + 1]
            // cursor_agent uses bare `-p`; the founder prompt is the final argv token.
            if afterFlag.hasPrefix("-") {
                prompt = args.last ?? afterFlag
            } else {
                prompt = afterFlag
            }
        } else {
            prompt = stdin ?? args.joined(separator: " ")
        }
        box.entries.append((command: URL(fileURLWithPath: command).lastPathComponent, prompt: prompt))
        return CommandResult(stdout: "FAKE_VISION_OK", stderr: "", exitCode: 0)
    }

    public func lastPrompt() -> String? {
        box.entries.last?.prompt
    }

    public func lastPrompt(forCommand command: String) -> String? {
        box.entries.last { $0.command == command }?.prompt
    }
}

extension TestSupport {
    static func visionManifest(id: String, command: String, timeout: Int = 2) -> DriverManifest {
        var manifest = headlessManifest(id: id, command: command, timeout: timeout)
        manifest.readsImages = true
        return manifest
    }
}
