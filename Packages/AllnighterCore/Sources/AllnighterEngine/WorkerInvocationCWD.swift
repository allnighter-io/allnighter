import Foundation
import AllnighterCore

/// The exact cwd resolution rule `WorkerRunner.invoke`/`invokeStreaming` used, extracted
/// so callers building a `WorkerInvocation` for the composed `WorkerInvoking` stack
/// (`WorkerInvokerFactory`) apply the SAME neutral-scratch policy today's deleted
/// `WorkerRunner` applied inline.
///
/// Rule (unchanged): explicit per-call override, else the runner's configured default
/// (repo-root / project runs), else an Allnighter-owned neutral scratch dir — NEVER the
/// app process's inherited CWD (in dev that's the checkout under `~/Documents`, which
/// trips a TCC Documents prompt attributed to the GUI app on first chat send; Launch
/// Authority TCC hotfix, slice H3).
///
/// `DriverManifest.Invoke.workingDir` (a per-manifest configured cwd) is deliberately
/// NOT part of this rule: every shipped driver manifest sets it to `null` — it has never
/// carried a real value — so folding it in would be dead code reproduced for no reason.
public enum WorkerInvocationCWD {
    public static func resolve(
        override: String?,
        default defaultWorkingDirectory: String?
    ) -> String? {
        override ?? defaultWorkingDirectory ?? AllnighterPaths.ensuredProbeScratchPath()
    }
}
