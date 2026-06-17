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
    var allowSubstitutions: Bool

    /// One worker's pending edit state (the rescue's TeamWorkerDraft). Prompt edits
    /// live here and are forked into a custom skill ONLY at team Save — never
    /// mutating the shared/built-in skill, never written before Save.
    struct Row: Identifiable, Equatable {
        let id: String
        var skillId: String
        var modelId: String?
        var purpose: TeamWorkerPurpose
        var minEffort: EffortLevel
        /// Edited prompt for this worker. nil = use `skillId`'s template as-is (no fork).
        var promptDraft: String? = nil
        /// The skill whose template seeded `promptDraft` (so a skill change can ask
        /// before discarding an edit).
        var promptBaseSkillId: String? = nil
    }

    /// Seed from a base team. A built-in seeds a "(custom)" name; rows pre-fill with
    /// the row's pinned model, else a concrete default so the user starts with names.
    init(base: TeamPreset, defaultModelId: String?) {
        self.base = base
        self.name = base.builtIn ? "\(base.displayName) (custom)" : base.displayName
        self.allowSubstitutions = true
        self.rows = base.activeRows(at: base.defaultEffort).map { spec in
            Row(id: UUID().uuidString, skillId: spec.skillId,
                modelId: spec.preferredModelId ?? defaultModelId,
                purpose: spec.purpose, minEffort: spec.minEffort)
        }
    }

    /// Save is allowed only when every role has a skill AND a named model.
    var isSavable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !rows.isEmpty &&
        rows.allSatisfy { !$0.skillId.isEmpty && $0.modelId != nil }
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
        var forkedSkillIds: [SkillID] = []
        var duplicatedTeamId: TeamID?

        func rollback() {
            for id in forkedSkillIds { try? SkillCatalog.deleteCustom(id) }
            if let duplicatedTeamId { try? TeamCatalog.deleteCustom(duplicatedTeamId) }
        }

        do {
            // 1) Fork edited prompts into custom skills; build the worker specs.
            let specs: [TeamWorkerSpec] = try rows.map { row in
                let skillId: String
                if let prompt = row.promptDraft?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                    let source = SkillCatalog.get(row.skillId)
                    let forkName = "\(source?.displayName ?? row.skillId) for \(name)"
                    let custom = try SkillCatalog.createCustom(
                        lane: base.lane,
                        name: forkName,
                        purpose: source?.purpose ?? .answer,
                        template: prompt
                    )
                    forkedSkillIds.append(custom.id)
                    skillId = custom.id
                } else {
                    skillId = row.skillId
                }
                return TeamWorkerSpec(
                    id: row.id, skillId: skillId, purpose: row.purpose,
                    minEffort: row.minEffort, preferredModelId: row.modelId,
                    count: 1, fallbackPolicy: fallback, required: true
                )
            }

            // 2) Save the custom team. Built-in source → duplicate to a fresh custom.
            var team: TeamPreset
            if base.builtIn {
                team = try TeamCatalog.duplicateBuiltIn(base.id, name: name)
                duplicatedTeamId = team.id
            } else if let existing = TeamCatalog.get(base.id) {
                team = existing
            } else {
                throw CatalogError.teamNotFound
            }
            team.displayName = name
            team.workerSpecs = specs
            try TeamCatalog.saveCustom(team)
            return team.id
        } catch {
            rollback()
            throw error
        }
    }
}

struct TeamEditorView: View {
    let lane: ComposeLane
    let models: [Model]
    /// Drop the in-memory edits and rebuild a fresh draft from the base team.
    var onRevert: () -> Void
    var onSaved: (TeamID) -> Void

    @State private var draft: TeamDraft
    @State private var errorText: String?
    /// Level-2: which worker row is open in the Customize-worker editor (nil = the
    /// team roster). The pane pushes to the worker editor and back.
    @State private var editingRow: Int?

    init(base: TeamPreset, lane: ComposeLane, models: [Model], readyModels: [Model],
         onRevert: @escaping () -> Void, onSaved: @escaping (TeamID) -> Void) {
        self.lane = lane
        self.models = models
        self.onRevert = onRevert
        self.onSaved = onSaved
        _draft = State(initialValue: TeamDraft(base: base, defaultModelId: readyModels.first?.id ?? models.first?.id))
    }

    /// True until this team has been forked to a custom — Save creates a copy and
    /// the built-in source is never mutated.
    private var isBuiltIn: Bool { draft.base.builtIn }

    private var laneSkills: [Skill] { SkillCatalog.list(lane: lane.workLane) }

    var body: some View {
        Group {
            if let i = editingRow, draft.rows.indices.contains(i) {
                CustomizeWorkerView(
                    teamName: draft.name, lane: lane, models: models, laneSkills: laneSkills,
                    row: draft.rows[i],
                    onDone: { updated in draft.rows[i] = updated; editingRow = nil },
                    onCancel: { editingRow = nil }
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
                    workers
                    substitutionsToggle
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

    private var workers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKERS").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            ForEach($draft.rows) { $row in
                HStack(spacing: 8) {
                    // Skill cell opens the level-2 Customize-worker editor (skill +
                    // prompt + model). A dot marks a worker whose prompt is tuned.
                    Button { editingRow = draft.rows.firstIndex { $0.id == row.id } } label: {
                        HStack(spacing: 6) {
                            Text(skillName($row.wrappedValue.skillId))
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
                    Button { draft.rows.removeAll { $0.id == row.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let skillId = laneSkills.first?.id ?? ""
                draft.rows.append(.init(id: UUID().uuidString, skillId: skillId,
                                        modelId: models.first?.id, purpose: .answer, minEffort: .low))
            } label: {
                Label("Add worker", systemImage: "plus").font(.system(size: 12, weight: .medium))
            }
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

    private var summary: some View {
        Text("\(draft.rows.count) workers · saved as a \(lane.label.lowercased()) team you can pick in the composer.")
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
                Button(isBuiltIn ? "Save as my team" : "Save changes", action: save)
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
    let lane: ComposeLane
    let models: [Model]
    let laneSkills: [Skill]
    let row: TeamDraft.Row
    var onDone: (TeamDraft.Row) -> Void
    var onCancel: () -> Void

    @State private var skillId: String
    @State private var modelId: String?
    @State private var promptText: String

    init(teamName: String, lane: ComposeLane, models: [Model], laneSkills: [Skill],
         row: TeamDraft.Row, onDone: @escaping (TeamDraft.Row) -> Void, onCancel: @escaping () -> Void) {
        self.teamName = teamName; self.lane = lane; self.models = models
        self.laneSkills = laneSkills; self.row = row; self.onDone = onDone; self.onCancel = onCancel
        _skillId = State(initialValue: row.skillId)
        _modelId = State(initialValue: row.modelId)
        _promptText = State(initialValue: row.promptDraft ?? (SkillCatalog.get(row.skillId)?.template ?? ""))
    }

    private var skill: Skill? { SkillCatalog.get(skillId) }
    private var template: String { skill?.template ?? "" }
    private var isForked: Bool {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            != template.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        ALDropdown(current: skill?.displayName ?? skillId,
                                   options: laneSkills.map { ($0.id, $0.displayName) }) { newId in
                            // Don't silently discard an edit: only reload the template
                            // when the prompt is still the current skill's template.
                            if promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                                == template.trimmingCharacters(in: .whitespacesAndNewlines) {
                                promptText = SkillCatalog.get(newId)?.template ?? ""
                            }
                            skillId = newId
                        }
                    }
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
                Text("Customize worker").font(.system(size: 14, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Text("\(teamName) · \(skill?.displayName ?? skillId) | \(modelName(modelId))")
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

    private var metadata: some View {
        HStack(spacing: 6) {
            chip(lane.label)
            chip((skill?.purpose.rawValue ?? "answer"))
            chip((skill?.builtIn ?? true) ? "from a template" : "custom")
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PROMPT").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                if isForked {
                    Text("· will save as a custom skill")
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
            Button("Cancel worker changes", action: onCancel).buttonStyle(.alSecondary(small: true))
            Button("Done") {
                var updated = row
                updated.skillId = skillId
                updated.modelId = modelId
                updated.promptDraft = isForked ? promptText : nil
                updated.promptBaseSkillId = isForked ? skillId : nil
                onDone(updated)
            }
            .buttonStyle(.alPrimary(small: true))
            .disabled(modelId == nil || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}
