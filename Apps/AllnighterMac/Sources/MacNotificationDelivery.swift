import Foundation
import UserNotifications
import AllnighterCore

extension Notification.Name {
    /// Posted when the user clicks a local thread notification.
    static let allnOpenThreadFromNotification = Notification.Name("AllnighterOpenThreadFromNotification")
}

/// Payload for deep-linking a notification click into a thread turn.
struct ThreadNotificationDeepLink: Sendable {
    let threadId: String
    let turnId: String
}

/// macOS local notification delivery and click-to-thread (NOTIF-S03).
@MainActor
final class MacNotificationDelivery: NSObject, UNUserNotificationCenterDelegate, ThreadNotificationDelivering {
    static let shared = MacNotificationDelivery()

    private let center = UNUserNotificationCenter.current()
    private var isConfigured = false

    override private init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    func deliver(candidate: NotificationCandidate, workerDisplayName: String?) async {
        let content = UNMutableNotificationContent()
        content.title = NotificationCopy.title(candidate: candidate, workerDisplayName: workerDisplayName)
        content.body = NotificationCopy.body(candidate: candidate)
        content.sound = .default
        content.userInfo = [
            "threadId": candidate.threadId,
            "turnId": candidate.turnId,
            "event": candidate.event.rawValue,
        ]

        let request = UNNotificationRequest(
            identifier: candidate.id,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let threadId = info["threadId"] as? String,
              let turnId = info["turnId"] as? String else { return }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .allnOpenThreadFromNotification,
                object: ThreadNotificationDeepLink(threadId: threadId, turnId: turnId)
            )
        }
    }
}
