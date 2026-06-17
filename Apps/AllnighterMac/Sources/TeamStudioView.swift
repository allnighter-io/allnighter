import SwiftUI
import AllnighterCore

// Settings — the Team configuration surface. Reached from "Manage team" (Team
// dropdown) and, later, the title-bar health badge. The whole app is lane-first
// (Build / Design / Copy), so the nav groups by lane: one CLIs page on top
// (lane-agnostic — sources feed every lane), then per-lane Teams + Skills.
//
// CLIs reuses the existing `TeamReadinessView` (the shipped CLI-setup/readiness
// surface). Teams render read-only until `alln teams edit` ships; Skills arrive
// with SkillCatalog (`alln skills`). The shell never
// invents team/skill truth — placeholders say so honestly.

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
            StudioPlaceholder(
                icon: lane.icon,
                title: "\(lane.label) teams",
                message: "Saved \(lane.label.lowercased()) lineups land here next — list, detail, and the Skill | Model table. Read-only until team editing (`alln teams edit`) ships."
            )
        case .skills(let lane):
            StudioPlaceholder(
                icon: "sparkles",
                title: "\(lane.label) skills",
                message: "The skill library arrives with SkillCatalog (`alln skills`). Allnighter won't fake skill truth in the UI before it exists."
            )
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

// MARK: - Placeholder (honest "not built / not backed yet")

private struct StudioPlaceholder: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(ALColor.accent)
            Text(title)
                .font(.system(size: 20, weight: .heavy)).tracking(-0.3)
                .foregroundStyle(ALColor.textPrimary)
            Text(message)
                .font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
                .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}
