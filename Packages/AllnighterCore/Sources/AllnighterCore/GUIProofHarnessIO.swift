import Foundation

/// Shared on-disk contract for the GUI Visual Proof harness.
///
/// `scripts/gui_proof.sh` launches the `.app` via `open`, so env vars never
/// reach the process. Paths here must stay under `~/Library/Developer/Allnighter`
/// — not DerivedData / `ALLNIGHTER_BUILD_DIR` — or the script and the app
/// disagree and a failed fixture looks like a timeout.
public enum GUIProofHarnessIO {
    public static let lastErrorFileName = "gui-proof-last-error.txt"
    public static let grantMarkerFileName = "gui-proof-screen-recording.ok"
    public static let requestFileName = "gui-proof-request.json"

    /// Tests redirect the whole contract to a temp directory.
    nonisolated(unsafe) public static var devRootOverride: URL?

    public static var defaultDevRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Allnighter", isDirectory: true)
    }

    public static var devRoot: URL { devRootOverride ?? defaultDevRoot }

    public static var lastErrorURL: URL {
        devRoot.appendingPathComponent(lastErrorFileName)
    }

    public static var grantMarkerURL: URL {
        devRoot.appendingPathComponent(grantMarkerFileName)
    }

    public static var requestURL: URL {
        devRoot.appendingPathComponent(requestFileName)
    }

    public static func writeLastError(_ message: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: devRoot, withIntermediateDirectories: true)
        try? message.write(to: lastErrorURL, atomically: true, encoding: .utf8)
    }

    /// Bookkeeping file only — never a substitute for a live TCC preflight.
    public static func writeGrantMarker(
        granted: Bool,
        bundleIdentifier: String,
        bundlePath: String,
        now: Date = Date()
    ) {
        let fm = FileManager.default
        if !granted {
            try? fm.removeItem(at: grantMarkerURL)
            return
        }
        let body = "granted-at=\(ISO8601DateFormatter().string(from: now))\n"
            + "bundle=\(bundleIdentifier)\n"
            + "path=\(bundlePath)\n"
            + "preflight=true\n"
        try? fm.createDirectory(at: devRoot, withIntermediateDirectories: true)
        try? body.write(to: grantMarkerURL, atomically: true, encoding: .utf8)
    }
}
