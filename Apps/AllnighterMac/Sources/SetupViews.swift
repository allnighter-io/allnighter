import SwiftUI
import AppKit
import AllnighterCore

// First-run Setup + Team-health UI, built pixel-exact from the setup handoff
// (docs/phases/mockups/design_handoff_first_run_setup 3 — setup.jsx / doctor.jsx).
// Vocabulary follows the code (team/worker/plan-writer cutover complete).
// Renders real ModelSetupStatus from AppModel.toolStatuses — never faked.

// MARK: - Card model (mapped from a ToolProbeRecord by AppModel.setupCards)

enum SetupCardState: Sendable {
    case ready, needsLogin, needsPath, notInstalled, probeFailed, installedNotProbed, detecting, reprobing, queued, waiting
    /// Supported, but never probed on this machine (cold first run). Honest
    /// "we haven't looked yet" — shown so onboarding lists every supported CLI
    /// before the first scan, instead of a blank roster.
    case notChecked
}

extension SetupCardState {
    /// Roster row / full card — one label per probe state.
    var rosterPill: SetupPill {
        switch self {
        case .ready: SetupPill(kind: .ready, label: "Ready")
        case .needsLogin: SetupPill(kind: .step, label: "Needs sign-in")
        case .needsPath: SetupPill(kind: .step, label: "Needs a path")
        case .notInstalled: SetupPill(kind: .muted, label: "Not installed")
        case .probeFailed: SetupPill(kind: .fail, label: "Probe failed")
        case .installedNotProbed: SetupPill(kind: .muted, label: "Installed")
        case .detecting: SetupPill(kind: .check, label: "Detecting…")
        case .reprobing: SetupPill(kind: .check, label: "Re-checking…")
        case .queued: SetupPill(kind: .muted, label: "Queued")
        case .waiting: SetupPill(kind: .check, label: "Waiting for sign-in…")
        case .notChecked: SetupPill(kind: .muted, label: "Not checked")
        }
    }

    /// Repair panel — collapses in-progress / unknown states.
    var repairPill: SetupPill {
        switch self {
        case .ready: SetupPill(kind: .ready, label: "Ready")
        case .needsLogin, .waiting: SetupPill(kind: .step, label: "Needs sign-in")
        case .needsPath: SetupPill(kind: .step, label: "Needs a path")
        case .notInstalled: SetupPill(kind: .muted, label: "Not installed")
        case .probeFailed: SetupPill(kind: .fail, label: "Probe failed")
        case .detecting, .reprobing: SetupPill(kind: .check, label: "Re-checking…")
        default: SetupPill(kind: .muted, label: "Needs a step")
        }
    }
}

/// Partitions setup cards into roster groups (popover vs full setup page).
struct SetupCardBuckets {
    let ready: [SetupCardModel]
    let step: [SetupCardModel]
    let notChecked: [SetupCardModel]
    let add: [SetupCardModel]

    init(_ cards: [SetupCardModel], splitNotChecked: Bool) {
        ready = cards.filter { $0.state == .ready }
        add = cards.filter { $0.state == .notInstalled }
        if splitNotChecked {
            notChecked = cards.filter { $0.state == .notChecked }
            step = cards.filter {
                $0.state != .ready && $0.state != .notInstalled && $0.state != .notChecked
            }
        } else {
            notChecked = []
            step = cards.filter { $0.state != .ready && $0.state != .notInstalled }
        }
    }
}

struct SetupCardModel: Identifiable {
    let driverId: String
    let name: String
    let route: String
    let version: String?
    let state: SetupCardState
    let workers: [WorkerSeat]      // models on this tool (shown when ready)
    let loginCommand: String?      // loginFlow.interactiveCommand
    let installHint: String?
    let docsURL: String?
    let shimCommand: String?       // raw `command -v` for needsPath
    let probeReason: String?
    /// Headless mutation/trust posture from the driver manifest (e.g. Cursor `--trust`).
    let headlessTrust: HeadlessTrustPolicy?

    var id: String { driverId }

    /// Clipboard payload for setup probe failures (Copy log).
    var probeLogText: String {
        var lines = ["driver: \(driverId)", "name: \(name)", "route: \(route)"]
        if let version { lines.append("detected: \(version)") }
        lines.append("state: \(String(describing: state))")
        if let probeReason, !probeReason.isEmpty { lines.append("detail: \(probeReason)") }
        if let shimCommand, !shimCommand.isEmpty { lines.append("shim: \(shimCommand)") }
        return lines.joined(separator: "\n")
    }

    /// Whether setup/repair surfaces should show the headless-trust callout.
    var showsHeadlessTrustDisclosure: Bool {
        guard let trust = headlessTrust, trust.required else { return false }
        switch state {
        case .ready, .needsLogin, .waiting, .notChecked, .installedNotProbed, .probeFailed:
            return true
        default:
            return false
        }
    }

    struct WorkerSeat: Identifiable {
        let id: String
        let name: String
        let modelLabel: String
        let isPlanWriter: Bool

        /// Model name on CLI setup surfaces (roster chips, detail panel).
        var setupChipLabel: String {
            let slug = modelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty else { return name }
            if slug.contains(" ") {
                let base = slug.split(separator: "(", maxSplits: 1).first.map(String.init) ?? slug
                return base.trimmingCharacters(in: .whitespaces)
            }
            return name
        }

        /// Short CLI model slug for detail mono line (opus, gpt-5.5), when useful.
        var setupDetailSlug: String? {
            let slug = modelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty, !slug.contains(" ") else { return nil }
            return slug
        }
    }
}

// MARK: - Brand glyph (40×40 tile + the tool's mark)

struct BrandGlyph: View {
    let driverId: String
    var muted: Bool = false

    var body: some View {
        DriverBrandGlyph(driverId: driverId, boxSize: 40, iconSize: 23, cornerRadius: 10, muted: muted)
    }
}

// MARK: - Setup pill (su-pill)

struct SetupPill: View {
    enum Kind { case ready, step, muted, fail, check }
    let kind: Kind
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
                .opacity(kind == .check && dim ? 0.3 : 1)
            Text(label).font(.system(size: 11.5, weight: .semibold))
        }
        .padding(.leading, 8).padding(.trailing, 10)
        .frame(height: 23)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
        .onAppear {
            guard kind == .check, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private var bg: Color {
        switch kind {
        case .ready: ALColor.successSurface
        case .step: ALColor.warningSurface
        case .muted: ALColor.active
        case .fail: ALColor.dangerSurface
        case .check: ALColor.infoSurface
        }
    }
    private var fg: Color {
        switch kind {
        case .ready: ALPalette.green400
        case .step: ALPalette.yellow400
        case .muted: ALColor.textFaint
        case .fail: ALPalette.red400
        case .check: ALPalette.blue400
        }
    }
    private var dot: Color {
        switch kind {
        case .ready: ALPalette.green500
        case .step: ALPalette.yellow400
        case .muted: ALColor.textFaint
        case .fail: ALPalette.red400
        case .check: ALPalette.blue400
        }
    }
}

// MARK: - Copyable command box (su-cmd)

struct CmdRow: View {
    var prompt: String = "$"
    let text: String
    var error: Bool = false

    var body: some View {
        HStack(spacing: 9) {
            Text(prompt).font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(error ? ALPalette.red400 : ALColor.textFaint)
            Text(text).font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(error ? ALPalette.red400 : ALColor.textPrimary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy", small: true) { SetupActions.copyToPasteboard(text) }
        }
        .padding(.vertical, 8).padding(.leading, 12).padding(.trailing, 8)
        .background(ALColor.void, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

// MARK: - Headless trust disclosure (driver manifest → setup/repair)

struct HeadlessTrustNotice: View {
    let policy: HeadlessTrustPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                Text("Runs with \(policy.cliFlag)")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(ALPalette.yellow400)
            Text(policy.disclosure)
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(ALColor.warningSurface, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

// MARK: - Group label (su-grouplbl)

struct SetupGroupLabel: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.15)
                .foregroundStyle(ALColor.textFaint)
            Text("\(count)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
        .padding(.top, 15).padding(.bottom, 3).padding(.horizontal, 2)
    }
}

// MARK: - The card (su-card)

/// `.roster` — list row: CLI name, model chips, status pill (detail lives in repair panel).
/// `.full` — expanded card with meta + inline fix-it (first-run setup, previews).
enum SetupCardLayout { case roster, full }

struct SetupCardView: View {
    let card: SetupCardModel
    var layout: SetupCardLayout = .full
    var compact: Bool = false
    /// When false, suppress inline fix-it body (legacy; roster layout never shows fix-it).
    var showFixIt: Bool = true
    var onAction: (SetupAction) -> Void = { _ in }

    enum SetupAction { case openTerminal(String), copy(String), openURL(String), rescan, locate, useAnyway }

    var body: some View {
        VStack(spacing: 0) {
            if layout == .roster {
                rosterHead
            } else {
                fullHead
            }
            bodyView
        }
        .background(fill, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.lg)
                .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : []))
        }
        .modifier(ShadowIfCard(on: layout == .full && !dashed))
    }

    // MARK: Roster row (CLI setup list + doctor compact list)

    private var rosterHead: some View {
        HStack(alignment: .top, spacing: 13) {
            BrandGlyph(driverId: card.driverId, muted: muted)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(card.name).font(.system(size: 14.5, weight: .semibold)).tracking(-0.14)
                        .foregroundStyle(muted ? ALColor.textMuted : ALColor.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    pill.fixedSize(horizontal: true, vertical: false)
                }
                if !card.workers.isEmpty {
                    SetupModelChips(workers: card.workers)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13).padding(.horizontal, 15)
    }

    // MARK: Full card head (setup flow — meta + pill)

    private var fullHead: some View {
        HStack(spacing: 13) {
            BrandGlyph(driverId: card.driverId, muted: muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name).font(.system(size: 14.5, weight: .semibold)).tracking(-0.14)
                    .foregroundStyle(muted ? ALColor.textMuted : ALColor.textPrimary)
                    .lineLimit(2)
                meta
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            pill
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 13).padding(.horizontal, 15)
    }

    // meta — one flowing mono line; status lives in the pill only (no redundant "signed in").
    private var meta: some View {
        Text(metaLine)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(ALColor.textMuted)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: String {
        metaItems.map(\.text).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private struct MetaItem { let text: String; let color: Color }
    private var metaItems: [MetaItem] {
        let route = MetaItem(text: card.route, color: ALColor.textMuted)
        let version = MetaItem(text: card.version ?? "", color: ALColor.textMuted)
        switch card.state {
        case .ready:
            return [route, version]
        case .needsLogin, .waiting:
            return [route, version, MetaItem(text: "found, not signed in", color: ALColor.textFaint)]
        case .needsPath:
            return [route, version, MetaItem(text: "shell function", color: ALColor.textFaint)]
        case .notInstalled:
            return [MetaItem(text: "no binary on PATH or known paths", color: ALColor.textFaint)]
        case .probeFailed:
            return [route, version, MetaItem(text: "smoke failed", color: ALColor.textFaint)]
        case .installedNotProbed:
            return [route, version, MetaItem(text: "installed — not yet probed", color: ALColor.textFaint)]
        case .reprobing:
            return [route, version, MetaItem(text: "cheap re-check…", color: ALColor.textFaint)]
        case .detecting:
            return [route, MetaItem(text: "resolving → version → smoke", color: ALColor.textFaint)]
        case .queued:
            return [MetaItem(text: "queued", color: ALColor.textFaint)]
        case .notChecked:
            return [route, MetaItem(text: "not checked yet", color: ALColor.textFaint)]
        }
    }

    private var pill: SetupPill { card.state.rosterPill }

    // body / fix-it
    @ViewBuilder private var bodyView: some View {
        if layout == .roster || !showFixIt {
            EmptyView()
        } else {
            fixItContent
        }
    }

    @ViewBuilder private var fixItContent: some View {
        switch card.state {
        case .ready where !compact:
            VStack(spacing: 0) {
                seatsBody
                if card.showsHeadlessTrustDisclosure, let trust = card.headlessTrust {
                    HeadlessTrustNotice(policy: trust)
                        .padding(.horizontal, 15).padding(.bottom, 14)
                }
            }
        case .needsLogin, .waiting:
            fixItBody {
                fixLine("\(card.name) is installed but not signed in. It prompts for sign-in on first run.")
                if card.showsHeadlessTrustDisclosure, let trust = card.headlessTrust {
                    HeadlessTrustNotice(policy: trust).padding(.bottom, 10)
                }
                CmdRow(text: card.loginCommand ?? card.driverId)
                if card.state == .waiting {
                    HStack(spacing: 10) {
                        SetupPill(kind: .check, label: "Waiting for sign-in…")
                        Text("re-checking every few seconds").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button { onAction(.openTerminal(card.loginCommand ?? card.driverId)) } label: {
                            Label("Open Terminal & sign in", systemImage: "terminal")
                        }.buttonStyle(.alPrimary(small: true))
                        Button { onAction(.copy(card.loginCommand ?? card.driverId)) } label: {
                            Label("Copy steps", systemImage: "doc.on.doc")
                        }.buttonStyle(.alGhost)
                    }
                }
                note(card.state == .waiting ? "Flips to ready the moment the probe passes — no restart, no app focus needed."
                                             : "Sign in in Terminal — we’ll detect when you’re done.",
                     systemImage: card.state == .waiting ? "arrow.triangle.2.circlepath" : "info.circle")
            }
        case .needsPath:
            fixItBody {
                fixLine("We found this tool as a shell function, not a plain command.")
                CmdRow(prompt: "ƒ", text: card.shimCommand ?? "")
                HStack(spacing: 8) {
                    Button { onAction(.useAnyway) } label: { Text("Use it anyway") }.buttonStyle(.alSecondary)
                    Button { onAction(.locate) } label: { Label("Locate the binary…", systemImage: "folder") }.buttonStyle(.alGhost)
                }
                note("Use-anyway runs it through your login shell — exactly as your terminal does.", systemImage: "info.circle")
            }
        case .notInstalled:
            fixItBody {
                fixLine("You don’t have \(card.name) yet. Install it, then re-scan.")
                CmdRow(text: card.installHint ?? "see docs")
                HStack(spacing: 8) {
                    Button { onAction(.openURL(card.docsURL ?? "")) } label: { Label("Open install page", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.alSecondary).disabled((card.docsURL ?? "").isEmpty)
                    Button { onAction(.rescan) } label: { Label("Re-scan", systemImage: "arrow.clockwise") }.buttonStyle(.alGhost)
                }
            }
        case .probeFailed:
            fixItBody {
                fixLine("Detected \(card.version ?? card.name), but the smoke run failed.")
                CmdRow(prompt: "!", text: card.probeReason ?? "smoke failed", error: true)
                HStack(spacing: 8) {
                    Button { onAction(.rescan) } label: { Label("Re-try probe", systemImage: "arrow.clockwise") }.buttonStyle(.alSecondary)
                }
                note("Detect passed, smoke didn’t — this is not a sign-in problem.", systemImage: "exclamationmark.triangle", tint: ALPalette.red400)
            }
        default:
            EmptyView()
        }
    }

    private var seatsBody: some View {
        VStack(spacing: 1) {
            ForEach(card.workers) { seat in
                HStack(spacing: 10) {
                    Circle().fill(ALColor.statusDone).frame(width: 7, height: 7)
                    Text(seat.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    Text(seat.modelLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                    Spacer(minLength: 8)
                    if seat.isPlanWriter {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles").font(.system(size: 11))
                            Text("plan writer").font(.system(size: 10.5, weight: .semibold))
                        }
                        .padding(.horizontal, 8).frame(height: 20)
                        .foregroundStyle(ALColor.accentText)
                        .background(ALColor.accentSurface, in: Capsule())
                        .overlay { Capsule().strokeBorder(ALColor.accentBorder, lineWidth: 1) }
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 9)
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 15)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    @ViewBuilder private func fixItBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, 14).padding(.horizontal, 15).padding(.bottom, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func fixLine(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(ALColor.textSecondary)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 11)
    }

    private func note(_ text: String, systemImage: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage).font(.system(size: 12)).foregroundStyle(tint ?? ALColor.textFaint)
            Text(text).font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    // variant styling
    private var muted: Bool {
        switch card.state { case .notInstalled, .queued, .detecting, .installedNotProbed, .notChecked: true; default: false }
    }
    private var dashed: Bool {
        switch card.state { case .notInstalled, .queued, .detecting: true; default: false }
    }
    private var fill: Color {
        switch card.state {
        case .ready: ALColor.raised
        case .notInstalled, .queued, .detecting, .installedNotProbed: ALColor.surface
        default: ALColor.raised
        }
    }
    private var borderColor: Color {
        ALColor.borderDefault
    }
}

// MARK: - Model chips (roster rows)

struct SetupModelChips: View {
    let workers: [SetupCardModel.WorkerSeat]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 76, maximum: 160), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(workers) { seat in
                Text(seat.setupChipLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ALColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(ALColor.active, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
        }
    }
}

private struct ShadowIfCard: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        on ? AnyView(content.shadow(color: .black.opacity(0.45), radius: 3, y: 2)) : AnyView(content)
    }
}

// MARK: - Bench health popover (home/doctor.jsx)

struct BenchHealthPopover: View {
    @Environment(AppModel.self) private var model
    var onClose: () -> Void
    var onOpenFull: () -> Void
    /// Tap a CLI row → open CLI setup with that driver selected in the detail panel.
    var onSelectCLI: (String) -> Void = { _ in }
    /// Cap scroll body so the panel stays on-screen below the title-bar anchor.
    var maxBodyHeight: CGFloat = 420

    private var cards: [SetupCardModel] { model.setupCards }

    // CLI-setup redesign §2: grouped CLI rows — Needs attention → Ready → Dormant.
    // Rows are tappable (opens CLI setup for that driver); no in-popover selection ring.
    // Ready = installed + signed in + ≥1 model ON; Dormant = ready CLI with 0 models on;
    // Needs attention = genuinely broken.
    private var attentionCards: [SetupCardModel] {
        cards.filter { CLIStatusGroup.isAttention($0.state) }
    }
    private var readyCards: [SetupCardModel] {
        cards.filter { $0.state == .ready && !onModelNames(for: $0.driverId).isEmpty }
    }
    private var dormantCards: [SetupCardModel] {
        cards.filter { ($0.state == .ready && onModelNames(for: $0.driverId).isEmpty) || $0.state == .notChecked }
    }

    private func onModelNames(for driverId: String) -> [String] {
        model.models
            .filter { $0.enabled && $0.driverId == driverId }
            .map(\.displayName)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    group("Needs attention", cards: attentionCards, kind: .attention)
                    group("Ready", cards: readyCards, kind: .ready)
                    group("Dormant", cards: dormantCards, kind: .dormant)
                }
                .padding(.top, 4).padding(.horizontal, 13).padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
            .frame(height: bodyHeight)
            footer
        }
        .frame(width: 404)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.xl))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .shadow(color: .black.opacity(0.66), radius: 30, y: 24)
    }

    private var bodyHeight: CGFloat {
        var h: CGFloat = 16
        for count in [attentionCards.count, readyCards.count, dormantCards.count] where count > 0 {
            h += 26 + CGFloat(count) * 70
        }
        return min(max(h, 80), maxBodyHeight)
    }

    @ViewBuilder private func group(_ title: String, cards: [SetupCardModel], kind: CLIStatusGroup) -> some View {
        if !cards.isEmpty {
            SetupGroupLabel(title: title, count: cards.count)
            ForEach(cards) { card in
                CLIStatusRow(
                    card: card, onModels: onModelNames(for: card.driverId), kind: kind,
                    interactive: true,
                    onTap: { onSelectCLI(card.driverId) })
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield").font(.system(size: 17)).foregroundStyle(ALColor.accentText)
                Text("CLIs").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ALColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(systemImage: "xmark", accessibilityLabel: "Close", small: true) { onClose() }
            }
            summaryLine
        }
        .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var summaryLine: some View {
        let attention = attentionCards.count
        return HStack(spacing: 0) {
            if attention > 0 {
                Text("\(attention) needs attention")
                    .foregroundStyle(ALColor.accentText).fontWeight(.semibold)
                Text(" · ").foregroundStyle(ALColor.textFaint)
            }
            Text("\(readyCards.count) ready").foregroundStyle(ALColor.textSecondary)
            Text(" · ").foregroundStyle(ALColor.textFaint)
            Text("\(model.availableModels.count) models on").foregroundStyle(ALColor.textSecondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
    }

    private var footer: some View {
        Button {
            onOpenFull()
        } label: {
            Label("Open CLI setup", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.alSecondary(small: true))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ALColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

}

// MARK: - Shared CLI status row (CLI-setup redesign §CLI row)

/// Which redesign group a CLI row belongs to — drives the status dot, content, and
/// dormant dimming. Shared by the CLI dropdown (non-interactive) and the CLI setup
/// page (selectable).
enum CLIStatusGroup {
    case attention, ready, dormant

    /// A genuinely broken state (vs. dormant, which is not an error).
    static func isAttention(_ state: SetupCardState) -> Bool {
        switch state {
        case .needsLogin, .needsPath, .notInstalled, .probeFailed, .waiting: return true
        case .ready, .notChecked, .installedNotProbed, .detecting, .reprobing, .queued: return false
        }
    }
}

/// One CLI row: glyph tile · name · (ON-model chips / failure reason / dormant
/// caption) · status dot. Reused verbatim in the CLI dropdown and the setup list.
struct CLIStatusRow: View {
    let card: SetupCardModel
    let onModels: [String]
    let kind: CLIStatusGroup
    var interactive: Bool = false
    var selected: Bool = false
    var onTap: () -> Void = {}
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            DriverBrandGlyph(driverId: card.driverId, boxSize: 40, iconSize: 22, cornerRadius: 10)
                .opacity(kind == .dormant ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 7) {
                Text(card.name)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(kind == .dormant ? ALColor.textMuted : ALColor.textPrimary)
                content
            }
            Spacer(minLength: 8)
            statusDot
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.lg)
                .strokeBorder(selected ? ALColor.accentBorder : (kind == .dormant ? .clear : (hover ? ALColor.borderDefault : ALColor.borderSubtle)),
                              lineWidth: 1)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.accent.opacity(0.12), lineWidth: 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { if interactive { hover = $0 } }
        .onTapGesture { if interactive { onTap() } }
    }

    private var rowBackground: Color {
        if kind == .dormant { return .clear }
        return hover && interactive ? ALColor.hover : ALColor.raised
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .ready:
            ChipRow(items: onModels)
        case .attention:
            Text(attentionReason)
                .font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        case .dormant:
            Text("No models on — dormant")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(ALColor.textFaint)
        }
    }

    @ViewBuilder private var statusDot: some View {
        switch kind {
        case .ready: StatusDot(color: ALPalette.green500, halo: ALPalette.green500.opacity(0.15))
        case .dormant: StatusDot(color: ALPalette.ink450, halo: nil)
        case .attention: StatusDot(color: ALPalette.amber500, halo: ALPalette.amber500.opacity(0.18))
        }
    }

    private var attentionReason: String {
        if let r = card.probeReason, !r.isEmpty { return r }
        switch card.state {
        case .needsLogin, .waiting: return "Installed but signed out — sign in to use its models."
        case .needsPath: return "Installed but not on PATH — locate it to use its models."
        case .notInstalled: return "Not installed."
        case .probeFailed: return "Health check failed — re-check or fix."
        default: return "Needs a step."
        }
    }
}

/// A simple non-wrapping chip row (ON models). Most CLIs expose 1–2 on models; caps
/// at 4 visible with a "+N" overflow so it never pushes the row width.
private struct ChipRow: View {
    let items: [String]
    private var visible: [String] { Array(items.prefix(4)) }
    private var overflow: Int { max(0, items.count - 4) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visible, id: \.self) { chip($0) }
            if overflow > 0 { chip("+\(overflow)") }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(ALColor.active, in: Capsule())
            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

/// Status dot with an optional soft halo ring (Ready/Needs-attention have a halo;
/// Dormant does not).
struct StatusDot: View {
    let color: Color
    var halo: Color?

    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9)
            .overlay {
                if let halo { Circle().stroke(halo, lineWidth: 3).frame(width: 13, height: 13) }
            }
    }
}

// MARK: - Title-bar health badge (opens Bench health)

struct BenchHealthFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct BenchHealthBadge: View {
    @Environment(AppModel.self) private var model
    @Binding var isOpen: Bool
    @State private var hover = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Badge(text: label, tone: tone, dot: true, mono: true)
        }
        .buttonStyle(.plain)
        .help("CLI setup — which command-line tools are ready")
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: BenchHealthFrameKey.self, value: geo.frame(in: .global))
            }
        }
        .overlay {
            if isOpen {
                RoundedRectangle(cornerRadius: ALRadius.pill)
                    .strokeBorder(ALColor.accentBorder, lineWidth: 1)
                    .shadow(color: ALColor.accent.opacity(0.35), radius: 6)
            }
        }
        .onHover { hover = $0 }
    }

    private var label: String {
        guard model.totalToolCount > 0 else { return "checking…" }
        let ready = model.readyToolCount, total = model.totalToolCount
        return ready == total ? "\(ready) ready" : "\(ready)/\(total) ready"
    }

    private var tone: Badge.Tone {
        guard model.totalToolCount > 0, !model.isDetecting else { return .neutral }
        return model.readyToolCount == model.totalToolCount ? .positive : .warning
    }
}

// MARK: - Shared actions

enum SetupActions {
    static func openTerminal(_ command: String) {
        let safe = command.replacingOccurrences(of: "\"", with: "\\\"")
        let src = "tell application \"Terminal\"\nactivate\ndo script \"\(safe)\"\nend tell"
        if let script = NSAppleScript(source: src) { script.executeAndReturnError(nil) }
    }
    @discardableResult static func locateBinary() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    @MainActor
    static func handle(_ action: SetupCardView.SetupAction, model: AppModel) {
        switch action {
        case .openTerminal(let cmd): openTerminal(cmd)
        case .copy(let text): copyToPasteboard(text)
        case .openURL(let url): if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        case .rescan, .useAnyway: model.runFullSetupProbe(userInitiated: true)
        case .locate: locateBinary()
        }
    }
}

// MARK: - Preview — every card state (the handoff spec sheet)

#Preview("Bench health — every card state") {
    func m(_ id: String, _ name: String, _ state: SetupCardState, version: String? = nil,
           workers: [SetupCardModel.WorkerSeat] = [], shim: String? = nil, reason: String? = nil) -> SetupCardModel {
        SetupCardModel(driverId: id, name: name, route: "via \(id.replacingOccurrences(of: "_", with: "-"))",
                       version: version, state: state, workers: workers,
                       loginCommand: "codex", installHint: "brew install grok",
                       docsURL: "https://x.ai/cli", shimCommand: shim, probeReason: reason,
                       headlessTrust: nil)
    }
    let claude = m("claude_code", "Claude Code", .ready, version: "claude 1.2.4", workers: [
        .init(id: "o", name: "Opus 4.8", modelLabel: "opus-4.8", isPlanWriter: true),
        .init(id: "s", name: "Sonnet 4.6", modelLabel: "sonnet-4.6", isPlanWriter: false)])
    return ScrollView {
        VStack(spacing: 14) {
            SetupCardView(card: claude)
            SetupCardView(card: m("codex", "Codex", .needsLogin, version: "codex 0.9.1"))
            SetupCardView(card: m("codex", "Codex", .waiting, version: "codex 0.9.1"))
            SetupCardView(card: m("grok", "Grok", .notInstalled))
            SetupCardView(card: m("antigravity", "Antigravity", .needsPath, version: "agy",
                                  shim: "agy () { /Applications/Antigravity.app/Contents/MacOS/agy $@ }"))
            SetupCardView(card: m("codex", "Codex", .probeFailed, version: "codex 0.9.1",
                                  reason: "error: unknown flag --model (exit 2)"))
            SetupCardView(card: m("grok", "Grok", .queued))
            SetupCardView(card: m("claude_code", "Claude Code", .detecting))
            SetupCardView(card: m("antigravity", "Antigravity", .reprobing, version: "agy"))
        }
        .padding(20).frame(width: 440)
    }
    .background(ALColor.base)
}
