//
//  ContentView.swift
//  AllnighteriOS
//
//  Created by Michael Reining on 2026-06-15.
//

import SwiftUI

struct ContentView: View {
    private let snapshot: ConversationListSnapshot

    init(snapshot: ConversationListSnapshot = ContentView.defaultSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        ConversationsHomeView(snapshot: snapshot)
    }

    private static var defaultSnapshot: ConversationListSnapshot {
        #if DEBUG
        ConversationHomePreviewData.snapshot
        #else
        .empty
        #endif
    }
}

private struct ConversationsHomeView: View {
    let snapshot: ConversationListSnapshot

    @State private var searchText = ""
    @State private var selectedFilter: ConversationFilter = .all
    @State private var composerText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandBar
                    .padding(.top, IOSSpace.s2)
                    .padding(.bottom, IOSSpace.s7)

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
            IOSComposerBar(text: $composerText)
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
            if !snapshot.pinned.isEmpty {
                SectionHeader(title: "Pinned")
                    .padding(.bottom, IOSSpace.s5)

                VStack(spacing: 0) {
                    ForEach(snapshot.pinned) { conversation in
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
                ForEach(snapshot.projects) { project in
                    ProjectGroup(project: project)
                }
            }
        }
    }
}

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        ContentView()
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
                    ForEach(project.conversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .padding(.leading, 44)
                    }

                    if project.hiddenConversationCount > 0 {
                        Text("\(project.hiddenConversationCount) more")
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

    private var iconName: String {
        switch project.icon {
        case .folder: "folder"
        case .inbox: "tray"
        }
    }
}

private struct IOSComposerBar: View {
    @Binding var text: String

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

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        text = ""
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
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canSend ? IOSColor.textOnLight : IOSColor.textFaint)
                    .frame(width: 48, height: 48)
                    .background(canSend ? IOSColor.textPrimary : IOSColor.active, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
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
