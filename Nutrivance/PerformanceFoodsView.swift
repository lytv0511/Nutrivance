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
    let target_carbs: Double
    let target_protein: Double
    let target_fats: Double
    let target_hydration: Double
    let recommended_foods: [(category: String, items: [String], timing_window: String)]
}

class PerformanceFoodPredictor: ObservableObject {
    @Published var lastWorkout: HKWorkout?
    @Published var isPostWorkout: Bool = false
    @Published var requiresUserInput: Bool = false
    let healthKitManager: HealthKitManager
    
    init(healthStore: HealthKitManager) {
        self.healthKitManager = healthStore
    }
    
    func generateModelInput(for workout: HKWorkout) async -> ModelInput {
        lastWorkout = workout
        return await gatherHealthKitData()
    }
    
    func fetchWorkoutContext() async {
        let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)
        return await withCheckedContinuation { continuation in
            healthKitManager.fetchMostRecentWorkout { workout in
                self.lastWorkout = workout
                self.isPostWorkout = workout?.endDate ?? Date() > threeHoursAgo
                self.requiresUserInput = workout == nil
                continuation.resume()
            }
        }
    }
    
    func fetchSavedWorkouts() async -> [HKWorkout] {
        return await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
            
            let predicate = HKQuery.predicateForSamples(
                withStart: oneWeekAgo,
                end: Date(),
                options: .strictEndDate
            )
            
            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierEndDate,
                ascending: false
            )
            
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            
            healthKitManager.executeQuery(query)
        }
    }
    
    func fetchActiveWorkout() async -> HKWorkout? {
        return await withCheckedContinuation { continuation in
            healthKitManager.fetchMostRecentWorkout { workout in
                if let workout = workout,
                   workout.endDate > Date().addingTimeInterval(-3600) {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func fetchRecentWorkout() async -> HKWorkout? {
        return await withCheckedContinuation { continuation in
            healthKitManager.fetchMostRecentWorkout { workout in
                continuation.resume(returning: workout)
            }
        }
    }
    
    func gatherHealthKitData() async -> ModelInput {
        let duration = lastWorkout?.duration ?? 60
        let intensity = await calculateRealIntensity()
        let timeOfDay = getTimeOfDay(from: Date())
        
        var bodyComp = (fatPercentage: 0.0, leanMass: 0.0)
        var carbsValue = 0.0
        var proteinValue = 0.0
        var fatsValue = 0.0
        var hydrationValue = 0.0
        var hrvValue = 0.0
        
        await withCheckedContinuation { continuation in
            healthKitManager.fetchBodyComposition { value in
                bodyComp = value
                continuation.resume()
            }
        }
        
        let targetCarbs = calculateTargetCarbs(intensity: intensity)
        let targetProtein = calculateTargetProtein(leanMass: bodyComp.leanMass)
        let targetFats = calculateTargetFats(intensity: intensity)
        
        await withCheckedContinuation { continuation in
            healthKitManager.fetchTodayNutrientData(for: "carbs") { value, _ in
                carbsValue = value ?? 0
                continuation.resume()
            }
        }
        
        await withCheckedContinuation { continuation in
            healthKitManager.fetchTodayNutrientData(for: "protein") { value, _ in
                proteinValue = value ?? 0
                continuation.resume()
            }
        }
        
        await withCheckedContinuation { continuation in
            healthKitManager.fetchTodayNutrientData(for: "fats") { value, _ in
                fatsValue = value ?? 0
                continuation.resume()
            }
        }
        
        await withCheckedContinuation { continuation in
            healthKitManager.fetchHydration { value in
                hydrationValue = value
                continuation.resume()
            }
        }
        
        await withCheckedContinuation { continuation in
            healthKitManager.fetchHeartRateVariability { value in
                hrvValue = value
                continuation.resume()
            }
        }
        
        return ModelInput(
            workout_type: lastWorkout?.workoutActivityType.displayName ?? "unknown",
            duration_planned: duration,
            intensity_level: intensity,
            time_of_day: timeOfDay,
            previous_workout_strain: await calculateWorkoutStrain(),
            current_macronutrients_carbs: carbsValue,
            current_macronutrients_proteins: proteinValue,
            current_macronutrients_fats: fatsValue,
            hydration_status: hydrationValue,
            heart_rate_variability: hrvValue,
            body_fat_percentage: bodyComp.fatPercentage,
            lean_mass_kg: bodyComp.leanMass,
            target_carbs: targetCarbs,
            target_protein: targetProtein,
            target_fats: targetFats,
            target_hydration: calculateTargetHydration(duration: duration),
            recommended_foods: generateFoodRecommendations(
                workoutType: lastWorkout?.workoutActivityType.displayName ?? "unknown",
                timeOfDay: timeOfDay,
                intensity: intensity
            )
        )
    }
    
    private func calculateRealIntensity() async -> Int {
        guard let workout = lastWorkout else { return 5 }
        
        let energyType = HKQuantityType(.activeEnergyBurned)
        let energyBurned = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        let duration = workout.duration
        let avgHeartRate = await fetchWorkoutHeartRate(workout)
        
        let energyIntensity = (energyBurned / duration) * 0.2
        let heartRateIntensity = (avgHeartRate - 60) / 12
        
        let combinedIntensity = (energyIntensity + heartRateIntensity) / 2
        return min(max(Int(combinedIntensity), 1), 10)
    }
    
    private func fetchWorkoutHeartRate(_ workout: HKWorkout) async -> Double {
        return await withCheckedContinuation { continuation in
            let heartRateType = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate,
                options: .strictStartDate
            )
            
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                let avgHeartRate = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
                continuation.resume(returning: avgHeartRate)
            }
            
            healthKitManager.executeQuery(query)
        }
    }
    
    private func calculateWorkoutStrain() async -> Double {
        guard let workout = lastWorkout else { return 0 }
        return await healthKitManager.calculateWorkoutEnergy(workout: workout)
    }
    
    private func getTimeOfDay(from date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }
    
    private func calculateTargetCarbs(intensity: Int) -> Double {
        return Double(intensity) * 30.0
    }
    
    private func calculateTargetProtein(leanMass: Double) -> Double {
        return leanMass * 2.0
    }
    
    private func calculateTargetFats(intensity: Int) -> Double {
        return Double(intensity) * 10.0
    }
    
    private func calculateTargetHydration(duration: TimeInterval) -> Double {
        return (duration / 3600.0) * 0.5 + 2.0
    }
    
    private func generateFoodRecommendations(workoutType: String, timeOfDay: String, intensity: Int) -> [(category: String, items: [String], timing_window: String)] {
        var recommendations: [(category: String, items: [String], timing_window: String)] = []
        
        recommendations.append((
            category: "Pre-workout",
            items: ["Banana", "Oatmeal", "Greek Yogurt"],
            timing_window: "1-2 hours before"
        ))
        
        if intensity > 7 || workoutType.lowercased().contains("cardio") {
            recommendations.append((
                category: "During workout",
                items: ["Sports Drink", "Energy Gel"],
                timing_window: "Every 45-60 minutes"
            ))
        }
        
        recommendations.append((
            category: "Post-workout",
            items: ["Protein Shake", "Sweet Potato", "Chicken Breast"],
            timing_window: "Within 30 minutes"
        ))
        
        return recommendations
    }
}



struct PerformanceFoodsView: View {
    @StateObject private var predictor: PerformanceFoodPredictor
    @State private var activeWorkout: HKWorkout?
    @State private var recentWorkout: HKWorkout?
    @State private var savedWorkouts: [HKWorkout] = []
    @State private var modelInput: ModelInput?
    @State private var isLoading = true
    @State private var animationPhase: Double = 0
    @State private var lastRefresh = Date()
    private let refreshInterval: TimeInterval = 30
    
    init() {
        _predictor = StateObject(wrappedValue: PerformanceFoodPredictor(healthStore: HealthKitManager()))
    }
    
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
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView("Loading workout data...")
                    } else {
                        if let activeWorkout = activeWorkout {
                            LiveWorkoutPanel(
                                workout: activeWorkout,
                                modelInput: modelInput,
                                predictor: predictor
                            )
                            .transition(.move(edge: .top))
                        }
                        
                        SavedWorkoutsPanel(
                            workouts: savedWorkouts,
                            modelInput: modelInput
                        )
                        
                        if let recentWorkout = recentWorkout {
                            PostWorkoutPanel(
                                workout: recentWorkout,
                                modelInput: modelInput
                            )
                        } else {
                            WorkoutEstimationPanel(
                                modelInput: $modelInput,
                                isLoading: $isLoading
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Performance Foods")
        .navigationBarTitleDisplayMode(.large)
        .task {
           await loadWorkoutData()
           for await _ in AsyncStream(unfolding: {
               try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
               return true
           }) {
               let now = Date()
               if now.timeIntervalSince(lastRefresh) >= refreshInterval {
                   await loadWorkoutData()
                   lastRefresh = now
               }
           }
       }
    }
    
    private func loadWorkoutData() async {
        let (active, recent, saved) = await (
            predictor.fetchActiveWorkout(),
            predictor.fetchRecentWorkout(),
            predictor.fetchSavedWorkouts()
        )
        
        activeWorkout = active
        recentWorkout = recent
        savedWorkouts = saved
        modelInput = await predictor.gatherHealthKitData()
        isLoading = false
    }
}

struct LiveWorkoutPanel: View {
    let workout: HKWorkout
    let modelInput: ModelInput?
    @State private var heartRate: Double = 0
    @State private var calories: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var hydrationStatus: Double = 0
    @State private var showHydrationAlert = false
    @EnvironmentObject private var healthKit: HealthKitManager
    let predictor: PerformanceFoodPredictor
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Live Workout", systemImage: "waveform.path.ecg")
                    .font(.title2.bold())
                Spacer()
                Text("In Progress")
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
            }
            
            // Live Metrics Section
            HStack {
                MetricCard(
                    title: "Heart Rate",
                    value: "\(Int(heartRate))",
                    unit: "BPM",
                    icon: "heart.fill",
                    color: .red
                )
                MetricCard(
                    title: "Calories",
                    value: "\(Int(calories))",
                    unit: "kcal",
                    icon: "flame.fill",
                    color: .orange
                )
                MetricCard(
                    title: "Duration",
                    value: duration.formattedString,
                    unit: "",
                    icon: "clock.fill",
                    color: .blue
                )
            }
            
            // Hydration Status
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(.blue)
                Text("Hydration Status")
                Spacer()
                Text("\(hydrationStatus, specifier: "%.1f")L")
                    .foregroundColor(hydrationStatus < 1.5 ? .orange : .green)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .onTapGesture {
                showHydrationAlert = hydrationStatus < 1.5
            }
            
            if let input = modelInput {
                WorkoutSummaryCard(input: input)
                NutrientRecommendationsCard(input: input)
                TimingGuideCard(input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .alert("Hydration Reminder", isPresented: $showHydrationAlert) {
            Button("OK") { }
        } message: {
            Text("Remember to stay hydrated during your workout!")
        }
        .task {
            await monitorWorkoutMetrics()
        }
    }
    
    private func monitorWorkoutMetrics() async {
        let workoutStart = workout.startDate
        let energyBurned = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        
        // Update metrics every second
        for await _ in AsyncStream(unfolding: { try? await Task.sleep(nanoseconds: 1_000_000_000) }) {
            duration = Date().timeIntervalSince(workoutStart)
            calories = energyBurned * (duration / workout.duration)
            
            // Fetch latest heart rate
            let latestHeartRate = await fetchLatestHeartRate()
            if latestHeartRate > 0 {
                heartRate = latestHeartRate
            }
            
            // Update hydration status
            hydrationStatus = await fetchHydrationStatus()
        }
    }
    
    private func fetchLatestHeartRate() async -> Double {
        await withCheckedContinuation { continuation in
            let heartRateType = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-10),
                end: Date(),
                options: .strictEndDate
            )
            
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .mostRecent
            ) { _, result, _ in
                let heartRate = result?.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
                continuation.resume(returning: heartRate)
            }
            
            predictor.healthKitManager.executeQuery(query)
        }
    }
    
    private func fetchHydrationStatus() async -> Double {
        await withCheckedContinuation { continuation in
            predictor.healthKitManager.fetchHydration { value in
                continuation.resume(returning: value)
            }
        }
    }
}


struct SavedWorkoutsPanel: View {
    let workouts: [HKWorkout]
    let modelInput: ModelInput?
    @State private var selectedWorkout: HKWorkout?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Workouts")
                .font(.title2.bold())
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(workouts, id: \.uuid) { workout in
                        SavedWorkoutCard(workout: workout)
                            .onTapGesture {
                                selectedWorkout = workout
                            }
                            .overlay {
                                if selectedWorkout?.uuid == workout.uuid {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue, lineWidth: 2)
                                }
                            }
                    }
                }
            }
            
            if let input = modelInput, selectedWorkout != nil {
                WorkoutSummaryCard(input: input)
                NutrientRecommendationsCard(input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}


struct PostWorkoutPanel: View {
    let workout: HKWorkout
    let modelInput: ModelInput?
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Post-Workout Analysis", systemImage: "chart.bar.fill")
                    .font(.title2.bold())
                Spacer()
            }
            
            if let input = modelInput {
                WorkoutSummaryCard(input: input)
                NutrientRecommendationsCard(input: input)
                TimingGuideCard(input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct WorkoutEstimationPanel: View {
    @Binding var modelInput: ModelInput?
    @Binding var isLoading: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Plan Your Workout")
                .font(.title2.bold())
            
            WorkoutInputForm(modelInput: $modelInput, isLoading: $isLoading)
            
            if let input = modelInput {
                WorkoutSummaryCard(input: input)
                NutrientRecommendationsCard(input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct LiveMetricsView: View {
    let heartRate: Double
    let calories: Double
    let duration: TimeInterval
    
    var body: some View {
        HStack {
            MetricCard(
                title: "Heart Rate",
                value: "\(Int(heartRate))",
                unit: "BPM",
                icon: "heart.fill",
                color: .red
            )
            MetricCard(
                title: "Calories",
                value: "\(Int(calories))",
                unit: "kcal",
                icon: "flame.fill",
                color: .orange
            )
            MetricCard(
                title: "Duration",
                value: duration.formattedString,
                unit: "",
                icon: "clock.fill",
                color: .blue
            )
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SavedWorkoutCard: View {
    let workout: HKWorkout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.workoutActivityType.displayName)
                .font(.headline)
            Text("\(Int(workout.duration / 60)) min")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(width: 120)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

extension TimeInterval {
    var formattedString: String {
        let hours = Int(self) / 3600
        let minutes = Int(self) / 60 % 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct WorkoutSummaryCard: View {
    let input: ModelInput
    
    var formattedDuration: String {
        let minutes = Int(input.duration_planned / 60)
        return "\(minutes) min"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Summary")
                .font(.title2)
                .bold()
            
            HStack {
                Label(input.workout_type.capitalized, systemImage: "figure.run")
                Spacer()
                Label(formattedDuration, systemImage: "clock")
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


struct NutrientRecommendationsCard: View {
    let input: ModelInput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrient Recommendations")
                .font(.title2)
                .bold()
            
            MacronutrientRow(name: "Carbs", current: input.current_macronutrients_carbs, target: input.target_carbs)
            MacronutrientRow(name: "Protein", current: input.current_macronutrients_proteins, target: input.target_protein)
            MacronutrientRow(name: "Fats", current: input.current_macronutrients_fats, target: input.target_fats)
            
            HStack {
                Label("Hydration", systemImage: "drop.fill")
                Spacer()
                Text("\(input.hydration_status, specifier: "%.1f")L / \(input.target_hydration, specifier: "%.1f")L")
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
            
            ForEach(input.recommended_foods, id: \.category) { recommendation in
                VStack(alignment: .leading, spacing: 8) {
                    Text(recommendation.category)
                        .font(.headline)
                    Text("When: \(recommendation.timing_window)")
                        .foregroundColor(.secondary)
                    Text("Foods: \(recommendation.items.joined(separator: ", "))")
                        .foregroundColor(.secondary)
                }
            }
            
            if input.heart_rate_variability < 50 {
                Text("Recovery status: Additional rest recommended")
                    .foregroundColor(.orange)
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
    @Binding var modelInput: ModelInput?
    @Binding var isLoading: Bool
    let workoutTypes = ["Strength", "Cardio", "HIIT", "Flexibility"]
    
    var body: some View {
        VStack(spacing: 20) {
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
    }
}

struct MacronutrientRow: View {
    let name: String
    let current: Double
    let target: Double
    
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text("\(Int(current))g / \(Int(target))g")
        }
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining:
            return "Strength"
        case .running:
            return "Running"
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .flexibility:
            return "Flexibility"
        default:
            return "Workout"
        }
    }
}
