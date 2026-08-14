import AppKit
import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Settings › **Use from your CLI** — ONE page (founder ruling): the dynamic
/// hook, the host teaching table (absorbs the former "Teach your CLIs" row),
/// the reframe, worked asks, and the capacity closer.
///
/// Approved design: `docs/design-system/explorations/use-from-your-cli/proposal.html`.
/// Copy in the reframe / ask / closer sections is founder-approved verbatim;
/// only the headline, host rows, rule count, chip list and capacity bars are
/// computed from real state (`docs/design-system/explorations/use-from-your-cli/proposal.html` §Proposal notes).
struct UseFromCLIView: View {
    @Environment(AppModel.self) private var appModel

    @State private var preview: GlobalTeachingInstaller.Preview?
    @State private var results: [String: GlobalTeachingInstaller.ApplyResult] = [:]
    @State private var busyHostId: String?
    @State private var bulkBusy = false
    @State private var showDisclosure = false
    @State private var copiedDisclosure = false
    @State private var copiedBlock = false
    @State private var copiedStarter = false
    @State private var contentWidth: CGFloat = 900
    @State private var capacityModel = CapacityStripModel()

    /// Below this content width the host row's path column has nowhere to sit —
    /// reflow the row instead of truncating (known defect this pane fixes).
    private static let narrowBreakpoint: CGFloat = 660

    private var narrow: Bool { contentWidth < Self.narrowBreakpoint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                breadcrumb
                hero
                cliChips
                setupCard
                pasteCard
                reframeSection
                askSection
                capacitySection
                quietClose
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .padding(.bottom, 56)
            .background(WidthReader(width: $contentWidth))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear { reload() }
        .task { await capacityModel.loadLive() }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Text(ChromeCopy.settings).foregroundStyle(ALColor.textFaint)
            Text("›").foregroundStyle(ALColor.textFaint).opacity(0.5)
            Text(ChromeCopy.useFromCLI).foregroundStyle(ALColor.textMuted).fontWeight(.medium)
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.6)
        .textCase(.uppercase)
        .padding(.bottom, 22)
    }

    // MARK: - Hero (headline + deck; above-the-fold budget)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline.title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(ALColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = headline.subline {
                Text(sub)
                    .font(.system(size: 14))
                    .foregroundStyle(ALColor.textMuted)
            }
            (
                Text("One short block, taught once, and ")
                    .foregroundStyle(ALColor.textSecondary)
                + Text("your CLIs can put each other to work")
                    .foregroundStyle(ALColor.textPrimary)
                    .fontWeight(.medium)
                + Text(".")
                    .foregroundStyle(ALColor.textSecondary)
            )
            .font(.system(size: 14))
            .padding(.top, 8)
        }
        .padding(.bottom, 18)
    }

    // MARK: - Dynamic headline (fallback ladder — never names an undetected CLI)

    private struct Headline {
        var title: String
        var subline: String?
    }

    /// Detection source: the three GLOBAL teaching hosts, "detected" meaning the
    /// CLI is actually installed on this Mac (real driver probe state) — not
    /// merely a host the installer knows how to write.
    private var detectedTaughtHosts: [(hostId: String, displayName: String)] {
        let driverIdByHost: [String: String] = [
            "claude": "claude_code",
            "cursor": "cursor_agent",
            "codex": "codex",
        ]
        return TeachingInstalledCheck.hostMatrix.compactMap { target in
            let hostId = target.id
            guard let driverId = driverIdByHost[hostId] else { return nil }
            guard let status = appModel.toolStatus(for: driverId)?.status,
                  status != .notInstalled else { return nil }
            return (hostId, GlobalTeachingInstaller.displayName(for: hostId))
        }
    }

    private var headline: Headline {
        let hosts = detectedTaughtHosts
        switch hosts.count {
        case 0:
            return Headline(
                title: "Access any model, from any CLI you already pay for.",
                subline: nil
            )
        case 1:
            return Headline(
                title: "Access every model you pay for from inside \(hosts[0].displayName).",
                subline: nil
            )
        default:
            let home = hosts[0].displayName
            let other = hosts[1].displayName
            let rest = hosts.dropFirst(2).map(\.displayName)
            let sub = rest.isEmpty
                ? "It runs both ways."
                : "It runs both ways — and \(rest.joined(separator: ", ")) \(rest.count == 1 ? "is" : "are") on the bench too."
            return Headline(
                title: "Access every \(other) model from inside \(home).",
                subline: sub
            )
        }
    }

    // MARK: - CLI chips (real bench — the 9 headless-CLI drivers Allnighter loads)

    /// Readiness as the CLIs panel states it — green ready, amber needs
    /// attention, grey absent.
    ///
    /// The strip's "three colours only, no green" law is written on
    /// `CapacityStripView` and scoped to the capacity strip, where green would
    /// imply a healthy *quota*. It is not an app-wide ban: `ALColor.statusDone`
    /// is the token for "done / healthy" and the CLIs panel already uses it for
    /// ready drivers. Two surfaces describing the same driver must not disagree
    /// about its colour.
    private enum ChipState {
        case ready, needsAttention, absent
    }

    private func chipState(forDriver driverId: String) -> ChipState {
        guard let status = appModel.toolStatus(for: driverId)?.status else { return .absent }
        if status.isSmokeReady { return .ready }
        if case .notInstalled = status { return .absent }
        return .needsAttention
    }

    /// Chips use the manifest's `shortName` — nine precise `displayName`s
    /// ("Codex / ChatGPT", "Grok Build CLI") wrap the row onto two lines, and the
    /// "CLI"/"Code"/"Agent" suffixes carry nothing once the reader can see they
    /// are all CLIs. The short name is a manifest field (AgentOS SSOT), not a
    /// suffix stripped here: a view must never invent product naming.
    private var benchChips: [(id: String, name: String, state: ChipState)] {
        appModel.registry.all
            .filter { $0.kind == .headlessCLI }
            .sorted { $0.shortName.localizedCaseInsensitiveCompare($1.shortName) == .orderedAscending }
            .map { ($0.id, $0.shortName, chipState(forDriver: $0.id)) }
    }

    private var benchCLICount: Int {
        appModel.registry.all.filter { $0.kind == .headlessCLI }.count
    }

    /// Enabled models only — the same set `alln models` reports.
    ///
    /// `appModel.models` is the raw catalog and includes disabled entries, so
    /// counting it advertised 40 on a machine where the CLI answers 27. Two
    /// surfaces describing one bench must not disagree, and the larger number is
    /// the dishonest one: it counts models the user cannot dispatch to.
    /// `models.filter(\.enabled)` is the codebase's definition of the bench
    /// (`RunService.readyModels`, `TeamService.readyModels`, `TeamAssembler`).
    private var benchModelCount: Int { appModel.models.filter(\.enabled).count }

    private var cliChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8) {
                ForEach(benchChips, id: \.id) { chip in
                    chipView(chip.name, state: chip.state)
                }
            }
            if benchCLICount > 0, benchModelCount > 0 {
                Text(benchLadderLine)
                    .font(.system(size: 11))
                    .foregroundStyle(ALColor.textFaint)
            }
        }
        .padding(.bottom, 18)
    }

    private func chipView(_ name: String, state: ChipState) -> some View {
        let dot: Color = {
            switch state {
            case .ready: return ALColor.statusDone
            case .needsAttention: return ALColor.accent
            case .absent: return ALColor.textFaint
            }
        }()
        let present = state != .absent
        return HStack(spacing: 7) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(present ? ALColor.textPrimary : ALColor.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(ALColor.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(present ? ALColor.borderStrong : ALColor.borderDefault, lineWidth: 1)
        }
    }

    /// States the ladder outright, so the gap between "9 CLIs" and the smaller
    /// number of one-click hosts explains itself instead of reading as a
    /// shortfall. The old line ("N CLIs · N models") sat directly above
    /// "3 hosts found on this Mac" and made the product look like it supported 3.
    private var benchLadderLine: String {
        let oneClick = oneClickHosts.count
        let rest = max(0, benchCLICount - oneClick)
        var parts = ["\(benchCLICount) CLIs · \(benchModelCount) models"]
        if oneClick > 0 {
            parts.append("\(oneClick) teach in one click, the other \(rest) take one paste")
        }
        parts.append("your logins, your subscriptions. No API keys, ever.")
        return parts.joined(separator: " · ")
    }

    // MARK: - Setup card (host table + the page's one amber primary)

    private var hosts: [GlobalTeachingInstaller.HostPreview] { preview?.hosts ?? [] }

    /// Rung 1 — hosts we can write a global context file for, in one click.
    private var oneClickHosts: [GlobalTeachingInstaller.HostPreview] {
        hosts.filter { !$0.unsupported }
    }

    /// Rung 2 — everything else on the bench. A host with no global file (Codex)
    /// is not a special case here; it is the first row of the normal path.
    ///
    /// The page used to show only the three hosts the installer knows and lead
    /// with "3 hosts found on this Mac" directly under a chip row listing nine
    /// CLIs — which reads as "Allnighter supports 3 of your 9". It works from
    /// all of them; two of them merely accept a button.
    private var pasteDriverIds: [String] {
        let oneClick: Set<String> = ["claude_code", "cursor_agent"]
        return benchChips.map(\.id).filter { !oneClick.contains($0) }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            setupHead
            ForEach(oneClickHosts) { host in
                hostRow(host)
                if host.id != oneClickHosts.last?.id {
                    Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                }
            }
            setupFoot
        }
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1)
        }
        .padding(.bottom, 8)
    }

    private var setupHead: some View {
        HStack(alignment: .center, spacing: 24) {
            Text(setupLead)
                .font(.system(size: 13))
                .foregroundStyle(ALColor.textSecondary)
                .frame(maxWidth: 420, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(TeachingSnippet.reflexLines.count) rules per file, fenced by markers")
                Text("read them first · remove in one click")
            }
            .font(.system(size: 11))
            .foregroundStyle(ALColor.textFaint)
            .multilineTextAlignment(.trailing)
            Button {
                installAll()
            } label: {
                Text(bulkBusy ? "Teaching…" : "Teach all CLIs")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.alPrimary(small: false))
            .disabled(bulkBusy || busyHostId != nil || (preview?.installable.isEmpty ?? true))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
    }

    /// Two-clause lead, built only from real counts — never the mock's fixed prose.
    private var setupLead: String {
        let all = oneClickHosts
        let total = all.count
        guard total > 0 else { return "No one-click hosts on this Mac." }
        let stale = all.filter { $0.installAction == .repair }.count
        let notTaught = all.filter { $0.installAction == .append }.count
        let base = "\(total) CLI\(total == 1 ? "" : "s") here teach in one click."
        switch (stale, notTaught) {
        case (0, 0):
            return base + " All current."
        case let (s, 0) where s > 0:
            return base + " \(s) \(s == 1 ? "is" : "are") out of date."
        case let (0, n) where n > 0:
            return base + " \(n) \(n == 1 ? "hasn't" : "haven't") been taught yet."
        default:
            return base + " \(stale) \(stale == 1 ? "is" : "are") out of date, \(notTaught) \(notTaught == 1 ? "hasn't" : "haven't") been taught yet."
        }
    }

    @ViewBuilder
    private func hostRow(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        if narrow {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    hostNameBlock(host)
                    Spacer(minLength: 8)
                    statePill(host)
                }
                hostPathText(host)
                HStack {
                    Spacer(minLength: 0)
                    hostActions(host)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
        } else {
            HStack(spacing: 16) {
                hostNameBlock(host).frame(width: 170, alignment: .leading)
                hostPathText(host).frame(maxWidth: .infinity, alignment: .leading)
                statePill(host).frame(width: 130, alignment: .leading)
                hostActions(host)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
        }
    }

    private func hostNameBlock(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(GlobalTeachingInstaller.displayName(for: host.hostId))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ALColor.textPrimary)
            Text(hostSubtitle(host))
                .font(.system(size: 11))
                .foregroundStyle(ALColor.textFaint)
        }
    }

    private func hostSubtitle(_ host: GlobalTeachingInstaller.HostPreview) -> String {
        host.unsupported ? "reads AGENTS.md per project" : "global context"
    }

    private func hostPathText(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        Group {
            if host.unsupported {
                Text(host.unsupportedReason ?? host.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ALColor.textFaint)
            } else {
                Text(displayPath(host.path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ALColor.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func statePill(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        let (label, fg, bg, dot): (String, Color, Color, Color?) = {
            if host.unsupported {
                return ("Manual", ALColor.textFaint, .clear, nil)
            }
            switch host.installAction {
            case .noOp:
                // "Ready", not "Taught · up to date": one word so the pill stops
                // wrapping to two lines (which was breaking the row rhythm and
                // the pill column's vertical edge), green because grey read as
                // disabled, and the same word the CLIs panel already uses for
                // this state.
                return ("Ready", ALColor.statusDone, ALColor.statusDone.opacity(0.12), ALColor.statusDone)
            case .repair:
                return ("Out of date", ALColor.accentText, ALColor.accentSurface, ALColor.accent)
            case .append:
                return ("Not taught", ALColor.textMuted, ALColor.textPrimary.opacity(0.05), ALColor.textFaint)
            case .requiresManual:
                return ("Needs a manual fix", ALPalette.red400, ALColor.dangerSurface, ALPalette.red500)
            case .unsupported, .remove:
                return ("Manual", ALColor.textFaint, .clear, nil)
            }
        }()
        return HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(label)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(bg, in: Capsule())
        .overlay {
            if host.unsupported {
                Capsule().strokeBorder(ALColor.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    @ViewBuilder
    private func hostActions(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        HStack(spacing: 8) {
            if let result = results[host.hostId], !result.success {
                Text("Failed: \(result.detail)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ALPalette.red400)
                    .lineLimit(1)
            }
            if host.unsupported {
                Button {
                    copyBootstrap(host: host.hostId)
                } label: {
                    Text("Copy block")
                }
                .buttonStyle(.alGhost)
            } else {
                switch host.installAction {
                case .append:
                    Button { runInstall(host) } label: {
                        Text(busyHostId == host.hostId ? "Teaching…" : "Teach")
                    }
                    .buttonStyle(.alGhost)
                    .disabled(busyHostId != nil || bulkBusy)
                case .repair:
                    Button { runInstall(host) } label: {
                        Text(busyHostId == host.hostId ? "Updating…" : "Update")
                    }
                    .buttonStyle(.alGhost)
                    .disabled(busyHostId != nil || bulkBusy)
                case .noOp:
                    if host.canRemove {
                        Button { runRemove(host) } label: {
                            Text(busyHostId == host.hostId ? "Removing…" : "Remove")
                        }
                        .buttonStyle(.alGhost)
                        .disabled(busyHostId != nil || bulkBusy)
                    }
                case .requiresManual:
                    Text("See detail").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                case .unsupported, .remove:
                    EmptyView()
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
    }

    /// `alln install-cli` is only worth mentioning when `alln` is NOT yet on
    /// PATH. On a machine that already has it — which is every machine that got
    /// this far — leading with it makes the most prominent instruction the one
    /// thing the user does not need. `Bootstrap.snippet(onPath:)` has taken this
    /// flag all along; nobody had wired the detection.
    private var alreadyOnPath: Bool {
        InstallCLI.resolveOnPath(
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
        ) != nil
    }

    @ViewBuilder
    private var setupFoot: some View {
        (
            alreadyOnPath
            ? Text("Prefer the terminal? ").foregroundStyle(ALColor.textFaint)
                + Text("alln bootstrap").foregroundStyle(ALColor.textMuted)
                + Text(" prints this same block, paste-ready.").foregroundStyle(ALColor.textFaint)
            : Text("alln isn't on your PATH yet — ").foregroundStyle(ALColor.textFaint)
                + Text("alln install-cli").foregroundStyle(ALColor.textMuted)
                + Text(" fixes that, then ").foregroundStyle(ALColor.textFaint)
                + Text("alln bootstrap").foregroundStyle(ALColor.textMuted)
                + Text(" prints this block.").foregroundStyle(ALColor.textFaint)
        )
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.subtle)
    }

    // MARK: - Rung 2 + 3: every other CLI (the majority path, not a footnote)

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Every other CLI takes one paste.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ALColor.textPrimary)
                    Text(pasteLead)
                        .font(.system(size: 12))
                        .foregroundStyle(ALColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button { copyBootstrap(host: nil) } label: {
                        Text(copiedBlock ? "Copied" : "Copy the block")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.alSecondary(small: false))
                    Button { copyStarter() } label: {
                        Text(copiedStarter ? "Copied" : "Copy a starter prompt")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.alGhost)
                }
            }

            if !pasteDriverIds.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(benchChips.filter { pasteDriverIds.contains($0.id) }, id: \.id) { chip in
                        Text(chip.name)
                            .font(.system(size: 11))
                            .foregroundStyle(ALColor.textFaint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(ALColor.base, in: Capsule())
                    }
                }
            }

            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)

            // Rung 3 — the zero-setup answer. True in any agent, right now.
            (
                Text("Or don't paste anything: tell any agent ")
                    .foregroundStyle(ALColor.textMuted)
                + Text("read `alln menu --json`")
                    .foregroundStyle(ALColor.textPrimary)
                    .fontWeight(.medium)
                + Text(" and it will find the bench on its own.")
                    .foregroundStyle(ALColor.textMuted)
            )
            .font(.system(size: 12))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1)
        }
        .padding(.bottom, 8)
    }

    private var pasteLead: String {
        let n = pasteDriverIds.count
        guard n > 0 else {
            return "Same block, pasted into that CLI's context file. It works from anywhere `alln` is on PATH."
        }
        return "\(n) of the CLIs on your bench have no global file we can write for you — including Codex. Same block, you paste it once into that CLI's own context file."
    }

    private func displayPath(_ path: String?) -> String {
        guard let path else { return "(no path)" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: - The reframe (static, approved copy — below the fold)

    private var reframeSection: some View {
        sectionBlock {
            Text("You already pay for most of this bench.")
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(ALColor.textPrimary)
            prose("Today those subscriptions don't know about each other. You work in one, and when you want a second opinion you open another window, paste the context in by hand, and paste the answer back. When one hits its limit, you stop — while the others sit idle with room you've already paid for.")
            prose("A well-known hack wires exactly one pair together: Codex inside Claude Code. This page is the general case — any of your CLIs can call any of the others, one at a time or five in parallel.")
        }
    }

    // MARK: - "Then you just ask" (static, approved copy)

    private struct Ask {
        var said: String
        var happens: String
        var command: String
    }

    private static let asks: [Ask] = [
        Ask(
            said: "Ask GPT Sol to review this doc.",
            happens: "Your agent hands the doc to a GPT Sol seat and brings the review back into your session. You never leave the window.",
            command: "alln run \"…\" --model model_gpt_sol"
        ),
        Ask(
            said: "Do a full spec review on this doc and get it implementation ready.",
            happens: "Spec Review: 6 seats from different vendors pressure-test the doc in parallel and return one hardened packet. Read-only.",
            command: "alln run \"…\" --team code_spec_review"
        ),
        Ask(
            said: "Have DeepSeek V4 Pro implement this doc. Commit after every slice — I'll PM.",
            happens: "DeepSeek takes the dev seat and builds, committing after every slice; you stay in your own CLI as the PM, reviewing as the commits land.",
            command: "alln loop start \"…\" --pm caller"
        ),
        Ask(
            said: "Which of my subscriptions still has room this week?",
            happens: "One answer across every CLI you're signed into — real weekly and 5-hour headroom, read from your own accounts.",
            command: "alln capacity"
        ),
    ]

    private var askSection: some View {
        sectionBlock {
            Text("THEN YOU JUST ASK")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(ALColor.textFaint)
            Text("No new tool to learn. You talk to the CLI you already talk to.")
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(ALColor.textPrimary)
                .padding(.top, 4)
            prose("Once taught, your agent knows when to reach for the bench. These are real asks and exactly what happens — the command underneath is what your agent runs, not something you have to type.")

            VStack(spacing: 10) {
                ForEach(Self.asks, id: \.said) { ask in
                    askCard(ask)
                }
            }
            .padding(.top, 16)

            (
                Text("The write rule: ").foregroundStyle(ALColor.textSecondary).fontWeight(.semibold)
                + Text("research teams are parallel and read-only. Mutation is always a single worker per repo, locked. Ten models can advise you at once; only one can ever touch your files.")
                    .foregroundStyle(ALColor.textMuted)
            )
            .font(.system(size: 11.5))
            .padding(.top, 14)
        }
    }

    private func askCard(_ ask: Ask) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text("“\(ask.said)”")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ALColor.textPrimary)
                .frame(width: 300, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(ask.happens)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.textSecondary)
                Text(ask.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ALColor.base, in: RoundedRectangle(cornerRadius: ALRadius.xs))
                    .overlay {
                        RoundedRectangle(cornerRadius: ALRadius.xs).strokeBorder(ALColor.borderSubtle, lineWidth: 1)
                    }
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1)
        }
    }

    // MARK: - Capacity closer (real CapacityStripModel — copy-only if unsampled)

    private var capacityRows: [CapacityBenchRow] {
        Array(capacityModel.rows.prefix(4))
    }

    /// States the age instead of asserting "live".
    ///
    /// The old caption said "live values from your own accounts" over whatever
    /// `loadLive()` returned — but that reads `resident.currentSnapshot()`, a
    /// STORED snapshot, and the model ships `needsLiveRefresh = true` precisely
    /// to say "these are placeholders". Naming the age is both honest and the
    /// stronger claim: "read from your accounts 4m ago" is specific, where
    /// "live" is a boast that dies the moment the number is stale.
    private var capacityCaption: String {
        guard let first = capacityRows.first else { return "Weekly headroom per CLI." }
        let age = CapacityStripRenderer.ageLabel(for: first, now: capacityModel.now)
        return "Weekly headroom per CLI — read from your accounts \(age)."
    }

    private var hasCapacityData: Bool {
        capacityModel.featureEnabled
            && capacityRows.contains { row in row.pools.contains { $0.dashboardRemainingPercent != nil } }
    }

    private var capacitySection: some View {
        sectionBlock {
            Text("THE PART A HAND-ROLLED SETUP CAN'T DO")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(ALColor.textFaint)

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("It knows which subscription still has room.")
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(ALColor.textPrimary)
                        .padding(.top, 4)
                    prose("`alln capacity` reads each vendor's real weekly and 5-hour headroom. So when your agent reaches for another model, it doesn't reach blindly — it can take the seat with quota to spare and leave alone the limit you're about to hit.")
                    prose("Every week, allowance you paid for expires unused on the subscriptions you didn't open. This is how it gets spent.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                capacityCard
                    .frame(width: 300)
            }
        }
    }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("alln capacity")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ALColor.textMuted)
            if !capacityModel.featureEnabled {
                Text("Capacity checks are off. Turn them on and this shows real weekly headroom for every CLI you're signed into.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ALColor.textMuted)
                Button { capacityModel.enableFeature() } label: {
                    Text("Enable capacity").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.alSecondary(small: true))
            } else if capacityModel.needsLiveRefresh || !hasCapacityData {
                // The model itself flags this state: "Launch showed placeholders
                // — user should tap Refresh for live numbers." Never caption a
                // stored snapshot as live; ask for the probe instead.
                Text("We haven't read your accounts yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ALColor.textSecondary)
                Text("One check reads the real weekly and 5-hour headroom from every CLI you're signed into.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ALColor.textMuted)
                Button { capacityModel.refreshAll() } label: {
                    HStack(spacing: 6) {
                        if capacityModel.isRefreshingAll {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        }
                        Text(capacityModel.isRefreshingAll ? "Checking…" : "Check my capacity")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.alSecondary(small: false))
                .disabled(capacityModel.isRefreshingAll)
                .padding(.top, 2)
            } else {
                ForEach(capacityRows, id: \.source) { row in
                    capacityLine(row)
                }
                HStack(spacing: 6) {
                    Text(capacityCaption)
                        .font(.system(size: 10))
                        .foregroundStyle(ALColor.textFaint)
                    Spacer(minLength: 0)
                    Button { capacityModel.refreshAll() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ALColor.textFaint)
                    }
                    .buttonStyle(.plain)
                    .disabled(capacityModel.isRefreshingAll)
                    .help("Re-read capacity from your accounts")
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1)
        }
    }

    private func capacityLine(_ row: CapacityBenchRow) -> some View {
        let remaining = row.pools.first { $0.dashboardRemainingPercent != nil }?.dashboardRemainingPercent
        let color = CapacityStripRenderer.color(for: row, now: capacityModel.now)
        return HStack(spacing: 12) {
            Text(CapacityStripRenderer.displayName(for: row.source))
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.textSecondary)
                .frame(width: 86, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ALColor.active)
                    if let remaining {
                        Capsule()
                            .fill(color == .amber ? ALColor.accent : ALColor.textMuted)
                            .frame(width: max(2, geo.size.width * CGFloat(min(100, max(0, remaining)) / 100)))
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Quiet close + the one disclosure

    private var quietClose: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                .padding(.top, 36)
            prose("After this page, the app is optional. Runs start, stream, and finish in your terminal; this window is a place to watch them and tune teams, not a place you have to be. If it stays closed for a month while alln gets used every day, that is the product working.")
                .padding(.top, 18)

            DisclosureGroup(isExpanded: $showDisclosure) {
                disclosureBody
            } label: {
                Text("What exactly gets written to the context files")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ALColor.textFaint)
            }
            .tint(ALColor.textFaint)
        }
    }

    private var disclosureBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The full teaching block, shown here verbatim before anything is written — the same text `alln bootstrap` prints. It never appears on the page above.")
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.textFaint)

            ScrollView {
                Text(TeachingSnippet.wrap())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ALColor.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 220)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1)
            }

            Button {
                copyDisclosure()
            } label: {
                Text(copiedDisclosure ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.alGhost)
        }
        .padding(.top, 10)
    }

    // MARK: - Shared prose helpers

    private func sectionBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.top, 44)
    }

    private func prose(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(ALColor.textSecondary)
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.top, 6)
    }

    // MARK: - Actions

    private func reload() {
        if let scratchHome = Self.fixtureScratchHome() {
            preview = GlobalTeachingInstaller.preview(homeDirectory: scratchHome)
        } else {
            preview = GlobalTeachingInstaller.preview()
        }
    }

    /// GUI Visual Proof Gate: a deterministic mix of host states (taught /
    /// out-of-date / unsupported — Codex has no v1 global write regardless) so
    /// the layout-watcher sees every pill shape, independent of this machine's
    /// real `~/.claude` / `~/.cursor`. DEBUG only; `GUIFixture.active` is always
    /// nil in Release, so this never touches disk outside a proof run.
    private static func fixtureScratchHome() -> URL? {
        guard GUIFixture.active == "settings-use-from-cli" else { return nil }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("alln-fixture-use-from-cli", isDirectory: true)
        try? fm.removeItem(at: root)
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        let cursorDir = root.appendingPathComponent(".cursor/rules", isDirectory: true)
        try? fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        // Claude: stale — an older schema version, so the row renders "Out of date".
        let staleBlock = TeachingSnippet.wrap(version: TeachingSnippet.schemaVersion - 1)
        try? staleBlock.write(to: claudeDir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        // Cursor: current — the row renders "Taught · up to date".
        try? TeachingSnippet.wrap().write(
            to: cursorDir.appendingPathComponent("allnighter.mdc"), atomically: true, encoding: .utf8
        )

        // Codex: always unsupported in v1 — the row renders "Manual" regardless of disk state.
        return root
    }

    private func runInstall(_ host: GlobalTeachingInstaller.HostPreview) {
        busyHostId = host.hostId
        let result = GlobalTeachingInstaller.applyInstall(
            hostId: host.hostId,
            expectedContentHash: host.contentHash
        )
        results[host.hostId] = result
        busyHostId = nil
        reload()
    }

    private func runRemove(_ host: GlobalTeachingInstaller.HostPreview) {
        busyHostId = host.hostId
        let result = GlobalTeachingInstaller.applyRemove(
            hostId: host.hostId,
            expectedContentHash: host.contentHash
        )
        results[host.hostId] = result
        busyHostId = nil
        reload()
    }

    private func installAll() {
        guard let snapshot = preview else { return }
        bulkBusy = true
        let applied = GlobalTeachingInstaller.installAllSupported(preview: snapshot)
        for r in applied { results[r.hostId] = r }
        bulkBusy = false
        reload()
    }

    /// `host: nil` = the generic block for any CLI (rung 2's Copy button).
    private func copyBootstrap(host: String?) {
        let ctx = Bootstrap.liveContext()
        let target = host.flatMap { Bootstrap.Host(argument: $0) } ?? .generic
        let text = Bootstrap.render(
            host: target,
            binaryPath: ctx.binaryPath,
            onPath: ctx.onPath
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if host == nil {
            copiedBlock = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copiedBlock = false }
        }
    }

    /// The one-time prompt — a different artifact from the block, on purpose.
    /// See `Bootstrap.starterPrompt`.
    private func copyStarter() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Bootstrap.starterPrompt, forType: .string)
        copiedStarter = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copiedStarter = false }
    }

    private func copyDisclosure() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TeachingSnippet.wrap(), forType: .string)
        copiedDisclosure = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copiedDisclosure = false
        }
    }
}

// MARK: - Width probe (narrow-width reflow)

private struct WidthReader: View {
    @Binding var width: CGFloat
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, new in width = new }
        }
    }
}

// MARK: - Flow layout (CLI chip wrap)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
