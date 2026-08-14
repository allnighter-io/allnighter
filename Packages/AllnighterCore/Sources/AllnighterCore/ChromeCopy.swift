import Foundation

/// Strings the Mac chrome actually draws. `ChromeCatalog` rows import these;
/// SwiftUI views must use the same constants. If a fact cannot be imported
/// from the enforcing view or store, it is not ready to teach.
public enum ChromeCopy {
    public static let askAI = AskAIPrompt.title
    public static let inbox = "Inbox"
    public static let teams = "Teams"
    public static let models = "Models"
    public static let settings = "Settings"
    public static let plan = "Plan"
    public static let clis = "CLIs"
    public static let boostWindow = "Boost window"
    public static let boostHeadline = "2× the capacity when you need it most."
    public static let boostHow =
        "How? Your capacity refills every 5 hours, but that reset usually lands after your busy stretch. Allnighter triggers an early one so a fresh bucket resets mid-window — two full buckets in the same five hours, not one."
    public static let defaultModel = "Default model"
    public static let defaultModelDeck = "What runs when you don’t pick a team or model."
    public static let useFromCLI = "Use from your CLI"
    public static let aboutUpdates = "About & updates"
    public static let cliOnPATH = "CLI on PATH"
    public static let standaloneHome = "Standalone home"
    public static let resolvesTo = "Resolves to"
    public static let notOnPATH = "(not on PATH)"
    public static let pathRepair = "Repair (app-bundled binary already on disk): alln install-cli"
    public static let pathConflict =
        "PATH resolves to a different binary than the cold-start home. Last writer wins — run install-cli from the binary you want, or the one-liner for a fresh standalone install."
    public static let needAStep = "need a step"
    public static let capacityIdleHero = "Most room on your bench"
    public static let capacityExpiringHero = "Use it before you lose it"
    public static let emailAPerson = "Email a person"
}
