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
            // Nutrivance Section
            TabSection {
                Tab("Home", systemImage: "house.fill") {
                    HomeView()
                }
                .customizationID("iPad.tab.home")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") {
                    HealthInsightsView()
                }
                .customizationID("iPad.tab.insights")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab("Labels", systemImage: "doc.text.viewfinder") {
                    NutritionScannerView()
                }
                .customizationID("iPad.tab.camera")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab(role: .search) {
                    LogView()
                }
                .customizationID("iPad.tab.search")
            } header: {
                Text("Nutrition")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.nutrition")
            
            // Macronutrients Section
            TabSection {
                Tab("Calories", systemImage: "flame") {
                    NutrientDetailView(nutrientName: "Calories")
                }
                .customizationID("iPad.tab.calories")
                
                Tab("Carbs", systemImage: "carrot") {
                    NutrientDetailView(nutrientName: "Carbs")
                }
                .customizationID("iPad.tab.carbs")
                
                Tab("Protein", systemImage: "fork.knife") {
                    NutrientDetailView(nutrientName: "Protein")
                }
                .customizationID("iPad.tab.protein")
                
                Tab("Fats", systemImage: "drop") {
                    NutrientDetailView(nutrientName: "Fats")
                }
                .customizationID("iPad.tab.fats")
                
                Tab("Water", systemImage: "drop.fill") {
                    NutrientDetailView(nutrientName: "Water")
                }
                .customizationID("iPad.tab.water")
            } header: {
                Text("Macronutrients")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.macronutrients")
            
            // Micronutrients Section
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
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.micronutrients")
            
            // Training Section
            TabSection {
                Tab("Dashboard", systemImage: "gauge.medium") {
                    DashboardView()
                }
                Tab("Today's Plan", systemImage: "calendar") {
                    TodaysPlanView()
                }
                Tab("Workout History", systemImage: "clock.arrow.circlepath") {
                    WorkoutHistoryView()
                }
                Tab("Training Calendar", systemImage: "calendar.badge.clock") {
                    TrainingCalendarView()
                }
                Tab("Form Coach", systemImage: "figure.strengthtraining.traditional") {
                    CoachView()
                }
                Tab("Movement Analysis", systemImage: "figure.run") {
                    MovementAnalysisView()
                }
                Tab("Exercise Library", systemImage: "books.vertical.fill") {
                    ExerciseLibraryView()
                }
                Tab("Program Builder", systemImage: "rectangle.stack.fill.badge.plus") {
                    ProgramBuilderView()
                }
                Tab("Workout Generator", systemImage: "wand.and.stars") {
                    WorkoutGeneratorView()
                }
            } header: {
                Text("Training")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }

            // Recovery Section
            TabSection {
                Tab("Recovery Score", systemImage: "chart.bar.fill") {
                    RecoveryScoreView()
                }
                Tab("Sleep Analysis", systemImage: "bed.double.fill") {
                    SleepAnalysisView()
                }
                Tab("Mobility Test", systemImage: "figure.walk") {
                    MobilityTestView()
                }
                Tab("Readiness", systemImage: "heart.fill") {
                    ReadinessCheckView()
                }
                Tab("Strain vs Recovery", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    StrainRecoveryView()
                }
                Tab("Fuel Check", systemImage: "fork.knife") {
                    FuelCheckView()
                }
            } header: {
                Text("Recovery")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }

            
            // Spirivance Section
            TabSection {
                Tab("Mood Tracker", systemImage: "brain.head.profile") {
                    ComingSoonView(feature: "Mood Tracking", description: "Track and analyze your emotional well-being")
                }
                .customizationID("iPad.tab.mood")
                
                Tab("Journal", systemImage: "book.fill") {
                    ComingSoonView(feature: "Journaling", description: "Document your mental health journey")
                }
                .customizationID("iPad.tab.journal")
                
                Tab("Resources", systemImage: "questionmark.circle.fill") {
                    ComingSoonView(feature: "Mental Health Resources", description: "Access helpful information and support")
                }
                .customizationID("iPad.tab.resources")
                
                Tab("Meditation", systemImage: "sparkles") {
                    ComingSoonView(feature: "Meditation", description: "Guided sessions for mental wellness")
                }
                .customizationID("iPad.tab.meditation")
                
                Tab("Breathing", systemImage: "wind") {
                    ComingSoonView(feature: "Breathing Exercises", description: "Guided breathing techniques")
                }
                .customizationID("iPad.tab.breathing")
                
                Tab("Sleep", systemImage: "moon.zzz.fill") {
                    ComingSoonView(feature: "Sleep Tracking", description: "Monitor and improve your sleep quality")
                }
                .customizationID("iPad.tab.sleep")
                
                Tab("Stress", systemImage: "waveform.path.ecg") {
                    ComingSoonView(feature: "Stress Management", description: "Track and manage stress levels")
                }
                .customizationID("iPad.tab.stress")
            } header: {
                Text("Mental Health")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.mentalhealth")
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}
