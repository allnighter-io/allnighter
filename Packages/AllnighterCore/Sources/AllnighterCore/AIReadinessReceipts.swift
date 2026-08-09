import Foundation

public enum AIReadinessReceipts {

    public static let seedQuestions: [String] = [
        "How do I run the tests here?",
        "How do I run this project locally from a clean clone?",
        "Where is the durable truth about how this product behaves?",
        "If I change behavior, what proves I did not break something?"
    ]

    public struct ColdReadSeatAnswer: Codable, Sendable, Equatable {
        public var question: String
        public var answer: String
        public var couldNotDetermine: Bool
        public init(question: String, answer: String, couldNotDetermine: Bool = false) {
            self.question = question; self.answer = answer; self.couldNotDetermine = couldNotDetermine
        }
    }

    public static let coldReadBrief = """
    ## Cold-read brief (INVIOLABLE — answer each question cold and alone)

    You are asked four small, decidable questions about this repo. Answer each COLD — \
    from what you observe in the repo only, without reading any other seat's answer or \
    the Lead's synthesis.

    Answer every question. If you cannot determine the answer from the repo, answer \
    "could not determine" — this is a distinct, rewarded answer, never a silent miss.

    After your seat summary and finding packet, emit a fenced ```ai-readiness-cold-read JSON block:
    {
      "answers": [
        {"question":"How do I run the tests here?","answer":"…","couldNotDetermine":false},
        {"question":"How do I run this project locally from a clean clone?","answer":"…","couldNotDetermine":false},
        {"question":"Where is the durable truth about how this product behaves?","answer":"…","couldNotDetermine":false},
        {"question":"If I change behavior, what proves I did not break something?","answer":"…","couldNotDetermine":false}
      ]
    }

    Ban vendor ranking / Claude-vs-Codex language. Indict the repo, never the models.
    """

    public static func parseColdRead(fromSeatOutput text: String?) -> [ColdReadSeatAnswer]? {
        guard let text, let json = FencedBlock.extract(from: text, fence: "ai-readiness-cold-read") else { return nil }
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answersArray = dict["answers"] as? [[String: Any]] else { return nil }
        return answersArray.compactMap { item in
            guard let question = item["question"] as? String,
                  let answer = item["answer"] as? String else { return nil }
            let cnd = item["couldNotDetermine"] as? Bool ?? false
            return ColdReadSeatAnswer(question: question, answer: answer, couldNotDetermine: cnd)
        }
    }

    public static func tally(question: String, answers: [AIReadinessReport.BlindAnswer])
        -> AIReadinessReport.ColdReadReceipt {
        let totalCount = answers.count
        let normalPairs: [(String, String)] = answers.compactMap { ba in
            isCouldNotDetermine(ba.answer) ? nil : (ba.seatId, normalize(ba.answer))
        }
        var clusterSizes: [String: Int] = [:]
        for (_, norm) in normalPairs {
            clusterSizes[norm, default: 0] += 1
        }
        let agreedCount = clusterSizes.values.max() ?? 0
        let hasCND = answers.contains { isCouldNotDetermine($0.answer) }
        let uniqueNormal = Set(normalPairs.map(\.1))
        let hasDisagreement = uniqueNormal.count > 1
        let notableMiss = buildNotableMiss(hasCND: hasCND, hasDisagreement: hasDisagreement)
        return AIReadinessReport.ColdReadReceipt(
            question: question,
            answers: answers,
            agreedCount: agreedCount,
            totalCount: totalCount,
            notableMiss: notableMiss
        )
    }

    /// Convenience for tests and callers that only have raw answer strings.
    public static func tally(question: String, answers: [String]) -> AIReadinessReport.ColdReadReceipt {
        let blind = answers.enumerated().map { idx, answer in
            AIReadinessReport.BlindAnswer(seatId: "seat_\(idx)", answer: answer)
        }
        return tally(question: question, answers: blind)
    }

    private static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.lowercased()
    }

    private static func isCouldNotDetermine(_ s: String) -> Bool {
        let n = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "could not determine" || n.isEmpty
    }

    private static func buildNotableMiss(hasCND: Bool, hasDisagreement: Bool) -> String? {
        if hasCND, hasDisagreement {
            return "Some seats could not determine; remaining seats disagreed"
        }
        if hasCND {
            return "Some seats could not determine"
        }
        if hasDisagreement {
            return "Seats disagreed"
        }
        return nil
    }
}
