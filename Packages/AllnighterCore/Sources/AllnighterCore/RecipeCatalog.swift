import Foundation
import AgentOSCLI

/// ONB-S02a recipe cards — intent-titled prompt cards for agents (and, later, the
/// Mac "Use from your CLI" surface).
///
/// **Shipped SSOT (v1):** markdown files at
/// `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Recipes/*.md`,
/// copied into the AllnighterCore sidecar as subdirectory `Recipes` and loaded
/// as files next to the executable. These files ARE the v1 source of truth
/// (Decision 2) — not ContractRegistry `example-recipes` (machine command
/// snippets; different artifact).
///
/// **Discovery (no Mac GUI):** `alln bootstrap --json` lists `{ id, title }` in
/// `recipes`; full markdown via `alln help get recipes --format md` (or JSON
/// sections). S02b mirrors this folder into Application Support via the Mac
/// app's `RecipeInstallMirror`; call `RecipeCatalog.list()` / `markdown(id:)` /
/// `bundledDirectoryURL` from the app for the read SSOT.
public enum RecipeCatalog {
    public struct Recipe: Identifiable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var markdown: String

        public init(id: String, title: String, markdown: String) {
            self.id = id
            self.title = title
            self.markdown = markdown
        }
    }

    /// Bundle subdirectory that holds the shipped `.md` cards.
    public static let bundleSubdirectory = "Recipes"

    /// Placeholder a source card writes where the teaching block belongs.
    ///
    /// The block itself is never stored in a `.md` file. It used to be
    /// hand-copied into all seven, kept honest only by a test that compared the
    /// copies to `TeachingSnippet` — seven duplicates with a linter, not a
    /// source of truth. Now `compose` substitutes the live block at load, so a
    /// card physically cannot ship a stale one and editing `TeachingSnippet` is
    /// a one-line change instead of eight.
    public static let teachingPlaceholder = "<!-- ALLNIGHTER:TEACHING:INSERT -->"

    /// Directory URL for the bundled Recipes folder (nil if resources missing).
    public static var bundledDirectoryURL: URL? {
        if let url = ExecutableResource.directory(
            bundleName: ExecutableResource.allnighterCoreBundleName,
            subdirectory: bundleSubdirectory
        ) {
            return url
        }
        return listURLs().first?.deletingLastPathComponent()
    }

    /// All shipped recipes, sorted by id (stable for agents / UI).
    ///
    /// Markdown is **composed**, not read verbatim: the teaching placeholder is
    /// replaced with the live `TeachingSnippet` block. Every consumer — CLI
    /// help, bootstrap, the Mac app, the Application Support mirror — reads
    /// through here, so they all see the same current block.
    public static func list() -> [Recipe] {
        listURLs().compactMap { url -> Recipe? in
            let id = url.deletingPathExtension().lastPathComponent
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let markdown = compose(source)
            let title = parseTitle(from: markdown) ?? id
            return Recipe(id: id, title: title, markdown: markdown)
        }
    }

    /// Substitute the live teaching block for the placeholder. A card with no
    /// placeholder is returned unchanged — composition never invents a block.
    public static func compose(_ source: String) -> String {
        guard source.contains(teachingPlaceholder) else { return source }
        return source.replacingOccurrences(
            of: teachingPlaceholder,
            with: TeachingSnippet.wrap()
        )
    }

    /// Bounded listing for bootstrap JSON (id + title only).
    public static func summaries() -> [(id: String, title: String)] {
        list().map { ($0.id, $0.title) }
    }

    public static func recipe(id: String) -> Recipe? {
        list().first { $0.id == id }
    }

    public static func markdown(id: String) -> String? {
        recipe(id: id)?.markdown
    }

    // MARK: - Internals

    private static func listURLs() -> [URL] {
        ExecutableResource.fileURLs(
            bundleName: ExecutableResource.allnighterCoreBundleName,
            subdirectory: bundleSubdirectory,
            ext: "md"
        )
    }

    /// First ATX H1 (`# Title`) wins.
    private static func parseTitle(from markdown: String) -> String? {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            var rest = trimmed.drop(while: { $0 == "#" })
            if rest.first?.isWhitespace == true { rest = rest.drop(while: { $0.isWhitespace }) }
            let title = String(rest).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        return nil
    }
}
