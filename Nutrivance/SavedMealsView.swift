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

@MainActor
class SavedMealsManager: ObservableObject, @unchecked Sendable {
    @Published var savedMeals: [SavedMeal] = []
    @Published var showSaveConfirmation = false
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
        Task { @MainActor in
            let healthStore = HealthKitManager()
            let nutrientData = meal.nutrients.map { key, value in
                HealthKitManager.NutrientData(name: key, value: value, unit: "g")
            }
            
            healthStore.saveNutrients(nutrientData) { success in
                if success {
                    withAnimation {
                        self.showSaveConfirmation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showSaveConfirmation = false
                        }
                    }
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
    @State private var animationPhase: Double = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddMeal = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(
                GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle(Text("Saved Meals"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(mealsManager: mealsManager)
            }
            .sheet(item: $mealToEdit) { meal in
                AddMealView(mealsManager: mealsManager, editingMeal: meal)
            }
        }
    }
    
    private var filteredMeals: [SavedMeal] {
        guard let category = selectedCategory else {
            return mealsManager.savedMeals
        }
        return mealsManager.savedMeals.filter { $0.category == category }
    }
    
    private var gradientBackground: some View {
        MeshGradient(
            width: 4, height: 4,
            points: [
                [0.0, 0.0], [0.33, 0.0], [0.66, 0.0], [1.0, 0.0],
                [0.0, 0.33], [0.33, 0.33], [0.66, 0.33], [1.0, 0.33],
                [0.0, 0.66], [0.33, 0.66], [0.66, 0.66], [1.0, 0.66],
                [0.0, 1.0], [0.33, 1.0], [0.66, 1.0], [1.0, 1.0]
            ],
            colors: [
                .black, Color(red: 0, green: 0.15, blue: 0.2), Color(red: 0, green: 0.2, blue: 0.15), .black,
                Color(red: 0, green: 0.2, blue: 0.1), Color(red: 0, green: 0.15, blue: 0.2),
                Color(red: 0, green: 0.2, blue: 0.15), Color(red: 0, green: 0.1, blue: 0.2),
                Color(red: 0, green: 0.2, blue: 0.1), Color(red: 0, green: 0.15, blue: 0.15),
                Color(red: 0, green: 0.2, blue: 0.2), Color(red: 0, green: 0.2, blue: 0.1),
                .black, Color(red: 0, green: 0.1, blue: 0.2), Color(red: 0, green: 0.2, blue: 0.1), .black
            ]
        )
        .ignoresSafeArea()
        .hueRotation(.degrees(animationPhase))
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: true)) {
                animationPhase = 360
            }
        }
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
                ForEach(Array(meal.nutrients.filter { $0.value > 0 })
                    .sorted(by: { $0.key < $1.key }), id: \.key) { nutrient in
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
        .background(.ultraThinMaterial)
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
