//
//  NutritionDetection.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/20/24.
//

import Foundation

struct NutritionDetection {
    let x: Float
    let y: Float
    let width: Float
    let height: Float
    let confidence: Float
    
    init(dict: [String: Any]) {
        self.x = dict["x"] as? Float ?? 0
        self.y = dict["y"] as? Float ?? 0
        self.width = dict["width"] as? Float ?? 0
        self.height = dict["height"] as? Float ?? 0
        self.confidence = dict["confidence"] as? Float ?? 0
    }
}
