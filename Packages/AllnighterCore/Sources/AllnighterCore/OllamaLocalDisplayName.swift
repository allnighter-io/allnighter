import Foundation

/// Readable LOCAL RUNTIME row title derived from an Ollama tag.
/// The raw tag stays on the secondary line (`ollama/<tag>`). A human `--name`
/// is not required and is not the source of truth on this surface.
public enum OllamaLocalDisplayName {
    public static func from(tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let family = formatFamily(String(parts[0]))
        guard parts.count > 1, let size = extractSize(String(parts[1])) else {
            return family
        }
        return "\(family) \(size)"
    }

    private static func formatFamily(_ raw: String) -> String {
        let tokens = raw.split(separator: "-", omittingEmptySubsequences: true)
            .map { formatToken(String($0)) }
        var merged: [String] = []
        var index = 0
        while index < tokens.count {
            if index + 1 < tokens.count,
               shortAcronyms.contains(tokens[index].lowercased()),
               shortAcronyms.contains(tokens[index + 1].lowercased()) {
                merged.append(tokens[index] + "-" + tokens[index + 1])
                index += 2
            } else {
                merged.append(tokens[index])
                index += 1
            }
        }
        return merged.joined(separator: " ")
    }

    private static func formatToken(_ token: String) -> String {
        let lower = token.lowercased()
        if shortAcronyms.contains(lower) {
            return lower.uppercased()
        }
        guard let first = token.first else { return token }
        return first.uppercased() + token.dropFirst()
    }

    /// Tokens that read as acronyms, not title-case words.
    private static let shortAcronyms: Set<String> = [
        "gpt", "oss", "llm", "vl", "moe",
    ]

    /// First `Nb` / `N.Nb` size in the variant side (`27b-mlx`, `1.5b`, `20b`).
    private static func extractSize(_ variant: String) -> String? {
        let scalars = Array(variant.lowercased())
        var i = 0
        while i < scalars.count {
            if scalars[i].isNumber {
                var j = i
                var sawDot = false
                while j < scalars.count {
                    if scalars[j].isNumber {
                        j += 1
                    } else if scalars[j] == ".", !sawDot, j + 1 < scalars.count, scalars[j + 1].isNumber {
                        sawDot = true
                        j += 1
                    } else {
                        break
                    }
                }
                if j < scalars.count, scalars[j] == "b" {
                    return String(scalars[i..<j]).uppercased() + "B"
                }
                i = j
            } else {
                i += 1
            }
        }
        return nil
    }
}
