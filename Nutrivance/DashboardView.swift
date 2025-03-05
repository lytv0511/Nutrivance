import SwiftUI
import Charts
import HealthKit

struct DashboardMetrics {
    var activeEnergy: String = "0"
    var restingEnergy: String = "0"
    var steps: String = "0"
    var distance: String = "0"
    var standMinutes: String = "0"
    var physicalEffort: String = "0"
    var standHours: String = "0"
    var flights: String = "0"
    var exercise: String = "0"
    var workouts: [HKWorkout] = []
}

class DashboardViewModel: ObservableObject {
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
    
    private let goalsKey = "complicationGoals"
    
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
    
    let healthStore: HealthKitManager
    
    init(healthStore: HealthKitManager) {
        self.healthStore = healthStore
        self.isRingSectionExpanded = UserDefaults.standard.bool(forKey: "ringSectionExpanded") || activeRings.count >= 1
        loadSavedRings()
        setupCloudSync()
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
    
    func loadHealthData() async {
        let types: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .basalEnergyBurned,
            .stepCount,
            .distanceWalkingRunning,
            .appleExerciseTime,
            .flightsClimbed
        ]
        
        for type in types {
            if let quantity = try? await healthStore.fetchTodayQuantity(for: type) {
                await MainActor.run {
                    switch type {
                    case .activeEnergyBurned:
                        metrics.activeEnergy = String(format: "%.0f", quantity)
                    case .basalEnergyBurned:
                        metrics.restingEnergy = String(format: "%.0f", quantity)
                    case .stepCount:
                        metrics.steps = String(format: "%.0f", quantity)
                    case .distanceWalkingRunning:
                        metrics.distance = String(format: "%.1f", quantity/1000)
                    case .appleExerciseTime:
                        metrics.exercise = String(format: "%.0f", quantity)
                    case .flightsClimbed:
                        metrics.flights = String(format: "%.0f", quantity)
                    default:
                        break
                    }
                }
            }
        }
    }
}

struct DashboardView: View {
    @State private var animationPhase: Double = 0
    @StateObject private var healthStore = HealthKitManager()
    @StateObject private var viewModel: DashboardViewModel
    @State private var isRing = false
    
    init() {
        let healthStore = HealthKitManager()
        _viewModel = StateObject(wrappedValue: DashboardViewModel(healthStore: healthStore))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today's Overview")
                                .font(.title2)
                                .bold()
                            Text(Date(), style: .date)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        CircularProgressView(progress: 0.75)
                            .frame(width: 60, height: 60)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 15) {
                            let complications = [
                                (title: "Active Energy", value: viewModel.metrics.activeEnergy, unit: "kcal", icon: "flame.fill", isActivityRing: true),
                                (title: "Steps", value: viewModel.metrics.steps, unit: "steps", icon: "figure.walk", isActivityRing: false),
                                (title: "Distance", value: viewModel.metrics.distance, unit: "km", icon: "figure.run", isActivityRing: false),
                                (title: "Exercise", value: viewModel.metrics.exercise, unit: "min", icon: "timer", isActivityRing: true),
                                (title: "Stand", value: viewModel.metrics.standHours, unit: "hr", icon: "figure.stand", isActivityRing: true),
                                (title: "Flights", value: viewModel.metrics.flights, unit: "floors", icon: "stairs", isActivityRing: false)
                            ]
                            
                            ForEach(complications, id: \.title) { complication in
                                ActivityComplication(
                                    viewModel: viewModel,
                                    title: complication.title,
                                    value: complication.value,
                                    unit: complication.unit,
                                    icon: complication.icon,
                                    isActivityRing: complication.isActivityRing
                                )
                                .frame(width: 200, height: 100)
                            }
                        }
                        
                        HStack {
                            Text("Rings")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Button(action: {
                                withAnimation(.spring()) {
                                    viewModel.isRingSectionExpanded.toggle()
                                }
                            }) {
                                Image(systemName: viewModel.isRingSectionExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)

                        if viewModel.isRingSectionExpanded {
                            RingCard(rings: $viewModel.activeRings)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                    }

                    .task {
                        await viewModel.loadHealthData()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today's Training")
                            .font(.title3)
                            .bold()
                        
                        ForEach(["Upper Body Strength", "HIIT Cardio", "Core Stability"], id: \.self) { workout in
                            DashboardWorkoutRow(name: workout, duration: "45 min", completed: false)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    
                    RecoveryStatusView()
                    WeeklyProgressChart(viewModel: viewModel)
                }
                .padding()
            }
            .background(
// GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
            )
            .navigationTitle("Dashboard")
        }
        .onAppear {
           healthStore.startObservingHealthData {
               Task { @MainActor in
                   await viewModel.loadHealthData()
               }
           }
       }
    }
}

struct DashboardWorkoutRow: View {
    let name: String
    let duration: String
    let completed: Bool
    
    var body: some View {
        HStack {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? .green : .secondary)
            Text(name)
            Spacer()
            Text(duration)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
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

struct RingCard: View {
    @Binding var rings: [DashboardViewModel.RingMetric]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(rings) { ring in
                    RingItemView(rings: $rings, ring: ring)
                        .dropDestination(for: ActivityComplicationTransferData.self) { complications, location in
                            if ring.layers.count < 4 {
                                for complication in complications {
                                    if !ring.layers.contains(where: { $0.title == complication.title }) {
                                        let newLayer = DashboardViewModel.RingLayer(
                                            id: UUID(),
                                            title: complication.title,
                                            value: Double(complication.value) ?? 0,
                                            goal: complication.customGoal ?? 100,
                                            colorRed: getLayerColor(for: ring.layers.count).red,
                                            colorGreen: getLayerColor(for: ring.layers.count).green,
                                            colorBlue: getLayerColor(for: ring.layers.count).blue,
                                            unit: complication.unit
                                        )
                                        if let index = rings.firstIndex(where: { $0.id == ring.id }) {
                                            rings[index].layers.append(newLayer)
                                        }
                                    }
                                }
                            }
                            return true
                        }
                }
                
                if rings.count < 5 {
                    VStack {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .frame(width: 350, height: 350)
                            .foregroundColor(.secondary)
                            .overlay(
                                Text("Drop Complication Here")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            )
                            .padding()
                    }
                    .dropDestination(for: ActivityComplicationTransferData.self) { complications, location in
                        handleDroppedComplications(complications)
                        return true
                    }
                }
            }
            .padding()
        }
        .frame(height: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .padding()
    }
    
    private func handleDroppedComplications(_ items: [ActivityComplicationTransferData]) {
        for item in items {
            let firstLayer = DashboardViewModel.RingLayer(
                id: UUID(),
                title: item.title,
                value: Double(item.value) ?? 0,
                goal: item.customGoal ?? 100,
                colorRed: 0.9,    // Deep red for outermost ring
                colorGreen: 0.2,
                colorBlue: 0.3,
                unit: item.unit
            )
            
            let newRing = DashboardViewModel.RingMetric(
                name: "Ring \(rings.count + 1)",
                layers: [firstLayer]
            )
            rings.append(newRing)
        }
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

struct ActivityComplication: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var isRing = false
    @State private var showGoalSheet = false
    @State private var customGoal: Double?
    let title: String
    let value: String
    let unit: String
    let icon: String
    let isActivityRing: Bool
    
    init(viewModel: DashboardViewModel, title: String, value: String, unit: String, icon: String, isActivityRing: Bool) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.isActivityRing = isActivityRing
    }
    
    var targetValue: String? {
        if isActivityRing {
            switch title {
                case "Active Energy": return "600"
                case "Exercise": return "30"
                case "Stand": return "12"
                default: return nil
            }
        }
        return customGoal?.description
    }
    
    var body: some View {
        VStack {
            HStack {
                if !isRing {
                    HStack {
                        Image(systemName: icon)
                        VStack(alignment: .leading) {
                            Text(title)
                                .font(.caption)
                            Text("\(value)/\(targetValue ?? "--") \(unit)")
                                .font(.title2)
                                .bold()
                        }
                        Spacer()
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .draggable(ActivityComplicationTransferData(
                        title: title,
                        value: value,
                        unit: unit,
                        customGoal: { @MainActor in customGoal }()
                    ))
                    .contextMenu {
                        if !isActivityRing {
                            Button(action: { showGoalSheet = true }) {
                                Label("Set Goal", systemImage: "target")
                            }
                        }
                        Button(action: {
                            withAnimation(.spring()) {
                                viewModel.showRingCard = true
                                isRing = true
                            }
                        }) {
                            Label("Make Ring", systemImage: "circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            GoalSettingView(goal: $customGoal)
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
            VStack {
                ringStack
                Text(ring.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                metricsStack
            }
            .frame(width: 350, height: 350)
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(15)
            .onTapGesture {
                showRingDetail = true
            }
            .navigationDestination(isPresented: $showRingDetail) {
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
        ZStack {
            if let outerRing = ring.layers.first {
                ActivityRing(
                    progress: outerRing.value / outerRing.goal,
                    gradient: Gradient(colors: [outerRing.color, outerRing.color]),
                    backgroundGradient: Gradient(colors: [outerRing.color.opacity(0.2)])
                )
                .frame(width: 280, height: 280)
            }
            
            ForEach(Array(ring.layers.dropFirst().enumerated()), id: \.element.id) { index, layer in
                ActivityRing(
                    progress: layer.value / layer.goal,
                    gradient: Gradient(colors: [layer.color, layer.color]),
                    backgroundGradient: Gradient(colors: [layer.color.opacity(0.2)])
                )
                .frame(width: ringSize(for: index), height: ringSize(for: index))
            }
        }
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


struct GoalSettingView: View {
    @Binding var goal: Double?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal Value", value: $goal, format: .number)
                        .keyboardType(.decimalPad)
                }
                
                if goal != nil {
                    Button("Delete Goal", role: .destructive) {
                        goal = nil
                        dismiss()
                    }
                }
            }
            .navigationTitle("Set Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ActivityRing: View {
    let progress: Double
    let gradient: Gradient
    let backgroundGradient: Gradient
    
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
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: gradient, center: .center),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
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
