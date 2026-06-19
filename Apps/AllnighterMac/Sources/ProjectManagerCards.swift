import SwiftUI
import AllnighterCore

// MARK: - Project Manager cards (PRJ-S14/S15)
//
// The Manager's typed turns made visible: a proposal you can approve/edit/postpone,
// the work order it produces (reveal/dispatch), and the verification that decides
// done. Pure presentational views over Core truth — actions are callbacks the host
// wires to `alln project …` / the MCP tools. Card minimums follow the UI Contract in
// docs/phases/Project_Spine_And_Project_Manager.md.

/// One bounded next move. Approve / Edit / Postpone.
struct ProposalCard: View {
    let proposal: ProjectProposal
    var onApprove: () -> Void = {}
    var onEdit: () -> Void = {}
    var onPostpone: () -> Void = {}

    var body: some View {
        PMCard(accent: .accent) {
            HStack(spacing: 8) {
                PMKindBadge(text: kindLabel, tone: .accent)
                Text(proposal.title)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                Spacer(minLength: 0)
                PMStatusBadge(text: proposal.status.rawValue.uppercased())
            }
            if !proposal.whyNow.isEmpty { PMField("Why now", proposal.whyNow) }
            if !proposal.scope.isEmpty { PMField("Scope", proposal.scope) }
            if !proposal.nonGoals.isEmpty { PMList("Non-goals", proposal.nonGoals) }
            if !proposal.risks.isEmpty { PMList("Risks / unknowns", proposal.risks) }
            if !proposal.blockingQuestions.isEmpty { PMList("Blocking questions", proposal.blockingQuestions) }
            if proposal.status == .proposed || proposal.status == .postponed {
                HStack(spacing: 8) {
                    PMButton("Approve", primary: true, action: onApprove)
                    PMButton("Edit", action: onEdit)
                    PMButton("Postpone", action: onPostpone)
                }
                .padding(.top, 2)
            }
        }
    }

    private var kindLabel: String { proposal.kind.rawValue.replacingOccurrences(of: "_", with: " ") }
}

/// The dispatchable payload from an approved proposal. Reveal / Dispatch.
struct WorkOrderCard: View {
    let order: WorkOrder
    var onReveal: () -> Void = {}
    var onDispatch: () -> Void = {}
    var onVerify: (() -> Void)? = nil

    var body: some View {
        PMCard(accent: .border) {
            HStack(spacing: 8) {
                PMKindBadge(text: "work order", tone: .neutral)
                Text(order.title).font(.system(size: 14, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                Spacer(minLength: 0)
                if order.lane != .none { PMStatusBadge(text: order.lane.rawValue.uppercased()) }
            }
            HStack(spacing: 14) {
                PMMeta("target", order.resolvedTargetSourceId ?? "—")
                PMMeta("root", (order.localRootPathSnapshot as NSString).lastPathComponent)
                if let head = order.baseGitHead, !head.isEmpty { PMMeta("base", String(head.prefix(8))) }
            }
            PMField("Prompt", String(order.promptBody.prefix(220)), mono: true)
            if !order.proofCommands.isEmpty {
                PMList("Proof commands", order.proofCommands, mono: true)
            } else if let waiver = order.proofWaiver {
                PMField("Proof", waiver)
            }
            PMField("Expected return", order.expectedReturn)
            HStack(spacing: 8) {
                PMButton("Dispatch", primary: true, action: onDispatch)
                PMButton("Reveal", action: onReveal)
                if let onVerify { PMButton("Verify return", action: onVerify) }
            }
            .padding(.top, 2)
        }
    }
}

/// The verification that decides done. Never "verified" on failure.
struct VerificationCard: View {
    let record: VerificationRecord

    var body: some View {
        PMCard(accent: outcomeTone == .done ? .done : .timeout) {
            HStack(spacing: 8) {
                PMKindBadge(text: "verification", tone: .neutral)
                PMOutcomeBadge(outcome: record.outcome)
                Spacer(minLength: 0)
            }
            ForEach(Array(record.proofResults.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(r.passed ? ALColor.statusDone : ALColor.statusTimeout)
                    Text(r.command).font(ALFont.monoSm).foregroundStyle(ALColor.textSecondary)
                    Spacer(minLength: 0)
                    Text(r.timedOut ? "timeout" : "exit \(r.exitCode.map(String.init) ?? "—")")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
            }
            if !record.scopeFindings.isEmpty { PMList("Scope findings", record.scopeFindings) }
            if !record.docsDriftFindings.isEmpty { PMList("Docs drift", record.docsDriftFindings) }
            if !record.missingProof.isEmpty { PMList("Missing proof", record.missingProof, mono: true) }
            PMField("Recommendation", record.recommendation)
        }
    }

    private var outcomeTone: PMAccent { record.outcome.isDone ? .done : .timeout }
}

// MARK: - Container (a Project Manager exchange)

/// The Manager's reply surface: an answer, then any typed cards it produced. This is
/// what a Project Manager turn renders to once chat is wired into the project thread.
struct ProjectManagerCardsView: View {
    let projectName: String
    var answerMarkdown: String? = nil
    var proposal: ProjectProposal? = nil
    var order: WorkOrder? = nil
    var verification: VerificationRecord? = nil
    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconButton(systemImage: "chevron.left", accessibilityLabel: "Back", small: true, action: onBack)
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 13)).foregroundStyle(ALColor.accentText)
                Text("Project Manager").font(.system(size: 14, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                Text("· \(projectName)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                Spacer()
            }
            .padding(.horizontal, 20).frame(height: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let answerMarkdown {
                        MarkdownText(markdown: answerMarkdown).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let proposal { ProposalCard(proposal: proposal) }
                    if let order { WorkOrderCard(order: order) }
                    if let verification { VerificationCard(record: verification) }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

// MARK: - Shared card chrome

private enum PMAccent { case accent, border, done, timeout
    var color: Color {
        switch self {
        case .accent: return ALColor.accentBorder
        case .border: return ALColor.borderDefault
        case .done: return ALColor.statusDone
        case .timeout: return ALColor.statusTimeout
        }
    }
}

private struct PMCard<Content: View>: View {
    let accent: PMAccent
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(accent.color).frame(width: 3).padding(.vertical, 12)
            }
    }
}

private struct PMField: View {
    let label: String; let value: String; var mono = false
    init(_ label: String, _ value: String, mono: Bool = false) { self.label = label; self.value = value; self.mono = mono }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textMuted)
            Text(value)
                .font(mono ? ALFont.monoSm : .system(size: 12.5))
                .foregroundStyle(ALColor.textSecondary).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PMList: View {
    let label: String; let items: [String]; var mono = false
    init(_ label: String, _ items: [String], mono: Bool = false) { self.label = label; self.items = items; self.mono = mono }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textMuted)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
                    Text(item).font(mono ? ALFont.monoSm : .system(size: 12.5)).foregroundStyle(ALColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct PMMeta: View {
    let label: String; let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(ALColor.textFaint)
            Text(value).font(ALFont.monoSm).foregroundStyle(ALColor.textSecondary)
        }
    }
}

private enum PMBadgeTone { case accent, neutral }

private struct PMKindBadge: View {
    let text: String; let tone: PMBadgeTone
    var body: some View {
        Text(text.uppercased()).font(.system(size: 8.5, weight: .semibold)).tracking(0.6)
            .foregroundStyle(tone == .accent ? ALColor.accentText : ALColor.textMuted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tone == .accent ? ALColor.accentBorder : ALColor.borderDefault, lineWidth: 1))
    }
}

private struct PMStatusBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 8.5, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textMuted)
    }
}

private struct PMOutcomeBadge: View {
    let outcome: VerificationOutcome
    var body: some View {
        let (label, color): (String, Color) = {
            switch outcome {
            case .verified: return ("VERIFIED", ALColor.statusDone)
            case .notVerified: return ("NOT VERIFIED", ALColor.statusTimeout)
            case .needsHuman: return ("NEEDS HUMAN", ALColor.accentText)
            case .waived: return ("WAIVED", ALColor.textMuted)
            }
        }()
        return Text(label).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.5), lineWidth: 1))
    }
}

private struct PMButton: View {
    let title: String; var primary = false; let action: () -> Void
    init(_ title: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.primary = primary; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary ? ALColor.textOnAmber : ALColor.textSecondary)
                .padding(.horizontal, 14).frame(height: 30)
                .background(primary ? ALColor.accent : ALColor.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? Color.clear : ALColor.borderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
