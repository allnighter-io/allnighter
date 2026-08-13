import AppKit
import Foundation
import Observation
import AllnighterCore

/// Mac projection of `EntitlementGate`. Opens Stripe Checkout in a real
/// browser on a human click — never puts a Stripe URL in a command field.
@MainActor
@Observable
final class EntitlementModel {
    var status: BillingJSON?
    var showKeepGoingSheet = false
    var checkoutBusy = false
    var checkoutError: String?

    var headerChip: EntitlementHeaderChip {
        EntitlementChrome.headerChip(status: status)
    }

    var planRow: EntitlementPlanRow {
        EntitlementChrome.planRow(status: status)
    }

    func refresh() async {
        #if DEBUG
        if let seeded = GUIFixture.entitlementStatus {
            status = seeded
            return
        }
        #endif
        status = await EntitlementGate.standard.statusJSON()
    }

    func presentKeepGoing() {
        showKeepGoingSheet = true
    }

    func checkout(_ plan: BillingCheckoutPlan) async {
        checkoutBusy = true
        checkoutError = nil
        defer { checkoutBusy = false }
        switch await EntitlementGate.standard.checkoutJSON(plan: plan) {
        case .success(let json):
            status = json
            if let raw = json.url, let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
                showKeepGoingSheet = false
            } else {
                checkoutError = "Checkout did not return a url. Try again."
            }
        case .failure(let refusal):
            checkoutError = refusal.message
        }
    }
}
