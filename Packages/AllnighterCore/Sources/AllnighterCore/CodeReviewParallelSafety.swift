import Foundation

/// PM safety gate for parallel code-review fan-out (docs/phases/code_review).
/// Parallel runs ONLY when touch surfaces are disjoint and findings-scoped.
public enum CodeReviewParallelSafety {
  public struct PacketSurface: Sendable, Equatable {
    public var sliceId: String
    public var touchAllowlist: [String]
    public var readPaths: [String]

    public init(sliceId: String, touchAllowlist: [String], readPaths: [String] = []) {
      self.sliceId = sliceId
      self.touchAllowlist = touchAllowlist
      self.readPaths = readPaths
    }

    public init(packet: WorkSlicePacket) {
      sliceId = packet.sliceId
      touchAllowlist = packet.touchAllowlist
      readPaths = packet.readPaths.map(\.path)
    }
  }

  public enum Violation: Sendable, Equatable {
    case duplicateSliceId(String)
    case emptyTouchAllowlist(String)
    case touchOutsideFindings(sliceId: String, path: String)
    case touchOverlap(sliceA: String, sliceB: String, path: String)
    case exceedsMaxConcurrent(requested: Int, max: Int)
  }

  public static let findingsPrefix = "docs/phases/code_review/findings/"
  public static let defaultMaxConcurrent = 1

  /// Returns violations; empty ⇒ safe to run `packets` together (up to `maxConcurrent`).
  public static func violations(
    _ packets: [PacketSurface],
    maxConcurrent: Int = defaultMaxConcurrent
  ) -> [Violation] {
    var out: [Violation] = []
    if packets.count > maxConcurrent {
      out.append(.exceedsMaxConcurrent(requested: packets.count, max: maxConcurrent))
    }
    var seenIds: Set<String> = []
    for packet in packets {
      if seenIds.contains(packet.sliceId) {
        out.append(.duplicateSliceId(packet.sliceId))
      }
      seenIds.insert(packet.sliceId)
      if packet.touchAllowlist.isEmpty {
        out.append(.emptyTouchAllowlist(packet.sliceId))
      }
      for path in packet.touchAllowlist {
        if !isFindingsScoped(path) {
          out.append(.touchOutsideFindings(sliceId: packet.sliceId, path: path))
        }
      }
    }
    for i in packets.indices {
      for j in packets.index(after: i)..<packets.endIndex {
        let a = packets[i], b = packets[j]
        for path in Set(a.touchAllowlist).intersection(b.touchAllowlist) {
          out.append(.touchOverlap(sliceA: a.sliceId, sliceB: b.sliceId, path: path))
        }
      }
    }
    return out
  }

  public static func canRunConcurrently(
    _ packets: [PacketSurface],
    maxConcurrent: Int = defaultMaxConcurrent
  ) -> Bool {
    violations(packets, maxConcurrent: maxConcurrent).isEmpty
  }

  /// Greedy batching: each batch is internally safe and ≤ `maxConcurrent`.
  public static func safeBatches(
    _ packets: [PacketSurface],
    maxConcurrent: Int = defaultMaxConcurrent
  ) -> [[PacketSurface]] {
    var remaining = packets
    var batches: [[PacketSurface]] = []
    while !remaining.isEmpty {
      var batch: [PacketSurface] = []
      var i = 0
      while i < remaining.count, batch.count < maxConcurrent {
        let candidate = remaining[i]
        let trial = batch + [candidate]
        if violations(trial, maxConcurrent: maxConcurrent).isEmpty {
          batch.append(candidate)
          remaining.remove(at: i)
        } else {
          i += 1
        }
      }
      if batch.isEmpty, let first = remaining.first {
        batches.append([first])
        remaining.removeFirst()
      } else if !batch.isEmpty {
        batches.append(batch)
      }
    }
    return batches
  }

  public static func isFindingsScoped(_ path: String) -> Bool {
    let norm = path.replacingOccurrences(of: "\\", with: "/")
    return norm.hasPrefix(findingsPrefix) && !norm.hasSuffix("/")
  }
}
