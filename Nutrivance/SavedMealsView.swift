//
//  SavedMealsView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/27/24.
//

import Foundation
import SwiftUI

struct SavedMeal: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: MealCategory
    var nutrients: [String: Double]
    var frequency: String?
    var isFavorite: Bool
    var lastUsed: Date
    
    enum MealCategory: String, Codable, CaseIterable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"
    }
}

class SavedMealsManager: ObservableObject {
    @Published var savedMeals: [SavedMeal] = []
    private let saveKey = "savedMeals"
    
    init() {
        loadFromDisk()
    }
    
    private func saveToDisk() {
        if let encoded = try? JSONEncoder().encode(savedMeals) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([SavedMeal].self, from: data) {
            savedMeals = decoded
        }
    }
    
    func addMeal(_ meal: SavedMeal) {
        savedMeals.append(meal)
        saveToDisk()
    }
    
    func logMeal(_ meal: SavedMeal) {
        let healthStore = HealthKitManager()
        healthStore.saveNutrients(meal.nutrients.map {
            NutrientData(name: $0.key, value: $0.value, unit: NutritionUnit.getUnit(for: $0.key))
        }) { success in
            if success {
                if let index = self.savedMeals.firstIndex(where: { $0.id == meal.id }) {
                    self.savedMeals[index].lastUsed = Date()
                    self.saveToDisk()
                }
            }
        }
    }
    
    func deleteMeal(_ meal: SavedMeal) {
        savedMeals.removeAll { $0.id == meal.id }
        saveToDisk()
    }
}

struct SavedMealsView: View {
    @StateObject private var mealsManager = SavedMealsManager()
    @State private var showingAddMeal = false
    @State private var selectedCategory: SavedMeal.MealCategory?
    @State private var mealToEdit: SavedMeal?
    
    var body: some View {
//        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Saved Meals")
                        .font(.largeTitle)
                        .bold()
                    
                    Spacer()
                    
                    Button(action: { showingAddMeal = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .hoverEffect(.lift)
                }
                .padding()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        CategoryButton(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        
                        ForEach(SavedMeal.MealCategory.allCases, id: \.self) { category in
                            CategoryButton(title: category.rawValue,
                                           isSelected: selectedCategory == category) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding()
                }
                
                ScrollView {
                    LazyVStack(spacing: 15) {
                        ForEach(filteredMeals) { meal in
                            MealCard(meal: meal) {
                                mealsManager.logMeal(meal)
                            } onEdit: {
                                mealToEdit = meal
                            } onDelete: {
                                withAnimation {
                                    mealsManager.deleteMeal(meal)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(mealsManager: mealsManager)
            }
            .sheet(item: $mealToEdit) { meal in
                AddMealView(mealsManager: mealsManager, editingMeal: meal)
            }
//        }
    }
    
    private var filteredMeals: [SavedMeal] {
        guard let category = selectedCategory else {
            return mealsManager.savedMeals
        }
        return mealsManager.savedMeals.filter { $0.category == category }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            Text(title)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
        .hoverEffect(.lift)
    }
}

struct MealCard: View {
    let meal: SavedMeal
    let onLog: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingLogConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(meal.name)
                    .font(.headline)
                
                Spacer()
                
                if meal.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
            }
            
            if let frequency = meal.frequency {
                Text(frequency)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            HStack {
                ForEach(Array(meal.nutrients.filter { $0.value > 0 }), id: \.key) { nutrient in
                    Text("\(nutrient.key): \(nutrient.value, specifier: "%.1f")")
                        .font(.caption)
                        .padding(5)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(5)
                }
            }
            
            Button("Log Meal") {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                showingLogConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .hoverEffect(.lift)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
        .alert("Log This Meal?", isPresented: $showingLogConfirmation) {
            Button("Log", action: onLog)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Add \(meal.name) to today's nutrition data?")
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
