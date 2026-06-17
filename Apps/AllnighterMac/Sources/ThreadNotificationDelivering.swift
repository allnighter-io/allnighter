import Foundation
import AllnighterCore

/// Delivers a notification candidate to the platform (test seam).
@MainActor
protocol ThreadNotificationDelivering: AnyObject {
    func deliver(candidate: NotificationCandidate, workerDisplayName: String?) async
}

@MainActor
final class NoOpThreadNotificationDelivery: ThreadNotificationDelivering {
    func deliver(candidate: NotificationCandidate, workerDisplayName: String?) async {}
}
