import SwiftUI
import AllnighterCore
import AllnighterEngine

// MARK: - R-S08 loop escalation (resume-from-GUI)

/// The one place a Loop round asks the founder a real question
/// (`docs/phases/PM_Relay.md` §4.1) and stops. `turn.threadId` IS the relay id
/// (`LoopThreadProjector`'s identity rule — no separate lookup). No existing composer
/// seam answers an open system event inline (`ThreadTurnRow` had no case for
/// `.systemEvent` at all before this), so this ships as its own affordance rather than
/// routing through `RoutingComposer`/`sendRouting` — see `RelayResumeController`'s doc
/// comment for why that would be invasive surgery instead of seam reuse.
struct RelayEscalationRow: View {
    @Environment(RelayResumeController.self) private var relayResume
    @Environment(ThreadsViewModel.self) private var threads
    let turn: ThreadTurn
    @State private var answer = ""
    @FocusState private var answerFocused: Bool

    private var loopId: String { turn.threadId }
    private var isResuming: Bool { relayResume.isResuming(loopId) }
    private var canResume: Bool { relayResume.canResume(loopId: loopId) }
    private var canSubmit: Bool {
        canResume && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResuming
    }

    var body: some View {
        if !canResume {
            readOnlyEscalation
        } else {
            answerableEscalation
        }
    }

    private var readOnlyEscalation: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            Text("Loop question (closed)")
                .font(ALFont.caption).foregroundStyle(ALColor.textMuted)
            if let note = turn.text, !note.isEmpty {
                Text("— \(note)")
                    .font(ALFont.caption).foregroundStyle(ALColor.textFaint).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var answerableEscalation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 13)).foregroundStyle(ALPalette.amber400)
                Text("Loop needs an answer").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            }
            if let note = turn.text, !note.isEmpty {
                Text(note).font(.system(size: 13)).foregroundStyle(ALColor.textSecondary).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                TextField("Your answer…", text: $answer, onCommit: submit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($answerFocused)
                    .padding(.horizontal, 10).frame(height: ALControl.height)
                    .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    .disabled(isResuming)
                Button(isResuming ? "Resuming…" : "Answer & resume", action: submit)
                    .buttonStyle(.alPrimary)
                    .disabled(!canSubmit)
            }
            if let error = relayResume.lastError[loopId] {
                Text(error).font(.system(size: 11)).foregroundStyle(ALPalette.red400)
            }
        }
        .padding(12)
        .background(ALColor.warningSurface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.accentBorder, lineWidth: 1) }
    }

    private func submit() {
        guard canSubmit else { return }
        let text = answer
        // `LoopCoordinator.resume` — same construction path as launch
        // (`RelayGUIRuntime.makeCoordinator`), never a normal chat turn.
        guard relayResume.resume(loopId: loopId, answer: text, onEvent: { _ in
            Task { @MainActor in threads.requestReload() }
        }) else { return }
        answer = ""
        answerFocused = false
    }
}
