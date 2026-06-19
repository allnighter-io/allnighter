import SwiftUI
import AppKit

// MARK: - WorkerGlyph
//
// A worker's brand glyph: a tinted square. Brand SVGs (Simple Icons) get
// bundled later; for now SF Symbol fallbacks per handoff §Iconography.

struct WorkerGlyph: View {
    var driverId: String? = nil
    var systemImage: String = "cpu"
    var tint: Color = ALColor.textSecondary
    var size: CGFloat = 30

    var body: some View {
        if let driverId, DriverBrandAsset.imageName(for: driverId) != nil {
            DriverBrandGlyph(driverId: driverId, boxSize: size, cornerRadius: ALRadius.md)
        } else {
            RoundedRectangle(cornerRadius: ALRadius.md)
                .fill(ALColor.active)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(tint)
                }
        }
    }
}

