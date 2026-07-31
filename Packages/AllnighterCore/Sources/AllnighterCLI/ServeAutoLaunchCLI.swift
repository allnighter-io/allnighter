import Foundation
import AllnighterCore
import AllnighterEngine

/// URN-S02 CLI glue — the single opt-out check and single stderr reporting
/// format shared by the four `pair` verbs that dispatch a real dev turn
/// (`pilot handoff`, `relay`, `relay-resume`, `relay adopt`). Not called from
/// `pilot start`, which only parks `awaitingPM`; nothing runs there yet.
enum ServeAutoLaunchCLI {
    /// `true` ⇒ neither opt-out is present, so auto-launch should be
    /// attempted. `--no-auto-serve` present → false; `ALLN_NO_AUTO_SERVE` set
    /// to any non-empty value → false; neither → true.
    static func shouldAutoLaunchServe(
        _ opts: Options,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !ServeAutoLaunch.isOptedOut(flag: opts.flag("no-auto-serve"), environment: environment)
    }

    /// Runs the guarantee for this dispatch. Never throws, never touches the
    /// caller's exit code — callers use the returned outcome only to report
    /// it (JSON field or stderr line), never to gate their own success path.
    @discardableResult
    static func ensureRunning(_ opts: Options) -> ServeAutoLaunch.LaunchResult {
        ServeAutoLaunch.ensureRunning(optedOut: !shouldAutoLaunchServe(opts))
    }

    /// Reports an auto-launch outcome to stderr, one line — used by the three
    /// verbs whose JSON envelope is the shared `LoopJSON` (no `serveAutoLaunch`
    /// field there by design) and by the blocking `pilot handoff` path.
    /// `.failed` is not re-reported here: `ServeAutoLaunch.ensureRunning`
    /// already wrote its one stderr line for that case. `.skipped` stays
    /// silent — opting out is intentional, not something to nag about.
    static func reportToStderr(_ result: ServeAutoLaunch.LaunchResult) {
        switch result.outcome {
        case .alreadyRunning:
            FileHandle.standardError.write(Data("alln serve: already running\n".utf8))
        case .launched:
            let pidPart = result.pid.map { " (pid \($0))" } ?? ""
            FileHandle.standardError.write(Data("alln serve: launched\(pidPart)\n".utf8))
        case .skipped, .failed:
            break
        }
    }
}
