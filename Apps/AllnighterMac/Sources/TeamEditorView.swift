import SwiftUI
import AllnighterCore

// The Customize-team editor (design-customize.png). A safe, in-memory DRAFT:
// nothing touches the catalog until Save; Cancel just drops it. Editing a built-in
// duplicates it to a NEW custom (the built-in is never mutated). Models are always
// picked by NAME — never "strongest" (founder ICP rule).

struct TeamEditorView: View {
    let lane: ComposeLane
    let models: [Model]
    let readyModels: [Model]
    /// True when editing a brand-new (not-yet-saved) team — the footer reads
    /// "Create team" rather than "Duplicate Team" / "Save changes".
    let isNew: Bool
    /// Cancel: for a new team, the parent removes the form; for an existing team it
    /// discards unsaved edits (or, in a modal drawer, closes it).
    var onCancel: () -> Void
    var onSaved: (TeamID) -> Void
    /// Open the Default-model screen — the SSOT for the "Auto" team's agent.
    var onOpenDefaultModel: () -> Void = {}

    @State private var draft: TeamDraft
    @State private var errorText: String?
    /// The draft as first loaded — compared against `draft` to know if anything was
    /// actually edited (so Cancel only appears when there's something to cancel).
    private let initialDraft: TeamDraft
    /// Level-2: which roster row is open in Edit skill (nil = team roster).
    @State private var editingRow: Int?
    /// Level-2 for the Team Lead (separate from worker rows; the Lead is pinned).
    @State private var editingLead = false
    /// Live "show on Teams page" state (TeamVisibility). A setting, not a draft edit — it
    /// persists immediately on toggle, no Save needed. Works for built-ins too (reversible).
    @State private var showOnTeamsPage = true
    /// Delete-confirmation for a custom team (built-ins can only be hidden).
    @State private var confirmingDelete = false

    init(base: TeamPreset, lane: ComposeLane, models: [Model], readyModels: [Model],
         isNew: Bool = false,
         onCancel: @escaping () -> Void, onSaved: @escaping (TeamID) -> Void,
         onOpenDefaultModel: @escaping () -> Void = {}) {
        self.lane = lane
        self.models = models
        self.readyModels = readyModels
        self.isNew = isNew
        self.onCancel = onCancel
        self.onSaved = onSaved
        self.onOpenDefaultModel = onOpenDefaultModel
        let seed = TeamDraft(base: base)
        _draft = State(initialValue: seed)
        self.initialDraft = seed
        // A brand-new team is shown by default; an existing one reflects its saved visibility.
        _showOnTeamsPage = State(initialValue: isNew ? true : TeamVisibility.isEnabled(base.id))
    }

    /// The built-in "Auto" team (default_chat) is the default route. Its agent model is NOT
    /// its own editable field — the run resolves it from the Default-model tiers (Settings →
    /// Default model), ignoring any per-team pick. So the editor shows that resolved model
    /// read-only and routes edits to the Default-model screen, instead of a divergent picker.
    private var isDefaultAutoTeam: Bool {
        draft.base.id == TeamCatalog.defaultRunTeam()?.id
    }

    /// What Auto actually runs right now — the resolved Default-model tier pick (the same
    /// resolution the composer Auto chip and the run path use).
    private var resolvedDefaultModelName: String {
        let settings = DefaultModelSettingsPersistence().load()
        let readyIds = Set(readyModels.map(\.id))
        if let id = SubstitutionResolver.resolveAuto(settings: settings, readyModelIds: readyIds).resolvedModelId,
           let name = models.first(where: { $0.id == id })?.displayName {
            return name
        }
        return "your Default model"
    }

    /// Has the user changed anything since the editor opened?
    private var isDirty: Bool { draft != initialDraft }

    /// The shipped (unedited) form of a built-in team. False once edited (an override).
    private var isBuiltIn: Bool { draft.base.builtIn }

    /// This team has a shipped version that the user has edited, so a Restore is offered.
    private var canRestore: Bool { !isNew && TeamCatalog.hasOverride(draft.base.id) }

    private var laneSkills: [Skill] { Self.pickerSkills(for: draft, lane: lane.workLane) }
    /// The Lead picks among plan-writer skills only — it's the synthesizer, not an
    /// answer/review worker.
    private var leadSkills: [Skill] { laneSkills.filter { $0.purpose == .planWriter } }

    /// Built-in identities (seed + override) plus custom skills this team references.
    static func pickerSkills(for draft: TeamDraft, lane: WorkLane) -> [Skill] {
        var refIds = Set<String>()
        for row in draft.rows + [draft.lead] + (draft.scout.map { [$0] } ?? []) where !row.skillId.isEmpty {
            refIds.insert(row.skillId)
        }
        for spec in draft.base.agentSpecs where !spec.skillId.isEmpty { refIds.insert(spec.skillId) }
        if !draft.base.lead.skillId.isEmpty { refIds.insert(draft.base.lead.skillId) }
        draft.base.scout.map { if !$0.skillId.isEmpty { refIds.insert($0.skillId) } }
        return SkillCatalog.list(lane: lane).filter { skill in
            switch SkillCatalog.origin(of: skill.id) {
            case .seed, .override: return true
            case .custom: return refIds.contains(skill.id)
            case .none: return false
            }
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        Group {
            if let i = editingRow, draft.rows.indices.contains(i) {
                EditSkillView(
                    teamName: draft.name, isLead: false, lane: lane, models: models, laneSkills: laneSkills,
                    row: draft.rows[i],
                    onDone: { updated in draft.rows[i] = updated; editingRow = nil },
                    onCancel: { editingRow = nil }
                )
            } else if editingLead {
                EditSkillView(
                    teamName: draft.name, isLead: true, lane: lane, models: models,
                    laneSkills: leadSkills, defaultPurpose: .planWriter,
                    row: draft.lead,
                    onDone: { updated in draft.lead = updated; editingLead = false },
                    onCancel: { editingLead = false }
                )
            } else {
                teamContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear {
            #if DEBUG
            if GUIFixture.opensWorkerEditor, editingRow == nil, !draft.rows.isEmpty { editingRow = 0 }
            #endif
        }
    }

    private var teamContent: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameField
                    // A mutating team is ONE agent — the worker does the work. No
                    // separate Lead (that split only makes sense for answer teams,
                    // where N workers feed one synthesizer).
                    if !draft.mutating { leadSection }
                    if draft.scout != nil { scoutSection }
                    workers
                    substitutionsToggle
                    executionPostureSection
                    summary
                    bottomSection
                }
                .padding(20)
            }
            footer
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(ALColor.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Text(canRestore ? "\(lane.label) team · edited · Restore to revert"
                                : "\(lane.label) team · model · skill")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 0)
            if canRestore {
                Text("EDITED").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(ALColor.textMuted.opacity(0.14), in: Capsule())
            }
            // Live Active/Inactive switch (TeamVisibility), in the title row. OFF
            // deactivates the team everywhere it's listed — Teams page, composer,
            // CLI — but it stays here in Settings to switch back on, and
            // still runs if invoked by id. Persists on toggle; no Save needed; works
            // for built-ins too (the seed is never touched, so it's reversible).
            if !isNew {
                VStack(alignment: .trailing, spacing: 3) {
                    Toggle("", isOn: Binding(
                        get: { showOnTeamsPage },
                        set: { on in
                            showOnTeamsPage = on
                            try? TeamVisibility.setEnabled(draft.base.id, on)
                        }
                    ))
                    .labelsHidden().toggleStyle(.switch).tint(ALColor.accent)
                    Text(showOnTeamsPage ? "Active" : "Inactive")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(showOnTeamsPage ? ALColor.textMuted : ALColor.textFaint)
                }
                .help(showOnTeamsPage
                      ? "Active — appears in the composer picker, the Teams page, and to agents over the alln CLI."
                      : "Inactive — hidden everywhere teams are listed. Still runs if invoked by id.")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    /// A truly custom team (not a built-in id and already saved) — only these can be deleted.
    private var isCustomTeam: Bool { !isNew && BuiltInTeams.team(draft.base.id) == nil }

    /// Bottom of the editor: the one-line explainer for the title-row Active/Inactive
    /// toggle (the explanation lives here, away from the control, read once), plus
    /// permanent delete for CUSTOM teams only. Built-ins can't be deleted (they're
    /// shipped seeds) — deactivate one with the title-row toggle instead.
    @ViewBuilder private var bottomSection: some View {
        if !isNew {
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(ALColor.borderSubtle).frame(height: 1).padding(.vertical, 4)
                Text(showOnTeamsPage
                     ? "Active — appears in the composer picker, the Teams page, and to agents over the alln CLI. Flip the title-bar toggle off to deactivate it."
                     : "Inactive — hidden from the picker, the Teams page, and agents over the alln CLI. It still runs if invoked directly by id.")
                    .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                if isCustomTeam {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash").font(.system(size: 12))
                            Text("Delete team").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(ALPalette.red400)
                    }
                    .buttonStyle(.plain).padding(.top, 2)
                    Text("Permanently removes this custom team. Built-in teams can only be deactivated.")
                        .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .confirmationDialog("Delete \u{201C}\(draft.name)\u{201D}?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete team", role: .destructive) { deleteTeam() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the custom team. This can't be undone.")
            }
        }
    }

    private func deleteTeam() {
        do {
            try TeamCatalog.deleteCustom(draft.base.id)
            onCancel()   // close the editor; the roster re-reads and drops the team
        } catch {
            errorText = "Couldn't delete this team."
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TEAM NAME").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            TextField("Team name", text: $draft.name)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    /// The pinned Team Lead — required, can't be removed, sits above the crew.
    private var leadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("TEAM LEAD").font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(ALColor.textFaint)
                Text("· reports back · required").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                Spacer(minLength: 0)
            }
            rosterColumnHeaders()
            leadRow
            Text("Reads every agent's output and writes the single answer.")
                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
    }

    private var leadRow: some View {
        HStack(spacing: 8) {
            modelPicker(draft.lead.modelId) { draft.lead.modelId = $0 }
            Button { editingLead = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                    Text(skillLabel(draft.lead))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
                }
                .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
                .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Color.clear.frame(width: 14, height: 1)
        }
    }

    private var workers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.mutating ? "AGENT" : "AGENTS")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            if draft.mutating {
                Text(isDefaultAutoTeam
                     ? "Auto runs your Default model — set which model that is in Default model. Editing it here won't change Auto."
                     : "One agent does the work in the repo root — no separate lead.")
                    .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            }
            rosterColumnHeaders(showRemoveColumn: !draft.mutating)
            ForEach($draft.rows) { $row in
                HStack(spacing: 8) {
                    if isDefaultAutoTeam {
                        defaultModelCell
                    } else if isTriangulated(row.id) {
                        triangulatedModelCell(count: triangulateCount(row.id))
                    } else {
                        modelPicker($row.wrappedValue.modelId) { $row.wrappedValue.modelId = $0 }
                    }
                    Button { editingRow = draft.rows.firstIndex { $0.id == row.id } } label: {
                        HStack(spacing: 6) {
                            Text(skillLabel($row.wrappedValue))
                                .font(.system(size: 12)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
                        }
                        .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
                        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
                        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if !draft.mutating {
                        Button { draft.rows.removeAll { $0.id == row.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 14, height: 1)
                    }
                }
            }
            Button {
                let skillId = laneSkills.first?.id ?? ""
                draft.rows.append(.init(id: UUID().uuidString, skillId: skillId,
                                        modelId: nil, purpose: .answer)) // nil = Auto
            } label: {
                Label("Add agent", systemImage: "plus").font(.system(size: 12, weight: .medium))
            }
            .disabled(draft.mutating)
            .buttonStyle(.plain).foregroundStyle(ALColor.textSecondary).padding(.top, 2)
        }
    }

    /// Column labels for model + skill roster rows (agents and team lead).
    private func rosterColumnHeaders(showRemoveColumn: Bool = true) -> some View {
        HStack(spacing: 8) {
            Text("MODEL")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SKILL")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showRemoveColumn {
                Color.clear.frame(width: 14, height: 1)
            }
        }
    }

    // Custom dropdown (never the native Menu — it breaks the dark UI).
    private func picker(current: String, options: [(String, String)], onPick: @escaping (String) -> Void) -> some View {
        ALDropdown(current: current, options: options, onPick: onPick)
    }

    // MARK: - Model pickers (Auto + concrete)

    /// Sentinel id for the "Auto" option (nil model = resolver picks a ready model).
    fileprivate static let autoOptionId = "__alln_auto__"

    /// Model display: nil → "Auto" (never a guessed/strongest model), else the name.
    private func modelDisplay(_ id: String?) -> String {
        guard let id else { return "Auto" }
        return models.first { $0.id == id }?.displayName ?? id
    }

    /// Read-only agent cell for the "Auto" team — shows the resolved Default model and
    /// opens the Default-model screen (its single source of truth) rather than letting the
    /// user set a per-team model the run would ignore.
    private var defaultModelCell: some View {
        Button(action: onOpenDefaultModel) {
            HStack(spacing: 5) {
                Image(systemName: "infinity").font(.system(size: 10)).foregroundStyle(ALColor.textMuted)
                Text(resolvedDefaultModelName)
                    .font(.system(size: 12)).foregroundStyle(ALColor.textSecondary).lineLimit(1)
                Image(systemName: "arrow.up.forward").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Auto runs your Default model — change it in Default model")
        .frame(maxWidth: .infinity)
    }

    /// A model picker whose first option is Auto (nil). Picking Auto clears the pin.
    private func modelPicker(_ id: String?, onPick: @escaping (String?) -> Void) -> some View {
        let options = [(Self.autoOptionId, "Auto")] + models.map { ($0.id, $0.displayName) }
        return picker(current: modelDisplay(id), options: options) { picked in
            onPick(picked == Self.autoOptionId ? nil : picked)
        }
        .frame(maxWidth: .infinity)
    }

    private func isTriangulated(_ rowId: String) -> Bool {
        draft.base.agentSpecs.first { $0.id == rowId }?.triangulate ?? false
    }
    private func triangulateCount(_ rowId: String) -> Int {
        max(1, draft.base.agentSpecs.first { $0.id == rowId }?.count ?? 3)
    }

    /// Read-only model cell for a triangulated worker row — it runs on several
    /// distinct CLIs, so there is no single model to show. (Editing the CLI set is a
    /// later slice.)
    private func triangulatedModelCell(count: Int) -> some View {
        HStack(spacing: 4) {
            Text("Auto · \(count) distinct CLIs")
                .font(.system(size: 12)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        .help("Reads the scout's source on \(count) distinct CLIs (e.g. Grok, GPT-5.5, Gemini).")
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scout (Signal teams)

    /// Stage-0 scout: grabs the source first. Pinned to an X-capable model (Grok);
    /// changing it off Grok shows a non-blocking warning.
    @ViewBuilder private var scoutSection: some View {
        if let scout = draft.scout {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("SCOUT").font(.system(size: 10, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(ALColor.textFaint)
                    Text("· grabs the source first · X-capable").font(.system(size: 10))
                        .foregroundStyle(ALColor.textFaint)
                    Spacer(minLength: 0)
                }
                rosterColumnHeaders(showRemoveColumn: false)
                HStack(spacing: 8) {
                    picker(current: modelDisplay(scout.modelId),
                           options: models.map { ($0.id, $0.displayName) }) { draft.scout?.modelId = $0 }
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                        Text(skillName(scout.skillId))
                            .font(.system(size: 12)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
                    .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    Color.clear.frame(width: 14, height: 1)
                }
                Text("Grok grabs the public link/post and distills it for the agents.")
                    .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                if let warning = SignalScoutPolicy.scoutModelWarning(scout.modelId) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10)).foregroundStyle(ALPalette.amber400)
                        Text(warning).font(.system(size: 11)).foregroundStyle(ALPalette.amber400)
                    }
                }
            }
        }
    }

    private var substitutionsToggle: some View {
        Toggle(isOn: $draft.allowSubstitutions) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow healthy substitutions").font(.system(size: 13, weight: .medium)).foregroundStyle(ALColor.textPrimary)
                Text("If a model is down, use another ready model in this lane.")
                    .font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            }
        }
        .toggleStyle(.switch).tint(ALColor.accent)
    }

    private var executionPostureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXECUTION").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            Toggle(isOn: $draft.mutating) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mutating team").font(.system(size: 13, weight: .medium)).foregroundStyle(ALColor.textPrimary)
                    Text("Runs one agent in the repo root under the write lock.")
                        .font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                }
            }
            .toggleStyle(.switch).tint(ALColor.accent)
            .onChange(of: draft.mutating) { _, on in
                if on {
                    draft.rows = Array(draft.rows.prefix(1))
                }
            }
            if draft.mutating, let conflict = executionSourceConflictMessage {
                Text(conflict).font(.system(size: 11)).foregroundStyle(ALPalette.red400)
            } else if draft.mutating, let source = pinnedExecutionSourceLabel {
                Text("Execution source: \(source)").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            }
        }
    }

    /// Rows that carry an execution source. A mutating team has no separate lead, so
    /// only its single agent counts; an answer team includes the synthesizer lead.
    private var executionSourceRows: [TeamDraft.Row] {
        draft.mutating ? draft.rows : draft.rows + [draft.lead]
    }

    private var pinnedExecutionSourceLabel: String? {
        let bench = Dictionary(models.map { ($0.id, $0.driverId) }, uniquingKeysWith: { a, _ in a })
        var sources = Set<String>()
        for row in executionSourceRows {
            if let mid = row.modelId, let source = bench[mid] { sources.insert(source) }
        }
        guard sources.count == 1, let only = sources.first else { return nil }
        return only
    }

    private var executionSourceConflictMessage: String? {
        let bench = Dictionary(models.map { ($0.id, $0.driverId) }, uniquingKeysWith: { a, _ in a })
        var sources = Set<String>()
        for row in executionSourceRows {
            if let mid = row.modelId, let source = bench[mid] { sources.insert(source) }
        }
        guard sources.count > 1 else { return nil }
        return "Execution teams run on one CLI. Pick one source for all agents."
    }

    private var summary: some View {
        Text(draft.mutating
             ? "1 agent · runs in the repo root under the write lock · saved as a \(lane.label.lowercased()) team you can pick in the composer."
             : "\(draft.rows.count) agents + 1 lead · saved as a \(lane.label.lowercased()) team you can pick in the composer.")
            .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let errorText {
                Text(errorText).font(.system(size: 11)).foregroundStyle(ALPalette.red400)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                // Restore appears once this shipped team has been edited — it reverts the
                // team to its shipped version (removes the user's edits). Left-aligned so
                // it reads as a quieter, separate action from Save.
                if canRestore {
                    Button("Restore", action: restore).buttonStyle(.alSecondary(small: true))
                }
                Spacer(minLength: 0)
                // Cancel only when there's something to cancel: a new team (removes
                // the form) or unsaved edits (discards them). Nothing to cancel → no
                // dangling button.
                if isNew || isDirty {
                    Button("Cancel", action: onCancel).buttonStyle(.alSecondary(small: true))
                }
                // Every existing team saves in place — there is no "Duplicate Team".
                Button(isNew ? "Create team" : "Save changes", action: save)
                    .buttonStyle(.alPrimary(small: true))
                    .disabled(!draft.isSavable || (!isNew && !isDirty))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func save() {
        do {
            let id = try draft.commit()
            onSaved(id)
        } catch let e as CatalogError {
            errorText = friendly(e)
        } catch {
            errorText = "Could not save this team."
        }
    }

    /// Revert this team to its shipped version (remove the user's edits) and reload the
    /// editor so it shows the restored seed.
    private func restore() {
        do {
            _ = try TeamCatalog.restore(draft.base.id)
            onSaved(draft.base.id)
        } catch {
            errorText = "Could not restore this team."
        }
    }

    private func skillName(_ id: String) -> String { SkillCatalog.get(id)?.displayName ?? id }
    /// A row's display name — the chosen name for a not-yet-created skill, else the
    /// resolved skill name.
      private func skillLabel(_ r: TeamDraft.Row) -> String {
        skillName(r.skillId)
    }
    private func modelName(_ id: String?) -> String? {
        guard let id else { return nil }
        return models.first { $0.id == id }?.displayName ?? id
    }

    private func friendly(_ e: CatalogError) -> String {
        switch e {
        case .skillLaneMismatch: return "One of these skills belongs to another lane. Pick a \(lane.label.lowercased()) skill."
        case .teamInvalid(let why): return why
        case .idCollision: return "A team with that name already exists — try another name."
        default: return "Could not save this team."
        }
    }
}

// MARK: - Edit skill (level 2)

/// Edit skill: Skill → skill.md. Model is staffed on the roster row; catalog writes commit on Done.
private struct EditSkillView: View {
    let teamName: String
    let isLead: Bool
    let lane: ComposeLane
    let models: [Model]
    let laneSkills: [Skill]
    let defaultPurpose: SkillPurpose
    let row: TeamDraft.Row
    var onDone: (TeamDraft.Row) -> Void
    var onCancel: () -> Void

    @State private var skillId: String
    @State private var templateText: String
    @State private var isNewSkill: Bool
    @State private var newSkillName: String
    @State private var errorText: String?

    init(teamName: String, isLead: Bool = false, lane: ComposeLane, models: [Model],
         laneSkills: [Skill], defaultPurpose: SkillPurpose = .answer,
         row: TeamDraft.Row, onDone: @escaping (TeamDraft.Row) -> Void, onCancel: @escaping () -> Void) {
        self.teamName = teamName; self.isLead = isLead; self.lane = lane; self.models = models
        self.laneSkills = laneSkills; self.defaultPurpose = defaultPurpose; self.row = row
        self.onDone = onDone; self.onCancel = onCancel
        _skillId = State(initialValue: row.skillId)
        _templateText = State(initialValue: SkillCatalog.get(row.skillId)?.template ?? "")
        _isNewSkill = State(initialValue: row.skillId.isEmpty)
        _newSkillName = State(initialValue: "")
    }

    private var skill: Skill? { isNewSkill ? nil : SkillCatalog.get(skillId) }
    private var canRestore: Bool {
        !isNewSkill && SkillCatalog.hasOverride(skillId)
    }
    private var currentSkillLabel: String {
        if isNewSkill { return newSkillName.isEmpty ? "New skill" : newSkillName }
        return skill?.displayName ?? skillId
    }
    private var chosenNewName: String? {
        let t = newSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    private var isDoneEnabled: Bool {
        guard !templateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isNewSkill ? chosenNewName != nil : !skillId.isEmpty
    }
    private var blastRadiusLine: String {
        if isNewSkill {
            return "New skill — not used until you save this team."
        }
        let names = SkillCatalog.teamDisplayNamesReferencingSkill(skillId)
        if names.isEmpty { return "This skill is not used by a saved team yet." }
        return "This skill is used by \(names.count) team\(names.count == 1 ? "" : "s"): \(names.joined(separator: " · "))"
    }
    private func modelLabel(_ id: String?) -> String {
        guard let id else { return "Auto" }
        return models.first { $0.id == id }?.displayName ?? id
    }
    private func skillPickerTag(_ skill: Skill) -> String {
        switch SkillCatalog.origin(of: skill.id) {
        case .seed: return "built-in"
        case .override: return "edited"
        case .custom: return "custom"
        case .none: return "custom"
        }
    }

    private func beginNewSkill(named name: String = "") {
        isNewSkill = true
        skillId = ""
        newSkillName = name
        templateText = ""
        errorText = nil
    }

    private func restoreDefault() {
        guard canRestore else { return }
        do {
            _ = try SkillCatalog.restore(skillId)
            templateText = SkillCatalog.get(skillId)?.template ?? ""
            errorText = nil
        } catch {
            errorText = "Could not restore this skill."
        }
    }

    private func commitDone() {
        do {
            let result = try WorkerSkillCommit.apply(.init(
                skillId: skillId,
                template: templateText,
                modelId: row.modelId,
                lane: lane.workLane,
                defaultPurpose: defaultPurpose,
                isNewSkill: isNewSkill,
                newSkillName: chosenNewName
            ))
            var updated = row
            updated.skillId = result.skillId
            updated.modelId = result.modelId
            onDone(updated)
        } catch let e as CatalogError {
            errorText = friendly(e)
        } catch {
            errorText = "Could not save this skill."
        }
    }

    private func friendly(_ e: CatalogError) -> String {
        switch e {
        case .skillInvalid(let why): return why
        case .skillNotFound: return "Skill not found."
        default: return "Could not save this skill."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    skillField
                    if isNewSkill { newSkillNameField }
                    skillMdEditor
                    Text(blastRadiusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(ALColor.textSecondary)
                    Text("Model applies to this team only — change it on the roster row.")
                        .font(.system(size: 11))
                        .foregroundStyle(ALColor.textFaint)
                    if let errorText {
                        Text(errorText).font(.system(size: 11)).foregroundStyle(ALColor.accentText)
                    }
                }
                .padding(20)
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) { Image(systemName: "arrow.left").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(ALColor.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit skill · \(currentSkillLabel)")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Text(headerSubtitle)
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var headerSubtitle: String {
        let model = modelLabel(row.modelId)
        if isLead { return "\(model) · \(teamName) · Team lead" }
        return "\(model) · \(teamName)"
    }

    private var skillField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SKILL").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                Spacer(minLength: 0)
                if canRestore {
                    Button("Restore default", action: restoreDefault)
                        .buttonStyle(.alSecondary(small: true))
                }
                Button(action: { beginNewSkill() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ALColor.accentText)
                        .frame(width: 22, height: 22)
                        .background(ALColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: ALRadius.sm))
                }
                .buttonStyle(.plain)
                .help("New skill")
            }
            ALSearchableDropdown(
                current: currentSkillLabel,
                items: laneSkills.map {
                    ALComboItem(id: $0.id, label: $0.displayName, tag: skillPickerTag($0))
                },
                placeholder: "Search \(lane.label.lowercased()) skills…",
                onPick: { newId in
                    skillId = newId
                    isNewSkill = false
                    newSkillName = ""
                    templateText = SkillCatalog.get(newId)?.template ?? ""
                    errorText = nil
                },
                onCreate: { typed in beginNewSkill(named: typed) }
            )
        }
    }

    private var newSkillNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SKILL NAME").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            TextField("Name your new skill", text: $newSkillName)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    private var skillMdEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("skill.md").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            TextEditor(text: $templateText)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(ALColor.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(10)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Cancel skill changes", action: onCancel).buttonStyle(.alSecondary(small: true))
            Button("Done", action: commitDone)
                .buttonStyle(.alPrimary(small: true))
                .disabled(!isDoneEnabled)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}
