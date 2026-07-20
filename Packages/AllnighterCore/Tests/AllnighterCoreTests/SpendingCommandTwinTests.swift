import XCTest
@testable import AllnighterCore

/// AE-S04: every quota-spending command declares a free twin.
final class SpendingCommandTwinTests: XCTestCase {
    func testEverySpendingCommandHasFreeTwin() {
        let registry = ContractRegistry.milestone1
        let m1 = registry.commands.filter { $0.milestone == .m1 }
        var missing: [String] = []
        for spec in m1 where spec.spendsQuota {
            guard let twin = spec.freeTwinCommand, !twin.isEmpty else {
                missing.append(spec.name)
                continue
            }
            XCTAssertTrue(twin.hasPrefix("alln "), "`\(spec.name)` freeTwin must be an alln invocation")
            XCTAssertNotNil(
                ContractRegistry.resolveCommandName(from: twin),
                "`\(spec.name)` freeTwin `\(twin)` must resolve to a registered command"
            )
        }
        XCTAssertTrue(missing.isEmpty, "spending commands missing freeTwinCommand: \(missing)")
    }

    func testRunDeclaresDryRunFlagAndTwin() {
        let spec = ContractRegistry.milestone1.commands.first { $0.name == "run" }
        XCTAssertNotNil(spec)
        XCTAssertTrue(spec?.spendsQuota == true)
        XCTAssertEqual(spec?.freeTwinCommand, "alln run --dry-run")
        XCTAssertTrue(spec?.flags.contains { $0.name == "dry-run" } == true)
    }
}
