import Foundation

/// Parse the ordered target list for a sweep. Duplicates are refused so a
/// second listing cannot stand in for a skipped first attempt.
public enum SweepTargetList {
    public static func parse(
        repeated: [String] = [],
        csv: String? = nil,
        fileLines: [String] = []
    ) throws -> [String] {
        var ids: [String] = []
        ids.append(contentsOf: repeated.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        if let csv {
            ids.append(contentsOf: csv.split(separator: ",", omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })
        }
        for line in fileLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            ids.append(trimmed)
        }
        ids = ids.filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw SweepError.noTargets }
        var seen = Set<String>()
        var dupes: [String] = []
        for id in ids {
            if seen.contains(id) {
                if !dupes.contains(id) { dupes.append(id) }
            } else {
                seen.insert(id)
            }
        }
        if !dupes.isEmpty { throw SweepError.duplicateTargets(dupes) }
        return ids
    }
}
