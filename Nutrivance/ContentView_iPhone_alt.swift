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
    @EnvironmentObject var navigationState: NavigationState
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var capturedImage: UIImage?

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .insights:
            HealthInsightsView()
        case .labels:
            NutritionScannerView()
        case .log:
            LogView()
        case .calories:
            NutrientDetailView(nutrientName: "Calories")
        case .carbs:
            NutrientDetailView(nutrientName: "Carbs")
        case .protein:
            NutrientDetailView(nutrientName: "Protein")
        case .fats:
            NutrientDetailView(nutrientName: "Fats")
        case .water:
            NutrientDetailView(nutrientName: "Water")
        case .fiber:
            NutrientDetailView(nutrientName: "Fiber")
        case .vitamins:
            NutrientDetailView(nutrientName: "Vitamins")
        case .minerals:
            NutrientDetailView(nutrientName: "Minerals")
        case .phytochemicals:
            NutrientDetailView(nutrientName: "Phytochemicals")
        case .antioxidants:
            NutrientDetailView(nutrientName: "Antioxidants")
        case .electrolytes:
            NutrientDetailView(nutrientName: "Electrolytes")
        case .todaysPlan:
            TodaysPlanView(planType: .all)
        case .trainingCalendar:
            TrainingCalendarView()
        case .coach:
            CoachView()
        case .recoveryScore:
            RecoveryScoreView()
        case .readiness:
            ReadinessCheckView()
        case .strainRecovery:
            StrainRecoveryView()
        case .workoutHistory:
            WorkoutHistoryView()
        case .activityRings:
            ActivityRingsView()
        case .heartZones:
            HeartZonesView()
        case .pastQuests:
            PastQuestsView()
        case .mindfulnessRealm:
            MindfulnessRealmView()
        case .moodTracker:
            MoodTrackerView()
        case .journal:
            JournalView()
        case .sleep:
            SleepView()
        case .stress:
            StressView()
        }
    }
    
    var body: some View {
        TabView(selection: $navigationState.selectedRootTab) {
            // Nutrivance Section
            Tab("Dash", systemImage: "gauge.medium", value: RootTabSelection.dashboard) {
                    DashboardView()
                }
                .customizationID( "iPhone.tab.dash")
                .defaultVisibility(.visible, for: .tabBar)
            
                Tab("Realm", systemImage: "eye.fill", value: RootTabSelection.mindfulnessRealm) {
                    MindfulnessRealmView()
                }
                .customizationID( "iPhone.tab.realm")
                .defaultVisibility(.visible, for: .tabBar)
            
//                Tab("Macros", systemImage: "chart.line.uptrend.xyaxis", value: RootTabSelection.insights) {
//                    HealthInsightsView()
//                }
//                .customizationID( "iPad.tab.macros")
//                .defaultVisibility(.visible, for: .tabBar)
//                .customizationBehavior(.disabled, for: .sidebar)
            
                Tab("Workout", systemImage: "figure.run", value: RootTabSelection.programBuilder) {
                    NavigationStack {
                        ProgramBuilderView()
                    }
                }
                .customizationID( "iPhone.tab.builder")
                .defaultVisibility(.visible, for: .tabBar)
                .customizationBehavior(.disabled, for: .sidebar)
                
                Tab(value: RootTabSelection.search, role: .search) {
                    SearchView_iPhone()
                }
                .customizationID("iPhone.tab.searchiPhone")
                .defaultVisibility(.hidden, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .fullScreenCover(item: $navigationState.presentedDestination) { destination in
            NavigationStack {
                destinationView(for: destination)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                navigationState.presentedDestination = nil
                            }
                        }
                    }
            }
        }
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}
