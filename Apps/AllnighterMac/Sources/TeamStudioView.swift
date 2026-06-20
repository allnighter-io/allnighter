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
    case defaultModel
    case teams(ComposeLane)
    case skills(ComposeLane)
}

struct TeamStudioView: View {
    /// Composer "Customize…" deep-link: which team to pre-select on the Teams page.
    var customizeTeamId: String?
    var onDone: () -> Void
    @State private var route: StudioRoute

    init(initialRoute: StudioRoute = .clis, customizeTeamId: String? = nil, onDone: @escaping () -> Void) {
        self.customizeTeamId = customizeTeamId
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
        case .defaultModel:
            DefaultModelView()
        case .teams(let lane):
            StudioTeamListView(lane: lane, customizeTeamId: customizeTeamId)
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
            // Default model (Auto) — lane-agnostic; the model that answers when no team
            // or model is picked, drawn from the substitution tiers.
            item("Default model", icon: "infinity", target: .defaultModel)

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
    /// Composer "Customize…" deep-link: pre-select this team on appear (its editor).
    var customizeTeamId: String? = nil
    @Environment(AppModel.self) private var appModel
    @State private var selectedId: TeamID?
    /// A brand-new, unsaved team being authored (Add team). Not in the catalog until
    /// Save; takes precedence over `selectedId` while present.
    @State private var newDraftBase: TeamPreset?
    /// Bumped to rebuild the inline editor with a fresh draft (revert / after save).
    @State private var revertTick = 0

    /// Lane teams, favorites first (in favorite order), then catalog order. The
    /// global Default Team always leads.
    private var teams: [TeamPreset] {
        let all = TeamCatalog.list(lane: lane.workLane)
        let favRank = Dictionary(uniqueKeysWithValues: appModel.favoriteTeamIds.enumerated().map { ($1, $0) })
        let defaultId = TeamCatalog.defaultRunTeam()?.id
        func rank(_ t: TeamPreset) -> (Int, Int) {
            if t.id == defaultId { return (0, 0) }
            if let r = favRank[t.id] { return (1, r) }
            return (2, 0)
        }
        return all.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra != rb { return ra < rb }
            return a.offset < b.offset
        }.map(\.element)
    }
    private var selected: TeamPreset? {
        newDraftBase ?? (teams.first { $0.id == selectedId } ?? teams.first)
    }

    /// A blank starting point for a new lane team: one worker on a lane skill + the
    /// first ready model. Not persisted until Save.
    private func blankBase() -> TeamPreset {
        let skillId = SkillCatalog.list(lane: lane.workLane).first?.id ?? ""
        let modelId = readyModels.first?.id ?? appModel.models.first?.id
        let worker = TeamWorkerSpec(id: UUID().uuidString, skillId: skillId, purpose: .answer,
                                    preferredModelId: modelId, count: 1, fallbackPolicy: .laneCapable, required: true)
        let lead = TeamLeadSpec(skillId: skillId, preferredModelId: modelId, fallbackPolicy: .laneCapable)
        return TeamPreset(id: "new_\(lane.workLane.rawValue)_draft", displayName: "New \(lane.label) team",
                          lane: lane.workLane, outputKind: .plan, workerSpecs: [worker], lead: lead, builtIn: false)
    }

    /// The models confirmed ready on the bench — so the detail can show who would
    /// actually run each role (concrete, not "Auto").
    private var readyModels: [Model] {
        let readyIds = Set(appModel.composeBench.filter(\.ready).map(\.id))
        return appModel.models.filter { readyIds.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Master — the lane's saved lineups.
            VStack(alignment: .leading, spacing: 0) {
                header("\(lane.label) teams",
                       subtitle: "Saved \(lane.label.lowercased()) lineups. Pick one to tune it, or pick one in the composer.")
                addTeamButton
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(teams) { team in teamRow(team) }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
            .frame(width: 300)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)

            // The detail pane IS the editor — select a team and tune it in place
            // (models inline, a skill cell opens the worker editor). No separate
            // "Customize" step, no read-only copy. Built-ins draft in memory and
            // only fork to a custom team on Save; switching teams rebuilds the draft.
            Group {
                if let team = selected {
                    TeamEditorView(
                        base: team, lane: lane, models: appModel.models, readyModels: readyModels,
                        isNew: newDraftBase != nil,
                        // Cancel: drop the new-team form (back to the prior selection),
                        // or discard edits by rebuilding the draft from the base.
                        onCancel: { newDraftBase = nil; revertTick += 1 },
                        onSaved: { id in newDraftBase = nil; selectedId = id; revertTick += 1 }
                    )
                    .id("\(newDraftBase != nil ? "new" : team.id)#\(revertTick)")
                } else {
                    StudioEmptyDetail(icon: lane.icon, message: "No \(lane.label.lowercased()) teams yet.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear {
            // Composer "Customize…" deep-link → select that team (its editor opens).
            if let id = customizeTeamId, teams.contains(where: { $0.id == id }) {
                selectedId = id
            }
        }
    }

    /// Creates a blank draft and opens it in the editor as a new team.
    private var addTeamButton: some View {
        Button { newDraftBase = blankBase(); revertTick += 1 } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                Text("New \(lane.label.lowercased()) team").font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.alPrimary(small: true))
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private func teamRow(_ team: TeamPreset) -> some View {
        let on = newDraftBase == nil && selected?.id == team.id
        let isDefaultRun = team.id == TeamCatalog.defaultRunTeam()?.id
        let fav = appModel.isFavorite(team.id)
        return HStack(spacing: 6) {
            Button { newDraftBase = nil; selectedId = team.id } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if isDefaultRun {
                            Image(systemName: "infinity").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                        }
                        Text(team.displayName)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                            .lineLimit(1)
                        if !team.builtIn { miniBadge("Custom", ALColor.textMuted) }
                        Spacer(minLength: 0)
                    }
                    Text("\(team.defaultEffort.rawValue.capitalized) · \(team.runShape == .execution ? "1 agent" : "\(team.workerSpecs.count) workers")")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Star toggles favorite (featured first here + in the composer). The
            // Default Team is implicitly a favorite and can't be unstarred.
            Button { if !isDefaultRun { appModel.toggleFavorite(team.id) } } label: {
                Image(systemName: (fav || isDefaultRun) ? "star.fill" : "star").font(.system(size: 12))
                    .foregroundStyle((fav || isDefaultRun) ? ALColor.textSecondary : ALColor.textFaint)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(isDefaultRun)
            .help(isDefaultRun ? "The Default Team is always featured" : (fav ? "Remove from favorites" : "Add to favorites"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(on ? ALColor.active : .clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private func miniBadge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(c.opacity(0.14), in: Capsule())
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
    @State private var query = ""

    /// Lane skills, sorted A→Z, filtered by the search box (founder: a growing list
    /// must be scannable + searchable).
    private var skills: [Skill] {
        let all = SkillCatalog.list(lane: lane.workLane)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? all : all.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }
    private var selected: Skill? { skills.first { $0.id == selectedId } ?? skills.first }

    var body: some View {
        HStack(spacing: 0) {
            // Master — the lane's skills (the hats a worker can wear).
            VStack(alignment: .leading, spacing: 0) {
                header("\(lane.label) skills",
                       subtitle: "The hats your \(lane.label.lowercased()) models wear. Duplicate to tune one.")
                skillSearchField
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(skills) { skill in skillRow(skill) }
                        if skills.isEmpty {
                            Text("No \(lane.label.lowercased()) skill matches \"\(query)\".")
                                .font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.top, 6)
                        }
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

    private var skillSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            TextField("Search skills…", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(ALColor.textPrimary)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        .padding(.horizontal, 12).padding(.bottom, 10)
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
                    chip(skill.builtIn ? "Built-in template" : "Custom", accent: !skill.builtIn)
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
                Text("Tune a skill where you use it — open a team and customize the worker's prompt.")
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
