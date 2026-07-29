//
//  IOSComposerBar.swift
//  AllnighteriOS
//
//  Shared work-request composer for home and thread surfaces.
//

import AllnighterCore
import SwiftUI

struct IOSComposerBar: View {
    @Binding var text: String
    @Binding var draft: IOSComposerDraft
    var placeholder: String = "Start something - ask, order, or build..."
    var continuationAgentTitle: String? = nil
    var continuationDriverId: String? = nil
    var continuationWorkerId: String? = nil
    var isSending: Bool = false
    var canSend: Bool = false
    var onSend: () async -> Void = {}

    @State private var showsModelPicker = false
    @State private var showsTeamPicker = false

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
                composerControls(compact: false)
                composerControls(compact: true)
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
        .onAppear {
            #if DEBUG
            if IOSTestFixture.opensModelPicker {
                showsModelPicker = true
            }
            #endif
        }
        .sheet(isPresented: $showsModelPicker) {
            IOSComposerModelPickerSheet(
                selectedModelId: draft.selectedModelId ?? continuationWorkerId
            ) { modelId in
                draft.selectedModelId = modelId
            }
            .presentationDetents([.medium, .large])
            .accessibilityIdentifier("model-picker-sheet")
        }
        .sheet(isPresented: $showsTeamPicker) {
            IOSComposerTeamPickerSheet(selectedTeamId: draft.selectedTeamId) { teamId in
                draft.selectedTeamId = teamId
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var modelChipTitle: String {
        if let selected = draft.selectedModel {
            return selected.title
        }
        if let continuationAgentTitle {
            return ConversationAgentPresentation.composerChipTitle(fromAgentTitle: continuationAgentTitle)
        }
        return "Auto"
    }

    private var modelChipDriverId: String {
        if let selected = draft.selectedModel?.driverId {
            return selected
        }
        if let continuationDriverId {
            return continuationDriverId
        }
        return "claude_code"
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

    private func composerControls(compact: Bool) -> some View {
        HStack(spacing: IOSSpace.s3) {
            ComposerIconButton(systemImage: "paperclip", accessibilityLabel: "Attach context") {
            }

            Button {
                showsModelPicker = true
            } label: {
                ComposerAgentChip(driverId: modelChipDriverId, title: modelChipTitle)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("composer-model-chip")

            if !compact {
                Button {
                    showsTeamPicker = true
                } label: {
                    RouteChip(systemImage: "person.3", title: draft.selectedTeam.name, detail: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-team-chip")
            }

            Button {
                draft.effort = nextEffort(after: draft.effort)
            } label: {
                RouteChip(systemImage: "speedometer", title: draft.effort.displayLabel, detail: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("composer-effort-chip")

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

    private func nextEffort(after effort: EffortLevel) -> EffortLevel {
        switch effort {
        case .low: .med
        case .med: .high
        case .high: .low
        }
    }
}

private struct IOSComposerModelPickerSheet: View {
    let selectedModelId: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    pickerRow(title: "Auto", subtitle: "", isSelected: selectedModelId == nil) {
                        onSelect(nil)
                        dismiss()
                    }
                }

                Section("Models") {
                    ForEach(IOSComposerCatalog.models) { model in
                        pickerRow(
                            title: model.title,
                            subtitle: "",
                            isSelected: selectedModelId == model.id,
                            driverId: model.driverId
                        ) {
                            onSelect(model.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("model-picker-navigation")
        }
        .preferredColorScheme(.dark)
    }

    private func pickerRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        driverId: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: IOSSpace.s3) {
                if let driverId {
                    IOSDriverBrandGlyphView(driverId: driverId, boxSize: 28, iconSize: 14)
                } else {
                    Image(systemName: "infinity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IOSColor.textMuted)
                        .frame(width: 28, height: 28)
                        .background(IOSColor.subtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(IOSFont.bodyStrong)
                        .foregroundStyle(IOSColor.textPrimary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(IOSFont.label)
                            .foregroundStyle(IOSColor.textMuted)
                    }
                }

                Spacer(minLength: IOSSpace.s2)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(IOSColor.accentText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct IOSComposerTeamPickerSheet: View {
    let selectedTeamId: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(IOSComposerCatalog.teams) { team in
                    Button {
                        onSelect(team.id)
                        dismiss()
                    } label: {
                        HStack(spacing: IOSSpace.s3) {
                            Text(team.name)
                                .font(IOSFont.bodyStrong)
                                .foregroundStyle(IOSColor.textPrimary)
                            Spacer(minLength: IOSSpace.s2)
                            if team.id == selectedTeamId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(IOSColor.accentText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
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

private struct ComposerAgentChip: View {
    let driverId: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            IOSDriverBrandGlyphView(driverId: driverId, boxSize: 28, iconSize: 14)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IOSColor.textSecondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
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
