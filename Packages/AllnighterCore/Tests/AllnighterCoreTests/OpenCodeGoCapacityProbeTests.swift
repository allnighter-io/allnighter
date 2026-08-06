import XCTest
@testable import AllnighterCore

final class OpenCodeGoCapacityProbeTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)

    private let solidHTML = """
    <html><body>
    rollingUsage:$R[0]={usagePercent:12.5,resetInSec:7200}
    weeklyUsage:$R[1]={usagePercent:30,resetInSec:86400}
    monthlyUsage:$R[2]={usagePercent:45,resetInSec:1209600}
    </body></html>
    """

    private let dataSlotHTML = """
    <div data-slot="usage-item">
      <span data-slot="usage-label">Rolling Usage</span>
      <span data-slot="usage-value">10%</span>
      <span data-slot="reset-time">Resets in 1 hour 30 minutes</span>
    </div>
    <div data-slot="usage-item">
      <span data-slot="usage-label">Weekly Usage</span>
      <span data-slot="usage-value">20%</span>
      <span data-slot="reset-now"></span>
    </div>
    <div data-slot="usage-item">
      <span data-slot="usage-label">Monthly Usage</span>
      <span data-slot="usage-value">55.5%</span>
      <span data-slot="reset-time">Resets in 6 days 2 hours</span>
    </div>
    """

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
