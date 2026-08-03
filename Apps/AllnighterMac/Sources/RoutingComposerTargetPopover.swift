import SwiftUI
import AllnighterCore
import AllnighterEngine

// Target popover — model/team/loop picker (CM-S03). State owner: RoutingComposer.

extension RoutingComposer {

    // MARK: target popover

    var targetPopoverPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if locksTeam {
                // Send-to-team launcher: team is fixed, so just override the model.
                popHeader("Model", "Override the resolved model when needed")
                modelList()
            } else {
                targetTabs
                if targetTab == .model {
                    // Auto = the default model, so it lives at the top of the Model tab.
                    defaultTeamRow
                    modelList()
                } else if targetTab == .team {
                    // Team tab is just teams now — no Auto row → way cleaner.
                    teamSearchField
                    teamPickerBody
                } else {
                    popHeader("Delivery Loop", "PM ↔ dev, round after round — brief once, then Return opens the launch sheet.")
                }
            }
        }
        .padding(6)
        .frame(width: locksTeam ? 300 : 400)
        .background(ALColor.surface)
        // ↑/↓/⏎ are handled by an AppKit key monitor (SwiftUI key focus doesn't fire
        // inside an NSPopover). Hover + the default top-row highlight come from `targetHighlight`.
        .overlay(targetKeyMonitor.allowsHitTesting(false))
        .onChange(of: targetTab) { _, tab in
            targetHighlight = 0
            if tab == .model, targetOpen { appModel.refreshCapacityCooldowns() }
        }
        .onChange(of: teamSearch) { _, _ in targetHighlight = 0 }
        .onChange(of: appModel.favoriteTeamIds) { _, _ in
            if targetOpen { refreshPickerTeams() }
        }
        .onAppear {
            if pickerTeams.isEmpty { refreshPickerTeams() }
        }
    }

    /// AppKit key catcher — reliably receives ↑/↓/⏎/esc inside the NSPopover (which
    /// SwiftUI's `.onKeyPress` does not). Captures value snapshots each render so the
    /// AppKit callback never reads SwiftUI environment.
    var targetKeyMonitor: some View {
        let items = targetItems
        let count = items.count
        let bench = appModel.composeBench
        let teams = pickerTeams
        return PopoverKeyCatcher { action in
            switch action {
            case .up:
                if count > 0 { targetHighlight = (targetHighlight - 1 + count) % count }
            case .down:
                if count > 0 { targetHighlight = (targetHighlight + 1) % count }
            case .escape:
                targetOpen = false
            case .tab:
                // ⇥ cycles Model → Team → Loop (only when tabs are shown).
                if !locksTeam {
                    switch targetTab {
                    case .model: targetTab = .team
                    case .team: targetTab = .loop
                    case .loop: targetTab = .model
                    }
                }
            case .enter:
                guard items.indices.contains(targetHighlight) else { return true }
                switch items[targetHighlight] {
                case .auto:
                    team = nil; pinnedModelId = nil; targetOpen = false
                case .model(let id):
                    if bench.first(where: { $0.id == id })?.ready == true {
                        pinBenchModel(id); if !locksTeam { team = nil }; targetOpen = false
                    }
                case .team(let id):
                    if let t = teams.first(where: { $0.id == id }) { selectTeam(t) }
                }
            }
            return true
        }
    }

    // One toggle, two forms — Team OR Agent. Lightened from the boxed segmented control
    // to two quiet text tabs (no outer track/border); the selected one carries a subtle
    // pill. The WHOLE tab is the hit target — `Color.clear` isn't hit-tested, so without
    // an explicit `contentShape` only the glyph was tappable.
    var targetTabs: some View {
        HStack(spacing: 4) {
            ForEach([TargetTab.model, .team, .loop], id: \.self) { tab in
                let selected = tab == targetTab
                Button { targetTab = tab } label: {
                    Text(tab == .team ? "Team" : (tab == .loop ? "Delivery Loop" : "Model"))
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? ALColor.textPrimary : ALColor.textFaint)
                        .padding(.horizontal, 11).frame(height: 24)
                        .background(selected ? ALColor.active : Color.clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 6)
    }

    func popHeader(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text(sub).font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 7)
    }

    // Search field sits directly under Auto — answering both modes instantly: "I know
    // what I want" (type) and "show me my bench" (Recent + Favorites below).
    var teamSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            TextField("Search teams…", text: $teamSearch)
                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(ALColor.textPrimary)
            if !teamSearch.isEmpty {
                Button { teamSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 2)
    }

    // Empty query → the full roster, ranked so it's NEVER blank: Favorites → Recent →
    // Featured (built-in starters) → the rest A–Z, deduped, with one quiet divider before
    // the A–Z tail. No per-tier labels (stars + order do the work). Non-empty → matches
    // across the whole roster.
    @ViewBuilder var teamPickerBody: some View {
        let q = teamSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = pickerTeams
        ScrollView {
            LazyVStack(spacing: 1) {
                if q.isEmpty {
                    let ranked = rankedTeams(all)
                    ForEach(ranked.top) { teamButton($0) }
                    if !ranked.rest.isEmpty {
                        Divider().overlay(ALColor.borderSubtle).padding(.horizontal, 9).padding(.vertical, 5)
                        ForEach(ranked.rest) { teamButton($0) }
                    }
                } else {
                    let results = all
                        .filter { matchesTeamQuery($0, q) }
                        .sorted { a, b in
                            let af = appModel.isFavorite(a.id), bf = appModel.isFavorite(b.id)
                            if af != bf { return af && !bf }
                            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                        }
                    if results.isEmpty {
                        teamPickerEmpty("No teams found")
                    } else {
                        ForEach(results) { teamButton($0) }
                    }
                }
            }
        }
        .frame(minHeight: 196, maxHeight: 240)
    }

    /// Default ordering: Favorites → Recent → Featured (curated built-ins), then the
    /// remaining teams A–Z. `top` is the ranked cluster, `rest` is the A–Z tail (rendered
    /// below a divider). Deduped — each team appears once, in its highest tier.
    func rankedTeams(_ all: [ComposeTeam]) -> (top: [ComposeTeam], rest: [ComposeTeam]) {
        let favs = all.filter { appModel.isFavorite($0.id) }
        var used = Set(favs.map(\.id))
        let recents = recentTeams(from: all).filter { used.insert($0.id).inserted }
        let featured = all.filter { $0.isFeatured && used.insert($0.id).inserted }
        let rest = all
            .filter { !used.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (favs + recents + featured, rest)
    }

    func teamPickerEmpty(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 8)
    }

    func recentTeams(from all: [ComposeTeam]) -> [ComposeTeam] {
        appModel.recentTeamIds.compactMap { id in all.first { $0.id == id } }
    }

    /// Match name, craft, summary, and the team's resolved worker/model — no special
    /// boosts for any vocabulary; it ranks only because the user typed it.
    func matchesTeamQuery(_ t: ComposeTeam, _ q: String) -> Bool {
        if t.name.lowercased().contains(q) { return true }
        if t.summary.lowercased().contains(q) { return true }
        if t.lane.label.lowercased().contains(q) { return true }
        if let modelId = resolvedModelId(forTeam: t.id),
           let m = appModel.composeBench.first(where: { $0.id == modelId }) {
            if m.name.lowercased().contains(q) || m.cli.lowercased().contains(q) { return true }
        }
        return false
    }

    /// Auto = the default model. Selected only in true Auto mode (no team, no pin) — a
    /// pinned model below must not leave Auto looking selected too.
    var isAutoSelected: Bool { team == nil && pinnedModelId == nil }

    // MARK: target keyboard / hover navigation

    /// One navigable target row.
    enum TargetItem: Equatable { case auto, model(String), team(String) }

    /// The teams shown in the Team tab, in render order (ranked, or search results).
    var visibleTeams: [ComposeTeam] {
        let all = pickerTeams
        let q = teamSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { let r = rankedTeams(all); return r.top + r.rest }
        return all.filter { matchesTeamQuery($0, q) }
    }

    func refreshPickerTeams() {
        pickerTeams = appModel.composeAllTeams()
    }

    /// On-Bench model ids in A–Z browse order (Unassigned tail order).
    var benchModelIds: [String] { appModel.composeBench.map(\.id) }

    /// Tier-grouped picker sections — roster order within tier, deduped by highest tier.
    var modelPickerSections: [TierMembership.PickerSection] {
        defaultSettings.tiers.pickerSections(orderedBench: benchModelIds)
    }

    /// Flat model rows for keyboard navigation (respects Unassigned collapse).
    var navigableModelIds: [String] {
        defaultSettings.tiers.pickerModelIds(
            orderedBench: benchModelIds,
            includeUnassigned: !unassignedSectionCollapsed)
    }

    /// The flat, ordered list of selectable rows for the current tab — the index space
    /// that ↑/↓ and hover move through.
    var targetItems: [TargetItem] {
        if locksTeam { return navigableModelIds.map { .model($0) } }
        if targetTab == .model { return [.auto] + navigableModelIds.map { .model($0) } }
        if targetTab == .team { return visibleTeams.map { .team($0.id) } }
        return []
    }

    var highlightedTargetItem: TargetItem? {
        targetItems.indices.contains(targetHighlight) ? targetItems[targetHighlight] : nil
    }

    func highlightTarget(_ item: TargetItem) {
        if let i = targetItems.firstIndex(of: item) { targetHighlight = i }
    }


    /// One-line row label: bold name + a quiet parenthetical — `Opus 5 (Claude)`,
    /// `Plan (7 workers)`. Collapses the old two-line name/subtitle rows.
    func rowLabel(_ name: String, _ detail: String, primary: Bool) -> some View {
        HStack(spacing: 5) {
            Text(name).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary ? ALColor.textPrimary : ALColor.textMuted)
            if !detail.isEmpty {
                Text("(\(detail))").font(.system(size: 12))
                    .foregroundStyle(ALColor.textFaint)
                    .layoutPriority(1)
            }
        }
        .lineLimit(1)
    }

    // "Auto" is pinned to the very top of the Model tab — the default, the 95% case.
    // One line, like every other row: name + a quiet parenthetical.
    var defaultTeamRow: some View {
        let highlighted = highlightedTargetItem == .auto
        return HStack(spacing: 4) {
            Button { team = nil; pinnedModelId = nil; targetOpen = false } label: {
                HStack(spacing: 8) {
                    Image(systemName: "infinity").font(.system(size: 11)).foregroundStyle(ALColor.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(ALColor.active, in: RoundedRectangle(cornerRadius: 5))
                    rowLabel("Auto", autoModelName ?? "Default model", primary: true)
                    Spacer(minLength: 8)
                    if isAutoSelected { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlighted ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(highlighted ? ALColor.borderDefault : ALColor.borderSubtle, lineWidth: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { if $0 { highlightTarget(.auto) } }
            if autoModelSupportsEffort, let id = autoModelId {
                modelEffortPill(for: id).padding(.trailing, 6)
            }
        }
    }

    func teamSectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.top, 6).padding(.bottom, 2)
    }

    func teamButton(_ t: ComposeTeam) -> some View {
        let isFavorite = appModel.isFavorite(t.id)
        return HStack(spacing: 6) {
            Button { selectTeam(t) } label: { teamRowBody(t) }.buttonStyle(.plain)
            // Star toggles favorite without selecting the team. Neutral fill — the
            // shape says "favorite", no color needed (color earns its place).
            Button {
                appModel.toggleFavorite(t.id)
                refreshPickerTeams()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 12))
                    .foregroundStyle(isFavorite ? ALColor.textSecondary : ALColor.textFaint)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(highlightedTargetItem == .team(t.id) ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .onHover { if $0 { highlightTarget(.team(t.id)) } }
    }

    /// Select a team: pin it, sync the lane to its craft (no lane tabs anymore), and
    /// record it for the Recent section.
    func selectTeam(_ t: ComposeTeam) {
        team = t.id
        lane = t.lane
        appModel.noteRecentTeam(t.id)
        targetOpen = false
    }

    func teamRowBody(_ t: ComposeTeam) -> some View {
        HStack(spacing: 8) {
            Image(systemName: t.lane.icon).font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                .frame(width: 18, height: 18)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 5))
            rowLabel(t.name, t.summary, primary: true)
            Spacer(minLength: 8)
            if team == t.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    func modelSectionLabel(_ text: String) -> some View {
        teamSectionLabel(text)
    }

    func unassignedSectionHeader(count: Int) -> some View {
        Button {
            unassignedSectionCollapsed.toggle()
            targetHighlight = min(targetHighlight, max(0, targetItems.count - 1))
        } label: {
            HStack(spacing: 4) {
                modelSectionLabel("Unassigned (\(count))")
                Spacer(minLength: 0)
                Image(systemName: unassignedSectionCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ALColor.textFaint)
            }
        }
        .buttonStyle(.plain)
    }

    func modelList() -> some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(modelPickerSections, id: \.title) { section in
                    if section.tier != nil {
                        modelSectionLabel(section.title)
                        ForEach(section.modelIds, id: \.self) { id in
                            modelListRow(id)
                        }
                    } else {
                        unassignedSectionHeader(count: section.modelIds.count)
                        if !unassignedSectionCollapsed {
                            ForEach(section.modelIds, id: \.self) { id in
                                modelListRow(id)
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 196, maxHeight: 240)
    }

    @ViewBuilder
    func modelListRow(_ id: String) -> some View {
        if let m = appModel.composeBench.first(where: { $0.id == id }) {
            HStack(spacing: 4) {
                Button {
                    if m.ready { pinBenchModel(id); if !locksTeam { team = nil }; targetOpen = false }
                } label: { modelRow(m) }
                    .buttonStyle(.plain)
                    .disabled(!m.ready)
                if m.ready && m.supportsEffort {
                    modelEffortPill(for: m.id).padding(.trailing, 6)
                }
            }
        }
    }

    func modelRow(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 8) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5).opacity(m.ready ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m.ready ? ALColor.textPrimary : ALColor.textMuted)
                    .lineLimit(1)
                if !m.sub.isEmpty {
                    Text(m.sub).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if m.ready {
                if pinnedModelId == m.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
            } else if let reason = m.notReadyReason {
                Badge(text: reason, tone: .warning)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlightedTargetItem == .model(m.id) ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .contentShape(Rectangle())
        .onHover { if m.ready, $0 { highlightTarget(.model(m.id)) } }
    }

    /// Model-row effort pill — shows Low/Med/High and opens the picker without
    /// selecting the row. Fast stays a separate catalog seat; no speed toggle here.
    func modelEffortPill(for modelId: String) -> some View {
        Button { modelEditModelId = modelId } label: {
            HStack(spacing: 3) {
                Text(effort.label).font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ALColor.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Reasoning effort for the next send")
        .alPopover(isPresented: Binding(
            get: { modelEditModelId == modelId },
            set: { if !$0 { modelEditModelId = nil } }
        ), arrowEdge: .trailing) {
            effortEditPanel(onDismiss: { modelEditModelId = nil })
        }
    }
}
