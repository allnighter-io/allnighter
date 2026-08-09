import Foundation

// MARK: - AI Readiness Report (docs/phases/AI_Readiness.md)

/// The typed output of an AI Readiness team — a repo audit that reports substance
/// (findings, receipts, three fixes, strengths, could-not-determine) with no score,
/// grade, or rating. The Lead Call is the headline; the body is evidence, never
/// judgment math.
public struct AIReadinessReport: Codable, Sendable, Equatable {

    // MARK: - Sub-types

    /// One blind answer to a cold-read question, attributed to a seat.
    public struct BlindAnswer: Codable, Sendable, Equatable {
        public var seatId: String
        public var answer: String
        public init(seatId: String, answer: String) {
            self.seatId = seatId; self.answer = answer
        }
    }

    /// The cold-read receipts panel: one question, blind-per-seat answers, and an
    /// agreement tally as raw counts (never a percentage).
    public struct ColdReadReceipt: Codable, Sendable, Equatable {
        public var question: String
        public var answers: [BlindAnswer]
        public var agreedCount: Int
        public var totalCount: Int
        public var notableMiss: String?
        public init(question: String, answers: [BlindAnswer], agreedCount: Int,
                    totalCount: Int, notableMiss: String? = nil) {
            self.question = question; self.answers = answers
            self.agreedCount = agreedCount; self.totalCount = totalCount
            self.notableMiss = notableMiss
        }
    }

    /// One owner-facing fix — never a score, never a rating.
    public struct Fix: Codable, Sendable, Equatable {
        public var title: String
        public var whyItBites: String
        public var fix: String
        public var doneWhen: String
        public init(title: String, whyItBites: String, fix: String, doneWhen: String) {
            self.title = title; self.whyItBites = whyItBites
            self.fix = fix; self.doneWhen = doneWhen
        }
    }

    /// One finding from a single seat — attributed, bucketed, with evidence and a fix.
    public struct Finding: Codable, Sendable, Equatable {
        public var seatId: String
        public var bucket: String
        public var severity: String
        public var title: String
        public var evidence: String
        public var nugget: String?
        public var whyItBites: String
        public var fix: String
        public var doneWhen: String
        public init(seatId: String, bucket: String, severity: String, title: String,
                    evidence: String, nugget: String? = nil, whyItBites: String,
                    fix: String, doneWhen: String) {
            self.seatId = seatId; self.bucket = bucket; self.severity = severity
            self.title = title; self.evidence = evidence; self.nugget = nugget
            self.whyItBites = whyItBites; self.fix = fix; self.doneWhen = doneWhen
        }
    }

    /// One cited strength — title plus file/command/pattern evidence.
    public struct Strength: Codable, Sendable, Equatable {
        public var title: String
        public var evidence: String
        public init(title: String, evidence: String) {
            self.title = title; self.evidence = evidence
        }
    }

    // MARK: - Top-level fields

    /// The Lead Call headline — one line that names the outcome.
    public var call: String
    /// Cold-read receipts: one or more questions, blind answers, agreement tally.
    public var receipts: [ColdReadReceipt]
    /// Up to three owner-facing fixes (paste-ready stubs or diffs).
    public var threeFixes: [Fix]
    /// Per-seat finding packets grouped into the report body.
    public var findings: [Finding]
    /// What is already right, with citations.
    public var strengths: [Strength]
    /// Questions the team could not answer — rewarded, never hidden.
    public var couldNotDetermine: [String]

    public init(call: String, receipts: [ColdReadReceipt] = [],
                threeFixes: [Fix] = [], findings: [Finding] = [],
                strengths: [Strength] = [], couldNotDetermine: [String] = []) {
        self.call = call; self.receipts = receipts; self.threeFixes = threeFixes
        self.findings = findings; self.strengths = strengths
        self.couldNotDetermine = couldNotDetermine
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case call, receipts, threeFixes, findings, strengths, couldNotDetermine
    }

    /// Tolerant decode: list fields default to empty when omitted; `call` is
    /// required — a block without a call parses to nil and the markdown still
    /// renders.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        call = try c.decode(String.self, forKey: .call)
        receipts = try c.decodeIfPresent([ColdReadReceipt].self, forKey: .receipts) ?? []
        threeFixes = try c.decodeIfPresent([Fix].self, forKey: .threeFixes) ?? []
        findings = try c.decodeIfPresent([Finding].self, forKey: .findings) ?? []
        strengths = try c.decodeIfPresent([Strength].self, forKey: .strengths) ?? []
        couldNotDetermine = try c.decodeIfPresent([String].self, forKey: .couldNotDetermine) ?? []
    }
}

// MARK: - Parser

public enum AIReadinessReportParser {
    /// Best-effort extraction of a typed `AIReadinessReport` from the Lead Writer's
    /// markdown. The writer appends a fenced ```ai-readiness-report … ``` JSON block;
    /// we parse and validate it. Returns `nil` when no valid block is present — the
    /// markdown still renders, so the Floor degrades gracefully.
    public static func parse(fromWriterOutput markdown: String?) -> AIReadinessReport? {
        guard let markdown, let json = fencedBlock(in: markdown, fence: "ai-readiness-report") else { return nil }
        return try? CoreJSON.decode(AIReadinessReport.self, from: Data(json.utf8))
    }

    static func fencedBlock(in text: String, fence: String) -> String? {
        FencedBlock.extract(from: text, fence: fence)
    }
}
