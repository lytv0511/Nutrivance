//
//  NutrientInfo.swift
//  Nutrivance
//
//  Created by Vincent Leong on 12/16/24.
//

import Foundation
import SwiftUI

func getNutrientIcon(for nutrient: String) -> String {
    switch nutrient {
    case "Calories": return "flame"
    case "Protein": return "fork.knife"
    case "Carbs": return "carrot"
    case "Fats": return "drop.fill"
    case "Fiber": return "leaf.fill"
    case "Vitamins": return "pill"
    case "Minerals": return "bolt"
    case "Water": return "drop.fill"
    case "Phytochemicals": return "leaf.arrow.triangle.circlepath"
    case "Antioxidants": return "shield"
    case "Electrolytes": return "battery.100"
    default: return "questionmark"
    }
}

func getNutrientColor(for nutrient: String) -> Color {
    switch nutrient {
    case "Carbs": return Color.green.opacity(0.7)
    case "Protein": return Color.orange.opacity(0.7)
    case "Fats": return Color.blue.opacity(0.7)
    case "Calories": return Color.red.opacity(0.7)
    case "Fiber": return Color.purple.opacity(0.7)
    case "Vitamins": return Color.yellow.opacity(0.7)
    case "Minerals": return Color.teal.opacity(0.7)
    case "Water": return Color.cyan.opacity(0.7)
    case "Phytochemicals": return Color.pink.opacity(0.7)
    case "Antioxidants": return Color.indigo.opacity(0.7)
    case "Electrolytes": return Color.mint.opacity(0.7)
    default: return Color.gray
    }
}
