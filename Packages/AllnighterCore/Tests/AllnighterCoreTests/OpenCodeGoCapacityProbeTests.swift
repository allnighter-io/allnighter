import XCTest
@testable import AllnighterCore

final class OpenCodeGoCapacityProbeTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)

    // Hand-authored synthetic fixtures live in
    // Packages/AllnighterCore/Tests/Fixtures/opencode-go/. They are NOT
    // captured pages — see the header comments in each fixture and the
    // README in that directory. The shape stays the same; the provenance
    // is what changed.
    private var solidHTML: String { OpenCodeGoFixture.solidSSR }
    private var dataSlotHTML: String { OpenCodeGoFixture.dataSlot }

    func testSolidSSRParseAllThreeWindowsAtomically() throws {
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: solidHTML).success)
        XCTAssertEqual(sample.strategy, .solidSSR)
        XCTAssertEqual(sample.rolling.usedPercent, 12.5)
        XCTAssertEqual(sample.weekly.usedPercent, 30)
        XCTAssertEqual(sample.monthly.usedPercent, 45)
    }

    func testCapacityWindowsFromSolidSSR() throws {
        let windows = OpenCodeGoCapacityProbe.capacityWindows(html: solidHTML, observedAt: observedAt)
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == nil })
        XCTAssertEqual(windows.map(\.scope), [.fiveHour, .weekly, .monthly])
        XCTAssertEqual(windows.map(\.source), Array(repeating: "opencode_go", count: 3))
        let rolling = try XCTUnwrap(windows.first { $0.scope == .fiveHour })
        XCTAssertEqual(rolling.usedPercent, 12.5)
        XCTAssertEqual(rolling.remainingPercent, 87.5)
        XCTAssertEqual(rolling.sourceTier, .dashboardScrape)
    }

    func testDataSlotFallbackWhenSolidMissing() throws {
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: dataSlotHTML).success)
        XCTAssertEqual(sample.strategy, .dataSlot)
        XCTAssertEqual(sample.rolling.usedPercent, 10)
        XCTAssertEqual(sample.weekly.usedPercent, 20)
        XCTAssertEqual(sample.monthly.usedPercent, 55.5)
    }

    func testPartialSolidIsTotalFailure() {
        let html = "rollingUsage:$R[0]={usagePercent:1,resetInSec:60}"
        let windows = OpenCodeGoCapacityProbe.capacityWindows(html: html, observedAt: observedAt)
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == .parserFailed(observedAt: observedAt) })
        XCTAssertTrue(windows.allSatisfy { $0.usedPercent == nil })
    }

    /// One out-of-range window poisons the whole sample — the siblings that
    /// parsed cleanly must not be emitted. Asserting only the bad window would
    /// let a plausible wrong 0% ship next to it.
    func testOutOfRangePercentRejectsEntireSample() {
        let html = """
        rollingUsage:$R[0]={usagePercent:150,resetInSec:60}
        weeklyUsage:$R[1]={usagePercent:0,resetInSec:60}
        monthlyUsage:$R[2]={usagePercent:0,resetInSec:60}
        """
        XCTAssertEqual(
            OpenCodeGoCapacityProbe.parseSample(html: html).failure,
            .invalidValue(field: "rolling")
        )
        let windows = OpenCodeGoCapacityProbe.capacityWindows(html: html, observedAt: observedAt)
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == .parserFailed(observedAt: observedAt) })
        XCTAssertTrue(windows.allSatisfy { $0.usedPercent == nil })
    }

    /// A reset clock beyond the window's credible ceiling is the same class of
    /// lie as a bad percentage — reject the sample, do not clamp.
    func testOutOfRangeResetRejectsEntireSample() {
        let html = """
        rollingUsage:$R[0]={usagePercent:10,resetInSec:60}
        weeklyUsage:$R[1]={usagePercent:20,resetInSec:60}
        monthlyUsage:$R[2]={usagePercent:30,resetInSec:9999999}
        """
        XCTAssertEqual(
            OpenCodeGoCapacityProbe.parseSample(html: html).failure,
            .invalidValue(field: "monthly")
        )
        let windows = OpenCodeGoCapacityProbe.capacityWindows(html: html, observedAt: observedAt)
        XCTAssertTrue(windows.allSatisfy { $0.usedPercent == nil })
    }

    func testLoginPageIsAuthRequired() {
        let html = "<html><title>Sign in</title><input type=\"password\"/></html>"
        let windows = OpenCodeGoCapacityProbe.capacityWindows(html: html, observedAt: observedAt)
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == .authRequired(observedAt: observedAt) })
    }

    /// A SolidJS route manifest naming `/sign-in` is not proof of rejection.
    /// A dashboard that carries usage markers must parse, never be written off
    /// as an auth failure on a substring.
    func testSignInRouteInBundleDoesNotFakeAuthRequired() throws {
        let html = """
        <html><body>
        <script>const routes=["/sign-in","/workspace","/auth/login"];</script>
        \(solidHTML)
        </body></html>
        """
        let windows = OpenCodeGoCapacityProbe.capacityWindows(html: html, observedAt: observedAt)
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == nil })
        let rolling = try XCTUnwrap(windows.first { $0.scope == .fiveHour })
        XCTAssertEqual(rolling.usedPercent, 12.5)
    }

    /// An unrecognized page is schema drift, not a manufactured auth verdict.
    func testUnrecognizedPageIsSchemaDriftNotAuthRequired() {
        let windows = OpenCodeGoCapacityProbe.capacityWindows(
            html: "<html><body><h1>Something else entirely</h1></body></html>",
            observedAt: observedAt
        )
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == .parserFailed(observedAt: observedAt) })
    }

    func testStrategyMismatchFailsClosed() {
        let html = """
        rollingUsage:$R[0]={usagePercent:10,resetInSec:60}
        weeklyUsage:$R[1]={usagePercent:20,resetInSec:120}
        monthlyUsage:$R[2]={usagePercent:30,resetInSec:180}
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling Usage</span>
          <span data-slot="usage-value">99%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly Usage</span>
          <span data-slot="usage-value">20%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly Usage</span>
          <span data-slot="usage-value">30%</span>
          <span data-slot="reset-now"></span>
        </div>
        """
        XCTAssertEqual(OpenCodeGoCapacityProbe.parseSample(html: html), .failure(.strategyMismatch))
    }

    func testDualFormatAgreesOnPercentPrefersSolidReset() throws {
        let html = """
        rollingUsage:$R[0]={usagePercent:0,resetInSec:18000}
        weeklyUsage:$R[1]={usagePercent:5,resetInSec:299015}
        monthlyUsage:$R[2]={usagePercent:2,resetInSec:2646068}
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling Usage</span>
          <span data-slot="usage-value">0%</span>
          <span data-slot="reset-time">Resets in 4 hours 59 minutes</span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly Usage</span>
          <span data-slot="usage-value">5%</span>
          <span data-slot="reset-time">Resets in 3 days 11 hours</span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly Usage</span>
          <span data-slot="usage-value">2%</span>
          <span data-slot="reset-time">Resets in 30 days 15 hours</span>
        </div>
        """
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: html).success)
        XCTAssertEqual(sample.strategy, .solidSSR)
        XCTAssertEqual(sample.rolling.usedPercent, 0)
        XCTAssertEqual(sample.rolling.resetInSec, 18000)
    }

    func testSolidResetFirstFieldOrder() throws {
        let html = """
        rollingUsage:$R[33]={status:"ok",resetInSec:17837,usagePercent:0}
        weeklyUsage:$R[34]={status:"ok",resetInSec:298852,usagePercent:5}
        monthlyUsage:$R[35]={status:"ok",resetInSec:2645905,usagePercent:2}
        """
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: html).success)
        XCTAssertEqual(sample.rolling.usedPercent, 0)
        XCTAssertEqual(sample.rolling.resetInSec, 17837)
        XCTAssertEqual(sample.weekly.usedPercent, 5)
        XCTAssertEqual(sample.monthly.usedPercent, 2)
    }

    // MARK: - Defect regression tests

    /// Defect #1: Greedy `[^}]*` in solidRegex backtracks to decoy values inside
    /// quoted strings. A `resetInSec` inside a note field must never supply the
    /// captured number.
    func testSolidSSRCapturesFirstOccurrenceNotDecoyInString() throws {
        let html = """
        rollingUsage:$R[0]={usagePercent:50,resetInSec:18000,x:"usagePercent:1,resetInSec:2"}
        weeklyUsage:$R[1]={usagePercent:30,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:45,resetInSec:86400}
        """
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: html).success)
        XCTAssertEqual(sample.rolling.usedPercent, 50)
        XCTAssertEqual(sample.rolling.resetInSec, 18000, "Decoy resetInSec:2 in string must not win")
    }

    /// Defect #1 variant: `resetInSec` in a note field at the end of the object.
    func testSolidSSRCapturesFirstNotNoteReset() throws {
        let html = """
        rollingUsage:$R[0]={usagePercent:10,resetInSec:300,note:"resetInSec:99999"}
        weeklyUsage:$R[1]={usagePercent:20,resetInSec:3600}
        monthlyUsage:$R[2]={usagePercent:30,resetInSec:86400}
        """
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: html).success)
        XCTAssertEqual(sample.rolling.usedPercent, 10)
        XCTAssertEqual(sample.rolling.resetInSec, 300, "Decoy resetInSec:99999 in note must not win")
    }

    /// Defect #2: data-slot usage-value captures first digit run, not the
    /// percentage. "1,234 tokens (42%)" must yield 42, not 1.
    func testDataSlotCapturesPercentageNotFirstDigit() throws {
        let html = """
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling Usage</span>
          <span data-slot="usage-value">1,234 tokens (42%)</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly Usage</span>
          <span data-slot="usage-value">20%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly Usage</span>
          <span data-slot="usage-value">30%</span>
          <span data-slot="reset-now"></span>
        </div>
        """
        let sample = try XCTUnwrap(OpenCodeGoCapacityProbe.parseSample(html: html).success)
        XCTAssertEqual(sample.rolling.usedPercent, 42, "Must capture 42% not first digit 1")
    }

    /// Defect #3: data-slot silently last-writes duplicate windows with different
    /// values. Two usage-item blocks mapping to the same window with different
    /// values must fail with `.duplicateWindow`.
    func testDataSlotDuplicateWindowWithDifferentValuesFails() {
        let html = """
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling Usage</span>
          <span data-slot="usage-value">10%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Rolling Usage</span>
          <span data-slot="usage-value">90%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly Usage</span>
          <span data-slot="usage-value">20%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly Usage</span>
          <span data-slot="usage-value">30%</span>
          <span data-slot="reset-now"></span>
        </div>
        """
        XCTAssertEqual(
            OpenCodeGoCapacityProbe.parseSample(html: html).failure,
            .duplicateWindow("rolling")
        )
    }

    /// Defect #4: Substring-based label classification is order-dependent.
    /// "Weekly Rolling Usage" contains both "rolling" and "weekly" — the parser
    /// must not silently assign it to "rolling" (first check wins).
    func testLabelAmbiguitySkipsBlockLeadingToMissingWindow() {
        let html = """
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly Rolling Usage</span>
          <span data-slot="usage-value">10%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Weekly Usage</span>
          <span data-slot="usage-value">20%</span>
          <span data-slot="reset-now"></span>
        </div>
        <div data-slot="usage-item">
          <span data-slot="usage-label">Monthly Usage</span>
          <span data-slot="usage-value">30%</span>
          <span data-slot="reset-now"></span>
        </div>
        """
        // Ambiguous label (matches both rolling + weekly) → skipped.
        // Unambiguous "Weekly Usage" → weekly=20. "Monthly Usage" → monthly=30.
        // Missing rolling → schemaDrift. Must not silently assign to rolling.
        XCTAssertEqual(
            OpenCodeGoCapacityProbe.parseSample(html: html).failure,
            .schemaDrift(strategy: "data_slot_v1", missing: ["rolling"])
        )
    }
}

private extension Result where Success == OpenCodeGoCapacityProbe.ParsedSample, Failure == OpenCodeGoCapacityProbe.ParseFailure {
    var success: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    var failure: Failure? {
        if case .failure(let value) = self { return value }
        return nil
    }
}

private enum OpenCodeGoFixture {
    static let solidSSRFile = "go-dashboard-ssr.html"
    static let dataSlotFile = "go-dashboard-dataslot.html"

    static var solidSSR: String { try! loadHTML(solidSSRFile) }
    static var dataSlot: String { try! loadHTML(dataSlotFile) }

    /// Resolves a fixture path relative to this test file using `#filePath`,
    /// so SwiftPM resource wiring is not required. Crashes loudly if a
    /// referenced file is missing — that is a test infrastructure failure
    /// and should not be papered over with a synthetic fallback.
    static func loadHTML(_ name: String, file: StaticString = #filePath) throws -> String {
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // AllnighterCoreTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("opencode-go")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
