//
//  SearchView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/22/24.
//

import Foundation
import SwiftUI
import NaturalLanguage
import HealthKit

struct SearchView: View {
    @State private var searchText = ""
    @State private var extractedNutrients: [String: Double] = [:]
    @State private var showConfirmation = false
    @FocusState private var isSearchBarFocused: Bool
    @State private var showingImportView = false
    @State private var nutrientData: [NutrientData] = []
    
    private let nlProcessor = NLNaturalLanguageProcessor()
    private let healthStore = HKHealthStore()
    
    var body: some View {
        Spacer(minLength: 50)
        VStack(spacing: 20) {
            Text("Add Nutrients")
                .font(.largeTitle)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            // Enhanced search bar
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundColor(.blue)
                    .padding(.leading, 10)
                
                TextField("Describe what you ate...", text: $searchText)
                    .focused($isSearchBarFocused)
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.3))
                    )
                    .onSubmit {
                        processInput()
                    }
                
                Button(action: processInput) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
//                .padding(10)
                .hoverEffect(.highlight) // Adds a subtle highlight effect for pointer interactions
            }
            .padding()
            
            if !extractedNutrients.isEmpty {
                // Results card view with icons
                VStack(spacing: 15) {
                    Text("Extracted Nutrients")
                        .font(.headline)
                        .padding(.top)
                    
                    ForEach(Array(extractedNutrients.keys.sorted()), id: \.self) { nutrient in
                        HStack {
                            Image(systemName: getNutrientIcon(for: nutrient))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.blue)
                                .padding(.trailing, 8)
                            
                            Text(nutrient.capitalized)
                                .font(.body)
                            Spacer()
                            Text("\(extractedNutrients[nutrient] ?? 0, specifier: "%.1f") \(getUnit(for: nutrient))")
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                        Divider()
                    }
                    
                    Button(action: saveToHealthKit) {
                        Text("Add to Health")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
                .cornerRadius(15)
                .shadow(radius: 5)
                .padding()
            }
            
            Spacer()
        }
        .sheet(isPresented: $showingImportView) {
            HealthKitImportView(nutrients: extractedNutrients.map { (name, value) in
                let unit = name.lowercased() == "calories" ? "kcal" :
                name.lowercased() == "water" ? "L" :
                "g"
                return NutrientData(
                    name: name,
                    value: value,
                    unit: unit
                )
            })
        }
        .alert("Added to Health", isPresented: $showConfirmation) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func processInput() {
        extractedNutrients = nlProcessor.extractNutrients(from: searchText)
        isSearchBarFocused = false
    }
    
//    private func saveToHealthKit() {
//        showConfirmation = true
//        extractedNutrients = [:]
//        searchText = ""
//    }
    
    private func getUnit(for nutrient: String) -> String {
        switch nutrient.lowercased() {
        case "protein", "carbs", "fats", "fiber": return "g"
        case "calories": return "kcal"
        case "water": return "L"
        default: return "g"
        }
    }
    
    private func saveToHealthKit() {
        nutrientData = extractedNutrients.map { (name, value) in
            let unit = name.lowercased() == "calories" ? "kcal" :
                       name.lowercased() == "water" ? "L" :
                       "g"
            return NutrientData(
                name: name,
                value: value,
                unit: unit
            )
        }
        showingImportView = true
    }
    
    private func getNutrientIcon(for nutrient: String) -> String {
        switch nutrient.lowercased() {
        case "calories": return "flame"
        case "protein": return "fork.knife"
        case "carbs": return "carrot"
        case "fats": return "drop"
        case "fiber": return "leaf.fill"
        case "vitamins": return "pill"
        case "minerals": return "bolt"
        case "water": return "drop.fill"
        case "phytochemicals": return "leaf.arrow.triangle.circlepath"
        case "antioxidants": return "shield"
        case "electrolytes": return "battery.100"
        default: return "circle.fill"
        }
    }
}

class NLNaturalLanguageProcessor {
    private let nutrientKeywords = [
        "protein": ["protein", "proteins", "whey", "casein"],
        "calories": ["calories", "calorie", "kcal", "cal"],
        "carbs": ["carbs", "carbohydrates", "carbohydrate"],
        "fats": ["fat", "fats", "lipids", "oil"],
        "fiber": ["fiber", "fibre", "dietary fiber"],
        "water": ["water", "h2o", "fluid"],
        "vitamins": ["vitamin", "vitamins", "vit"],
        "minerals": ["mineral", "minerals"]
    ]
    
    func extractNutrients(from text: String) -> [String: Double] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .tokenType])
        tagger.string = text.lowercased()
        
        var nutrients: [String: Double] = [:]
        var currentNumber: Double?
        var lastFoundNumber: Double?
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            let word = String(text[tokenRange]).lowercased()
            
            if let number = extractNumber(from: word) {
                currentNumber = number
                lastFoundNumber = number
            }
            
            for (nutrientKey, keywords) in nutrientKeywords {
                if keywords.contains(word) {
                    if let number = currentNumber ?? lastFoundNumber {
                        nutrients[nutrientKey] = number
                        currentNumber = nil
                    }
                }
            }
            
            return true
        }
        
        return nutrients
    }
    
    private func extractNumber(from word: String) -> Double? {
        let patterns = [
            "([0-9]+\\.?[0-9]*)(g|mg|kcal)?",
            "([0-9]+)",
            "([0-9]+\\.[0-9]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(word.startIndex..., in: word)
                if let match = regex.firstMatch(in: word, range: range) {
                    if let numberRange = Range(match.range(at: 1), in: word) {
                        return Double(word[numberRange])
                    }
                }
            }
        }
        
        let numberWords = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
        ]
        
        return numberWords[word].map { Double($0) }
    }

}
