import Foundation

/// Path-overlap convergence for a panel round (`docs/phases/Panel_Polish.md` §1 decision 4).
/// Flag only — never ranks, scores, or orders by importance. An entry exists when ≥2
/// **distinct** seats cite the same file-path-shaped anchor in finding evidence/claim.
public enum PanelConvergence {
    /// Known source/doc suffixes that mark a bare filename as path-shaped even without `/`.
    private static let pathSuffixes: Set<String> = [
        "swift", "md", "txt", "json", "yml", "yaml", "toml", "plist",
        "ts", "tsx", "js", "jsx", "mjs", "cjs",
        "py", "rb", "go", "rs", "java", "kt", "kts",
        "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "m", "mm",
        "sh", "bash", "zsh", "fish",
        "html", "htm", "css", "scss", "less",
        "sql", "graphql", "proto",
        "xml", "svg", "csv", "tsv",
        "r", "R", "jl", "lua", "php", "cs", "fs", "scala",
        "dockerfile", "makefile", "cmake",
    ]

    /// Project convergence entries from a round's merged seat results.
    /// Always returns a (possibly empty) array; sorted lexically by `anchor`, seats sorted.
    public static func project(from results: [SeatResult]) -> [PanelConvergenceJSON] {
        // anchor → set of distinct workerIds that cited it
        var seatsByAnchor: [String: Set<String>] = [:]

        for seat in results {
            guard let findings = seat.findings else { continue }
            var anchorsForSeat = Set<String>()
            for finding in findings {
                for text in [finding.evidence, finding.claim] {
                    for anchor in extractAnchors(from: text) {
                        anchorsForSeat.insert(anchor)
                    }
                }
            }
            for anchor in anchorsForSeat {
                seatsByAnchor[anchor, default: []].insert(seat.workerId)
            }
        }

        return seatsByAnchor
            .compactMap { anchor, seats -> PanelConvergenceJSON? in
                guard seats.count >= 2 else { return nil }
                return PanelConvergenceJSON(
                    anchor: anchor,
                    seats: seats.sorted()
                )
            }
            .sorted { $0.anchor < $1.anchor }
    }

    /// Extract normalized path-shaped anchors from free text.
    public static func extractAnchors(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []

        // Split on whitespace and common wrappers; keep path-like fragments.
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.init(charactersIn: "()[]{}\"'`,;!?<>|"))
        for raw in text.components(separatedBy: separators) where !raw.isEmpty {
            guard let anchor = normalizeToken(raw), seen.insert(anchor).inserted else { continue }
            ordered.append(anchor)
        }
        return ordered
    }

    /// Normalize one token into a bare path anchor, or nil if not path-shaped.
    static func normalizeToken(_ raw: String) -> String? {
        var token = raw

        // Strip leading punctuation (quotes already handled by split; keep # for #N refs? no — strip).
        while let first = token.first, ".,:;!?*-–—".contains(first) {
            token.removeFirst()
        }
        // Strip trailing punctuation except when part of a path (handled after :line strip).
        while let last = token.last, ".,:;!?*-–—".contains(last) {
            token.removeLast()
        }
        guard !token.isEmpty else { return nil }

        // Strip trailing :line or :line:col (e.g. docs/spec.md:42, Foo.swift:10:3).
        while let colon = token.lastIndex(of: ":") {
            let after = token[token.index(after: colon)...]
            if !after.isEmpty, after.allSatisfy(\.isNumber) {
                token = String(token[..<colon])
            } else {
                break
            }
        }
        // Trailing punctuation again after line strip (e.g. `file.swift:12.`).
        while let last = token.last, ".,:;!?*-–—".contains(last) {
            token.removeLast()
        }
        guard !token.isEmpty else { return nil }

        // Path-shaped: contains `/` or ends with a known source/doc suffix.
        let isPathShaped: Bool
        if token.contains("/") {
            isPathShaped = true
        } else if let dot = token.lastIndex(of: "."),
                  dot > token.startIndex,
                  token.index(after: dot) < token.endIndex {
            let ext = String(token[token.index(after: dot)...]).lowercased()
            isPathShaped = pathSuffixes.contains(ext)
        } else {
            isPathShaped = false
        }
        guard isPathShaped else { return nil }

        // Drop pure `./` or trailing slash noise.
        while token.hasPrefix("./") {
            token = String(token.dropFirst(2))
        }
        while token.hasSuffix("/") && token.count > 1 {
            token.removeLast()
        }
        guard !token.isEmpty, token != "." else { return nil }
        return token
    }
}
