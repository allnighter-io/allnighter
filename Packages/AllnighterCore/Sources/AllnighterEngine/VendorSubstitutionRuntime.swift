import Foundation
import AllnighterCore

/// Runtime checks for RLC-S04 substitution (needs process ownership truth).
public enum VendorSubstitutionRuntime {
    /// Mutating substitution requires the original worker tree to be quiescent.
    public static func isOriginalWorkerQuiescent(
        runDirectory: URL,
        run: TeamRun
    ) -> Bool {
        if run.phase == .waitingForVendor { return true }
        let workers = ProcessOwnership.readWorkerOwners(inRunDirectory: runDirectory)
        return !workers.contains { ProcessOwnership.isIdentityAlive($0.identity) }
    }
}
