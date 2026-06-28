import Foundation

/// Accumulates streamed answer deltas into the visible partial text of a running
/// worker turn, enforcing the 64 KB visible cap and a byte-based flush cadence
/// (03_Mac_Streaming §Thread Storage). Pure and synchronous: the wiring layer owns
/// the wall-clock flush timer and the `ThreadStore.updateTurn` write. When the cap
/// is exceeded we keep the NEWEST visible suffix and mark `isTruncated`; the
/// complete final answer replaces the partial at settlement.
public struct StreamingPartialBuffer: Sendable {
    /// Cap on visible partial text (newest suffix kept beyond this).
    public static let visibleCapBytes = 64 * 1024
    /// Flush when this many bytes have accumulated since the last flush — the byte
    /// half of "every 120–250 ms or every 2–4 KB, whichever comes first".
    public static let flushByteThreshold = 2 * 1024

    private var text: String = ""
    private var truncated = false
    private var unflushedBytes = 0
    private let capBytes: Int
    private let flushBytes: Int

    public init(capBytes: Int = StreamingPartialBuffer.visibleCapBytes,
                flushBytes: Int = StreamingPartialBuffer.flushByteThreshold) {
        self.capBytes = capBytes
        self.flushBytes = flushBytes
    }

    public var visibleText: String { text }
    public var isTruncated: Bool { truncated }

    /// Append a delta to the visible text. Returns true when a byte-threshold flush
    /// is due (the caller may also flush on a timer regardless).
    @discardableResult
    public mutating func append(_ delta: String) -> Bool {
        guard !delta.isEmpty else { return false }
        text += delta
        if text.utf8.count > capBytes {
            text = Self.newestSuffix(of: text, maxBytes: capBytes)
            truncated = true
        }
        unflushedBytes += delta.utf8.count
        return unflushedBytes >= flushBytes
    }

    /// Call after writing the current `visibleText` so the byte counter resets.
    public mutating func markFlushed() { unflushedBytes = 0 }

    /// The newest UTF-8 suffix of `s` within `maxBytes`, cut on a Character boundary.
    /// Single O(n) pass from the end — avoids rescanning the full buffer on each drop.
    static func newestSuffix(of s: String, maxBytes: Int) -> String {
        var accumulated = 0
        var startIndex = s.endIndex
        var index = s.endIndex
        while index > s.startIndex {
            let prev = s.index(before: index)
            let charBytes = s[prev..<index].utf8.count
            if accumulated + charBytes > maxBytes { break }
            accumulated += charBytes
            startIndex = prev
            index = prev
        }
        return String(s[startIndex...])
    }
}
