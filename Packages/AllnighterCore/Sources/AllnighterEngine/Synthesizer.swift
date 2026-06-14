import Foundation
import AllnighterCore

/// The default master-plan synthesis instruction and the section structure the
/// synthesizer is asked to produce. Editable/overridable by the user (Phase 05).
public enum SynthesisInstructions {
    public static let defaultID = "default_master_plan_v1"

    public static let defaultText = """
    You are the master synthesizer. Below is one prompt and the independent \
    answers several different AI models gave to that exact prompt. Analyze them \
    for consensus, contradictions, unique insights, blind spots, and gaps. Then \
    produce a single comprehensive Master Plan using EXACTLY these sections:

    ## Consensus
    ## Conflicts
    ## Unique insights
    ## Blind spots & gaps
    ## Risks & unknowns
    ## The Plan
    ## Open questions

    Ground every recommendation in the source answers (attribute when useful). \
    Be decisive and actionable. Output only the Master Plan in Markdown.
    """
}

/// Builds the single prompt handed to the synthesizer: the instruction, the
/// original prompt, every answered member's response labeled by worker, and an
/// honest note about any worker that did not answer.
public enum SynthesisPromptBuilder {
    public static func build(run: CouncilRun, workers: [Worker], instructions: String) -> String {
        let nameByID = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0.displayName) })
        func name(_ id: String) -> String { nameByID[id] ?? id }

        var sections: [String] = [instructions, "# Original prompt", run.prompt]

        sections.append("# Independent answers from the panel")
        for member in run.members where member.hasAnswer {
            sections.append("## \(name(member.workerId))\n\n\(member.output ?? "")")
        }

        let missing = run.members.filter { !$0.hasAnswer }
        if !missing.isEmpty {
            let lines = missing.map { member -> String in
                let reason = member.errorReason ?? member.status.rawValue
                return "- \(name(member.workerId)): \(reason)"
            }
            sections.append("# Panel completeness\nThese workers did not return an answer; account for their absence:\n" + lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}

/// Runs the synthesis step: builds the prompt and invokes the synthesizer worker
/// through the same `WorkerRunner` used for members.
public struct Synthesizer: Sendable {
    private let workerRunner: WorkerRunner

    public init(workerRunner: WorkerRunner) {
        self.workerRunner = workerRunner
    }

    public func synthesize(
        run: CouncilRun,
        synthesizer: Worker,
        manifest: DriverManifest,
        workers: [Worker],
        instructions: String = SynthesisInstructions.defaultText
    ) async -> Synthesis {
        let prompt = SynthesisPromptBuilder.build(run: run, workers: workers, instructions: instructions)
        let startedAt = Date()
        let response = await workerRunner.run(worker: synthesizer, manifest: manifest, prompt: prompt)

        var synthesis = Synthesis(
            synthesizerWorkerId: synthesizer.id,
            instructions: SynthesisInstructions.defaultID,
            status: .running,
            startedAt: startedAt,
            finishedAt: Date()
        )

        if response.status == .done, let plan = response.output {
            synthesis.masterPlanMarkdown = plan
            synthesis.status = .complete
        } else {
            synthesis.status = .failed
        }
        return synthesis
    }
}
