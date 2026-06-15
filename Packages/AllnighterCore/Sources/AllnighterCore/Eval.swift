import Foundation

/// One weighted scoring criterion. `weight` may be **negative** to punish
/// confident-wrong / verbosity (the DRACO lesson).
public struct RubricCriterion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var description: String
    public var weight: Double
    public init(id: String, description: String, weight: Double) {
        self.id = id
        self.description = description
        self.weight = weight
    }
}

/// A weighted rubric. `passMark` is the minimum `totalWeighted` to "pass".
public struct Rubric: Codable, Sendable, Equatable {
    public var criteria: [RubricCriterion]
    public var passMark: Double
    public init(criteria: [RubricCriterion], passMark: Double) {
        self.criteria = criteria
        self.passMark = passMark
    }

    /// Builds a rubric from a final spec's structured acceptance criteria
    /// (RB5): each criterion gets unit weight and must mostly pass.
    public static func fromAcceptanceCriteria(_ criteria: [String]) -> Rubric {
        let items = criteria.enumerated().map { RubricCriterion(id: "ac_\($0.offset)", description: $0.element, weight: 1) }
        return Rubric(criteria: items, passMark: Double(items.count) * 0.7)
    }
}

/// One hidden eval case: a prompt + its weighted rubric. Lives outside `Runs/`
/// and is never fed to a panel/reduce (structural contamination guard).
public struct EvalCase: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var prompt: String
    public var rubric: Rubric
    public var notes: String?
    public init(id: String, prompt: String, rubric: Rubric, notes: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.rubric = rubric
        self.notes = notes
    }
}

/// Who grades and how many passes to average.
public struct EvalConfig: Codable, Sendable, Equatable {
    public var planWriterModelId: String
    public var passes: Int
    public init(planWriterModelId: String, passes: Int = 3) {
        self.planWriterModelId = planWriterModelId
        self.passes = max(1, passes)
    }
}

/// The graded result of scoring one artifact against one case's rubric in one
/// mode (solo | combined | separate | review_board).
public struct EvalScore: Codable, Sendable, Equatable {
    public struct CriterionScore: Codable, Sendable, Equatable {
        public var criterionId: String
        /// 0…1 satisfaction of the criterion (multiplied by its weight).
        public var score: Double
        public var note: String?
        public init(criterionId: String, score: Double, note: String? = nil) {
            self.criterionId = criterionId
            self.score = score
            self.note = note
        }
    }
    public var caseId: String
    public var mode: String
    public var totalWeighted: Double
    public var perCriterion: [CriterionScore]
    public var planWriterModelId: String
    public var pass: Bool

    public init(caseId: String, mode: String, totalWeighted: Double, perCriterion: [CriterionScore], planWriterModelId: String, pass: Bool) {
        self.caseId = caseId
        self.mode = mode
        self.totalWeighted = totalWeighted
        self.perCriterion = perCriterion
        self.planWriterModelId = planWriterModelId
        self.pass = pass
    }

    /// Computes the weighted total + pass from per-criterion 0…1 scores.
    public static func compute(caseId: String, mode: String, rubric: Rubric, scores: [CriterionScore], planWriterModelId: String) -> EvalScore {
        let weightByID = Dictionary(rubric.criteria.map { ($0.id, $0.weight) }, uniquingKeysWith: { a, _ in a })
        let total = scores.reduce(0.0) { acc, s in acc + s.score * (weightByID[s.criterionId] ?? 0) }
        return EvalScore(caseId: caseId, mode: mode, totalWeighted: total, perCriterion: scores, planWriterModelId: planWriterModelId, pass: total >= rubric.passMark)
    }
}
