import Foundation

/// How the Signal scout must obtain a source, decided by the link itself.
///
/// This is a SAFETY rule before it is a routing convenience: running a media
/// downloader (`vvx` → yt-dlp) against an X/Twitter URL risks the user's own X
/// account under X's terms. X links are read by an X-capable model (Grok) or
/// they fail honestly — never by `vvx`.
///
/// HONEST LIMIT — read before trusting this type. This enum is the single owner
/// of the RULE, and `scoutInstructions` is generated from it so the teaching can
/// never contradict the policy. But the scout is a vendor CLI that shells out on
/// its own; Allnighter does not sit between it and its subprocesses, so nothing
/// here can physically block a `vvx` invocation. Enforcement is therefore the
/// scout's instructions, not an interceptor. `allowsVideoTool` exists for callers
/// that CAN gate (a future confirm sheet, a pre-dispatch check) and is currently
/// used only by tests — do not describe this as code-enforced end to end.
public enum SignalSourceRoute: String, Codable, Sendable, Equatable, CaseIterable {
    /// X / Twitter. Grok reads it. `vvx` is FORBIDDEN on this route.
    case xModelOnly
    /// Any other link. `vvx` extracts metadata + transcript (no media download).
    case videoTool
    /// A known link shortener. Where it lands is unknowable without following it,
    /// and it may land on X — so the downloader is forbidden here too. The model
    /// resolves it by reading, never `vvx`.
    case unresolvedRedirect
    /// No usable URL in the prompt — the worker reasons over pasted text.
    case pastedText
}

public extension SignalSourceRoute {
    /// The safety predicate: routes where a media downloader must never be aimed.
    var forbidsVideoTool: Bool { self == .xModelOnly || self == .unresolvedRedirect }
}

/// Decides — from a prompt or a bare link — how the Signal scout is allowed to
/// fetch the source. Pure and reusable: the skill prompt text below is generated
/// from these same rules, so the teaching and the policy cannot drift apart.
public enum SignalSourceRouter {

    /// Hosts that are X, including the `t.co` shortener (it redirects INTO x.com,
    /// so resolving it with a downloader is the same exposure).
    static let xHosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com", "m.x.com",
        "twitter.com", "www.twitter.com", "mobile.twitter.com", "m.twitter.com"
    ]

    /// Link shorteners. `t.co` is X's own, but ANY shortener can land on X, and we
    /// refuse to find out by following it with a downloader. Fail safe: the model
    /// resolves the destination by reading.
    static let shortenerHosts: Set<String> = [
        "t.co", "www.t.co", "bit.ly", "buff.ly", "ow.ly", "tinyurl.com",
        "goo.gl", "lnkd.in", "trib.al", "dlvr.it", "rb.gy", "is.gd", "shorturl.at"
    ]

    /// The tool the non-X route shells out to. A user-installed CLI — Allnighter
    /// never fetches anything itself.
    ///
    /// NOTE: `vvx` itself CAN sense an x.com URL (its own help advertises it).
    /// Allnighter is deliberately stricter: `sense` runs yt-dlp under the hood, and
    /// pointing that at X risks the user's account under X's terms. Capability is
    /// not permission — the X route stays model-only regardless of what the tool
    /// will accept.
    public static let videoToolCommand = "vvx"
    public static let videoToolInstallHint = "brew install videovortex-app/tap/vvx"

    /// Classify a single URL string.
    public static func route(forURL raw: String) -> SignalSourceRoute {
        guard let host = host(ofURL: raw) else { return .pastedText }
        if xHosts.contains(host) { return .xModelOnly }
        if shortenerHosts.contains(host) { return .unresolvedRedirect }
        return .videoTool
    }

    /// Classify a whole prompt: the FIRST url decides, and any X link anywhere in
    /// the prompt forces the X route. Fail-safe by construction — a prompt mixing
    /// an X link with a YouTube link must never authorise `vvx`, because the
    /// scout could otherwise point the downloader at the X one.
    public static func route(forPrompt prompt: String) -> SignalSourceRoute {
        let urls = self.urls(in: prompt)
        guard !urls.isEmpty else { return .pastedText }
        if urls.contains(where: { route(forURL: $0) == .xModelOnly }) { return .xModelOnly }
        if urls.contains(where: { route(forURL: $0) == .unresolvedRedirect }) { return .unresolvedRedirect }
        return .videoTool
    }

    /// True only when shelling out to the video tool is permitted for this prompt.
    public static func allowsVideoTool(forPrompt prompt: String) -> Bool {
        route(forPrompt: prompt) == .videoTool
    }

    public static func urls(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { $0.url?.absoluteString }
    }

    static func host(ofURL raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: candidate)?.host?.lowercased(), host.contains(".") else { return nil }
        return host
    }

    /// The scout's fetch instructions, generated from the rules above so the
    /// prompt can never authorise something the policy forbids.
    public static var scoutInstructions: String {
        """
        Getting the source — follow this exactly, it is a safety rule, not a preference:
        - X / Twitter link (\(xHosts.sorted().prefix(3).joined(separator: ", ")), …): read it \
        yourself as an X-capable model. NEVER run \(videoToolCommand) or any downloader on an \
        X link — that risks the user's X account under X's terms. If you cannot read the post, \
        say so and stop; do not work around it.
        - Shortened link (\(shortenerHosts.sorted().prefix(4).joined(separator: ", ")), …): you \
        cannot know where it lands, and it may land on X. Resolve it by READING it yourself \
        first. Never hand a shortener to \(videoToolCommand) — only once you have seen a \
        non-X destination may you treat it as an ordinary link.
        - Any other link: run `\(videoToolCommand) sense "<url>"` — ALWAYS with the url in \
        double quotes, or the shell will mangle `?v=` — which extracts metadata and a \
        transcript with no media download. It prints JSON; read the file at its \
        `transcriptPath` to get the full transcript, and use that as the source. If the \
        link is not a video, read the page directly instead.
        - If `\(videoToolCommand)` is missing: do NOT guess from the title and do NOT reach for \
        another downloader. Stop and tell the user to install it with `\(videoToolInstallHint)`, \
        or to paste the transcript.
        - No link at all: reason over the pasted text.
        """
    }
}
