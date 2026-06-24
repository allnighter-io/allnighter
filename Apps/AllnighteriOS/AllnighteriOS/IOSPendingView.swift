//
//  IOSPendingView.swift
//  AllnighteriOS
//
//  Queued work per project — mirrors Mac PendingView; projects PendingQueueJSON.
//

import AllnighterCore
import SwiftUI

struct IOSPendingView: View {
    let queue: PendingQueueJSON
    let prompt: (String) -> String
    let onRemove: (String) -> Void
    let onUnarm: (String) -> Void
    let onResubmit: (String, String, IOSComposerDraft) -> Void
    let onClose: () -> Void

    @State private var reviewTarget: ReviewTarget?

    struct ReviewTarget: Identifiable, Equatable {
        let item: PendingItemJSON
        let position: Int
        let projectName: String
        var id: String { item.pendingItem.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if queue.projects.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: IOSSpace.s8) {
                            ForEach(queue.projects, id: \.projectId) { group in
                                projectGroup(group)
                            }
                        }
                        .padding(.horizontal, IOSSpace.s5)
                        .padding(.vertical, IOSSpace.s7)
                    }
                }
            }
            .background(IOSColor.void)
            .navigationTitle("Pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if queue.totalPending > 0 {
                        Text("\(queue.totalPending)")
                            .font(IOSFont.mono)
                            .foregroundStyle(IOSColor.accentText)
                            .padding(.horizontal, IOSSpace.s3)
                            .padding(.vertical, 4)
                            .background(IOSColor.accentSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(IOSColor.accentBorder, lineWidth: 1))
                            .accessibilityIdentifier("pending-count-badge")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .foregroundStyle(IOSColor.textSecondary)
                }
            }
            .sheet(item: $reviewTarget) { target in
                IOSPendingReviewSheet(
                    target: target,
                    initialPrompt: prompt(target.item.pendingItem.id),
                    onUnarm: {
                        onUnarm(target.item.pendingItem.id)
                        reviewTarget = nil
                    },
                    onRemove: {
                        onRemove(target.item.pendingItem.id)
                        reviewTarget = nil
                    },
                    onResubmit: { text, draft in
                        onResubmit(target.item.pendingItem.id, text, draft)
                        reviewTarget = nil
                    },
                    onClose: { reviewTarget = nil }
                )
            }
            .onAppear { openPendingReviewFixtureIfNeeded() }
            .onChange(of: queue.totalPending) { _, _ in
                openPendingReviewFixtureIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("ios-pending-view")
    }

    #if DEBUG
    private func openPendingReviewFixtureIfNeeded() {
        guard IOSTestFixture.opensPendingReview, reviewTarget == nil,
              let group = queue.projects.first,
              let first = group.pending.first else { return }
        reviewTarget = ReviewTarget(
            item: first,
            position: 1,
            projectName: group.projectName ?? "Unassigned"
        )
    }
    #else
    private func openPendingReviewFixtureIfNeeded() {}
    #endif

    private var emptyState: some View {
        VStack(spacing: IOSSpace.s4) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(IOSColor.textFaint)
            Text("Nothing queued")
                .font(IOSFont.bodyStrong)
                .foregroundStyle(IOSColor.textMuted)
            Text("Work you arm for later shows up here, grouped by project.")
                .font(IOSFont.label)
                .foregroundStyle(IOSColor.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, IOSSpace.s7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectGroup(_ group: PendingQueueJSON.ProjectQueue) -> some View {
        VStack(alignment: .leading, spacing: IOSSpace.s3) {
            HStack(spacing: IOSSpace.s2) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IOSColor.textMuted)
                Text(group.projectName ?? "Unassigned")
                    .font(IOSFont.bodyStrong)
                    .foregroundStyle(IOSColor.textSecondary)
                Text("\(group.pending.count)")
                    .font(IOSFont.monoSm)
                    .foregroundStyle(IOSColor.textFaint)
            }

            if let running = group.running {
                queueRow(running, position: nil, running: true)
            }

            ForEach(Array(group.pending.enumerated()), id: \.element.pendingItem.id) { index, item in
                Button {
                    reviewTarget = ReviewTarget(
                        item: item,
                        position: index + 1,
                        projectName: group.projectName ?? "Unassigned"
                    )
                } label: {
                    queueRow(item, position: index + 1, running: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func queueRow(_ item: PendingItemJSON, position: Int?, running: Bool) -> some View {
        HStack(alignment: .top, spacing: IOSSpace.s3) {
            Group {
                if running {
                    Circle()
                        .fill(IOSColor.accent)
                        .frame(width: 8, height: 8)
                } else {
                    Text("#\(position ?? 0)")
                        .font(IOSFont.monoSm)
                        .foregroundStyle(IOSColor.textFaint)
                }
            }
            .frame(width: 28, alignment: .leading)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.pendingItem.promptExcerpt)
                    .font(IOSFont.body)
                    .foregroundStyle(running ? IOSColor.textSecondary : IOSColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(IOSPendingPresentation.targetLabel(item.target))
                    .font(IOSFont.monoSm)
                    .foregroundStyle(IOSColor.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if running {
                Text("running")
                    .font(IOSFont.monoSm)
                    .foregroundStyle(IOSColor.accentText)
            } else {
                Button {
                    onRemove(item.pendingItem.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IOSColor.textMuted)
                        .frame(width: 32, height: 32)
                        .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from queue")
            }
        }
        .padding(IOSSpace.s4)
        .background(IOSColor.raised, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
    }
}

private struct IOSPendingReviewSheet: View {
    let target: IOSPendingView.ReviewTarget
    let initialPrompt: String
    let onUnarm: () -> Void
    let onRemove: () -> Void
    let onResubmit: (String, IOSComposerDraft) -> Void
    let onClose: () -> Void

    @State private var composerText: String
    @State private var composerDraft = IOSComposerDraft()
    @State private var didUnarm = false

    init(
        target: IOSPendingView.ReviewTarget,
        initialPrompt: String,
        onUnarm: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onResubmit: @escaping (String, IOSComposerDraft) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.target = target
        self.initialPrompt = initialPrompt
        self.onUnarm = onUnarm
        self.onRemove = onRemove
        self.onResubmit = onResubmit
        self.onClose = onClose
        _composerText = State(initialValue: initialPrompt)
        var draft = IOSComposerDraft()
        if let workerId = target.item.target.preferredWorkerIds.first ?? target.item.target.workerIds.first {
            draft.selectedWorkerId = workerId
        }
        if let teamId = target.item.target.teamPresetId,
           let option = IOSComposerCatalog.teams.first(where: { $0.presetId == teamId || $0.id == teamId }) {
            draft.selectedTeamId = option.id
        }
        _composerDraft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, IOSSpace.s5)
                    .padding(.vertical, IOSSpace.s4)

                Text("Editing un-arms this item (Pending → Draft). Send re-submits it to the queue.")
                    .font(IOSFont.label)
                    .foregroundStyle(IOSColor.textFaint)
                    .padding(.horizontal, IOSSpace.s5)
                    .padding(.bottom, IOSSpace.s4)

                IOSComposerBar(
                    text: $composerText,
                    draft: $composerDraft,
                    placeholder: "Edit queued work…",
                    isSending: false,
                    canSend: !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onSend: {
                        onResubmit(composerText, composerDraft)
                    }
                )
                .padding(.horizontal, IOSSpace.s3)
                .onChange(of: composerText) { _, _ in
                    guard !didUnarm else { return }
                    didUnarm = true
                    onUnarm()
                }

                Spacer(minLength: 0)

                Button(role: .destructive, action: onRemove) {
                    Label("Remove from queue", systemImage: "trash")
                        .font(IOSFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, IOSSpace.s5)
                .padding(.vertical, IOSSpace.s5)
            }
            .background(IOSColor.void)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                }
            }
        }
        .accessibilityIdentifier("pending-review-sheet")
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("#\(target.position) in line · \(target.projectName)")
                .font(IOSFont.mono)
                .foregroundStyle(IOSColor.textMuted)
            Text(target.item.pendingItem.title)
                .font(IOSFont.bodyStrong)
                .foregroundStyle(IOSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum IOSPendingPresentation {
    static func targetLabel(_ target: PendingItemJSON.TargetInfo) -> String {
        if let team = target.teamPresetId,
           let name = IOSComposerCatalog.teams.first(where: { $0.presetId == team || $0.id == team })?.name {
            return name
        }
        if let team = target.teamPresetId, !team.isEmpty { return team }
        if let workerId = target.preferredWorkerIds.first ?? target.workerIds.first,
           let name = ModelCatalog.get(workerId)?.displayName {
            return name
        }
        if let workerId = target.preferredWorkerIds.first ?? target.workerIds.first {
            return workerId
        }
        return "Auto"
    }
}

extension PendingQueueJSON {
    static var empty: PendingQueueJSON {
        PendingQueueJSON(
            contractVersion: ContractRegistry.contractVersion,
            totalPending: 0,
            projects: []
        )
    }
}
