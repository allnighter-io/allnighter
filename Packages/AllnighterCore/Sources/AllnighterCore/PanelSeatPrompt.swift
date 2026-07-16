import Foundation

/// Assembles one panel seat's founder prompt: lens instruction + brief verbatim +
/// target path + finding-schema contract (`docs/phases/Pilot_Panel.md` decision 5/3).
/// Pure string assembly — dispatch is the answer-path's job (per-seat messages on
/// `CatalogRunCoordinator`).
public enum PanelSeatPrompt {
    /// Built-in round-1 brief (decision 6). Sessions may override with `--brief`.
    public static let builtinBrief =
        "Stress-test this target; structured findings only; no material findings is a valid answer."

    /// The finding-schema contract block. Appears exactly once at the end of every
    /// seat prompt so seats end with a fenced JSON findings block.
    public static let schemaContract: String = """
        # Finding schema (required)

        End your report with exactly one fenced JSON block on its own lines:

        ```json
        {
          "findings": [
            {
              "claim": "one concrete claim",
              "severity": "low|medium|high",
              "evidence": "cite file/line or quote",
              "proposedChange": "optional suggested edit"
            }
          ],
          "noMaterialFindings": false,
          "reason": null
        }
        ```

        Rules:
        - Shape only — judge content yourself; Allnighter validates structure.
        - severity is exactly low, medium, or high.
        - "No material findings" is first-class valid: set findings to [], noMaterialFindings to true, and give a reason. Never pad.
        - You are one blind seat. You do not see other seats' reports.
        - The fenced JSON block must appear in the report text itself, as the last thing in it — never in an artifact, a file, an attachment, or merely described in prose. The report text is the only channel Allnighter reads.
        """

    /// Build the founder prompt for one seat. Brief is embedded byte-exact (embedded
    /// fences must survive). Schema contract appears exactly once.
    public static func assemble(
        seat: PanelSeat,
        brief: String,
        targetPath: String
    ) -> String {
        var parts: [String] = []

        parts.append("# Lens: \(seat.lens)")
        if let instruction = seat.lensInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instruction.isEmpty {
            parts.append(instruction)
        }

        parts.append("# Brief\n\n\(brief)")
        parts.append("# Target\n\nRe-read this path fresh (anchor, never payload):\n`\(targetPath)`")
        parts.append(schemaContract)

        return parts.joined(separator: "\n\n")
    }

    /// Convenience: map every seat on a panel to its founder prompt for the answer path's
    /// `workerPrompts` dictionary. Keys are worker ids (must match resolved answer workers).
    public static func workerPrompts(
        seats: [PanelSeat],
        brief: String,
        targetPath: String
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: seats.map { seat in
            (seat.workerId, assemble(seat: seat, brief: brief, targetPath: targetPath))
        })
    }
}
