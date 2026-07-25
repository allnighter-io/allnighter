import Foundation

/// Parsed `lead-call` fenced JSON from a team Lead's markdown (SkillCatalog envelope).
public struct LeadCall: Codable, Equatable, Sendable {
    public struct Recommendation: Codable, Equatable, Sendable {
        public var decision: String?
        public var lean: String?
        public var why: String?
    }

    public struct Flag: Codable, Equatable, Sendable {
        public var flag: String?
        public var whyMightBeRight: String?
        public var round2: Bool?
    }

    public var schemaVersion: Int?
    public var status: String?
    public var call: String?
    public var changed: String?
    public var recommendations: [Recommendation]?
    public var flags: [Flag]?
    public var nextMove: String?
    public var proof: String?
    public var basis: String?
}

public enum LeadCallParser {
    public static func parse(from markdown: String?) -> LeadCall? {
        guard let markdown,
              let json = FencedBlock.extract(from: markdown, fence: "lead-call") else { return nil }
        return try? CoreJSON.decode(LeadCall.self, from: Data(json.utf8))
    }

    /// Remove the machine `lead-call` fence so craft-body rendering stays honest.
    public static func stripFence(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var kept: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !skipping {
                if trimmed == "```lead-call" || trimmed == "``` lead-call" {
                    skipping = true
                    continue
                }
                kept.append(line)
            } else if trimmed == "```" {
                skipping = false
            }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
