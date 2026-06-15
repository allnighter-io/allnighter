//
//  Item.swift
//  AllnighteriOS
//
//  Created by Michael Reining on 2026-06-15.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
