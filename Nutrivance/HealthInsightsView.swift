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
    
    enum TimeFrame: String, CaseIterable {
        case daily = "Today"
        case weekly = "This Week"
        case monthly = "This Month"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Health Insights")
                        .font(.largeTitle)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
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
                }
            }
        }
        .onAppear {
            fetchDataForTimeFrame()
        }
    }
    
    struct QuickActionButtons: View {
        let nutrientData: [String: Double]
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
        
        var body: some View {
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
                ("View History", "clock.fill", "Track your nutrition trends"),
                ("Set Goals", "target", "Manage nutrition targets"),
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
        var data: [String: Double] = [:]
        
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
        var aggregatedData: [String: Double] = [:]
        
        let group = DispatchGroup()
        
        for nutrient in nutrients {
            group.enter()
            // Update the fetchNutrientData calls
            // Inside fetchHistoricalData function
            healthStore.fetchNutrientData(for: nutrient) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        nutrientValues[nutrient] = result
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            nutrientData = aggregatedData
            analysisService.analyzeNutrientData(aggregatedData)
        }
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

struct NutrientCharts: View {
    let data: [String: Double]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Nutrient Distribution")
                .font(.headline)
                .padding(.horizontal)
            
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(
                    Text("Nutrient Charts Coming Soon")
                        .foregroundColor(.gray)
                )
                .padding(.horizontal)
        }
    }
}

struct GoalsView: View {
    var body: some View {
        Text("Goals Coming Soon")
    }
}

struct TipsView: View {
    var body: some View {
        Text("Tips Coming Soon")
    }
}
