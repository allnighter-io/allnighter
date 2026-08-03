import SwiftUI
import AppKit

/// One composer attachment. An image is a Cursor-style thumbnail tile — larger preview, no
/// label, click to view, and a remove (×) button that appears top-right on hover. A captured
/// `.txt` keeps a compact doc chip (it has no thumbnail).
struct ComposerAttachmentTile: View {
    let attachment: ComposeAttachment
    let thumb: NSImage?
    let onRemove: () -> Void
    let onOpen: () -> Void
    @State private var hovering = false

    private let side: CGFloat = 56

    var body: some View {
        Group {
            if attachment.kind == .image {
                imageTile
            } else {
                textChip
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private var imageTile: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(ALColor.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Click to view")

            if hovering { removeButton.padding(3) }
        }
    }

    private var textChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            Text(attachment.displayName)
                .font(ALFont.monoSm).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(ALColor.textFaint)
                }
                .buttonStyle(.plain).help("Remove")
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    // White × on a dark disc so it reads on any image; top-right on hover.
    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Remove")
        .transition(.opacity)
    }
}
