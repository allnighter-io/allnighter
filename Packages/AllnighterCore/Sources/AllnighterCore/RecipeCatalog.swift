import Foundation

/// ONB-S02a recipe cards — intent-titled prompt cards for agents (and, later, the
/// Mac "Use from your CLI" surface).
///
/// **Shipped SSOT (v1):** markdown files at
/// `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Recipes/*.md`,
/// copied into the AllnighterCore bundle as subdirectory `Recipes` and loaded
/// via `Bundle.module`. These files ARE the v1 source of truth (Decision 2) —
/// not ContractRegistry `example-recipes` (machine command snippets; different
/// artifact).
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

    /// Directory URL for the bundled Recipes folder (nil if resources missing).
    public static var bundledDirectoryURL: URL? {
        if let url = Bundle.module.resourceURL?.appendingPathComponent(bundleSubdirectory, isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Fallback: derive from any known recipe file.
        return listURLs().first?.deletingLastPathComponent()
    }

    /// All shipped recipes, sorted by id (stable for agents / UI).
    public static func list() -> [Recipe] {
        listURLs().compactMap { url -> Recipe? in
            let id = url.deletingPathExtension().lastPathComponent
            guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let title = parseTitle(from: markdown) ?? id
            return Recipe(id: id, title: title, markdown: markdown)
        }
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
        let urls = Bundle.module.urls(
            forResourcesWithExtension: "md",
            subdirectory: bundleSubdirectory
        ) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
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
