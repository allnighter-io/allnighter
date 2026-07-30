#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Marker-delimited teaching block for host-agent context files
/// (`docs/archive/phases/Agent_Onboarding.md` Decision 4 + ONB-S01;
/// MR-S05 four-rule live-menu reflex).
///
/// Pure Core SSOT: body text, schema version, content hash, wrap/unwrap.
/// No filesystem writes — the CLI prints; the Mac app (ONB-S03) owns clicks.
public enum TeachingSnippet {
    /// Marker schema version. Bump when the marker grammar or body contract changes.
    public static let schemaVersion = 5

    /// Open marker: `<!-- ALLNIGHTER:TEACHING v<N> hash=<hex> -->`
    public static let openMarkerPrefix = "<!-- ALLNIGHTER:TEACHING v"
    /// Close marker (exact).
    public static let closeMarker = "<!-- ALLNIGHTER:TEACHING:END -->"

    /// Live-menu reflex plus the universal detached-delivery discipline.
    /// Protocol only — never embed models, teams, recipes, or command rows.
    /// Surface-specific commands remain in their acknowledgement and recipe.
    public static let reflexLines = [
        "1. Before first Allnighter use in a session, read `alln menu --json`.",
        "2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.",
        "3. Before an unfamiliar agent-starting action, run its validation template.",
        "4. Re-read the live menu in a new session; never trust a pasted catalog.",
        "5. After `--no-wait`, run the returned delivery command once; never poll or use resume for terminal delivery.",
        "6. Relay running ≠ dev running — check devRunId.",
    ]

    /// Canonical inner teaching body (hash input). No trailing newline.
    public static var body: String {
        reflexLines.joined(separator: "\n")
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

    /// UTF-16 NSRange covering one teaching block (open marker through close marker).
    /// Nil when markers are absent or not a single well-ordered pair.
    public struct BlockSpan: Sendable, Equatable {
        public var fullRange: NSRange
        public var openRange: NSRange
        public var closeRange: NSRange
        public var version: Int?
        public var hash: String?
    }

    /// Locate the marked teaching block. For a single open+close pair returns that
    /// span; for duplicates returns the span from the first open through the last
    /// close (installer repair/remove); absent → nil.
    public static func blockSpan(in contents: String) -> BlockSpan? {
        let ns = contents as NSString
        let full = NSRange(location: 0, length: ns.length)
        let opens = openPattern.matches(in: contents, range: full)
        let closes = closePattern.matches(in: contents, range: full)
        guard let firstOpen = opens.first, let lastClose = closes.last else { return nil }
        let openEnd = firstOpen.range.location + firstOpen.range.length
        let closeStart = lastClose.range.location
        guard closeStart >= openEnd else { return nil }

        var version: Int?
        var hash: String?
        if firstOpen.numberOfRanges >= 3 {
            let vr = firstOpen.range(at: 1)
            let hr = firstOpen.range(at: 2)
            if vr.location != NSNotFound { version = Int(ns.substring(with: vr)) }
            if hr.location != NSNotFound { hash = ns.substring(with: hr).lowercased() }
        }

        let fullRange = NSRange(
            location: firstOpen.range.location,
            length: (lastClose.range.location + lastClose.range.length) - firstOpen.range.location
        )
        return BlockSpan(
            fullRange: fullRange,
            openRange: firstOpen.range,
            closeRange: lastClose.range,
            version: version,
            hash: hash
        )
    }
}
