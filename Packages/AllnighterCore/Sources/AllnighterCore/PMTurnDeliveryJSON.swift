import Foundation

/// Read-side wake delivery state for a durable PM turn.
///
/// `PMTurnJSON` remains the delivery truth. This is only the serve-owned
/// projection of whether its configured wake receiver acknowledged the turn.
public struct PMTurnDeliveryJSON: Codable, Equatable, Sendable {
    public var status: String
    public var attempts: Int
    public var lastAttemptAt: Date?
    public var nextAttemptAt: Date?
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        status: String,
        attempts: Int,
        lastAttemptAt: Date? = nil,
        nextAttemptAt: Date? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.nextAttemptAt = nextAttemptAt
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}
