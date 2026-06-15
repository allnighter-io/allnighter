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

    static func worker(_ id: String, driverId: String, model: String = "m", enabled: Bool = true, role: ModelRole = .member) -> Model {
        Model(id: id, displayName: id, modelLabel: model, driverId: driverId, role: role, enabled: enabled)
    }

    static func seat(_ modelId: String, index: Int = 0, skillId: String? = nil) -> Worker {
        Worker(id: Worker.makeID(modelId: modelId, instanceIndex: index), modelId: modelId, instanceIndex: index, skillId: skillId)
    }

    static func workers(_ workerIds: [String]) -> [Worker] {
        workerIds.map { seat($0) }
    }

    static func config(judge: String, depth: AnalysisDepth = .combined) -> SynthesisConfig {
        SynthesisConfig(analysisDepth: depth, planWriterModelId: judge, analysisProfileId: SynthesisInstructions.analysisID, planProfileId: SynthesisInstructions.planID)
    }
}
