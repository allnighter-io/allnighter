import Foundation
import AllnighterCore

/// A tiny in-memory cache of decoded `TeamRun`s keyed by runId. Deliberately NOT
/// `@Observable` and not part of any SwiftUI state graph — its whole job is to let a
/// view's computed property ask for a run repeatedly during one draw pass without
/// re-decoding `run.json` each time (the cause of the 5–10s team-run open stall).
/// Only terminal (immutable) runs are stored; callers invalidate on update.
final class RunDecodeCache {
    private var cache: [String: TeamRun] = [:]

    func get(_ runId: String) -> TeamRun? { cache[runId] }
    func set(_ runId: String, _ run: TeamRun) { cache[runId] = run }
    func clear(_ runId: String) { cache[runId] = nil }
    func clearAll() { cache.removeAll() }
}
