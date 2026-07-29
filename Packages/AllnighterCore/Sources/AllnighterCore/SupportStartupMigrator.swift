import Foundation

/// Runs one-time support-root migrations before stores read user history.
public enum SupportStartupMigrator {
    private static let lock = NSLock()
    private static var didRun = false

    /// Idempotent; safe to call on every CLI invocation and app launch.
    public static func runOnce() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didRun else { return }
        didRun = true
        let root = AllnighterSupportRoot.support
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try RetiredWorkerKeysMigration.migrate(supportRoot: root)
    }
}
