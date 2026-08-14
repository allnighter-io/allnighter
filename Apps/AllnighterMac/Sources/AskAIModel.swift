import Foundation
import AllnighterCore
import AllnighterEngine

/// Title-bar Ask AI session. One Auto run, inward preamble, streamed into the
/// panel — never a project thread, never a Team artifact.
@MainActor
@Observable
final class AskAIModel {
    enum Phase: Equatable {
        case idle
        case running
        case done
        case failed
    }

    var draft: String = ""
    var question: String = ""
    var answer: String = ""
    var phase: Phase = .idle
    var errorText: String?
    var onEntitlementLimited: (() -> Void)?

    private var sessionId = UUID().uuidString
    private var inFlight: Task<Void, Never>?

    var canAsk: Bool {
        phase != .running
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func newSession() {
        sessionId = UUID().uuidString
        question = ""
        answer = ""
        errorText = nil
        phase = .idle
    }

    func ask(
        service: RunService,
        repoRoot: String,
        projectId: String?,
        context: AskAIPrompt.Context
    ) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase != .running else { return }
        question = text
        draft = ""
        answer = ""
        errorText = nil
        phase = .running
        let prompt = AskAIPrompt.assemble(question: text, context: context)
        let runId = UUID().uuidString
        let threadId = sessionId
        inFlight = Task { @MainActor in
            let (events, continuation) = AsyncStream<RunEvent>.makeStream()
            let consumer = Task { @MainActor in
                for await event in events {
                    guard event.kind == RunEventKind.workerAnswerDelta,
                          let delta = event.payload["text"]?.stringValue else { continue }
                    self.answer += delta
                }
            }
            let request = RunRequest(
                message: prompt,
                repoRoot: repoRoot,
                threadId: threadId,
                projectId: projectId,
                readOnly: true
            )
            let result = await service.run(request, origin: .gui, runId: runId, events: continuation)
            await consumer.value
            switch result {
            case .success(let run):
                if self.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let output = run.answers.first?.output, !output.isEmpty
                {
                    self.answer = output
                }
                self.phase = .done
            case .failure(let error):
                self.phase = .failed
                if case .entitlementLimited = error {
                    self.errorText = EntitlementCopy.dailyCapHeadline
                    self.onEntitlementLimited?()
                } else {
                    self.errorText = error.description
                }
            }
        }
    }

    #if DEBUG
    func applyFixture(_ name: String) {
        switch name {
        case "ask-ai-done":
            question = "Where do I set the Boost window?"
            answer = "Settings › Boost window. That is when Allnighter may seed work into a vendor’s higher-limit window — not a model picker. The title-bar Models control picks the seat for this send. Default model in Settings is Auto when nothing is pinned.\n\nIf this is billing or a refund, email support@allnighter.io."
            phase = .done
            draft = ""
        default:
            newSession()
        }
    }
    #endif
}
