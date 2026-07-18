import Foundation
import CryptoKit

/// Immutable context provenance for a team run (Concurrent Invocation
/// Isolation F4 — `docs/phases/Concurrent_Invocation_Isolation.md`).
///
/// Every staged runner packet carries this record; the runner refuses to
/// execute a packet whose delivered context is not its own request. Three
/// independently-checkable anchors:
/// - `runId` — the run this context belongs to (vs the runner's argv run id);
/// - `repoRoot` — the resolved ABSOLUTE canonical project root (symlinks
///   resolved, never a relative/aliased spelling);
/// - `contentHash` — SHA256 over the length-prefixed context parts (question,
///   context, threadId, resolved root), so any byte substituted in flight
///   fails the recompute.
///
/// The runner additionally cross-checks the packet against the run's durable
/// journal (minted prompt + thread id + root): a packet that is internally
/// consistent but belongs to a DIFFERENT run is still rejected.
public struct RunContextProvenance: Codable, Sendable, Equatable {
    /// The run this context packet belongs to.
    public var runId: String
    /// Resolved absolute canonical project root (nil only when genuinely rootless).
    public var repoRoot: String?
    public var threadId: String?
    /// SHA256 hex over the canonical context parts (see `contentHash(...)`).
    public var contentHash: String

    public init(runId: String, repoRoot: String?, threadId: String?, contentHash: String) {
        self.runId = runId
        self.repoRoot = repoRoot
        self.threadId = threadId
        self.contentHash = contentHash
    }

    /// Canonical, ambiguity-free encoding: each field length-prefixed, nil
    /// encoded as `-1:` so ["a","bc"] and ["ab","c"] cannot collide.
    public static func contentHash(
        question: String,
        context: String?,
        threadId: String?,
        repoRoot: String?
    ) -> String {
        func field(_ value: String?) -> String {
            guard let value else { return "-1:" }
            return "\(value.utf8.count):\(value)"
        }
        let canonical = [field(question), field(context), field(threadId), field(repoRoot)]
            .joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Stamp provenance for a request being staged for `runId`.
    /// `resolvedRepoRoot` must already be the canonical absolute root.
    public static func make(
        runId: String,
        question: String,
        context: String?,
        threadId: String?,
        resolvedRepoRoot: String?
    ) -> RunContextProvenance {
        RunContextProvenance(
            runId: runId,
            repoRoot: resolvedRepoRoot,
            threadId: threadId,
            contentHash: contentHash(
                question: question, context: context,
                threadId: threadId, repoRoot: resolvedRepoRoot
            )
        )
    }

    /// True when the stamped hash matches the delivered content — proves the
    /// packet's question/context/thread id are exactly what the stager sent.
    public func authenticates(question: String, context: String?, threadId: String?) -> Bool {
        contentHash == Self.contentHash(
            question: question, context: context, threadId: threadId, repoRoot: repoRoot
        )
    }
}
