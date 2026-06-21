import XCTest
@testable import AllnighterCore

/// The Bug Packet writer emits a fenced ```fix-packet block; Core lifts it into a typed
/// FixPacket (the Auto Fix hand-off). Parsing is lenient — partial blocks still parse, the
/// GATE (not the decoder) enforces what's required to execute.
final class FixPacketParserTests: XCTestCase {

    private let writerOutput = """
    # Bug Packet

    The composer drops pasted images. Truth lives at the AppKit↔SwiftUI bridge.

    Ranked hypotheses…

    ```fix-packet
    {
      "schemaVersion": 1,
      "seam": "AppKit↔SwiftUI",
      "symptom": "Pasting an image does nothing",
      "repro": "Copy a screenshot, focus composer, ⌘V",
      "truthOwner": "ComposerTextView paste bridge",
      "hypotheses": [
        {"id": "h1", "cause": "readablePasteboardTypes omits image", "experiment": "log paste types", "fix": "advertise image types", "fixBoundary": "ComposerTextView"},
        {"id": "h2", "cause": "string read first swallows image", "experiment": "reorder reader", "fix": "image before string", "fixBoundary": "ComposerPasteboardReader"}
      ],
      "ruledOut": ["Edit-menu wiring (proven present)"],
      "proofMethod": "guiFixture",
      "guiProofFixture": "composer-image-paste",
      "requiresLayoutWatcher": true,
      "harnessNeeded": true,
      "harnessSketch": "one SwiftUI text field over NSViewRepresentable+NSTextView; paste image",
      "confidenceOrdering": "low",
      "tier": "T2 SSOT",
      "dangerFlags": []
    }
    ```
    """

    func testParsesTypedPacketFromWriterBlock() {
        let p = FixPacketParser.parse(fromWriterOutput: writerOutput)
        let packet = try? XCTUnwrap(p)
        XCTAssertEqual(packet?.seam, "AppKit↔SwiftUI")
        XCTAssertEqual(packet?.truthOwner, "ComposerTextView paste bridge")
        XCTAssertEqual(packet?.hypotheses.count, 2)
        XCTAssertEqual(packet?.hypotheses.first?.id, "h1")
        XCTAssertEqual(packet?.hypotheses.first?.fixBoundary, "ComposerTextView")
        XCTAssertEqual(packet?.ruledOut, ["Edit-menu wiring (proven present)"])
        XCTAssertEqual(packet?.proofMethod, .guiFixture)
        XCTAssertTrue(packet?.harnessNeeded == true)
        // Low confidence is fine — it's an ordering hint, not a gate.
        XCTAssertEqual(packet?.confidenceOrdering, .low)
    }

    func testMissingBlockReturnsNil() {
        XCTAssertNil(FixPacketParser.parse(fromWriterOutput: "# Bug Packet\n\nno block here"))
        XCTAssertNil(FixPacketParser.parse(fromWriterOutput: nil))
    }

    func testLenientDecodeFillsDefaults() {
        let out = """
        ```fix-packet
        { "symptom": "x", "hypotheses": [{"id":"h1","cause":"c","fix":"f","fixBoundary":"b"}] }
        ```
        """
        let p = FixPacketParser.parse(fromWriterOutput: out)
        XCTAssertEqual(p?.symptom, "x")
        XCTAssertEqual(p?.proofMethod, .userObservation, "missing proofMethod defaults")
        XCTAssertEqual(p?.confidenceOrdering, .medium, "missing confidence defaults")
        XCTAssertEqual(p?.dangerFlags, [])
        XCTAssertFalse(p?.harnessNeeded ?? true)
    }
}
