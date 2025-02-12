import SwiftUI
import HealthKit

struct ModelInput {
    let workout_type: String
    let duration_planned: Double
    let intensity_level: Int
    let time_of_day: String
    let previous_workout_strain: Double
    let current_macronutrients_carbs: Double
    let current_macronutrients_proteins: Double
    let current_macronutrients_fats: Double
    let hydration_status: Double
    let heart_rate_variability: Double
    let body_fat_percentage: Double
    let lean_mass_kg: Double
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .traditionalStrengthTraining:
            return "strength"
        case .running, .cycling, .swimming:
            return "cardio"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .flexibility, .yoga:
            return "flexibility"
        default:
            return "other"
        }
    }
}

class PerformanceFoodPredictor: ObservableObject {
    @Published var lastWorkout: HKWorkout?
    @Published var isPostWorkout: Bool = false
    @Published var requiresUserInput: Bool = false
    private let healthStore: HealthKitManager
    
    init(healthStore: HealthKitManager) {
        self.healthStore = healthStore
    }
    
    @MainActor
    func fetchWorkoutContext() {
        let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)
        healthStore.fetchMostRecentWorkout { [weak self] workout in
            self?.lastWorkout = workout
            self?.isPostWorkout = workout?.endDate ?? Date() > threeHoursAgo
            self?.requiresUserInput = workout == nil
        }
    }
    
    @MainActor
    func gatherHealthKitData() async -> ModelInput {
        // Convert completion handler to async
        let carbs = await withCheckedContinuation { continuation in
            healthStore.fetchTodayNutrientData(for: "carbs") { value, _ in
                continuation.resume(returning: value ?? 0)
            }
        }
        
        let protein = await withCheckedContinuation { continuation in
            healthStore.fetchTodayNutrientData(for: "protein") { value, _ in
                continuation.resume(returning: value ?? 0)
            }
        }
        
        let fats = await withCheckedContinuation { continuation in
            healthStore.fetchTodayNutrientData(for: "fats") { value, _ in
                continuation.resume(returning: value ?? 0)
            }
        }
        
        // Keep existing continuations for other health data
        let hydrationValue = await withCheckedContinuation { continuation in
            healthStore.fetchHydration { value in
                continuation.resume(returning: value)
            }
        }
        
        let hrvValue = await withCheckedContinuation { continuation in
            healthStore.fetchHeartRateVariability { value in
                continuation.resume(returning: value)
            }
        }
        
        let bodyCompValue = await withCheckedContinuation { continuation in
            healthStore.fetchBodyComposition { value in
                continuation.resume(returning: value)
            }
        }
        
        let strainValue = await withCheckedContinuation { continuation in
            healthStore.calculateWorkoutStrain { value in
                continuation.resume(returning: value)
            }
        }
        
        return ModelInput(
            workout_type: lastWorkout?.workoutActivityType.name ?? "unknown",
            duration_planned: Double(lastWorkout?.duration ?? 0),
            intensity_level: Int(strainValue),
            time_of_day: Calendar.current.component(.hour, from: Date()) < 12 ? "morning" : "afternoon",
            previous_workout_strain: strainValue,
            current_macronutrients_carbs: carbs,
            current_macronutrients_proteins: protein,
            current_macronutrients_fats: fats,
            hydration_status: hydrationValue,
            heart_rate_variability: hrvValue,
            body_fat_percentage: bodyCompValue.fatPercentage,
            lean_mass_kg: bodyCompValue.leanMass
        )
    }

}



struct PerformanceFoodsView: View {
    @StateObject private var predictor: PerformanceFoodPredictor
    @State private var modelInput: ModelInput?
    @State private var isLoading = true
    @State private var animationPhase: Double = 0
    
    init() {
        _predictor = StateObject(wrappedValue: PerformanceFoodPredictor(healthStore: HealthKitManager()))
    }
    
    var body: some View {
        ZStack {
            // Mesh Gradient Background
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    Color(red: 0.75, green: 0.0, blue: 0),  // Deep red
                    Color(red: 1.0, green: 0.4, blue: 0),   // Vibrant orange
                    Color(red: 0.95, green: 0.6, blue: 0),  // Warm yellow
                    Color(red: 0.8, green: 0.2, blue: 0),   // Rich red-orange
                    Color(red: 1.0, green: 0.5, blue: 0),   // Pure orange
                    Color(red: 0.9, green: 0.3, blue: 0),   // Bright red-orange
                    Color(red: 0.8, green: 0.1, blue: 0),   // Deep red
                    Color(red: 1.0, green: 0.45, blue: 0),  // Bright orange
                    Color(red: 0.85, green: 0.25, blue: 0)  // Rich red-orange
                ]
            )
            .ignoresSafeArea()
            .hueRotation(.degrees(animationPhase))
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
            }
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Analyzing workout data...")
                    } else if predictor.requiresUserInput {
                        WorkoutInputForm()
                    } else {
                        if let input = modelInput {
                            WorkoutSummaryCard(input: input)
                            NutrientRecommendationsCard(input: input)
                            TimingGuideCard(input: input)
                        }
                    }
                }
                .padding()
            }
            .task {
                await predictor.fetchWorkoutContext()
                modelInput = await predictor.gatherHealthKitData()
                isLoading = false
            }
        }
    }
}

struct WorkoutSummaryCard: View {
    let input: ModelInput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Summary")
                .font(.title2)
                .bold()
            
            HStack {
                Label(input.workout_type.capitalized, systemImage: "figure.run")
                Spacer()
                Label("\(Int(input.duration_planned)) min", systemImage: "clock")
            }
            
            HStack {
                Label("Intensity: \(input.intensity_level)/10", systemImage: "flame")
                Spacer()
                Label(input.time_of_day.capitalized, systemImage: "sun.max")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct WorkoutInputForm: View {
    @State private var selectedWorkoutType = "Strength"
    @State private var duration: Double = 60
    @State private var intensity = 5
    
    let workoutTypes = ["Strength", "Cardio", "HIIT", "Flexibility"]
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 20) {
                Text("Plan Your Workout")
                    .font(.title2)
                    .bold()
                
                Picker("Workout Type", selection: $selectedWorkoutType) {
                    ForEach(workoutTypes, id: \.self) { type in
                        Text(type)
                    }
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading) {
                    Text("Duration: \(Int(duration)) minutes")
                    Slider(value: $duration, in: 15...180, step: 15)
                }
                
                VStack(alignment: .leading) {
                    Text("Intensity: \(intensity)/10")
                    Slider(value: .init(get: { Double(intensity) },
                                      set: { intensity = Int($0) }), in: 1...10, step: 1)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            
            // Food Suggestions Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Recommended Pre-Workout Foods")
                    .font(.title2)
                    .bold()
                
                ForEach(getFoodSuggestions(), id: \.self) { food in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                        Text(food)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
    
    private func getFoodSuggestions() -> [String] {
        switch selectedWorkoutType {
        case "Strength":
            return ["Protein shake with banana", "Greek yogurt with berries", "Oatmeal with protein powder"]
        case "Cardio":
            return ["Toast with peanut butter", "Banana with honey", "Energy bar"]
        case "HIIT":
            return ["Rice cake with almond butter", "Apple with protein bar", "Smoothie bowl"]
        case "Flexibility":
            return ["Light smoothie", "Small fruit bowl", "Green tea with honey"]
        default:
            return []
        }
    }
}


struct NutrientRecommendationsCard: View {
    let input: ModelInput
    
    var foodRecommendations: [(category: String, foods: [String], timing: String)] {
        // Determine primary needs based on workout type and intensity
        let isHighIntensity = input.intensity_level > 7
        let isStrengthTraining = input.workout_type == "strength"
        let needsQuickEnergy = input.time_of_day == "morning" || input.previous_workout_strain > 7
        let lowCarbs = input.current_macronutrients_carbs < 50
        let lowProtein = input.current_macronutrients_proteins < 30
        let poorRecovery = input.heart_rate_variability < 40
        
        var recommendations: [(String, [String], String)] = []
        
        // High Glycemic Carbs
        if isHighIntensity || needsQuickEnergy {
            recommendations.append((
                "Quick Energy",
                ["Rice cakes with honey", "White bread with jam", "Sports drink"],
                "30-60 min pre-workout"
            ))
        }
        
        // Complete Proteins
        if isStrengthTraining || lowProtein {
            recommendations.append((
                "Protein Sources",
                ["Whey protein shake", "Greek yogurt", "Chicken breast"],
                "60-90 min pre-workout"
            ))
        }
        
        // Slow-Release Carbs
        if !needsQuickEnergy && lowCarbs {
            recommendations.append((
                "Sustained Energy",
                ["Oatmeal with berries", "Sweet potato", "Quinoa"],
                "90-120 min pre-workout"
            ))
        }
        
        // Recovery Focus
        if poorRecovery || input.previous_workout_strain > 8 {
            recommendations.append((
                "Recovery Boosters",
                ["BCAA drink", "Tart cherry juice", "Electrolyte water"],
                "During workout"
            ))
        }
        
        return recommendations
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nutrient Recommendations")
                .font(.title2)
                .bold()
            
            // Current Nutrient Status
            MacronutrientRow(name: "Carbs", value: input.current_macronutrients_carbs)
            MacronutrientRow(name: "Protein", value: input.current_macronutrients_proteins)
            MacronutrientRow(name: "Fats", value: input.current_macronutrients_fats)
            
            HStack {
                Label("Hydration", systemImage: "drop.fill")
                Spacer()
                Text("\(input.hydration_status, specifier: "%.1f")L")
            }
            
            Divider()
            
            // Food Recommendations
            ForEach(foodRecommendations, id: \.category) { category, foods, timing in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category)
                        .font(.headline)
                    Text(timing)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach(foods, id: \.self) { food in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                            Text(food)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Hydration Warning
            if input.hydration_status < 1.5 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Increase fluid intake before workout")
                        .foregroundColor(.orange)
                }
                .padding(.top)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}



struct TimingGuideCard: View {
    let input: ModelInput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing Guide")
                .font(.title2)
                .bold()
            
            Text("Optimal time: \(getOptimalTime(for: input.time_of_day))")
            Text("Recovery status: \(getRecoveryStatus(hrv: input.heart_rate_variability))")
            
            if input.previous_workout_strain > 7 {
                Text("High previous strain detected - consider lighter intensity")
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    private func getOptimalTime(for timeOfDay: String) -> String {
        switch timeOfDay {
        case "morning": return "30-60 minutes after breakfast"
        case "afternoon": return "2-3 hours after lunch"
        case "evening": return "1-2 hours before dinner"
        default: return "Based on your last meal"
        }
    }
    
    private func getRecoveryStatus(hrv: Double) -> String {
        switch hrv {
        case ..<30: return "Recovery needed"
        case 30..<50: return "Moderate recovery"
        default: return "Well recovered"
        }
    }
}

struct MacronutrientRow: View {
    let name: String
    let value: Double
    
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text("\(Int(value))g")
        }
    }
}
