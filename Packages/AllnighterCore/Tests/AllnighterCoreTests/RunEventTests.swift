import XCTest
@testable import AllnighterCore

final class RunEventTests: XCTestCase {

    func testEventRoundTripsWithMixedPayload() throws {
        let event = RunEvent(
            id: "evt_1",
            seq: 42,
            ts: Date(timeIntervalSince1970: 1_750_000_000),
            kind: RunEventKind.memberStatusChanged,
            payload: [
                "runId": .string("run_complete_0001"),
                "workerId": .string("worker_grok"),
                "from": .string("running"),
                "to": .string("timed_out"),
                "attempt": .int(1),
                "elapsed": .double(120.5),
                "final": .bool(true),
                "note": .null,
                "tags": .array([.string("a"), .string("b")]),
                "meta": .object(["k": .string("v")])
            ]
        )

        let data = try CoreJSON.encode(event)
        let decoded = try CoreJSON.decode(RunEvent.self, from: data)
        XCTAssertEqual(event, decoded)
    }

    func testIntDoesNotDecodeAsDouble() throws {
        let json = Data(#"{"n": 7}"#.utf8)
        let decoded = try CoreJSON.decode([String: JSONValue].self, from: json)
        XCTAssertEqual(decoded["n"], .int(7))
    }

    func testBoolDoesNotDecodeAsInt() throws {
        let json = Data(#"{"b": true}"#.utf8)
        let decoded = try CoreJSON.decode([String: JSONValue].self, from: json)
        XCTAssertEqual(decoded["b"], .bool(true))
    }
}
