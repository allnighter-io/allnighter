import AppKit
import SwiftUI
import AllnighterCore

/// Shared thumbnail chip for composer drafts and thread timeline attachments (MIR-GUI-S01).
struct TimelineAttachmentChip: View {
    enum Style {
        case timeline
        case composer

        var size: CGSize {
            switch self {
            case .timeline: CGSize(width: 46, height: 66)
            case .composer: CGSize(width: 56, height: 56)
            }
        }
    }

    let attachment: ResolvedThreadAttachment
    var thumb: NSImage?
    var style: Style = .timeline
    var onOpen: () -> Void
    var onRemove: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                chipBody
                    .frame(width: style.size.width, height: style.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(attachment.missing ? (attachment.error ?? "Attachment missing") : "Click to view")

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
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 16))
                .foregroundStyle(ALColor.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ALColor.subtle)
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.attachmentId) { attachment in
                    TimelineAttachmentChip(
                        attachment: attachment,
                        thumb: thumb(attachment),
                        onOpen: { onOpen(attachment) }
                    )
                }
            }
        }
    }
}
