import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Settings-less **Pending** screen — committed work per project, shown as a line.
/// Each project group is headed by its running item, with armed pending chained
/// beneath. Pure projection of `PendingQueueJSON`; actions go through the view-model
/// (→ `PendingService`). Color is earned: amber only on the count + the running dot.
struct PendingView: View {
    @State private var viewModel: PendingViewModel
    /// The pending item under review — opens the composer in a modal.
    @State private var reviewTarget: ReviewTarget?
    var onClose: () -> Void

    init(service: PendingService, onClose: @escaping () -> Void) {
        _viewModel = State(initialValue: PendingViewModel(service: service))
        self.onClose = onClose
    }

    /// A pending row opened for review (composer-in-modal).
    struct ReviewTarget: Identifiable, Equatable {
        let item: PendingItemJSON
        let position: Int
        let projectName: String
        var id: String { item.pendingItem.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(ALColor.borderSubtle)
            if viewModel.queue.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(viewModel.queue.projects, id: \.projectId) { group in
                            projectGroup(group)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1080, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALColor.base)
        .onAppear {
            #if DEBUG
            if GUIFixture.opensPendingReview, reviewTarget == nil,
               let group = viewModel.queue.projects.first, let first = group.pending.first {
                reviewTarget = ReviewTarget(item: first, position: 1, projectName: group.projectName ?? "Unassigned")
            }
            #endif
        }
        .overlay {
            if let target = reviewTarget {
                PendingReviewModal(
                    target: target,
                    initialPrompt: viewModel.prompt(for: target.item.pendingItem.id),
                    onEdit: { viewModel.unarm(target.item.pendingItem.id) },
                    onResubmit: { routing in
                        viewModel.rearm(
                            target.item.pendingItem.id,
                            prompt: routing.text,
                            team: routing.team,
                            worker: routing.team == nil ? routing.to : nil
                        )
                        reviewTarget = nil
                    },
                    onRemove: {
                        viewModel.remove(target.item.pendingItem.id)
                        reviewTarget = nil
                    },
                    onClose: { reviewTarget = nil }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PENDING").font(ALFont.sans(11, .bold)).tracking(1.3).foregroundStyle(ALColor.accent)
                Text("Queued work").font(ALFont.sans(20, .heavy)).foregroundStyle(ALColor.textPrimary)
            }
            if viewModel.totalPending > 0 {
                Text("\(viewModel.totalPending)")
                    .font(ALFont.mono(12, .bold)).foregroundStyle(ALColor.accent)
                    .padding(.vertical, 2).padding(.horizontal, 8)
                    .background(Capsule().fill(ALColor.accent.opacity(0.12)))
                    .overlay(Capsule().stroke(ALColor.accent.opacity(0.32), lineWidth: 1))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textMuted)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(ALColor.active))
            }
            .buttonStyle(.plain).help("Close")
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(ALColor.textFaint)
            Text("Nothing queued").font(ALFont.sans(14, .semibold)).foregroundStyle(ALColor.textMuted)
            Text("Work you arm for later shows up here, grouped by project.")
                .font(ALFont.sans(12)).foregroundStyle(ALColor.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Project group

    private func projectGroup(_ group: PendingQueueJSON.ProjectQueue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                Text(group.projectName ?? "Unassigned").font(ALFont.sans(13, .bold)).foregroundStyle(ALColor.textSecondary)
                Text("\(group.pending.count)").font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.leading, 2)

            if let running = group.running {
                queueRow(running, position: nil, running: true)
            }
            ForEach(Array(group.pending.enumerated()), id: \.element.pendingItem.id) { idx, item in
                queueRow(item, position: idx + 1, running: false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        reviewTarget = ReviewTarget(
                            item: item,
                            position: idx + 1,
                            projectName: group.projectName ?? "Unassigned"
                        )
                    }
            }
        }
    }

    private func queueRow(_ item: PendingItemJSON, position: Int?, running: Bool) -> some View {
        HStack(spacing: 11) {
            // Order marker / running dot (the only motion is amber; queued is neutral).
            Group {
                if running {
                    Circle().fill(ALPalette.blue500).frame(width: 8, height: 8)
                } else {
                    Text("#\(position ?? 0)").font(ALFont.mono(11, .semibold)).foregroundStyle(ALColor.textFaint)
                }
            }
            .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.pendingItem.promptExcerpt)
                    .font(ALFont.sans(13.5)).foregroundStyle(running ? ALColor.textSecondary : ALColor.textPrimary)
                    .lineLimit(2)
                Text(targetLabel(item.target)).font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 8)
            if running {
                Text("running").font(ALFont.mono(11)).foregroundStyle(ALPalette.blue400)
            } else {
                Button { viewModel.remove(item.pendingItem.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(ALColor.textMuted)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7).fill(ALColor.active))
                }
                .buttonStyle(.plain).help("Remove from queue")
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ALColor.borderSubtle, lineWidth: 1))
    }

    private func targetLabel(_ target: PendingItemJSON.TargetInfo) -> String {
        if let team = target.teamPresetId, !team.isEmpty { return team }
        if let worker = target.preferredModelIds.first ?? target.modelIds.first { return worker }
        return "auto"
    }
}

/// Reviewing a pending item opens the **composer in a modal** (founder: "don't build a
/// review drawer — open the composer in the panel"). Slim header naming its place in
/// line + project; the real `RoutingComposer` prefilled (taller, scrolls internally);
/// footer Remove-from-queue on the left, the composer's own send = re-submit on the
/// right. Editing un-arms (Pending→Draft); sending re-arms.
private struct PendingReviewModal: View {
    let target: PendingView.ReviewTarget
    let initialPrompt: String
    let onEdit: () -> Void
    let onResubmit: (ComposeRouting) -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                header
                Divider().overlay(ALColor.borderSubtle)
                RoutingComposer(
                    team: target.item.target.teamPresetId,
                    big: true,
                    showsProject: false,
                    initialText: initialPrompt,
                    editorMaxHeight: 360,
                    onSend: onResubmit,
                    onEdit: onEdit
                )
                .padding(16)
                footer
            }
            .frame(maxWidth: 640)
            .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ALRadius.lg).stroke(ALColor.borderDefault, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 32, y: 14)
            .padding(40)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("#\(target.position) in line").font(ALFont.mono(12, .semibold)).foregroundStyle(ALColor.textSecondary)
            Text("·").foregroundStyle(ALColor.textFaint)
            Text(target.projectName).font(ALFont.sans(12)).foregroundStyle(ALColor.textMuted)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textMuted)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(ALColor.active))
            }
            .buttonStyle(.plain).help("Close")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button(action: onRemove) {
                HStack(spacing: 5) {
                    Image(systemName: "trash").font(.system(size: 11))
                    Text("Remove from queue").font(ALFont.sans(12, .medium))
                }
                .foregroundStyle(ALColor.textMuted)
            }
            .buttonStyle(.plain).help("Remove this item from the queue")
            Spacer()
            Text("Send re-submits to the queue").font(ALFont.sans(11)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}
