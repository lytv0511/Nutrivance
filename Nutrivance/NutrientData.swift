//
//  NutrientData.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/20/24.
//

import Foundation
struct NutrientData: Identifiable {
    let id = UUID()
    let name: String
    var value: Double
    let unit: String
    var isEditing: Bool = false
}
