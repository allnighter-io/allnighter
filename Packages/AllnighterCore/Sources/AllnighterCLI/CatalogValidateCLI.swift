import Foundation
import AllnighterCore

enum CatalogValidateCLI {
    static func run(_ args: [String]) {
        let opts = Options(args)
        let summary = ModelCatalogValidator.validate()
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(summary))
        } else if summary.ok {
            print(
                "catalog ok — \(summary.driverCount) driver(s), \(summary.modelCount) model(s), \(summary.overlayModelCount) overlay row(s)"
            )
        } else {
            for problem in summary.problems {
                fputs("catalog validate: \(problem)\n", stderr)
            }
        }
        exit(summary.ok ? 0 : 1)
    }
}
