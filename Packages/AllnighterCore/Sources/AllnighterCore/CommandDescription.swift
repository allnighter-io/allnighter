import Foundation

/// AE-S15 description authoring: every M1 command surfaces a trigger situation,
/// one worked example, and one anti-example. Structured `CommandSpec` fields win;
/// otherwise values are derived so the gate never depends on hand-maintaining 100+.
public enum CommandDescription {
    public static func trigger(for spec: ContractRegistry.CommandSpec) -> String {
        if let t = spec.trigger?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return spec.summary
    }

    public static func example(
        for spec: ContractRegistry.CommandSpec,
        recipes: [String: ContractRegistry.ExampleRecipe] = [:]
    ) -> String {
        if let e = spec.example?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return e
        }
        for id in spec.exampleIds {
            if let recipe = recipes[id], !recipe.command.isEmpty {
                return recipe.command
            }
        }
        return derivedExample(for: spec)
    }

    public static func antiExample(for spec: ContractRegistry.CommandSpec) -> String {
        if let a = spec.antiExample?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            return a
        }
        return derivedAntiExample(for: spec)
    }

    // MARK: - Derivation

    private static func derivedExample(for spec: ContractRegistry.CommandSpec) -> String {
        var parts = ["alln", spec.name]
        for arg in spec.args where arg.required {
            parts.append("<\(arg.name)>")
        }
        if spec.flags.contains(where: { $0.name == "json" }) {
            parts.append("--json")
        }
        return parts.joined(separator: " ")
    }

    private static func derivedAntiExample(for spec: ContractRegistry.CommandSpec) -> String {
        let name = spec.name
        if name == "run" {
            return "Do NOT use this to explore shapes — prefer `alln run --dry-run` or `alln menu --json` first; this spends quota."
        }
        if name == "models" || name == "teams" || name == "skills" {
            return "Do NOT use this when you need the selection-grade catalog — run `alln menu --json` first."
        }
        if name.hasPrefix("help ") || name == "docs" || name == "menu" || name.hasPrefix("menu ") {
            return "Do NOT use this when you need live readiness for a spend — use `alln run --dry-run` or `alln doctor --json`."
        }
        if name == "doctor" {
            return "Do NOT use this to pick a model or team by name — use `alln menu --json`."
        }
        if name.hasPrefix("pending ") {
            return "Do NOT use this when the user wants work started now — use `alln run` (add `--detach` for async) after `--dry-run`."
        }
        return "Do NOT use this when `alln menu --json` or `alln help search \"<intent>\" --json` already answers the question."
    }
}
