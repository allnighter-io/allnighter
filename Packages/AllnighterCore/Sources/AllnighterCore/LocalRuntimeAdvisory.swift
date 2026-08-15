import Foundation

/// LR-S05 — §2.2 advisory reasons for local runtime tag rows. GUI and CLI share
/// these strings; never gate the toggle. Nil inputs are never "not recommended."
public enum LocalRuntimeAdvisory {
  public static let g1Failed =
    "G1 failed — structured `tool_calls` missing. Enable still works."
  public static let g1Unknown = "G1 unknown. Not a fail."
  public static let windowUnobserved =
    "Window unobserved (tag not in `/api/ps`). Not a fail."

  public static func servedWindowBelowFloor(_ window: Int) -> String {
    "Served window \(window) (below automatic Code floor). Enable still works."
  }

  /// Observed G1 / served window only — never `allowsAutomaticCodeOffer` on nil.
  public static func reason(
    g1Passed: Bool?,
    servedContextWindow: Int?,
    tagObservedInPS: Bool
  ) -> String? {
    if g1Passed == false { return g1Failed }
    if g1Passed != true { return g1Unknown }
    if let window = servedContextWindow {
      if window < OllamaLocalSeatEnablePolicy.automaticCodeServedContextMinimum {
        return servedWindowBelowFloor(window)
      }
      return nil
    }
    if !tagObservedInPS { return windowUnobserved }
    return nil
  }
}
