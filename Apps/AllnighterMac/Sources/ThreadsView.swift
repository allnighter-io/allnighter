import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

// MARK: - Thread list (sidebar)

struct ThreadListView: View {
    @Environment(ThreadsViewModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Threads")
                    .font(ALFont.caption.weight(.bold)).tracking(1.1).textCase(.uppercase)
                    .foregroundStyle(ALColor.accentText)
                Spacer()
                IconButton(systemImage: "square.and.pencil", accessibilityLabel: "New thread", small: true) {
                    model.newThread()
                }
            }
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 10)

            if model.triagedThreads.isEmpty {
                VStack(spacing: 6) {
                    Text("No threads yet").font(ALFont.body.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                    Text("Start one to think with a worker.").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 14)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.triagedThreads) { thread in
                            ThreadRow(thread: thread, selected: thread.id == model.selectedThreadId) {
                                model.select(thread)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
    }
}

private struct ThreadRow: View {
    let thread: WorkThread
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    stateDot
                    Text(thread.title).font(ALFont.body.weight(.semibold))
                        .foregroundStyle(ALColor.textPrimary).lineLimit(1)
                    Spacer(minLength: 4)
                    if thread.isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
                    }
                }
                if let preview = thread.preview {
                    Text(preview).font(ALFont.caption).foregroundStyle(ALColor.textMuted).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let worker = thread.lastWorkerId {
                        Text(worker).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
                    }
                    Text(thread.updatedAt, format: .relative(presentation: .numeric))
                        .font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                    Spacer(minLength: 0)
                    if let dir = thread.workingDir {
                        Text((dir as NSString).lastPathComponent)
                            .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(ALColor.surface, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var stateDot: some View {
        switch ThreadsPresenter.rowState(thread) {
        case .needsAttention: Circle().fill(ALColor.statusFailed).frame(width: 7, height: 7)
        case .running: Circle().fill(ALColor.statusRunning).frame(width: 7, height: 7)
        case .idle: EmptyView()
        }
    }
}

// MARK: - Thread detail (timeline + composer)

struct ThreadDetailPane: View {
    @Environment(ThreadsViewModel.self) private var model

    var body: some View {
        Group {
            if let thread = model.selectedThread {
                VStack(spacing: 0) {
                    ThreadHeader(thread: thread)
                    Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                    ThreadTimeline(thread: thread)
                    Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                    ThreadComposer(thread: thread)
                }
            } else {
                VStack(spacing: 8) {
                    Text("No thread selected").font(ALFont.h3).foregroundStyle(ALColor.textSecondary)
                    Text("Pick a thread or start a new one.").font(ALFont.body).foregroundStyle(ALColor.textFaint)
                    Button { model.newThread() } label: { Label("New thread", systemImage: "square.and.pencil") }
                        .buttonStyle(.alPrimary).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .sheet(item: revealBinding) { packet in ContextRevealSheet(packet: packet) }
    }

    /// Bridges the optional packet to a `.sheet(item:)`.
    private var revealBinding: Binding<IdentifiedPacket?> {
        Binding(
            get: { model.revealedPacket.map(IdentifiedPacket.init) },
            set: { if $0 == nil { model.dismissReveal() } }
        )
    }
}

private struct ThreadHeader: View {
    @Environment(ThreadsViewModel.self) private var model
    let thread: WorkThread

    var body: some View {
        HStack(spacing: 10) {
            Text(thread.title).font(ALFont.h3).foregroundStyle(ALColor.textPrimary).lineLimit(1)
            if let dir = thread.workingDir {
                Label((dir as NSString).lastPathComponent, systemImage: "folder")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(ALColor.surface, in: Capsule())
            }
            Spacer()
            if let worker = thread.defaultWorkerId {
                Text("default: \(worker)").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}

private struct ThreadTimeline: View {
    @Environment(ThreadsViewModel.self) private var model
    let thread: WorkThread

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(thread.turns) { turn in
                        TurnRow(turn: turn).id(turn.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: thread.turns.count) { _, _ in
                if let last = thread.turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TurnRow: View {
    @Environment(ThreadsViewModel.self) private var model
    let turn: ThreadTurn

    var body: some View {
        switch turn.family {
        case .message: messageRow
        case .reply: replyRow
        case .team, .build: richRow
        case .system: systemRow
        }
    }

    // User message — right-aligned bubble.
    private var messageRow: some View {
        HStack {
            Spacer(minLength: 40)
            Text(turn.text ?? "")
                .font(ALFont.body).foregroundStyle(ALColor.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                .textSelection(.enabled)
        }
    }

    // Model reply — left-aligned, with status + heartbeat + reveal.
    private var replyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(ThreadsPresenter.authorLabel(turn))
                    .font(ALFont.label.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                StatusPill(kind: ThreadsPresenter.pillKind(for: turn.status))
                if ThreadsPresenter.isLive(turn) { heartbeat }
                Spacer()
                if let packetId = turn.contextPacketId {
                    Button { model.revealContext(packetId: packetId) } label: {
                        Label("Context", systemImage: "doc.text.magnifyingglass").font(ALFont.caption)
                    }.buttonStyle(.alGhost)
                }
            }
            if let body = ThreadsPresenter.bodyText(turn) {
                Text(body).font(ALFont.body)
                    .foregroundStyle(turn.status == .done ? ALColor.textPrimary : ALColor.statusFailed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    private var heartbeat: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("· \(ThreadsPresenter.elapsedSeconds(turn, now: context.date))s")
                .font(ALFont.monoSm).foregroundStyle(ALColor.statusRunning)
        }
    }

    // Council / build turn — compact card referencing its run.
    private var richRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: turn.family == .team ? "person.3.fill" : "hammer.fill")
                    .foregroundStyle(ALColor.accentText)
                Text(turn.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(ALFont.label.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                StatusPill(kind: ThreadsPresenter.pillKind(for: turn.status))
                Spacer()
                if let runId = turn.runId {
                    Text("run \(runId)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
            }
            ForEach(Array(turn.artifactRefs.enumerated()), id: \.offset) { _, ref in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                    Text(ref.kind.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(ALFont.caption).foregroundStyle(ALColor.textMuted)
                    if let excerpt = ref.excerpt {
                        Text("— \(excerpt)").font(ALFont.caption).foregroundStyle(ALColor.textFaint).lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.accentBorder, lineWidth: 1) }
    }

    // System note — manual-paste gets an inline paste box; others are muted.
    @ViewBuilder private var systemRow: some View {
        if turn.systemEvent == .manualPaste, !turn.status.isTerminal {
            ManualPasteBox(noteTurn: turn)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                Text(turn.text ?? "").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct ManualPasteBox: View {
    @Environment(ThreadsViewModel.self) private var model
    let noteTurn: ThreadTurn
    @State private var pasted = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(noteTurn.text ?? "Paste the worker's reply.", systemImage: "doc.on.clipboard")
                .font(ALFont.label.weight(.semibold)).foregroundStyle(ALColor.accentText)
            TextEditor(text: $pasted)
                .font(ALFont.body).scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(ALColor.base, in: RoundedRectangle(cornerRadius: ALRadius.md))
            HStack {
                Spacer()
                Button {
                    // The worker turn is the most recent running worker_chat turn.
                    if let workerTurnId = model.selectedThread?.turns.last(where: { $0.kind == .workerChat && $0.status == .running })?.id {
                        model.completeManualPaste(workerTurnId: workerTurnId, manualNoteTurnId: noteTurn.id, reply: pasted)
                    }
                } label: { Text("Save reply") }
                .buttonStyle(.alPrimary)
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.accentBorder, lineWidth: 1) }
    }
}

// MARK: - Composer

private struct ThreadComposer: View {
    @Environment(ThreadsViewModel.self) private var model
    let thread: WorkThread
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            workerChip
            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $model.composerText)
                    .focused($focused)
                    .font(ALFont.body).scrollContentBackground(.hidden)
                    .frame(minHeight: 38, maxHeight: 140)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: ALRadius.lg)
                            .strokeBorder(focused ? ALColor.accentBorder : ALColor.borderDefault, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if model.composerText.isEmpty {
                            Text("Message the worker… (Enter sends, Shift+Enter for a new line)")
                                .font(ALFont.body).foregroundStyle(ALColor.textFaint)
                                .padding(.leading, 14).padding(.top, 14).allowsHitTesting(false)
                        }
                    }
                    // Enter never builds: it sends a chat turn. Shift+Enter = newline.
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                        if model.canSend { model.send() }
                        return .handled
                    }
                Button { model.send() } label: { Label("Send", systemImage: "arrow.up") }
                    .buttonStyle(.alPrimary).disabled(!model.canSend)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var workerChip: some View {
        Menu {
            ForEach(model.models) { worker in
                Button {
                    model.requestedWorkerId = worker.id
                } label: {
                    if model.resolvedComposerWorkerId == worker.id {
                        Label(worker.displayName, systemImage: "checkmark")
                    } else { Text(worker.displayName) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.system(size: 11))
                Text(ThreadsPresenter.replyingAs(workerId: model.resolvedComposerWorkerId))
                    .font(ALFont.caption)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(ALColor.textMuted)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(ALColor.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton).fixedSize()
    }
}

// MARK: - Context reveal

/// "What the worker will see" — the exact persisted packet, sized in bytes.
private struct ContextRevealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let packet: ThreadContextPacket

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What the worker will see").font(ALFont.h3).foregroundStyle(ALColor.textPrimary)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(packet.text, forType: .string) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }.buttonStyle(.alSecondary)
                Button { dismiss() } label: { Label("Close", systemImage: "xmark") }.buttonStyle(.alGhost)
            }
            HStack(spacing: 10) {
                Text(ThreadsPresenter.contextSizeLabel(packet)).font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                if let note = packet.truncationNote {
                    Label(note, systemImage: "scissors").font(ALFont.caption).foregroundStyle(ALColor.statusTimeout)
                }
            }
            ScrollView {
                Text(packet.text).font(ALFont.mono).foregroundStyle(ALColor.textSecondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(ALColor.base, in: RoundedRectangle(cornerRadius: ALRadius.md))
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .background(ALColor.surface)
    }
}

/// `.sheet(item:)` needs Identifiable; the packet id is stable.
private struct IdentifiedPacket: Identifiable {
    let packet: ThreadContextPacket
    init(_ packet: ThreadContextPacket) { self.packet = packet }
    var id: String { packet.id }
}

private extension ContextRevealSheet {
    init(packet: IdentifiedPacket) { self.init(packet: packet.packet) }
}
