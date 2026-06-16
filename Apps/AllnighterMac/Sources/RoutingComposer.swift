import SwiftUI
import AppKit

// Compose Routing composer (docs/phases/wiring/design_handoff_compose_routing).
// The composer reads as a sentence: [verb] → [who] → [effort].
//   - Mode pill (Chat / Fan out / Execute) with ⌘1/⌘2/⌘3, opening the mode menu.
//   - Adaptive target chip carrying who + effort (model for chat/exec, lane team
//     for fan out).
//   - Send button whose label reflects the armed verb.
// CR1: the bar + mode menu. Target popovers + effort row = CR2; real-model
// wiring = CR3; thread integration = CR4. Until then it runs on local prototype
// data that mirrors reference/app.jsx, so the surface is provable in isolation.

enum ComposeMode: String, CaseIterable { case chat, fanout, exec }
enum ComposeEffort: String, CaseIterable { case low, med, high }
enum ComposeLane: String, CaseIterable { case build, design, copy }

/// A bench model as the composer sees it (CR3 maps this from AppModel).
struct ComposeBenchModel: Identifiable, Equatable {
    let id: String
    let name: String
    let driverId: String      // for DriverBrandGlyph
    let cli: String           // slug shown on the bench chip (e.g. "claude-code")
    let sub: String
    let ready: Bool
    var notReadyReason: String?
}

/// A saved team for a lane (CR3 maps this from presets).
struct ComposeTeam: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let isDefault: Bool
}

enum ComposeRoutingData {
    // The bench is MODELS — work routes to a model (Opus), never to a CLI
    // (Claude Code). The CLI is only the source: it picks the brand glyph and
    // shows as the chip's grey slug. (CR3 maps this from AppModel.models.)
    static let bench: [ComposeBenchModel] = [
        .init(id: "opus", name: "Opus 4.8", driverId: "claude_code", cli: "claude-code", sub: "Anthropic · Claude Code", ready: true),
        .init(id: "sonnet", name: "Sonnet 4.6", driverId: "claude_code", cli: "claude-code", sub: "Anthropic · Claude Code", ready: true),
        .init(id: "chatgpt", name: "ChatGPT 5.5", driverId: "codex", cli: "codex", sub: "OpenAI · Codex", ready: true),
        .init(id: "grok", name: "Grok Build", driverId: "grok", cli: "grok", sub: "xAI · Grok", ready: true),
        .init(id: "composer", name: "Composer 2.5", driverId: "grok", cli: "grok", sub: "Cursor · Grok", ready: true),
        .init(id: "gemini", name: "Gemini 3.5 Flash", driverId: "antigravity", cli: "antigravity", sub: "Google · Antigravity", ready: true),
    ]
    /// Models that can run as an agent in your repo (Execute mode).
    static let execIds: Set<String> = ["opus", "chatgpt", "grok", "composer"]
    static let teams: [ComposeLane: [ComposeTeam]] = [
        .build: [.init(id: "bd-light", name: "Light review", summary: "3 workers", isDefault: true),
                 .init(id: "bd-full", name: "Full review", summary: "6 workers", isDefault: false),
                 .init(id: "bd-sec", name: "Security pass", summary: "3 workers · custom", isDefault: false)],
        .design: [.init(id: "ds-std", name: "Standard board", summary: "4 mockups", isDefault: true),
                  .init(id: "ds-brand", name: "Brand pass", summary: "2 mockups · custom", isDefault: false)],
        .copy: [.init(id: "cp-land", name: "Landing page", summary: "4 versions", isDefault: true),
                .init(id: "cp-launch", name: "Aggressive launch", summary: "6 versions · custom", isDefault: false)],
    ]
    static func defaultTeam(_ lane: ComposeLane) -> String {
        let list = teams[lane] ?? []
        return (list.first { $0.isDefault } ?? list.first)?.id ?? ""
    }
    static func model(_ id: String) -> ComposeBenchModel? { bench.first { $0.id == id } }
}

extension ComposeMode {
    var label: String { switch self { case .chat: "Chat"; case .fanout: "Fan out"; case .exec: "Execute" } }
    var icon: String { switch self { case .chat: "message"; case .fanout: "rectangle.stack"; case .exec: "hammer" } }
    var kbd: String { switch self { case .chat: "⌘1"; case .fanout: "⌘2"; case .exec: "⌘3" } }
    var desc: String {
        switch self {
        case .chat: "One model answers — route the turn to anyone."
        case .fanout: "A team answers in parallel → a board to compare and pick."
        case .exec: "An agent runs it in your repo and the result returns here."
        }
    }
}

extension ComposeEffort { var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() } }
extension ComposeLane {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var icon: String { switch self { case .build: "hammer"; case .design: "photo"; case .copy: "doc.text" } }
}

/// Proof/specimen container — shows the composer on the dark canvas, anchored
/// like the thread pane, for the GUI proof gate + the dev GUI-routes sheet.
/// Real placement in the thread workspace lands in CR4.
struct ComposeSpecimen: View {
    var openModeMenu: Bool = false
    var openTarget: Bool = false
    var mode: ComposeMode = .chat
    var body: some View {
        VStack {
            Spacer()
            RoutingComposer(mode: mode, openModeMenu: openModeMenu, openTarget: openTarget)
                .frame(maxWidth: 680)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

struct RoutingComposer: View {
    enum Popover { case mode, target }

    @State var mode: ComposeMode
    @State var to: String
    @State var effort: ComposeEffort
    @State var lane: ComposeLane
    @State var team: String
    @State private var text: String = ""
    @State private var pop: Popover?

    let placeholder: String
    private let big: Bool

    init(mode: ComposeMode = .chat, openModeMenu: Bool = false, openTarget: Bool = false, big: Bool = false) {
        _mode = State(initialValue: mode)
        _to = State(initialValue: mode == .exec ? "opus" : "opus")
        _effort = State(initialValue: .med)
        _lane = State(initialValue: .design)
        _team = State(initialValue: ComposeRoutingData.defaultTeam(.design))
        _pop = State(initialValue: openModeMenu ? .mode : (openTarget ? .target : nil))
        self.big = big
        self.placeholder = big
            ? "Describe the work — a question, a screen to redesign, a change to ship…"
            : "Reply, or start the next turn…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            box
            hint
        }
        .overlay(alignment: .bottomLeading) { popoverLayer }
    }

    // MARK: composer box

    private var box: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                        .padding(.horizontal, 14).padding(.top, 12).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.top, 6)
                    .frame(minHeight: big ? 76 : 52, maxHeight: 140)
            }
            bar
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var bar: some View {
        HStack(spacing: 9) {
            modePill
            if mode != .fanout {
                Text("to").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            targetChip
            Spacer(minLength: 8)
            IconButton(systemImage: "photo", accessibilityLabel: "Attach image", small: true) {}
            sendButton
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
    }

    private var modePill: some View {
        Button { pop = (pop == .mode ? nil : .mode) } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.icon).font(.system(size: 13)).foregroundStyle(ALColor.accentText)
                Text(mode.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 11).frame(height: 31)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var targetChip: some View {
        Button { pop = (pop == .target ? nil : .target) } label: {
            HStack(spacing: 7) {
                switch mode {
                case .chat, .exec:
                    if let m = ComposeRoutingData.model(to) {
                        DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5)
                        Text(m.name).font(ALFont.mono).foregroundStyle(ALColor.textPrimary)
                    }
                case .fanout:
                    Image(systemName: lane.icon).font(.system(size: 12)).foregroundStyle(ALColor.accentText)
                    Text("\(lane.label) team").font(ALFont.mono).foregroundStyle(ALColor.textPrimary)
                }
                Text("· \(effort.label)").font(ALFont.mono).foregroundStyle(ALColor.textMuted)
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 10).frame(height: 31)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var sendButton: some View {
        Button {} label: {
            Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALColor.textOnAmber)
                .frame(width: 34, height: 34)
                .background(ALColor.accent, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send — \(mode.label)")
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            Text(mode.desc).font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.leading, 2)
    }

    // MARK: actions

    private func selectMode(_ m: ComposeMode) {
        mode = m
        if m == .exec, !ComposeRoutingData.execIds.contains(to) { to = "opus" }
        // Picking Fan out drops the user straight into the lane/team picker.
        pop = (m == .fanout) ? .target : nil
    }

    // MARK: popovers

    @ViewBuilder private var popoverLayer: some View {
        switch pop {
        case .mode: modeMenu
        case .target: targetPopover
        case .none: EmptyView()
        }
    }

    // MARK: target popover (who + effort)

    private var targetPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch mode {
            case .chat:
                popHeader("Route to model", "One model answers this turn")
                modelList(ComposeRoutingData.bench.map(\.id))
                effortRow(note: "Higher effort = more reasoning time.")
            case .exec:
                popHeader("Hand to executor", "An agent runs it in your repo")
                modelList(ComposeRoutingData.bench.filter { ComposeRoutingData.execIds.contains($0.id) }.map(\.id))
                effortRow(note: "Higher effort = more reasoning time.")
            case .fanout:
                popHeader("Send to team", "Pick the lane, then the lineup")
                laneTabs
                teamList
                customizeFooter
                effortRow(note: "Higher effort = more workers + a deeper pass.")
            }
        }
        .padding(6)
        .frame(width: mode == .fanout ? 320 : 300)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .alShadowXl()
        .fixedSize()
        .offset(x: 96, y: -150)
    }

    private func popHeader(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(ALColor.textPrimary)
            Text(sub).font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 7)
    }

    private func modelList(_ ids: [String]) -> some View {
        VStack(spacing: 1) {
            ForEach(ids, id: \.self) { id in
                if let m = ComposeRoutingData.model(id) {
                    Button { if m.ready { to = id; pop = nil } } label: { modelRow(m) }
                        .buttonStyle(.plain)
                        .disabled(!m.ready)
                }
            }
        }
    }

    private func modelRow(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 10) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 27, iconSize: 15, cornerRadius: 7).opacity(m.ready ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m.ready ? ALColor.textPrimary : ALColor.textMuted)
                Text(m.sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 8)
            if m.ready {
                if to == m.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
            } else if let reason = m.notReadyReason {
                Badge(text: reason, tone: .warning)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(to == m.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private var laneTabs: some View {
        HStack(spacing: 6) {
            ForEach(ComposeLane.allCases, id: \.self) { l in
                Button { lane = l; team = ComposeRoutingData.defaultTeam(l) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: l.icon).font(.system(size: 12)).foregroundStyle(l == lane ? ALColor.accentText : ALColor.textMuted)
                        Text(l.label).font(.system(size: 12, weight: .medium)).foregroundStyle(l == lane ? ALColor.textPrimary : ALColor.textMuted)
                    }
                    .frame(maxWidth: .infinity).frame(height: 31)
                    .background(l == lane ? ALColor.active : ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(l == lane ? ALColor.borderDefault : .clear, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    private var teamList: some View {
        VStack(spacing: 1) {
            ForEach(ComposeRoutingData.teams[lane] ?? []) { t in
                Button { team = t.id; pop = nil } label: { teamRow(t) }.buttonStyle(.plain)
            }
        }
    }

    private func teamRow(_ t: ComposeTeam) -> some View {
        HStack(spacing: 10) {
            Image(systemName: lane.icon).font(.system(size: 14)).foregroundStyle(ALColor.accentText)
                .frame(width: 27, height: 27)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    if t.isDefault {
                        Text("default").font(.system(size: 9, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay { RoundedRectangle(cornerRadius: ALRadius.xs).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    }
                }
                Text(t.summary).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 8)
            if team == t.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(team == t.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private var customizeFooter: some View {
        HStack(spacing: 8) {
            Button {} label: { Label("Customize…", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.alGhost)
            Text("Build & edit teams in settings.").font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func effortRow(note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("EFFORT").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    ForEach(ComposeEffort.allCases, id: \.self) { e in
                        Button { effort = e } label: {
                            Text(e.label).font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(e == effort ? ALColor.textPrimary : ALColor.textMuted)
                                .frame(width: 44, height: 24)
                                .background(e == effort ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
            Text(note).font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var modeMenu: some View {
        VStack(spacing: 2) {
            ForEach(ComposeMode.allCases, id: \.self) { m in
                Button { selectMode(m) } label: { modeRow(m) }
                    .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 300)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .alShadowXl()
        .offset(y: -130)
    }

    private func modeRow(_ m: ComposeMode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: m.icon).font(.system(size: 15)).foregroundStyle(ALColor.accentText).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    if m == mode { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
                    Spacer(minLength: 8)
                    Text(m.kbd).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.xs))
                        .overlay { RoundedRectangle(cornerRadius: ALRadius.xs).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                Text(m.desc).font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m == mode ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }
}
