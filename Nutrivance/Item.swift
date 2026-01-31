//
//  Item.swift
//  Nutrivance
//
//  Created by Vincent Leong on 10/29/24.
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
