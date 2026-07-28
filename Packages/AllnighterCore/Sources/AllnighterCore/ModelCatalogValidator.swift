import Foundation
import AgentOSCLI

/// MCAT-S07: fail-closed validation of bundled AgentOS catalog + Allnighter overlay.
public enum ModelCatalogValidator {
    public struct Summary: Codable, Sendable, Equatable {
        public var ok: Bool
        public var driverCount: Int
        public var modelCount: Int
        public var overlayModelCount: Int
        public var problems: [String]

        public init(ok: Bool, driverCount: Int, modelCount: Int, overlayModelCount: Int, problems: [String]) {
            self.ok = ok
            self.driverCount = driverCount
            self.modelCount = modelCount
            self.overlayModelCount = overlayModelCount
            self.problems = problems
        }
    }

    public static func validate() -> Summary {
        var problems: [String] = []
        var driverCount = 0
        var modelCount = 0
        var overlayModelCount = 0

        do {
            let catalog = try CatalogLoader.bundled()
            driverCount = catalog.drivers.count
            modelCount = catalog.models.count

            let overlay = try CatalogOverlayLoader.bundled()
            overlayModelCount = overlay.models.count

            for diagnostic in CatalogMerge.unknownOverlayDiagnostics(overlay: overlay, catalog: catalog) {
                problems.append(diagnostic.message)
            }

            for record in catalog.models {
                do {
                    _ = try catalog.materializeModel(record, enabled: false)
                } catch {
                    problems.append("model \(record.id): \(error)")
                }
            }

            do {
                _ = try CatalogMerge.builtInDefinitions(catalog: catalog, overlay: overlay)
            } catch {
                problems.append("merge built-ins: \(error)")
            }
        } catch {
            problems.append(String(describing: error))
        }

        return Summary(
            ok: problems.isEmpty,
            driverCount: driverCount,
            modelCount: modelCount,
            overlayModelCount: overlayModelCount,
            problems: problems
        )
    }
}
