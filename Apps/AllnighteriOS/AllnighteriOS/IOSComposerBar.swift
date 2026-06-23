//
//  IOSComposerBar.swift
//  AllnighteriOS
//
//  Shared work-request composer for home and thread surfaces.
//

import SwiftUI

struct IOSComposerBar: View {
    @Binding var text: String
    var placeholder: String = "Start something - ask, order, or build..."
    var continuationAgentTitle: String? = nil
    var continuationDriverId: String? = nil
    var isSending: Bool = false
    var canSend: Bool = false
    var onSend: () async -> Void = {}

    var body: some View {
        VStack(spacing: IOSSpace.s3) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(IOSFont.body)
                        .foregroundStyle(IOSColor.textFaint)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("composer-placeholder")
                }

                TextEditor(text: $text)
                    .font(IOSFont.body)
                    .foregroundStyle(IOSColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 44, maxHeight: 92)
                    .accessibilityLabel("Work request")
                    .accessibilityIdentifier("work-request-editor")
            }

            ViewThatFits(in: .horizontal) {
                composerControls(showModelDetail: true, showEffort: true)
                composerControls(showModelDetail: false, showEffort: true)
                composerControls(showModelDetail: false, showEffort: false)
            }
        }
        .padding(IOSSpace.s4)
        .background(IOSColor.raised, in: RoundedRectangle(cornerRadius: IOSRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.xl, style: .continuous)
                .strokeBorder(IOSColor.borderDefault, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.46), radius: 24, x: 0, y: 14)
        .accessibilityIdentifier("ios-composer-bar")
    }

    private var sendEnabled: Bool {
        canSend && !isSending
    }

    private func send() {
        guard sendEnabled else { return }
        Task {
            await onSend()
        }
    }

    private func composerControls(showModelDetail: Bool, showEffort: Bool) -> some View {
        HStack(spacing: IOSSpace.s3) {
            ComposerIconButton(systemImage: "paperclip", accessibilityLabel: "Attach context") {
            }

            if let continuationAgentTitle, let continuationDriverId {
                ContinuationAgentChip(
                    driverId: continuationDriverId,
                    title: continuationAgentTitle
                )
            } else {
                RouteChip(systemImage: "infinity", title: "Auto", detail: showModelDetail ? "Claude" : nil)
            }

            if showEffort {
                RouteChip(systemImage: "speedometer", title: "Med", detail: nil)
            }

            Spacer(minLength: IOSSpace.s2)

            Button(action: send) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(IOSColor.textOnLight)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(sendEnabled ? IOSColor.textOnLight : IOSColor.textFaint)
                .frame(width: 48, height: 48)
                .background(sendEnabled ? IOSColor.textPrimary : IOSColor.active, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!sendEnabled)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("composer-send-button")
        }
    }
}

extension View {
    func iosComposerSafeAreaInset<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            content()
                .padding(.horizontal, IOSSpace.s3)
                .padding(.top, IOSSpace.s3)
                .padding(.bottom, IOSSpace.s2)
                .background {
                    VStack(spacing: 0) {
                        IOSColor.borderSubtle.frame(height: 1)
                        IOSColor.void
                    }
                    .ignoresSafeArea()
                }
        }
    }
}

private struct ComposerIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(IOSColor.textSecondary)
                .frame(width: 48, height: 48)
                .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                        .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ContinuationAgentChip: View {
    let driverId: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            IOSDriverBrandGlyphView(driverId: driverId, boxSize: 28, iconSize: 14)

            Text(title)
                .font(IOSFont.bodyStrong)
                .foregroundStyle(IOSColor.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, IOSSpace.s3)
        .frame(height: 48)
        .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityLabel(title)
    }
}

private struct RouteChip: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IOSColor.textMuted)

            Text(title)
                .font(IOSFont.mono)
                .foregroundStyle(IOSColor.textSecondary)
                .lineLimit(1)

            if let detail {
                Text("·")
                    .font(IOSFont.monoSm)
                    .foregroundStyle(IOSColor.textFaint)

                Text(detail)
                    .font(IOSFont.mono)
                    .foregroundStyle(IOSColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, IOSSpace.s3)
        .frame(height: 48)
        .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSRadius.md, style: .continuous)
                .strokeBorder(IOSColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
