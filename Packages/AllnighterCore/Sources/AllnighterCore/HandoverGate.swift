import Foundation

/// Danger scan over a Loop handover's free prose (PM_Relay.md §5 item 1). This is the
/// slice-queue danger gate's shape (`TryFixGate`/`SliceGate`): **danger blocks, doubt does
/// not**. There is no confidence threshold, no "this sounds risky" fuzz — only a short,
/// named list of danger classes fires: credential/secret exposure, signing/distribution,
/// destructive git, sandbox/TCC/system permission changes, and mass deletion outside an
/// obvious build dir.
///
/// Detection matches **imperative danger instructions**, not mere mentions: patterns pair a
/// danger noun (API key, `codesign`, `reset --hard`, `tccutil reset`, …) with a nearby action
/// verb, and a shared negation/safe-context check scoped to the sentence containing the match
/// waves off handovers that are *prohibiting*, *reviewing*, or *undoing* the danger rather
/// than ordering it ("don't force-push", "revert the accidental reset --hard"). Doubt does
/// not block: a handover merely mentioning a term with no imperative pairing, or discussing
/// it in a safe-context sentence, passes.
public enum HandoverGate {
    /// The five named danger classes (PM_Relay.md §5 item 1). No catch-all "risky" bucket —
    /// unmatched prose is doubt, and doubt doesn't block.
    public enum DangerClass: String, Sendable, Equatable, CaseIterable {
        case credentialsSecrets
        case signingDistribution
        case destructiveGit
        case sandboxPermissions
        case massDeletion
    }

    public enum Decision: Equatable, Sendable {
        case allowed
        /// `dangerClass` + `snippet` are carried for the escalation message — the founder
        /// needs to see exactly what fired and where, not just that something did.
        case blocked(dangerClass: DangerClass, code: String, reason: String, snippet: String)

        public var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }
    }

    private static let unsafeCode = "RELAY_HANDOVER_UNSAFE"

    public static func evaluate(handoverText: String) -> Decision {
        for rule in rules {
            for pattern in rule.patterns {
                guard let range = firstUnsafeMatch(of: pattern, in: handoverText) else { continue }
                return .blocked(
                    dangerClass: rule.dangerClass,
                    code: unsafeCode,
                    reason: rule.reason,
                    snippet: snippetText(handoverText, range))
            }
        }
        if let decision = rmRfDecision(in: handoverText) {
            return decision
        }
        return .allowed
    }

    // MARK: - Danger table

    private struct DangerRule {
        let dangerClass: DangerClass
        let reason: String
        let patterns: [NSRegularExpression]
    }

    private static let rules: [DangerRule] = [
        DangerRule(
            dangerClass: .credentialsSecrets,
            reason: "credential/secret exposure instruction (API key, token, .env, or keychain)",
            patterns: compile([
                verbNounPattern(
                    verbs: ["commit", "push", "print", "log", "paste", "dump", "export", "upload",
                            "email", "share", "expose", "hardcode", "leak", "send", "post"],
                    nouns: ["api\\s*keys?", "secrets?", "tokens?", "credentials?", "passwords?",
                            "\\.env(?:\\s*file)?s?", "keychain"])
            ])),
        DangerRule(
            dangerClass: .signingDistribution,
            reason: "signing/distribution instruction (codesign, notarization, provisioning, or App Store submission)",
            patterns: compile([
                verbNounPattern(
                    verbs: ["run", "execute", "do", "perform", "start", "trigger", "kick off",
                            "create", "generate", "upload", "submit", "publish", "ship", "install"],
                    nouns: ["codesign", "notariz\\w+", "provisioning\\s+profile",
                            "distribution\\s+certificate", "app\\s*store"]),
                "\\b(codesign|notarize)\\s+(the|this|our|it)\\b"
            ])),
        DangerRule(
            dangerClass: .destructiveGit,
            reason: "destructive git instruction (hard reset, force push, history rewrite, or shared-branch deletion)",
            patterns: compile([
                "\\b(git\\s+)?reset\\s+--hard\\b",
                "\\b(git\\s+)?push\\s+(-f\\b|--force\\b)",
                "\\bforce[- ]push(es|ed|ing)?\\b",
                "\\b(git\\s+)?filter-(branch|repo)\\b",
                "\\brewrit(e|es|ing)\\s+(the\\s+)?(git\\s+)?history\\b",
                "\\bhistory\\s+rewrite\\b",
                "\\bdelete\\s+(the\\s+)?(shared\\s+)?(main|master|develop|production|release)\\s+branch\\b",
                "\\b(git\\s+)?branch\\s+-D\\s+(main|master|develop|production|release)\\b"
            ])),
        DangerRule(
            dangerClass: .sandboxPermissions,
            reason: "sandbox/TCC/system permission instruction (tccutil, csrutil, SIP, or sudo system command)",
            patterns: compile([
                "\\btccutil\\s+reset\\b",
                "\\bcsrutil\\s+(disable|enable)\\b",
                "\\bsudo\\s+(spctl|nvram|systemsetup|kextload|installer|scutil|dscl|pmset)\\b",
                "\\bdisable\\s+(the\\s+)?(system\\s+integrity\\s+protection|sip)\\b",
                "\\bdisable\\s+the\\s+sandbox\\b"
            ])),
        DangerRule(
            dangerClass: .massDeletion,
            reason: "mass-deletion instruction outside an obvious build directory",
            patterns: compile([
                "\\b(delete|wipe|remove)\\s+(everything|all\\s+files|the\\s+entire\\s+repo|the\\s+whole\\s+repo|the\\s+entire\\s+project)\\b"
            ]))
    ]

    /// `rm -rf <target>` is only dangerous when the target isn't an obvious, disposable
    /// build/cache directory — handled separately from the verb/noun table because the
    /// "danger or not" call depends on the captured argument, not just the command name.
    private static let buildDirAllowlist: Set<String> = [
        "node_modules", ".build", "build", "dist", "derivedData", ".next", "out",
        "coverage", ".cache", "target", "__pycache__", ".pytest_cache", ".turbo",
        ".gradle", "bin", "obj", ".dart_tool", ".gradle_cache"
    ]

    private static func rmRfDecision(in text: String) -> Decision? {
        // Capture the WHOLE argument list after `rm -rf` (up to the next shell operator or
        // end of line), not just the first token — `rm -rf build /important-data` used to
        // read only `build`, see the allowlist, and wave the whole command (incl.
        // `/important-data`) through. EVERY target must be an allowlisted build dir for the
        // command to pass. (SR-2 / Sol F9.)
        guard let regex = try? NSRegularExpression(
            pattern: "rm\\s+-rf\\s+(.+?)(?=\\s*(?:&&|\\|\\||;|\\||>>|>|<|\\n|$))",
            options: [.caseInsensitive])
        else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let fullRange = Range(match.range, in: text), match.numberOfRanges > 1 else { continue }
            let rawTail = nsText.substring(with: match.range(at: 1))
            let targets = rawTail
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.hasPrefix("-") }   // drop flags like `--no-preserve-root`
            let hasDangerousTarget = targets.contains { target in
                let cleaned = target.trimmingCharacters(in: CharacterSet(charactersIn: "./\\"))
                let lastComponent = cleaned.split(separator: "/").last.map(String.init) ?? cleaned
                return !buildDirAllowlist.contains(lastComponent.lowercased())
            }
            if !hasDangerousTarget { continue }   // every target is an allowlisted build dir
            if containsSafeContextCue(String(sentence(around: fullRange, in: text))) { continue }
            return .blocked(
                dangerClass: .massDeletion,
                code: unsafeCode,
                reason: "mass-deletion instruction outside an obvious build directory",
                snippet: snippetText(text, fullRange))
        }
        return nil
    }

    // MARK: - Pattern building

    private static func verbNounPattern(verbs: [String], nouns: [String]) -> String {
        "\\b(\(verbs.joined(separator: "|")))\\b[\\w\\s\\-./]{0,30}\\b(\(nouns.joined(separator: "|")))\\b"
    }

    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    // MARK: - Negation / safe-context

    /// Cue words that, when present in the same sentence as a danger match, mean the
    /// sentence is prohibiting, reviewing, or undoing the danger rather than ordering it.
    /// Doubt does not block — when in doubt, this list errs toward "don't block."
    private static let safeContextCues: [String] = [
        "don't", "do not", "doesn't", "does not", "never", "won't", "will not",
        "shouldn't", "should not", "must not", "mustn't", "cannot", "can't",
        "avoid", "refrain from", "prohibited", "banned", "disallowed",
        "not to", "no need to",
        // NOTE: "without" is deliberately NOT a safe cue. "Proceed without asking",
        // "without confirming", "without review" are autonomy-granting phrases —
        // the opposite of a prohibition — and used to whitelist a whole (non-`.`/`!`/`?`
        // -delimited, e.g. semicolon-joined) sentence that also carried a real danger
        // instruction. A "without" that genuinely prohibits (e.g. "proceed without
        // running reset --hard") now blocks; escalating to a human on that ambiguity is
        // the safe direction for this human-confirm net. (SR-1 / Sol F8.)
        "revert", "reverting", "reverted",
        "undo", "undoing", "undone",
        "restore", "restoring", "restored",
        "recover", "recovering", "recovered",
        "accidental", "accidentally",
        "rolled back", "rolling back", "roll back"
    ]

    private static func containsSafeContextCue(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        return safeContextCues.contains { lowered.contains($0) }
    }

    /// The first match of `regex` in `text` whose containing sentence carries no
    /// safe-context cue, in document order. Later, un-negated matches of the same pattern
    /// still fire even if an earlier occurrence was negated.
    private static func firstUnsafeMatch(of regex: NSRegularExpression, in text: String) -> Range<String.Index>? {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            if containsSafeContextCue(String(sentence(around: range, in: text))) { continue }
            return range
        }
        return nil
    }

    /// The sentence containing `range`, bounded by `.`/`!`/`?`/newline on either side (or
    /// text start/end) — the scope the negation check reads within.
    private static func sentence(around range: Range<String.Index>, in text: String) -> Substring {
        let delimiters: Set<Character> = [".", "!", "?", "\n"]
        var start = range.lowerBound
        while start > text.startIndex {
            let prior = text.index(before: start)
            if delimiters.contains(text[prior]) { break }
            start = prior
        }
        var end = range.upperBound
        while end < text.endIndex {
            if delimiters.contains(text[end]) { break }
            end = text.index(after: end)
        }
        return text[start..<end]
    }

    private static func snippetText(_ text: String, _ range: Range<String.Index>) -> String {
        String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
