import Foundation

/// Bare `alln` on a human TTY — a teaching card, not the command catalog.
/// `--help` / non-TTY keep `CLIUsage.topLevelHelpText`.
public enum CLIGreeting {
    public static func render(
        version: String = AllnighterVersionIdentity.binaryVersion,
        color: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        var lines: [String] = [
            "",
            CLIPaint.wordmarkLine(version: version, color: color, environment: environment),
            "",
        ]
        lines.append(contentsOf: CLIPaint.lesson(
            command: #"alln run "review this diff" --model model_grok"#,
            benefit: "From this terminal, send it to Grok.",
            color: color,
            environment: environment
        ))
        lines.append(contentsOf: CLIPaint.lesson(
            command: #"alln run "review this diff" --team spec_review"#,
            benefit: "Several models. One answer.",
            color: color,
            environment: environment
        ))
        lines.append(contentsOf: CLIPaint.lesson(
            command: "alln capacity",
            benefit: "Remaining usage on every CLI.",
            color: color,
            environment: environment
        ))
        lines.append(contentsOf: CLIPaint.lesson(
            command: #"alln loop start "fix the failing test""#,
            benefit: "You brief once. A lead runs it. One worker writes.",
            color: color,
            environment: environment
        ))
        let footer = CLIPaint.faint(
            "alln --help · \(SupportHatch.email)",
            color: color,
            environment: environment
        )
        lines.append("  \(footer)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
