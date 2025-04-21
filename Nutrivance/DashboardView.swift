import SwiftUI
import Charts
import HealthKit

struct DashboardMetrics {
    // General Health Metrics
    var activeEnergy: String = "0"
    var steps: String = "0"
    var distance: String = "0"
    var exercise: String = "0"
    var standHours: String = "0"
    var flights: String = "0"
    var mindfulnessMinutes: String = "0"
    
    // Sports Metrics
    var runningDistance: String = "0"
    var walkingDistance: String = "0"
    var cyclingDistance: String = "0"
    var swimmingDistance: String = "0"
    var hikingDistance: String = "0"
    var yogaTime: String = "0"
    var functionalStrengthTraining: String = "0"
    var rowingDistance: String = "0"
    var ellipticalDistance: String = "0"
    var highIntensityTrainingMinutes: String = "0"
    var basketballMinutes: String = "0"
    var tennisMinutes: String = "0"
    var soccerMinutes: String = "0"
    var volleyballMinutes: String = "0"
    var golfMinutes: String = "0"
    
    // Workout Data
    var workouts: [HKWorkout] = []
    var timeInWorkoutZones: [String: String] = [:]
}

struct ComplicationData: Identifiable, Hashable, Codable {
    var id: UUID
    let title: String
    let value: String
    let unit: String
    let icon: String
    let category: ComplicationCategory
    let isActivityRing: Bool

    // Add this custom initializer
    init(title: String, value: String, unit: String, icon: String, category: ComplicationCategory, isActivityRing: Bool) {
        self.id = UUID()
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.category = category
        self.isActivityRing = isActivityRing
    }

    // Keep the existing Codable implementation
    enum CodingKeys: String, CodingKey {
        case id, title, value, unit, icon, category, isActivityRing
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(icon, forKey: .icon)
        try container.encode(category == .general ? "general" : "sports", forKey: .category)
        try container.encode(isActivityRing, forKey: .isActivityRing)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        value = try container.decode(String.self, forKey: .value)
        unit = try container.decode(String.self, forKey: .unit)
        icon = try container.decode(String.self, forKey: .icon)
        let categoryString = try container.decode(String.self, forKey: .category)
        category = categoryString == "general" ? .general : .sports
        isActivityRing = try container.decode(Bool.self, forKey: .isActivityRing)
    }
}

struct ComplicationSection: View {
    let title: String
    let complications: [ComplicationData]
    let selectedComplications: Set<ComplicationData>
    let onToggle: (ComplicationData) -> Void
    
    var body: some View {
        Section(title) {
            ForEach(complications) { complication in
                ComplicationRow(
                    complication: complication,
                    isSelected: selectedComplications.contains(complication)
                )
                .onTapGesture {
                    onToggle(complication)
                }
            }
        }
    }
}

struct ComplicationRow: View {
    let complication: ComplicationData
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: complication.icon)
                .foregroundStyle(complication.isActivityRing ? .red : .blue)
            Text(complication.title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
}

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var selectedComplications: Set<ComplicationData> = []
    let healthStore: HealthKitManager
       
   @AppStorage("savedComplications") private var savedComplicationsData: Data = {
       let defaultComplications = [
           ComplicationData(
               title: "Active Energy",
               value: "0",
               unit: "cal",
               icon: "flame.fill",
               category: .general,
               isActivityRing: true
           ),
           ComplicationData(
               title: "Steps",
               value: "0",
               unit: "steps",
               icon: "figure.walk",
               category: .general,
               isActivityRing: false
           ),
           ComplicationData(
               title: "Distance",
               value: "0",
               unit: "km",
               icon: "figure.walk.motion",
               category: .general,
               isActivityRing: false
           ),
           ComplicationData(
               title: "Exercise",
               value: "0",
               unit: "min",
               icon: "figure.run",
               category: .general,
               isActivityRing: true
           )
       ]
       return try! JSONEncoder().encode(defaultComplications)
   }()
   
    init() {
        let defaultComplications = [
            ComplicationData(
                title: "Active Energy",
                value: "0",
                unit: "cal",
                icon: "flame.fill",
                category: .general,
                isActivityRing: true
            ),
            ComplicationData(
                title: "Steps",
                value: "0",
                unit: "steps",
                icon: "figure.walk",
                category: .general,
                isActivityRing: false
            ),
            ComplicationData(
                title: "Distance",
                value: "0",
                unit: "km",
                icon: "figure.walk.motion",
                category: .general,
                isActivityRing: false
            ),
            ComplicationData(
                title: "Exercise",
                value: "0",
                unit: "min",
                icon: "figure.run",
                category: .general,
                isActivityRing: true
            )
        ]
        
        let initialData = (try? JSONEncoder().encode(defaultComplications)) ?? Data()
        
        self.healthStore = HealthKitManager()
        self.selectedComplications = Set(defaultComplications)
        self.savedComplicationsData = initialData
        self.showComplicationPicker = false
    }

   func saveComplications() {
       if let encoded = try? JSONEncoder().encode(Array(selectedComplications)) {
           savedComplicationsData = encoded
       }
   }
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Published var metrics: DashboardMetrics = DashboardMetrics()
    @Published var showRingCard = false
    @Published var activeRings: [RingMetric] = [] {
        didSet {
            saveRings()
        }
    }
    @Published var isRingSectionExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isRingSectionExpanded, forKey: "ringSectionExpanded")
        }
    }

    @Published var showComplicationPicker = false
    @Published var isLoading = false
    
    var availableComplications: [ComplicationData] {
        [
            ComplicationData(title: "Active Energy", value: metrics.activeEnergy, unit: "kcal", icon: "flame.fill", category: .general, isActivityRing: true),
            
            ComplicationData(title: "Steps", value: metrics.steps, unit: "steps", icon: "figure.walk", category: .general, isActivityRing: false),
            
            ComplicationData(title: "Distance", value: metrics.distance, unit: "km", icon: "figure.walk", category: .general, isActivityRing: false),
            
            ComplicationData(title: "Stand Hours", value: metrics.standHours, unit: "hr", icon: "figure.stand", category: .general, isActivityRing: true),
            ComplicationData(title: "Flights Climbed", value: metrics.flights, unit: "floors", icon: "stairs", category: .general, isActivityRing: false),
            
            ComplicationData(title: "Exercise", value: metrics.exercise, unit: "min", icon: "figure.run", category: .general, isActivityRing: true),
           
            ComplicationData(title: "Mindfulness", value: metrics.mindfulnessMinutes, unit: "min", icon: "brain.head.profile", category: .general, isActivityRing: false),
        ]
    }
    
    private let goalsKey = "complicationGoals"
    private let ringsKey = "activeRings"
    
    struct RingLayer: Identifiable, Codable {
        let id: UUID
        var title: String
        var value: Double
        var goal: Double
        var colorRed: Double
        var colorGreen: Double
        var colorBlue: Double
        var unit: String
        
        var color: Color {
            Color(red: colorRed, green: colorGreen, blue: colorBlue)
        }
    }
    
    struct RingMetric: Identifiable, Codable {
        let id: UUID
        var name: String
        var layers: [RingLayer]
        
        enum CodingKeys: CodingKey {
            case id, name, layers
        }
        
        init(id: UUID = UUID(), name: String, layers: [RingLayer]) {
            self.id = id
            self.name = name
            self.layers = layers
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            layers = try container.decode([RingLayer].self, forKey: .layers)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(layers, forKey: .layers)
        }
    }
    
    init(healthStore: HealthKitManager) {
        self.healthStore = healthStore
        self.isRingSectionExpanded = UserDefaults.standard.bool(forKey: "ringSectionExpanded") || activeRings.count >= 1
        loadSavedRings()
        setupCloudSync()
    }
    
    func saveGoal(title: String, goal: Double) {
        var goals = UserDefaults.standard.dictionary(forKey: goalsKey) as? [String: Double] ?? [:]
        goals[title] = goal
        UserDefaults.standard.set(goals, forKey: goalsKey)
        NSUbiquitousKeyValueStore.default.set(goals, forKey: goalsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func loadGoal(for title: String) -> Double? {
        let goals = UserDefaults.standard.dictionary(forKey: goalsKey) as? [String: Double]
        return goals?[title]
    }
    
    private func saveRings() {
        if let encoded = try? JSONEncoder().encode(activeRings) {
            UserDefaults.standard.set(encoded, forKey: ringsKey)
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: ringsKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
    
    private func loadSavedRings() {
        if let cloudData = NSUbiquitousKeyValueStore.default.data(forKey: ringsKey),
           let decoded = try? JSONDecoder().decode([RingMetric].self, from: cloudData) {
            activeRings = decoded
        } else if let localData = UserDefaults.standard.data(forKey: ringsKey),
                  let decoded = try? JSONDecoder().decode([RingMetric].self, from: localData) {
            activeRings = decoded
        }
    }
    
    private func setupCloudSync() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquitousKeyValueStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
    }
    
    @objc private func ubiquitousKeyValueStoreDidChange(_ notification: Notification) {
        loadSavedRings()
    }
    
    @MainActor
    func loadHealthData() async {
        let healthTypes: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .basalEnergyBurned,
            .stepCount,
            .distanceWalkingRunning,
            .appleExerciseTime,
            .appleStandTime,
            .flightsClimbed,
            .walkingSpeed,
            .walkingAsymmetryPercentage,
            .walkingStepLength,
            .walkingDoubleSupportPercentage,
            .walkingHeartRateAverage,
            .runningSpeed,
            .runningPower,
            .vo2Max,
            .respiratoryRate,
            .heartRateRecoveryOneMinute,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .distanceSwimming,
            .distanceCycling
        ]

        for type in healthTypes {
            if let quantity = try? await healthStore.fetchTodayQuantity(for: type) {
                await MainActor.run {
                    switch type {
                    case .activeEnergyBurned: metrics.activeEnergy = String(format: "%.0f", quantity)
                    case .stepCount: metrics.steps = String(format: "%.0f", quantity)
                    case .distanceWalkingRunning: metrics.distance = String(format: "%.1f", quantity/1000)
                    case .appleExerciseTime: metrics.exercise = String(format: "%.0f", quantity)
                    case .appleStandTime:
                        metrics.standHours = String(format: "%.0f", quantity/60)
                    case .flightsClimbed: metrics.flights = String(format: "%.0f", quantity)
                    default: break
                    }
                }
            }
        }
        
        if let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            let mindfulPredicate = HKQuery.predicateForSamples(
                withStart: Calendar.current.startOfDay(for: Date()),
                end: Date(),
                options: .strictStartDate
            )
            
            if let minutes = try? await healthStore.fetchSum(for: mindfulType, predicate: mindfulPredicate) {
                metrics.mindfulnessMinutes = String(format: "%.0f", minutes)
            }
        }
        
        await loadWorkoutMetrics()
    }

    func loadWorkoutMetrics() async {
        let types: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .basalEnergyBurned,
            .stepCount,
            .distanceWalkingRunning,
            .appleExerciseTime,
            .appleStandTime,
            .flightsClimbed,
            .walkingSpeed,
            .walkingAsymmetryPercentage,
            .walkingStepLength,
            .walkingDoubleSupportPercentage,
            .walkingHeartRateAverage,
            .runningSpeed,
            .runningPower,
            .vo2Max,
            .respiratoryRate,
            .heartRateRecoveryOneMinute,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .distanceSwimming,
            .distanceCycling
        ]
        
        // Load health data
        for type in types {
            if let quantity = try? await healthStore.fetchTodayQuantity(for: type) {
                await MainActor.run {
                    switch type {
                    case .activeEnergyBurned: metrics.activeEnergy = String(format: "%.0f", quantity)
                    case .stepCount: metrics.steps = String(format: "%.0f", quantity)
                    case .distanceWalkingRunning: metrics.distance = String(format: "%.1f", quantity/1000)
                    case .appleExerciseTime: metrics.exercise = String(format: "%.0f", quantity)
                    case .appleStandTime:
                        metrics.standHours = String(format: "%.0f", quantity/60)
                    case .flightsClimbed: metrics.flights = String(format: "%.0f", quantity)
                    default: break
                    }
                }
            }
        }
        
        // Load mindfulness data
        if let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            let today = Calendar.current.startOfDay(for: Date())
            let mindfulPredicate = HKQuery.predicateForSamples(
                withStart: today,
                end: Date(),
                options: .strictStartDate
            )
            
            let sendablePredicate = SendablePredicate(mindfulPredicate)
            if let mindfulSamples = try? await healthStore.samples(for: mindfulType, predicate: sendablePredicate.predicate) {
                await MainActor.run {
                    let totalMinutes = mindfulSamples.reduce(0.0) { sum, sample in
                        sum + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    }
                    metrics.mindfulnessMinutes = String(format: "%.0f", totalMinutes)
                }
            }
        }
    }
    
    @MainActor
    private func updateMetric(type: HKQuantityTypeIdentifier, value: Double) {
        switch type {
        case .activeEnergyBurned:
            metrics.activeEnergy = String(format: "%.0f", value)
        case .stepCount:
            metrics.steps = String(format: "%.0f", value)
        case .distanceWalkingRunning:
            metrics.distance = String(format: "%.1f", value/1000)
        case .appleExerciseTime:
            metrics.exercise = String(format: "%.0f", value)
        case .appleStandTime:
            metrics.standHours = String(format: "%.0f", value/60)
        case .flightsClimbed:
            metrics.flights = String(format: "%.0f", value)
        default:
            break
        }
    }
}

struct ActivityRingView: View {
    let metric: DashboardViewModel.RingMetric
    @State private var animatedValues: [UUID: Double] = [:]
    
    var body: some View {
        VStack(spacing: 16) {
            // Ring Display
            ZStack {
                ForEach(metric.layers) { layer in
                    Circle()
                        .stroke(lineWidth: 20)
                        .opacity(0.3)
                        .foregroundColor(layer.color)
                    
                    Circle()
                        .trim(from: 0, to: min(animatedValues[layer.id] ?? 0, 1.0))
                        .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .foregroundColor(layer.color)
                        .rotationEffect(.degrees(-90))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onAppear {
                for layer in metric.layers {
                    withAnimation(.spring(response: 1.5, dampingFraction: 0.8, blendDuration: 0.8)) {
                        animatedValues[layer.id] = layer.value / layer.goal
                    }
                }
            }
            
            // Name and Metrics Row
            HStack(alignment: .center, spacing: 12) {
                Text(metric.name)
                    .font(.headline)
                
                Divider()
                    .frame(height: 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(metric.layers) { layer in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(layer.color)
                                    .frame(width: 8, height: 8)
                                Text(layer.title)
                                    .font(.caption)
                                Text(String(format: "%.0f \(layer.unit)", layer.value))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel(healthStore: HealthKitManager())
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var animationPhase: Double = 0
    @State private var rings: [DashboardViewModel.RingMetric] = []
    
    init() {
        let healthStore = HealthKitManager()
        _viewModel = StateObject(wrappedValue: DashboardViewModel(healthStore: healthStore))
    }
    
    private var adaptiveGridColumns: [GridItem] {
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible()), count: columnCount)
    }
    
    private var maxVisibleComplications: Int {
        horizontalSizeClass == .regular ? 8 : 4
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.activeRings.isEmpty {
                        DisclosureGroup(
                            isExpanded: $viewModel.isRingSectionExpanded,
                            content: {
                                FormTipsStyleRingScroll(rings: $viewModel.activeRings)
                                    .frame(minHeight: UIDevice.current.userInterfaceIdiom == .phone ? 360 : 510)
                                        .frame(maxHeight: .infinity)
                                    .padding()
                            },
                            label: {
                                Label("Activity Rings", systemImage: "circle.circle")
                                    .font(.headline)
                            }
                        )
                        .padding(.horizontal)
                    } else {
                        EmptyRingDropTarget(rings: $viewModel.activeRings)
                            .padding(.horizontal)
                    }

                    LazyVGrid(columns: adaptiveGridColumns, spacing: 20) {
                        ForEach(Array(viewModel.selectedComplications), id: \.id) { complication in
                            ActivityComplication(
                                viewModel: viewModel,
                                title: complication.title,
                                value: complication.value,
                                unit: complication.unit,
                                icon: complication.icon,
                                isActivityRing: complication.isActivityRing
                            )
                        }
                        
                        // Default Complications
                        if viewModel.selectedComplications.isEmpty {
                            ActivityComplication(
                                viewModel: viewModel,
                                title: "Active Energy",
                                value: viewModel.metrics.activeEnergy,
                                unit: "kcal",
                                icon: "flame.fill",
                                isActivityRing: true
                            )
                            
                            ActivityComplication(
                                viewModel: viewModel,
                                title: "Steps",
                                value: viewModel.metrics.steps,
                                unit: "steps",
                                icon: "figure.walk",
                                isActivityRing: false
                            )
                            
                            ActivityComplication(
                                viewModel: viewModel,
                                title: "Distance",
                                value: viewModel.metrics.distance,
                                unit: "km",
                                icon: "figure.run",
                                isActivityRing: false
                            )
                            
                            ActivityComplication(
                                viewModel: viewModel,
                                title: "Exercise",
                                value: viewModel.metrics.exercise,
                                unit: "min",
                                icon: "timer",
                                isActivityRing: true
                            )
                        }
                        
                        if viewModel.selectedComplications.count < maxVisibleComplications {
                            Button {
                                viewModel.showComplicationPicker = true
                            } label: {
                                VStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title)
                                    Text("Add Complication")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .aspectRatio(1.6, contentMode: .fit)
                                .background(.ultraThinMaterial)
                                .cornerRadius(15)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    if !viewModel.metrics.workouts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent Workouts")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 15) {
                                    ForEach(viewModel.metrics.workouts, id: \.uuid) { workout in
                                        DashboardWorkoutRow(workout: workout)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .background(
                GradientBackgrounds()
                    .burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showComplicationPicker = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showComplicationPicker) {
                NavigationStack {
                    ComplicationPickerView(viewModel: viewModel, healthStore: HealthKitManager(), rings: $rings)
                }
            }
        }
        .task {
            await viewModel.loadHealthData()
        }
    }
}

struct DashboardWorkoutRow: View {
    let workout: HKWorkout
    private let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.red)
                if let statistics = workout.statistics(for: HKQuantityType(.activeEnergyBurned)),
                   let calories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    Text(String(format: "%.0f", calories))
                        + Text(" kcal")
                        .foregroundStyle(.secondary)
                } else {
                    Text("-- kcal")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)
                Text(formatter.string(from: workout.duration) ?? "")
                    .font(.subheadline)
            }
            Text(workoutName(for: workout.workoutActivityType))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
    
    private func workoutName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "Running"
        case .cycling:
            return "Cycling"
        case .walking:
            return "Walking"
        case .swimming:
            return "Swimming"
        case .hiking:
            return "Hiking"
        case .yoga:
            return "Yoga"
        case .functionalStrengthTraining:
            return "Strength"
        case .traditionalStrengthTraining:
            return "Weights"
        case .highIntensityIntervalTraining:
            return "HIIT"
        default:
            return "Workout"
        }
    }
}

struct RecoveryStatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery Status")
                .font(.title3)
                .bold()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("85%")
                        .font(.title)
                        .bold()
                    Text("Ready for Peak Performance")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                Spacer()
                CircularProgressView(progress: 0.85)
                    .frame(width: 60, height: 60)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}

struct WeeklyProgressChart: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    struct ActivityData: Identifiable, Equatable {
        let id = UUID()
        let day: String
        let moveScore: Double
        let exerciseScore: Double
        let standScore: Double
        
        static func == (lhs: ActivityData, rhs: ActivityData) -> Bool {
            lhs.day == rhs.day &&
            lhs.moveScore == rhs.moveScore &&
            lhs.exerciseScore == rhs.exerciseScore &&
            lhs.standScore == rhs.standScore
        }
    }

    private func fetchWeeklyActivityData() async -> [ActivityData] {
        var activityData: [ActivityData] = []
        let calendar = Calendar.current
        
        let goals = try? await viewModel.healthStore.fetchActivityGoals()
        let activeEnergyGoal = goals?.activeEnergy ?? 600
        let exerciseGoal = goals?.exerciseTime ?? 30
        let standGoal = goals?.standHours ?? 12
        
        for daysAgo in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let activeEnergy = try? await viewModel.healthStore.fetchQuantity(for: .activeEnergyBurned, start: startOfDay, end: endOfDay)
            let exerciseMinutes = try? await viewModel.healthStore.fetchQuantity(for: .appleExerciseTime, start: startOfDay, end: endOfDay)
            let standHours = try? await viewModel.healthStore.fetchQuantity(for: .appleStandTime, start: startOfDay, end: endOfDay)
            
            let energyScore = min((activeEnergy ?? 0) / activeEnergyGoal, 1.0) * 40
            let exerciseScore = min((exerciseMinutes ?? 0) / exerciseGoal, 1.0) * 40
            let standScore = min((standHours ?? 0) / standGoal, 1.0) * 20
            
            let weekdaySymbol = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            
            activityData.append(ActivityData(
                day: weekdaySymbol,
                moveScore: energyScore,
                exerciseScore: exerciseScore,
                standScore: standScore
            ))
        }
        
        return activityData
    }
    
    @State private var weeklyData: [ActivityData] = []
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Progress")
                .font(.title3)
                .bold()
            Text("Your familiar rings, powering your week")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Chart(weeklyData) { item in
                Plot {
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Move", item.moveScore)
                    )
                    .foregroundStyle(item.moveScore/40 >= 0.8 ?
                        Gradient(colors: [Color(red: 255/255, green: 46/255, blue: 84/255), .orange, .yellow]) :
                        Gradient(colors: [Color(red: 255/255, green: 46/255, blue: 84/255)]))
                    
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Exercise", item.exerciseScore)
                    )
                    .foregroundStyle(item.exerciseScore/40 >= 0.8 ?
                        Gradient(colors: [Color(red: 76/255, green: 217/255, blue: 100/255), .mint, .yellow]) :
                        Gradient(colors: [Color(red: 76/255, green: 217/255, blue: 100/255)]))
                    
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Stand", item.standScore)
                    )
                    .foregroundStyle(item.standScore/20 >= 0.8 ?
                        Gradient(colors: [Color(red: 0/255, green: 122/255, blue: 255/255), .cyan, .white]) :
                        Gradient(colors: [Color(red: 0/255, green: 122/255, blue: 255/255)]))
                }
            }

            .animation(.easeInOut(duration: 0.3), value: weeklyData)
            .frame(height: 200)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .task {
            weeklyData = await fetchWeeklyActivityData()
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                LinearGradient(
                    colors: [.blue, .green],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }
}

extension UTType {
    static var activityComplication: UTType {
        UTType(exportedAs: "com.nutrivance.activitycomplication")
    }
}

struct ActivityComplicationTransferData: Transferable, Codable {
    let title: String
    let value: String
    let unit: String
    let customGoal: Double?
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .activityComplication)
    }
}

enum ComplicationCategory {
    case general
    case sports
}

struct ComplicationInfo: Identifiable {
    let id = UUID()
    let title: String
    let valueKey: String
    let unit: String
    let icon: String
    let isActivityRing: Bool
    let category: ComplicationCategory
}

struct ComplicationPickerView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var healthStore: HealthKitManager
    @Binding var rings: [DashboardViewModel.RingMetric]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private let categories = [
        "General Health": [
            ComplicationInfo(title: "Active Energy", valueKey: "activeEnergy", unit: "kcal", icon: "flame.fill", isActivityRing: true, category: .general),
            ComplicationInfo(title: "Steps", valueKey: "steps", unit: "steps", icon: "figure.walk", isActivityRing: false, category: .general),
            ComplicationInfo(title: "Distance", valueKey: "distance", unit: "km", icon: "figure.walk.motion", isActivityRing: false, category: .general),
            ComplicationInfo(title: "Exercise", valueKey: "exercise", unit: "min", icon: "figure.run", isActivityRing: true, category: .general),
            ComplicationInfo(title: "Stand", valueKey: "standHours", unit: "hrs", icon: "figure.stand", isActivityRing: true, category: .general),
            ComplicationInfo(title: "Flights Climbed", valueKey: "flights", unit: "floors", icon: "stairs", isActivityRing: false, category: .general),
            ComplicationInfo(title: "Mindfulness", valueKey: "mindfulnessMinutes", unit: "min", icon: "brain.head.profile", isActivityRing: false, category: .general)
        ],
//        "Sports": [
//            ComplicationInfo(title: "Swimming Distance", valueKey: "swimmingDistance", unit: "m", icon: "figure.pool.swim", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Swimming Strokes", valueKey: "swimmingStrokes", unit: "count", icon: "figure.pool.swim", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Swimming Laps", valueKey: "swimmingLapCount", unit: "laps", icon: "figure.pool.swim", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Tennis", valueKey: "tennisStrokeCount", unit: "strokes", icon: "figure.tennis", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Badminton", valueKey: "badmintonMinutes", unit: "min", icon: "figure.badminton", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Paddle Sports", valueKey: "paddleSportsTime", unit: "min", icon: "figure.rowing", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Pickleball", valueKey: "pickleballMinutes", unit: "min", icon: "figure.tennis", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Golf", valueKey: "golfStrokes", unit: "strokes", icon: "figure.golf", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Jump Rope", valueKey: "jumpRopeReps", unit: "jumps", icon: "figure.jumprope", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Snowboarding", valueKey: "snowboardingDistance", unit: "km", icon: "snowflake", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Skiing", valueKey: "skiingDistance", unit: "km", icon: "figure.skiing.downhill", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Downhill Vertical", valueKey: "downhillSkiingVertical", unit: "m", icon: "mountain.2.fill", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Rowing Distance", valueKey: "rowingDistance", unit: "m", icon: "figure.rower", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Rowing Strokes", valueKey: "rowingStrokes", unit: "strokes", icon: "figure.rower", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Elliptical", valueKey: "ellipticalDistance", unit: "km", icon: "figure.elliptical", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Stair Stepper", valueKey: "stairStepperFloors", unit: "floors", icon: "figure.stair.stepper", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Tai Chi", valueKey: "taiChiMinutes", unit: "min", icon: "figure.mind.and.body", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Yoga", valueKey: "yogaTime", unit: "min", icon: "figure.yoga", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Flexibility", valueKey: "flexibilityMinutes", unit: "min", icon: "figure.flexibility", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Handball", valueKey: "handballMinutes", unit: "min", icon: "figure.handball", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Disc Sports", valueKey: "discSportsDistance", unit: "m", icon: "circle.fill", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Curling", valueKey: "curlingMinutes", unit: "min", icon: "figure.curling", isActivityRing: false, category: .sports),
//            ComplicationInfo(title: "Equestrian", valueKey: "equestrianMinutes", unit: "min", icon: "figure.equestrian.sports", isActivityRing: false, category: .sports)
//        ]
    ]
    
    private var availableComplications: [String: [ComplicationInfo]] {
        var filtered = categories
        for (category, complications) in filtered {
            filtered[category] = complications.filter { complication in
                !rings.contains { ring in
                    ring.layers.contains { layer in
                        layer.title == complication.title
                    }
                }
            }
        }
        filtered = filtered.filter { !$0.value.isEmpty }
        return filtered
    }
    
    var filteredCategories: [String: [ComplicationInfo]] {
        if searchText.isEmpty {
            return availableComplications
        }
        return availableComplications.mapValues { metrics in
            metrics.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }.filter { !$0.value.isEmpty }
    }
    
    private func getValue(for key: String) async -> String {
        let metrics: [String: HKQuantityTypeIdentifier] = [
            "activeEnergy": .activeEnergyBurned,
            "restingEnergy": .basalEnergyBurned,
            "steps": .stepCount,
            "distance": .distanceWalkingRunning,
            "standHours": .appleStandTime,
            "flights": .flightsClimbed,
            "exercise": .appleExerciseTime,
            "walkingSpeed": .walkingSpeed,
            "walkingAsymmetry": .walkingAsymmetryPercentage,
            "walkingStepLength": .walkingStepLength,
            "walkingDoubleSupport": .walkingDoubleSupportPercentage,
            "walkingHeartRate": .heartRate,
            "runningSpeed": .runningSpeed,
            "runningPower": .runningPower,
            "runningDistance": .distanceWalkingRunning,
            "cyclingDistance": .distanceCycling,
            "cyclingPower": .cyclingPower,
            "cyclingCadence": .cyclingCadence,
            "vo2Max": .vo2Max,
            "respiratoryRate": .respiratoryRate,
            "heartRateRecovery": .heartRate,
            "restingHeartRate": .restingHeartRate,
            "heartRateVariability": .heartRateVariabilitySDNN,
            "swimmingStrokes": .swimmingStrokeCount,
            "swimmingDistance": .distanceSwimming,
            "snowboardingDistance": .distanceDownhillSnowSports,
            "skiingDistance": .distanceDownhillSnowSports,
            "wheelchairDistance": .distanceWheelchair
        ]
        
        if let typeIdentifier = metrics[key] {
            let value = try? await healthStore.fetchTodayQuantity(for: typeIdentifier)
            if let value = value {
                switch key {
                case "distance", "cyclingDistance", "swimmingDistance", "snowboardingDistance", "skiingDistance", "wheelchairDistance":
                    return String(format: "%.1f", value/1000)
                case "standHours":
                    return String(format: "%.0f", value/60)
                case "walkingAsymmetry", "walkingDoubleSupport":
                    return String(format: "%.1f", value*100)
                default:
                    return String(format: "%.0f", value)
                }
            }
        }
        
        let mirror = Mirror(reflecting: viewModel.metrics)
        return mirror.children
            .first(where: { $0.label == key })?
            .value as? String ?? "0"
    }
    
    private func addComplication(_ info: ComplicationInfo) async {
        let value = await getValue(for: info.valueKey)
        let complication = ComplicationData(
            title: info.title,
            value: value,
            unit: info.unit,
            icon: info.icon,
            category: info.category,
            isActivityRing: info.isActivityRing
        )
        
        viewModel.selectedComplications.insert(complication)
        
        if let firstRing = rings.first(where: { $0.layers.count < 4 }) {
            if let ringIndex = rings.firstIndex(where: { $0.id == firstRing.id }) {
                let colors = getLayerColor(for: rings[ringIndex].layers.count)
                let newLayer = DashboardViewModel.RingLayer(
                    id: UUID(),
                    title: complication.title,
                    value: Double(value) ?? 0,
                    goal: getDefaultGoalFor(complication.title),
                    colorRed: colors.red,
                    colorGreen: colors.green,
                    colorBlue: colors.blue,
                    unit: complication.unit
                )
                rings[ringIndex].layers.append(newLayer)
            }
        }
    }
    
    private func getLayerColor(for index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 0: return (0.9, 0.2, 0.3)
        case 1: return (0.3, 0.85, 0.3)
        case 2: return (0.1, 0.5, 0.9)
        case 3: return (0.6, 0.2, 0.8)
        default: return (0.5, 0.5, 0.5)
        }
    }
    
    private func getDefaultGoalFor(_ metric: String) -> Double {
        switch metric {
        case "Steps": return 10000
        case "Distance": return 5
        case "Active Energy": return 500
        case "Stand": return 12
        case "Exercise": return 30
        case "Flights": return 10
        default: return 100
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories.keys.sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(filteredCategories[category] ?? [], id: \.title) { info in
                            Button {
                                Task {
                                    await addComplication(info)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Label(info.title, systemImage: info.icon)
                                    Spacer()
                                    Text(info.unit)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search metrics")
            .navigationTitle("Add Complication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private let generalHealthMetrics = [
        ComplicationInfo(title: "Active Energy", valueKey: "activeEnergy", unit: "kcal", icon: "flame.fill", isActivityRing: true, category: .general),
        ComplicationInfo(title: "Steps", valueKey: "steps", unit: "steps", icon: "figure.walk", isActivityRing: false, category: .general),
        ComplicationInfo(title: "Distance", valueKey: "distance", unit: "km", icon: "figure.walk.motion", isActivityRing: false, category: .general),
        ComplicationInfo(title: "Exercise", valueKey: "exercise", unit: "min", icon: "figure.run", isActivityRing: true, category: .general),
        ComplicationInfo(title: "Stand", valueKey: "standHours", unit: "hrs", icon: "figure.stand", isActivityRing: true, category: .general),
        ComplicationInfo(title: "Flights Climbed", valueKey: "flights", unit: "floors", icon: "stairs", isActivityRing: false, category: .general),
        ComplicationInfo(title: "Mindfulness", valueKey: "mindfulnessMinutes", unit: "min", icon: "brain.head.profile", isActivityRing: false, category: .general)
    ]

}



// Separate list view component
private struct ComplicationsListView: View {
    let complications: [ComplicationInfo]
    let viewModel: DashboardViewModel
    let onSelect: (ComplicationInfo) -> Void
    
    var body: some View {
        ForEach(complications) { info in
            ComplicationRowView(
                info: info,
                value: getValue(for: info.valueKey, from: viewModel),
                isSelected: isSelected(info)
            )
            .onTapGesture {
                onSelect(info)
            }
        }
    }
    
    private func getValue(for key: String, from viewModel: DashboardViewModel) -> String {
        let mirror = Mirror(reflecting: viewModel.metrics)
        return mirror.children
            .first(where: { $0.label == key })?
            .value as? String ?? "0"
    }
    
    private func isSelected(_ info: ComplicationInfo) -> Bool {
        viewModel.selectedComplications.contains { $0.title == info.title }
    }
}

// Row view component
private struct ComplicationRowView: View {
    let info: ComplicationInfo
    let value: String
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: info.icon)
                .foregroundStyle(info.isActivityRing ? .red : .blue)
            Text(info.title)
            Spacer()
            Text("\(value) \(info.unit)")
                .foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct ActivityRingCreator: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var ringName = ""
    @State private var selectedLayers: [DashboardViewModel.RingLayer] = []
    
    var body: some View {
        List {
            Section("Ring Details") {
                TextField("Ring Name", text: $ringName)
                
                ForEach(selectedLayers) { layer in
                    HStack {
                        Circle()
                            .fill(Color(red: layer.colorRed, green: layer.colorGreen, blue: layer.colorBlue))
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading) {
                            Text(layer.title)
                            Text("\(Int(layer.value))/\(Int(layer.goal)) \(layer.unit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if selectedLayers.count < 4 {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Drop Complication Here")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .dropDestination(for: ActivityComplicationTransferData.self) { complications, _ in
                        handleDroppedComplications(complications)
                        return true
                    }
                }
            }
            
            if !selectedLayers.isEmpty {
                Section {
                    VStack(alignment: .center) {
                        ZStack {
                            ForEach(Array(selectedLayers.enumerated()), id: \.element.id) { index, layer in
                                ActivityRing(
                                    progress: layer.value / layer.goal,
                                    gradient: Gradient(colors: [Color(red: layer.colorRed, green: layer.colorGreen, blue: layer.colorBlue)]),
                                    backgroundGradient: Gradient(colors: [Color(red: layer.colorRed, green: layer.colorGreen, blue: layer.colorBlue).opacity(0.2)])
                                )
                                .frame(width: 200 - CGFloat(index * 40), height: 200 - CGFloat(index * 40))
                            }
                        }
                        .frame(height: 220)
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("New Ring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createRing()
                    dismiss()
                }
                .disabled(ringName.isEmpty || selectedLayers.isEmpty)
            }
        }
    }
    
    private func handleDroppedComplications(_ complications: [ActivityComplicationTransferData]) {
        guard let complication = complications.first,
              selectedLayers.count < 4 else { return }
        
        let colors = getLayerColor(for: selectedLayers.count)
        let newLayer = DashboardViewModel.RingLayer(
            id: UUID(),
            title: complication.title,
            value: Double(complication.value) ?? 0,
            goal: complication.customGoal ?? 100,
            colorRed: colors.red,
            colorGreen: colors.green,
            colorBlue: colors.blue,
            unit: complication.unit
        )
        
        selectedLayers.append(newLayer)
    }
    
    private func getLayerColor(for index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 0: return (red: 0.9, green: 0.2, blue: 0.3)
        case 1: return (red: 0.3, green: 0.85, blue: 0.3)
        case 2: return (red: 0.1, green: 0.5, blue: 0.9)
        case 3: return (red: 0.6, green: 0.2, blue: 0.8)
        default: return (red: 0.5, green: 0.5, blue: 0.5)
        }
    }
    
    private func createRing() {
        let newRing = DashboardViewModel.RingMetric(
            name: ringName,
            layers: selectedLayers
        )
        viewModel.activeRings.append(newRing)
    }
}

private struct EmptyRingDropTarget: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    
    var body: some View {
        let circleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 275 : 350
        
        Circle()
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
            .frame(width: circleSize, height: circleSize)
            .foregroundColor(.secondary)
            .overlay(
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: circleSize * 0.9, height: circleSize * 0.9)
            )
            .dropDestination(for: ActivityComplicationTransferData.self) { complications, _ in
                handleNewRingFromComplications(complications)
                return true
            }
            .overlay(
                Text("Drop Complication Here\nto Create New Ring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            )
    }

    private func handleNewRingFromComplications(_ complications: [ActivityComplicationTransferData]) {
        guard let firstComplication = complications.first else { return }
        
        let colors = getDefaultColors(for: 0)
        let firstLayer = DashboardViewModel.RingLayer(
            id: UUID(),
            title: firstComplication.title,
            value: Double(firstComplication.value) ?? 0,
            goal: firstComplication.customGoal ?? 100,
            colorRed: colors.red,
            colorGreen: colors.green,
            colorBlue: colors.blue,
            unit: firstComplication.unit
        )
        
        let newRing = DashboardViewModel.RingMetric(
            name: "Ring \(rings.count + 1)",
            layers: [firstLayer]
        )
        rings.append(newRing)
    }
    
    private func getDefaultColors(for index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 0: return (red: 0.9, green: 0.2, blue: 0.3)  // Deep red
        case 1: return (red: 0.3, green: 0.85, blue: 0.3) // Rich green
        case 2: return (red: 0.1, green: 0.5, blue: 0.9)  // Deep blue
        case 3: return (red: 0.6, green: 0.2, blue: 0.8)  // Rich purple
        default: return (red: 0.5, green: 0.5, blue: 0.5) // Gray
        }
    }
}

private struct EmptyRingView: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    
    private func getDefaultColors(for index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 0: return (red: 0.9, green: 0.2, blue: 0.3)
        case 1: return (red: 0.3, green: 0.85, blue: 0.3)
        case 2: return (red: 0.1, green: 0.5, blue: 0.9)
        case 3: return (red: 0.6, green: 0.2, blue: 0.8)
        default: return (red: 0.5, green: 0.5, blue: 0.5)
        }
    }
    
    private func handleNewRingFromComplications(_ complications: [ActivityComplicationTransferData]) {
        guard let firstComplication = complications.first else { return }
        
        let colors = getDefaultColors(for: rings.count)
        let firstLayer = DashboardViewModel.RingLayer(
            id: UUID(),
            title: firstComplication.title,
            value: Double(firstComplication.value) ?? 0,
            goal: firstComplication.customGoal ?? 100,
            colorRed: colors.red,
            colorGreen: colors.green,
            colorBlue: colors.blue,
            unit: firstComplication.unit
        )
        
        let newRing = DashboardViewModel.RingMetric(
            name: "Ring \(rings.count + 1)",
            layers: [firstLayer]
        )
        rings.append(newRing)
    }
    
    var body: some View {
        VStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .frame(width: 350, height: 350)
                .foregroundColor(.secondary)
                .overlay(
                    Text("Drop Complication Here\nto Create New Ring")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                )
                .padding()
        }
        .dropDestination(for: ActivityComplicationTransferData.self) { complications, _ in
            handleNewRingFromComplications(complications)
            return true
        }
    }
}

struct RingCard: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    let ring: DashboardViewModel.RingMetric
    
    var body: some View {
        RingItemView(rings: $rings, ring: ring)
            .dropDestination(for: ActivityComplicationTransferData.self) { complications, _ in
                if ring.layers.count < 4 {
                    handleDroppedComplications(complications, for: ring)
                    return true
                }
                return false
            }
            .padding()
    }
    
    private func handleDroppedComplications(_ complications: [ActivityComplicationTransferData], for ring: DashboardViewModel.RingMetric) {
        guard let firstComplication = complications.first,
              let ringIndex = rings.firstIndex(where: { $0.id == ring.id }) else { return }
        
        let colors = getLayerColor(for: rings[ringIndex].layers.count)
        let newLayer = DashboardViewModel.RingLayer(
            id: UUID(),
            title: firstComplication.title,
            value: Double(firstComplication.value) ?? 0,
            goal: firstComplication.customGoal ?? 100,
            colorRed: colors.red,
            colorGreen: colors.green,
            colorBlue: colors.blue,
            unit: firstComplication.unit
        )
        
        rings[ringIndex].layers.append(newLayer)
    }
    
    private func getLayerColor(for index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 0: return (0.9, 0.2, 0.3)  // Deep red
        case 1: return (0.3, 0.85, 0.3) // Rich green
        case 2: return (0.1, 0.5, 0.9)  // Deep blue
        case 3: return (0.6, 0.2, 0.8)  // Rich purple
        default: return (0.5, 0.5, 0.5) // Gray
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct ActivityComplication: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showGoalSheet = false
    let title: String
    let value: String
    let unit: String
    let icon: String
    let isActivityRing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(isActivityRing ? .red : .blue)
                Text(title)
                    .font(.caption)
            }
            
            Text("\(value) \(unit)")
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .contextMenu {
            if !isActivityRing {
                Button(action: {
                    showGoalSheet = true
                }) {
                    Label("Set Goal", systemImage: "target")
                }
            }
            
            Button(action: {
                withAnimation {
                    viewModel.showRingCard = true
                }
            }) {
                Label("Make Ring", systemImage: "circle")
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            NavigationStack {
                GoalSettingView(goal: .constant(100)) // Replace with actual goal binding
                    .navigationTitle("Set Goal")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .draggable(ActivityComplicationTransferData(
            title: title,
            value: value,
            unit: unit,
            customGoal: nil
        ))
    }
}

struct GoalSettingView: View {
    @Binding var goal: Double
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField("Goal Value", value: $goal, format: .number)
                    .keyboardType(.decimalPad)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

struct RingItemView: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    let ring: DashboardViewModel.RingMetric
    @State private var showEditSheet = false
    @State private var showRingDetail = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: UIDevice.current.userInterfaceIdiom == .phone ? 16 : 8) {
                ringStack
                Text(ring.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                if UIDevice.current.userInterfaceIdiom != .phone {
                    metricsStack
                }
            }
            .frame(width: UIDevice.current.userInterfaceIdiom == .phone ? 225 : 350,
                   height: UIDevice.current.userInterfaceIdiom == .phone ? 225 : 350)
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(15)
            .onTapGesture {
                showRingDetail = true
            }
            .sheet(isPresented: $showRingDetail) {
                RingDetailView(ring: ring)
            }
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation {
                        rings.removeAll { $0.id == ring.id }
                    }
                } label: {
                    Label("Delete Ring", systemImage: "trash")
                }
                
                Button {
                    showEditSheet = true
                } label: {
                    Label("Edit Ring", systemImage: "pencil")
                }
            }
            .sheet(isPresented: $showEditSheet) {
                NavigationStack {
                    RingEditView(rings: $rings, ring: ring, editedRingName: ring.name)
                }
            }
        }
    }
    
    private var ringStack: some View {
        let baseSize: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 210 : 270
        let layerSpacing: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 36 : 40
        
        return ZStack {
            if let outerRing = ring.layers.first {
                ActivityRing(
                    progress: outerRing.value / outerRing.goal,
                    gradient: Gradient(colors: [outerRing.color, outerRing.color]),
                    backgroundGradient: Gradient(colors: [outerRing.color.opacity(0.2)])
                )
                .frame(width: baseSize, height: baseSize)
            }
            
            ForEach(Array(ring.layers.dropFirst().enumerated()), id: \.element.id) { index, layer in
                ActivityRing(
                    progress: layer.value / layer.goal,
                    gradient: Gradient(colors: [layer.color, layer.color]),
                    backgroundGradient: Gradient(colors: [layer.color.opacity(0.2)])
                )
                .frame(width: baseSize - layerSpacing * CGFloat(index + 1),
                       height: baseSize - layerSpacing * CGFloat(index + 1))
            }
        }
    }

    struct ActivityRing: View {
        let progress: Double
        let gradient: Gradient
        let backgroundGradient: Gradient
        @State private var animatedProgress: Double = 0
        
        var body: some View {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(gradient: backgroundGradient, center: .center),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        AngularGradient(gradient: gradient, center: .center),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .onChange(of: progress) { oldValue, newValue in
                animatedProgress = 0
                withAnimation(.spring(response: 1.2, dampingFraction: 0.9, blendDuration: 0.9)) {
                    animatedProgress = min(newValue, 1.0)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 1.2, dampingFraction: 0.9, blendDuration: 0.9)) {
                    animatedProgress = min(progress, 1.0)
                }
            }
        }
    }

    private func ringSize(for index: Int, baseSize: CGFloat) -> CGFloat {
        baseSize - CGFloat(index + 1) * (UIDevice.current.userInterfaceIdiom == .phone ? 17.5 : 35)
    }
    
    private var metricsStack: some View {
        VStack {
            ForEach(ring.layers) { layer in
                HStack {
                    Text(layer.title)
                        .foregroundColor(.primary)
                    Text("\(Int(layer.value))/\(Int(layer.goal)) \(layer.unit)")
                        .foregroundColor(.primary)
                }
                .font(.caption)
            }
        }
    }
    
    private func ringSize(for index: Int) -> CGFloat {
        280 - CGFloat(index + 1) * 35
    }
}


struct RingEditView: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    let ring: DashboardViewModel.RingMetric
    @Environment(\.dismiss) private var dismiss
    @State var editedRingName: String
    @State private var editMode: EditMode = .inactive
    
    private var nameSection: some View {
        Section("Ring Name") {
            TextField("Ring Name", text: $editedRingName)
                .onChange(of: editedRingName) { _, newValue in
                    if let index = rings.firstIndex(where: { $0.id == ring.id }) {
                        rings[index].name = newValue
                    }
                }
        }
    }
    
    private var layersSection: some View {
        Section("Ring Layers") {
            ForEach(ring.layers) { layer in
                DisclosureGroup {
                    VStack(spacing: 12) {
                        ColorPicker(selection: Binding(
                            get: {
                                Color(red: layer.colorRed, green: layer.colorGreen, blue: layer.colorBlue)
                            },
                            set: { newColor in
                                if let ringIndex = rings.firstIndex(where: { $0.id == ring.id }),
                                   let layerIndex = rings[ringIndex].layers.firstIndex(where: { $0.id == layer.id }) {
                                    let components = newColor.components
                                    rings[ringIndex].layers[layerIndex].colorRed = components.red
                                    rings[ringIndex].layers[layerIndex].colorGreen = components.green
                                    rings[ringIndex].layers[layerIndex].colorBlue = components.blue
                                }
                            }
                        )) {
                            HStack {
                                Circle()
                                    .fill(layer.color)
                                    .frame(width: 20, height: 20)
                                Text("Ring Color")
                            }
                        }
                        
                        HStack {
                            Text("Goal")
                            Spacer()
                            TextField("Goal", value: Binding(
                                get: { layer.goal },
                                set: { newValue in
                                    if let ringIndex = rings.firstIndex(where: { $0.id == ring.id }),
                                       let layerIndex = rings[ringIndex].layers.firstIndex(where: { $0.id == layer.id }) {
                                        rings[ringIndex].layers[layerIndex].goal = newValue
                                    }
                                }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            Text(layer.unit)
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    HStack {
                        Text(layer.title)
                        Spacer()
                        Text("\(Int(layer.value))/\(Int(layer.goal)) \(layer.unit)")
                    }
                }
            }
            .onMove(perform: editMode == .active ? moveLayer : nil)
            .onDelete(perform: editMode == .active ? deleteLayer : nil)
        }
    }
    
    private func moveLayer(from source: IndexSet, to destination: Int) {
        if let ringIndex = rings.firstIndex(where: { $0.id == ring.id }) {
            rings[ringIndex].layers.move(fromOffsets: source, toOffset: destination)
        }
    }
    
    private func deleteLayer(at offsets: IndexSet) {
        if let ringIndex = rings.firstIndex(where: { $0.id == ring.id }) {
            rings[ringIndex].layers.remove(atOffsets: offsets)
        }
    }
    
    var body: some View {
        List {
            nameSection
            layersSection
        }
        .navigationTitle("Edit Ring")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {
                    Text(editMode == .active ? "Done" : "Edit")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct ActivityRing: View {
    let progress: Double
    let gradient: Gradient
    let backgroundGradient: Gradient
    let strokeWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 18 : 20
    
    init(progress: Double, gradient: Gradient, backgroundGradient: Gradient? = nil) {
        self.progress = progress
        self.gradient = gradient
        self.backgroundGradient = backgroundGradient ?? Gradient(colors: [Color.gray.opacity(0.2)])
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(gradient: backgroundGradient, center: .center),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: gradient, center: .center),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

extension Color {
    var components: (red: Double, green: Double, blue: Double, alpha: Double) {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}

extension HealthKitManager {
    func fetchTodayWorkouts() async throws -> [HKWorkout] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            
            self.healthStore.execute(query)
        }
    }
}

struct FormTipsStyleRingScroll: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    @State private var currentIndex = 0
    @State private var isUserInteracting = false
    @AppStorage("ringsAutoScroll") private var autoScrollEnabled = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var lastDragPosition: CGFloat = 0
    
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    private var ringSize: CGFloat {
        switch horizontalSizeClass {
        case .regular:
            return UIScreen.main.bounds.width > 1000 ? 400 : 350
        default:
            return 300
        }
    }
    
    private var totalItems: Int {
        rings.count < 5 ? rings.count + 1 : rings.count
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: UIDevice.current.userInterfaceIdiom == .phone ? 20 : 30) {
                HStack {
                    Spacer()
                    Toggle("Auto", isOn: $autoScrollEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                        .labelsHidden()
                        .padding()
                }
                .padding(.horizontal)
                .padding(.top, UIDevice.current.userInterfaceIdiom == .phone ? 20 : 10)
                
                ZStack {
                    ForEach(rings.indices, id: \.self) { index in
                        RingItemView(rings: $rings, ring: rings[index])
                            .frame(width: UIDevice.current.userInterfaceIdiom == .phone ? ringSize * 0.8 : ringSize,
                                   height: UIDevice.current.userInterfaceIdiom == .phone ? ringSize * 0.8 : ringSize)
                            .scaleEffect(index == currentIndex ? 1.0 : 0.8)
                            .opacity(getOpacity(for: index))
                            .offset(x: getOffset(for: index, in: geometry))
                            .zIndex(Double(index == currentIndex ? 1 : 0))
                            .dropDestination(for: ActivityComplicationTransferData.self) { complications, _ in
                                if rings[index].layers.count < 4 {
                                    handleDroppedComplications(complications, for: rings[index])
                                    return true
                                }
                                return false
                            }
                    }
                    
                    if rings.count < 5 {
                        EmptyRingDropTarget(rings: $rings)
                            .frame(width: UIDevice.current.userInterfaceIdiom == .phone ? ringSize * 0.8 : ringSize,
                                   height: UIDevice.current.userInterfaceIdiom == .phone ? ringSize * 0.8 : ringSize)
                            .scaleEffect(currentIndex == rings.count ? 1.0 : 0.8)
                            .opacity(getOpacity(for: rings.count))
                            .offset(x: getOffset(for: rings.count, in: geometry))
                            .zIndex(Double(currentIndex == rings.count ? 1 : 0))
                    }
                }
                .frame(maxWidth: .infinity)
                .gesture(
                    DragGesture()
                        .onChanged { _ in
                            isUserInteracting = true
                        }
                        .onEnded { value in
                            handleDragGesture(value)
                        }
                )

                if totalItems > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<totalItems, id: \.self) { index in
                            if index == rings.count {
                                Rectangle()
                                    .fill(currentIndex == index ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                    .rotationEffect(.degrees(45))
                                    .onTapGesture {
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        withAnimation(.spring()) {
                                            currentIndex = index
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                    .onTapGesture {
                                        isUserInteracting = true
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        withAnimation(.spring()) {
                                            currentIndex = index
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                            isUserInteracting = false
                                        }
                                    }
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            isUserInteracting = true
                                            isDragging = true
                                            let currentPosition = value.translation.width
                                            let dragDelta = (currentPosition - lastDragPosition) * -1
                                            let dragThreshold: CGFloat = 50
                                            
                                            if dragDelta > dragThreshold && currentIndex > 0 {
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                                withAnimation(.spring()) {
                                                    currentIndex -= 1
                                                }
                                                lastDragPosition = currentPosition
                                            } else if dragDelta < -dragThreshold && currentIndex < rings.count - 1 {
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                                withAnimation(.spring()) {
                                                    currentIndex += 1
                                                }
                                                lastDragPosition = currentPosition
                                            }
                                        }
                                        .onEnded { _ in
                                            isDragging = false
                                            isUserInteracting = false
                                            lastDragPosition = 0
                                            let generator = UIImpactFeedbackGenerator(style: .rigid)
                                            generator.impactOccurred()
                                        }
                                )

                            }
                        }
                    }
                    .padding(.top, UIDevice.current.userInterfaceIdiom == .phone ? 20 : 10)
                }
            }
            .onReceive(timer) { _ in
                guard !isUserInteracting &&
                      autoScrollEnabled &&
                      rings.count > 1 &&
                      currentIndex < rings.count else {
                    return
                }
                
                withAnimation(.spring()) {
                    currentIndex = (currentIndex + 1) % rings.count
                }
            }
            .frame(height: UIDevice.current.userInterfaceIdiom == .phone ? ringSize * 0.8 + 100 : ringSize + 80)
        }
    }

    
    private func handleDroppedComplications(_ complications: [ActivityComplicationTransferData], for ring: DashboardViewModel.RingMetric) {
        guard let firstComplication = complications.first,
              let ringIndex = rings.firstIndex(where: { $0.id == ring.id }) else { return }
        
        let colors = getLayerColor(for: rings[ringIndex].layers.count)
        let newLayer = DashboardViewModel.RingLayer(
            id: UUID(),
            title: firstComplication.title,
            value: Double(firstComplication.value) ?? 0,
            goal: firstComplication.customGoal ?? 100,
            colorRed: colors.red,
            colorGreen: colors.green,
            colorBlue: colors.blue,
            unit: firstComplication.unit
        )
        
        rings[ringIndex].layers.append(newLayer)
    }
    
    private func getOpacity(for index: Int) -> Double {
        let distance = abs(index - currentIndex)
        return 1.0 - Double(distance) * 0.3
    }
    
    private func getOffset(for index: Int, in geometry: GeometryProxy) -> CGFloat {
        let _ = (geometry.size.width - ringSize) / 2
        let distance = CGFloat(index - currentIndex)
        return distance * (ringSize + 40)
    }
    
    private func handleDragGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 50
        if value.translation.width > threshold && currentIndex > 0 {
            withAnimation(.spring()) {
                currentIndex -= 1
            }
        } else if value.translation.width < -threshold && currentIndex < totalItems - 1 {
            withAnimation(.spring()) {
                currentIndex += 1
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isUserInteracting = false
        }
    }
    
    private func getLayerColor(for index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 0: return (0.9, 0.2, 0.3)
        case 1: return (0.3, 0.85, 0.3)
        case 2: return (0.1, 0.5, 0.9)
        case 3: return (0.6, 0.2, 0.8)
        default: return (0.5, 0.5, 0.5)
        }
    }
}

extension HealthKitManager {
    func fetchSum(for categoryType: HKCategoryType, predicate: NSPredicate?) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let total = Double(samples?.count ?? 0)
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }
    
    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )
            
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            
            healthStore.execute(query)
        }
    }
}

extension HealthKitManager {
    nonisolated func samples(for categoryType: HKCategoryType, predicate: NSPredicate?) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = samples as? [HKCategorySample] ?? []
                continuation.resume(returning: categorySamples)
            }
            healthStore.execute(query)
        }
    }
}

struct SendablePredicate: @unchecked Sendable {
    let predicate: NSPredicate
    
    init(_ predicate: NSPredicate) {
        self.predicate = predicate
    }
}
