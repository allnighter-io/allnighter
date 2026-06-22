import SwiftUI
import AllnighterCore

/// The **Teams** workspace — the Send-to-team launcher ("showroom").
/// (docs/phases/wiring/design_handoff_send_to_team). G-T0 wires the toggle target
/// + a real TeamCard roster from Core; G-T1 brings the full fidelity (Recent &
/// favorites / Curated / Browse-all lenses, tiles with lineup + bench strip +
/// action bar). Cards are a projection of the existing team catalog — never
/// GUI-local content.
struct TeamsLauncherView: View {
    /// Called when a send starts — the host switches to the Inbox and the
    /// new running thread (sendRouting selects it).
    var onContinue: () -> Void = {}
    /// Open the team editor to create a new team.
    var onAddTeam: () -> Void = {}
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var selectedTeamId: String?
    /// Non-nil while the centered send-to-team composer modal is open.
    @State private var composingTeam: TeamCard?
    /// Non-nil while the Team Editor drawer is open (hover-pencil → review/customize).
    @State private var editingTeam: TeamCard?
    /// Browse-all family filter (nil = All). G-T1.
    @State private var familyFilter: String?

    private var cards: [TeamCard] {
        let userTeams = TeamCatalog.all.filter { !$0.isLabTeam }
        return TeamCardCatalogJSON.project(userTeams, family: nil,
                                           contractVersion: ContractRegistry.contractVersion).cards
    }

    /// Ready models, mirroring Team Studio's derivation (bench-ready ids).
    private var readyModels: [Model] {
        let readyIds = Set(appModel.composeBench.filter(\.ready).map(\.id))
        return appModel.models.filter { readyIds.contains($0.id) }
    }

    private var filteredCards: [TeamCard] {
        var result = familyFilter.map { f in cards.filter { $0.family == f } } ?? cards
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter { card in
                card.displayName.lowercased().contains(q)
                    || card.family.lowercased().contains(q)
                    || card.starterPrompts.contains { $0.lowercased().contains(q) }
                    || card.recommendedFor.contains { $0.lowercased().contains(q) }
            }
        }
        // Featured first: the Default Team, then favorites (in favorite order), then
        // the rest in catalog order.
        let favRank = Dictionary(uniqueKeysWithValues: appModel.favoriteTeamIds.enumerated().map { ($1, $0) })
        let defaultId = TeamCatalog.defaultRunTeam()?.id
        func rank(_ c: TeamCard) -> (Int, Int) {
            if c.teamId == defaultId { return (0, 0) }
            if let r = favRank[c.teamId] { return (1, r) }
            return (2, 0)
        }
        return result.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra != rb { return ra < rb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredCards) { card in
                            let isDefaultRun = card.teamId == TeamCatalog.defaultRunTeam()?.id
                            TeamCardTile(
                                card: card, selected: selectedTeamId == card.id,
                                isFavorite: appModel.isFavorite(card.teamId),
                                isDefaultRun: isDefaultRun,
                                onTap: {
                                    // One click = select + open the composer (fast path).
                                    selectedTeamId = card.id
                                    composingTeam = card
                                },
                                onEdit: { editingTeam = card },   // hover-pencil → editor drawer
                                onToggleFavorite: { if !isDefaultRun { appModel.toggleFavorite(card.teamId) } })
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let team = composingTeam {
                SendToTeamModal(team: team,  // (fixture-opened or card-click)
                                onSend: { routing in
                                    threads.sendRouting(routing, createThread: true)
                                    composingTeam = nil
                                    onContinue()   // switch to Inbox + the new thread
                                },
                                onDismiss: { composingTeam = nil })  // Esc → back to Teams, card stays highlighted
            }

            if let card = editingTeam, let base = TeamCatalog.get(card.teamId) {
                TeamEditorDrawer(
                    base: base, lane: ComposeLane(rawValue: card.family) ?? .code,
                    models: appModel.models, readyModels: readyModels,
                    onClose: { editingTeam = nil })
            }
        }
        .background(ALColor.base)
        .onAppear {
            #if DEBUG
            if GUIFixture.opensTeamsComposeModal, composingTeam == nil {
                let card = cards.first { $0.id == "signal_post_to_project" } ?? cards.first
                selectedTeamId = card?.id
                composingTeam = card
            }
            if GUIFixture.opensTeamsEditDrawer, editingTeam == nil {
                editingTeam = cards.first { $0.id == "code_core" } ?? cards.first
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEAMS · YOUR ROSTER")
                .font(ALFont.monoSm.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(ALColor.accentText)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Send to team").font(.system(size: 23, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                Text("Pick the crew. Your prompt comes next.")
                    .font(ALFont.body).foregroundStyle(ALColor.textMuted)
                Spacer()
            }
            searchRow
            familyTabs
        }
    }

    /// Search teams + an Add team action. (The bench is shown in the title bar, so
    /// it isn't repeated here.)
    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                TextField("Search teams, outcomes, or starter prompts…", text: $searchText)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }

            Button(action: onAddTeam) {
                Label("Add team", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 40)
            }
            .buttonStyle(.alPrimary)
        }
    }

    private var familyTabs: some View {
        HStack(spacing: 6) {
            familyChip(nil, "All")
            familyChip("signal", "Signal")
            familyChip("code", "Code")
            familyChip("design", "Design")
            familyChip("copy", "Copy")
        }
    }

    private func familyChip(_ family: String?, _ label: String) -> some View {
        let active = familyFilter == family
        return Button { familyFilter = family } label: {
            Text(label)
                .font(ALFont.label.weight(.medium))
                .foregroundStyle(active ? ALColor.textPrimary : ALColor.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? ALColor.accentSurface : ALColor.subtle, in: Capsule())
                .overlay(Capsule().strokeBorder(active ? ALColor.accentBorder : ALColor.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The centered "Send to team" composer modal (G-T2). One click on a launcher card
/// opens it with that team pre-loaded; it reuses `RoutingComposer` locked to
/// send-to-team. Send → `onSend` (the host runs it + lands on the Inbox thread);
/// Esc / click-scrim → `onDismiss` (back to Teams, card still highlighted).
private struct SendToTeamModal: View {
    let team: TeamCard
    var onSend: (ComposeRouting) -> Void
    var onDismiss: () -> Void

    private var lane: ComposeLane { ComposeLane(rawValue: team.family) ?? .code }

    var body: some View {
        ZStack {
            ALColor.overlay.ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 14) {
                header
                if !team.starterPrompts.isEmpty {
                    starterChips
                }
                RoutingComposer(
                    team: team.teamId, lane: lane, big: true, locksTeam: true,
                    onSend: onSend
                )
            }
            .padding(20)
            .frame(maxWidth: 640)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 32, y: 12)
            .padding(40)
        }
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SEND TO \(team.family.uppercased()) TEAM")
                .font(ALFont.monoSm.weight(.semibold)).tracking(1.0)
                .foregroundStyle(ALColor.accentText)
            Text(team.displayName).font(.system(size: 18, weight: .bold)).foregroundStyle(ALColor.textPrimary)
        }
    }

    private var starterChips: some View {
        HStack(spacing: 8) {
            ForEach(team.starterPrompts.prefix(2), id: \.self) { prompt in
                Text(prompt)
                    .font(ALFont.caption).foregroundStyle(ALColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(ALColor.subtle, in: Capsule())
                    .overlay(Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1))
            }
        }
    }
}

/// The Team Editor as a right-hand drawer over the launcher (#3). Reuses the
/// existing `TeamEditorView` (no new view) so hover-pencil → review/customize is
/// one click from the roster. Esc / tap-scrim → close; Save → close.
private struct TeamEditorDrawer: View {
    let base: TeamPreset
    let lane: ComposeLane
    let models: [Model]
    let readyModels: [Model]
    var onClose: () -> Void
    @State private var revertTick = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            ALColor.overlay.ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack {
                    Text("REVIEW & CUSTOMIZE").font(ALFont.monoSm.weight(.semibold)).tracking(1.0)
                        .foregroundStyle(ALColor.textFaint)
                    Spacer()
                    IconButton(systemImage: "xmark", accessibilityLabel: "Close", small: true, action: onClose)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider().overlay(ALColor.borderSubtle)
                TeamEditorView(
                    base: base, lane: lane, models: models, readyModels: readyModels,
                    // In the modal drawer, Cancel discards and closes (matches the X).
                    onCancel: onClose,
                    onSaved: { _ in onClose() }
                )
                .id("\(base.id)#\(revertTick)")
            }
            .frame(width: 600)
            .frame(maxHeight: .infinity)
            .background(ALColor.base)
            .overlay(alignment: .leading) { Rectangle().fill(ALColor.borderDefault).frame(width: 1) }
            .shadow(color: .black.opacity(0.45), radius: 32, x: -8)
        }
        .onExitCommand(perform: onClose)
    }
}

/// One team tile — a faithful-enough G-T0 card (family tag · name · outcome ·
/// lineup count · mutating marker). G-T1 adds the deduped model-logo lineup,
/// favorite star, last-run footer, and selection glow per the handoff.
private struct TeamCardTile: View {
    let card: TeamCard
    let selected: Bool
    var isFavorite: Bool = false
    var isDefaultRun: Bool = false
    var onTap: () -> Void
    var onEdit: () -> Void
    var onToggleFavorite: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        // NOT a Button: the card body uses a tap gesture (compose) so the
        // hover-revealed pencil can be its own Button (review/customize) without
        // nesting interactive controls (the handoff's nested-button trap).
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: familySymbol).font(.system(size: 11))
                    Text(card.family.capitalized).font(ALFont.monoSm)
                    if card.mutating {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Label("Writes", systemImage: "lock").font(ALFont.monoSm).foregroundStyle(ALColor.accentText)
                            if let source = card.executionSourceId {
                                Text(source).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                            }
                        }
                    }
                }
                .foregroundStyle(ALColor.textMuted)

                Text(card.displayName).font(.system(size: 15, weight: .bold)).foregroundStyle(ALColor.textPrimary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.accentText)
                    Text("returns").font(ALFont.caption).foregroundStyle(ALColor.textMuted)
                    Text(card.outputKind).font(ALFont.caption.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                }

                Divider().overlay(ALColor.borderSubtle)

                HStack(spacing: 8) {
                    Text(card.mutating ? "1 agent" : "\(card.workerCount) workers")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    if card.mutating {
                        Text("· mutating").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    }
                    Spacer()
                    // Favorite star — featured first in this grid + the composer.
                    if isFavorite || isDefaultRun || hovering {
                        Button(action: onToggleFavorite) {
                            Image(systemName: (isFavorite || isDefaultRun) ? "star.fill" : "star").font(.system(size: 12))
                                .foregroundStyle((isFavorite || isDefaultRun) ? ALColor.textSecondary : ALColor.textMuted)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDefaultRun)
                        .help(isDefaultRun ? "The Default Team is always featured" : (isFavorite ? "Remove from favorites" : "Add to favorites"))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Hover-revealed edit affordance → opens the Team Editor drawer.
            if hovering {
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                        .foregroundStyle(ALColor.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                        .overlay(RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderDefault, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Review & customize this team")
                .padding(10)
            }
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: ALRadius.lg)
                .strokeBorder(selected ? ALColor.accentBorder : (hovering ? ALColor.borderStrong : ALColor.borderSubtle), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private var familySymbol: String {
        switch card.family {
        case "signal": return "antenna.radiowaves.left.and.right"
        case "code": return "hammer"
        case "design": return "photo"
        case "copy": return "doc.text"
        default: return "person.2"
        }
    }
}
