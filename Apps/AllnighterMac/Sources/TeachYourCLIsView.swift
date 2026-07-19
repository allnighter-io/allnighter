import AppKit
import SwiftUI
import AllnighterCore

/// Settings › **Teach your CLIs** — one-click GLOBAL teaching-snippet install
/// (`docs/phases/Agent_Onboarding.md` Decision 3 + ONB-S03).
///
/// Preview first, write only on explicit click. Never touches project-scoped
/// files. Codex is unsupported for global write — paste via bootstrap instead.
///
/// V1 first-run: Settings entry only. RootView hotfix keeps cold launch from
/// auto-opening setup/studio; a soft post-bench offer can land later without
/// forcing an auto-write.
struct TeachYourCLIsView: View {
    @State private var preview: GlobalTeachingInstaller.Preview?
    @State private var selectedId: String?
    @State private var results: [String: GlobalTeachingInstaller.ApplyResult] = [:]
    @State private var busyHostId: String?
    @State private var bulkBusy = false

    private var hosts: [GlobalTeachingInstaller.HostPreview] {
        preview?.hosts ?? []
    }

    private var selected: GlobalTeachingInstaller.HostPreview? {
        hosts.first { $0.hostId == selectedId } ?? hosts.first
    }

    var body: some View {
        HStack(spacing: 0) {
            masterList
                .frame(width: 320)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear { reload() }
    }

    // MARK: - Master

    private var masterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Teach your CLIs")
                    .font(.system(size: 20, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Install the Allnighter trigger into each host's global instructions — so agents find `alln` without you pasting.")
                    .font(.system(size: 12))
                    .foregroundStyle(ALColor.textMuted)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(hosts) { host in
                        hostRow(host)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }

            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            if let note = preview?.scopeNote {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ALColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let installable = preview?.installable ?? []
            if !installable.isEmpty {
                Button {
                    installAll()
                } label: {
                    Label(
                        bulkBusy ? "Installing…" : "Install all supported (\(installable.count))",
                        systemImage: "square.and.arrow.down.on.square"
                    )
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.alPrimary(small: true))
                .disabled(bulkBusy || busyHostId != nil)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func hostRow(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        let on = selected?.hostId == host.hostId
        let result = results[host.hostId]
        return Button {
            selectedId = host.hostId
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(GlobalTeachingInstaller.displayName(for: host.hostId))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ALColor.textPrimary)
                        .lineLimit(1)
                    Text(statusLabel(host, result: result))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(statusColor(host, result: result))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                stateChip(host, result: result)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? ALColor.active : .clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let host = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(host)
                    if host.unsupported {
                        unsupportedCard(host)
                    } else {
                        pathCard(host)
                        if let err = host.error {
                            callout(err, tone: .warn)
                        }
                        if let result = results[host.hostId] {
                            callout(
                                result.success ? result.detail : "Failed: \(result.detail)",
                                tone: result.success ? .ok : .error
                            )
                        }
                        actions(host)
                        if let diff = host.diffText, host.installAction == .repair {
                            section("PREVIEW DIFF") {
                                monoBlock(diff)
                            }
                        } else if let after = host.afterBlock, host.installAction == .append {
                            section("WILL WRITE") {
                                monoBlock(after)
                            }
                        } else if host.installAction == .noOp, let after = host.afterBlock {
                            section("INSTALLED BLOCK") {
                                monoBlock(after)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ALColor.base)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "graduationcap").font(.system(size: 28)).foregroundStyle(ALColor.textFaint)
                Text("No host selected.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ALColor.base)
        }
    }

    private func header(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(GlobalTeachingInstaller.displayName(for: host.hostId))
                    .font(.system(size: 18, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(ALColor.textPrimary)
                Text(host.hostId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 0)
            stateChip(host, result: results[host.hostId])
        }
    }

    private func pathCard(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GLOBAL PATH").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            Text(displayPath(host.path))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ALColor.textSecondary)
                .textSelection(.enabled)
            Text(host.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.lg)
                .strokeBorder(ALColor.borderSubtle, lineWidth: 1)
        }
    }

    private func unsupportedCard(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            callout(host.unsupportedReason ?? host.detail, tone: .warn)
            Text("Paste the bootstrap snippet into a project AGENTS.md instead. This installer never writes project files.")
                .font(.system(size: 12))
                .foregroundStyle(ALColor.textMuted)
            Button {
                copyBootstrap(host: "codex")
            } label: {
                Label("Copy `alln bootstrap --host codex` instructions", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.alSecondary(small: true))
            Text("Run in a terminal: alln bootstrap --host codex")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ALColor.textFaint)
                .textSelection(.enabled)
        }
    }

    private func actions(_ host: GlobalTeachingInstaller.HostPreview) -> some View {
        HStack(spacing: 8) {
            switch host.installAction {
            case .append:
                Button {
                    runInstall(host)
                } label: {
                    Label(busyHostId == host.hostId ? "Installing…" : "Install", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.alPrimary(small: true))
                .disabled(busyHostId != nil || bulkBusy)
            case .repair:
                Button {
                    runInstall(host)
                } label: {
                    Label(busyHostId == host.hostId ? "Repairing…" : "Repair", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.alPrimary(small: true))
                .disabled(busyHostId != nil || bulkBusy)
            case .noOp:
                EmptyView()
            case .requiresManual:
                Text("Manual fix required — see detail above.")
                    .font(.system(size: 12))
                    .foregroundStyle(ALColor.textMuted)
            case .unsupported, .remove:
                EmptyView()
            }

            if host.canRemove {
                Button {
                    runRemove(host)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.alGhost)
                .disabled(busyHostId != nil || bulkBusy)
            }

            Button {
                reload()
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.alSecondary(small: true))
            .disabled(busyHostId != nil || bulkBusy)

            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
            content()
        }
    }

    private func monoBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(ALColor.textSecondary)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.lg)
                    .strokeBorder(ALColor.borderSubtle, lineWidth: 1)
            }
    }

    private enum CalloutTone { case ok, warn, error }

    private func callout(_ text: String, tone: CalloutTone) -> some View {
        let color: Color = {
            switch tone {
            case .ok: return ALPalette.green500
            case .warn: return ALPalette.yellow500
            case .error: return ALPalette.red500
            }
        }()
        return Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private func stateChip(_ host: GlobalTeachingInstaller.HostPreview, result: GlobalTeachingInstaller.ApplyResult?) -> some View {
        let label: String
        let color: Color
        if let result, result.success, let state = result.newState {
            label = state.rawValue
            color = state == .installed || state == .absent ? ALPalette.green500 : ALPalette.yellow500
        } else if host.unsupported {
            label = "unsupported"
            color = ALColor.textMuted
        } else {
            label = host.state.rawValue
            color = chipColor(for: host.state)
        }
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func chipColor(for state: TeachingSnippet.InstallState) -> Color {
        switch state {
        case .installed: return ALPalette.green500
        case .absent: return ALColor.textMuted
        case .stale, .modified: return ALPalette.yellow500
        case .malformed: return ALPalette.red500
        }
    }

    private func statusLabel(_ host: GlobalTeachingInstaller.HostPreview, result: GlobalTeachingInstaller.ApplyResult?) -> String {
        if let result {
            return result.success ? result.detail : "failed"
        }
        if host.unsupported { return "paste via bootstrap" }
        switch host.installAction {
        case .append: return "will create / append"
        case .repair: return "repair available"
        case .noOp: return "up to date"
        case .requiresManual: return "manual fix"
        case .unsupported: return "unsupported"
        case .remove: return "remove"
        }
    }

    private func statusColor(_ host: GlobalTeachingInstaller.HostPreview, result: GlobalTeachingInstaller.ApplyResult?) -> Color {
        if let result {
            return result.success ? ALPalette.green500 : ALPalette.red500
        }
        return ALColor.textFaint
    }

    private func displayPath(_ path: String?) -> String {
        guard let path else { return "(no path)" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Actions

    private func reload() {
        let keep = selectedId
        preview = GlobalTeachingInstaller.preview()
        if let keep, hosts.contains(where: { $0.hostId == keep }) {
            selectedId = keep
        } else {
            selectedId = hosts.first?.hostId
        }
    }

    private func runInstall(_ host: GlobalTeachingInstaller.HostPreview) {
        busyHostId = host.hostId
        let result = GlobalTeachingInstaller.applyInstall(
            hostId: host.hostId,
            expectedContentHash: host.contentHash
        )
        results[host.hostId] = result
        busyHostId = nil
        reload()
    }

    private func runRemove(_ host: GlobalTeachingInstaller.HostPreview) {
        busyHostId = host.hostId
        let result = GlobalTeachingInstaller.applyRemove(
            hostId: host.hostId,
            expectedContentHash: host.contentHash
        )
        results[host.hostId] = result
        busyHostId = nil
        reload()
    }

    private func installAll() {
        guard let snapshot = preview else { return }
        bulkBusy = true
        let applied = GlobalTeachingInstaller.installAllSupported(preview: snapshot)
        for r in applied {
            results[r.hostId] = r
        }
        bulkBusy = false
        reload()
    }

    private func copyBootstrap(host: String) {
        let ctx = Bootstrap.liveContext()
        let text = Bootstrap.render(
            host: Bootstrap.Host(argument: host) ?? .codex,
            binaryPath: ctx.binaryPath,
            onPath: ctx.onPath
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
