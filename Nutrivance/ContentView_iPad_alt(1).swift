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
    @State private var capturedImage: UIImage?
    
    var body: some View {
        TabView {
            // Nutrivance Section
                Tab("Home", systemImage: "house") {
                    HomeView()
                }
                .customizationID( "iPad.tab.home")
                .defaultVisibility(.visible, for: .tabBar)
            
            TabSection {
                Tab("Nutrivance", systemImage: "leaf") {
                    NutrivanceView()
                }
                .customizationID( "iPad.tab.nutrivance")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab("Movance", systemImage: "figure.run") {
                    MovanceView()
                }
                .customizationID( "iPad.tab.movance")
                .defaultVisibility(.visible, for: .tabBar)
                
                Tab("Spirivance", systemImage: "brain.head.profile") {
                    SpirivanceView()
                }
                .customizationID("iPad.tab.spririvance")
                .defaultVisibility(.visible, for: .tabBar)
            } header: {
                Text("Focus Modes")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .defaultVisibility(.visible, for: .tabBar)
            .customizationID("iPad.tabsection.focusModes")
            
                Tab("Playground", systemImage: "arrow.triangle.2.circlepath") {
                    PlaygroundView()
                }
                .customizationID("iPad.tab.playground")
                .defaultVisibility(.visible, for: .tabBar)
            
               
//            TabSection {
//                Tab("Log", systemImage: "square.and.pencil") {
//                    LogView()
//                }
//                .customizationID("iPad.tab.log")
//                .defaultVisibility(.hidden, for: .tabBar)
//                
//                Tab("Labels", systemImage: "doc.text.viewfinder") {
//                    NutritionScannerView()
//                }
//                .customizationID("iPad.tab.camera")
//                .defaultVisibility(.hidden, for: .tabBar)
//                
//                Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") {
//                    HealthInsightsView()
//                }
//                .customizationID("iPad.tab.insights")
//                .defaultVisibility(.visible, for: .tabBar)
//                
//                Tab("Barcode", systemImage: "barcode.viewfinder") {
//                    BarcodeScannerView()
//                }
//                .customizationID("iPad.tab.barcode")
//                .defaultVisibility(.hidden, for: .tabBar)
//                
//            } header: {
//                Text("Nutrivance Tools")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            .customizationID("iPad.tabsection.nutrivanceTools")
//                
//                Tab(role: .search) {
//                    SearchView()
//                }
//                .customizationID("iPad.tab.search")
//            
//            // Macronutrients Section
//            TabSection {
//            
//                Tab("Calories", systemImage: "flame") {
//                    NutrientDetailView(nutrientName: "Calories")
//                }
//                .customizationID("iPad.tab.calories")
//                
//                Tab("Carbs", systemImage: "carrot") {
//                    NutrientDetailView(nutrientName: "Carbs")
//                }
//                .customizationID("iPad.tab.carbs")
//                
//                Tab("Protein", systemImage: "fork.knife") {
//                    NutrientDetailView(nutrientName: "Protein")
//                }
//                .customizationID("iPad.tab.protein")
//                
//                Tab("Fats", systemImage: "drop") {
//                    NutrientDetailView(nutrientName: "Fats")
//                }
//                .customizationID("iPad.tab.fats")
//                
//                Tab("Water", systemImage: "drop.fill") {
//                    NutrientDetailView(nutrientName: "Water")
//                }
//                .customizationID("iPad.tab.water")
//                
//            } header: {
//                Text("Macronutrients")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            .customizationID("iPad.tabsection.macronutrients")
//            
//            // Micronutrients Section
//            TabSection {
//                Tab("Fiber", systemImage: "leaf.fill") {
//                    NutrientDetailView(nutrientName: "Fiber")
//                }
//                .customizationID("iPad.tab.fiber")
//                
//                Tab("Vitamins", systemImage: "pill") {
//                    NutrientDetailView(nutrientName: "Vitamins")
//                }
//                .customizationID("iPad.tab.vitamins")
//                
//                Tab("Minerals", systemImage: "bolt") {
//                    NutrientDetailView(nutrientName: "Minerals")
//                }
//                .customizationID("iPad.tab.minerals")
//                
//                Tab("Phytochemicals", systemImage: "leaf.arrow.triangle.circlepath") {
//                    NutrientDetailView(nutrientName: "Phytochemicals")
//                }
//                .customizationID("iPad.tab.phytochemicals")
//                
//                Tab("Antioxidants", systemImage: "shield") {
//                    NutrientDetailView(nutrientName: "Antioxidants")
//                }
//                .customizationID("iPad.tab.antioxidants")
//                
//                Tab("Electrolytes", systemImage: "battery.100") {
//                    NutrientDetailView(nutrientName: "Electrolytes")
//                }
//                .customizationID("iPad.tab.electrolytes")
//            } header: {
//                Text("Micronutrients")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
//            .customizationID("iPad.tabsection.micronutrients")
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
//                .customizationID( "iPad.tab.mindfulnessRealm")
//                
//                Tab("Mood Tracker", systemImage: "sun.max") {
//                    MoodTrackerView()
//                }
//                .customizationID("iPad.tab.moodTracker")
//                
//                Tab("Journal", systemImage: "book.fill") {
//                    JournalView()
//                }
//                .customizationID("iPad.tab.journal")
//                
//                Tab("Resources", systemImage: "folder.fill") {
//                    ResourcesView()
//                }
//                .customizationID("iPad.tab.resources")
//                
//                Tab("Meditation", systemImage: "sparkles") {
//                    MeditationView()
//                }
//                .customizationID("iPad.tab.meditation")
//                
//                Tab("Breathing", systemImage: "wind") {
//                    BreathingView()
//                }
//                .customizationID("iPad.tab.breathing")
//                
//                Tab("Sleep", systemImage: "moon.zzz.fill") {
//                    SleepView()
//                }
//                .customizationID("iPad.tab.sleep")
//                
//                Tab("Stress", systemImage: "waveform.path.ecg") {
//                    StressView()
//                }
//                .customizationID("iPad.tab.stress")
//            } header: {
//                Text("Mental Health")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.hidden, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}
