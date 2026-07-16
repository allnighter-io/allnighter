import Foundation

/// Core-owned support-dir resolution (mirrors `AllnighterEngine.AllnighterPaths.support`).
/// Catalog + roster persistence in Core must honor `ALLNIGHTER_SUPPORT_DIR` the same
/// way engine stores do — otherwise isolated config homes split roster state.
public enum AllnighterSupportRoot {
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter", isDirectory: true)
    }

    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }
}
