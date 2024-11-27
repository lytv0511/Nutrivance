//
//  HistoryView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/27/24.
//

import Foundation
import SwiftUI

struct HistoryView: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var selectedTimeFrame: TimeFrame = .daily
    @State private var entries: [HealthKitManager.NutritionEntry] = []
    @State private var selectedDate: Date = Date()
    
    enum TimeFrame {
        case daily, weekly, monthly, custom
    }
    
    private var groupedEntries: [Date: [HealthKitManager.NutritionEntry]] {
        Dictionary(grouping: entries) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                timeFramePicker
                dateSelector
                entriesList
            }
            .navigationTitle("Nutrition History")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadData()
            }
            .onChange(of: selectedTimeFrame) { oldValue, newValue in
                loadData()
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                loadData()
            }
        }
    }
    
    private var timeFramePicker: some View {
        Picker("Time Frame", selection: $selectedTimeFrame) {
            Text("Daily").tag(TimeFrame.daily)
            Text("Weekly").tag(TimeFrame.weekly)
            Text("Monthly").tag(TimeFrame.monthly)
            Text("Custom").tag(TimeFrame.custom)
        }
        .pickerStyle(.segmented)
        .padding()
    }
    
    private var dateSelector: some View {
        DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .frame(maxHeight: 300)
            .padding()
    }
    
    private var entriesList: some View {
        List {
            let sortedDates = groupedEntries.keys.sorted(by: >)
            ForEach(sortedDates, id: \.self) { date in
                Section {
                    let entries = groupedEntries[date] ?? []
                    ForEach(entries) { entry in
                        NutritionEntryRow(entry: entry) {
                            deleteEntry(entry)
                        }
                    }
                } header: {
                    Text(formatDate(date))
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func deleteEntry(_ entry: HealthKitManager.NutritionEntry) {
        withAnimation {
            healthStore.deleteNutrientData(for: entry.id) { success in
                if success {
                    entries.removeAll { $0.id == entry.id }
                    loadData()
                }
            }
        }
    }
    
    private func loadData() {
        let calendar = Calendar.current
        var startDate: Date
        let endDate = calendar.endOfDay(for: selectedDate)
        
        switch selectedTimeFrame {
        case .daily:
            startDate = calendar.startOfDay(for: selectedDate)
        case .weekly:
            startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        case .monthly:
            startDate = calendar.date(byAdding: .month, value: -1, to: endDate)!
        case .custom:
            startDate = calendar.date(byAdding: .day, value: -14, to: endDate)!
        }
        
        healthStore.fetchNutrientHistory(from: startDate, to: endDate) { fetchedEntries in
            entries = fetchedEntries
        }
    }
}

struct NutritionEntryRow: View {
    let entry: HealthKitManager.NutritionEntry
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(entry.mealType ?? "Meal")
                    .font(.headline)
                Spacer()
                Text(entry.timestamp, style: .time)
                    .foregroundColor(.secondary)
            }
            
            ForEach(Array(entry.nutrients.keys.sorted()), id: \.self) { nutrient in
                if let value = entry.nutrients[nutrient] {
                    Text("\(nutrient.capitalized): \(value, specifier: "%.1f")")
                        .font(.subheadline)
                }
            }
            
            HStack {
                Image(systemName: sourceIcon)
                Text(sourceLabel)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var sourceIcon: String {
        switch entry.source {
        case .scanner: return "doc.text.viewfinder"
        case .search: return "text.bubble"
        case .savedMeal: return "star"
        }
    }
    
    private var sourceLabel: String {
        switch entry.source {
        case .scanner: return "Scanned"
        case .search: return "Search"
        case .savedMeal: return "Saved Meal"
        }
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfDay(for: date))!
    }
}

