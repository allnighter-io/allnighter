import CryptoKit
import Foundation

/// Marker-delimited teaching block for host-agent context files
/// (`docs/phases/Agent_Onboarding.md` Decision 4 + ONB-S01).
///
/// Pure Core SSOT: body text, schema version, content hash, wrap/unwrap.
/// No filesystem writes — the CLI prints; the Mac app (ONB-S03) owns clicks.
public enum TeachingSnippet {
    /// Marker schema version. Bump when the marker grammar or body contract changes.
    public static let schemaVersion = 1

    /// Open marker: `<!-- ALLNIGHTER:TEACHING v<N> hash=<hex> -->`
    public static let openMarkerPrefix = "<!-- ALLNIGHTER:TEACHING v"
    /// Close marker (exact).
    public static let closeMarker = "<!-- ALLNIGHTER:TEACHING:END -->"

    /// The v3 router-reflex trigger (Decision 4). Asking is always safe;
    /// executing `recommended.command` needs the same user authorization as any
    /// mutating/spending action — never auto-run.
    public static let triggerLine =
        "Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for \"<the user's intent>\" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker."

    /// Short companions kept with the trigger (help search + doctor). Panel/Pilot
    /// multi-line recipes stay out of bootstrap — see `help get panel`.
    public static let companionLines = [
        "- Find anything with `alln help search \"<query>\"`, then `alln help get <topic>`. Prefer `--json` envelopes.",
        "- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.",
    ]

    /// Canonical inner teaching body (hash input). No trailing newline.
    public static var body: String {
        ([triggerLine] + companionLines).joined(separator: "\n")
    }

    /// SHA256 hex of the canonical inner body UTF-8 bytes.
    public static var contentHash: String {
        hash(of: body)
    }

    public static func hash(of bodyText: String) -> String {
        SHA256.hash(data: Data(bodyText.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Full marked block ready to paste/install.
    public static func wrap(
        body bodyText: String = body,
        version: Int = schemaVersion,
        hash hex: String? = nil
    ) -> String {
        let digest = hex ?? hash(of: bodyText)
        return """
        \(openMarker(version: version, hash: digest))
        \(bodyText)
        \(closeMarker)
        """
    }

    public static func openMarker(version: Int, hash hex: String) -> String {
        "\(openMarkerPrefix)\(version) hash=\(hex) -->"
    }

    /// Doctor / installer parse states for a file's teaching block.
    public enum InstallState: String, Sendable, Equatable, CaseIterable {
        /// No Allnighter teaching markers present.
        case absent
        /// Current schema version + matching content hash.
        case installed
        /// Recognizable markers with an older (or foreign) schema version.
        case stale
        /// Current schema version but hash does not match canonical body (hand-edit).
        case modified
        /// Broken / duplicate / unparseable markers.
        case malformed
    }

    public struct ParseResult: Sendable, Equatable {
        public var state: InstallState
        public var version: Int?
        public var hash: String?
        public var body: String?
        public var detail: String

        public init(
            state: InstallState,
            version: Int? = nil,
            hash: String? = nil,
            body: String? = nil,
            detail: String
        ) {
            self.state = state
            self.version = version
            self.hash = hash
            self.body = body
            self.detail = detail
        }
    }

    private static let openPattern = try! NSRegularExpression(
        pattern: #"<!--\s*ALLNIGHTER:TEACHING\s+v(\d+)\s+hash=([a-fA-F0-9]+)\s*-->"#
    )
    private static let closePattern = try! NSRegularExpression(
        pattern: #"<!--\s*ALLNIGHTER:TEACHING:END\s*-->"#
    )

    /// Parse teaching markers from file contents. Pure — no I/O.
    public static func parse(_ contents: String?) -> ParseResult {
        guard let contents, !contents.isEmpty else {
            return ParseResult(state: .absent, detail: "no teaching block")
        }

        let ns = contents as NSString
        let full = NSRange(location: 0, length: ns.length)
        let opens = openPattern.matches(in: contents, range: full)
        let closes = closePattern.matches(in: contents, range: full)

        if opens.isEmpty && closes.isEmpty {
            // Legacy / unmarked Allnighter mentions are not a teaching install.
            return ParseResult(state: .absent, detail: "no teaching markers")
        }
        if opens.count != 1 || closes.count != 1 {
            return ParseResult(
                state: .malformed,
                detail: "teaching markers malformed (open=\(opens.count), close=\(closes.count))"
            )
        }

        let open = opens[0]
        let close = closes[0]
        guard open.numberOfRanges >= 3 else {
            return ParseResult(state: .malformed, detail: "teaching open marker unparseable")
        }
        let versionRange = open.range(at: 1)
        let hashRange = open.range(at: 2)
        guard versionRange.location != NSNotFound, hashRange.location != NSNotFound,
              let version = Int(ns.substring(with: versionRange)) else {
            return ParseResult(state: .malformed, detail: "teaching open marker missing version/hash")
        }
        let foundHash = ns.substring(with: hashRange).lowercased()

        let bodyStart = open.range.location + open.range.length
        let bodyEnd = close.range.location
        guard bodyEnd >= bodyStart else {
            return ParseResult(
                state: .malformed,
                version: version,
                hash: foundHash,
                detail: "teaching close marker precedes open marker"
            )
        }

        var inner = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
        // Canonical body has no surrounding newlines; tolerate one leading/trailing \n from wrap().
        if inner.hasPrefix("\n") { inner.removeFirst() }
        if inner.hasSuffix("\n") { inner.removeLast() }

        if version != schemaVersion {
            let relation = version < schemaVersion ? "older" : "newer"
            return ParseResult(
                state: .stale,
                version: version,
                hash: foundHash,
                body: inner,
                detail: "teaching schema v\(version) is \(relation) than expected v\(schemaVersion)"
            )
        }

        let expected = contentHash
        if foundHash != expected || inner != body {
            return ParseResult(
                state: .modified,
                version: version,
                hash: foundHash,
                body: inner,
                detail: "teaching hash mismatch (file=\(foundHash.prefix(12))… expected=\(expected.prefix(12))…)"
            )
        }

        return ParseResult(
            state: .installed,
            version: version,
            hash: foundHash,
            body: inner,
            detail: "teaching v\(version) installed"
        )
    }
}
