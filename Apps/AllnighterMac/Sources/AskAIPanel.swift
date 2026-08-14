import SwiftUI
import AppKit
import AllnighterCore

struct AskAIFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Cloudflare-style title-bar door. Always visible. Not Settings, not About.
struct AskAIButton: View {
    @Binding var isOpen: Bool
    @State private var hover = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                Text(AskAIPrompt.title)
                    .font(ALFont.sans(12, .semibold))
            }
            .foregroundStyle(isOpen || hover ? ALColor.textPrimary : ALColor.textSecondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background(
                Capsule().fill(isOpen || hover ? ALColor.hover : Color.clear)
            )
            .overlay {
                if isOpen {
                    Capsule().strokeBorder(ALColor.accentBorder, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Ask about Allnighter on this Mac")
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: AskAIFrameKey.self, value: geo.frame(in: .global))
            }
        }
        .onHover { hover = $0 }
    }
}

struct AskAIPanel: View {
    @Bindable var model: AskAIModel
    var onClose: () -> Void
    var onAsk: () -> Void
    var maxBodyHeight: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(ALColor.borderSubtle)
            VStack(alignment: .leading, spacing: 12) {
                Text(AskAIPrompt.deck)
                    .font(ALFont.sans(13))
                    .foregroundStyle(ALColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                askRow
                result
            }
            .padding(16)
            footer
        }
        .frame(width: 440)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.66), radius: 30, y: 24)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALColor.accent)
                Text(AskAIPrompt.title)
                    .font(ALFont.sans(15, .semibold))
                    .foregroundStyle(ALColor.textPrimary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ALColor.textFaint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var askRow: some View {
        HStack(spacing: 8) {
            TextField(AskAIPrompt.placeholder, text: $model.draft)
                .textFieldStyle(.plain)
                .font(ALFont.sans(14))
                .foregroundStyle(ALColor.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay {
                    RoundedRectangle(cornerRadius: ALRadius.md)
                        .strokeBorder(ALColor.accent.opacity(0.55), lineWidth: 1)
                }
                .disabled(model.phase == .running)
                .onSubmit { if model.canAsk { onAsk() } }
            Button("Ask") { onAsk() }
                .buttonStyle(.alPrimary(small: true))
                .disabled(!model.canAsk)
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .running, .done, .failed:
            VStack(alignment: .leading, spacing: 8) {
                if !model.question.isEmpty {
                    Text(model.question)
                        .font(ALFont.sans(12, .medium))
                        .foregroundStyle(ALColor.textFaint)
                        .textSelection(.enabled)
                }
                ViewThatFits(in: .vertical) {
                    answerBody
                    ScrollView {
                        answerBody
                    }
                    .frame(maxHeight: maxBodyHeight)
                }
            }
        }
    }

    @ViewBuilder
    private var answerBody: some View {
        Group {
            if model.phase == .failed, let error = model.errorText {
                Text(error)
                    .font(ALFont.sans(13))
                    .foregroundStyle(ALPalette.red400)
                    .textSelection(.enabled)
            } else if model.answer.isEmpty, model.phase == .running {
                Text("Looking…")
                    .font(ALFont.sans(13))
                    .foregroundStyle(ALColor.textMuted)
            } else {
                MarkdownText(markdown: model.answer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(AskAIPrompt.supportMailto)
            } label: {
                Text(ChromeCopy.emailAPerson)
                    .font(ALFont.sans(12, .medium))
                    .foregroundStyle(ALColor.textMuted)
            }
            .buttonStyle(.plain)
            .help(AskAIPrompt.supportEmail)
            Spacer()
            Text(AskAIPrompt.supportEmail)
                .font(ALFont.mono(11))
                .foregroundStyle(ALColor.textFaint)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}
