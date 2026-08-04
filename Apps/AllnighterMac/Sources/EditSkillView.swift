import SwiftUI
import AllnighterCore

// MARK: - Edit skill (level 2)

/// Edit skill: Skill → skill.md. Model is staffed on the roster row; catalog writes commit on Done.
struct EditSkillView: View {
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
