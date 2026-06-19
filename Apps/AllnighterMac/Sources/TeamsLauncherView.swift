import SwiftUI
import AllnighterCore

/// The **Teams** workspace — the Send-to-team launcher ("showroom").
/// (docs/phases/wiring/design_handoff_send_to_team). G-T0 wires the toggle target
/// + a real TeamCard roster from Core; G-T1 brings the full fidelity (Recent &
/// favorites / Curated / Browse-all lenses, tiles with lineup + bench strip +
/// action bar). Cards are a projection of the existing team catalog — never
/// GUI-local content.
struct TeamsLauncherView: View {
    /// Called when a send is dispatched — the host switches to the Inbox and the
    /// new running thread (sendRouting selects it).
    var onContinue: () -> Void = {}
    @Environment(ThreadsViewModel.self) private var threads
    @State private var selectedTeamId: String?
    /// Non-nil while the centered send-to-team composer modal is open.
    @State private var composingTeam: TeamCard?

    private var cards: [TeamCard] {
        TeamCardCatalogJSON.project(TeamCatalog.all, family: nil,
                                    contractVersion: ContractRegistry.contractVersion).cards
    }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(cards) { card in
                            TeamCardTile(card: card, selected: selectedTeamId == card.id) {
                                // One click = select + open the composer (fast path).
                                selectedTeamId = card.id
                                composingTeam = card
                            }
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
        }
        .background(ALColor.base)
        .onAppear {
            #if DEBUG
            if GUIFixture.opensTeamsComposeModal, composingTeam == nil {
                let card = cards.first { $0.id == "signal_post_to_project" } ?? cards.first
                selectedTeamId = card?.id
                composingTeam = card
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEAMS · YOUR ROSTER")
                .font(ALFont.monoSm.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(ALColor.accentText)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Send to team").font(.system(size: 23, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                Text("Pick the crew. Your prompt comes next.")
                    .font(ALFont.body).foregroundStyle(ALColor.textMuted)
            }
        }
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
                    mode: .sendToTeam, lane: lane, team: team.teamId, big: true,
                    defaultMode: .sendToTeam, lockedSendToTeam: true,
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

/// One team tile — a faithful-enough G-T0 card (family tag · name · outcome ·
/// lineup count · posture/mutating). G-T1 adds the deduped model-logo lineup,
/// favorite star, last-run footer, and selection glow per the handoff.
private struct TeamCardTile: View {
    let card: TeamCard
    let selected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: familySymbol).font(.system(size: 11))
                    Text(card.family.capitalized).font(ALFont.monoSm)
                    if card.mutating {
                        Spacer()
                        Label("Execute", systemImage: "lock").font(ALFont.monoSm).foregroundStyle(ALColor.accentText)
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

                HStack {
                    Text("\(card.workerCount) workers").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    Spacer()
                    Text(card.posture).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: ALRadius.lg)
                    .strokeBorder(selected ? ALColor.accentBorder : ALColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
