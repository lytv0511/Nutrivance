//
//  NutritionTableDetector.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/19/24.
//

import UIKit

class NutritionTableDetector {
    private let nutritionExtractorWrapper = NutritionExtractorWrapper()
    
    func detectNutritionTable(_ image: UIImage) -> [Any]? {
        guard let wrapper = nutritionExtractorWrapper else {
            return nil
        }
        return wrapper.detectNutritionTable(image)
    }
}
