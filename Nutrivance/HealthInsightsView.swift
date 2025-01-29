//
//  HealthInsightsView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/27/24.
//

import Foundation
import SwiftUI

struct HealthInsightsView: View {
    @StateObject private var healthStore = HealthKitManager()
    @StateObject private var analysisService = HealthAnalysisService()
    @State private var nutrientData: [String: Double] = [:]
    @State private var selectedTimeFrame: TimeFrame = .daily
    @State private var nutrientValues: [String: Double] = [:]
    @EnvironmentObject var navigationState: NavigationState
    @Environment(\.dismiss) private var dismiss
    
    enum TimeFrame: String, CaseIterable {
        case daily = "Today"
        case weekly = "This Week"
        case monthly = "This Month"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Mesh Gradient
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.1, blue: 0.2),  // Very dark blue
                        Color(red: 0.02, green: 0.15, blue: 0.05), // Very dark green
                        Color.black
                    ]),
                    center: .topLeading,
                    startRadius: 200,
                    endRadius: 1500
                )
                .opacity(0.9)
                .ignoresSafeArea()
                
                // Overlay gradient for depth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.0, green: 0.08, blue: 0.12).opacity(0.7),
                        Color.clear
                    ]),
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()
                ScrollView {
                    VStack {
                        Text(timeBasedGreeting() + ", learn more about your health")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                        Picker("Time Frame", selection: $selectedTimeFrame) {
                            ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                                Text(timeFrame.rawValue).tag(timeFrame)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .onChange(of: selectedTimeFrame) { oldValue, newValue in
                            fetchDataForTimeFrame()
                        }
                        
                        if analysisService.isAnalyzing {
                            ProgressView("Analyzing your nutrition data...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        
                        if !analysisService.insights.isEmpty {
                            InsightCard(insight: analysisService.insights)
                        }
                        
                        QuickActionButtons(nutrientData: nutrientData)
                        
                        NutrientCharts(data: nutrientData)
                            .padding()
                    }
                }
            }
            .onAppear {
                fetchDataForTimeFrame()
            }
            .navigationTitle(Text("Health Insights"))
        }
//        .toolbar {
//           ToolbarItem(placement: .navigationBarTrailing) {
//               Button(action: { dismiss() }) {
//                   Image(systemName: "keyboard")
//               }
//               .keyboardShortcut("[", modifiers: .command)
//           }
//       }
        .onDisappear {
            navigationState.setDismissAction {
                dismiss()
            }
        }
        .onAppear {
            navigationState.clearDismissAction()
        }
    }
    
    struct QuickActionButtons: View {
        let nutrientData: [String: Double]
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
        
        var body: some View {
            Text("Action Buttons")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 25)
            Group {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 20) {
                        ForEach(actionButtons, id: \.title) { button in
                            NavigationLink(destination: destinationView(for: button.title)) {
                                HStack {
                                    Image(systemName: button.icon)
                                        .font(.title)
                                    VStack(alignment: .leading) {
                                        Text(button.title)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(button.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                            }
                            .hoverEffect(.lift)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(actionButtons, id: \.title) { button in
                            NavigationLink(destination: destinationView(for: button.title)) {
                                VStack {
                                    Image(systemName: button.icon)
                                        .font(.title2)
                                    Text(button.title)
                                        .font(.caption)
                                }
                                .frame(height: 80)
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                            }
                            .hoverEffect(.lift)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        
        private var actionButtons: [(title: String, icon: String, description: String)] {
            [
                ("Log Meal", "plus.circle.fill", "Quick access to saved meals"),
                ("View History", "clock.fill", "Easily track your nutrition trends"),
                ("Set Goals", "target", "Effectively manage nutrition targets"),
                ("Get Tips", "lightbulb.fill", "Personalized recommendations")
            ]
        }
        
        private func destinationView(for buttonTitle: String) -> some View {
            switch buttonTitle {
            case "Log Meal":
                return AnyView(SavedMealsView())
            case "View History":
                return AnyView(HistoryView())
            case "Set Goals":
                return AnyView(GoalsView())
            case "Get Tips":
                return AnyView(TipsView())
            default:
                return AnyView(EmptyView())
            }
        }
    }
    
    private func fetchDataForTimeFrame() {
        switch selectedTimeFrame {
        case .daily:
            fetchTodayData()
        case .weekly:
            fetchWeekData()
        case .monthly:
            fetchMonthData()
        }
    }
    
    private func fetchTodayData() {
        let nutrients = ["calories", "protein", "carbs", "fats", "water"]
        let data = [String: Double]()
        let _: [String: Double] = [:]
        
        let group = DispatchGroup()
        
        for nutrient in nutrients {
            group.enter()
            // Update the fetchNutrientData calls
            healthStore.fetchNutrientData(for: nutrient) { value, error in
                if let value = value {
                    DispatchQueue.main.async {
                        nutrientValues[nutrient] = value
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            nutrientData = data
            analysisService.analyzeNutrientData(data)
        }
    }
    
    private func fetchWeekData() {
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        fetchHistoricalData(from: weekAgo, to: today)
    }
    
    private func fetchMonthData() {
        let calendar = Calendar.current
        let today = Date()
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: today)!
        
        fetchHistoricalData(from: monthAgo, to: today)
    }
    
    private func fetchHistoricalData(from startDate: Date, to endDate: Date) {
        let nutrients = ["calories", "protein", "carbs", "fats", "water"]
        let group = DispatchGroup()
        
        for nutrient in nutrients {
            group.enter()
            healthStore.fetchNutrientData(for: nutrient) { value, error in
                if value != nil {
                    DispatchQueue.main.async {
                        // Update UI or data model here
                        updateNutrientData(nutrient: nutrient, value: value!)
                    }
                }
                group.leave()
            }
        }
    }

    private func updateNutrientData(nutrient: String, value: Double) {
        // Handle the nutrient value update
        nutrientData[nutrient] = value
    }
}

struct InsightCard: View {
    let insight: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis Results")
                .font(.headline)
            Text(insight)
                .font(.body)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
        .padding(.horizontal)
    }
}

struct TipsView: View {
    var body: some View {
        Text("Tips Coming Soon")
    }
}

private func timeBasedGreeting() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<12:
        return "Good Morning"
    case 12..<17:
        return "Good Afternoon"
    case 17..<21:
        return "Good Evening"
    default:
        return "Good Night"
    }
}
