import AllnighterCore
import SwiftUI

/// Settings > **iPhone remote control** — optional cloud relay for the iOS companion.
struct IPhoneRemoteControlView: View {
    @Environment(RemoteAccountModel.self) private var remoteAccount

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                optionalCard
                if remoteAccount.isSignedIn {
                    activeCard
                } else {
                    enableCard
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ALColor.base)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IPHONE REMOTE CONTROL")
                .font(ALFont.sans(11, .bold))
                .tracking(1.3)
                .foregroundStyle(ALColor.accent)
            Text("Control this Mac from your iPhone.")
                .font(ALFont.sans(22, .semibold))
                .foregroundStyle(ALColor.textPrimary)
        }
    }

    private var optionalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional")
                .font(ALFont.sans(12, .semibold))
                .foregroundStyle(ALColor.textSecondary)
            Text("You only need this if you want to use the Allnighter iPhone app. The Mac app works fully without it.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alCard()
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enable iPhone access")
                .font(ALFont.sans(15, .semibold))
                .foregroundStyle(ALColor.textPrimary)

            Text("Sign in with the same Apple ID you use on your phone. This Mac will appear in the iOS app for one-tap pairing.")
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let statusLine = remoteAccount.statusLine {
                Text(statusLine)
                    .font(ALFont.sans(12, .medium))
                    .foregroundStyle(ALColor.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Sign in with Apple") {
                Task { await remoteAccount.signInWithApple() }
            }
            .buttonStyle(.borderedProminent)
            .tint(ALColor.textPrimary)
            .controlSize(.large)
        }
        .alCard()
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ALPalette.green400)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iPhone access is on")
                            .font(ALFont.sans(15, .semibold))
                            .foregroundStyle(ALColor.textPrimary)
                        Text(remoteAccount.accountLabel ?? "Apple account connected")
                            .font(ALFont.sans(13))
                            .foregroundStyle(ALColor.textSecondary)
                    }
                }

                relayStatusLine

                if let statusLine = remoteAccount.statusLine {
                    Text(statusLine)
                        .font(ALFont.sans(12, .medium))
                        .foregroundStyle(ALColor.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .alCard()

            Button("Turn off iPhone access") {
                Task { await remoteAccount.signOut() }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var relayStatusLine: some View {
        switch remoteAccount.relayState {
        case .idle:
            EmptyView()
        case .starting:
            Text("Starting remote relay…")
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textMuted)
        case .running:
            Text("This Mac is reachable from your iPhone.")
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textMuted)
        case let .failed(message):
            Text(message)
                .font(ALFont.sans(12))
                .foregroundStyle(ALPalette.red400)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
