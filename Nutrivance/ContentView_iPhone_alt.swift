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
            
            Tab("Playground", systemImage: "arrow.triangle.2.circlepath") {
                ContentView_iPhone()
            }
            .customizationID("iPhone.tab.alt")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab(role: .search) {
                SearchView()
            }
            .customizationID("iPhone.tab.search")
            
            Tab("Labels", systemImage: "doc.text.viewfinder") {
                NutritionScannerView()
            }
            .customizationID("iPhone.tab.camera")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab("Nutrients", systemImage: "leaf") {
                NutrientListView()
            }
            .customizationID("iPhone.tab.nutrients")
            .defaultVisibility(.hidden, for: .tabBar)
            
            Tab("Log", systemImage: "square.and.pencil") {
                LogView()
            }
            .customizationID("iPhone.tab.log")
            .defaultVisibility(.visible, for: .tabBar)
            
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
                .customizationID("iPhone.tab.mood")
                
                Tab("Journal", systemImage: "book.fill") {
                    ComingSoonView(feature: "Journaling", description: "Document your mental health journey")
                }
                .customizationID("iPhone.tab.journal")
                
                Tab("Resources", systemImage: "questionmark.circle.fill") {
                    ComingSoonView(feature: "Mental Health Resources", description: "Access helpful information and support")
                }
                .customizationID("iPhone.tab.resources")
                
                Tab("Meditation", systemImage: "sparkles") {
                    ComingSoonView(feature: "Meditation", description: "Guided sessions for mental wellness")
                }
                .customizationID("iPhone.tab.meditation")
                
                Tab("Breathing", systemImage: "wind") {
                    ComingSoonView(feature: "Breathing Exercises", description: "Guided breathing techniques")
                }
                .customizationID("iPhone.tab.breathing")
                
                Tab("Sleep", systemImage: "moon.zzz.fill") {
                    ComingSoonView(feature: "Sleep Tracking", description: "Monitor and improve your sleep quality")
                }
                .customizationID("iPhone.tab.sleep")
                
                Tab("Stress", systemImage: "waveform.path.ecg") {
                    ComingSoonView(feature: "Stress Management", description: "Track and manage stress levels")
                }
                .customizationID("iPhone.tab.stress")
            } header: {
                Text("Mental Health")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPhone.tabsection.mentalhealth")
        }
        .tabViewStyle(.sidebarAdaptable)
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
