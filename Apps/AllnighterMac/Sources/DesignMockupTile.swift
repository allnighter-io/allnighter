import AppKit
import SwiftUI
import AllnighterCore

/// Design fan-out mockup tile for thread board rows and Factory Floor (MIR-GUI-S04/S05).
struct DesignMockupTile: View {
    let persona: String
    let imagePath: String?
    let absolutePath: String?
    let isChosen: Bool
    let failed: Bool
    let failureReason: String?
    var size: CGSize = CGSize(width: 78, height: 120)
    var onOpen: (() -> Void)?

    @State private var image: NSImage?

    private var resolvedPath: String? {
        if let absolutePath, FileManager.default.fileExists(atPath: absolutePath) { return absolutePath }
        if let imagePath, FileManager.default.fileExists(atPath: imagePath) { return imagePath }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                tileImage
                    .frame(width: size.width, height: size.height - 22)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isChosen ? ALColor.accent : ALColor.borderSubtle, lineWidth: isChosen ? 2 : 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { onOpen?() }

                if isChosen {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("pick").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(ALColor.accentText)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(ALColor.accent, in: Capsule())
                    .padding(6)
                }
            }
            Text(persona)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ALColor.textSecondary)
                .lineLimit(1)
                .frame(width: size.width, alignment: .leading)
        }
        .task(id: resolvedPath) { await loadImage() }
    }

    @ViewBuilder private var tileImage: some View {
        if failed {
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 18))
                    .foregroundStyle(ALColor.textMuted)
                Text(failureReason ?? "Failed")
                    .font(.system(size: 9))
                    .foregroundStyle(ALPalette.red400)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ALColor.subtle)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(ALColor.subtle)
                .overlay {
                    ProgressView().controlSize(.small)
                }
        }
    }

    @MainActor
    private func loadImage() async {
        guard let path = resolvedPath else {
            image = nil
            return
        }
        image = NSImage(contentsOfFile: path)
    }
}

struct DesignBoardTileStrip: View {
    let board: BoardPayload
    let runDirectory: URL?
    var onOpenBoard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(board.options) { option in
                        DesignMockupTile(
                            persona: option.persona,
                            imagePath: option.imagePath.flatMap { runDirectory?.appendingPathComponent($0).path },
                            absolutePath: option.imagePath.flatMap { rel in
                                runDirectory.flatMap { RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }
                            },
                            isChosen: board.chosen?.workerId == option.workerId,
                            failed: !option.hasImage,
                            failureReason: option.failureReason,
                            onOpen: {
                                if let rel = option.imagePath,
                                   let path = runDirectory.flatMap({ RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }) {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                }
                            }
                        )
                    }
                }
            }
            HStack {
                if let chosen = board.chosen {
                    HStack(spacing: 0) {
                        Text("You picked ").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary)
                        Text(chosen.persona).font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
                        Text(".").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onOpenBoard) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.grid.2x2").font(.system(size: 10))
                        Text("Open board").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(ALColor.textPrimary)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(ALColor.raised, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
