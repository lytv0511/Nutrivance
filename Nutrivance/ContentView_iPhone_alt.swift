//
//  ContentView_iPhone_alt.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/2/24.
//

import SwiftUI

struct ContentView_iPhone_alt: View {
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State var customization = TabViewCustomization()

    
    private let nutrientChoices = [
        "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
        "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"
    ]
    
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            .customizationID("iPhone.tab.home")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") {
                HealthInsightsView()
            }
            .customizationID("iPhone.tab.insights")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab("Labels", systemImage: "doc.text.viewfinder") {
                NutritionScannerView()
            }
            .customizationID("iPhone.tab.camera")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab("Nutrients", systemImage: "leaf") {
                NutrientListView()
            }
            .customizationID("iPhone.tab.nutrients")
        
            Tab(role: .search) {
                SearchView()
            }
            .customizationID("iPhone.tab.search")
        }
        .tabViewCustomization($customization)
    }
}

struct NutrientListView: View {
    let nutrients = ["Carbs", "Protein", "Fats", "Calories", "Fiber", "Vitamins", "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
    @Namespace private var namespace

    var body: some View {
            NavigationStack {
                List(nutrients, id: \.self) { nutrient in
                    NavigationLink(
                        destination: NutrientDetailView(nutrientName: nutrient)
                            .navigationTransition(.zoom(sourceID: nutrient, in: namespace)) // Use `nutrient` as unique ID
                    ) {
                        HStack {
                            Image(systemName: getNutrientIcon(for: nutrient))
                                .font(.system(size: 24)) // Larger icon size
                                .foregroundColor(getNutrientColor(for: nutrient))
                            
                            Text(nutrient)
                                .font(.system(size: 18, weight: .bold)) // Bold and larger text
                                .foregroundColor(.primary)
                                .padding()
                        }
                    }
                }
                .navigationTitle("Nutrients")
            }
        }
    
    // Icon fetching function
    private func getNutrientIcon(for nutrient: String) -> String {
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

    // Color fetching function
    private func getNutrientColor(for nutrient: String) -> Color {
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
}
