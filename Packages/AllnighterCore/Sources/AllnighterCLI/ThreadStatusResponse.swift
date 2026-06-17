import Foundation
import AllnighterCore

struct ThreadStatusResponse: Codable {
    var threadId: String
    var isRunning: Bool
    var needsAttention: Bool
}
