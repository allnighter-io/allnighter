import SwiftUI
import AllnighterCore

// Settings — the Team configuration surface. Reached from "Manage team" (Team
// dropdown) and, later, the title-bar health badge. The whole app is lane-first
// (Build / Design / Copy), so the nav groups by lane: one CLIs page on top
// (lane-agnostic — sources feed every lane), then per-lane Teams + Skills.
//
// CLIs reuses the existing `TeamReadinessView` (the shipped CLI-setup/readiness
// surface). Teams and Skills read `TeamCatalog` / `SkillCatalog` — the shell never
// invents team/skill truth.

/// One destination in the Studio. Teams/Skills are always lane-scoped (every team
/// and skill belongs to exactly one lane — Work_Order_Team_Model.md).
enum StudioRoute: Hashable {
    case clis
    case teams(ComposeLane)
    case skills(ComposeLane)
}

struct TeamStudioView: View {
    var onDone: () -> Void
    @State private var route: StudioRoute

    init(initialRoute: StudioRoute = .clis, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        HStack(spacing: 0) {
            StudioNav(route: $route, onDone: onDone)
                .frame(width: 232)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .clis:
            // The shipped CLI-setup / readiness surface, embedded as the CLIs page.
            TeamReadinessView(focusDriverId: nil, onClose: onDone, onAddSource: {})
        case .teams(let lane):
            StudioTeamListView(lane: lane)
        case .skills(let lane):
            StudioSkillListView(lane: lane)
        }
    }
}

// MARK: - Left nav (lane-first)

private struct StudioNav: View {
    @Binding var route: StudioRoute
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onDone) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left").font(.system(size: 13))
                    Text("Done").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(ALColor.textSecondary)
                .padding(.horizontal, 8).frame(height: 30)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)

            // CLIs — lane-agnostic foundation; sources feed every lane.
            item("CLIs", icon: "terminal", target: .clis)

            ForEach(ComposeLane.allCases, id: \.self) { lane in
                laneHeader(lane)
                item("Teams", icon: "rectangle.3.group", target: .teams(lane), indented: true)
                item("Skills", icon: "sparkles", target: .skills(lane), indented: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
    }

    private func laneHeader(_ lane: ComposeLane) -> some View {
        HStack(spacing: 6) {
            Image(systemName: lane.icon).font(.system(size: 10))
            Text(lane.label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6)
        }
        .foregroundStyle(ALColor.textFaint)
        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 3)
    }

    private func item(_ label: String, icon: String, target: StudioRoute, indented: Bool = false) -> some View {
        let on = route == target
        return Button { route = target } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12.5)).frame(width: 16)
                Text(label).font(.system(size: 13, weight: on ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? ALColor.textPrimary : ALColor.textMuted)
            .padding(.leading, indented ? 18 : 0)
            .padding(.horizontal, 8).frame(height: 30)
            .background(on ? ALColor.active : .clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog lists (read catalog APIs; edit flows land in a later slice)

private struct StudioTeamListView: View {
    let lane: ComposeLane
    private var teams: [TeamPreset] { TeamCatalog.list(lane: lane.workLane) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("\(lane.label) teams", subtitle: "Lane-scoped lineups from the team catalog.")
            List(teams) { team in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(team.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ALColor.textPrimary)
                        if team.isDefaultForLane {
                            Text("Default")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ALColor.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(ALColor.accent.opacity(0.12), in: Capsule())
                        }
                        if !team.builtIn {
                            Text("Custom")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ALColor.textFaint)
                        }
                    }
                    Text(team.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                    let counts = team.workerCountByEffort()
                    Text("Workers L/M/H: \(counts[.low] ?? 0)/\(counts[.med] ?? 0)/\(counts[.high] ?? 0) · \(team.outputKind.rawValue)")
                        .font(.system(size: 11))
                        .foregroundStyle(ALColor.textMuted)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ALColor.base)
    }
}

private struct StudioSkillListView: View {
    let lane: ComposeLane
    private var skills: [Skill] { SkillCatalog.list(lane: lane.workLane) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("\(lane.label) skills", subtitle: "Prompt profiles for this lane — templates on detail in a later slice.")
            List(skills) { skill in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(skill.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ALColor.textPrimary)
                        Text(skill.purpose.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ALColor.textFaint)
                        if skill.builtIn {
                            Text("Built-in")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ALColor.textFaint)
                        } else {
                            Text("Custom")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ALColor.accent)
                        }
                    }
                    Text(skill.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ALColor.base)
    }
}

@ViewBuilder
private func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 20, weight: .heavy)).tracking(-0.3)
            .foregroundStyle(ALColor.textPrimary)
        Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(ALColor.textMuted)
    }
    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
}
