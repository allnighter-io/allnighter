import Foundation

/// Built-in design personas (Lane 2). A persona is a short, editable style
/// direction carried on a seat's `stance` and appended to the image-gen prompt —
/// the source of range. Structural enough that engines actually diverge; unknown
/// ids resolve to a neutral direction (graceful). See `docs/mvp/Design0`.
public enum DesignPersonaLibrary {
    /// The default design panel: spread across distinct taste directions + a
    /// genre-breaking wildcard. `on_brand` swaps in when a brand is bound.
    public static let defaultPanelIDs = ["minimal", "bold", "editorial", "on_brand"]
    public static let builtInIDs = ["minimal", "bold", "editorial", "on_brand"]

    public static func direction(for personaId: String) -> String {
        switch personaId {
        case "minimal":
            return "Restraint, generous whitespace, type-led hierarchy; strip every non-essential element."
        case "bold":
            return "High contrast, oversized type, opinionated color; the primary action dominates."
        case "editorial":
            return "Break the generic SaaS look — magazine/editorial or information-dense — while staying recognizably the same screen and usable."
        case "on_brand":
            return "Match the product's existing look: palette, type scale, and spacing from the attached screen. Range in layout, not in brand."
        default:
            return "A clean, considered redesign with clear hierarchy."
        }
    }

    public static func displayName(for personaId: String) -> String {
        switch personaId {
        case "minimal": return "Minimal"
        case "bold": return "Bold"
        case "editorial": return "Editorial"
        case "on_brand": return "On-brand"
        default: return personaId.capitalized
        }
    }
}
