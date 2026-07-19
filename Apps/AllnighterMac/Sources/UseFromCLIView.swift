import AppKit
import SwiftUI
import AllnighterCore

/// Settings › **Use from your CLI** — intent-titled recipe cards from
/// `RecipeCatalog`, with copy-to-pasteboard and an Application Support mirror
/// for Finder / agent discovery (ONB-S02b).
struct UseFromCLIView: View {
    @State private var recipes: [RecipeCatalog.Recipe] = []
    @State private var selectedId: String?
    @State private var copiedId: String?
    @State private var mirrorPath: String?

    private var selected: RecipeCatalog.Recipe? {
        recipes.first { $0.id == selectedId } ?? recipes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            masterList
                .frame(width: 320)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear { reload() }
    }

    // MARK: - Master

    private var masterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Use from your CLI")
                    .font(.system(size: 20, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Paste-ready prompt cards for agents. Copy one into a CLI session.")
                    .font(.system(size: 12))
                    .foregroundStyle(ALColor.textMuted)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(recipes) { recipe in
                        recipeRow(recipe)
                    }
                    if recipes.isEmpty {
                        Text("No recipes shipped in this build.")
                            .font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }

            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            Text("On disk (refreshed when the app updates)")
                .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                .foregroundStyle(ALColor.textFaint)
            Text(mirrorPath ?? "~/Library/Application Support/Allnighter/Recipes/")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(ALColor.textMuted)
                .lineLimit(2)
                .textSelection(.enabled)
            if mirrorPath != nil {
                Button {
                    RecipeInstallMirror.sync()
                    NSWorkspace.shared.activateFileViewerSelecting([RecipeInstallMirror.directoryURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.alGhost)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func recipeRow(_ recipe: RecipeCatalog.Recipe) -> some View {
        let on = selected?.id == recipe.id
        return HStack(spacing: 6) {
            Button {
                selectedId = recipe.id
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ALColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let blurb = Self.blurb(from: recipe.markdown) {
                        Text(blurb)
                            .font(.system(size: 10.5))
                            .foregroundStyle(ALColor.textFaint)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                copyMarkdown(recipe)
            } label: {
                Text(copiedId == recipe.id ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.alSecondary(small: true))
            .help("Copy full recipe markdown")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(on ? ALColor.active : .clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let recipe = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recipe.title)
                                .font(.system(size: 18, weight: .bold)).tracking(-0.3)
                                .foregroundStyle(ALColor.textPrimary)
                            Text(recipe.id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ALColor.textFaint)
                        }
                        Spacer(minLength: 0)
                        Button {
                            copyMarkdown(recipe)
                        } label: {
                            Label(copiedId == recipe.id ? "Copied" : "Copy markdown", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.alPrimary(small: true))
                    }

                    Text(recipe.markdown)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(ALColor.textSecondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                        .overlay {
                            RoundedRectangle(cornerRadius: ALRadius.lg)
                                .strokeBorder(ALColor.borderSubtle, lineWidth: 1)
                        }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ALColor.base)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 28)).foregroundStyle(ALColor.textFaint)
                Text("No recipe selected.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ALColor.base)
        }
    }

    // MARK: - Actions

    private func reload() {
        recipes = RecipeCatalog.list()
        if selectedId == nil { selectedId = recipes.first?.id }
        if let dest = RecipeInstallMirror.sync() {
            mirrorPath = dest.path
        }
    }

    private func copyMarkdown(_ recipe: RecipeCatalog.Recipe) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recipe.markdown, forType: .string)
        copiedId = recipe.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedId == recipe.id { copiedId = nil }
        }
    }

    /// First prose paragraph after the H1 — short subtitle for the list.
    static func blurb(from markdown: String) -> String? {
        var pastTitle = false
        var lines: [String] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !pastTitle {
                if trimmed.hasPrefix("#") { pastTitle = true }
                continue
            }
            if trimmed.isEmpty {
                if !lines.isEmpty { break }
                continue
            }
            if trimmed.hasPrefix("#") { break }
            if trimmed.hasPrefix("<!--") { continue }
            lines.append(trimmed)
            if lines.joined(separator: " ").count > 120 { break }
        }
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
