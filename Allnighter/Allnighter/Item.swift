//
//  Item.swift
//  Allnighter
//
//  Created by Michael Reining on 2026-06-14.
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
