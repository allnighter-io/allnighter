import Foundation
import AllnighterCore

/// `alln billing` / `alln billing checkout --plan …`
enum BillingCLI {
    static func run(_ args: [String]) async {
        if args.first == "checkout" {
            await runCheckout(Array(args.dropFirst()))
            return
        }
        let opts = Options(args)
        let json = await EntitlementGate.standard.statusJSON()
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(json))
            return
        }
        print("plan \(json.plan)")
        if json.paid {
            print("paid yes")
        } else if let remaining = json.runsAllowedToday.map({ $0 - (json.runsUsedToday ?? 0) }) {
            print("runs remaining today \(max(0, remaining)) of \(json.runsAllowedToday ?? EntitlementPolicy.freeRunsPerDay)")
        }
        if let ends = json.trialEndsAt {
            print("trial ends \(ends)")
        }
        print("checkout \(json.checkoutCommand)")
        if let message = json.message {
            print(message)
        }
    }

    private static func runCheckout(_ args: [String]) async {
        let opts = Options(args)
        guard let raw = opts.value("plan"),
              let plan = BillingCheckoutPlan(rawValue: raw) else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln billing checkout --plan monthly|yearly|founding [--json]"
            )
        }
        switch await EntitlementGate.standard.checkoutJSON(plan: plan) {
        case .success(let json):
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(json))
                return
            }
            if let url = json.url {
                print("url \(url)")
                print("open that url in Safari or Chrome to pay. do not exec it.")
                print("Cursor's preview browser returns Access Denied — paste into a real browser.")
            }
            print("then: alln billing --json")
        case .failure(let refusal):
            AllnighterCLI.fail(
                code: "ENTITLEMENT_LIMIT",
                message: refusal.message,
                nextAction: EntitlementLimitNextAction.agent
            )
        }
    }
}
