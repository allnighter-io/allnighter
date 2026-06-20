import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Settings-less **Pending** screen — committed work per project, shown as a line.
/// Each project group is headed by its running item, with armed pending chained
/// beneath. Pure projection of `PendingQueueJSON`; actions go through the view-model
/// (→ `PendingService`). Color is earned: amber only on the count + the running dot.
struct PendingView: View {
    @State private var viewModel: PendingViewModel
    var onClose: () -> Void

    init(service: PendingService, onClose: @escaping () -> Void) {
        _viewModel = State(initialValue: PendingViewModel(service: service))
        self.onClose = onClose
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
        if let worker = target.preferredWorkerIds.first ?? target.workerIds.first { return worker }
        return "auto"
    }
}
