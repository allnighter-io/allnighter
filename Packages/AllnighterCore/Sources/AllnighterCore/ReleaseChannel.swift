import Foundation

/// Canonical install / upgrade one-liner (OPC-S03).
///
/// Single SSOT string for help, README, and (later) menu `update.command`.
/// Fetch/cache/manifest logic ships in OPC-S06 — this type holds the constant only.
public enum ReleaseChannel {
    /// Public install and upgrade command. Never invent cousins; cite this string.
    public static let installCommand = "curl -fsSL https://get.allnighter.app | sh"
}
