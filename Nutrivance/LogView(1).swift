//
//  LogView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/22/24.
//

import Foundation
import SwiftUI
import NaturalLanguage
import HealthKit

struct LogView: View {
    @State private var searchText = ""
    @State private var extractedNutrients: [String: Double] = [:]
    @State private var showConfirmation = false
    @FocusState private var isSearchBarFocused: Bool
    @State private var showingImportView = false
    @State private var nutrientData: [NutrientData] = []
    @State private var showingNutrientSheet = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private let nlProcessor = NLNaturalLanguageProcessor()
    private let healthStore = HKHealthStore()
    @State private var animationPhase: Double = 0
    
    var body: some View {
        NavigationStack {
                ScrollView {
                    VStack {
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundColor(.blue)
                                .padding(.leading, 10)
                            
                            TextField("Describe what you ate...", text: $searchText)
                                .focused($isSearchBarFocused)
                                .foregroundColor(.primary)
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                                .autocorrectionDisabled(true)
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
                            .hoverEffect(.highlight)
                        }
                        .padding()
                        
                        if extractedNutrients.isEmpty {
                            BubblesView(activeNutrients: Set(), rotationSpeed: 0.0005, nutrientValues: [:])
                                .frame(minHeight: 500)
                        } else if !extractedNutrients.isEmpty {
                            BubblesView(activeNutrients: Set(extractedNutrients.keys), rotationSpeed: 0.001, nutrientValues: extractedNutrients)
                                .frame(minHeight: 300)
                        }
                        
                        if !extractedNutrients.isEmpty {
                            VStack() {
                                HStack {
                                    Text("Extracted Nutrients")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        showingNutrientSheet = true
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .foregroundStyle(.blue)
                                            .padding()
                                    }
                                    .hoverEffect(.highlight)
                                }
                                .padding(.top)
                                .padding(.horizontal)
//                                if horizontalSizeClass == .regular {
                                    ScrollView {
                                        ForEach(Array(extractedNutrients.keys.sorted()), id: \.self) { nutrient in
                                            Spacer()
                                            Spacer()
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
                                            Spacer()
                                            Spacer()
                                            Divider()
                                        }
                                    }
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(15)
                                    .shadow(radius: 5)
                                    .padding(.horizontal)
//                                }
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
                        
                        
                        
                        Spacer()
                    }
                }
                .sheet(isPresented: $showingImportView) {
                    HealthKitImportView(nutrients: extractedNutrients.map { (name, value) in
                        let unit = NutritionUnit.getUnit(for: name)
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
                .sheet(isPresented: $showingNutrientSheet) {
                    NavigationStack {
                        List {
                            ForEach(Array(extractedNutrients.keys.sorted()), id: \.self) { nutrient in
                                HStack {
                                    Image(systemName: getNutrientIcon(for: nutrient))
                                        .foregroundStyle(.blue)
                                    Text(nutrient.capitalized)
                                    Spacer()
                                    Text("\(extractedNutrients[nutrient] ?? 0, specifier: "%.1f") \(getUnit(for: nutrient))")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .navigationTitle("Detected Nutrients")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showingNutrientSheet = false
                                }
                            }
                        }
                    }
                }
                .background(
                   GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                       .onAppear {
                           withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                               animationPhase = 20
                           }
                       }
               )
                .navigationTitle(Text("Log Nutrients"))
        }
    }
    
    private func processInput() {
        extractedNutrients = nlProcessor.extractNutrients(from: searchText)
        isSearchBarFocused = false
    }
    
    private func getUnit(for nutrient: String) -> String {
        switch nutrient.lowercased() {
        case "protein", "carbs", "fats", "fiber": return "g"
        case "calories": return "kcal"
        case "water": return "mL"  // Updated from "L" to "mL"
        default: return "g"
        }
    }
    
    private func saveToHealthKit() {
        nutrientData = extractedNutrients.map { (name, value) in
            NutrientData(
                name: name,
                value: value,
                unit: getUnit(for: name)
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
        // Macronutrients
        "protein": ["protein", "proteins", "whey", "casein", "amino acid", "amino acids"],
        "calories": ["calories", "calorie", "kcal", "cal", "energy", "dietary energy"],
        "carbs": ["carbs", "carbohydrates", "carbohydrate", "sugars", "starches", "glucose"],
        "fats": ["fat", "fats", "lipids", "oil", "oils", "triglycerides"],
        "fiber": ["fiber", "fibre", "dietary fiber", "roughage", "cellulose", "pectin"],
        "water": ["water", "h2o", "fluid", "hydration"],
        
        // Vitamins
        "vitamin a": ["vitamin a", "retinol", "beta-carotene"],
        "vitamin c": ["vitamin c", "ascorbic acid"],
        "vitamin d": ["vitamin d", "calciferol", "cholecalciferol"],
        "vitamin e": ["vitamin e", "tocopherol"],
        "vitamin k": ["vitamin k", "phylloquinone", "menaquinone"],
        "thiamin": ["thiamin", "vitamin b1", "b1", "aneurin"],
        "riboflavin": ["riboflavin", "vitamin b2", "b2"],
        "niacin": ["niacin", "vitamin b3", "b3", "nicotinic acid", "niacinamide"],
        "vitamin b6": ["vitamin b6", "b6", "pyridoxine", "pyridoxal", "pyridoxamine"],
        "vitamin b12": ["vitamin b12", "b12", "cobalamin", "cyanocobalamin"],
        "folate": ["folate", "folic acid", "vitamin b9", "b9"],
        "biotin": ["biotin", "vitamin b7", "b7"],
        "pantothenic acid": ["pantothenic acid", "vitamin b5", "b5"],
        
        // Minerals
        "calcium": ["calcium", "ca"],
        "iron": ["iron", "fe", "ferrous"],
        "magnesium": ["magnesium", "mg"],
        "phosphorus": ["phosphorus", "p", "phosphate"],
        "potassium": ["potassium", "k"],
        "sodium": ["sodium", "na", "salt"],
        "zinc": ["zinc", "zn"],
        "copper": ["copper", "cu"],
        "manganese": ["manganese", "mn"],
        "selenium": ["selenium", "se"],
        "chromium": ["chromium", "cr"],
        "molybdenum": ["molybdenum", "mo"],
        "chloride": ["chloride", "cl"],
        
        // Additional Nutrients
        "cholesterol": ["cholesterol"],
        "caffeine": ["caffeine", "coffee", "stimulant"]
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

struct BubblesView: View {
    let activeNutrients: Set<String>
    let rotationSpeed: Double
    let nutrientValues: [String: Double]
    
    let symbolMapping = [
        "calories": "flame",
        "protein": "fork.knife",
        "carbs": "carrot",
        "fats": "drop",
        "fiber": "leaf.fill",
        "vitamins": "pill",
        "minerals": "bolt",
        "water": "drop.fill",
        "phytochemicals": "leaf.arrow.triangle.circlepath",
        "antioxidants": "shield",
        "electrolytes": "battery.100"
    ]
    
    var activeSymbols: [String] {
        let symbols = activeNutrients.isEmpty ?
            Array(symbolMapping.values) :
            activeNutrients.compactMap { symbolMapping[$0] }
        return symbols.sorted()
    }
    
    @State private var angle: Double = 0
    let timer = Timer.publish(every: 1/480, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let minDimension = min(geometry.size.width, geometry.size.height)
            let radius = minDimension / 3
            let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
            
            ZStack {
                ForEach(Array(activeSymbols.enumerated()), id: \.offset) { index, symbol in
                    let individualAngle = angle + (Double(index) * 2 * .pi / Double(activeSymbols.count))
                    
                    ZStack {
                        Image(systemName: symbol)
                            .font(.system(size: 45))
                            .foregroundStyle(.blue)
                            .animation(.linear(duration: 1/120), value: angle)
                        
                        if let nutrientKey = activeNutrients.first(where: { symbolMapping[$0] == symbol }),
                           let value = nutrientValues[nutrientKey] {
                            Text("\(value, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .padding(4)
                                .background(.blue)
                                .clipShape(Circle())
                                .offset(x: 20, y: -20)
                                .animation(.linear(duration: 1/120), value: angle)
                        }
                    }
                    .position(
                        x: center.x + radius * cos(individualAngle),
                        y: center.y + radius * sin(individualAngle)
                    )
                }
            }
            .onReceive(timer) { _ in
                withAnimation(.linear(duration: 1/120)) {
                    angle += rotationSpeed
                }
            }
        }
    }
}


struct FloatingBubble: View {
    let symbol: String
    let size: CGFloat
    let position: CGPoint
    
    @State private var offset = CGSize.zero
    
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(.blue)
            .position(position)
            .offset(offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 3)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = CGSize(
                        width: CGFloat.random(in: -10...10),
                        height: CGFloat.random(in: -10...10)
                    )
                }
            }
    }
}
