//
//  RemoteOnboardingView.swift
//  AllnighteriOS
//
//  Thin presenter over Core pairing — no transport logic here.
//

import SwiftUI

struct RemoteOnboardingView: View {
    let phase: RemoteAppConnectionPhase
    let onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSSpace.s7) {
                header
                content
            }
            .padding(.horizontal, IOSSpace.s5)
            .padding(.vertical, IOSSpace.s8)
        }
        .background(IOSColor.void)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: IOSSpace.s4) {
            HStack(spacing: IOSSpace.s3) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IOSColor.accentText)
                    .frame(width: 38, height: 38)
                    .background(IOSColor.accentSurface, in: RoundedRectangle(cornerRadius: IOSRadius.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: IOSRadius.sm, style: .continuous)
                            .strokeBorder(IOSColor.accentBorder, lineWidth: 1)
                    }

                Text("Allnighter")
                    .font(IOSFont.title)
                    .foregroundStyle(IOSColor.textSecondary)
            }

            Text(headline)
                .font(IOSFont.display)
                .foregroundStyle(IOSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding-headline")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .connecting:
            connectingCard
        case .needsConfiguration:
            signInCard
        case let .awaitingPairingApproval(macName):
            pairingApprovalCard(macName: macName)
        case .noMacsOnAccount:
            noMacsCard
        case let .failed(message):
            failedCard(message: message)
        case .preview, .connected:
            EmptyView()
        }
    }

    private var connectingCard: some View {
        OnboardingCard {
            ProgressView()
                .tint(IOSColor.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, IOSSpace.s4)

            Text("Connecting to your Mac…")
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("onboarding-connecting")
    }

    private var signInCard: some View {
        OnboardingCard {
            Text("Sign in to see your Macs and control team runs from anywhere.")
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textSecondary)

            OnboardingPrimaryButton(title: "Sign in with Apple", systemImage: "apple.logo") {
                Task { await retry() }
            }
            .accessibilityIdentifier("onboarding-sign-in-apple")

            OnboardingSecondaryButton(title: "Sign in with Google", systemImage: "g.circle") {
                Task { await retry() }
            }
            .accessibilityIdentifier("onboarding-sign-in-google")

            #if DEBUG
            Text("Dev builds use preview data when relay credentials are not injected.")
                .font(IOSFont.label)
                .foregroundStyle(IOSColor.textFaint)
            #endif
        }
    }

    private func pairingApprovalCard(macName: String) -> some View {
        OnboardingCard {
            Text("Approve this iPhone on \(macName) to finish pairing.")
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textSecondary)

            VStack(alignment: .leading, spacing: IOSSpace.s4) {
                onboardingStep(number: 1, text: "Open Allnighter on your Mac.")
                onboardingStep(number: 2, text: "When prompted, tap Trust for this iPhone.")
                onboardingStep(number: 3, text: "This screen will continue automatically.")
            }
            .padding(.top, IOSSpace.s3)

            ProgressView()
                .tint(IOSColor.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, IOSSpace.s5)
        }
        .accessibilityIdentifier("onboarding-awaiting-approval")
    }

    private var noMacsCard: some View {
        OnboardingCard {
            Text("No Mac is registered on this account yet.")
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textSecondary)

            Text("Open Allnighter on your Mac and sign in with the same account. Your Mac will appear here once it connects.")
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textMuted)

            OnboardingPrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                Task { await retry() }
            }
            .accessibilityIdentifier("onboarding-retry")
        }
        .accessibilityIdentifier("onboarding-no-macs")
    }

    private func failedCard(message: String) -> some View {
        OnboardingCard {
            Text(message)
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textSecondary)

            OnboardingPrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                Task { await retry() }
            }
            .accessibilityIdentifier("onboarding-retry")
        }
        .accessibilityIdentifier("onboarding-failed")
    }

    private func onboardingStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: IOSSpace.s4) {
            Text("\(number)")
                .font(IOSFont.mono)
                .foregroundStyle(IOSColor.accentText)
                .frame(width: 28, height: 28)
                .background(IOSColor.accentSurface, in: Circle())

            Text(text)
                .font(IOSFont.body)
                .foregroundStyle(IOSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        switch phase {
        case .idle, .connecting:
            "Connecting"
        case .needsConfiguration:
            "Control your Mac from anywhere"
        case .awaitingPairingApproval:
            "Approve on your Mac"
        case .noMacsOnAccount:
            "Your Macs"
        case .failed:
            "Could not connect"
        case .preview, .connected:
            ""
        }
    }

    private func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        await onRetry()
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: IOSSpace.s5) {
            content()
        }
        .padding(IOSSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.surface, in: RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.lg, style: .continuous)
                .strokeBorder(IOSColor.borderDefault, lineWidth: 1)
        }
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: IOSSpace.s3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(IOSFont.bodyStrong)
            }
            .foregroundStyle(IOSColor.textOnLight)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(IOSColor.textPrimary, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: IOSSpace.s3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(IOSFont.bodyStrong)
            }
            .foregroundStyle(IOSColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(IOSColor.raised, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                    .strokeBorder(IOSColor.borderDefault, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
