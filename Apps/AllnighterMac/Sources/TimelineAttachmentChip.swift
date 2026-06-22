import AppKit
import SwiftUI
import AllnighterCore

/// Shared thumbnail chip for composer drafts and thread timeline attachments (MIR-GUI-S01).
struct TimelineAttachmentChip: View {
    enum Style {
        /// Composer drafts stay a fixed square tile.
        case composer
        /// Timeline previews size to the image's real aspect ratio, up to a max long edge,
        /// so a square render stays square and a wide screenshot stays wide (no crop).
        case timeline

        var maxLongEdge: CGFloat {
            switch self {
            case .composer: 56
            case .timeline: 120
            }
        }
        var minShortEdge: CGFloat {
            switch self {
            case .composer: 56
            case .timeline: 60
            }
        }
    }

    let attachment: ResolvedThreadAttachment
    var thumb: NSImage?
    var style: Style = .timeline
    var onOpen: () -> Void
    var onReveal: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRemove: (() -> Void)?

    @State private var hovering = false

    /// Display size from the stored image dimensions (falls back to the loaded thumb, then a
    /// gentle portrait box), fit inside the style's max long edge with no crop.
    private var displaySize: CGSize {
        if style == .composer { return CGSize(width: 56, height: 56) }
        let dims: CGSize
        if let w = attachment.storedWidth, let h = attachment.storedHeight, w > 0, h > 0 {
            dims = CGSize(width: w, height: h)
        } else if let thumb, thumb.size.width > 0, thumb.size.height > 0 {
            dims = thumb.size
        } else {
            return CGSize(width: 84, height: 112)
        }
        let maxEdge = style.maxLongEdge
        let minShort = style.minShortEdge
        let ratio = dims.width / dims.height
        if ratio >= 1 {
            return CGSize(width: maxEdge, height: max(minShort, (maxEdge / ratio).rounded()))
        }
        return CGSize(width: max(minShort, (maxEdge * ratio).rounded()), height: maxEdge)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                chipBody
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(attachment.missing ? (attachment.error ?? "Attachment missing") : "Click to view")
            .contextMenu { contextMenuItems }

            if hovering, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(ALColor.textPrimary, ALColor.raised)
                }
                .buttonStyle(.plain)
                .padding(2)
            }
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var chipBody: some View {
        if attachment.missing {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(ALPalette.red400)
                Text("Missing")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ALPalette.red400)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ALColor.subtle)
        } else if let thumb {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 16))
                .foregroundStyle(ALColor.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ALColor.subtle)
        }
    }

    /// Right-click actions on the preview — the founder's set: preview it, view it in
    /// Finder (to move/copy the file), or copy the image bytes. No bytes → no actions.
    @ViewBuilder private var contextMenuItems: some View {
        if !attachment.missing {
            Button("Open", action: onOpen)
            if let onReveal { Button("Reveal in Finder", action: onReveal) }
            if let onCopy { Button("Copy Image", action: onCopy) }
        }
    }

    private var borderColor: Color {
        attachment.missing ? ALPalette.red400.opacity(0.5) : ALColor.borderSubtle
    }
}

/// Horizontal row of timeline attachment chips sorted by sequence.
struct TimelineAttachmentRow: View {
    let attachments: [ResolvedThreadAttachment]
    var thumb: (ResolvedThreadAttachment) -> NSImage?
    var onOpen: (ResolvedThreadAttachment) -> Void
    var onReveal: ((ResolvedThreadAttachment) -> Void)?
    var onCopy: ((ResolvedThreadAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(attachments, id: \.attachmentId) { attachment in
                    TimelineAttachmentChip(
                        attachment: attachment,
                        thumb: thumb(attachment),
                        onOpen: { onOpen(attachment) },
                        onReveal: onReveal.map { reveal in { reveal(attachment) } },
                        onCopy: onCopy.map { copy in { copy(attachment) } }
                    )
                }
            }
        }
    }
}
