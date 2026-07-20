import XCTest
@testable import AllnighterCore

/// Typed command refs round-trip across menu and docs; bare dotted ids stay
/// near-misses with structured suggestions (no alias).
final class TypedRefRoundTripTests: XCTestCase {

    func testDocsResolvesTypedCommandRef() {
        switch TypedRef.resolveDocsTopic("command:teams.duplicate") {
        case .commands(let cmds):
            XCTAssertEqual(cmds.map(\.name), ["teams duplicate"])
        default:
            XCTFail("expected docs to resolve command:teams.duplicate")
        }
    }

    func testDocsResolvesSpacedHumanCommandName() {
        switch TypedRef.resolveDocsTopic("teams duplicate") {
        case .commands(let cmds):
            XCTAssertEqual(cmds.map(\.name), ["teams duplicate"])
        default:
            XCTFail("expected docs to resolve spaced command name")
        }
    }

    func testBareDottedIdIsNearMissNotAlias() {
        switch TypedRef.resolveDocsTopic("teams.duplicate") {
        case .nearMiss(_, let suggestions):
            XCTAssertEqual(suggestions, ["command:teams.duplicate", "teams duplicate"])
        case .commands:
            XCTFail("bare teams.duplicate must not alias to a command")
        default:
            XCTFail("expected near-miss suggestions for teams.duplicate")
        }
        XCTAssertTrue(TypedRef.isBareDottedCommandNearMiss("teams.duplicate"))
        XCTAssertFalse(TypedRef.isBareDottedCommandNearMiss("command:teams.duplicate"))
        XCTAssertFalse(TypedRef.isBareDottedCommandNearMiss("teams duplicate"))
    }

    func testMenuShowStillResolvesTypedCommandRef() throws {
        let detail = try MenuCatalog.show(ref: "command:teams.duplicate")
        XCTAssertEqual(detail.kind, "command")
        XCTAssertEqual(detail.command?.name, "teams duplicate")
        XCTAssertEqual(detail.command?.ref, "command:teams.duplicate")
    }

    func testWalkerEmittedRefsResolveOnStatedConsumers() throws {
        let menu = MenuCatalog.project()
        let emitted = TypedRef.collectEmitted(menu: menu)
        XCTAssertFalse(emitted.isEmpty, "walker must find menu/docs/error refs")

        var commandRefs = 0
        for item in emitted {
            XCTAssertFalse(item.consumers.isEmpty, "\(item.ref) missing consumers (\(item.source))")
            for consumer in item.consumers {
                do {
                    let ok = try TypedRef.resolve(item.ref, on: consumer)
                    XCTAssertTrue(
                        ok,
                        "\(item.ref) from \(item.source) failed on \(consumer.rawValue)"
                    )
                } catch {
                    XCTFail(
                        "\(item.ref) from \(item.source) threw on \(consumer.rawValue): \(error)"
                    )
                }
            }
            if item.kind == .command { commandRefs += 1 }
        }
        XCTAssertGreaterThan(commandRefs, 0)
        XCTAssertTrue(
            emitted.contains { $0.ref == "command:teams.duplicate" && $0.consumers.contains(.docs) },
            "menu must emit command:teams.duplicate for the docs consumer"
        )
    }

    func testExtractTypedRefsSkipsPlaceholders() {
        let fromProse = TypedRef.extractTypedRefs(
            from: "Run `alln menu show team:<id>` or `alln menu show command:run --json`"
        )
        XCTAssertEqual(fromProse.map(\.ref), ["command:run"])
    }
}
