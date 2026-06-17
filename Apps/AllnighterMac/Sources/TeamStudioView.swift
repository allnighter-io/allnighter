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
            Text(lane.label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
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
    @Environment(AppModel.self) private var appModel
    @State private var selectedId: TeamID?
    @State private var editingBase: TeamPreset?

    private var teams: [TeamPreset] { TeamCatalog.list(lane: lane.workLane) }
    private var selected: TeamPreset? { teams.first { $0.id == selectedId } ?? teams.first }

    /// The models confirmed ready on the bench — so the detail can show who would
    /// actually run each role (concrete, not "Auto").
    private var readyModels: [Model] {
        let readyIds = Set(appModel.composeBench.filter(\.ready).map(\.id))
        return appModel.models.filter { readyIds.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                // Master — the lane's saved lineups.
                VStack(alignment: .leading, spacing: 0) {
                    header("\(lane.label) teams",
                           subtitle: "Saved \(lane.label.lowercased()) lineups. Pick one in the composer, or duplicate to tune it.")
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(teams) { team in teamRow(team) }
                        }
                        .padding(.horizontal, 12).padding(.bottom, 12)
                    }
                }
                .frame(width: 300)
                Rectangle().fill(ALColor.borderSubtle).frame(width: 1)

                // Detail — the selected team's Skill → Model lineup.
                Group {
                    if let team = selected {
                        StudioTeamDetailView(team: team, models: appModel.models, readyModels: readyModels,
                                             onEdit: { editingBase = team })
                    } else {
                        StudioEmptyDetail(icon: lane.icon, message: "No \(lane.label.lowercased()) teams yet.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Customize editor — a right-anchored drawer over a scrim. Nothing is
            // saved until Save; Cancel drops the draft (built-ins never mutate).
            if let base = editingBase {
                ALColor.scrimSubtle.ignoresSafeArea()
                    .onTapGesture { editingBase = nil }
                TeamEditorView(
                    base: base, lane: lane, models: appModel.models, readyModels: readyModels,
                    onCancel: { editingBase = nil },
                    onSaved: { id in selectedId = id; editingBase = nil }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear {
            #if DEBUG
            if GUIFixture.opensTeamEditor { editingBase = selected }
            #endif
        }
    }

    private func teamRow(_ team: TeamPreset) -> some View {
        let on = selected?.id == team.id
        return Button { selectedId = team.id } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(team.displayName)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                        .lineLimit(1)
                    if team.isDefaultForLane { miniBadge("Default", ALColor.accent) }
                    if !team.builtIn { miniBadge("Custom", ALColor.textMuted) }
                    Spacer(minLength: 0)
                }
                Text("\(team.defaultEffort.rawValue.capitalized) · \(team.activeRows(at: team.defaultEffort).count) workers")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? ALColor.active : .clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func miniBadge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(c.opacity(0.14), in: Capsule())
    }
}

/// Read-only team detail: header + chips + the Skill | Model table (the declared
/// lineup at the team's default effort). Edit/duplicate/set-default land next slice.
private struct StudioTeamDetailView: View {
    let team: TeamPreset
    let models: [Model]
    let readyModels: [Model]
    var onEdit: () -> Void = {}

    private var rows: [TeamWorkerSpec] { team.activeRows(at: team.defaultEffort) }
    /// Who would actually run this team on the current bench (skill → real model).
    private var resolved: ResolvedTeamRun {
        TeamResolver.resolve(team: team, requestLane: team.lane,
                             requestEffort: team.defaultEffort, readyModels: readyModels)
    }
    private var lineup: [Worker] {
        resolved.answerWorkers + resolved.reviewWorkers + (resolved.planWriter.map { [$0] } ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group").font(.system(size: 15)).foregroundStyle(ALColor.accent)
                    Text(team.displayName)
                        .font(.system(size: 18, weight: .bold)).tracking(-0.3)
                        .foregroundStyle(ALColor.textPrimary)
                    if team.isDefaultForLane { chip("Default", accent: true) }
                    if !team.builtIn { chip("Custom", accent: false) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    chip(team.lane.rawValue.capitalized, accent: false)
                    chip(team.defaultEffort.rawValue.capitalized, accent: false)
                    chip("\(lineup.isEmpty ? rows.count : lineup.count) workers", accent: false)
                    chip(team.outputKind.rawValue, accent: false)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("SKILL").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                        Spacer()
                        Text("MODEL").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                    }
                    .padding(.bottom, 4)
                    if lineup.isEmpty {
                        // No ready bench → show the declared roles honestly.
                        ForEach(rows) { row in
                            tableRow(skill: skillName(row.skillId), model: "needs a ready CLI", muted: true)
                        }
                    } else {
                        ForEach(lineup) { worker in
                            tableRow(skill: worker.skillName ?? worker.skillId.map(skillName) ?? "Worker",
                                     model: modelName(worker.modelId), muted: false)
                        }
                    }
                }

                if lineup.isEmpty {
                    Text("Connect a CLI on the Bench to see who runs this team.")
                        .font(.system(size: 11)).foregroundStyle(ALColor.statusTimeout)
                }

                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Label(team.builtIn ? "Duplicate to edit" : "Edit team", systemImage: "square.on.square")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.alSecondary(small: true))
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ALColor.base)
    }

    private func tableRow(skill: String, model: String, muted: Bool) -> some View {
        HStack {
            Text(skill).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
            Spacer(minLength: 12)
            Text(model)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted ? ALColor.textFaint : ALColor.textSecondary)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func skillName(_ id: String) -> String { SkillCatalog.get(id)?.displayName ?? id }
    private func modelName(_ id: String) -> String {
        models.first { $0.id == id }?.displayName ?? id
    }
    private func chip(_ t: String, accent: Bool) -> some View {
        Text(t).font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent ? ALColor.accent : ALColor.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(accent ? ALColor.accent.opacity(0.12) : ALColor.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

private struct StudioEmptyDetail: View {
    let icon: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(ALColor.textFaint)
            Text(message).font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

private struct StudioSkillListView: View {
    let lane: ComposeLane
    @State private var selectedId: SkillID?

    private var skills: [Skill] { SkillCatalog.list(lane: lane.workLane) }
    private var selected: Skill? { skills.first { $0.id == selectedId } ?? skills.first }

    var body: some View {
        HStack(spacing: 0) {
            // Master — the lane's skills (the hats a worker can wear).
            VStack(alignment: .leading, spacing: 0) {
                header("\(lane.label) skills",
                       subtitle: "The hats your \(lane.label.lowercased()) models wear. Duplicate to tune one.")
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(skills) { skill in skillRow(skill) }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
            .frame(width: 300)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)

            // Detail — the selected skill's compatibility + prompt template.
            Group {
                if let skill = selected {
                    StudioSkillDetailView(skill: skill)
                } else {
                    StudioEmptyDetail(icon: "sparkles", message: "No \(lane.label.lowercased()) skills yet.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }

    private func skillRow(_ skill: Skill) -> some View {
        let on = selected?.id == skill.id
        return Button { selectedId = skill.id } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.displayName)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                        .lineLimit(1)
                    if !skill.builtIn {
                        Text("Custom").font(.system(size: 9, weight: .semibold)).foregroundStyle(ALColor.accent)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(ALColor.accent.opacity(0.14), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                Text("\(skill.builtIn ? "built-in" : "custom") · \(skill.purpose.rawValue)")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? ALColor.active : .clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Read-only skill detail: name + built-in/custom + purpose, the lane it belongs
/// to, and the prompt template. Duplicate-to-edit / new land in the editor slice.
private struct StudioSkillDetailView: View {
    let skill: Skill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(ALColor.accent)
                    Text(skill.displayName)
                        .font(.system(size: 18, weight: .bold)).tracking(-0.3)
                        .foregroundStyle(ALColor.textPrimary)
                    chip(skill.builtIn ? "Built-in · read-only" : "Custom", accent: !skill.builtIn)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("LANE · PURPOSE").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                    HStack(spacing: 6) {
                        chip(skill.lane.rawValue.capitalized, accent: false)
                        chip(skill.purpose.rawValue, accent: false)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROMPT TEMPLATE").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                    Text(skill.template)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(ALColor.textSecondary)
                        .lineSpacing(3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                Text("Duplicate to edit and New skill arrive in the editor slice.")
                    .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ALColor.base)
    }

    private func chip(_ t: String, accent: Bool) -> some View {
        Text(t).font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent ? ALColor.accent : ALColor.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(accent ? ALColor.accent.opacity(0.12) : ALColor.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

@ViewBuilder
private func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 20, weight: .bold)).tracking(-0.3)
            .foregroundStyle(ALColor.textPrimary)
        Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(ALColor.textMuted)
    }
    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
}
