//
//  IOSTestFixture.swift
//  AllnighteriOS
//
//  DEBUG launch-arg fixtures for agent screenshot / uitest proof.
//

import Foundation

enum IOSTestFixture {
    static var opensModelPicker: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui_fixture_model_picker")
        #else
        false
        #endif
    }

    static var opensPendingReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui_fixture_pending_review")
        #else
        false
        #endif
    }

    static var opensPendingQueue: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui_fixture_pending")
            || ProcessInfo.processInfo.arguments.contains("-ui_fixture_pending_review")
        #else
        false
        #endif
    }

    /// e.g. `-ui_fixture_thread=thread-1`
    static var openThreadId: String? {
        #if DEBUG
        for argument in ProcessInfo.processInfo.arguments {
            let prefix = "-ui_fixture_thread="
            if argument.hasPrefix(prefix) {
                let id = String(argument.dropFirst(prefix.count))
                return id.isEmpty ? nil : id
            }
        }
        return nil
        #else
        nil
        #endif
    }
}
