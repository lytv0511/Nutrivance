import SwiftUI
import HealthKit

struct ModelInput {
    let workout: HKWorkout?
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

@MainActor
class PerformanceFoodPredictor: ObservableObject {
    @Published var lastWorkout: HKWorkout?
    @Published var isPostWorkout: Bool = false
    @Published var requiresUserInput: Bool = false
    let healthKitManager: HealthKitManager
    
    init(healthStore: HealthKitManager) {
        self.healthKitManager = healthStore
    }
    
    func generateModelInput(for workout: HKWorkout) async -> ModelInput {
        print("Generating model input for workout: \(workout.workoutActivityType.displayName), duration: \(workout.duration/60) min")
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
    
    func fetchMostRecentWorkout() async -> HKWorkout? {
        return await withCheckedContinuation { continuation in
            healthKitManager.fetchMostRecentWorkout { workout in
                continuation.resume(returning: workout)
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
                sampleType: HKObjectType.workoutType(),
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
        print("Last workout type: \(lastWorkout?.workoutActivityType.displayName ?? "none")")
        print("Last workout duration: \(lastWorkout?.duration ?? 0)")
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
            workout: lastWorkout,
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
        
        return Int((energyIntensity + heartRateIntensity) / 2)
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
     @State private var selectedWorkout: HKWorkout?
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
                        LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 16)
                            ], spacing: 16) {
                                ForEach(savedWorkouts, id: \.uuid) { workout in
                                    SavedWorkoutCard(workout: workout)
                                        .onTapGesture {
                                            selectedWorkout = workout
                                            Task {
                                                modelInput = await predictor.generateModelInput(for: workout)
                                            }
                                        }
                                        .overlay {
                                            if selectedWorkout?.uuid == workout.uuid {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.blue, lineWidth: 2)
                                            }
                                        }
                                }
                            }
                            .padding()
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
                            predictor: predictor
                        )
                        
                        if let recentWorkout = recentWorkout {
                            PostWorkoutPanel(
                                workout: recentWorkout,
                                predictor: predictor
                            )
                        } else {
                            WorkoutEstimationPanel(
                                modelInput: $modelInput,
                                isLoading: $isLoading,
                                predictor: predictor
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

struct WorkoutEstimationPanel: View {
    @Binding var modelInput: ModelInput?
    @Binding var isLoading: Bool
    @State private var selectedWorkout: HKWorkout?
    let predictor: PerformanceFoodPredictor
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Workout Estimation", systemImage: "figure.run")
                    .font(.title2.bold())
                Spacer()
            }
            
            if let workout = selectedWorkout, let input = modelInput {
                WorkoutSummaryCard(workout: workout, input: input)
                NutrientRecommendationsCard(workout: workout, input: input)
                TimingGuideCard(workout: workout, input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .task {
            if let workout = await predictor.fetchMostRecentWorkout() {
                selectedWorkout = workout
                modelInput = await predictor.generateModelInput(for: workout)
            }
            isLoading = false
        }
    }
}

struct SavedWorkoutCard: View {
    let workout: HKWorkout
    
    var workoutIcon: String {
        switch workout.workoutActivityType {
        case .running: return "figure.run"
        case .cycling: return "figure.cycling"
        case .swimming: return "figure.pool.swim"
        case .hiking: return "figure.hiking"
        case .yoga: return "figure.mind.and.body"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .soccer: return "figure.soccer"
        case .basketball: return "figure.basketball"
        case .tennis: return "figure.tennis"
        case .golf: return "figure.golf"
        case .baseball: return "figure.baseball"
        case .dance: return "figure.dance"
        case .waterPolo: return "figure.waterpolo"
        default: return "figure.mixed.cardio"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: workoutIcon)
                    .font(.title2)
                Text(workout.workoutActivityType.name)
                    .font(.headline)
            }
            
            HStack {
                Image(systemName: "clock")
                Text("\(Int(workout.duration / 60)) min")
            }
            .font(.subheadline)
            
            HStack {
                Image(systemName: "calendar")
                Text(workout.startDate, style: .date)
            }
            .font(.subheadline)
            
            HStack {
                Image(systemName: "flame.fill")
                let energyType = HKQuantityType(.activeEnergyBurned)
                if let calories = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    Text("\(Int(calories)) kcal")
                } else {
                    Text("-- kcal")
                }
            }
            .font(.subheadline)
            
            HStack {
                Image(systemName: "figure.walk")
                if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                    Text(String(format: "%.1f km", distance/1000))
                } else {
                    Text("-- km")
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 200)
    }
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .danceInspiredTraining: return "Dance Training"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian Sports"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Functional Strength"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind and Body"
        case .paddleSports: return "Paddle Sports"
        case .play: return "Play"
        case .preparationAndRecovery: return "Prep & Recovery"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating Sports"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing Sports"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track and Field"
        case .traditionalStrengthTraining: return "Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .flexibility: return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .pilates: return "Pilates"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .wheelchairRunPace: return "Wheelchair Run"
        case .wheelchairWalkPace: return "Wheelchair Walk"
        case .cardioDance: return "Cardio Dance"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .cooldown: return "Cooldown"
        case .swimBikeRun: return "Triathlon"
        case .transition: return "Transition"
        default: return "Workout"
        }
    }
}



struct LiveWorkoutPanel: View {
    let workout: HKWorkout
    let modelInput: ModelInput?
    let predictor: PerformanceFoodPredictor
    @State private var heartRate: Double = 0
    @State private var calories: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var hydrationStatus: Double = 0
    
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
            
            LiveMetricsView(
                heartRate: heartRate,
                calories: calories,
                duration: duration
            )
            
            if let input = modelInput {
                WorkoutSummaryCard(workout: workout, input: input)
                NutrientRecommendationsCard(workout: workout, input: input)
                TimingGuideCard(workout: workout, input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct SavedWorkoutsPanel: View {
    let workouts: [HKWorkout]
    @State private var selectedWorkout: HKWorkout?
    @State private var selectedWorkoutInput: ModelInput?
    let predictor: PerformanceFoodPredictor
    
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
                                Task {
                                    selectedWorkoutInput = await predictor.generateModelInput(for: workout)
                                }
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
            
            if let workout = selectedWorkout, let input = selectedWorkoutInput {
                WorkoutSummaryCard(workout: workout, input: input)
                NutrientRecommendationsCard(workout: workout, input: input)
                TimingGuideCard(workout: workout, input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct PostWorkoutPanel: View {
    let workout: HKWorkout
    @State private var selectedWorkout: HKWorkout?
    @State private var modelInput: ModelInput?
    let predictor: PerformanceFoodPredictor
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Post-Workout Analysis", systemImage: "chart.bar.fill")
                    .font(.title2.bold())
                Spacer()
            }
            
            if let input = modelInput {
                WorkoutSummaryCard(workout: workout, input: input)
                NutrientRecommendationsCard(workout: workout, input: input)
                TimingGuideCard(workout: workout, input: input)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .task {
            selectedWorkout = workout
            modelInput = await predictor.generateModelInput(for: workout)
        }
    }
}

//struct SavedWorkoutCard: View {
//    let workout: HKWorkout
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Text(workout.workoutActivityType.displayName)
//                .font(.headline)
//            
//            Text("\(Int(workout.duration / 60)) minutes")
//                .font(.subheadline)
//            
//            Text(workout.startDate, style: .date)
//                .font(.caption)
//                .foregroundStyle(.secondary)
//        }
//        .padding()
//        .background(.ultraThinMaterial)
//        .clipShape(RoundedRectangle(cornerRadius: 12))
//        .frame(width: 160)
//    }
//}

struct LiveMetricsView: View {
    let heartRate: Double
    let calories: Double
    let duration: TimeInterval
    
    var body: some View {
        HStack(spacing: 20) {
            MetricCard(
                title: "Heart Rate",
                value: String(format: "%.0f", heartRate),
                unit: "bpm",
                icon: "heart.fill"
            )
            
            MetricCard(
                title: "Calories",
                value: String(format: "%.0f", calories),
                unit: "kcal",
                icon: "flame.fill"
            )
            
            MetricCard(
                title: "Duration",
                value: String(format: "%.0f", duration/60),
                unit: "min",
                icon: "clock.fill"
            )
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
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
    let workout: HKWorkout
    let input: ModelInput
    
    var formattedDuration: String {
        let minutes = Int(workout.duration / 60)
        return "\(minutes) min"
    }
    
    var workoutTimeOfDay: String {
        let hour = Calendar.current.component(.hour, from: workout.startDate)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Summary")
                .font(.title2)
                .bold()
            
            HStack {
                Label(workout.workoutActivityType.displayName, systemImage: "figure.run")
                Spacer()
                Label(formattedDuration, systemImage: "clock")
            }
            
            HStack {
                Label("Intensity: \(input.intensity_level)/10", systemImage: "flame")
                Spacer()
                Label(workoutTimeOfDay.capitalized, systemImage: "sun.max")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct NutrientRecommendationsCard: View {
    let workout: HKWorkout
    let input: ModelInput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrient Recommendations")
                .font(.title2)
                .bold()
            
            MacronutrientRow(
                name: "Carbs",
                current: input.current_macronutrients_carbs,
                target: input.target_carbs,
                unit: "g"
            )
            
            MacronutrientRow(
                name: "Protein",
                current: input.current_macronutrients_proteins,
                target: input.target_protein,
                unit: "g"
            )
            
            MacronutrientRow(
                name: "Fats",
                current: input.current_macronutrients_fats,
                target: input.target_fats,
                unit: "g"
            )
            
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
    let workout: HKWorkout
    let input: ModelInput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing Guide")
                .font(.title2)
                .bold()
            
            Text("Optimal time: \(getOptimalTime())")
            Text("Recovery status: \(getRecoveryStatus())")
            
            if input.previous_workout_strain > 7 {
                Text("High previous strain detected - consider lighter intensity")
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    private func getOptimalTime() -> String {
        let hour = Calendar.current.component(.hour, from: workout.startDate)
        switch hour {
        case 5..<12: return "30-60 minutes after breakfast"
        case 12..<17: return "2-3 hours after lunch"
        case 17..<22: return "1-2 hours before dinner"
        default: return "Based on your last meal"
        }
    }
    
    private func getRecoveryStatus() -> String {
        switch input.heart_rate_variability {
        case ..<30: return "Recovery needed"
        case 30..<50: return "Moderate recovery"
        default: return "Well recovered"
        }
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
    let unit: String
    
    var percentageOfTarget: Double {
        guard target > 0 else { return 0 }
        return min(current / target * 100, 100)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(name)
                Spacer()
                Text("\(Int(current))\(unit) / \(Int(target))\(unit)")
            }
            ProgressView(value: percentageOfTarget, total: 100)
                .tint(percentageOfTarget >= 100 ? .green : .blue)
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
