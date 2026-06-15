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

    static func worker(_ id: String, driverId: String, model: String = "m", enabled: Bool = true, role: WorkerRole = .member) -> Worker {
        Worker(id: id, displayName: id, modelLabel: model, driverId: driverId, role: role, enabled: enabled)
    }

    static func seat(_ workerId: String, index: Int = 0, stance: String? = nil) -> PanelSeat {
        PanelSeat(id: PanelSeat.makeID(workerId: workerId, seatIndex: index), workerId: workerId, seatIndex: index, stance: stance)
    }

    static func seats(_ workerIds: [String]) -> [PanelSeat] {
        workerIds.map { seat($0) }
    }

    static func config(judge: String, depth: AnalysisDepth = .combined) -> SynthesisConfig {
        SynthesisConfig(analysisDepth: depth, judgeWorkerId: judge, analysisProfileId: SynthesisInstructions.analysisID, planProfileId: SynthesisInstructions.planID)
    }
}
