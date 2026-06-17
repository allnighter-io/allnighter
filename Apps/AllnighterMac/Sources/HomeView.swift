import SwiftUI
import AllnighterCore

// The clean conversation-workspace home (docs/phases/wiring compose-routing).
// CR4a: real thread rail + send creates/opens conversations; marketing empty
// state stays for a cold bench with no work orders yet.

struct HomeView: View {
    @Environment(ThreadsViewModel.self) private var threads

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar()
                .frame(width: 300)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        if threads.selectedThread != nil {
            ThreadView()
        } else if threads.threads.isEmpty {
            HomeMarketingEmptyState()
        } else {
            HomeNewWorkOrderPane()
        }
    }
}

// MARK: - Left rail

private struct HomeSidebar: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(CommandCenter.self) private var commands
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var filter: ThreadsPresenter.RailFilter = .all

    private var railGroups: [ThreadsPresenter.RailGroup] {
        ThreadsPresenter.railGroups(threads.threads, filter: filter, search: search)
    }

    private func label(for filter: ThreadsPresenter.RailFilter) -> String {
        switch filter {
        case .all: return "All"
        case .design: return "Design"
        case .build: return "Build"
        case .running: return "Running"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                Button { threads.newWorkOrder() } label: {
                    Label("New work order", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.alLight)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                    TextField("Search conversations", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ALColor.textPrimary)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }

                HStack(spacing: 7) {
                    ForEach(ThreadsPresenter.RailFilter.allCases, id: \.self) { key in
                        Button { filter = key } label: {
                            Text(label(for: key)).font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(filter == key ? ALColor.textPrimary : ALColor.textMuted)
                                .padding(.horizontal, 11).frame(height: 26)
                                .background(filter == key ? ALColor.active : ALColor.subtle, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)

            if railGroups.isEmpty {
                Spacer(minLength: 0)
                if threads.threads.contains(where: { !$0.isArchived }) {
                    noMatchHint
                } else {
                    emptyHint
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        ForEach(railGroups) { group in
                            Section {
                                ForEach(group.threads) { thread in
                                    ConversationRow(
                                        thread: thread,
                                        selected: thread.id == threads.selectedThreadId
                                    ) {
                                        threads.select(thread)
                                    }
                                }
                            } header: {
                                railSectionHeader(group.title)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 12)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
        .onChange(of: commands.focusSearchTick) { _, _ in searchFocused = true }
    }

    private func railSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.top, 10).padding(.bottom, 4)
            .background(ALColor.subtle)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            AllnighterGlyph(size: 26)
            Text("No conversations yet")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
            Text("Your work orders will live here — newest on top.")
                .font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
                .multilineTextAlignment(.center).frame(maxWidth: 210).lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    private var noMatchHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 24)).foregroundStyle(ALColor.textFaint)
            Text("No matches")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
            Text(search.isEmpty ? "No \(label(for: filter).lowercased()) conversations." : "Nothing matches “\(search)”.")
                .font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
                .multilineTextAlignment(.center).frame(maxWidth: 210).lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }
}

private struct ConversationRow: View {
    @Environment(AppModel.self) private var appModel
    let thread: WorkThread
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                rowGlyph
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ALColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let status = ThreadsPresenter.conversationStatus(for: thread) {
                            ConversationStatusPill(status: status)
                        }
                        Text(thread.updatedAt, format: .relative(presentation: .numeric))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ALColor.textFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rowGlyph: some View {
        let workerId = thread.lastWorkerId ?? thread.defaultWorkerId
        if let workerId, let model = appModel.models.first(where: { $0.id == workerId }) {
            DriverBrandGlyph(driverId: model.driverId, boxSize: 28, iconSize: 14, cornerRadius: 7)
        } else {
            AllnighterGlyph(size: 15)
                .frame(width: 28, height: 28)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct ConversationStatusPill: View {
    let status: ThreadsPresenter.ConversationStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(labelColor)
        }
    }

    private var dotColor: Color {
        switch status {
        case .running: ALPalette.blue400
        case .exit0: ALPalette.green400
        case .exit1: ALPalette.red400
        default: ALColor.textFaint
        }
    }

    private var labelColor: Color {
        switch status {
        case .running: ALPalette.blue400
        case .boardReady, .specReady: ALColor.accentText
        case .exit0: ALPalette.green400
        case .exit1: ALPalette.red400
        default: ALColor.textMuted
        }
    }
}

// MARK: - Marketing empty state ("You already pay for the team")

private struct HomeMarketingEmptyState: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    private var bench: [ComposeBenchModel] { appModel.composeBench }
    private let modes: [(ComposeMode, String)] = [
        (.chat, "Ask the bench a question — “token bucket or sliding window for rate limiting?”"),
        (.fanout, "Drop a screenshot — “make this profile feel premium and clean” → a board of options."),
        (.exec, "Point an agent at your repo — “add the 429 + Retry-After path to the limiter.”"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AllnighterGlyph(size: 40)
                    .padding(.top, 40)
                Text("You already pay for the team.")
                    .font(.system(size: 26, weight: .heavy)).tracking(-0.4)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Allnighter puts the AI tools you already subscribe to on one bench. Ask one, ask them all, or hand the work to an agent — and route any turn to anyone.")
                    .font(.system(size: 13.5)).foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 600)

                benchChips
                modeCards
                RoutingComposer(
                    big: true,
                    onSend: { threads.sendRouting($0, createThread: true) }
                )
                .padding(.top, 4)
                hint
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.bottom, 40)
        }
        .background(ALColor.base)
    }

    private var benchChips: some View {
        let rows = [Array(bench.prefix(3)), Array(bench.suffix(from: min(3, bench.count)))]
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { m in benchChip(m) }
                }
            }
        }
        .padding(.top, 6)
    }

    private func benchChip(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 8) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5)
            Text(m.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text(m.cli).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            Circle().fill(m.ready ? ALPalette.green500 : ALColor.textFaint).frame(width: 6, height: 6)
        }
        .padding(.horizontal, 11).frame(height: 34)
        .background(ALColor.raised, in: Capsule())
        .overlay { Capsule().strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var modeCards: some View {
        HStack(spacing: 12) {
            ForEach(Array(modes.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: item.0.icon).font(.system(size: 15)).foregroundStyle(ALColor.accentText)
                        Text(item.0.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    }
                    Text(item.1).font(.system(size: 11.5)).foregroundStyle(ALColor.textMuted)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
        }
        .padding(.top, 4)
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            Text("One model answers — route the turn to anyone.")
                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
    }
}

// MARK: - New work order (threads exist, none selected)

private struct HomeNewWorkOrderPane: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel

    private var readyCount: Int { appModel.composeBench.filter(\.ready).count }
    private var benchTotal: Int { appModel.composeBench.count }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                AllnighterGlyph(size: 38)
                Text("Start a work order")
                    .font(.system(size: 25, weight: .heavy)).tracking(-0.4)
                    .foregroundStyle(ALColor.textPrimary)
                Text("One message in. Chat with a single model, fan it out to the whole bench for options, or hand it to an agent to build — and route any turn to anyone.")
                    .font(.system(size: 13.5)).foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 486)
                HStack(spacing: 8) {
                    Circle().fill(ALPalette.green500).frame(width: 6, height: 6)
                    Text("\(benchTotal) models on the bench · \(readyCount) ready")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
            RoutingComposer(
                big: true,
                onSend: { threads.sendRouting($0, createThread: true) }
            )
            .frame(maxWidth: 640)
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}
