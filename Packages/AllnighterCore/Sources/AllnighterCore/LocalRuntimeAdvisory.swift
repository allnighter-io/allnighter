import Foundation

/// LR-S05 — §2.2 advisory reasons for local runtime tag rows. GUI and CLI share
/// these strings; never gate the toggle. Nil inputs are never "not recommended."
public enum LocalRuntimeAdvisory {
  public static let g1Failed =
    "This model did not use tools correctly in our test. It may struggle with coding work. You can still turn it on."
  public static let g1Unknown = "Allnighter has not tested this model."
  public static let windowUnobserved =
    "Allnighter will know this model context size after it runs once."

  public static func formatContextSize(_ tokens: Int) -> String {
    if tokens >= 1024 && tokens % 1024 == 0 {
      return "\(tokens / 1024)K"
    }
    return "\(tokens)"
  }

  public static func servedWindowBelowFloor(_ window: Int) -> String {
    "This model has a \(formatContextSize(window)) context. That is smaller than Allnighter normally picks for coding work. You can still turn it on."
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
