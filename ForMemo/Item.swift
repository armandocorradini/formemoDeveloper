//
//  Item.swift
//  ForMemo
//
//  Created by Armando Corradini on 02/04/2026.
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
