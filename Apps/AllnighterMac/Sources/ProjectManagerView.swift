import SwiftUI
import AllnighterCore

/// The live Project Manager conversation for a project (PRJ-S15 wiring). Renders the
/// Manager timeline (answers + proposal/work-order/verification cards) and a composer.
/// Default chat is Manager chat; "What's next?" asks for one bounded proposal. Card
/// actions drive the real services through the view model.
struct ProjectManagerView: View {
    @Bindable var pm: ProjectManagerViewModel
    var onBack: () -> Void = {}
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if pm.items.isEmpty { emptyState }
                    ForEach(pm.items) { item in row(item) }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(systemImage: "chevron.left", accessibilityLabel: "Back", small: true, action: onBack)
            Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 13)).foregroundStyle(ALColor.accentText)
            Text("Project Manager").font(.system(size: 14, weight: .bold)).foregroundStyle(ALColor.textPrimary)
            if let name = pm.project?.displayName {
                Text("· \(name)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            Spacer()
            Button { pm.proposeNext() } label: {
                Label("What's next?", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(ALColor.accentText)
            .disabled(pm.isWorking)
        }
        .padding(.horizontal, 20).frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    @ViewBuilder
    private func row(_ item: ProjectManagerViewModel.Item) -> some View {
        switch item {
        case .answer(let turn):
            if turn.mode == .wait {
                waitRow(turn.warnings.first ?? "The Manager is waiting on a blocker.")
            } else {
                MarkdownText(markdown: turn.answerMarkdown ?? "").frame(maxWidth: .infinity, alignment: .leading)
            }
        case .proposal(let p):
            ProposalCard(proposal: p, onApprove: { pm.approve(p.id) }, onEdit: {}, onPostpone: { pm.postpone(p.id) })
        case .workOrder(let w):
            WorkOrderCard(order: w, onReveal: {}, onDispatch: { pm.dispatch(w.id) }, onVerify: { pm.verify(workOrderId: w.id) })
        case .verification(let v):
            VerificationCard(record: v)
        }
    }

    private func waitRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "pause.circle").font(.system(size: 13)).foregroundStyle(ALColor.statusTimeout)
            Text(message).font(.system(size: 12.5)).foregroundStyle(ALColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chat with the Project Manager")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text("Ask where things stand, or tap “What's next?” for one bounded next move. The Manager answers from this project's git, docs, and threads — it never invents.")
                .font(.system(size: 12.5)).foregroundStyle(ALColor.textMuted).lineSpacing(2)
                .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask the Project Manager…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                .lineLimit(1...5)
                .onSubmit(sendDraft)
            if pm.isWorking {
                ProgressView().controlSize(.small)
            } else {
                IconButton(systemImage: "arrow.up", accessibilityLabel: "Send", small: false, action: sendDraft)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(ALColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        pm.send(text)
    }
}
