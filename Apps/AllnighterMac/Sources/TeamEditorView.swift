import SwiftUI
import AllnighterCore

// The Customize-team editor (design-customize.png). A safe, in-memory DRAFT:
// nothing touches the catalog until Save; Cancel just drops it. Editing a built-in
// duplicates it to a NEW custom (the built-in is never mutated). Models are always
// picked by NAME — never "strongest" (founder ICP rule).

/// In-memory edit state for one team. Pure of UI; `commit()` writes roster only.
/// Skill bodies commit separately via `WorkerSkillCommit` on Worker Done.
struct TeamDraft: Equatable {
    let base: TeamPreset
    var name: String
    var rows: [Row]
    var lead: Row
    var scout: Row?
    var allowSubstitutions: Bool
    var mutating: Bool

    /// One worker's roster row (skill + model). Skill catalog writes happen on Worker Done.
    struct Row: Identifiable, Equatable {
        let id: String
        var skillId: String
        var modelId: String?
        var purpose: TeamWorkerPurpose
    }

    /// Seed from a base team. The name stays the base team's real name — selecting a
    /// built-in must NOT preemptively rename it to "(custom)"; that only happens at
    /// Save (see `commit()`). A row keeps its pinned model; an UNPINNED row stays nil
    /// = **Auto** (the resolver picks a ready model at run time) — we never coerce it
    /// to a concrete model the user didn't choose. Row ids mirror the spec ids so
    /// commit() can carry forward per-row facts (triangulation, count).
    init(base: TeamPreset) {
        self.base = base
        self.name = base.displayName
        self.allowSubstitutions = true
        self.mutating = base.mutating
        self.rows = base.workerSpecs.map { spec in
            Row(id: spec.id, skillId: spec.skillId, modelId: spec.preferredModelId, purpose: spec.purpose)
        }
        // The Team Lead. Its Row.purpose is unused (the Lead is the synthesizer,
        // not an answer/review worker); commit() writes a TeamLeadSpec.
        self.lead = Row(id: "lead", skillId: base.lead.skillId,
                        modelId: base.lead.preferredModelId, purpose: .answer)
        // Stage-0 scout (Signal): pinned model (Grok), shown above the workers.
        self.scout = base.scout.map { s in
            Row(id: s.id, skillId: s.skillId, modelId: s.preferredModelId, purpose: s.purpose)
        }
    }

    /// A role is complete when it has a skill id. nil model = Auto.
    static func rowComplete(_ r: Row) -> Bool {
        !r.skillId.isEmpty
    }

    /// Save is allowed only when every role — and the Lead — is complete.
    var isSavable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !rows.isEmpty &&
        (!mutating || rows.count == 1) &&
        rows.allSatisfy(Self.rowComplete) &&
        // A mutating team has no separate lead — the single agent is the source.
        (mutating || Self.rowComplete(lead))
    }

    /// Persist roster facts only (skill ids + model picks). Skill bodies are committed
    /// on Worker Done via `WorkerSkillCommit`, not here.
    @discardableResult
    func commit() throws -> TeamID {
        if mutating {
            let bench = Dictionary(ModelCatalog.list().map { ($0.id, $0.driverId) },
                                   uniquingKeysWith: { a, _ in a })
            let sources = Set(rows.compactMap { $0.modelId.flatMap { bench[$0] } })
            if sources.count > 1 {
                throw CatalogError.teamInvalid("Execution teams run on one CLI. Pick one source for all workers.")
            }
        }
        let fallback: ModelFallbackPolicy = allowSubstitutions ? .laneCapable : .exactOnly
        let saveName = name
        var duplicatedTeamId: TeamID?

        let effectiveRows = mutating ? Array(rows.prefix(1)) : rows
        let specs: [TeamWorkerSpec] = try effectiveRows.map { row in
            guard !row.skillId.isEmpty else {
                throw CatalogError.teamInvalid("every worker needs a skill")
            }
            let original = base.workerSpecs.first { $0.id == row.id }
            return TeamWorkerSpec(
                id: row.id, skillId: row.skillId,
                purpose: row.purpose, preferredModelId: row.modelId,
                fallbackModelIds: original?.fallbackModelIds,
                allowedModelIds: original?.allowedModelIds ?? [],
                requiredCapabilityTags: original?.requiredCapabilityTags ?? [],
                count: original?.count ?? 1, fallbackPolicy: fallback,
                required: original?.required ?? true,
                triangulate: original?.triangulate ?? false,
                triangulatePreferenceIds: original?.triangulatePreferenceIds ?? []
            )
        }
        let leadSpec: TeamLeadSpec
        if mutating, let only = specs.first {
            leadSpec = TeamLeadSpec(
                skillId: only.skillId,
                preferredModelId: only.preferredModelId,
                fallbackModelIds: only.fallbackModelIds,
                requiredCapabilityTags: only.requiredCapabilityTags,
                fallbackPolicy: fallback,
                dissentPolicy: base.lead.dissentPolicy
            )
        } else {
            guard !lead.skillId.isEmpty else {
                throw CatalogError.teamInvalid("the team lead needs a skill")
            }
            leadSpec = TeamLeadSpec(
                skillId: lead.skillId,
                preferredModelId: lead.modelId,
                fallbackModelIds: base.lead.fallbackModelIds,
                requiredCapabilityTags: base.lead.requiredCapabilityTags,
                fallbackPolicy: fallback,
                dissentPolicy: base.lead.dissentPolicy
            )
        }

        var team: TeamPreset
        if base.builtIn {
            team = base
        } else if let existing = TeamCatalog.get(base.id) {
            team = existing
        } else {
            let newId = TeamCatalog.freshCustomId(lane: base.lane, displayName: saveName)
            team = base.duplicated(newId: newId, newName: saveName)
            duplicatedTeamId = team.id
        }
        team.displayName = saveName
        team.workerSpecs = specs
        team.lead = leadSpec
        if let s = scout {
            let original = base.scout
            team.scout = TeamWorkerSpec(
                id: s.id, skillId: s.skillId, purpose: .answer,
                preferredModelId: s.modelId,
                fallbackModelIds: original?.fallbackModelIds,
                allowedModelIds: original?.allowedModelIds ?? [],
                requiredCapabilityTags: original?.requiredCapabilityTags ?? [],
                count: original?.count ?? 1,
                fallbackPolicy: original?.fallbackPolicy ?? .laneCapable,
                required: original?.required ?? true,
                triangulate: original?.triangulate ?? false,
                triangulatePreferenceIds: original?.triangulatePreferenceIds ?? [])
        } else {
            team.scout = nil
        }
        team.mutating = mutating
        if mutating {
            team.executionSourceId = try Self.resolvedExecutionSourceId(from: specs, lead: leadSpec)
        } else {
            team.executionSourceId = nil
        }
        do {
            try TeamCatalog.validateExecutionSourceGate(team)
            try TeamCatalog.saveCustom(team)
            return team.id
        } catch {
            if let duplicatedTeamId { try? TeamCatalog.deleteCustom(duplicatedTeamId) }
            throw error
        }
    }

    private static func resolvedExecutionSourceId(from specs: [TeamWorkerSpec], lead: TeamLeadSpec) throws -> String? {
        let bench = Dictionary(ModelCatalog.list().map { ($0.id, $0.driverId) }, uniquingKeysWith: { a, _ in a })
        var sources = Set<String>()
        for row in specs {
            if let mid = row.preferredModelId, let source = bench[mid] { sources.insert(source) }
        }
        if let mid = lead.preferredModelId, let source = bench[mid] { sources.insert(source) }
        guard sources.count <= 1 else { return nil }
        return sources.first
    }
}

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
    /// Level-2: which worker row is open in the Customize-worker editor (nil = the
    /// team roster). The pane pushes to the worker editor and back.
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
        for spec in draft.base.workerSpecs where !spec.skillId.isEmpty { refIds.insert(spec.skillId) }
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
                CustomizeWorkerView(
                    teamName: draft.name, roleLabel: "worker", lane: lane, models: models, laneSkills: laneSkills,
                    row: draft.rows[i],
                    onDone: { updated in draft.rows[i] = updated; editingRow = nil },
                    onCancel: { editingRow = nil }
                )
            } else if editingLead {
                CustomizeWorkerView(
                    teamName: draft.name, roleLabel: "Team Lead", lane: lane, models: models,
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
                                : "\(lane.label) team · skill | model")
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
            leadRow
            Text("Reads every worker's output and writes the single answer.")
                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
    }

    private var leadRow: some View {
        HStack(spacing: 8) {
            // Skill cell opens the same level-2 editor (skill + prompt + model). No
            // remove button — the Lead is mandatory.
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

            modelPicker(draft.lead.modelId) { draft.lead.modelId = $0 }
            // Width-match the workers' × column so the model dropdowns align.
            Color.clear.frame(width: 14, height: 1)
        }
    }

    private var workers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.mutating ? "AGENT" : "WORKERS")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            if draft.mutating {
                Text(isDefaultAutoTeam
                     ? "Auto runs your Default model — set which model that is in Default model. Editing it here won't change Auto."
                     : "One agent does the work in the repo root — no separate lead.")
                    .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            }
            ForEach($draft.rows) { $row in
                HStack(spacing: 8) {
                    // Skill cell opens the level-2 Customize-worker editor (skill +
                    // prompt + model). A dot marks a worker whose prompt is tuned.
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

                    // Model quick-swap stays inline (rescue: fast model change on the row).
                    // A triangulated row reads on several distinct CLIs — shown read-only.
                    // The Auto team's model is owned by the Default-model screen, shown
                    // read-only here (a per-team pick would be silently ignored by the run).
                    if isDefaultAutoTeam {
                        defaultModelCell
                    } else if isTriangulated(row.id) {
                        triangulatedModelCell(count: triangulateCount(row.id))
                    } else {
                        modelPicker($row.wrappedValue.modelId) { $row.wrappedValue.modelId = $0 }
                    }
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
                Label("Add worker", systemImage: "plus").font(.system(size: 12, weight: .medium))
            }
            .disabled(draft.mutating)
            .buttonStyle(.plain).foregroundStyle(ALColor.textSecondary).padding(.top, 2)
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
    }

    /// A model picker whose first option is Auto (nil). Picking Auto clears the pin.
    private func modelPicker(_ id: String?, onPick: @escaping (String?) -> Void) -> some View {
        let options = [(Self.autoOptionId, "Auto")] + models.map { ($0.id, $0.displayName) }
        return picker(current: modelDisplay(id), options: options) { picked in
            onPick(picked == Self.autoOptionId ? nil : picked)
        }
    }

    private func isTriangulated(_ rowId: String) -> Bool {
        draft.base.workerSpecs.first { $0.id == rowId }?.triangulate ?? false
    }
    private func triangulateCount(_ rowId: String) -> Int {
        max(1, draft.base.workerSpecs.first { $0.id == rowId }?.count ?? 3)
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
                HStack(spacing: 8) {
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

                    // Scout shows a concrete model (Grok), not Auto — its model is
                    // load-bearing (only Grok reads X).
                    picker(current: modelDisplay(scout.modelId),
                           options: models.map { ($0.id, $0.displayName) }) { draft.scout?.modelId = $0 }
                    Color.clear.frame(width: 14, height: 1)
                }
                Text("Grok grabs the public link/post and distills it for the workers.")
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
                    Text("Runs one worker in the repo root under the write lock.")
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
        return "Execution teams run on one CLI. Pick one source for all workers."
    }

    private var summary: some View {
        Text(draft.mutating
             ? "1 agent · runs in the repo root under the write lock · saved as a \(lane.label.lowercased()) team you can pick in the composer."
             : "\(draft.rows.count) workers + 1 lead · saved as a \(lane.label.lowercased()) team you can pick in the composer.")
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

// MARK: - Customize worker (level 2)

/// Edit worker: Model → Skill → skill.md. Skill catalog writes commit on Done.
private struct CustomizeWorkerView: View {
    let teamName: String
    let roleLabel: String
    let lane: ComposeLane
    let models: [Model]
    let laneSkills: [Skill]
    let defaultPurpose: SkillPurpose
    let row: TeamDraft.Row
    var onDone: (TeamDraft.Row) -> Void
    var onCancel: () -> Void

    @State private var skillId: String
    @State private var modelId: String?
    @State private var templateText: String
    @State private var isNewSkill: Bool
    @State private var newSkillName: String
    @State private var errorText: String?

    init(teamName: String, roleLabel: String = "worker", lane: ComposeLane, models: [Model],
         laneSkills: [Skill], defaultPurpose: SkillPurpose = .answer,
         row: TeamDraft.Row, onDone: @escaping (TeamDraft.Row) -> Void, onCancel: @escaping () -> Void) {
        self.teamName = teamName; self.roleLabel = roleLabel; self.lane = lane; self.models = models
        self.laneSkills = laneSkills; self.defaultPurpose = defaultPurpose; self.row = row
        self.onDone = onDone; self.onCancel = onCancel
        _skillId = State(initialValue: row.skillId)
        _modelId = State(initialValue: row.modelId)
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
            return "New skill — it is not used until you save this team."
        }
        let names = SkillCatalog.teamDisplayNamesReferencingSkill(skillId)
        if names.isEmpty { return "Not used by a saved team yet." }
        return "Shared across \(names.count) team\(names.count == 1 ? "" : "s"): \(names.joined(separator: " · "))"
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
                modelId: modelId,
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
                    field("MODEL") { modelField }
                    skillField
                    if isNewSkill { newSkillNameField }
                    skillMdEditor
                    Text(blastRadiusLine)
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
                Text("Edit \(roleLabel.lowercased()) · \(teamName)")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Text("\(currentSkillLabel) · \(modelLabel(modelId))")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var modelField: some View {
        let options: [(String, String)] = [(TeamEditorView.autoOptionId, "Auto")]
            + models.map { ($0.id, $0.displayName) }
        return ALDropdown(current: modelLabel(modelId), options: options) { pick in
            modelId = pick == TeamEditorView.autoOptionId ? nil : pick
        }
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

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            content()
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
            Button("Cancel \(roleLabel) changes", action: onCancel).buttonStyle(.alSecondary(small: true))
            Button("Done", action: commitDone)
                .buttonStyle(.alPrimary(small: true))
                .disabled(!isDoneEnabled)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}
