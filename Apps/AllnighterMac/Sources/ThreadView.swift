import SwiftUI
import AllnighterCore

// Conversation thread pane (docs/phases/wiring/compose-routing, reference/app.jsx
// ThreadPane + NewPane). CR4a: userMessage turns + docked RoutingComposer; worker
// replies land in CR4b.

struct ThreadView: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let thread = threads.selectedThread {
            if thread.turns.isEmpty {
                ThreadEmptyState(thread: thread)
            } else {
                ThreadConversationPane(thread: thread)
            }
        }
    }
}

// MARK: - Empty thread ("Start a work order")

private struct ThreadEmptyState: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel
    let thread: WorkThread

    private var readyCount: Int { appModel.composeBench.filter(\.ready).count }
    private var benchTotal: Int { appModel.composeBench.count }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Image(systemName: "moon.stars.fill").font(.system(size: 38)).foregroundStyle(ALColor.accent)
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
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
            RoutingComposer(
                big: true,
                defaultMode: ComposeRoutingDefaults.mode(for: thread),
                onSend: { threads.sendRouting($0) }
            )
            .frame(maxWidth: 640)
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

// MARK: - Thread with turns

private struct ThreadConversationPane: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    var body: some View {
        VStack(spacing: 0) {
            ThreadPaneHeader(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ThreadTurnTimeline(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            RoutingComposer(
                defaultMode: ComposeRoutingDefaults.mode(for: thread),
                onSend: { threads.sendRouting($0) }
            )
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

private struct ThreadPaneHeader: View {
    @Environment(AppModel.self) private var appModel
    let thread: WorkThread

    var body: some View {
        HStack(spacing: 10) {
            Text(thread.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ALColor.textPrimary)
                .lineLimit(1)
            if let lane = inferredLane {
                laneChip(lane)
            }
            Spacer(minLength: 8)
            if !routedWorkerIds.isEmpty {
                HStack(spacing: 6) {
                    Text("routed across")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    HStack(spacing: -4) {
                        ForEach(routedWorkerIds.prefix(4), id: \.self) { workerId in
                            if let model = appModel.composeBench.first(where: { $0.id == workerId }) {
                                DriverBrandGlyph(driverId: model.driverId, boxSize: 18, iconSize: 10, cornerRadius: 5)
                                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(ALColor.surface, lineWidth: 1.5) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var inferredLane: ComposeLane? {
        if thread.turns.contains(where: { $0.kind == .designBoard }) { return .design }
        if thread.turns.contains(where: { $0.kind == .teamRun || $0.kind == .workOrder }) { return .build }
        return nil
    }

    private var routedWorkerIds: [String] {
        var seen = Set<String>()
        return thread.turns.compactMap(\.workerId).filter { seen.insert($0).inserted }
    }

    private func laneChip(_ lane: ComposeLane) -> some View {
        HStack(spacing: 4) {
            Image(systemName: lane.icon).font(.system(size: 11))
            Text(lane.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(lane == .design ? ALColor.accentText : ALColor.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(lane == .design ? ALColor.active : ALColor.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

private struct ThreadTurnTimeline: View {
    let thread: WorkThread

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(thread.turns) { turn in
                        ThreadUserTurnRow(turn: turn).id(turn.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: thread.turns.count) { _, _ in
                if let last = thread.turns.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// CR4a renders user messages; other turn kinds get honest stubs until CR4b–d.
private struct ThreadUserTurnRow: View {
    let turn: ThreadTurn

    var body: some View {
        switch turn.kind {
        case .userMessage, .userDecision:
            userBubble
        default:
            stubTurn
        }
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("YOU")
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundStyle(ALColor.textFaint)
                .frame(width: 28, height: 28)
                .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("You")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ALColor.textSecondary)
                    Text(turn.createdAt, format: .dateTime.hour().minute())
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
                Text(turn.text ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(ALColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var stubTurn: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            Text(turn.kind.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(ALFont.caption).foregroundStyle(ALColor.textMuted)
            StatusPill(kind: ThreadsPresenter.pillKind(for: turn.status))
        }
        .padding(.vertical, 4)
    }
}
