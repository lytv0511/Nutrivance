//
//  ContentView_iPhone_alt.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/2/24.
//

//
//  ContentView_iPad_alt.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/2/24.
//

import SwiftUI

struct ContentView_iPhone_alt: View {
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var capturedImage: UIImage?
    
    var body: some View {
        TabView {
            // Nutrivance Section
                Tab("Home", systemImage: "house") {
//                    HomeView()
                    SleepView()
                }
                .customizationID( "iPhone.tab.home")
                .defaultVisibility(.visible, for: .tabBar)
            
                Tab("Playground", systemImage: "arrow.triangle.2.circlepath") {
                    PlaygroundView()
                }
                .customizationID("iPhone.tab.playground")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab(role: .search) {
                    SearchView_iPhone()
                }
                .customizationID("iPhone.tab.searchiPhone")
                
//            TabSection {
//                Tab("Nutrivance", systemImage: "leaf") {
//                    NutrivanceView()
//                }
//                .customizationID( "iPhone.tab.nutrivance")
//                .defaultVisibility(.visible, for: .tabBar)
//                
//                Tab("Movance", systemImage: "figure.run") {
//                    MovanceView()
//                }
//                .customizationID( "iPhone.tab.movance")
//                .defaultVisibility(.visible, for: .tabBar)
//                
//                Tab("Spirivance", systemImage: "brain.head.profile") {
//                    SpirivanceView()
//                }
//                .customizationID("iPhone.tab.spririvance")
//                .defaultVisibility(.visible, for: .tabBar)
//            } header: {
//                Text("Focus Modes")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.visible, for: .tabBar)
//            .customizationID("iPhone.tabsection.focusModes")
               
//            TabSection {
//                Tab("Log", systemImage: "square.and.pencil") {
//                    LogView()
//                }
//                .customizationID("iPhone.tab.log")
//                .defaultVisibility(.hidden, for: .tabBar)
//                
//                Tab("Labels", systemImage: "doc.text.viewfinder") {
//                    NutritionScannerView()
//                }
//                .customizationID("iPhone.tab.camera")
//                .defaultVisibility(.hidden, for: .tabBar)
//                
//                Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") {
//                    HealthInsightsView()
//                }
//                .customizationID("iPhone.tab.insights")
//                .defaultVisibility(.visible, for: .tabBar)
//                
//            } header: {
//                Text("Nutrivance Tools")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            .customizationID("iPhone.tabsection.nutrivanceTools")
//
//            
//            // Macronutrients Section
//            TabSection {
//            
//                Tab("Calories", systemImage: "flame") {
//                    NutrientDetailView(nutrientName: "Calories")
//                }
//                .customizationID("iPhone.tab.calories")
//                
//                Tab("Carbs", systemImage: "carrot") {
//                    NutrientDetailView(nutrientName: "Carbs")
//                }
//                .customizationID("iPhone.tab.carbs")
//                
//                Tab("Protein", systemImage: "fork.knife") {
//                    NutrientDetailView(nutrientName: "Protein")
//                }
//                .customizationID("iPhone.tab.protein")
//                
//                Tab("Fats", systemImage: "drop") {
//                    NutrientDetailView(nutrientName: "Fats")
//                }
//                .customizationID("iPhone.tab.fats")
//                
//                Tab("Water", systemImage: "drop.fill") {
//                    NutrientDetailView(nutrientName: "Water")
//                }
//                .customizationID("iPhone.tab.water")
//                
//            } header: {
//                Text("Macronutrients")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            .customizationID("iPhone.tabsection.macronutrients")
//            
//            // Micronutrients Section
//            TabSection {
//                Tab("Fiber", systemImage: "leaf.fill") {
//                    NutrientDetailView(nutrientName: "Fiber")
//                }
//                .customizationID("iPhone.tab.fiber")
//                
//                Tab("Vitamins", systemImage: "pill") {
//                    NutrientDetailView(nutrientName: "Vitamins")
//                }
//                .customizationID("iPhone.tab.vitamins")
//                
//                Tab("Minerals", systemImage: "bolt") {
//                    NutrientDetailView(nutrientName: "Minerals")
//                }
//                .customizationID("iPhone.tab.minerals")
//                
//                Tab("Phytochemicals", systemImage: "leaf.arrow.triangle.circlepath") {
//                    NutrientDetailView(nutrientName: "Phytochemicals")
//                }
//                .customizationID("iPhone.tab.phytochemicals")
//                
//                Tab("Antioxidants", systemImage: "shield") {
//                    NutrientDetailView(nutrientName: "Antioxidants")
//                }
//                .customizationID("iPhone.tab.antioxidants")
//                
//                Tab("Electrolytes", systemImage: "battery.100") {
//                    NutrientDetailView(nutrientName: "Electrolytes")
//                }
//                .customizationID("iPhone.tab.electrolytes")
//            } header: {
//                Text("Micronutrients")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            .customizationID("iPhone.tabsection.micronutrients")
//            
//            // Training Section
//            TabSection {
//                Tab("Dashboard", systemImage: "gauge.medium") {
//                    DashboardView()
//                }
//                Tab("Today's Plan", systemImage: "calendar") {
//                    TodaysPlanView()
//                }
//                Tab("Workout History", systemImage: "clock.arrow.circlepath") {
//                    WorkoutHistoryView()
//                }
//                Tab("Training Calendar", systemImage: "calendar.badge.clock") {
//                    TrainingCalendarView()
//                }
//                Tab("Coach", systemImage: "figure.strengthtraining.traditional") {
//                    CoachView()
//                }
//                Tab("Movement Analysis", systemImage: "figure.run") {
//                    MovementAnalysisView()
//                }
//                Tab("Exercise Library", systemImage: "books.vertical.fill") {
//                    ExerciseLibraryView()
//                }
//                Tab("Program Builder", systemImage: "rectangle.stack.fill.badge.plus") {
//                    ProgramBuilderView()
//                }
//                Tab("Workout Generator", systemImage: "wand.and.stars") {
//                    WorkoutGeneratorView()
//                }
//            } header: {
//                Text("Training")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            
//            // Recovery Section
//            TabSection {
//                Tab("Recovery Score", systemImage: "chart.bar.fill") {
//                    RecoveryScoreView()
//                }
//                Tab("Sleep Analysis", systemImage: "bed.double.fill") {
//                    SleepAnalysisView()
//                }
//                Tab("Mobility Test", systemImage: "figure.walk") {
//                    MobilityTestView()
//                }
//                Tab("Readiness", systemImage: "heart.fill") {
//                    ReadinessCheckView()
//                }
//                Tab("Strain vs Recovery", systemImage: "gauge.with.dots.needle.bottom.50percent") {
//                    StrainRecoveryView()
//                }
//                Tab("Fuel Check", systemImage: "fork.knife") {
//                    FuelCheckView()
//                }
//            } header: {
//                Text("Recovery")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            
//            // Spirivance Section
//            TabSection {
//                Tab("Mindfulness Realm", systemImage: "eye.fill") {
//                    MindfulnessRealmView()
//                }
//                .customizationID( "iPhone.tab.mindfulnessRealm")
//                
//                Tab("Mood Tracker", systemImage: "sun.max") {
//                    MoodTrackerView()
//                }
//                .customizationID("iPhone.tab.moodTracker")
//                
//                Tab("Journal", systemImage: "book.fill") {
//                    JournalView()
//                }
//                .customizationID("iPhone.tab.journal")
//                
//                Tab("Resources", systemImage: "folder.fill") {
//                    ResourcesView()
//                }
//                .customizationID("iPhone.tab.resources")
//                
//                Tab("Meditation", systemImage: "sparkles") {
//                    MeditationView()
//                }
//                .customizationID("iPhone.tab.meditation")
//                
//                Tab("Breathing", systemImage: "wind") {
//                    BreathingView()
//                }
//                .customizationID("iPhone.tab.breathing")
//                
//                Tab("Sleep", systemImage: "moon.zzz.fill") {
//                    SleepView()
//                }
//                .customizationID("iPhone.tab.sleep")
//                
//                Tab("Stress", systemImage: "waveform.path.ecg") {
//                    StressView()
//                }
//                .customizationID("iPhone.tab.stress")
//            } header: {
//                Text("Mental Health")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
            
            .defaultVisibility(.hidden, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}
