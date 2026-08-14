import AppKit
import SwiftUI
import AllnighterCore

/// Settings › **About & updates** — same `latest.json` channel as CLI
/// (`ReleaseChannel`). Human notes as plain text; upgrade is the one-liner
/// (CLI) or the published app asset URL (not a second feed).
struct AboutUpdatesView: View {
    @Environment(ReleaseUpdateModel.self) private var updates
    @State private var copiedCommand = false
    @State private var copiedURL = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                versionCard
                if let app = updates.appUpdate {
                    appUpdateCard(app)
                } else {
                    upToDateCard
                }
                if let cli = updates.cliUpdate {
                    cliUpdateCard(cli)
                }
                pathCard
                channelCard
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ALColor.base)
        .onAppear { updates.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT & UPDATES")
                .font(ALFont.sans(11, .bold))
                .tracking(1.3)
                .foregroundStyle(ALColor.accent)
            Text("This Mac app and the CLI share one release channel.")
                .font(ALFont.sans(22, .semibold))
                .foregroundStyle(ALColor.textPrimary)
            Text("Updates appear when a release is published — not on every git commit.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This build")
                .font(ALFont.sans(12, .semibold))
                .foregroundStyle(ALColor.textSecondary)
            monoRow("App", updates.appVersion)
            monoRow("CLI identity", AllnighterVersionIdentity.binaryVersion)
            if let checked = updates.lastCheckedAt {
                Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                    .font(ALFont.sans(11))
                    .foregroundStyle(ALColor.textFaint)
            }
            HStack(spacing: 8) {
                Button {
                    updates.refresh(force: true)
                } label: {
                    Label(
                        updates.isChecking ? "Checking…" : "Check for updates",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.alSecondary(small: true))
                .disabled(updates.isChecking)
            }
        }
        .alCard()
    }

    private var upToDateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ALPalette.green400)
                Text("App is current")
                    .font(ALFont.sans(15, .semibold))
                    .foregroundStyle(ALColor.textPrimary)
            }
            Text("No newer published app version in the release channel.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textMuted)
        }
        .alCard()
    }

    private func appUpdateCard(_ info: ReleaseAppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Badge(text: "update", tone: .accent, dot: true, mono: true)
                Text("App \(info.latest) is available")
                    .font(ALFont.sans(15, .semibold))
                    .foregroundStyle(ALColor.textPrimary)
            }
            Text("You are on \(info.current). Install the published app build for this release.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = info.notes {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(ALFont.sans(11, .semibold))
                        .foregroundStyle(ALColor.textFaint)
                    // Plain text only — never treat notes as a command (law 9).
                    Text(notes)
                        .font(ALFont.sans(13))
                        .foregroundStyle(ALColor.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let urlString = info.downloadURL, let url = URL(string: urlString) {
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open download", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.alPrimary(small: true))
                    Button {
                        copy(urlString, flag: { copiedURL = $0 })
                    } label: {
                        Text(copiedURL ? "Copied" : "Copy URL")
                    }
                    .buttonStyle(.alGhost)
                }
                Text(urlString)
                    .font(ALFont.mono(11))
                    .foregroundStyle(ALColor.textFaint)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .alCard()
    }

    private func cliUpdateCard(_ info: ReleaseUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Badge(text: "cli", tone: .neutral, mono: true)
                Text("CLI \(info.latest) is available")
                    .font(ALFont.sans(15, .semibold))
                    .foregroundStyle(ALColor.textPrimary)
            }
            Text("Running identity \(info.current). Same one-liner as cold start upgrades the CLI.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    copy(info.command, flag: { copiedCommand = $0 })
                } label: {
                    Label(copiedCommand ? "Copied" : "Copy install command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.alSecondary(small: true))
            }
            Text(info.command)
                .font(ALFont.mono(11))
                .foregroundStyle(ALColor.textMuted)
                .textSelection(.enabled)
        }
        .alCard()
    }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ChromeCopy.cliOnPATH)
                .font(ALFont.sans(12, .semibold))
                .foregroundStyle(ALColor.textSecondary)
            monoRow(ChromeCopy.standaloneHome, updates.standaloneHomePath)
            monoRow(ChromeCopy.resolvesTo, updates.resolvedPathAlln ?? ChromeCopy.notOnPATH)
            if updates.pathConflict {
                Text(ChromeCopy.pathConflict)
                    .font(ALFont.sans(12))
                    .foregroundStyle(ALPalette.yellow400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(ChromeCopy.pathRepair)
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textFaint)
            Text("Cold start / upgrade: \(ReleaseChannel.installCommand)")
                .font(ALFont.mono(11))
                .foregroundStyle(ALColor.textMuted)
                .textSelection(.enabled)
        }
        .alCard()
    }

    private var channelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release channel")
                .font(ALFont.sans(12, .semibold))
                .foregroundStyle(ALColor.textSecondary)
            Text("SSOT is latest.json on the install host. The Mac app does not keep a private “latest” constant.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            monoRow("Default base", ReleaseChannel.defaultBaseURL)
        }
        .alCard()
    }

    private func monoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textFaint)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(ALFont.mono(12))
                .foregroundStyle(ALColor.textPrimary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func copy(_ text: String, flag: @escaping (Bool) -> Void) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flag(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            flag(false)
        }
    }
}
