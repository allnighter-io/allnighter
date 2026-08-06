import Foundation
import AllnighterCore
import AllnighterEngine

/// ONB-S02b: mirrors bundled recipe `.md` cards into Application Support so
/// Finder and agents can open them on disk. Core `RecipeCatalog` stays the read
/// SSOT; this folder is overwrite-refreshed from the bundle (shipped content,
/// not user data).
///
/// Writes `RecipeCatalog`'s **composed** markdown rather than copying the bundle
/// bytes. The source cards carry a teaching placeholder, so a byte copy would
/// put an unsubstituted marker on disk — exactly where agents read it.
enum RecipeInstallMirror {
    /// Canonical install path: `~/Library/Application Support/Allnighter/Recipes/`.
    static var directoryURL: URL { AllnighterPaths.recipes }

    /// Overwrite-sync every bundled recipe into Application Support.
    /// Removes retired `.md` files that are no longer in the bundle.
    /// - Parameter destination: override for tests; defaults to `directoryURL`.
    /// - Returns: destination directory on success, or `nil` if the bundle is
    ///   missing / unlistable / has zero recipe files / any copy fails.
    @discardableResult
    static func sync(
        to destination: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard RecipeCatalog.bundledDirectoryURL != nil else { return nil }
        let dest = destination ?? directoryURL
        do {
            try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
            let recipes = RecipeCatalog.list()
            guard !recipes.isEmpty else { return nil }

            let shippedNames = Set(recipes.map { "\($0.id).md" })
            for recipe in recipes {
                try writeFile(
                    markdown: recipe.markdown,
                    named: "\(recipe.id).md",
                    into: dest,
                    fileManager: fileManager
                )
            }

            // Drop retired cards so the mirror matches the shipped catalog.
            let existing = try fileManager.contentsOfDirectory(
                at: dest,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "md" }
            for stale in existing where !shippedNames.contains(stale.lastPathComponent) {
                try fileManager.removeItem(at: stale)
            }
            return dest
        } catch {
            return nil
        }
    }

    /// Write via a sibling temp file, then replace — never delete the live
    /// target before the new bytes are safely on disk.
    private static func writeFile(
        markdown: String,
        named name: String,
        into destDir: URL,
        fileManager: FileManager
    ) throws {
        let target = destDir.appendingPathComponent(name)
        let temp = destDir.appendingPathComponent(".\(name).tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temp) }
        try markdown.write(to: temp, atomically: false, encoding: .utf8)
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: target)
        }
    }
}
