import SwiftUI
import AllnighterCore

/// The **Teams** workspace — the Send-to-team launcher ("showroom").
/// (docs/phases/wiring/design_handoff_send_to_team). G-T0 wires the toggle target
/// + a real TeamCard roster from Core; G-T1 brings the full fidelity (Recent &
/// favorites / Curated / Browse-all lenses, tiles with lineup + bench strip +
/// action bar). Cards are a projection of the existing team catalog — never
/// GUI-local content.
struct TeamsLauncherView: View {
    var onContinue: () -> Void = {}
    @State private var selectedTeamId: String?

    private var cards: [TeamCard] {
        TeamCardCatalogJSON.project(TeamCatalog.all, family: nil,
                                    contractVersion: ContractRegistry.contractVersion).cards
    }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(cards) { card in
                        TeamCardTile(card: card, selected: selectedTeamId == card.id) {
                            selectedTeamId = card.id
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALColor.base)
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
