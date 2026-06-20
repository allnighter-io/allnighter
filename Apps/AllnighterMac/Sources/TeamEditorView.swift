import SwiftUI
import AllnighterCore

// The Customize-team editor (design-customize.png). A safe, in-memory DRAFT:
// nothing touches the catalog until Save; Cancel just drops it. Editing a built-in
// duplicates it to a NEW custom (the built-in is never mutated). Models are always
// picked by NAME — never "strongest" (founder ICP rule).

/// In-memory edit state for one team. Pure of UI; `commit()` is the only write.
struct TeamDraft: Equatable {
    let base: TeamPreset
    var name: String
    var rows: [Row]
    /// The mandatory Team Lead (synthesizer) — exactly one, never removable. Editable
    /// like a worker (skill + model + prompt); its prompt forks on save the same way.
    var lead: Row
    var allowSubstitutions: Bool
    var mutating: Bool

    /// One worker's pending edit state (the rescue's TeamWorkerDraft). Prompt edits
    /// live here and are forked into a custom skill ONLY at team Save — never
    /// mutating the shared/built-in skill, never written before Save.
    struct Row: Identifiable, Equatable {
        let id: String
        var skillId: String
        var modelId: String?
        var purpose: TeamWorkerPurpose
        /// Edited prompt for this worker. nil = use `skillId`'s template as-is (no fork).
        var promptDraft: String? = nil
        /// The skill whose template seeded `promptDraft` (so a skill change can ask
        /// before discarding an edit).
        var promptBaseSkillId: String? = nil
        /// User-chosen name for the would-be custom skill. nil = auto-name a fork
        /// "<Skill> for <Team>". An empty `skillId` means a brand-new skill (type-to-
        /// create) named by this; it then requires `promptDraft`.
        var customSkillName: String? = nil
    }

    /// Seed from a base team. The name stays the base team's real name — selecting a
    /// built-in must NOT preemptively rename it to "(custom)"; that only happens at
    /// Save (see `commit()`). Rows pre-fill with the row's pinned model, else a
    /// concrete default so the user starts with real names.
    init(base: TeamPreset, defaultModelId: String?) {
        self.base = base
        self.name = base.displayName
        self.allowSubstitutions = true
        self.mutating = base.mutating
        self.rows = base.workerSpecs.map { spec in
            Row(id: UUID().uuidString, skillId: spec.skillId,
                modelId: spec.preferredModelId ?? defaultModelId,
                purpose: spec.purpose)
        }
        // The Team Lead. Its Row.purpose is unused (the Lead is the synthesizer,
        // not an answer/review worker); commit() writes a TeamLeadSpec.
        self.lead = Row(id: "lead", skillId: base.lead.skillId,
                        modelId: base.lead.preferredModelId ?? defaultModelId,
                        purpose: .answer)
    }

    /// A role is complete when it has a model and either an existing skill or a
    /// fully-specified new skill (name + prompt) to create on save.
    static func rowComplete(_ r: Row) -> Bool {
        guard r.modelId != nil else { return false }
        guard r.skillId.isEmpty else { return true }
        let hasName = !((r.customSkillName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let hasPrompt = !((r.promptDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return hasName && hasPrompt
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

    /// Persist as a custom team and return its id. Built-in base → duplicate to a
    /// fresh custom; existing custom → save in place. Throws CatalogError on
    /// validation failure (e.g. a skill from another lane).
    /// Save-time forking (rescue S01A): one transaction-like sequence.
    ///   for each row with an edited prompt → fork a custom skill, repoint the row;
    ///   then save the custom team. If anything fails, roll back every custom skill
    ///   (and a freshly-duplicated team) created in this attempt — no orphans.
    /// Built-in source skills/teams are never mutated; the fork is a normal custom
    /// SkillDefinition named "<Skill> for <Team>".
    @discardableResult
    func commit() throws -> TeamID {
        let fallback: ModelFallbackPolicy = allowSubstitutions ? .laneCapable : .exactOnly
        // Built-ins become "<name> (custom)" only at Save, and only if the user
        // didn't already rename it — never preemptively on selection.
        let saveName = (base.builtIn && name == base.displayName) ? "\(name) (custom)" : name
        var forkedSkillIds: [SkillID] = []
        var duplicatedTeamId: TeamID?

        func rollback() {
            for id in forkedSkillIds { try? SkillCatalog.deleteCustom(id) }
            if let duplicatedTeamId { try? TeamCatalog.deleteCustom(duplicatedTeamId) }
        }

        // A row's effective skill. Makes a custom skill when the prompt was edited
        // (fork) OR there's no source skill (type-to-create). Otherwise the skill is
        // used as-is. The custom name is the user's chosen name, else auto
        // "<Skill> for <Team>". Tracked for rollback. Shared by workers + Lead.
        func resolveSkill(_ row: Row, defaultPurpose: SkillPurpose) throws -> String {
            let prompt = (row.promptDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let makesCustom = !prompt.isEmpty || row.skillId.isEmpty
            guard makesCustom else { return row.skillId }
            let source = SkillCatalog.get(row.skillId)
            let chosen = (row.customSkillName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = chosen.isEmpty ? "\(source?.displayName ?? row.skillId) for \(saveName)" : chosen
            let custom = try SkillCatalog.createCustom(
                lane: base.lane, name: name,
                purpose: source?.purpose ?? defaultPurpose, template: prompt
            )
            forkedSkillIds.append(custom.id)
            return custom.id
        }

        do {
            // 1) Fork edited prompts into custom skills; build the worker specs.
            let effectiveRows = mutating ? Array(rows.prefix(1)) : rows
            let specs: [TeamWorkerSpec] = try effectiveRows.map { row in
                TeamWorkerSpec(
                    id: row.id, skillId: try resolveSkill(row, defaultPurpose: .answer),
                    purpose: row.purpose, preferredModelId: row.modelId,
                    count: 1, fallbackPolicy: fallback, required: true
                )
            }
            // 1b) The Team Lead. For an answer team this is the synthesizer (fork its
            // prompt the same way). For a MUTATING team there is no separate lead —
            // the single agent IS the source, so mirror the worker into the lead slot
            // the data model still carries (kept identical, never a second agent).
            let leadSpec: TeamLeadSpec
            if mutating, let only = specs.first {
                leadSpec = TeamLeadSpec(
                    skillId: only.skillId,
                    preferredModelId: only.preferredModelId,
                    fallbackPolicy: fallback,
                    dissentPolicy: base.lead.dissentPolicy
                )
            } else {
                leadSpec = TeamLeadSpec(
                    skillId: try resolveSkill(lead, defaultPurpose: .planWriter),
                    preferredModelId: lead.modelId,
                    fallbackPolicy: fallback,
                    dissentPolicy: base.lead.dissentPolicy
                )
            }

            // 2) Save the custom team. Built-in source → duplicate to a fresh custom;
            // an existing custom → save in place; a brand-new draft (Add team) →
            // mint a fresh custom id and create it.
            var team: TeamPreset
            if base.builtIn {
                team = try TeamCatalog.duplicateBuiltIn(base.id, name: saveName)
                duplicatedTeamId = team.id
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
            team.mutating = mutating
            if mutating {
                team.executionSourceId = try Self.resolvedExecutionSourceId(from: specs, lead: leadSpec)
            } else {
                team.executionSourceId = nil
            }
            try TeamCatalog.validateExecutionSourceGate(team)
            try TeamCatalog.saveCustom(team)
            return team.id
        } catch {
            rollback()
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
    /// True when editing a brand-new (not-yet-saved) team — the footer reads
    /// "Create team" rather than "Duplicate Team" / "Save changes".
    let isNew: Bool
    /// Drop the in-memory edits and rebuild a fresh draft from the base team.
    var onRevert: () -> Void
    var onSaved: (TeamID) -> Void

    @State private var draft: TeamDraft
    @State private var errorText: String?
    /// Level-2: which worker row is open in the Customize-worker editor (nil = the
    /// team roster). The pane pushes to the worker editor and back.
    @State private var editingRow: Int?
    /// Level-2 for the Team Lead (separate from worker rows; the Lead is pinned).
    @State private var editingLead = false

    init(base: TeamPreset, lane: ComposeLane, models: [Model], readyModels: [Model],
         isNew: Bool = false,
         onRevert: @escaping () -> Void, onSaved: @escaping (TeamID) -> Void) {
        self.lane = lane
        self.models = models
        self.isNew = isNew
        self.onRevert = onRevert
        self.onSaved = onSaved
        _draft = State(initialValue: TeamDraft(base: base, defaultModelId: readyModels.first?.id ?? models.first?.id))
    }

    /// True until this team has been forked to a custom — Save creates a copy and
    /// the built-in source is never mutated.
    private var isBuiltIn: Bool { draft.base.builtIn }

    private var laneSkills: [Skill] { SkillCatalog.list(lane: lane.workLane) }
    /// The Lead picks among plan-writer skills only — it's the synthesizer, not an
    /// answer/review worker.
    private var leadSkills: [Skill] { laneSkills.filter { $0.purpose == .planWriter } }

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
                    teamName: draft.name, roleLabel: "Team Lead", lane: lane, models: models, laneSkills: leadSkills,
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
                    workers
                    substitutionsToggle
                    executionPostureSection
                    summary
                }
                .padding(20)
            }
            footer
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(ALColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Text(isBuiltIn ? "Built-in · edits save as your own team" : "\(lane.label) team · skill | model")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 0)
            if isBuiltIn {
                Text("BUILT-IN").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(ALColor.textMuted.opacity(0.14), in: Capsule())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
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
                    .foregroundStyle(ALColor.accentText)
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
                    Image(systemName: "megaphone.fill").font(.system(size: 11)).foregroundStyle(ALColor.accentText)
                    Text(skillLabel(draft.lead))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                    if draft.lead.promptDraft != nil {
                        Circle().fill(ALColor.accent).frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
                }
                .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
                .background(ALColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.accent.opacity(0.4), lineWidth: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            picker(current: modelName(draft.lead.modelId) ?? "Pick a model", options: models.map { ($0.id, $0.displayName) }) {
                draft.lead.modelId = $0
            }
            // Width-match the workers' × column so the model dropdowns align.
            Color.clear.frame(width: 14, height: 1)
        }
    }

    private var workers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.mutating ? "AGENT" : "WORKERS")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(draft.mutating ? ALColor.accentText : ALColor.textFaint)
            if draft.mutating {
                Text("One agent does the work in the repo root — no separate lead.")
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
                            if $row.wrappedValue.promptDraft != nil {
                                Circle().fill(ALColor.accent).frame(width: 5, height: 5)
                            }
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
                    picker(current: modelName($row.wrappedValue.modelId) ?? "Pick a model", options: models.map { ($0.id, $0.displayName) }) {
                        $row.wrappedValue.modelId = $0
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
                                        modelId: models.first?.id, purpose: .answer))
            } label: {
                Label("Add worker", systemImage: "plus").font(.system(size: 12, weight: .medium))
            }
            .disabled(draft.mutating)
            .buttonStyle(.plain).foregroundStyle(ALColor.accentText).padding(.top, 2)
        }
    }

    // Custom dropdown (never the native Menu — it breaks the dark UI).
    private func picker(current: String, options: [(String, String)], onPick: @escaping (String) -> Void) -> some View {
        ALDropdown(current: current, options: options, onPick: onPick)
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
                Text("Execution source: \(source)").font(.system(size: 11)).foregroundStyle(ALColor.accentText)
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
                Spacer(minLength: 0)
                Button("Revert", action: onRevert).buttonStyle(.alSecondary(small: true))
                Button(isNew ? "Create team" : (isBuiltIn ? "Duplicate Team" : "Save changes"), action: save)
                    .buttonStyle(.alPrimary(small: true)).disabled(!draft.isSavable)
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

    private func skillName(_ id: String) -> String { SkillCatalog.get(id)?.displayName ?? id }
    /// A row's display name — the chosen name for a not-yet-created skill, else the
    /// resolved skill name.
    private func skillLabel(_ r: TeamDraft.Row) -> String {
        r.skillId.isEmpty ? (r.customSkillName ?? "New skill") : skillName(r.skillId)
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

/// The focused worker editor: the skill (hat), its full PROMPT (editable), and the
/// model — everything for one worker in one place (rescue S01B). Edits stay in the
/// in-memory team draft; the prompt is forked into a custom skill only at team Save.
private struct CustomizeWorkerView: View {
    let teamName: String
    /// "worker" or "Team Lead" — only affects the header copy.
    let roleLabel: String
    let lane: ComposeLane
    let models: [Model]
    let laneSkills: [Skill]
    let row: TeamDraft.Row
    var onDone: (TeamDraft.Row) -> Void
    var onCancel: () -> Void

    @State private var skillId: String
    @State private var modelId: String?
    @State private var promptText: String
    /// Type-to-create: building a brand-new skill (no source). Name is required.
    @State private var isNew: Bool
    /// User-chosen name for the would-be custom skill (fork or new).
    @State private var customName: String

    init(teamName: String, roleLabel: String = "worker", lane: ComposeLane, models: [Model], laneSkills: [Skill],
         row: TeamDraft.Row, onDone: @escaping (TeamDraft.Row) -> Void, onCancel: @escaping () -> Void) {
        self.teamName = teamName; self.roleLabel = roleLabel; self.lane = lane; self.models = models
        self.laneSkills = laneSkills; self.row = row; self.onDone = onDone; self.onCancel = onCancel
        _skillId = State(initialValue: row.skillId)
        _modelId = State(initialValue: row.modelId)
        _promptText = State(initialValue: row.promptDraft ?? (SkillCatalog.get(row.skillId)?.template ?? ""))
        _isNew = State(initialValue: row.skillId.isEmpty)
        _customName = State(initialValue: row.customSkillName ?? "")
    }

    private var skill: Skill? { SkillCatalog.get(skillId) }
    private var template: String { skill?.template ?? "" }
    private var isForked: Bool {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            != template.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// True when this edit will produce a custom skill (a fork or a brand-new one).
    private var willSaveAsCustom: Bool { isNew || isForked }
    /// What the SKILL field + header show — the chosen name for a new skill, else
    /// the picked skill's name.
    private var currentSkillLabel: String {
        if isNew { return customName.isEmpty ? "New skill" : customName }
        return skill?.displayName ?? skillId
    }
    private var autoForkName: String { "\(skill?.displayName ?? skillId) for \(teamName)" }
    /// The trimmed chosen name, or nil to let commit auto-name a fork.
    private var chosenName: String? {
        let t = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    /// Done is allowed with a model, a non-empty prompt, and — for a new skill — a name.
    private var isDone: Bool {
        guard modelId != nil, !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isNew ? (chosenName != nil) : true
    }
    private func modelName(_ id: String?) -> String {
        guard let id else { return "Pick a model" }
        return models.first { $0.id == id }?.displayName ?? id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("SKILL") {
                        ALSearchableDropdown(
                            current: currentSkillLabel,
                            items: laneSkills.map { ALComboItem(id: $0.id, label: $0.displayName,
                                                                tag: $0.builtIn ? "built-in" : "custom") },
                            placeholder: "Search \(lane.label.lowercased()) skills…",
                            onPick: { newId in
                                // Don't silently discard an edit: only reload the template
                                // when the prompt is still the current skill's template.
                                if promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    == template.trimmingCharacters(in: .whitespacesAndNewlines) {
                                    promptText = SkillCatalog.get(newId)?.template ?? ""
                                }
                                skillId = newId; isNew = false; customName = ""
                            },
                            onCreate: { typed in
                                // Type-to-create: a brand-new skill named `typed`, empty
                                // prompt to fill in below; persists on team Save.
                                isNew = true; skillId = ""; customName = typed; promptText = ""
                            }
                        )
                    }
                    if willSaveAsCustom { skillNameField }
                    field("MODEL") {
                        ALDropdown(current: modelName(modelId),
                                   options: models.map { ($0.id, $0.displayName) }) { modelId = $0 }
                    }
                    metadata
                    promptEditor
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
                Text("Customize \(roleLabel)").font(.system(size: 14, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Text("\(teamName) · \(currentSkillLabel) | \(modelName(modelId))")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            content()
        }
    }

    /// Shown only when the edit will create a custom skill — name it (or accept the
    /// suggested fork name).
    private var skillNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SKILL NAME").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            TextField(isNew ? "Name your new skill" : autoForkName, text: $customName)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            Text(isNew
                 ? "Saved as a new custom \(lane.label.lowercased()) skill on Save."
                 : "Your edit forks a custom skill — name it, or leave blank for \u{201C}\(autoForkName)\u{201D}.")
                .font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            chip(lane.label)
            if isNew {
                chip("new")
            } else {
                chip(skill?.purpose.rawValue ?? "answer")
                chip(willSaveAsCustom ? "custom" : ((skill?.builtIn ?? true) ? "from a template" : "custom"))
            }
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PROMPT").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                if willSaveAsCustom {
                    Text(isNew ? "· new custom skill" : "· will save as a custom skill")
                        .font(.system(size: 10)).foregroundStyle(ALColor.accentText)
                }
                Spacer(minLength: 0)
            }
            TextEditor(text: $promptText)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(ALColor.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(10)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(ALColor.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(ALColor.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Cancel \(roleLabel) changes", action: onCancel).buttonStyle(.alSecondary(small: true))
            Button("Done") {
                var updated = row
                updated.skillId = isNew ? "" : skillId
                updated.modelId = modelId
                updated.promptDraft = willSaveAsCustom ? promptText : nil
                updated.promptBaseSkillId = (willSaveAsCustom && !isNew) ? skillId : nil
                updated.customSkillName = willSaveAsCustom ? chosenName : nil
                onDone(updated)
            }
            .buttonStyle(.alPrimary(small: true))
            .disabled(!isDone)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}
