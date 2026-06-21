import SwiftUI

struct InlineText: View {
  @Environment(\.inlineImageProvider) private var inlineImageProvider
  @Environment(\.baseURL) private var baseURL
  @Environment(\.imageBaseURL) private var imageBaseURL
  @Environment(\.softBreakMode) private var softBreakMode
  @Environment(\.theme) private var theme

  @State private var inlineImages: [String: Image] = [:]

  private let inlines: [InlineNode]

  init(_ inlines: [InlineNode]) {
    self.inlines = inlines
  }

  var body: some View {
    TextStyleAttributesReader { attributes in
      let styles = InlineTextStyles(
        code: self.theme.code,
        emphasis: self.theme.emphasis,
        strong: self.theme.strong,
        strikethrough: self.theme.strikethrough,
        link: self.theme.link
      )
      if self.hasInlineImages {
        // Inline images can't live in an AttributedString — keep the Text-concatenation
        // path so they still render (copy is best-effort for these rare cases).
        self.inlines.renderText(
          baseURL: self.baseURL,
          textStyles: styles,
          images: self.inlineImages,
          softBreakMode: self.softBreakMode,
          attributes: attributes
        )
      } else {
        // Draw the whole run as ONE Text(AttributedString) so SwiftUI's text selection
        // copies to the pasteboard on ⌘C (a `Text + Text` concatenation only highlights).
        Text(
          self.inlines.renderAttributedString(
            baseURL: self.baseURL,
            textStyles: styles,
            softBreakMode: self.softBreakMode,
            attributes: attributes
          )
        )
      }
    }
    .task(id: self.inlines) {
      self.inlineImages = (try? await self.loadInlineImages()) ?? [:]
    }
  }

  /// True when this inline run contains an image anywhere in its tree — those force the
  /// Text-concatenation path (AttributedString can't embed images).
  private var hasInlineImages: Bool {
    func scan(_ nodes: [InlineNode]) -> Bool {
      for node in nodes {
        if case .image = node { return true }
        if scan(node.children) { return true }
      }
      return false
    }
    return scan(self.inlines)
  }

  private func loadInlineImages() async throws -> [String: Image] {
    let images = Set(self.inlines.compactMap(\.imageData))
    guard !images.isEmpty else { return [:] }

    return try await withThrowingTaskGroup(of: (String, Image).self) { taskGroup in
      for image in images {
        guard let url = URL(string: image.source, relativeTo: self.imageBaseURL) else {
          continue
        }

        taskGroup.addTask {
          (image.source, try await self.inlineImageProvider.image(with: url, label: image.alt))
        }
      }

      var inlineImages: [String: Image] = [:]

      for try await result in taskGroup {
        inlineImages[result.0] = result.1
      }

      return inlineImages
    }
  }
}
