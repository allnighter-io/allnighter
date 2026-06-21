import SwiftUI
import AppKit

// MARK: - alPopover (the ONE way to anchor a popup)
//
// Allnighter's single blessed way to present a control-anchored popup — mode
// menus, routing pickers, dropdowns. It wraps the NATIVE SwiftUI `.popover`, so
// AppKit owns positioning, screen-edge flipping, and outside-click dismissal.
//
// DO NOT hand-position popups with `.offset`, preference keys, GeometryReader
// math, or `alignmentGuide`. Those re-introduce the anchoring bugs this exists
// to kill. Attach this directly to the trigger view. See
// docs/gui/patterns/Anchored_Popups.md.

extension View {
    func alPopover<PopContent: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> PopContent
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            content()
                .environment(\.colorScheme, .dark)
                .presentationBackground(ALColor.surface)
        }
    }
}

// MARK: - ALDropdown
//
// The app's styled option picker. NEVER use the native SwiftUI `Menu` for
// skill/model/option lists — it renders the system menu chrome (light, wrong
// metrics) that breaks the dark UI. This opens an `.alPopover` with our own rows.

struct ALDropdown: View {
    let current: String
    /// (id, label) pairs.
    let options: [(String, String)]
    var width: CGFloat = 220
    var onPick: (String) -> Void

    @State private var open = false
    /// Keyboard/hover highlight; starts on the current selection.
    @State private var highlighted = 0

    /// Sorted A→Z and DEDUPED by label — the "Auto" sentinel and a concrete model also
    /// named "Auto" (Cursor's Auto) collapse to one row instead of two (handoff bug #2).
    private var rows: [(String, String)] {
        var seen = Set<String>()
        return options
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
            .filter { seen.insert($0.1.lowercased()).inserted }
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Text(current).font(.system(size: 12)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.md)
                    .strokeBorder(open ? ALColor.borderDefault : ALColor.borderSubtle, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alPopover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.0) { idx, row in
                        let (id, label) = row
                        Button { onPick(id); open = false } label: {
                            HStack(spacing: 8) {
                                Text(label).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                                Spacer(minLength: 8)
                                // Checkmark marks the actual selection; the background is
                                // the keyboard/hover highlight (selected ≠ highlighted).
                                if label == current {
                                    Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(ALColor.accentText)
                                }
                            }
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(idx == highlighted ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = idx } }
                    }
                }
                .padding(6)
            }
            .frame(width: width)
            .frame(maxHeight: 300)
            .background(ALColor.surface)
            .overlay(keyMonitor.allowsHitTesting(false))
            .onAppear { highlighted = rows.firstIndex { $0.1 == current } ?? 0 }
        }
    }

    /// ↑/↓/⏎/esc via the AppKit key monitor (SwiftUI key focus doesn't fire in an
    /// NSPopover, and this dropdown has no search field to host it).
    private var keyMonitor: some View {
        let rows = self.rows
        return PopoverKeyCatcher { action in
            switch action {
            case .up: if !rows.isEmpty { highlighted = (highlighted - 1 + rows.count) % rows.count }
            case .down: if !rows.isEmpty { highlighted = (highlighted + 1) % rows.count }
            case .enter: if rows.indices.contains(highlighted) { onPick(rows[highlighted].0); open = false }
            case .escape: open = false
            }
            return true
        }
    }
}

// MARK: - ALSearchableDropdown
//
// A searchable option picker for long lists (skills): type to filter, rows sorted
// A→Z with an optional trailing tag (e.g. built-in / custom), and — when `onCreate`
// is set and the typed name matches nothing — a "+ Create …" footer. Same anchored
// `.alPopover` chrome as `ALDropdown`; never the native Menu.

struct ALComboItem: Identifiable, Equatable {
    let id: String
    let label: String
    var tag: String? = nil
}

struct ALSearchableDropdown: View {
    let current: String
    let items: [ALComboItem]
    var width: CGFloat = 280
    var placeholder: String = "Search…"
    var onPick: (String) -> Void
    /// When set, a non-matching query offers "+ Create <query>" (passes the name).
    var onCreate: ((String) -> Void)? = nil

    @State private var open = false
    @State private var query = ""
    /// Keyboard cursor across the filtered rows then (if shown) the create row. Top
    /// row is highlighted by default so ↑/↓ + ⏎ selects without the mouse.
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var sorted: [ALComboItem] {
        items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
    private var filtered: [ALComboItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasExactMatch: Bool {
        !trimmedQuery.isEmpty && items.contains { $0.label.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }
    private var canCreate: Bool { onCreate != nil && !trimmedQuery.isEmpty && !hasExactMatch }
    /// Selectable rows = filtered items, plus the create row when offered.
    private var optionCount: Int { filtered.count + (canCreate ? 1 : 0) }

    private func move(_ delta: Int) {
        guard optionCount > 0 else { return }
        highlighted = (highlighted + delta + optionCount) % optionCount
    }
    private func activateHighlighted() {
        if highlighted < filtered.count {
            onPick(filtered[highlighted].id); close()
        } else if canCreate {
            onCreate?(trimmedQuery); close()
        }
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Text(current).font(.system(size: 12)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.md)
                    .strokeBorder(open ? ALColor.borderDefault : ALColor.borderSubtle, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alPopover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                    TextField(placeholder, text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(ALColor.textPrimary)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 10).frame(height: 36)
                Rectangle().fill(ALColor.borderSubtle).frame(height: 1)

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                            row(item, index: idx)
                        }
                        if filtered.isEmpty && !canCreate {
                            Text("No match").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)

                if canCreate {
                    Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                    let createIndex = filtered.count
                    Button {
                        onCreate?(trimmedQuery); close()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(ALColor.accentText)
                            Text("Create \"\(trimmedQuery)\"").font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(ALColor.accentText).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: 36).frame(maxWidth: .infinity, alignment: .leading)
                        .background(highlighted == createIndex ? ALColor.active : Color.clear,
                                    in: RoundedRectangle(cornerRadius: ALRadius.sm))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { highlighted = createIndex } }
                    .padding(.horizontal, 6).padding(.vertical, 6)
                }
            }
            .frame(width: width)
            .background(ALColor.surface)
            .onAppear { searchFocused = true; highlighted = 0 }
            .onChange(of: query) { _, _ in highlighted = 0 }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.return) { activateHighlighted(); return .handled }
        }
    }

    private func row(_ item: ALComboItem, index: Int) -> some View {
        let active = index == highlighted || item.label == current
        return Button { onPick(item.id); close() } label: {
            HStack(spacing: 8) {
                Text(item.label).font(.system(size: 13)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if let tag = item.tag {
                    Text(tag).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ALColor.textMuted)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(ALColor.textMuted.opacity(0.14), in: Capsule())
                }
                if item.label == current {
                    Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(ALColor.accentText)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = index } }
    }

    private func close() { open = false; query = "" }
}

