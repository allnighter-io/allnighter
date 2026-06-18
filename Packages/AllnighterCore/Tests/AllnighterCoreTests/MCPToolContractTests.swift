import XCTest
@testable import AllnighterCore

/// M-A Works Test: every advertised MCP tool is fully specified — argument schema,
/// an explicit return schema, a declared error set whose codes all exist in the
/// catalog, and an idempotency rule. A tool cannot be advertised "name-only".
final class MCPToolContractTests: XCTestCase {
    private let registry = ContractRegistry.milestone1
    private var tools: [ContractRegistry.MCPToolSpec] { registry.mcpTools }

    func testToolsExist() {
        XCTAssertFalse(tools.isEmpty)
    }

    func testNoToolIsNameOnly() {
        for t in tools {
            XCTAssertFalse(t.command.isEmpty, "\(t.name) has no command projection")
            XCTAssertFalse(t.summary.isEmpty, "\(t.name) has no summary")
            // `outputSchema` is non-optional, so it is always an explicit, registered
            // choice (including a deliberate `.none`) — never absent / name-only.
            XCTAssertFalse(t.outputSchema.rawValue.isEmpty, "\(t.name) has no outputSchema")
        }
    }

    func testEveryDeclaredErrorCodeExistsInCatalog() {
        let known = Set(registry.errors.map(\.code))
        for t in tools {
            for code in t.errors {
                XCTAssertTrue(known.contains(code), "\(t.name) declares unknown error code \(code)")
            }
        }
    }

    func testEveryRequiredParamIsDocumented() {
        for t in tools {
            for p in t.params {
                XCTAssertFalse(p.summary.isEmpty, "\(t.name).\(p.name) has no summary")
                XCTAssertFalse(p.type.isEmpty, "\(t.name).\(p.name) has no type")
            }
        }
    }

    func testKeyedToolsDeclareAnIdempotencyKeyParam() {
        for t in tools where t.idempotency == .keyed {
            XCTAssertTrue(t.params.contains { $0.name == "idempotencyKey" },
                          "\(t.name) is keyed but has no idempotencyKey param")
        }
    }

    func testMutatingRunStartersAreNotMarkedIdempotent() {
        // A fresh synchronous run must not claim idempotent (each call spends quota).
        XCTAssertEqual(registry.mcpTools.first { $0.name == "team_ask" }?.idempotency, .notIdempotent)
        XCTAssertEqual(registry.mcpTools.first { $0.name == "team_start" }?.idempotency, .keyed)
    }

    func testIdempotencyDecodeIsTolerantOfMissingField() throws {
        // A pre-M-A artifact without errors/idempotency decodes to safe defaults.
        let json = #"{"name":"x","command":"x","summary":"s","params":[],"outputSchema":"none"}"#
        let spec = try JSONDecoder().decode(ContractRegistry.MCPToolSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.errors, [])
        XCTAssertEqual(spec.idempotency, .notIdempotent)
    }
}
