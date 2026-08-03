import SwiftUI
import AllnighterCore
import AllnighterEngine

// Send path + auto-resolution + routing bar (CM-S05). State owner: RoutingComposer.

extension RoutingComposer {

    // MARK: Send routing

    var effectivePlaceholder: String {
        if targetTab == .loop {
            return "Brief the PM — what should this loop deliver?"
        }
        return placeholder
    }

    var canSend: Bool {
        if targetTab == .loop { return true }
        // Image-only (or text-attachment-only) sends are valid — a pasted screenshot with
        // no typed text must enable Send.
        let hasBody = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasBody || !attachments.isEmpty) && onSend != nil
    }
    // MARK: Auto resolution (the chip preview == what the run will do)

    /// Model ids runnable right now — reuse AppModel's canonical availability (ON-bench
    /// AND source ready), the same gate the run path applies, so the Auto chip never
    /// previews a model the run would skip (e.g. an off-bench model whose CLI is up).
    var sourceReadyIds: Set<ModelID> { Set(appModel.availableModels.map(\.id)) }

    /// What Auto resolves to now — the tier default, or a same-tier substitute when a
    /// CLI is down. nil = the tier is fully down (Auto would wait).
    var autoModelId: String? {
        SubstitutionResolver.resolveAuto(settings: defaultSettings, readyModelIds: sourceReadyIds).resolvedModelId
    }

    /// The model the route currently runs: an explicit pin, else the team's model,
    /// else the tier-resolved Auto model.
    var selectedModelId: String? {
        if let pinnedModelId { return pinnedModelId }
        if team != nil { return resolvedModelId(forTeam: team) }
        return autoModelId
    }

    /// The model a team actually runs — its first worker's pinned model (or the
    /// lead's). This is the SSOT the composer chip must mirror, exactly as the Team
    /// Studio editor shows it. Returns nil only if the team pins nothing.
    func resolvedModelId(forTeam team: String?) -> String? {
        let preset = team.flatMap { TeamCatalog.get($0) } ?? TeamCatalog.defaultRunTeam()
        guard let id = preset?.agentSpecs.first?.preferredModelId ?? preset?.lead.preferredModelId else { return nil }
        // Only honor it if it's actually on the bench (else the chip would show a
        // model the user can't run); otherwise the ready-fallback applies.
        return appModel.composeBench.contains(where: { $0.id == id }) ? id : nil
    }
    /// Team runs keep a standalone effort chip. Model routes surface effort in the
    /// target chip (`Grok 4.5 · High`) and in each model row's effort pill.
    var showsEffortChip: Bool { team != nil }

    func benchModelSupportsEffort(_ id: String?) -> Bool {
        guard let id else { return false }
        return appModel.composeBench.first(where: { $0.id == id })?.supportsEffort == true
    }

    var autoModelSupportsEffort: Bool { benchModelSupportsEffort(autoModelId) }

    var selectedModelSupportsEffort: Bool { benchModelSupportsEffort(selectedModelId) }

    var bar: some View {
        HStack(spacing: 9) {
            targetChip
            if showsEffortChip { effortChip }
            Spacer(minLength: 8)
            IconButton(systemImage: "paperclip", accessibilityLabel: "Attach image", small: true, action: pickImages)
            sendButton
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
    }

    // Scope, not control: the active project · branch floats ABOVE the box as quiet
    // read-only context (reflects what's active — you switch projects in the sidebar,
    // not here). No box, no helper line restating it.
    @ViewBuilder var projectScope: some View {
        if let active = projects.activeProject {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                Text(active.displayName).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ALColor.textSecondary).lineLimit(1)
                if let branch = active.gitBranch, !branch.isEmpty {
                    Text("·").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                    Text(branch).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // Two honest modes, never crossed: a single model reads `model · effort`; a team
    // reads its own identity — team glyph + `name · N workers` (or `1 agent`) — and
    // never a fake model · effort that hides the worker count.
    var targetChip: some View {
        Button { targetOpen.toggle() } label: {
            HStack(spacing: 6) {
                targetChipContent
                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .alPopover(isPresented: $targetOpen, arrowEdge: .top) { targetPopoverPanel }
    }

    @ViewBuilder var targetChipContent: some View {
        if targetTab == .loop {
            Image(systemName: "arrow.2.circlepath").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            Text("Delivery Loop").font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
        } else if let id = team, let preset = TeamCatalog.get(id) {
            Image(systemName: "person.2").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            Text(preset.displayName).font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
            Text(teamAgentLabel(preset)).font(ALFont.mono).foregroundStyle(ALColor.textMuted)
        } else if pinnedModelId == nil {
            // Auto: name the mode AND the model it resolves to, so the user can tell
            // they're in Auto and not pinned to that model (founder: "Auto · <model>").
            Image(systemName: "infinity").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            Text("Auto").font(ALFont.mono).foregroundStyle(ALColor.textSecondary)
            if let name = autoModelName {
                Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
                Text(name).font(ALFont.mono).foregroundStyle(ALColor.textMuted).lineLimit(1)
                if autoModelSupportsEffort {
                    Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
                    Text(effort.label).font(ALFont.mono).foregroundStyle(ALColor.textMuted)
                }
            }
        } else {
            Text(singleModelName).font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            if selectedModelSupportsEffort {
                Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
                Text(effort.label).font(ALFont.mono).foregroundStyle(ALColor.textMuted)
            }
        }
    }

    /// The model the single-model route runs — the tier-resolved Auto model, or an
    /// explicit pin. Equals what the run will actually execute.
    var singleModelName: String {
        appModel.composeBench.first(where: { $0.id == selectedModelId })?.name ?? "Auto"
    }

    /// The model name Auto resolves to right now (nil when the tier is fully down and
    /// Auto would wait — the chip then reads just "Auto").
    var autoModelName: String? {
        guard let id = autoModelId else { return nil }
        return appModel.composeBench.first { $0.id == id }?.name
    }

    /// A team's honest size: execution teams are one agent; answer teams show agent count.
    func teamAgentLabel(_ preset: TeamPreset) -> String {
        if preset.runShape == .execution { return "1 agent" }
        let n = preset.agentSpecs.count
        return "\(n) \(n == 1 ? "agent" : "agents")"
    }

    // Round, small, and deliberately not bright-white — a soft circle, not a loud
    // square. Restraint over theater (founder: "learn from the leader").
    var sendButton: some View {
        Button(action: performSend) {
            Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSend ? ALColor.textOnLight : ALColor.textFaint)
                .frame(width: 28, height: 28)
                .background(canSend ? ALPalette.ink150 : ALColor.active, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(targetTab == .loop ? "Start loop" : "Send")
    }

    func performSend() {
        if targetTab == .loop {
            let kickoff = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let projectId = projects.activeProjectId ?? threads.currentProjectId ?? projects.projects.first?.id
            guard let projectId else { return }
            openLoopLaunch(kickoff: kickoff, projectId: projectId)
            targetOpen = false
            return
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow an attachment-only send (e.g. a pasted screenshot with no typed text).
        guard !body.isEmpty || !attachments.isEmpty else { return }
        // Auto (no team, no pin) sends an EMPTY worker so the run resolves the tier
        // default and substitutes across CLIs. A team or an explicit pin sends a
        // concrete worker (exact, no substitution).
        let toSend: String
        if team != nil {
            toSend = (pinnedModelId ?? resolvedModelId(forTeam: team)) ?? ""
        } else {
            toSend = pinnedModelId ?? ""
        }
        onSend?(ComposeRouting(
            team: team,
            to: toSend,
            effort: effort,
            lane: lane,
            text: body,
            fileReferences: selectedFileInputs,
            attachments: attachments
        ))
        text = ""
        selectedFileReferences = []
        attachments = []
        attachmentThumbs = [:]
        closeFileSearch()
        targetOpen = false
        editorHeight = ComposeEditorMetrics.minHeight
    }

    /// Plain Return (Cursor-style): accept the highlighted @ file if the picker is open,
    /// else send. Shift+Return inserts a newline (handled in the text view).
    func handleReturn() -> Bool {
        if fileSearchOpen {
            guard fileCandidates.indices.contains(highlightedFileIndex) else { return false }
            selectFileReference(fileCandidates[highlightedFileIndex].path)
            return true
        }
        guard canSend else { return false }
        performSend()
        return true
    }
}
