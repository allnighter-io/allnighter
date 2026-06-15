import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AllnighterCore
import AllnighterEngine

// MARK: - Mode switch

/// Council (Lane 1) vs Design (Lane 2). No silent mode switch — the user chooses.
struct ModePicker: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Picker("", selection: $model.designMode) {
            Label("Council", systemImage: "person.3.sequence").tag(false)
            Label("Design", systemImage: "paintbrush").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal).padding(.top, 8)
        .disabled(model.isRunning || model.isDesigning)
    }
}

// MARK: - Design composer

/// Attach a screenshot, set the target shape + personas, and generate. Image
/// engines design; coding agents build. The deliverable is code — the board is
/// concept art you pick from, then "Build this" implements it (Design2).
struct DesignComposer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Design").font(.headline)
                Spacer()
                Picker("", selection: $model.designTargetShape) {
                    Text("Mobile").tag(TargetShape.mobile)
                    Text("Desktop").tag(TargetShape.desktop)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }

            ScreenshotWell()

            TextEditor(text: $model.prompt)
                .font(.body).frame(minHeight: 54, maxHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .overlay(alignment: .topLeading) {
                    if model.prompt.isEmpty {
                        Text("Improve this — e.g. “make it feel premium and clean”")
                            .font(.body).foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                    }
                }

            PersonaChips()

            HStack {
                if model.imageWorkers.isEmpty {
                    Label("No image-capable workers — run Doctor (Grok / Gemini-Antigravity / Codex).", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text(callPlanText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isDesigning {
                    Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { model.runDesign() } label: { Label("Generate designs", systemImage: "sparkles") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canRunDesign)
                }
            }
        }
        .padding()
    }

    private var callPlanText: String {
        let n = model.designPersonaIds.count
        let engines = Set(model.imageWorkers.map(\.displayName)).sorted().joined(separator: ", ")
        return "\(n) image generation\(n == 1 ? "" : "s") · \(engines) · uses your provider quota"
    }
}

/// Drag-and-drop or pick a screenshot to redesign. Shown as the "before".
private struct ScreenshotWell: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            if let url = model.designScreenshotURL, let img = NSImage(contentsOf: url) {
                HStack(spacing: 10) {
                    Image(nsImage: img).resizable().scaledToFit().frame(height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.caption).lineLimit(1)
                        Text("attached — the engines redesign this").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.clearScreenshot() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button(action: pick) {
                    HStack { Image(systemName: "photo.badge.plus"); Text("Attach a screenshot to redesign (optional)") }
                        .font(.callout).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, NSImage(contentsOf: url) != nil {
                    Task { @MainActor in model.attachScreenshot(url) }
                }
            }
            return true
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.attachScreenshot(url) }
    }
}

/// Toggle which design personas (style directions) join the panel — the range.
private struct PersonaChips: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            ForEach(DesignPersonaLibrary.builtInIDs, id: \.self) { id in
                let on = model.designPersonaIds.contains(id)
                Button {
                    if on { model.designPersonaIds.removeAll { $0 == id } }
                    else { model.designPersonaIds.append(id) }
                } label: {
                    Text(DesignPersonaLibrary.displayName(for: id))
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(on ? Color.accentColor.opacity(0.25) : Color(nsColor: .quaternaryLabelColor).opacity(0.4),
                                    in: Capsule())
                        .overlay(Capsule().stroke(on ? Color.accentColor : .clear))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - The board

/// The gallery wall — the first truth surface. Tiles fill in progressively as each
/// engine finishes; a failed seat is a gray tile, not a blocked board.
struct DesignBoardView: View {
    @Environment(AppModel.self) private var model
    @State private var fullscreenSeat: String?

    var body: some View {
        if let run = model.displayRun, run.presetId == "design_board" {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 14)], spacing: 14) {
                        ForEach(run.panel) { seat in
                            BoardTile(seat: seat, aspect: aspect, readOnly: readOnly,
                                      isChosen: model.board?.chosen?.seatId == seat.id,
                                      onOpen: { fullscreenSeat = seat.id },
                                      onPick: { model.pickOption(seatId: seat.id) })
                        }
                    }
                    if let chosen = model.board?.chosen {
                        if readOnly {
                            Label("Picked \(DesignPersonaLibrary.displayName(for: chosen.persona))", systemImage: "checkmark.seal.fill")
                                .font(.callout).foregroundStyle(.green)
                        } else {
                            BuildSection()
                        }
                    }
                }
                .padding()
            }
            .sheet(item: Binding(get: { fullscreenSeat.map { IdentifiedSeat(id: $0) } },
                                 set: { fullscreenSeat = $0?.id })) { ident in
                FullscreenOption(seatId: ident.id)
            }
        } else {
            ContentUnavailableView(
                "No board yet",
                systemImage: "square.grid.2x2",
                description: Text("Attach a screenshot, pick personas, and generate. The engines you already pay for return real design options side by side.")
            )
        }
    }

    private var readOnly: Bool { model.historySelection != nil }
    private var shape: TargetShape { model.board?.targetShape ?? model.designTargetShape }
    private var aspect: CGFloat { shape == .mobile ? 0.6 : 1.5 }
    private var tileWidth: CGFloat { shape == .mobile ? 170 : 260 }
}

private struct IdentifiedSeat: Identifiable { let id: String }

/// "Build this": hand the chosen image to a coding agent that restyles the existing
/// code to match (reuses RB4 dispatch). Image-readers (Claude Code, Codex) first.
private struct BuildSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 4)
            Label("Build this — an agent restyles your existing code to match the pick", systemImage: "hammer")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Working directory (your repo)", text: $model.dispatchWorkingDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: pickFolder)
            }
            HStack(spacing: 8) {
                Picker("Implementer", selection: Binding(get: { model.dispatchWorkerId ?? model.buildWorkers.first?.id ?? "" },
                                                         set: { model.dispatchWorkerId = $0 })) {
                    ForEach(model.buildWorkers) { w in
                        Text(model.canReadImages(w.id) ? "\(w.displayName) (reads images)" : w.displayName).tag(w.id)
                    }
                }
                .fixedSize()
                Toggle("Reveal only", isOn: $model.dispatchRevealOnly)
                Spacer()
                if model.isDispatching {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.buildChosen() } label: { Label("Build this", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).disabled(!model.canBuildChosen)
                }
            }
            if let dirWorker = model.dispatchWorkerId, !model.canReadImages(dirWorker) {
                Label("This worker can't read the image — the build will be weaker (reveal-only recommended).", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(model.dispatches) { stage in
                if let ret = stage.payload?.executionReturn {
                    HStack(spacing: 6) {
                        Image(systemName: ret.status == .done ? "checkmark.circle.fill" : (ret.status == .reveal ? "doc.text" : "xmark.circle.fill"))
                            .foregroundStyle(ret.status == .done ? .green : (ret.status == .reveal ? .secondary : .red))
                        Text("Build #\(ret.dispatchIndex) · \(ret.status.rawValue)").font(.caption)
                        Spacer()
                    }
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.dispatchWorkingDirectory = url.path }
    }
}

private struct BoardTile: View {
    @Environment(AppModel.self) private var model
    let seat: PanelSeat
    let aspect: CGFloat
    let readOnly: Bool
    let isChosen: Bool
    let onOpen: () -> Void
    let onPick: () -> Void

    var body: some View {
        let member = model.displayRun?.member(seatId: seat.id)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor))
                if let url = model.imageURL(forSeat: seat.id), let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else if member?.status == .failed || member?.status == .timedOut {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(member?.errorReason ?? "seat failed").font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 6)
                    }
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isChosen ? Color.green : Color.black.opacity(0.1), lineWidth: isChosen ? 3 : 1))
            .onTapGesture { if model.imageURL(forSeat: seat.id) != nil { onOpen() } }

            HStack(spacing: 6) {
                Text(DesignPersonaLibrary.displayName(for: seat.stance ?? ""))
                    .font(.caption).bold()
                Text(engineName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if model.imageURL(forSeat: seat.id) != nil && !readOnly {
                    Button(isChosen ? "Picked" : "Pick", action: onPick)
                        .font(.caption).buttonStyle(.borderless).disabled(isChosen)
                } else if isChosen {
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    private var engineName: String {
        model.workers.first { $0.id == seat.workerId }?.displayName ?? seat.workerId
    }
}

private struct FullscreenOption: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let seatId: String
    @State private var showingBefore = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(DesignPersonaLibrary.displayName(for: model.designPersona(forSeat: seatId))).font(.headline)
                Spacer()
                if model.screenshotURL != nil {
                    Toggle("Show original", isOn: $showingBefore).toggleStyle(.button)
                }
                if model.historySelection == nil {
                    Button("Pick this") { model.pickOption(seatId: seatId); dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Close") { dismiss() }
            }
            if let url = imageURL, let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("No image", systemImage: "photo")
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 620)
    }

    private var imageURL: URL? {
        showingBefore ? model.screenshotURL : model.imageURL(forSeat: seatId)
    }
}
