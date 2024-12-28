//
//  GoalsView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 12/16/24.
//

import Foundation
import SwiftUI
import HealthKit

struct GoalsView: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var goals: [NutritionGoal] = []
    @State private var showingAddGoal = false
    
    var body: some View {
        NavigationStack {
            
            List {
                ForEach(goals) { goal in
                    GoalCard(goal: goal)
                }
                .onDelete(perform: deleteGoal)
                
                Button(action: { showingAddGoal = true }) {
                    Label("Add New Goal", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Nutrition Goals")
        .sheet(isPresented: $showingAddGoal) {
            AddGoalView(goals: $goals)
        }
        .onAppear {
            loadGoals()
            updateGoalProgress()
        }
    }
    
    private func loadGoals() {
        if let data = UserDefaults.standard.data(forKey: "savedGoals"),
           let savedGoals = try? JSONDecoder().decode([NutritionGoal].self, from: data) {
            goals = savedGoals
        }
    }
    
    private func saveGoals() {
        if let encoded = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(encoded, forKey: "savedGoals")
        }
    }
    
    private func updateGoalProgress() {
        for (index, goal) in goals.enumerated() {
            healthStore.fetchNutrientData(for: goal.nutrient.lowercased()) { value, error in
                if let value = value {
                    DispatchQueue.main.async {
                        goals[index].currentValue = value
                        saveGoals()
                    }
                }
            }
        }
    }
    
    private func deleteGoal(at offsets: IndexSet) {
        goals.remove(atOffsets: offsets)
        saveGoals()
    }
}

struct NutritionGoal: Identifiable, Codable {
    let id = UUID()
    var nutrient: String
    var target: Double
    var currentValue: Double
    var unit: String
    var deadline: Date
}

struct GoalCard: View {
    let goal: NutritionGoal
    
    var progress: Double {
        min(goal.currentValue / goal.target, 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(goal.nutrient)
                .font(.headline)
            
            ProgressView(value: progress) {
                Text("\(Int(progress * 100))%")
            }
            
            HStack {
                Text("\(goal.currentValue, specifier: "%.1f")/\(goal.target, specifier: "%.1f") \(goal.unit)")
                Spacer()
                Text("Due: \(goal.deadline, style: .date)")
                    .font(.caption)
            }
        }
        .padding()
    }
}

struct AddGoalView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var goals: [NutritionGoal]
    @State private var selectedNutrient = "Protein"
    @State private var targetValue = ""
    @State private var deadline = Date()
    
    let nutrients = [
        "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins", "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"
    ]
    var body: some View {
        NavigationStack {
            Form {
                Section("Nutrient") {
                    Picker("Select Nutrient", selection: $selectedNutrient) {
                        ForEach(nutrients, id: \.self) { nutrient in
                            Text(nutrient)
                                .foregroundColor(getNutrientColor(for: nutrient))
                        }
                    }
                }
                Section("Target") {
                    HStack {
                        TextField("Target Value", text: $targetValue)
                            .keyboardType(.decimalPad)
                        Text(NutritionUnit.getUnit(for: selectedNutrient))
                    }
                }
                Section("Deadline") {
                    DatePicker("Target Date", selection: $deadline, displayedComponents: .date)
                }
            }
            .navigationTitle("New Goal")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") { saveGoal() }
            )
        }
    }
    private func saveGoal() {
       guard let target = Double(targetValue) else { return }
       
       let newGoal = NutritionGoal(
           nutrient: selectedNutrient,
           target: target,
           currentValue: 0,
           unit: NutritionUnit.getUnit(for: selectedNutrient),
           deadline: deadline
       )
       
       goals.append(newGoal)
       
       // Save to UserDefaults right after adding the new goal
       if let encoded = try? JSONEncoder().encode(goals) {
           UserDefaults.standard.set(encoded, forKey: "savedGoals")
       }
       
       dismiss()
   }
}
