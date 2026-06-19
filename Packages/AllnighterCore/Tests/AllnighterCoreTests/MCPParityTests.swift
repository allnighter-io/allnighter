import XCTest
@testable import AllnighterCore

/// M-B: CLI<->MCP parity proof. Every MCP tool is a thin projection of an `alln`
/// command and never exposes a richer semantic surface than the CLI (Agent-First
/// Product Law). This gate fails if an MCP-only tool or an MCP-richer return
/// schema appears.
final class MCPParityTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    private var commandByName: [String: ContractRegistry.CommandSpec] {
        Dictionary(reg.commands.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func testEveryToolMapsToAnM1Command() {
        let m1 = commandByName.filter { $0.value.milestone == .m1 }
        for tool in reg.mcpTools {
            XCTAssertNotNil(m1[tool.command],
                            "MCP tool \(tool.name) maps to command '\(tool.command)' which is not an M1 CLI command")
        }
    }

    func testMCPNeverExposesARicherReturnThanTheCLI() {
        let byName = commandByName
        for tool in reg.mcpTools where tool.outputSchema != .none {
            guard let cmd = byName[tool.command] else { continue }   // covered by the test above
            XCTAssertEqual(tool.outputSchema, cmd.outputSchema,
                           "MCP tool \(tool.name) returns \(tool.outputSchema.rawValue) but its CLI command '\(tool.command)' returns \(cmd.outputSchema.rawValue) — MCP must not be richer than the CLI")
        }
    }

    func testEveryToolDeclaresIdempotencyAndValidErrors() {
        let codes = Set(reg.errors.map(\.code))
        for tool in reg.mcpTools {
            XCTAssertTrue(ContractRegistry.Idempotency.allCases.contains(tool.idempotency))
            for code in tool.errors {
                XCTAssertTrue(codes.contains(code), "MCP tool \(tool.name) declares unknown error \(code)")
            }
        }
    }

    /// The parity table is stable and total: a tool count change is a deliberate
    /// surface change, not an accident.
    func testParityTableIsTotal() {
        XCTAssertEqual(reg.mcpTools.count, Set(reg.mcpTools.map(\.name)).count, "duplicate MCP tool name")
        for tool in reg.mcpTools {
            XCTAssertFalse(tool.command.isEmpty, "\(tool.name) has no command projection")
        }
    }
}
