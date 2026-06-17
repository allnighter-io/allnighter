import Foundation
import Observation
import AllnighterCore

/// Menu-bar floor-manager indicator inputs (NOTIF-S05).
@MainActor
@Observable
final class FloorManagerStatus {
    private(set) var anyThreadRunning = false
    private(set) var needsAttentionCount = 0
    private(set) var priorityThreadId: String?

    func update(from threads: [WorkThread]) {
        let triaged = ThreadsPresenter.triagedActive(threads)
        anyThreadRunning = triaged.contains { $0.isRunning }
        needsAttentionCount = triaged.filter(\.needsAttention).count
        priorityThreadId = triaged.first?.id
    }
}
