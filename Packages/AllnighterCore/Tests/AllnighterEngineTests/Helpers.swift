import Foundation
import AllnighterCore
@testable import AllnighterEngine

enum TestSupport {
    static func headlessManifest(id: String, command: String, timeout: Int = 2) -> DriverManifest {
        DriverManifest(
            id: id,
            displayName: id,
            kind: .headlessCLI,
            detectCommand: "\(command) --version",
            smokeTestCommand: "\(command) smoke {{model}}",
            smokeTestExpect: "READY",
            invoke: .init(
                command: command,
                args: ["-p", "{{prompt}}", "--model", "{{model}}"],
                promptVia: .arg,
                env: [:],
                workingDir: nil,
                timeoutSeconds: timeout
            ),
            output: .init()
        )
    }

    static func worker(_ id: String, driverId: String, model: String = "m", enabled: Bool = true) -> Worker {
        Worker(id: id, displayName: id, modelLabel: model, driverId: driverId, role: .member, enabled: enabled)
    }
}
