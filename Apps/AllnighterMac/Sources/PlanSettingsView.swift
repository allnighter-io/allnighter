import SwiftUI
import AllnighterCore

/// Settings › **Plan** — honest home for trial / free / Builder. The closer
/// is the Keep going sheet on a blocked run; this page is where people go looking.
struct PlanSettingsView: View {
    @Environment(EntitlementModel.self) private var entitlement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusCard
                if entitlement.planRow.showsUpgrade {
                    offerCard
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ALColor.base)
        .task { await entitlement.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAN")
                .font(ALFont.sans(11, .bold))
                .tracking(1.3)
                .foregroundStyle(ALColor.accent)
            Text(entitlement.planRow.subtitle)
                .font(ALFont.sans(22, .semibold))
                .foregroundStyle(ALColor.textPrimary)
            Text(headerBlurb)
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerBlurb: String {
        if entitlement.status?.paid == true {
            return "Same product. No daily cap."
        }
        if entitlement.status?.plan == "trial" {
            return "Unlimited while the trial lasts. Builder is $8/month after that."
        }
        return "The whole product, three times a day. Builder skips the wait."
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This machine")
                .font(ALFont.sans(12, .semibold))
                .foregroundStyle(ALColor.textSecondary)
            row("Plan", entitlement.status?.plan ?? "—")
            if let remaining = entitlement.status.flatMap(EntitlementChrome.remainingRuns) {
                row("Runs left today", "\(remaining)")
            }
            if let ends = entitlement.status?.trialEndsAt {
                row("Trial ends", ends)
            }
        }
        .alCard()
    }

    private var offerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(offerHeadline)
                .font(ALFont.sans(15, .semibold))
                .foregroundStyle(ALColor.textPrimary)
            Text(offerBody)
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = entitlement.checkoutError {
                Text(error)
                    .font(ALFont.caption)
                    .foregroundStyle(ALColor.statusFailed)
            }
            Button {
                Task { await entitlement.checkout(.monthly) }
            } label: {
                Text(entitlement.checkoutBusy ? "Opening…" : EntitlementCopy.keepGoingButton)
            }
            .buttonStyle(.alPrimary(small: true))
            .disabled(entitlement.checkoutBusy)

            HStack(spacing: 6) {
                Button(EntitlementCopy.altYearly) {
                    Task { await entitlement.checkout(.yearly) }
                }
                Text("·")
                    .foregroundStyle(ALColor.textFaint)
                Button(EntitlementCopy.altFounding) {
                    Task { await entitlement.checkout(.founding) }
                }
            }
            .buttonStyle(.plain)
            .font(ALFont.caption)
            .foregroundStyle(ALColor.textFaint)
            .disabled(entitlement.checkoutBusy)
        }
        .alCard()
    }

    private var offerHeadline: String {
        if let status = entitlement.status, EntitlementChrome.remainingRuns(status) == 0 {
            return EntitlementCopy.dailyCapHeadline
        }
        return "Keep going with Builder."
    }

    private var offerBody: String {
        if let status = entitlement.status, EntitlementChrome.remainingRuns(status) == 0 {
            return EntitlementCopy.dailyCapBody
        }
        return "Same product, no daily cap. $8/month, or $80/year."
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(ALFont.sans(13))
                .foregroundStyle(ALColor.textMuted)
            Spacer()
            Text(value)
                .font(ALFont.monoSm)
                .foregroundStyle(ALColor.textPrimary)
                .textSelection(.enabled)
        }
    }
}
