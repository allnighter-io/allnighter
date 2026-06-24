//
//  ConversationRelativeTime.swift
//  AllnighteriOS
//
//  Shared relative-age formatting for home and cache labels.
//

import Foundation

enum ConversationRelativeTime {
    static func age(from date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        let minute = 60
        let hour = 60 * minute
        let day = 24 * hour

        if elapsed < minute { return "just now" }
        if elapsed < hour { return unit(elapsed / minute, singular: "minute") }
        if elapsed < day { return unit(elapsed / hour, singular: "hour") }
        return unit(elapsed / day, singular: "day")
    }

    static func lastSeen(serverTime: Date, now: Date = Date()) -> String {
        "Last seen \(age(from: serverTime, now: now))"
    }

    private static func unit(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s") ago"
    }
}
