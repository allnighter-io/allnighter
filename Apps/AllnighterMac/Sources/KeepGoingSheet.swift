import SwiftUI
import AllnighterCore

/// Blocked 4th-run closer. Copy SSOT: `EntitlementCopy`.
struct KeepGoingSheet: View {
    var model: EntitlementModel

    var body: some View {
        VStack(alignment: .leading, spacing: ALSpace.s5) {
            Text(EntitlementCopy.dailyCapHeadline)
                .font(ALFont.h2)
                .foregroundStyle(ALColor.textPrimary)

            Text(EntitlementCopy.dailyCapBody)
                .font(ALFont.body)
                .foregroundStyle(ALColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.checkoutError {
                Text(error)
                    .font(ALFont.caption)
                    .foregroundStyle(ALColor.statusFailed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await model.checkout(.monthly) }
            } label: {
                Text(model.checkoutBusy ? "Opening…" : EntitlementCopy.keepGoingButton)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.alPrimary)
            .disabled(model.checkoutBusy)
            .keyboardShortcut(.defaultAction)

            Button(EntitlementCopy.notNowButton) {
                model.showKeepGoingSheet = false
            }
            .buttonStyle(.alGhost)
            .keyboardShortcut(.cancelAction)

            HStack(spacing: 6) {
                Button(EntitlementCopy.altYearly) {
                    Task { await model.checkout(.yearly) }
                }
                .disabled(model.checkoutBusy)
                Text("·")
                Button(EntitlementCopy.altFounding) {
                    Task { await model.checkout(.founding) }
                }
                .disabled(model.checkoutBusy)
            }
            .buttonStyle(.plain)
            .font(ALFont.caption)
            .foregroundStyle(ALColor.textFaint)
        }
        .padding(ALSpace.s7)
        .frame(width: 440)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1)
        }
        .alShadowSm()
    }
}
