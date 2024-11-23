//
//  ContentView_iPad_alt.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/2/24.
//

import SwiftUI

struct ContentView_iPad_alt: View {
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    private let detector = NutritionTableDetector()
    @State private var capturedImage: UIImage?

    let nutrientDetails: [String: NutrientInfo] = [
        "Carbs": NutrientInfo(
            todayConsumption: "0 g",
            weeklyConsumption: "1.4kg",
            monthlyConsumption: "6kg",
            recommendedIntake: "45-65% of total calories",
            foodsRichInNutrient: "Bread, Pasta, Rice",
            benefits: "Provides energy, aids in digestion."
        ),
        "Protein": NutrientInfo(
            todayConsumption: "50g",
            weeklyConsumption: "350g",
            monthlyConsumption: "1.5kg",
            recommendedIntake: "10-35% of total calories",
            foodsRichInNutrient: "Meat, Beans, Nuts",
            benefits: "Essential for muscle repair and growth."
        ),
        "Fats": NutrientInfo(
            todayConsumption: "70g",
            weeklyConsumption: "490g",
            monthlyConsumption: "2.1kg",
            recommendedIntake: "20-35% of total calories",
            foodsRichInNutrient: "Oils, Nuts, Avocados",
            benefits: "Supports cell growth, provides energy."
        ),
        "Calories": NutrientInfo(
            todayConsumption: "2000 kcal",
            weeklyConsumption: "14000 kcal",
            monthlyConsumption: "60000 kcal",
            recommendedIntake: "Varies based on activity level",
            foodsRichInNutrient: "All foods contribute calories",
            benefits: "Essential for energy."
        ),
        // New categories
        "Fiber": NutrientInfo(
            todayConsumption: "25g",
            weeklyConsumption: "175g",
            monthlyConsumption: "750g",
            recommendedIntake: "25g for women, 38g for men",
            foodsRichInNutrient: "Fruits, Vegetables, Whole Grains",
            benefits: "Aids digestion, helps maintain a healthy weight."
        ),
        "Vitamins": NutrientInfo(
            todayConsumption: "A, C, D, E",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Varies by vitamin",
            foodsRichInNutrient: "Fruits, Vegetables, Dairy",
            benefits: "Supports immune function, promotes vision."
        ),
        "Minerals": NutrientInfo(
            todayConsumption: "Iron, Calcium",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Varies by mineral",
            foodsRichInNutrient: "Meat, Dairy, Leafy Greens",
            benefits: "Supports bone health, aids in oxygen transport."
        ),
        "Water": NutrientInfo(
            todayConsumption: "2L",
            weeklyConsumption: "14L",
            monthlyConsumption: "60L",
            recommendedIntake: "8 cups per day",
            foodsRichInNutrient: "Water, Fruits, Vegetables",
            benefits: "Essential for hydration, regulates body temperature."
        ),
        "Phytochemicals": NutrientInfo(
            todayConsumption: "Varies",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Include colorful fruits and vegetables",
            foodsRichInNutrient: "Berries, Green Tea, Nuts",
            benefits: "Antioxidant properties, may reduce disease risk."
        ),
        "Antioxidants": NutrientInfo(
            todayConsumption: "Varies",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Include a variety of foods",
            foodsRichInNutrient: "Berries, Dark Chocolate, Spinach",
            benefits: "Protects cells from damage, supports overall health."
        ),
        "Electrolytes": NutrientInfo(
            todayConsumption: "Sodium, Potassium",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Sodium: <2300 mg, Potassium: 3500 mg",
            foodsRichInNutrient: "Bananas, Salt, Coconut Water",
            benefits: "Regulates fluid balance, supports muscle function."
        )
    ]
    
    var body: some View {
        TabView {
                Tab("Home", systemImage: "house.fill") {
                    HomeView()
                }
                .customizationID("iPad.tab.home")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab("Water", systemImage: "drop.fill") {
                    NutrientDetailView(nutrientName: "Water")
                }
                .customizationID("iPad.tab.water")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab("Labels", systemImage: "doc.text.viewfinder") {
                    NutritionScannerView()
                }
                .customizationID("iPad.tab.camera")
                .defaultVisibility(.visible, for: .tabBar)
            
                Tab(role: .search) {
                    SearchView()
                }
                .customizationID("iPad.tab.search")
            
            TabSection {
                Tab("Calories", systemImage: "flame") {
                    NutrientDetailView(nutrientName: "Calories")
                }
                .customizationID("iPad.tab.calories")
                .defaultVisibility(.hidden, for: .tabBar)
                
                Tab("Carbs", systemImage: "carrot") {
                    NutrientDetailView(nutrientName: "Carbs")
                }
                .customizationID("iPad.tab.carbs")
                .defaultVisibility(.hidden, for: .tabBar)
                
                Tab("Protein", systemImage: "fork.knife") {
                    NutrientDetailView(nutrientName: "Protein")
                }
                .customizationID("iPad.tab.protein")
                .defaultVisibility(.hidden, for: .tabBar)
                
                Tab("Fats", systemImage: "drop") {
                    NutrientDetailView(nutrientName: "Fats")
                }
                .customizationID("iPad.tab.fats")
                .defaultVisibility(.hidden, for: .tabBar)
            } header: {
                Text("Macronutrients")
                    .font(.headline)
                    .padding(.leading, 16) // Add padding to the left
                    .padding(.top, 8) // Add padding to the top
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.macronutrients") // Custom ID for Micronutrient Section
            
            TabSection {
                Tab("Fiber", systemImage: "leaf.fill") {
                    NutrientDetailView(nutrientName: "Fiber")
                }
                .customizationID("iPad.tab.fiber")
                
                Tab("Vitamins", systemImage: "pill") {
                    NutrientDetailView(nutrientName: "Vitamins")
                }
                .customizationID("iPad.tab.vitamins")
                
                Tab("Minerals", systemImage: "bolt") {
                    NutrientDetailView(nutrientName: "Minerals")
                }
                .customizationID("iPad.tab.minerals")
                
                Tab("Phytochemicals", systemImage: "leaf.arrow.triangle.circlepath") {
                    NutrientDetailView(nutrientName: "Phytochemicals")
                }
                .customizationID("iPad.tab.phytochemicals")
                
                Tab("Antioxidants", systemImage: "shield") {
                    NutrientDetailView(nutrientName: "Antioxidants")
                }
                .customizationID("iPad.tab.antioxidants")
                
                Tab("Electrolytes", systemImage: "battery.100") {
                    NutrientDetailView(nutrientName: "Electrolytes")
                }
                .customizationID("iPad.tab.electrolytes")
            } header: {
                Text("Micronutrients")
                    .font(.headline)
                    .padding(.leading, 16) // Add padding to the left
                    .padding(.top, 8) // Add padding to the top
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.micronutrients") // Custom ID for Micronutrient Section
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}
