import Foundation

/// Process-wide gate so LoopbackHealthServer / DirectModeCommandServer suites
/// do not overlap accept-loops when XCTest runs classes in parallel (TIU-S02).
enum ServerAcceptLoopTestGate {
    private static let lock = NSLock()

    static func enter() {
        lock.lock()
    }

    static func exit() {
        lock.unlock()
    }
}
