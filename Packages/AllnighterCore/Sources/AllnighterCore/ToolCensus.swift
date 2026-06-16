import Foundation

// Agent-powered tool discovery (the "census"). A healthy worker runs a read-only
// build order — "find these CLIs, report {absolute_path, version}" — and returns
// JSON. We ingest it as a HINT, never trusted: every path is verified by actually
// running it before a tool is marked ready (health == runs). See the setup phase
// docs; this is the long-tail finder that backstops the plain-code resolver.

/// A parsed census: bin name → discovered location. Keys are bin names
/// (`claude`, `codex`, `grok`, `agy`); unknown keys are ignored at match time.
public struct ToolCensus: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Codable {
        public var absolutePath: String
        public var version: String?

        public init(absolutePath: String, version: String? = nil) {
            self.absolutePath = absolutePath
            self.version = version
        }

        private enum CodingKeys: String, CodingKey {
            case absolutePath = "absolute_path"
            case version
        }
    }

    public var entries: [String: Entry]

    public init(entries: [String: Entry]) { self.entries = entries }

    public enum CensusError: Error, Equatable { case notJSON }

    /// Parse the agent's JSON. Tolerant of surrounding prose: if the output is
    /// wrapped in commentary, the first top-level `{ … }` object is extracted so
    /// a chatty CLI still ingests. Entries with a blank path are dropped.
    public static func parse(_ raw: String) throws -> ToolCensus {
        let candidate = extractJSONObject(from: raw) ?? raw
        guard let data = candidate.data(using: .utf8) else { throw CensusError.notJSON }
        let decoded: [String: Entry]
        do {
            decoded = try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            throw CensusError.notJSON
        }
        let clean = decoded.filter {
            !$0.value.absolutePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ToolCensus(entries: clean)
    }

    /// Match census entries to drivers via `setup.bins`. One candidate per matched
    /// headless-CLI driver (the first reported bin wins).
    public func candidates(for manifests: [DriverManifest]) -> [Candidate] {
        var out: [Candidate] = []
        for manifest in manifests where manifest.kind == .headlessCLI {
            guard let bins = manifest.setup?.bins else { continue }
            for bin in bins {
                guard let entry = entries[bin] else { continue }
                out.append(Candidate(
                    driverId: manifest.id,
                    bin: bin,
                    path: entry.absolutePath,
                    version: entry.version,
                    looksEphemeral: CensusPath.looksEphemeral(entry.absolutePath)
                ))
                break
            }
        }
        return out
    }

    /// One driver's worth of discovered location, ready to verify.
    public struct Candidate: Sendable, Equatable {
        public var driverId: String
        public var bin: String
        public var path: String
        public var version: String?
        /// True when the path is version-pinned / upgrade-fragile (a `/downloads/`,
        /// `/versions/2.1.178`, or `/Caskroom/<v>/` blob). Such a path runs today
        /// but breaks on the next tool upgrade, so ingest must prefer a stable
        /// launcher (`~/.local/bin/<bin>`, `/opt/homebrew/bin/<bin>`, …) when one
        /// exists and fall back to this only as a last resort.
        public var looksEphemeral: Bool

        public init(driverId: String, bin: String, path: String, version: String?, looksEphemeral: Bool) {
            self.driverId = driverId
            self.bin = bin
            self.path = path
            self.version = version
            self.looksEphemeral = looksEphemeral
        }
    }

    /// Extract the outermost `{ … }` so JSON wrapped in prose still parses.
    private static func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        return String(raw[start...end])
    }
}

/// Whether a binary path is a stable launcher (survives upgrades) or a
/// version-pinned blob the manager will move on the next upgrade. The agent that
/// runs the census tends to chase symlinks all the way to the payload, so we
/// guard against caching a path that will 404 after `tool upgrade`.
public enum CensusPath {
    public static func looksEphemeral(_ path: String) -> Bool {
        let lower = path.lowercased()
        let markers = ["/downloads/", "/versions/", "/caskroom/", "/cellar/", "/.cache/"]
        if markers.contains(where: { lower.contains($0) }) { return true }
        // A path component that is a bare version number (…/2.1.178/…, …/0.130.0/…).
        return path.split(separator: "/").contains(where: isVersionLike)
    }

    private static func isVersionLike(_ s: Substring) -> Bool {
        var sawDigit = false
        var sawDot = false
        for ch in s {
            if ch.isNumber { sawDigit = true }
            else if ch == "." { sawDot = true }
            else { return false }
        }
        return sawDigit && sawDot
    }
}
