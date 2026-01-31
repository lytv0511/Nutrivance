import SwiftUI
import Charts
import HealthKit

struct DashboardMetrics {
    var activeEnergy: String = "0"
    var steps: String = "0"
    var distance: String = "0"
    var exercise: String = "0"
    var standHours: String = "0"
    var flights: String = "0"
    var mindfulnessMinutes: String = "0"
    
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
    
    var workouts: [HKWorkout] = []
    var timeInWorkoutZones: [String: String] = [:]
}

struct ComplicationData: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let valueKey: String
    let unit: String
    let icon: String
    let category: ComplicationCategory
    let isActivityRing: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, title, valueKey, unit, icon, category, isActivityRing
    }
    
    init(title: String, valueKey: String, unit: String, icon: String, category: ComplicationCategory, isActivityRing: Bool) {
        self.id = UUID()
        self.title = title
        self.valueKey = valueKey
        self.unit = unit
        self.icon = icon
        self.category = category
        self.isActivityRing = isActivityRing
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        valueKey = try container.decode(String.self, forKey: .valueKey)
        unit = try container.decode(String.self, forKey: .unit)
        icon = try container.decode(String.self, forKey: .icon)
        category = try container.decode(ComplicationCategory.self, forKey: .category)
        isActivityRing = try container.decode(Bool.self, forKey: .isActivityRing)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(valueKey, forKey: .valueKey)
        try container.encode(unit, forKey: .unit)
        try container.encode(icon, forKey: .icon)
        try container.encode(category, forKey: .category)
        try container.encode(isActivityRing, forKey: .isActivityRing)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ComplicationData, rhs: ComplicationData) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ComplicationInfo: Identifiable {
    let id = UUID()
    let title: String
    let valueKey: String
    let unit: String
    let icon: String
    let category: ComplicationCategory
    let isActivityRing: Bool
}

struct HealthMetrics {
    var activeEnergy: String = "0"
    var steps: String = "0"
    var distance: String = "0"
    var exerciseTime: String = "0"
    var standHours: String = "0"
    var flightsClimbed: String = "0"
    var heartRate: String = "0"
    var restingHeartRate: String = "0"
    var hrv: String = "0"
    var sleepHours: String = "0"
    var mindfulMinutes: String = "0"
    var protein: String = "0"
    var carbs: String = "0"
    var fats: String = "0"
    var water: String = "0"
    var calories: String = "0"
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
    @Published var showComplicationPicker = false
    @Published var showRingDetail: RingMetric?
    @Published var isRingSectionExpanded = true
    @Published var metrics = HealthMetrics()
    @Published var rings: [RingMetric] = []
    @Published var activeRings: [RingMetric] = []
   @Published var showRingCard: Bool = false
    @Published var isRefreshing = false
    let healthStore = HealthKitManager()
    private var updateTimer: Timer?
    
    @Published var selectedComplications: Set<ComplicationData> = [] {
        didSet {
            saveComplications()
        }
    }
    
    let defaultComplications: [ComplicationData] = [
        ComplicationData(title: "Active Energy", valueKey: "activeEnergy", unit: "cal", icon: "flame.fill", category: .general, isActivityRing: true),
        ComplicationData(title: "Steps", valueKey: "steps", unit: "steps", icon: "figure.walk", category: .general, isActivityRing: false),
        ComplicationData(title: "Distance", valueKey: "distance", unit: "km", icon: "figure.walk", category: .general, isActivityRing: false),
        ComplicationData(title: "Sleep Duration", valueKey: "sleepHours", unit: "hr", icon: "bed.double.fill", category: .general, isActivityRing: false)
    ]
    func value(for key: String) -> String {
        switch key {
        case "activeEnergy": return metrics.activeEnergy == "0" ? "--" : metrics.activeEnergy
        case "steps": return metrics.steps == "0" ? "--" : metrics.steps
        case "distance": return metrics.distance == "0" ? "--" : metrics.distance
        case "exerciseTime": return metrics.exerciseTime == "0" ? "--" : metrics.exerciseTime
        case "standHours": return metrics.standHours == "0" ? "--" : metrics.standHours
        case "flightsClimbed": return metrics.flightsClimbed == "0" ? "--" : metrics.flightsClimbed
        case "heartRate": return metrics.heartRate == "0" ? "--" : metrics.heartRate
        case "restingHeartRate": return metrics.restingHeartRate == "0" ? "--" : metrics.restingHeartRate
        case "hrv": return metrics.hrv == "0" ? "--" : metrics.hrv
        case "sleepHours": return metrics.sleepHours == "0" ? "--" : metrics.sleepHours
        case "mindfulMinutes": return metrics.mindfulMinutes == "0" ? "--" : metrics.mindfulMinutes
        case "protein": return metrics.protein == "0" ? "--" : metrics.protein
        case "carbs": return metrics.carbs == "0" ? "--" : metrics.carbs
        case "fats": return metrics.fats == "0" ? "--" : metrics.fats
        case "water": return metrics.water == "0" ? "--" : metrics.water
        case "calories": return metrics.calories == "0" ? "--" : metrics.calories
        default: return "--"
        }
    }
    
    @AppStorage("savedComplications") private(set) var savedComplicationsData: Data = Data()
    @AppStorage("savedRings") private var savedRingsData: Data = Data()
    
    init() {
        if let decoded = try? JSONDecoder().decode([RingMetric].self, from: savedRingsData) {
            rings = decoded
        } else {
            rings = [
                RingMetric(
                    id: UUID(),
                    name: "Move",
                    layers: [
                        RingLayer(
                            id: UUID(),
                            title: "Active Energy",
                            value: 0,
                            goal: 600,
                            unit: "cal",
                            color: .red
                        )
                    ]
                ),
                RingMetric(
                    id: UUID(),
                    name: "Exercise",
                    layers: [
                        RingLayer(
                            id: UUID(),
                            title: "Exercise Time",
                            value: 0,
                            goal: 30,
                            unit: "min",
                            color: .green
                        )
                    ]
                ),
                RingMetric(
                    id: UUID(),
                    name: "Stand",
                    layers: [
                        RingLayer(
                            id: UUID(),
                            title: "Stand Hours",
                            value: 0,
                            goal: 12,
                            unit: "hr",
                            color: .blue
                        )
                    ]
                )
            ]
        }
        
        if let decoded = try? JSONDecoder().decode([ComplicationData].self, from: savedComplicationsData),
           !decoded.isEmpty {
            // Update units for known complications with old values
            var updated = decoded
            for i in 0..<updated.count {
                switch updated[i].valueKey {
                case "standHours":
                    if updated[i].unit == "hr" {
                        updated[i] = ComplicationData(title: "Stand Minutes", valueKey: "standHours", unit: "min", icon: updated[i].icon, category: updated[i].category, isActivityRing: updated[i].isActivityRing)
                    }
                case "distance":
                    if updated[i].unit == "mi" {
                        updated[i] = ComplicationData(title: updated[i].title, valueKey: "distance", unit: "km", icon: updated[i].icon, category: updated[i].category, isActivityRing: updated[i].isActivityRing)
                    }
                case "water":
                    if updated[i].unit == "oz" {
                        updated[i] = ComplicationData(title: updated[i].title, valueKey: "water", unit: "mL", icon: updated[i].icon, category: updated[i].category, isActivityRing: updated[i].isActivityRing)
                    }
                default:
                    break
                }
            }
            selectedComplications = Set(updated)
        } else {
            selectedComplications = Set(defaultComplications)
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    func startPeriodicUpdates() {
        // Update metrics every 60 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task {
                await self?.loadHealthData()
            }
        }
    }
    
    func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func saveComplications() {
        if let encoded = try? JSONEncoder().encode(Array(selectedComplications)) {
            savedComplicationsData = encoded
        }
    }
    
    func addComplication(_ complication: ComplicationData) {
        selectedComplications.insert(complication)
    }
    
    func removeComplication(_ complication: ComplicationData) {
        selectedComplications.remove(complication)
    }
    
    func saveRings() {
        if let encoded = try? JSONEncoder().encode(rings) {
            savedRingsData = encoded
        }
    }
    
    func updateRingValue(ringName: String, layerTitle: String, value: Double) {
        if let ringIndex = rings.firstIndex(where: { $0.name == ringName }),
           let layerIndex = rings[ringIndex].layers.firstIndex(where: { $0.title == layerTitle }) {
            rings[ringIndex].layers[layerIndex].value = value
            saveRings()
        }
    }
    
    @MainActor
    func loadHealthData() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        await healthStore.requestAuthorization { success, error in
            if !success {
                print("HealthKit authorization failed: \(String(describing: error))")
            }
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Fetch active energy
        do {
            let value = try await healthStore.fetchQuantity(for: .activeEnergyBurned, start: startOfDay, end: endOfDay)
            self.metrics.activeEnergy = String(format: "%.0f", value)
            self.updateRingValue(ringName: "Move", layerTitle: "Active Energy", value: value)
        } catch {
            print("Error fetching active energy: \(error)")
        }
        
        // Fetch steps
        do {
            let value = try await healthStore.fetchQuantity(for: .stepCount, start: startOfDay, end: endOfDay)
            self.metrics.steps = String(format: "%.0f", value)
        } catch {
            print("Error fetching steps: \(error)")
        }
        
        // Fetch distance
        do {
            let value = try await healthStore.fetchQuantity(for: .distanceWalkingRunning, start: startOfDay, end: endOfDay)
            self.metrics.distance = String(format: "%.1f", value / 1000) // Convert meters to km
        } catch {
            print("Error fetching distance: \(error)")
        }
        
        // Fetch exercise time
        do {
            let value = try await healthStore.fetchQuantity(for: .appleExerciseTime, start: startOfDay, end: endOfDay)
            self.metrics.exerciseTime = String(format: "%.0f", value)
            self.updateRingValue(ringName: "Exercise", layerTitle: "Exercise Time", value: value)
        } catch {
            print("Error fetching exercise time: \(error)")
        }
        
        // Fetch stand hours
        do {
            let value = try await healthStore.fetchQuantity(for: .appleStandTime, start: startOfDay, end: endOfDay)
            self.metrics.standHours = String(format: "%.0f", value)
            self.updateRingValue(ringName: "Stand", layerTitle: "Stand Hours", value: value)
        } catch {
            print("Error fetching stand hours: \(error)")
        }
        
        // Fetch flights climbed
        do {
            let value = try await healthStore.fetchQuantity(for: .flightsClimbed, start: startOfDay, end: endOfDay)
            self.metrics.flightsClimbed = String(format: "%.0f", value)
        } catch {
            print("Error fetching flights climbed: \(error)")
        }
        
        // Fetch resting heart rate - look back 7 days for discrete measurements
        do {
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfDay)!
            let value = try await healthStore.fetchQuantity(for: .restingHeartRate, start: sevenDaysAgo, end: endOfDay)
            self.metrics.restingHeartRate = String(format: "%.0f", value)
        } catch {
            print("Error fetching resting heart rate: \(error)")
        }
        
        // Fetch heart rate - look back 7 days for discrete measurements
        do {
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfDay)!
            let value = try await healthStore.fetchQuantity(for: .heartRate, start: sevenDaysAgo, end: endOfDay)
            self.metrics.heartRate = String(format: "%.0f", value)
        } catch {
            print("Error fetching heart rate: \(error)")
        }
        
        // Fetch HRV - look back 7 days for discrete measurements
        do {
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfDay)!
            let value = try await healthStore.fetchQuantity(for: .heartRateVariabilitySDNN, start: sevenDaysAgo, end: endOfDay)
            self.metrics.hrv = String(format: "%.0f", value)
        } catch {
            print("Error fetching HRV: \(error)")
        }
        
        // Fetch sleep - sum all sleep sample durations
        do {
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                print("Error: Could not create sleep analysis category type")
                self.metrics.sleepHours = "0"
                return
            }
            
            // Apple's approach: look back ~40 hours to capture "last night's sleep"
            let lookbackHours: Double = 40
            let sleepStartDate = calendar.date(byAdding: .hour, value: Int(-lookbackHours), to: endOfDay)!
            let predicate = HKQuery.predicateForSamples(withStart: sleepStartDate, end: endOfDay, options: .strictStartDate)
            
            // Sort by start date ascending to process chronologically
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            
            print("Fetching sleep samples from \(sleepStartDate) to \(endOfDay)")
            
            let sleepSamples: [HKCategorySample] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        print("Sleep query error: \(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    let categorySamples = samples as? [HKCategorySample] ?? []
                    print("Sleep samples found: \(categorySamples.count)")
                    for (index, sample) in categorySamples.enumerated() {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                        var valueType = ""
                        switch sample.value {
                        case 0: valueType = "inBed"
                        case 1: valueType = "asleep"
                        case 2: valueType = "awake"
                        case 3: valueType = "asleepCore"
                        case 4: valueType = "asleepDeep"
                        case 5: valueType = "asleepREM"
                        default: valueType = "unknown(\(sample.value))"
                        }
                        print("  [\(index)]: \(sample.startDate) to \(sample.endDate), duration: \(duration) min, value: \(valueType)")
                    }
                    continuation.resume(returning: categorySamples)
                }
                healthStore.healthStore.execute(query)
            }
            
            // Sum asleepCore (3), asleepDeep (4), and asleepREM (5)
            var totalsByValue: [Int: Double] = [:]
            let totalSleepSeconds = sleepSamples.reduce(0.0) { total, sample in
                if sample.value == 3 || sample.value == 4 || sample.value == 5 {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    totalsByValue[sample.value, default: 0] += duration
                    return total + duration
                }
                return total
            }
            
            // Log breakdown by value type
            print("Sleep breakdown:")
            print("  Value 3 (asleepCore): \(Int(totalsByValue[3] ?? 0) / 60) min")
            print("  Value 4 (asleepDeep): \(Int(totalsByValue[4] ?? 0) / 60) min")
            print("  Value 5 (asleepREM): \(Int(totalsByValue[5] ?? 0) / 60) min")
            
            let totalSleepHours = totalSleepSeconds / 3600.0
            self.metrics.sleepHours = String(format: "%.1f", totalSleepHours)
            print("Total sleep: \(totalSleepHours) hours (\(Int(totalSleepSeconds / 60)) minutes)")
        } catch {
            print("Error fetching sleep: \(error)")
            self.metrics.sleepHours = "0"
        }
        
        // Fetch nutrition data - calories
        do {
            let value = try await healthStore.fetchQuantity(for: .dietaryEnergyConsumed, start: startOfDay, end: endOfDay)
            self.metrics.calories = String(format: "%.0f", value)
        } catch {
            print("Error fetching calories: \(error)")
        }
        
        // Fetch protein
        do {
            let value = try await healthStore.fetchQuantity(for: .dietaryProtein, start: startOfDay, end: endOfDay)
            self.metrics.protein = String(format: "%.0f", value)
        } catch {
            print("Error fetching protein: \(error)")
        }
        
        // Fetch carbs
        do {
            let value = try await healthStore.fetchQuantity(for: .dietaryCarbohydrates, start: startOfDay, end: endOfDay)
            self.metrics.carbs = String(format: "%.0f", value)
        } catch {
            print("Error fetching carbs: \(error)")
        }
        
        // Fetch fats
        do {
            let value = try await healthStore.fetchQuantity(for: .dietaryFatTotal, start: startOfDay, end: endOfDay)
            self.metrics.fats = String(format: "%.0f", value)
        } catch {
            print("Error fetching fats: \(error)")
        }
        
        // Fetch water
        do {
            let value = try await healthStore.fetchQuantity(for: .dietaryWater, start: startOfDay, end: endOfDay)
            self.metrics.water = String(format: "%.0f", value)
        } catch {
            print("Error fetching water: \(error)")
        }
        
        // Fetch mindfulness - today only
        do {
            guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
                print("Error: Could not create mindful session category type")
                self.metrics.mindfulMinutes = "0"
                return
            }
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
            print("Fetching mindfulness samples from \(startOfDay) to \(endOfDay)")
            
            let mindfulSamples: [HKCategorySample] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
                let query = HKSampleQuery(
                    sampleType: mindfulType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        print("Mindfulness query error: \(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    let categorySamples = samples as? [HKCategorySample] ?? []
                    print("Mindfulness samples found: \(categorySamples.count)")
                    for (index, sample) in categorySamples.enumerated() {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                        print("  [\(index)]: \(sample.startDate) to \(sample.endDate), duration: \(duration) min, value: \(sample.value)")
                    }
                    continuation.resume(returning: categorySamples)
                }
                healthStore.healthStore.execute(query)
            }
            
            let totalMinutes = mindfulSamples.reduce(0.0) { total, sample in
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                return total + duration
            }
            self.metrics.mindfulMinutes = String(format: "%.0f", totalMinutes)
            print("Total mindful minutes: \(totalMinutes)")
        } catch {
            print("Error fetching mindfulness: \(error)")
            self.metrics.mindfulMinutes = "0"
        }
    }

    @MainActor
    private func updateMetric(type: String, value: Double) {
        switch type {
        case "activeEnergy":
            metrics.activeEnergy = String(format: "%.0f", value)
            updateRingValue(ringName: "Move", layerTitle: "Active Energy", value: value)
        case "exerciseTime":
            metrics.exerciseTime = String(format: "%.0f", value)
            updateRingValue(ringName: "Exercise", layerTitle: "Exercise Time", value: value)
        case "standHours":
            metrics.standHours = String(format: "%.0f", value)
            updateRingValue(ringName: "Stand", layerTitle: "Stand Hours", value: value)
        case "steps":
            metrics.steps = String(format: "%.0f", value)
        case "distance":
            metrics.distance = String(format: "%.1f", value)
        default:
            break
        }
        
        saveRings()
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
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var animationPhase: Double = 0
    
    private var adaptiveGridColumns: [GridItem] {
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible()), count: columnCount)
    }
    
    private var maxVisibleComplications: Int {
        horizontalSizeClass == .regular ? 8 : 8
    }
    
    var complicationsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Complications")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    viewModel.showComplicationPicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.selectedComplications.count >= maxVisibleComplications)
            }
            .padding(.horizontal)
            
            LazyVGrid(columns: adaptiveGridColumns, spacing: 20) {
                ForEach(Array(viewModel.selectedComplications), id: \.id) { complication in
                    ActivityComplication(
                        viewModel: viewModel,
                        title: complication.title,
                        value: viewModel.value(for: complication.valueKey),
                        unit: complication.unit,
                        icon: complication.icon,
                        isActivityRing: complication.isActivityRing
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.removeComplication(complication)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .draggable(ActivityComplicationTransferData(
                        title: complication.title,
                        value: viewModel.value(for: complication.valueKey),
                        unit: complication.unit,
                        customGoal: nil
                    ))
                }
                
                if viewModel.selectedComplications.count < maxVisibleComplications {
                    Button {
                        viewModel.showComplicationPicker = true
                    } label: {
                        VStack {
                            Image(systemName: "plus")
                                .font(.system(size: 30))
                                .foregroundColor(.blue)
                            Text("Add")
                                .font(.caption)
                        }
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)
                    }
                }
            }
            .padding()
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.rings.isEmpty {
                        DisclosureGroup(
                            isExpanded: $viewModel.isRingSectionExpanded,
                            content: {
                                FormTipsStyleRingScroll(rings: $viewModel.rings)
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
                        EmptyRingDropTarget(rings: $viewModel.rings)
                            .padding(.horizontal)
                    }
                    
                    complicationsSection
                    
                    AnchorlineSection(viewModel: viewModel, healthStore: viewModel.healthStore)
                    
//                    if !viewModel.metrics.workouts.isEmpty {
//                        VStack(alignment: .leading, spacing: 10) {
//                            Text("Recent Workouts")
//                                .font(.headline)
//                                .padding(.horizontal)
//
//                            ScrollView(.horizontal, showsIndicators: false) {
//                                LazyHStack(spacing: 15) {
//                                    ForEach(viewModel.metrics.workouts, id: \.uuid) { workout in
//                                        DashboardWorkoutRow(workout: workout)
//                                    }
//                                }
//                                .padding(.horizontal)
//                            }
//                        }
//                    }
                }
            }
            .refreshable {
                await viewModel.loadHealthData()
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
                    ComplicationPickerView(viewModel: viewModel)
                }
            }
        }
        .task {
            await viewModel.loadHealthData()
            viewModel.startPeriodicUpdates()
        }
        .onDisappear {
            viewModel.stopPeriodicUpdates()
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

enum ComplicationCategory: String, Codable {
    case general
    case sports
}

struct ComplicationPickerView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String?
    @StateObject private var healthStore = HealthKitManager()
    
    private let categories: [String: [ComplicationInfo]] = [
        "Activity": [
            ComplicationInfo(title: "Active Energy", valueKey: "activeEnergy", unit: "cal", icon: "flame.fill", category: .general, isActivityRing: true),
            ComplicationInfo(title: "Steps", valueKey: "steps", unit: "steps", icon: "figure.walk", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Distance", valueKey: "distance", unit: "km", icon: "figure.walk", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Exercise Time", valueKey: "exerciseTime", unit: "min", icon: "timer", category: .general, isActivityRing: true),
            ComplicationInfo(title: "Stand Minutes", valueKey: "standHours", unit: "min", icon: "figure.stand", category: .general, isActivityRing: true),
            ComplicationInfo(title: "Flights Climbed", valueKey: "flightsClimbed", unit: "floors", icon: "stairs", category: .general, isActivityRing: false)
        ],
        "Health": [
            ComplicationInfo(title: "Heart Rate", valueKey: "heartRate", unit: "bpm", icon: "heart.fill", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Resting HR", valueKey: "restingHeartRate", unit: "bpm", icon: "heart", category: .general, isActivityRing: false),
            ComplicationInfo(title: "HRV", valueKey: "hrv", unit: "ms", icon: "waveform.path.ecg", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Sleep Duration", valueKey: "sleepHours", unit: "hr", icon: "bed.double.fill", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Mindful Minutes", valueKey: "mindfulMinutes", unit: "min", icon: "brain.head.profile", category: .general, isActivityRing: false)
        ],
        "Nutrition": [
            ComplicationInfo(title: "Protein", valueKey: "protein", unit: "g", icon: "fork.knife", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Carbs", valueKey: "carbs", unit: "g", icon: "fork.knife", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Fats", valueKey: "fats", unit: "g", icon: "fork.knife", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Water", valueKey: "water", unit: "mL", icon: "drop.fill", category: .general, isActivityRing: false),
            ComplicationInfo(title: "Calories", valueKey: "calories", unit: "cal", icon: "flame.fill", category: .general, isActivityRing: false)
        ]
    ]
    
    private var availableComplications: [String: [ComplicationInfo]] {
        var filtered = categories
        for (category, complications) in filtered {
            filtered[category] = complications.filter { complication in
                !viewModel.selectedComplications.contains { existing in
                    existing.title == complication.title
                }
            }
        }
        filtered = filtered.filter { !$0.value.isEmpty }
        return filtered
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(availableComplications.keys.sorted()), id: \.self) { category in
                    Section(header: Text(category)) {
                        ForEach(availableComplications[category] ?? [], id: \.title) { complication in
                            Button {
                                Task {
                                    await addComplication(complication)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: complication.icon)
                                        .foregroundColor(.blue)
                                    Text(complication.title)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
                
                if availableComplications.isEmpty {
                    Section {
                        Text("All complications have been added")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Complication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addComplication(_ info: ComplicationInfo) async {
        let complication = ComplicationData(
            title: info.title,
            valueKey: info.valueKey,
            unit: info.unit,
            icon: info.icon,
            category: info.category,
            isActivityRing: info.isActivityRing
        )
        
        viewModel.addComplication(complication)
        
        if info.isActivityRing {
            let value = await getValue(for: info.valueKey)
            if let ringIndex = viewModel.rings.firstIndex(where: { $0.name == info.title }) {
                viewModel.rings[ringIndex].layers[0].value = Double(value) ?? 0
            } else {
                let newRing = DashboardViewModel.RingMetric(
                    id: UUID(),
                    name: info.title,
                    layers: [
                        DashboardViewModel.RingLayer(
                            id: UUID(),
                            title: info.title,
                            value: Double(value) ?? 0,
                            goal: 600,
                            unit: info.unit,
                            color: Color.red
                        )
                    ]
                )
                viewModel.rings.append(newRing)
            }
            viewModel.saveRings()
        }
        
        dismiss()
    }
    
    private func getValue(for key: String) async -> String {
        switch key {
        case "activeEnergy":
            return viewModel.metrics.activeEnergy
        case "steps":
            return viewModel.metrics.steps
        case "distance":
            return viewModel.metrics.distance
        case "exerciseTime":
            return viewModel.metrics.exerciseTime
        case "standHours":
            return viewModel.metrics.standHours
        case "flightsClimbed":
            return viewModel.metrics.flightsClimbed
        case "heartRate":
            return viewModel.metrics.heartRate
        case "restingHeartRate":
            return viewModel.metrics.restingHeartRate
        case "hrv":
            return viewModel.metrics.hrv
        case "sleepHours":
            return viewModel.metrics.sleepHours
        case "mindfulMinutes":
            return viewModel.metrics.mindfulMinutes
        case "protein":
            return viewModel.metrics.protein
        case "carbs":
            return viewModel.metrics.carbs
        case "fats":
            return viewModel.metrics.fats
        case "water":
            return viewModel.metrics.water
        case "calories":
            return viewModel.metrics.calories
        default:
            return "0"
        }
    }
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

struct SendablePredicate: @unchecked Sendable {
    let predicate: NSPredicate
    
    init(_ predicate: NSPredicate) {
        self.predicate = predicate
    }
}

struct AnchorSlot: Identifiable, Equatable {
    let id: UUID
    var metric: ComplicationData?
    var weeklyAverage: Double = 0
    var todayValue: Double = 0
    var trend: TrendDirection = .steady
    
    static func == (lhs: AnchorSlot, rhs: AnchorSlot) -> Bool {
        lhs.id == rhs.id &&
        lhs.metric?.title == rhs.metric?.title &&
        lhs.weeklyAverage == rhs.weeklyAverage &&
        lhs.todayValue == rhs.todayValue &&
        lhs.trend == rhs.trend
    }
}

enum TrendDirection: Equatable {
    case up, down, steady
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .steady: return .blue
        }
    }
}

struct AnchorlineSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var healthStore: HealthKitManager
    @State private var autoScroll = false
    @State private var slots: [AnchorSlot] = Array(repeating: AnchorSlot(id: UUID()), count: 5)
    @State private var currentIndex = 0
    
    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Anchorline Charts")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .labelsHidden()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(0..<slots.count, id: \.self) { index in
                        AnchorlineCard(slot: $slots[index])
                            .frame(width: 300, height: 200)
                            .dropDestination(for: ActivityComplicationTransferData.self) { items, location in
                                if let item = items.first {
                                    // Only update this specific slot
                            slots[index].metric = ComplicationData(
                                title: item.title,
                                valueKey: "", // No valueKey available in ActivityComplicationTransferData
                                unit: item.unit,
                                icon: "chart.line.uptrend.xyaxis",
                                category: .general,
                                isActivityRing: false
                            )
                                    
                                    // Update just this slot's comparison data
                                    Task {
                                        await updateMetricComparison(for: index)
                                    }
                                }
                                return true
                            }
                    }
                }
                .padding()
            }
            .onReceive(timer) { _ in
                if autoScroll {
                    withAnimation {
                        currentIndex = (currentIndex + 1) % slots.count
                    }
                }
            }
        }
    }
    
    private func updateMetricComparison(for index: Int) async {
        guard index < slots.count, let metric = slots[index].metric else { return }
        
        let metrics: [String: HKQuantityTypeIdentifier] = [
            "Active Energy": .activeEnergyBurned,
            "Steps": .stepCount,
            "Distance": .distanceWalkingRunning,
            "Exercise": .appleExerciseTime,
            "Stand": .appleStandTime,
            "Flights Climbed": .flightsClimbed
        ]
        
        if let typeIdentifier = metrics[metric.title] {
            let todayValue = try? await healthStore.fetchTodayQuantity(for: typeIdentifier)
            
            if let todayValue = todayValue {
                // Update only this specific slot
                slots[index].todayValue = todayValue
                slots[index].weeklyAverage = todayValue // Temporary until weekly average implementation
                
                let difference = abs(todayValue - slots[index].weeklyAverage)
                let threshold = slots[index].weeklyAverage * 0.15
                
                if difference <= threshold {
                    slots[index].trend = .steady
                } else if todayValue > slots[index].weeklyAverage {
                    slots[index].trend = .up
                } else {
                    slots[index].trend = .down
                }
            }
        }
    }
}


struct AnchorlineCard: View {
    @Binding var slot: AnchorSlot
    
    var body: some View {
        VStack {
            if let metric = slot.metric {
                VStack(alignment: .leading, spacing: 10) {
                    Text(metric.title)
                        .font(.headline)
                    
                    HStack {
                        Text("Today: \(slot.todayValue, specifier: "%.1f") \(metric.unit)")
                        Spacer()
                        Image(systemName: trendArrow)
                            .foregroundColor(slot.trend.color)
                    }
                    
                    Text("7-day avg: \(slot.weeklyAverage, specifier: "%.1f") \(metric.unit)")
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Drop metric here")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
    
    private var trendArrow: String {
        switch slot.trend {
        case .up: return "arrow.up.circle.fill"
        case .down: return "arrow.down.circle.fill"
        case .steady: return "equal.circle.fill"
        }
    }
}

extension DashboardViewModel {
    struct RingMetric: Identifiable, Codable, Equatable {
        var id = UUID()
        var name: String
        var layers: [RingLayer]
        
        init(id: UUID = UUID(), name: String, layers: [RingLayer]) {
            self.id = id
            self.name = name
            self.layers = layers
        }
        
        static func == (lhs: RingMetric, rhs: RingMetric) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    struct RingLayer: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var value: Double
        var goal: Double
        var unit: String
        var colorRed: Double = 1.0
        var colorGreen: Double = 0.0
        var colorBlue: Double = 0.0
        
        var color: Color {
            Color(red: colorRed, green: colorGreen, blue: colorBlue)
        }
        
        init(id: UUID = UUID(), title: String, value: Double, goal: Double, unit: String, color: Color) {
            self.id = id
            self.title = title
            self.value = value
            self.goal = goal
            self.unit = unit
            
            let components = color.ringComponents
            self.colorRed = components.red
            self.colorGreen = components.green
            self.colorBlue = components.blue
        }
        
        init(id: UUID = UUID(), title: String, value: Double, goal: Double, colorRed: Double, colorGreen: Double, colorBlue: Double, unit: String) {
            self.id = id
            self.title = title
            self.value = value
            self.goal = goal
            self.colorRed = colorRed
            self.colorGreen = colorGreen
            self.colorBlue = colorBlue
            self.unit = unit
        }
        
        static func == (lhs: RingLayer, rhs: RingLayer) -> Bool {
            return lhs.id == rhs.id
        }
    }
}

extension Color {
    var ringComponents: (red: Double, green: Double, blue: Double, alpha: Double) {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}
