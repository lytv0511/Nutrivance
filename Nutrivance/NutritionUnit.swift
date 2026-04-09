//
//  NutritionUnit.swift
//  Nutrivance
//
//  Created by Vincent Leong on 12/10/24.
//

import Foundation
import Combine

struct NutritionUnit {
    static func getUnit(for nutrient: String) -> String {
        switch nutrient.lowercased() {
        
        // Energy and Macronutrients
        case "calories", "dietary energy consumed": return "kcal"
        case "water", "dietary water": return "mL"
        case "protein", "dietary protein",
             "fat", "dietary fat total",
             "carbohydrates", "dietary carbohydrates",
             "fiber", "dietary fiber",
             "cholesterol", "dietary cholesterol",
             "sugar", "dietary sugar",
             "fat monounsaturated", "dietary fat monounsaturated",
             "fat polyunsaturated", "dietary fat polyunsaturated",
             "fat saturated", "dietary fat saturated",
             "caffeine", "dietary caffeine": return "g"
        
        // Vitamins
        case let vitamin where vitamin.contains("vitamin"):
            if ["vitamin a", "dietary vitamin a",
                "vitamin d", "dietary vitamin d",
                "vitamin k", "dietary vitamin k"].contains(vitamin) {
                return "mcg"
            } else {
                return "mg"
            }
        case "thiamin", "dietary thiamin",
             "riboflavin", "dietary riboflavin",
             "niacin", "dietary niacin",
             "folate", "dietary folate",
             "biotin", "dietary biotin",
             "pantothenic acid", "dietary pantothenic acid",
             "vitamin b6", "dietary vitamin b6",
             "vitamin b12", "dietary vitamin b12",
             "vitamin c", "dietary vitamin c",
             "vitamin e", "dietary vitamin e": return "mg"
        
        // Minerals
        case "calcium", "dietary calcium",
             "iron", "dietary iron",
             "magnesium", "dietary magnesium",
             "phosphorus", "dietary phosphorus",
             "potassium", "dietary potassium",
             "sodium", "dietary sodium",
             "zinc", "dietary zinc",
             "chloride", "dietary chloride",
             "copper", "dietary copper",
             "manganese", "dietary manganese": return "mg"
        
        case "selenium", "dietary selenium",
             "chromium", "dietary chromium",
             "molybdenum", "dietary molybdenum",
             "iodine", "dietary iodine": return "mcg"
        
        default:
            return "g"
        }
    }
}
