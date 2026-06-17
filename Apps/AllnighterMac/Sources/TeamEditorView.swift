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

    struct Row: Identifiable, Equatable {
        let id: String
        var skillId: String
        var modelId: String?
        var purpose: TeamWorkerPurpose
        var minEffort: EffortLevel
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
    @discardableResult
    func commit() throws -> TeamID {
        let fallback: ModelFallbackPolicy = allowSubstitutions ? .laneCapable : .exactOnly
        let specs = rows.map { row in
            TeamWorkerSpec(
                id: row.id, skillId: row.skillId, purpose: row.purpose,
                minEffort: row.minEffort, preferredModelId: row.modelId,
                count: 1, fallbackPolicy: fallback, required: true
            )
        }

        if base.builtIn {
            // Duplicate to a fresh custom, then save the edited rows. If the edit
            // fails validation (e.g. a wrong-lane skill), roll back the duplicate
            // so a failed Save never leaves an orphan team behind.
            var team = try TeamCatalog.duplicateBuiltIn(base.id, name: name)
            team.displayName = name
            team.workerSpecs = specs
            do {
                try TeamCatalog.saveCustom(team)
            } catch {
                try? TeamCatalog.deleteCustom(team.id)
                throw error
            }
            return team.id
        } else {
            guard var existing = TeamCatalog.get(base.id) else { throw CatalogError.teamNotFound }
            existing.displayName = name
            existing.workerSpecs = specs
            try TeamCatalog.saveCustom(existing)
            return existing.id
        }
    }
}

struct TeamEditorView: View {
    let lane: ComposeLane
    let models: [Model]
    var onCancel: () -> Void
    var onSaved: (TeamID) -> Void

    @State private var draft: TeamDraft
    @State private var errorText: String?

    init(base: TeamPreset, lane: ComposeLane, models: [Model], readyModels: [Model],
         onCancel: @escaping () -> Void, onSaved: @escaping (TeamID) -> Void) {
        self.lane = lane
        self.models = models
        self.onCancel = onCancel
        self.onSaved = onSaved
        _draft = State(initialValue: TeamDraft(base: base, defaultModelId: readyModels.first?.id ?? models.first?.id))
    }

    private var laneSkills: [Skill] { SkillCatalog.list(lane: lane.workLane) }

    var body: some View {
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
        .frame(width: 420)
        .frame(maxHeight: .infinity)
        .background(ALColor.surface)
        .overlay(alignment: .leading) { Rectangle().fill(ALColor.borderSubtle).frame(width: 1) }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(ALColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Customize team").font(.system(size: 14, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                Text("\(lane.label) · skill | model").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) { Image(systemName: "xmark").font(.system(size: 12)) }
                .buttonStyle(.plain).foregroundStyle(ALColor.textMuted)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TEAM NAME").font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            TextField("Team name", text: $draft.name)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    private var workers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKERS").font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            ForEach($draft.rows) { $row in
                HStack(spacing: 8) {
                    picker(current: skillName($row.wrappedValue.skillId), options: laneSkills.map { ($0.id, $0.displayName) }) {
                        $row.wrappedValue.skillId = $0
                    }
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

    private func picker(current: String, options: [(String, String)], onPick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.0) { id, label in Button(label) { onPick(id) } }
        } label: {
            HStack(spacing: 4) {
                Text(current).font(.system(size: 12)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
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
                Button("Cancel", action: onCancel).buttonStyle(.alSecondary(small: true))
                Button("Save", action: save).buttonStyle(.alPrimary(small: true)).disabled(!draft.isSavable)
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
