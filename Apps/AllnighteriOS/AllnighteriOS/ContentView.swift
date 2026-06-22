//
//  ContentView.swift
//  AllnighteriOS
//
//  Created by Michael Reining on 2026-06-15.
//

import SwiftUI

struct ContentView: View {
    @Environment(RemoteAppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.showsHome {
                ConversationsHomeView(
                    snapshot: appModel.homeSnapshot,
                    connectionPhase: appModel.connectionPhase,
                    homeStatus: appModel.homeStatus,
                    workRequestSendPhase: appModel.workRequestSendPhase,
                    killSwitchPhase: appModel.killSwitchPhase,
                    activeWorkCount: appModel.activeWorkCount,
                    canSendWorkRequests: appModel.canSendWorkRequests,
                    canStopAllWork: appModel.canStopAllWork,
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
    let connectionPhase: RemoteAppConnectionPhase
    let homeStatus: ConversationHomeLoadStatus
    let workRequestSendPhase: WorkRequestSendPhase
    let killSwitchPhase: KillSwitchPhase
    let activeWorkCount: Int
    let canSendWorkRequests: Bool
    let canStopAllWork: Bool
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
                    StatusBanner(text: message, tone: .positive)
                        .padding(.bottom, IOSSpace.s5)
                        .onTapGesture(perform: onDismissKillSwitchStatus)
                } else if case let .failed(message) = killSwitchPhase {
                    StatusBanner(text: message, tone: .warning)
                        .padding(.bottom, IOSSpace.s5)
                        .onTapGesture(perform: onDismissKillSwitchStatus)
                }

                if case let .failed(message) = workRequestSendPhase {
                    StatusBanner(text: message, tone: .warning)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOSComposerBar(
                text: $composerText,
                isSending: workRequestSendPhase == .sending,
                canSend: canSendWorkRequests && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: {
                    let prompt = composerText
                    composerText = ""
                    await onSendWorkRequest(prompt)
                }
            )
                .padding(.horizontal, IOSSpace.s3)
                .padding(.top, IOSSpace.s3)
                .padding(.bottom, IOSSpace.s2)
                .background {
                    VStack(spacing: 0) {
                        IOSColor.borderSubtle.frame(height: 1)
                        IOSColor.void
                    }
                    .ignoresSafeArea()
                }
        }
        .preferredColorScheme(.dark)
    }

    private var connectionBanner: some View {
        Group {
            switch connectionPhase {
            case .idle, .connecting:
                StatusBanner(text: "Connecting to your Mac…", tone: .neutral)
            case .preview:
                StatusBanner(text: "Preview data — configure Supabase to connect live.", tone: .neutral)
            case let .connected(macName):
                StatusBanner(text: "Connected to \(macName)", tone: .positive)
            case let .awaitingPairingApproval(macName):
                StatusBanner(text: "Approve this iPhone on \(macName)", tone: .warning)
            case .needsConfiguration:
                StatusBanner(text: "Sign in to connect to your Mac.", tone: .warning)
            case .noMacsOnAccount:
                StatusBanner(text: "No Mac registered on this account yet.", tone: .warning)
            case let .failed(message):
                StatusBanner(text: message, tone: .warning)
            }
        }
        .padding(.bottom, IOSSpace.s5)
    }

    private var visibleSnapshot: ConversationListSnapshot {
        switch selectedFilter {
        case .all:
            snapshot
        case .unread, .pending:
            snapshot.filtering(selectedFilter.includes)
        }
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

            Button {
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

    private var conversationSections: some View {
        VStack(alignment: .leading, spacing: 0) {
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

private struct StatusBanner: View {
    enum Tone {
        case neutral
        case positive
        case warning
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(IOSFont.label)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, IOSSpace.s4)
            .padding(.vertical, IOSSpace.s3)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .accessibilityIdentifier("connection-status-banner")
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral: IOSColor.textSecondary
        case .positive: IOSColor.accentText
        case .warning: IOSColor.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral: IOSColor.surface
        case .positive: IOSColor.accentSurface
        case .warning: IOSColor.raised
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral: IOSColor.borderDefault
        case .positive: IOSColor.accentBorder
        case .warning: IOSColor.borderStrong
        }
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
            return conversation.isPending
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
        HStack(alignment: .firstTextBaseline, spacing: IOSSpace.s3) {
            Text(conversation.title)
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(conversation.relativeAge)
                .font(IOSFont.mono)
                .foregroundStyle(IOSColor.textFaint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, IOSSpace.s4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectGroup: View {
    let project: ConversationProject
    private let visibleConversationLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: IOSSpace.s3) {
                Image(systemName: project.isExpanded ? "chevron.down" : "chevron.right")
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

            if project.isExpanded {
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

private struct IOSComposerBar: View {
    @Binding var text: String
    var isSending: Bool = false
    var canSend: Bool = false
    var onSend: () async -> Void = {}

    private let placeholder = "Start something - ask, order, or build..."

    var body: some View {
        VStack(spacing: IOSSpace.s3) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(IOSFont.body)
                        .foregroundStyle(IOSColor.textFaint)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("composer-placeholder")
                }

                TextEditor(text: $text)
                    .font(IOSFont.body)
                    .foregroundStyle(IOSColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 44, maxHeight: 92)
                    .accessibilityLabel("Work request")
                    .accessibilityIdentifier("work-request-editor")
            }

            ViewThatFits(in: .horizontal) {
                composerControls(showModelDetail: true, showEffort: true)
                composerControls(showModelDetail: false, showEffort: true)
                composerControls(showModelDetail: false, showEffort: false)
            }
        }
        .padding(IOSSpace.s4)
        .background(IOSColor.raised, in: RoundedRectangle(cornerRadius: IOSRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.xl, style: .continuous)
                .strokeBorder(IOSColor.borderDefault, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.46), radius: 24, x: 0, y: 14)
        .accessibilityIdentifier("ios-composer-bar")
    }

    private var sendEnabled: Bool {
        canSend && !isSending
    }

    private func send() {
        guard sendEnabled else { return }
        Task {
            await onSend()
        }
    }

    private func composerControls(showModelDetail: Bool, showEffort: Bool) -> some View {
        HStack(spacing: IOSSpace.s3) {
            ComposerIconButton(systemImage: "paperclip", accessibilityLabel: "Attach context") {
            }

            RouteChip(systemImage: "infinity", title: "Auto", detail: showModelDetail ? "Claude" : nil)

            if showEffort {
                RouteChip(systemImage: "speedometer", title: "Med", detail: nil)
            }

            Spacer(minLength: IOSSpace.s2)

            Button(action: send) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(IOSColor.textOnLight)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(sendEnabled ? IOSColor.textOnLight : IOSColor.textFaint)
                .frame(width: 48, height: 48)
                .background(sendEnabled ? IOSColor.textPrimary : IOSColor.active, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!sendEnabled)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("composer-send-button")
        }
    }
}

private struct ComposerIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(IOSColor.textSecondary)
                .frame(width: 48, height: 48)
                .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                        .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RouteChip: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IOSColor.textMuted)

            Text(title)
                .font(IOSFont.mono)
                .foregroundStyle(IOSColor.textSecondary)
                .lineLimit(1)

            if let detail {
                Text("·")
                    .font(IOSFont.monoSm)
                    .foregroundStyle(IOSColor.textFaint)

                Text(detail)
                    .font(IOSFont.mono)
                    .foregroundStyle(IOSColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, IOSSpace.s3)
        .frame(height: 48)
        .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
