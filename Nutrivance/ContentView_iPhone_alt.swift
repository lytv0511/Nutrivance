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
                LogView()
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
            ZStack {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.2),
                        Color(red: 0.03, green: 0.12, blue: 0.08),
                        Color.black
                    ]),
                    center: .bottomTrailing,
                    startRadius: 100,
                    endRadius: 1500
                )
                .opacity(0.85)
                .ignoresSafeArea()
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.02, green: 0.1, blue: 0.15).opacity(0.8),
                        Color.clear
                    ]),
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .ignoresSafeArea()
                List(nutrients, id: \.self) { nutrient in
                    NavigationLink(
                        destination: NutrientDetailView(nutrientName: nutrient)
                            .navigationTransition(.zoom(sourceID: nutrient, in: namespace))
                    ) {
                        HStack {
                            Image(systemName: getNutrientIcon(for: nutrient))
                                .font(.system(size: 24))
                                .foregroundColor(getNutrientColor(for: nutrient))
                            
                            Text(nutrient)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                                .padding()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 20)
                .navigationTitle("Nutrients")
            }
        }
    }
}
