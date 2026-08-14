import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln chrome --json` — Mac owner-action catalog. Same discovery law as
/// `alln menu --json`. Rows are projected from the labels the Mac app draws.
enum ChromeCLI {
    static func run(_ args: [String], runtime: ToolRuntime) {
        let opts = Options(args)
        let screen = opts.value("screen")
        let setup = SetupStore().load()
        let tally = BenchTallyProjector.tally(
            registry: runtime.registry,
            records: setup.records,
            parked: setup.parkedSet
        )
        let boost = BoostWindowSettingsPersistence().load()
        let home = ReleaseChannel.standaloneBinaryPath()
        let resolved = InstallCLI.resolveOnPath(
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
        )
        let conflict: Bool = {
            guard let resolved else { return false }
            return !InstallCLI.sameExecutable(resolved, home)
        }()
        let live = ChromeLiveFacts(
            boostEnabled: boost.enabled,
            boostWindowStart: BoostWindowTiming.formatMinutes(boost.windowStart),
            benchChromeLabel: BenchTallyProjector.chromeLabel(for: tally),
            benchReady: tally.ready,
            benchNeedsStep: tally.needsStep,
            benchSupported: tally.supported,
            pathStandaloneHome: home,
            pathResolved: resolved,
            pathConflict: conflict
        )
        let json = ChromeCatalog.project(screen: screen, live: live)
        do {
            print(try ChromeCatalog.encode(json))
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "failed to encode chrome catalog: \(error)")
        }
    }
}
