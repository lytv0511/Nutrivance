import SwiftUI

struct FuelCheckView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    Color(red: 0.75, green: 0.0, blue: 0),
                    Color(red: 1.0, green: 0.4, blue: 0),
                    Color(red: 0.95, green: 0.6, blue: 0),
                    Color(red: 0.8, green: 0.2, blue: 0),
                    Color(red: 1.0, green: 0.5, blue: 0),
                    Color(red: 0.9, green: 0.3, blue: 0),
                    Color(red: 0.8, green: 0.1, blue: 0),
                    Color(red: 1.0, green: 0.45, blue: 0),
                    Color(red: 0.85, green: 0.25, blue: 0)
                ]
            )
            .ignoresSafeArea()
            .hueRotation(.degrees(animationPhase))
            
            ScrollView {
                VStack(spacing: 20) {
                    MacronutrientStatusCard()
                    HydrationLevelsCard()
                    NutrientTimingCard()
                    PerformanceRecommendations()
                }
                .padding()
            }
        }
        .navigationTitle("Fuel Check")
    }
}

struct MacronutrientStatusCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var carbs: Double = 0
    @State private var protein: Double = 0
    @State private var fats: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macronutrient Balance")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Carbs",
                        value: String(format: "%.0fg", carbs),
                        icon: "leaf.fill"
                    )
                    Divider()
                    MetricItem(
                        title: "Protein",
                        value: String(format: "%.0fg", protein),
                        icon: "figure.strengthtraining.traditional"
                    )
                    Divider()
                    MetricItem(
                        title: "Fats",
                        value: String(format: "%.0fg", fats),
                        icon: "drop.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchMacroData()
        }
    }
    
    private func fetchMacroData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    healthStore.fetchTodayNutrientData(for: "carbs") { value, _ in
                        carbs = value ?? 0
                        continuation.resume()
                    }
                }
            }
            group.addTask {
                await withCheckedContinuation { continuation in
                    healthStore.fetchTodayNutrientData(for: "protein") { value, _ in
                        protein = value ?? 0
                        continuation.resume()
                    }
                }
            }
            group.addTask {
                await withCheckedContinuation { continuation in
                    healthStore.fetchTodayNutrientData(for: "fats") { value, _ in
                        fats = value ?? 0
                        continuation.resume()
                    }
                }
            }
        }
        isLoading = false
    }
}

struct HydrationLevelsCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var hydrationLevel: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hydration Status")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Water Intake",
                        value: String(format: "%.0f mL", hydrationLevel * 1000),
                        icon: "drop.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchHydrationData()
        }
    }
    
    private func fetchHydrationData() async {
        await withCheckedContinuation { continuation in
            healthStore.fetchHydration { value in
                hydrationLevel = value
                isLoading = false
                continuation.resume()
            }
        }
    }
}

struct NutrientTimingCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var lastMealTime: Date?
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrient Timing")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let lastMeal = lastMealTime {
                        TimingRow(
                            title: "Last Meal",
                            time: lastMeal,
                            icon: "clock.fill"
                        )
                    }
                    TimingRow(
                        title: "Optimal Window",
                        time: Date().addingTimeInterval(7200),
                        icon: "target"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchNutrientTiming()
        }
    }
    
    private func fetchNutrientTiming() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate)!
        
        healthStore.fetchNutrientHistory(from: startDate, to: endDate) { entries in
            lastMealTime = entries.first?.timestamp
            isLoading = false
        }
    }
}

struct PerformanceRecommendations: View {
    let recommendations: [(String, String, String)] = [
        ("Pre-Workout", "Consume complex carbs 2-3 hours before", "figure.run"),
        ("During Activity", "Stay hydrated, electrolyte balance", "drop.fill"),
        ("Post-Workout", "Protein within 30 minutes", "figure.cooldown"),
        ("Recovery", "Balance macros for optimal recovery", "heart.fill")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Nutrition")
                .font(.title2.bold())
            
            ForEach(recommendations, id: \.0) { rec in
                RecommendationRow(
                    title: rec.0,
                    description: rec.1,
                    icon: rec.2
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TimingRow: View {
    let title: String
    let time: Date
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(time, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
