//
//  Item.swift
//  BHealth
//
//  Created by Bill on 2026-06-26.
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
