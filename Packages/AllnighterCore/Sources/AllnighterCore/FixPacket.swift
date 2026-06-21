import Foundation

/// The typed hand-off from a Bug Hunt answer run to a fix attempt (Try_Fix_Auto_Implement).
/// Built for the ELIMINATION LOOP: a ranked hypothesis ladder + the experiments + the proof
/// method, not a single confident patch. `confidenceOrdering` only orders the ladder — it is
/// NEVER a gate (what blocks is danger, not doubt). Lifted from the Bug Packet writer's
/// fenced ```fix-packet block; decoding is LENIENT (missing fields default) so partial model
/// output still parses — the gate, not the decoder, enforces what's required to execute.
public struct FixPacket: Codable, Sendable, Equatable {
    public enum ProofMethod: String, Codable, Sendable, CaseIterable {
        case command, guiFixture, userObservation
    }
    public enum Confidence: String, Codable, Sendable, CaseIterable {
        case low, medium, high
    }

    /// One rung of the ranked ladder.
    public struct Hypothesis: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var cause: String
        /// The cheapest experiment that confirms or refutes this cause.
        public var experiment: String?
        /// The smallest change to try if this is the cause.
        public var fix: String
        /// Apply only here — no opportunistic refactor.
        public var fixBoundary: String

        public init(id: String, cause: String, experiment: String? = nil, fix: String, fixBoundary: String) {
            self.id = id; self.cause = cause; self.experiment = experiment
            self.fix = fix; self.fixBoundary = fixBoundary
        }
    }

    public var schemaVersion: Int
    public var sourceRunId: String?
    /// The boundary the bug crosses (e.g. AppKit↔SwiftUI), when one — a one-side proof is a trap.
    public var seam: String?
    public var symptom: String
    public var repro: String?
    public var bugFingerprint: String?
    public var truthOwner: String
    public var lieProneLayer: String?
    /// Ranked, most-likely first. The loop tries the top SURVIVING one.
    public var hypotheses: [Hypothesis]
    /// Failure points already eliminated — the loop's memory; carried into each next round.
    public var ruledOut: [String]
    public var proofMethod: ProofMethod
    public var proofCommand: String?
    public var guiProofFixture: String?
    public var requiresLayoutWatcher: Bool
    /// True when the honest end-to-end proof can't be written in this codebase → isolate.
    public var harnessNeeded: Bool
    public var harnessSketch: String?
    public var confidenceOrdering: Confidence
    public var expectedRounds: Int?
    public var tier: String?
    /// Hard stops about HARM (credentials, deletion, deploy…) — block regardless of confidence.
    public var dangerFlags: [String]

    public init(
        schemaVersion: Int = 1, sourceRunId: String? = nil, seam: String? = nil,
        symptom: String = "", repro: String? = nil, bugFingerprint: String? = nil,
        truthOwner: String = "", lieProneLayer: String? = nil,
        hypotheses: [Hypothesis] = [], ruledOut: [String] = [],
        proofMethod: ProofMethod = .userObservation, proofCommand: String? = nil,
        guiProofFixture: String? = nil, requiresLayoutWatcher: Bool = false,
        harnessNeeded: Bool = false, harnessSketch: String? = nil,
        confidenceOrdering: Confidence = .medium, expectedRounds: Int? = nil,
        tier: String? = nil, dangerFlags: [String] = []
    ) {
        self.schemaVersion = schemaVersion; self.sourceRunId = sourceRunId; self.seam = seam
        self.symptom = symptom; self.repro = repro; self.bugFingerprint = bugFingerprint
        self.truthOwner = truthOwner; self.lieProneLayer = lieProneLayer
        self.hypotheses = hypotheses; self.ruledOut = ruledOut
        self.proofMethod = proofMethod; self.proofCommand = proofCommand
        self.guiProofFixture = guiProofFixture; self.requiresLayoutWatcher = requiresLayoutWatcher
        self.harnessNeeded = harnessNeeded; self.harnessSketch = harnessSketch
        self.confidenceOrdering = confidenceOrdering; self.expectedRounds = expectedRounds
        self.tier = tier; self.dangerFlags = dangerFlags
    }

    // Lenient decode: any missing field defaults so a partial model block still parses.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sourceRunId = try c.decodeIfPresent(String.self, forKey: .sourceRunId)
        seam = try c.decodeIfPresent(String.self, forKey: .seam)
        symptom = try c.decodeIfPresent(String.self, forKey: .symptom) ?? ""
        repro = try c.decodeIfPresent(String.self, forKey: .repro)
        bugFingerprint = try c.decodeIfPresent(String.self, forKey: .bugFingerprint)
        truthOwner = try c.decodeIfPresent(String.self, forKey: .truthOwner) ?? ""
        lieProneLayer = try c.decodeIfPresent(String.self, forKey: .lieProneLayer)
        hypotheses = try c.decodeIfPresent([Hypothesis].self, forKey: .hypotheses) ?? []
        ruledOut = try c.decodeIfPresent([String].self, forKey: .ruledOut) ?? []
        proofMethod = try c.decodeIfPresent(ProofMethod.self, forKey: .proofMethod) ?? .userObservation
        proofCommand = try c.decodeIfPresent(String.self, forKey: .proofCommand)
        guiProofFixture = try c.decodeIfPresent(String.self, forKey: .guiProofFixture)
        requiresLayoutWatcher = try c.decodeIfPresent(Bool.self, forKey: .requiresLayoutWatcher) ?? false
        harnessNeeded = try c.decodeIfPresent(Bool.self, forKey: .harnessNeeded) ?? false
        harnessSketch = try c.decodeIfPresent(String.self, forKey: .harnessSketch)
        confidenceOrdering = try c.decodeIfPresent(Confidence.self, forKey: .confidenceOrdering) ?? .medium
        expectedRounds = try c.decodeIfPresent(Int.self, forKey: .expectedRounds)
        tier = try c.decodeIfPresent(String.self, forKey: .tier)
        dangerFlags = try c.decodeIfPresent([String].self, forKey: .dangerFlags) ?? []
    }
}

/// Lifts a `FixPacket` from the Bug Packet writer's fenced ```fix-packet block. Returns nil
/// when no valid block is present (the markdown still renders).
public enum FixPacketParser {
    public static func parse(fromWriterOutput markdown: String?) -> FixPacket? {
        guard let markdown,
              let json = FencedBlock.extract(from: markdown, fence: "fix-packet") else { return nil }
        return try? CoreJSON.decode(FixPacket.self, from: Data(json.utf8))
    }
}
