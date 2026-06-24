//
//  ContentView.swift
//  AllnighteriOS
//
//  Created by Michael Reining on 2026-06-15.
//

import SwiftUI

struct ContentView: View {
    @Environment(RemoteAppModel.self) private var appModel
    @State private var navigationPath = NavigationPath()
    @State private var showsPendingQueue = false

    var body: some View {
        Group {
            if appModel.showsHome {
                NavigationStack(path: $navigationPath) {
                    ConversationsHomeView(
                        snapshot: appModel.homeSnapshot,
                        connectionStatusText: appModel.connectionStatusText,
                        connectionStatusTone: appModel.connectionStatusTone,
                        homeFreshnessLabel: appModel.homeFreshnessLabel,
                        homeStatus: appModel.homeStatus,
                        workRequestSendPhase: appModel.workRequestSendPhase,
                        killSwitchPhase: appModel.killSwitchPhase,
                        activeWorkCount: appModel.activeWorkCount,
                        pendingDecisionCount: appModel.pendingDecisionCount,
                        armedPendingCount: appModel.armedPendingCount,
                        canSendWorkRequests: appModel.canSendWorkRequests,
                        canStopAllWork: appModel.canStopAllWork,
                        composerDraft: Binding(
                            get: { appModel.composerDraft },
                            set: { appModel.composerDraft = $0 }
                        ),
                        onBeginNewConversation: {
                            appModel.beginNewConversation()
                        },
                        onOpenPendingQueue: {
                            showsPendingQueue = true
                        },
                        onSendWorkRequest: { prompt in
                            await appModel.sendWorkRequest(prompt: prompt)
                        },
                        onDismissSendFailure: {
                            appModel.clearWorkRequestSendFailure()
                        },
                        onStopAllWork: {
                            await appModel.stopAllWork()
                        },
                        onDismissKillSwitchStatus: {
                            appModel.clearKillSwitchStatus()
                        }
                    )
                    .navigationDestination(for: String.self) { threadId in
                        ConversationThreadView(threadId: threadId)
                    }
                }
                .onChange(of: appModel.pendingOpenThreadId) { _, threadId in
                    guard let threadId else { return }
                    navigationPath.append(threadId)
                    appModel.consumePendingOpenThread()
                }
                .sheet(isPresented: $showsPendingQueue) {
                    IOSPendingView(
                        queue: appModel.pendingQueue,
                        prompt: { appModel.pendingPrompt(for: $0) },
                        onRemove: { appModel.removePendingItem(id: $0) },
                        onUnarm: { appModel.unarmPendingItem(id: $0) },
                        onResubmit: { id, prompt, draft in
                            appModel.rearmPendingItem(id: id, prompt: prompt, draft: draft)
                        },
                        onClose: { showsPendingQueue = false }
                    )
                }
                .onAppear {
                    #if DEBUG
                    if IOSTestFixture.opensPendingQueue {
                        showsPendingQueue = true
                    }
                    #endif
                }
            } else {
                RemoteOnboardingView(phase: appModel.connectionPhase) {
                    await appModel.activate()
                }
            }
        }
        .refreshable {
            await appModel.refreshHome()
        }
    }
}

private struct ConversationsHomeView: View {
    let snapshot: ConversationListSnapshot
    let connectionStatusText: String
    let connectionStatusTone: IOSStatusBanner.Tone
    let homeFreshnessLabel: String?
    let homeStatus: ConversationHomeLoadStatus
    let workRequestSendPhase: WorkRequestSendPhase
    let killSwitchPhase: KillSwitchPhase
    let activeWorkCount: Int
    let pendingDecisionCount: Int
    let armedPendingCount: Int
    let canSendWorkRequests: Bool
    let canStopAllWork: Bool
    @Binding var composerDraft: IOSComposerDraft
    let onBeginNewConversation: () -> Void
    let onOpenPendingQueue: () -> Void
    let onSendWorkRequest: (String) async -> Void
    let onDismissSendFailure: () -> Void
    let onStopAllWork: () async -> Void
    let onDismissKillSwitchStatus: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: ConversationFilter = .all
    @State private var composerText = ""
    @State private var showsKillSwitchConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandBar
                    .padding(.top, IOSSpace.s2)
                    .padding(.bottom, IOSSpace.s7)

                connectionBanner

                if armedPendingCount > 0 {
                    Button(action: onOpenPendingQueue) {
                        IOSStatusBanner(
                            text: armedPendingCount == 1
                                ? "1 item armed in your queue"
                                : "\(armedPendingCount) items armed in your queue",
                            tone: .warning
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, IOSSpace.s5)
                    .accessibilityIdentifier("home-armed-pending-banner")
                }

                if let homeFreshnessLabel {
                    IOSStatusBanner(text: homeFreshnessLabel, tone: .neutral)
                        .padding(.bottom, IOSSpace.s5)
                        .accessibilityIdentifier("home-freshness-banner")
                }

                if pendingDecisionCount > 0 {
                    IOSStatusBanner(
                        text: pendingDecisionLabel,
                        tone: .warning
                    )
                    .padding(.bottom, IOSSpace.s5)
                    .accessibilityIdentifier("home-pending-decisions-banner")
                }

                KillSwitchBar(
                    activeWorkCount: activeWorkCount,
                    phase: killSwitchPhase,
                    isEnabled: canStopAllWork,
                    onTap: { showsKillSwitchConfirm = true }
                )
                .padding(.bottom, IOSSpace.s5)
                .confirmationDialog(
                    "Stop all work on your Mac?",
                    isPresented: $showsKillSwitchConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Stop All Work", role: .destructive) {
                        Task { await onStopAllWork() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if activeWorkCount > 0 {
                        Text("This stops \(activeWorkCount) active run\(activeWorkCount == 1 ? "" : "s") on your Mac.")
                    } else {
                        Text("This sends a stop-all command to your Mac.")
                    }
                }

                if case let .succeeded(message) = killSwitchPhase {
                    IOSStatusBanner(text: message, tone: .positive)
                        .padding(.bottom, IOSSpace.s5)
                        .onTapGesture(perform: onDismissKillSwitchStatus)
                } else if case let .failed(message) = killSwitchPhase {
                    IOSStatusBanner(text: message, tone: .warning)
                        .padding(.bottom, IOSSpace.s5)
                        .onTapGesture(perform: onDismissKillSwitchStatus)
                }

                if case let .failed(message) = workRequestSendPhase {
                    IOSStatusBanner(text: message, tone: .warning)
                        .padding(.bottom, IOSSpace.s5)
                        .onTapGesture(perform: onDismissSendFailure)
                }

                Text("Conversations")
                    .font(IOSFont.display)
                    .foregroundStyle(IOSColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("conversations-title")

                searchField
                    .padding(.top, IOSSpace.s8)

                filterRow
                    .padding(.top, IOSSpace.s5)

                conversationSections
                    .padding(.top, IOSSpace.s7)
            }
            .padding(.horizontal, IOSSpace.s5)
            .padding(.bottom, 28)
        }
        .background(IOSColor.void)
        .scrollContentBackground(.hidden)
        .iosComposerSafeAreaInset {
            IOSComposerBar(
                text: $composerText,
                draft: $composerDraft,
                isSending: workRequestSendPhase == .sending,
                canSend: canSendWorkRequests && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: {
                    let prompt = composerText
                    composerText = ""
                    await onSendWorkRequest(prompt)
                }
            )
        }
        .preferredColorScheme(.dark)
    }

    private var connectionBanner: some View {
        IOSStatusBanner(text: connectionStatusText, tone: connectionStatusTone)
            .padding(.bottom, IOSSpace.s5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(connectionStatusText)
            .accessibilityIdentifier("connection-status-banner")
    }

    private var pendingDecisionLabel: String {
        if pendingDecisionCount == 1 {
            "1 conversation needs your decision"
        } else {
            "\(pendingDecisionCount) conversations need your decision"
        }
    }

    private var visibleSnapshot: ConversationListSnapshot {
        let filtered: ConversationListSnapshot = switch selectedFilter {
        case .all:
            snapshot
        case .unread, .pending:
            snapshot.filtering(selectedFilter.includes)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filtered }
        return filtered.filtering { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var brandBar: some View {
        HStack(spacing: IOSSpace.s3) {
            HStack(spacing: IOSSpace.s3) {
                BrandGlyph()

                Text("Allnighter")
                    .font(IOSFont.title)
                    .foregroundStyle(IOSColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: IOSSpace.s4)

            if armedPendingCount > 0 {
                Button(action: onOpenPendingQueue) {
                    HStack(spacing: 6) {
                        Text("\(armedPendingCount)")
                            .font(IOSFont.monoSm)
                            .foregroundStyle(IOSColor.accentText)
                        Text("Pending")
                            .font(IOSFont.label)
                            .foregroundStyle(IOSColor.textSecondary)
                    }
                    .padding(.horizontal, IOSSpace.s4)
                    .frame(height: 48)
                    .background(IOSColor.accentSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(IOSColor.accentBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-pending-pill")
            }

            Button {
                composerText = ""
                onBeginNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(IOSColor.textSecondary)
                    .frame(width: 58, height: 58)
                    .background(IOSColor.surface, in: Circle())
                    .overlay {
                        Circle().strokeBorder(IOSColor.borderDefault, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New conversation")
        }
    }

    private var searchField: some View {
        HStack(spacing: IOSSpace.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(IOSColor.textMuted)

            TextField("Search conversations", text: $searchText)
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("conversation-search-field")
        }
        .padding(.horizontal, IOSSpace.s5)
        .frame(height: 68)
        .background(IOSColor.surface, in: RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous)
                .strokeBorder(IOSColor.borderDefault, lineWidth: 1)
        }
    }

    private var filterRow: some View {
        HStack(spacing: IOSSpace.s3) {
            ForEach(ConversationFilter.allCases) { filter in
                FilterPill(
                    title: filter.title,
                    isSelected: selectedFilter == filter
                ) {
                    selectedFilter = filter
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var activeConversations: [ConversationSummary] {
        let all = visibleSnapshot.pinned + visibleSnapshot.projects.flatMap(\.conversations)
        return all.filter(\.isPending)
    }

    private var conversationSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !activeConversations.isEmpty {
                SectionHeader(title: "Active on your Mac")
                    .padding(.bottom, IOSSpace.s5)

                VStack(spacing: 0) {
                    ForEach(activeConversations) { conversation in
                        ConversationRow(conversation: conversation)
                    }
                }
                .padding(.bottom, IOSSpace.s8)
            }

            if !visibleSnapshot.pinned.isEmpty {
                SectionHeader(title: "Pinned")
                    .padding(.bottom, IOSSpace.s5)

                VStack(spacing: 0) {
                    ForEach(visibleSnapshot.pinned) { conversation in
                        ConversationRow(conversation: conversation)
                    }
                }
                .padding(.bottom, IOSSpace.s8)
            }

            HStack {
                SectionHeader(title: "Projects")

                Spacer()

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(IOSColor.textMuted)
                    .accessibilityLabel("Add project")
            }
            .padding(.bottom, IOSSpace.s4)

            VStack(spacing: IOSSpace.s2) {
                ForEach(visibleSnapshot.projects) { project in
                    ProjectGroup(project: project)
                }
            }
        }
    }
}

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(RemoteAppModel())
    }
}

private struct KillSwitchBar: View {
    let activeWorkCount: Int
    let phase: KillSwitchPhase
    let isEnabled: Bool
    let onTap: () -> Void

    private var title: String {
        if activeWorkCount > 0 {
            "Stop \(activeWorkCount) Active Run\(activeWorkCount == 1 ? "" : "s")"
        } else {
            "Stop All Work"
        }
    }

    private var isStopping: Bool {
        if case .stopping = phase { return true }
        return false
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: IOSSpace.s3) {
                Group {
                    if isStopping {
                        ProgressView()
                            .tint(IOSColor.textPrimary)
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(IOSFont.bodyStrong)
                        .foregroundStyle(IOSColor.textPrimary)
                    Text("Kill switch — stops every run on your Mac")
                        .font(IOSFont.label)
                        .foregroundStyle(IOSColor.textMuted)
                }

                Spacer(minLength: IOSSpace.s2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IOSColor.textFaint)
            }
            .padding(.horizontal, IOSSpace.s4)
            .padding(.vertical, IOSSpace.s4)
            .background(IOSColor.raised, in: RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.42), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isStopping)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityIdentifier("kill-switch-bar")
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to confirm stopping all work on your Mac")
    }
}

private enum ConversationFilter: CaseIterable, Identifiable {
    case all
    case unread
    case pending

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .pending: "Pending"
        }
    }

    func includes(_ conversation: ConversationSummary) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return conversation.isUnread
        case .pending:
            return conversation.isPending || conversation.needsAttention
        }
    }
}

private struct BrandGlyph: View {
    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(IOSColor.accentText)
            .frame(width: 38, height: 38)
            .background(IOSColor.accentSurface, in: RoundedRectangle(cornerRadius: IOSRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IOSRadius.sm, style: .continuous)
                    .strokeBorder(IOSColor.accentBorder, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(IOSFont.section)
            .tracking(3)
            .foregroundStyle(IOSColor.textFaint)
            .accessibilityLabel(title)
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(IOSFont.label)
                .foregroundStyle(isSelected ? IOSColor.textPrimary : IOSColor.textMuted)
                .padding(.horizontal, IOSSpace.s5)
                .frame(height: 54)
                .background(isSelected ? IOSColor.active : IOSColor.void, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? IOSColor.borderStrong : IOSColor.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-filter-\(title.lowercased())")
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        NavigationLink(value: conversation.id) {
            HStack(alignment: .firstTextBaseline, spacing: IOSSpace.s3) {
                if conversation.isUnread || conversation.needsAttention {
                    Circle()
                        .fill(IOSColor.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                        .accessibilityLabel(conversation.needsAttention ? "Needs your decision" : "Unread")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(IOSFont.body)
                        .foregroundStyle(IOSColor.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let statusLabel = conversation.statusLabel {
                        Text(statusLabel)
                            .font(IOSFont.monoSm)
                            .foregroundStyle(conversation.isPending || conversation.needsAttention ? IOSColor.accentText : IOSColor.textMuted)
                    }
                }

                Text(conversation.relativeAge)
                    .font(IOSFont.mono)
                    .foregroundStyle(IOSColor.textFaint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, IOSSpace.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-row-\(conversation.id)")
    }
}

private struct ProjectGroup: View {
    let project: ConversationProject
    private let visibleConversationLimit = 4

    @State private var isExpanded: Bool

    init(project: ConversationProject) {
        self.project = project
        _isExpanded = State(initialValue: project.isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: IOSSpace.s3) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(IOSColor.textMuted)
                        .frame(width: 24)

                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(IOSColor.textMuted)
                        .frame(width: 30)

                    Text(project.name)
                        .font(IOSFont.bodyStrong)
                        .foregroundStyle(IOSColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if project.hasUnread {
                        Circle()
                            .fill(IOSColor.accent)
                            .frame(width: 13, height: 13)
                            .accessibilityLabel("Unread")
                    }

                    Spacer(minLength: IOSSpace.s3)

                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(IOSColor.textMuted)
                        .frame(width: 32, height: 32)
                        .accessibilityLabel("New work request")
                }
                .padding(.vertical, IOSSpace.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project-group-\(project.id)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleConversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .padding(.leading, 44)
                    }

                    if hiddenConversationCount > 0 {
                        Text("\(hiddenConversationCount) more")
                            .font(IOSFont.label)
                            .foregroundStyle(IOSColor.accentText)
                            .padding(.leading, 44)
                            .padding(.top, IOSSpace.s3)
                            .padding(.bottom, IOSSpace.s2)
                    }
                }
            }
        }
    }

    private var visibleConversations: [ConversationSummary] {
        Array(project.conversations.prefix(visibleConversationLimit))
    }

    private var hiddenConversationCount: Int {
        max(0, project.conversations.count - visibleConversations.count)
    }

    private var iconName: String {
        switch project.icon {
        case .folder: "folder"
        case .inbox: "tray"
        }
    }
}
