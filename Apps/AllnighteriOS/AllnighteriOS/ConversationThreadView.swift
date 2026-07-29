//
//  ConversationThreadView.swift
//  AllnighteriOS
//
//  Active run / thread detail — decrypted transcript from Core.
//

import SwiftUI

struct ConversationThreadView: View {
    let threadId: String

    @Environment(RemoteAppModel.self) private var appModel
    @State private var showsStopConfirm = false
    @State private var composerText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSSpace.s7) {
                header
                statusSection
                transcriptSection
                stopSection
            }
            .padding(.horizontal, IOSSpace.s5)
            .padding(.vertical, IOSSpace.s8)
        }
        .background(IOSColor.void)
        .scrollContentBackground(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .iosComposerSafeAreaInset {
            IOSComposerBar(
                text: $composerText,
                draft: Binding(
                    get: { appModel.composerDraft },
                    set: { appModel.composerDraft = $0 }
                ),
                placeholder: "Continue this conversation…",
                continuationAgentTitle: appModel.composerContinuationAgent?.title,
                continuationDriverId: appModel.composerContinuationAgent?.driverId,
                continuationModelId: appModel.composerContinuationAgent?.modelId,
                isSending: appModel.workRequestSendPhase == .sending,
                canSend: appModel.canSendWorkRequests
                    && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: {
                    let prompt = composerText
                    composerText = ""
                    await appModel.sendWorkRequest(prompt: prompt)
                }
            )
        }
        .task(id: threadId) {
            appModel.composerThreadId = threadId
            await appModel.loadThread(threadId: threadId)
            appModel.setThreadPolling(threadId: threadId, enabled: true)
        }
        .onDisappear {
            appModel.setThreadPolling(threadId: nil, enabled: false)
            if appModel.composerThreadId == threadId {
                appModel.composerThreadId = nil
            }
        }
        .refreshable {
            await appModel.loadThread(threadId: threadId)
        }
        .confirmationDialog(
            "Stop this run?",
            isPresented: $showsStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop Run", role: .destructive) {
                Task { await appModel.stopActiveRun() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends a typed stop command to your Mac.")
        }
    }

    @ViewBuilder
    private var header: some View {
        switch appModel.threadLoadStatus {
        case .idle, .loading:
            ProgressView()
                .tint(IOSColor.accent)
        case .loaded, .failed, .cached:
            if let snapshot = appModel.threadSnapshot, snapshot.id == threadId {
                Text(snapshot.title)
                    .font(IOSFont.title)
                    .foregroundStyle(IOSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("thread-detail-title")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if case let .failed(_, failure) = appModel.threadLoadStatus {
            IOSStatusBanner(text: failureMessage(failure), tone: .warning)
        } else if case let .cached(_, serverTime, _) = appModel.threadLoadStatus {
            IOSStatusBanner(text: ConversationRelativeTime.lastSeen(serverTime: serverTime), tone: .neutral)
        } else if case let .failed(message) = appModel.stopRunPhase {
            IOSStatusBanner(text: message, tone: .warning)
                .onTapGesture { appModel.clearStopRunStatus() }
        } else if case .succeeded = appModel.stopRunPhase {
            IOSStatusBanner(text: "Run stopped on your Mac.", tone: .positive)
                .onTapGesture { appModel.clearStopRunStatus() }
        } else if case let .failed(message) = appModel.workRequestSendPhase {
            IOSStatusBanner(text: message, tone: .warning)
                .onTapGesture { appModel.clearWorkRequestSendFailure() }
        }

        if let snapshot = appModel.threadSnapshot, snapshot.id == threadId {
            if let statusLabel = snapshot.statusLabel {
                HStack(spacing: IOSSpace.s3) {
                    Circle()
                        .fill(snapshot.isActive ? IOSColor.accent : IOSColor.textMuted)
                        .frame(width: 10, height: 10)
                    Text(statusLabel)
                        .font(IOSFont.label)
                        .foregroundStyle(snapshot.isActive ? IOSColor.accentText : IOSColor.textSecondary)
                }
                .accessibilityIdentifier("thread-detail-status")
            }

            if let latest = snapshot.latestOutput {
                VStack(alignment: .leading, spacing: IOSSpace.s3) {
                    Text("LATEST OUTPUT")
                        .font(IOSFont.section)
                        .tracking(2)
                        .foregroundStyle(IOSColor.textFaint)

                    Text(latest)
                        .font(IOSFont.body)
                        .foregroundStyle(IOSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("thread-detail-latest-output")
                }
                .padding(IOSSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IOSColor.surface, in: RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous)
                        .strokeBorder(IOSColor.borderDefault, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        if let snapshot = appModel.threadSnapshot, snapshot.id == threadId, !snapshot.turns.isEmpty {
            Text("TRANSCRIPT")
                .font(IOSFont.section)
                .tracking(2)
                .foregroundStyle(IOSColor.textFaint)

            VStack(spacing: IOSSpace.s4) {
                ForEach(snapshot.turns) { turn in
                    ThreadTurnRow(turn: turn)
                }
            }
            .accessibilityIdentifier("thread-detail-transcript")
        }
    }

    @ViewBuilder
    private var stopSection: some View {
        if let snapshot = appModel.threadSnapshot,
           snapshot.id == threadId,
           snapshot.activeRunId != nil {
            let isStopping: Bool = {
                if case .stopping = appModel.stopRunPhase { return true }
                return false
            }()

            Button {
                showsStopConfirm = true
            } label: {
                HStack(spacing: IOSSpace.s3) {
                    if isStopping {
                        ProgressView()
                            .tint(IOSColor.textPrimary)
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("Stop Run")
                        .font(IOSFont.bodyStrong)
                }
                .foregroundStyle(IOSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(IOSColor.raised, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.42), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!appModel.canStopActiveRun || isStopping)
            .accessibilityIdentifier("thread-stop-run-button")
        }
    }

    private func failureMessage(_ failure: ConversationThreadLoadFailure) -> String {
        switch failure {
        case .unavailable:
            "Could not load this conversation from your Mac."
        case let .threadMismatch(expected, actual):
            "Thread mismatch (\(expected) vs \(actual))."
        case .sealedDetailEnvelopeMismatch:
            "Could not decrypt this conversation on this device."
        }
    }
}

private struct ThreadTurnRow: View {
    let turn: ConversationThreadTurn

    var body: some View {
        switch turn.role {
        case .user:
            userBubble
        case .assistant:
            workerBubble
        case .system:
            systemBubble
        }
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: IOSSpace.s3) {
            Text("YOU")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(IOSColor.textFaint)
                .frame(width: 28, height: 28)
                .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: IOSSpace.s2) {
                Text("You")
                    .font(IOSFont.bodyStrong)
                    .foregroundStyle(IOSColor.textSecondary)

                if let text = turn.text {
                    Text(text)
                        .font(IOSFont.body)
                        .foregroundStyle(IOSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(IOSSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.surface, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
    }

    private var workerBubble: some View {
        HStack(alignment: .top, spacing: IOSSpace.s3) {
            IOSDriverBrandGlyphView(
                driverId: turn.driverId ?? ConversationAgentPresentation.driverId(for: turn.modelId),
                boxSize: 28,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: IOSSpace.s2) {
                HStack(spacing: IOSSpace.s2) {
                    Text(turn.agentTitle ?? ConversationAgentPresentation.agentTitle(for: turn.modelId))
                        .font(IOSFont.bodyStrong)
                        .foregroundStyle(IOSColor.textSecondary)

                    if turn.isPending {
                        Text("live")
                            .font(IOSFont.monoSm)
                            .foregroundStyle(IOSColor.accentText)
                    } else if turn.isFailed {
                        Text("failed")
                            .font(IOSFont.monoSm)
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                }

                if turn.isPending, turn.text == nil || turn.text?.isEmpty == true {
                    HStack(spacing: IOSSpace.s2) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(IOSColor.textMuted)
                        Text("running…")
                            .font(IOSFont.label)
                            .foregroundStyle(IOSColor.textMuted)
                    }
                } else if let text = turn.text {
                    Text(text)
                        .font(IOSFont.body)
                        .foregroundStyle(IOSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if turn.isTruncated {
                    Text("Output truncated on your Mac")
                        .font(IOSFont.label)
                        .foregroundStyle(IOSColor.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(IOSSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.surface, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
    }

    private var systemBubble: some View {
        VStack(alignment: .leading, spacing: IOSSpace.s2) {
            Text("SYSTEM")
                .font(IOSFont.monoSm)
                .foregroundStyle(IOSColor.textFaint)

            if let text = turn.text {
                Text(text)
                    .font(IOSFont.body)
                    .foregroundStyle(IOSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(IOSSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.surface, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
    }
}
