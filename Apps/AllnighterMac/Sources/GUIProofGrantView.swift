import SwiftUI
import AppKit

/// One-time Screen Recording grant UI for the GUI proof harness.
///
/// Launched via `bash scripts/gui_proof_grant.sh` through the real `.app`
/// bundle (Launch Services), so macOS registers Allnighter in System Settings →
/// Privacy & Security → Screen & System Audio Recording. Fixture-only; inert on
/// every normal launch.
struct GUIProofGrantView: View {
    @State private var granted = CGPreflightScreenCaptureAccess()
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("GUI proof — Screen Recording")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ALColor.textPrimary)

            Text("""
            Allnighter’s developer proof harness captures its own windows — \
            including native SwiftUI popovers — so we can verify layout before \
            calling a GUI fix “done.” macOS requires Screen Recording permission \
            for that capture. Normal app use never calls this path.
            """)
            .font(.system(size: 13))
            .foregroundStyle(ALColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Group {
                if granted {
                    Label("Screen Recording is granted for Allnighter.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ALColor.statusDone)
                } else {
                    Label("Screen Recording is not granted yet.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(ALPalette.yellow500)
                }
            }
            .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Steps").font(.system(size: 12, weight: .bold)).foregroundStyle(ALColor.textMuted)
                Text("1. Click **Open System Settings** below.")
                Text("2. If Allnighter is not listed, click **+** → ⌘⇧G → paste the app path shown below → Open.")
                Text("3. Turn **Allnighter** ON.")
                Text("4. Return here — this window updates automatically when macOS accepts the grant.")
            }
            .font(.system(size: 12))
            .foregroundStyle(ALColor.textSecondary)

            Text(GUIFixture.grantAppPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ALColor.textFaint)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))

            HStack(spacing: 10) {
                Button("Open System Settings") { GUIFixture.openScreenRecordingSettings() }
                    .buttonStyle(.alSecondary)
                Button("Check again") { refreshGrant() }
                    .buttonStyle(.alGhost)
                Spacer()
                Button(granted ? "Quit" : "Cancel") { NSApp.terminate(nil) }
                    .buttonStyle(.alGhost)
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear(perform: beginGrantFlow)
        .onDisappear { pollTask?.cancel() }
    }

    private func beginGrantFlow() {
        // Register Allnighter in the Screen Recording list and surface the prompt.
        _ = CGRequestScreenCaptureAccess()
        refreshGrant()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                refreshGrant()
                if granted { break }
            }
        }
    }

    private func refreshGrant() {
        granted = CGPreflightScreenCaptureAccess()
        if granted { GUIFixture.writeGrantMarker() }
    }
}
