import SwiftUI
import HealthKit
import Charts
import MapKit
import CoreLocation

enum HRZoneConfigurationMode: String, CaseIterable, Identifiable {
    case intelligent
    case customSchema
    case customZones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intelligent:
            return "Intelligent"
        case .customSchema:
            return "Custom Schema"
        case .customZones:
            return "Custom Zones"
        }
    }

    var symbol: String {
        switch self {
        case .intelligent:
            return "sparkles"
        case .customSchema:
            return "slider.horizontal.3"
        case .customZones:
            return "dial.high"
        }
    }

    var description: String {
        switch self {
        case .intelligent:
            return "Adjust HR zones automatically using recent resting HR, max HR, threshold data, and sport type."
        case .customSchema:
            return "Use one formula for every workout and optionally set the variables yourself."
        case .customZones:
            return "Enter your own zone ceilings and use the same zone map across workouts."
        }
    }
}

struct HRZoneUserSettings {
    var mode: HRZoneConfigurationMode
    var customSchema: HRZoneSchema
    var fixedMaxHR: Double?
    var fixedRestingHR: Double?
    var fixedLTHR: Double?
    var customZoneUpperBounds: [Double]
}

private struct HRZonePersistedSettings: Codable, Equatable {
    var modeRawValue: String
    var schemaRawValue: String
    var fixedMaxHR: Double?
    var fixedRestingHR: Double?
    var fixedLTHR: Double?
    var customZoneUpperBounds: [Double]
}

private enum HRZoneSettingsPersistence {
    static let storageKey = "hr_zone_user_settings_v1"

    static func load() -> HRZonePersistedSettings? {
        let ubiquitousStore = NSUbiquitousKeyValueStore.default

        if let cloudData = ubiquitousStore.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(HRZonePersistedSettings.self, from: cloudData) {
            return decoded
        }

        if let localData = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(HRZonePersistedSettings.self, from: localData) {
            return decoded
        }

        return nil
    }

    static func save(_ settings: HRZonePersistedSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
        let ubiquitousStore = NSUbiquitousKeyValueStore.default
        ubiquitousStore.set(encoded, forKey: storageKey)
    }
}

private extension HRZonePersistedSettings {
    static let fallback = HRZonePersistedSettings(
        modeRawValue: HRZoneConfigurationMode.intelligent.rawValue,
        schemaRawValue: HRZoneSchema.lactatThreshold.rawValue,
        fixedMaxHR: nil,
        fixedRestingHR: nil,
        fixedLTHR: nil,
        customZoneUpperBounds: [120, 140, 160, 180, 200]
    )
}

func workoutRowIdentifier(for workout: HKWorkout) -> String {
    if let cachedWorkoutID = workout.metadata?["NutrivanceCachedWorkoutUUID"] as? String,
       !cachedWorkoutID.isEmpty {
        return cachedWorkoutID
    }
    return workout.uuid.uuidString
}

struct WorkoutHistoryView: View {
    @ObservedObject var engine = HealthStateEngine.shared
    @EnvironmentObject private var navigationState: NavigationState
    let initialScrollWorkoutID: String?
    @State private var expandedWorkoutIDs: Set<String> = []
    @State private var isLoading = false
    @State private var animationPhase: Double = 0
    @State private var sportFilter: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var pendingJumpDate: Date?
    @State private var pendingScrollTargetID: String?
    @State private var scrollRequestNonce: Int = 0
    @State private var showHRZoneSettings = false
    @State private var hrZoneConfigurationMode: HRZoneConfigurationMode = .intelligent
    @State private var selectedHRZoneSchema: HRZoneSchema = .lactatThreshold
    @State private var fixedMaxHR: Double? = nil
    @State private var fixedRestingHR: Double? = nil
    @State private var fixedLTHR: Double? = nil
    @State private var customZone1Upper: Double = 120
    @State private var customZone2Upper: Double = 140
    @State private var customZone3Upper: Double = 160
    @State private var customZone4Upper: Double = 180
    @State private var customZone5Upper: Double = 200
    @State private var hasLoadedPersistedHRZoneSettings = false
    @State private var isLoadingHistoricalCoverage = false
    @State private var hasConsumedInitialWorkoutScroll = false
    @State private var isJumpingToSelectedDate = false

    init(initialScrollWorkoutID: String? = nil) {
        self.initialScrollWorkoutID = initialScrollWorkoutID
        let persisted = HRZoneSettingsPersistence.load() ?? .fallback
        let mode = HRZoneConfigurationMode(rawValue: persisted.modeRawValue) ?? .intelligent
        let schema = HRZoneSchema(rawValue: persisted.schemaRawValue) ?? .lactatThreshold
        let bounds = persisted.customZoneUpperBounds.count == 5 ? persisted.customZoneUpperBounds : HRZonePersistedSettings.fallback.customZoneUpperBounds

        _hrZoneConfigurationMode = State(initialValue: mode)
        _selectedHRZoneSchema = State(initialValue: schema)
        _fixedMaxHR = State(initialValue: persisted.fixedMaxHR)
        _fixedRestingHR = State(initialValue: persisted.fixedRestingHR)
        _fixedLTHR = State(initialValue: persisted.fixedLTHR)
        _customZone1Upper = State(initialValue: bounds[0])
        _customZone2Upper = State(initialValue: bounds[1])
        _customZone3Upper = State(initialValue: bounds[2])
        _customZone4Upper = State(initialValue: bounds[3])
        _customZone5Upper = State(initialValue: bounds[4])
        _hasLoadedPersistedHRZoneSettings = State(initialValue: true)
    }

    private var hrZoneSettings: HRZoneUserSettings {
        HRZoneUserSettings(
            mode: hrZoneConfigurationMode,
            customSchema: selectedHRZoneSchema,
            fixedMaxHR: fixedMaxHR,
            fixedRestingHR: fixedRestingHR,
            fixedLTHR: fixedLTHR,
            customZoneUpperBounds: [
                customZone1Upper,
                customZone2Upper,
                customZone3Upper,
                customZone4Upper,
                customZone5Upper
            ]
        )
    }

    private var persistedHRZoneSettings: HRZonePersistedSettings {
        HRZonePersistedSettings(
            modeRawValue: hrZoneConfigurationMode.rawValue,
            schemaRawValue: selectedHRZoneSchema.rawValue,
            fixedMaxHR: fixedMaxHR,
            fixedRestingHR: fixedRestingHR,
            fixedLTHR: fixedLTHR,
            customZoneUpperBounds: [
                customZone1Upper,
                customZone2Upper,
                customZone3Upper,
                customZone4Upper,
                customZone5Upper
            ]
        )
    }

    var filteredWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        engine.workoutAnalytics.filter { sportFilter == nil || $0.workout.workoutActivityType.name == sportFilter }
    }

    var uniqueSports: [String] {
        engine.workoutAnalytics.map { $0.workout.workoutActivityType.name }.unique.sorted()
    }

    var workoutDates: Set<Date> {
        Set(filteredWorkouts.map { Calendar.current.startOfDay(for: $0.workout.startDate) })
    }

    var groupedWorkouts: [DateComponents: [(workout: HKWorkout, analytics: WorkoutAnalytics)]] {
        Dictionary(grouping: filteredWorkouts) { pair in
            Calendar.current.dateComponents([.year, .month], from: pair.workout.startDate)
        }
    }

    private func workoutRowID(for pair: (workout: HKWorkout, analytics: WorkoutAnalytics)) -> String {
        workoutRowIdentifier(for: pair.workout)
    }

    private func monthSectionID(for dateComponents: DateComponents) -> String {
        "month-\(dateComponents.year ?? 0)-\(dateComponents.month ?? 0)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView("Loading workouts...")
                                    .padding()
                                Spacer()
                            }
                        } else if filteredWorkouts.isEmpty {
                            Text("No workouts found.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(groupedWorkouts.sorted(by: { ($0.key.year! * 12 + $0.key.month!) > ($1.key.year! * 12 + $1.key.month!) }), id: \.key) { (key, workouts) in
                                Section(
                                    header:
                                        Text("\(Calendar.current.monthSymbols[key.month! - 1]) \(String(format: "%d", key.year!))")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .id(monthSectionID(for: key))
                                ) {
                                    ForEach(workouts.sorted(by: { $0.workout.startDate > $1.workout.startDate }), id: \.analytics.workout.uuid) { pair in
                                        WorkoutCard(
                                            workout: pair.workout,
                                            analytics: pair.analytics,
                                            isExpanded: expandedWorkoutIDs.contains(workoutRowID(for: pair)),
                                            hrZoneSettings: hrZoneSettings,
                                            onHeaderTap: {
                                                withAnimation {
                                                    let workoutID = workoutRowID(for: pair)
                                                    if expandedWorkoutIDs.contains(workoutID) {
                                                        expandedWorkoutIDs.remove(workoutID)
                                                    } else {
                                                        expandedWorkoutIDs.insert(workoutID)
                                                    }
                                                }
                                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                                impact.impactOccurred()
                                            }
                                        )
                                        .id(workoutRowID(for: pair))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom)
                    .onAppear {
                        handleInitialWorkoutNavigation()
                        handlePendingWorkoutNavigation()
                        completePendingDateJumpIfPossible()
                    }
                    .onChange(of: scrollRequestNonce) { _, _ in
                        guard let pendingScrollTargetID else { return }
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(pendingScrollTargetID, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workout History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                isLoading = true
                                if engine.hasNewDataAvailable {
                                    // New data detected: replace cache with fresh fetch
                                    await engine.replaceWorkoutCacheWithNewData(days: 3650)
                                } else {
                                    // Standard reload: force refresh
                                    await engine.forceRefreshWorkoutAnalytics(days: 3650)
                                }
                                isLoading = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.orange)
                                if engine.hasNewDataAvailable {
                                    Text("NEW")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        Button(action: { showDatePicker = true }) {
                            Image(systemName: "calendar")
                                .foregroundColor(.orange)
                        }
                        Menu {
                            Button("All Sports") { sportFilter = nil }
                            ForEach(uniqueSports, id: \.self) { sport in
                                Button(sport.capitalized) { sportFilter = sport }
                            }
                        } label: {
                            Image(systemName: "line.horizontal.3.decrease.circle")
                                .foregroundColor(.orange)
                        }
                        Button(action: { showHRZoneSettings = true }) {
                            Image(systemName: "gear")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                VStack {
                    DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    if workoutDates.contains(Calendar.current.startOfDay(for: selectedDate)) {
                        HStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Has workouts")
                                .foregroundColor(.orange)
                        }
                    } else {
                        HStack {
                            Circle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text("No workouts")
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Jump to Workout") {
                        Task {
                            await loadCoverageForDatePickerSelection()
                        }
                    }
                    .padding()
                    .foregroundColor(.orange)
                    .disabled(isJumpingToSelectedDate)
                }
            }
            .sheet(isPresented: $showHRZoneSettings) {
                HRZoneSettingsSheet(
                    isPresented: $showHRZoneSettings,
                    configurationMode: $hrZoneConfigurationMode,
                    selectedSchema: $selectedHRZoneSchema,
                    fixedMaxHR: $fixedMaxHR,
                    fixedRestingHR: $fixedRestingHR,
                    fixedLTHR: $fixedLTHR,
                    customZone1Upper: $customZone1Upper,
                    customZone2Upper: $customZone2Upper,
                    customZone3Upper: $customZone3Upper,
                    customZone4Upper: $customZone4Upper,
                    customZone5Upper: $customZone5Upper
                )
            }
            .background(
               GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                   .onAppear {
                       withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                           animationPhase = 20
                       }
                   }
           )
            .onChange(of: persistedHRZoneSettings) { _, newValue in
                guard hasLoadedPersistedHRZoneSettings else { return }
                HRZoneSettingsPersistence.save(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                reloadPersistedHRZoneSettings()
            }
            .onChange(of: navigationState.pendingWorkoutScrollID) { _, _ in
                handlePendingWorkoutNavigation()
            }
            .onChange(of: groupedWorkouts.count) { _, _ in
                completePendingDateJumpIfPossible()
            }
            .onChange(of: sportFilter) { _, _ in
                completePendingDateJumpIfPossible()
            }
        }
    }

    private func handleInitialWorkoutNavigation() {
        guard hasConsumedInitialWorkoutScroll == false,
              let targetID = initialScrollWorkoutID else { return }
        hasConsumedInitialWorkoutScroll = true
        sportFilter = nil
        guard filteredWorkouts.contains(where: { workoutRowID(for: $0) == targetID }) else { return }
        requestScroll(to: targetID)
    }

    private func handlePendingWorkoutNavigation() {
        guard let targetID = navigationState.pendingWorkoutScrollID else { return }
        sportFilter = nil
        guard filteredWorkouts.contains(where: { workoutRowID(for: $0) == targetID }) else { return }
        requestScroll(to: targetID)
        navigationState.pendingWorkoutScrollID = nil
    }

    private func loadPersistedHRZoneSettingsIfNeeded() {
        guard !hasLoadedPersistedHRZoneSettings else { return }
        hasLoadedPersistedHRZoneSettings = true
        applyPersistedHRZoneSettings(HRZoneSettingsPersistence.load())
    }

    private func reloadPersistedHRZoneSettings() {
        guard hasLoadedPersistedHRZoneSettings else { return }
        applyPersistedHRZoneSettings(HRZoneSettingsPersistence.load())
    }

    private func applyPersistedHRZoneSettings(_ saved: HRZonePersistedSettings?) {
        guard let saved else { return }
        if let mode = HRZoneConfigurationMode(rawValue: saved.modeRawValue) {
            hrZoneConfigurationMode = mode
        }

        if let schema = HRZoneSchema(rawValue: saved.schemaRawValue) {
            selectedHRZoneSchema = schema
        }

        fixedMaxHR = saved.fixedMaxHR
        fixedRestingHR = saved.fixedRestingHR
        fixedLTHR = saved.fixedLTHR

        if saved.customZoneUpperBounds.count == 5 {
            customZone1Upper = saved.customZoneUpperBounds[0]
            customZone2Upper = saved.customZoneUpperBounds[1]
            customZone3Upper = saved.customZoneUpperBounds[2]
            customZone4Upper = saved.customZoneUpperBounds[3]
            customZone5Upper = saved.customZoneUpperBounds[4]
        }
    }

    private func requestScroll(to targetID: String) {
        pendingScrollTargetID = targetID
        scrollRequestNonce += 1
    }

    private func scrollToClosestWorkout(to date: Date) -> Bool {
        let calendar = Calendar.current
        let monthWorkouts = filteredWorkouts.filter {
            calendar.isDate($0.workout.startDate, equalTo: date, toGranularity: .month)
        }

        let candidatePool = monthWorkouts.isEmpty ? filteredWorkouts : monthWorkouts
        let closest = candidatePool.min(by: {
            abs($0.workout.startDate.timeIntervalSince(date)) < abs($1.workout.startDate.timeIntervalSince(date))
        })

        guard let closest else { return false }
        requestScroll(to: workoutRowID(for: closest))
        return true
    }

    private func completePendingDateJumpIfPossible() {
        guard let pendingJumpDate else { return }

        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: pendingJumpDate)
        let hasMonthLoaded = groupedWorkouts.keys.contains {
            $0.year == monthComponents.year && $0.month == monthComponents.month
        }

        guard hasMonthLoaded else { return }

        if scrollToClosestWorkout(to: pendingJumpDate) == false {
            requestScroll(to: monthSectionID(for: monthComponents))
        }

        self.pendingJumpDate = nil
    }

    @MainActor
    private func loadCoverageForDatePickerSelection() async {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: selectedDate)
        let start = monthInterval?.start ?? calendar.startOfDay(for: selectedDate)
        let end = monthInterval?.end ?? (calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        let targetDate = selectedDate
        let monthAlreadyLoadedInMemory = engine.workoutAnalytics.contains {
            calendar.isDate($0.workout.startDate, equalTo: targetDate, toGranularity: .month)
        }

        pendingJumpDate = targetDate
        showDatePicker = false
        isJumpingToSelectedDate = true
        defer { isJumpingToSelectedDate = false }

        if engine.needsWorkoutAnalyticsCoverage(from: start, to: end) || !monthAlreadyLoadedInMemory {
            isLoadingHistoricalCoverage = true
            await engine.ensureWorkoutAnalyticsCoverage(from: start, to: end, forceFetch: true)
            isLoadingHistoricalCoverage = false
        }

        await Task.yield()
        completePendingDateJumpIfPossible()
    }
}

struct WorkoutCard: View {
    let workout: HKWorkout
    let analytics: WorkoutAnalytics
    let isExpanded: Bool
    let hrZoneSettings: HRZoneUserSettings
    let onHeaderTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        return df
    }()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    private var workoutEffortScore: Double? {
        workoutEffortScoreValue(from: workout)
    }

    private var estimatedWorkoutEffortScore: Double? {
        estimatedWorkoutEffortScoreValue(from: workout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onHeaderTap) {
                HStack {
                    Image(systemName: workout.workoutActivityType.activityTypeSymbol)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text(workout.workoutActivityType.name.capitalized)
                            .font(.headline)
                        Text(Self.dateFormatter.string(from: workout.startDate)) + Text(" • ") + Text(Self.timeFormatter.string(from: workout.startDate)) + Text(" • \(Int(workout.duration/60)) min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        if let avgHR = analytics.heartRates.map({ $0.1 }).average {
                            Text("Avg HR: \(Int(avgHR)) bpm")
                                .font(.caption)
                        }
                        if let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
                            Text("Kcal: \(Int(kcal))")
                                .font(.caption)
                        }
                        if let met = analytics.metTotal {
                            Text("MET-min: \(Int(met))")
                                .font(.caption)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if workoutEffortScore != nil || estimatedWorkoutEffortScore != nil {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 10) {
                    if let workoutEffortScore {
                        CompactWorkoutMetricCard(
                            title: "Effort Score",
                            value: String(format: "%.1f", workoutEffortScore),
                            unit: "",
                            color: .orange
                        )
                    }
                    if let estimatedWorkoutEffortScore {
                        CompactWorkoutMetricCard(
                            title: "Estimated Effort",
                            value: String(format: "%.1f", estimatedWorkoutEffortScore),
                            unit: "",
                            color: .yellow
                        )
                    }
                }
            }
            if isExpanded {
                WorkoutDetailView(
                    analytics: analytics,
                    hrZoneSettings: hrZoneSettings
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct RoutePoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ColoredRouteSegment: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
}

private actor WorkoutRouteStore {
    static let shared = WorkoutRouteStore()

    private var cachedLocations: [UUID: [CLLocation]] = [:]

    func locations(for workout: HKWorkout) async -> [CLLocation] {
        if let cached = cachedLocations[workout.uuid] {
            return cached
        }

        let loaded = await loadLocations(for: workout)
        cachedLocations[workout.uuid] = loaded
        return loaded
    }

    private func loadLocations(for workout: HKWorkout) async -> [CLLocation] {
        let healthStore = HKHealthStore()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeType = HKSeriesType.workoutRoute()

        let route: HKWorkoutRoute? = await withCheckedContinuation { continuation in
            let sampleQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil,
                      let routes = samples as? [HKWorkoutRoute],
                      let route = routes.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: route)
            }
            healthStore.execute(sampleQuery)
        }

        guard let route else { return [] }

        return await withCheckedContinuation { continuation in
            var allLocations: [CLLocation] = []
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                guard error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                if let locations {
                    allLocations.append(contentsOf: locations)
                }

                if done {
                    continuation.resume(returning: allLocations)
                }
            }
            healthStore.execute(routeQuery)
        }
    }
}

private func sampledLocations(from locations: [CLLocation], maxPoints: Int) -> [CLLocation] {
    guard locations.count > maxPoints, maxPoints > 1 else { return locations }

    let step = Double(locations.count - 1) / Double(maxPoints - 1)
    var sampled: [CLLocation] = []
    sampled.reserveCapacity(maxPoints)

    for index in 0..<maxPoints {
        let sampledIndex = Int((Double(index) * step).rounded())
        sampled.append(locations[min(locations.count - 1, sampledIndex)])
    }

    return sampled
}

private func routeTintColor(for heartRate: Double) -> UIColor {
    switch heartRate {
    case ..<120: return .systemBlue
    case ..<140: return .systemGreen
    case ..<160: return .systemYellow
    case ..<180: return .systemOrange
    default: return .systemRed
    }
}

private func buildColoredRouteSegments(
    locations: [CLLocation],
    heartRates: [(Date, Double)]
) -> [ColoredRouteSegment] {
    guard locations.count > 1 else { return [] }

    let sortedHeartRates = heartRates.sorted { $0.0 < $1.0 }
    guard !sortedHeartRates.isEmpty else {
        return [ColoredRouteSegment(coordinates: locations.map(\.coordinate), color: .systemBlue)]
    }

    func nearestHeartRate(to date: Date, startingAt index: inout Int) -> Double {
        while index < sortedHeartRates.count - 1 &&
                abs(sortedHeartRates[index + 1].0.timeIntervalSince(date)) <= abs(sortedHeartRates[index].0.timeIntervalSince(date)) {
            index += 1
        }
        return sortedHeartRates[index].1
    }

    var segments: [ColoredRouteSegment] = []
    var currentCoordinates: [CLLocationCoordinate2D] = [locations[0].coordinate]
    var heartRateIndex = 0
    var currentColor = routeTintColor(for: nearestHeartRate(to: locations[0].timestamp, startingAt: &heartRateIndex))

    for locationIndex in 1..<locations.count {
        let location = locations[locationIndex]
        let nextColor = routeTintColor(for: nearestHeartRate(to: location.timestamp, startingAt: &heartRateIndex))

        if nextColor != currentColor && currentCoordinates.count > 1 {
            segments.append(ColoredRouteSegment(coordinates: currentCoordinates, color: currentColor))
            currentCoordinates = [locations[locationIndex - 1].coordinate, location.coordinate]
            currentColor = nextColor
        } else {
            currentCoordinates.append(location.coordinate)
        }
    }

    if currentCoordinates.count > 1 {
        segments.append(ColoredRouteSegment(coordinates: currentCoordinates, color: currentColor))
    }

    return segments
}

struct Split {
    let distance: Double // in km
    let time: TimeInterval
    let pace: Double? // min/km
    let avgHR: Double?
}

private struct HRZone {
    let name: String
    let color: Color
    var time: TimeInterval
    let range: ClosedRange<Double>
}

private func workoutElapsedTimeText(_ seconds: TimeInterval) -> String {
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    let s = Int(seconds) % 60
    if h > 0 {
        return String(format: "%dh %02dm %02ds", h, m, s)
    } else {
        return String(format: "%02dm %02ds", m, s)
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var unitPreferences: UnitPreferencesStore
    let analytics: WorkoutAnalytics
    let hrZoneSettings: HRZoneUserSettings
    var allowsMapExpansion: Bool = true
    var showsSummaryContent: Bool = true
    var showsMapSection: Bool = true
    var scrubbedDate: Binding<Date?>? = nil

    @StateObject private var healthKitManager = HealthKitManager()

    @State private var showHRZones = false
    @State private var routePoints: [RoutePoint] = []
    @State private var routeLocations: [CLLocation] = []
    @State private var routeLookupLocations: [CLLocation] = []
    @State private var coloredSegments: [ColoredRouteSegment] = []
    @State private var isLoadingRoute = false
    @State private var historicalZoneProfile: HRZoneProfile? = nil
    @State private var historicalMaxHR: Double? = nil
    @State private var historicalRestingHR: Double? = nil
    @State private var hasResolvedZoneProfile = false
    @State private var localSelectedScrubbedDate: Date? = nil
    @State private var showMapDetail = false

    private var activeDuration: TimeInterval {
        analytics.workout.duration
    }

    private var selectedScrubbedDate: Date? {
        scrubbedDate?.wrappedValue ?? localSelectedScrubbedDate
    }

    private func updateSelectedScrubbedDate(_ date: Date?) {
        if let scrubbedDate {
            scrubbedDate.wrappedValue = date
        } else {
            localSelectedScrubbedDate = date
        }
    }

    private var standardChartHeight: CGFloat {
        showsSummaryContent ? 150 : 96
    }

    private var heartRateChartHeight: CGFloat {
        showsSummaryContent ? 180 : 112
    }

    private var elapsedDuration: TimeInterval {
        analytics.workout.endDate.timeIntervalSince(analytics.workout.startDate)
    }

    private var pausedDuration: TimeInterval? {
        let pause = elapsedDuration - activeDuration
        return pause > 0 ? pause : nil
    }

    private var distanceMeters: Double? {
        analytics.workout.totalDistance?.doubleValue(for: HKUnit.meter())
    }

    private var avgSpeedKPH: Double? {
        guard let dist = distanceMeters, activeDuration > 0 else { return nil }
        return (dist / 1000) / (activeDuration / 3600)
    }

    private var formattedDistanceMetric: (value: String, unit: String)? {
        guard let distanceMeters else { return nil }
        return unitPreferences.formattedDistance(fromMeters: distanceMeters)
    }

    private var formattedAvgSpeedMetric: (value: String, unit: String)? {
        guard let avgSpeedKPH else { return nil }
        return unitPreferences.formattedSpeed(fromKilometersPerHour: avgSpeedKPH)
    }

    private var formattedAvgPaceMetric: (value: String, unit: String)? {
        guard let avgSpeedKPH, avgSpeedKPH > 0 else { return nil }
        return unitPreferences.formattedPace(fromMinutesPerKilometer: 60 / avgSpeedKPH)
    }

    private var displaySpeedSeries: [(Date, Double)] {
        analytics.speedSeries.map { point in
            let speedKPH = point.1 * 3.6
            let displayValue = unitPreferences.resolvedSpeedUnit == .milesPerHour
                ? speedKPH / 1.609344
                : speedKPH
            return (point.0, displayValue)
        }
    }

    private var displayElevationSeries: [(Date, Double)] {
        analytics.elevationSeries.map { point in
            let displayValue = unitPreferences.resolvedElevationUnit == .feet
                ? point.1 * 3.28084
                : point.1
            return (point.0, displayValue)
        }
    }

    private var displayStrideLengthSeries: [(Date, Double)] {
        analytics.strideLengthSeries.map { point in
            let displayValue = unitPreferences.resolvedElevationUnit == .feet
                ? point.1 * 3.28084
                : point.1
            return (point.0, displayValue)
        }
    }

    private var avgPower: Double? {
        let p = analytics.powerSeries.map { $0.1 }
        guard !p.isEmpty else { return nil }
        return p.reduce(0, +) / Double(p.count)
    }

    private var avgCadence: Double? {
        analytics.cadenceSeries.map { $0.1 }.average
    }

    private var avgHeartRate: Double? {
        let hr = analytics.heartRates.map { $0.1 }
        guard !hr.isEmpty else { return nil }
        return hr.reduce(0, +) / Double(hr.count)
    }

    private var maxHeartRate: Double? {
        analytics.heartRates.map { $0.1 }.max()
    }

    private var selectedRouteLocation: CLLocation? {
        let referenceDate = selectedScrubbedDate ?? analytics.workout.startDate
        return nearestRouteLocation(to: referenceDate)
    }

    private var selectedRouteCoordinateText: String? {
        guard let coordinate = selectedRouteLocation?.coordinate else { return nil }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private var selectedMETPoint: (Date, Double)? {
        selectedPoint(in: analytics.metSeries)
    }

    private var selectedHRPoint: (Date, Double)? {
        selectedPoint(in: analytics.heartRates)
    }

    private var selectedPostHRPoint: (Date, Double)? {
        selectedPoint(in: analytics.postWorkoutHRSeries)
    }

    private var selectedPowerPoint: (Date, Double)? {
        selectedPoint(in: analytics.powerSeries)
    }

    private var selectedCadencePoint: (Date, Double)? {
        selectedPoint(in: analytics.cadenceSeries)
    }

    private var selectedSpeedPoint: (Date, Double)? {
        selectedPoint(in: displaySpeedSeries)
    }

    private var selectedPacePoint: (Date, Double)? {
        let paceSeries = analytics.speedSeries.compactMap { point -> (Date, Double)? in
            let speedKPH = point.1 * 3.6
            guard speedKPH > 0 else { return nil }
            return (point.0, 60 / speedKPH)
        }
        return selectedPoint(in: paceSeries)
    }

    private var paceSeries: [(Date, Double)] {
        analytics.speedSeries.compactMap { point -> (Date, Double)? in
            let speedKPH = point.1 * 3.6
            guard speedKPH > 0.1 else { return nil }
            let pacePerKilometer = 60 / speedKPH
            let formattedPace = unitPreferences.resolvedPaceUnit == .perMile
                ? pacePerKilometer * 1.609344
                : pacePerKilometer
            return (point.0, formattedPace)
        }
    }

    private var selectedElevationPoint: (Date, Double)? {
        selectedPoint(in: displayElevationSeries)
    }

    private var selectedVerticalOscillationPoint: (Date, Double)? {
        selectedPoint(in: analytics.verticalOscillationSeries)
    }

    private var selectedGroundContactTimePoint: (Date, Double)? {
        selectedPoint(in: analytics.groundContactTimeSeries)
    }

    private var selectedStrideLengthPoint: (Date, Double)? {
        selectedPoint(in: displayStrideLengthSeries)
    }

    private var selectedStrokeCountPoint: (Date, Double)? {
        selectedPoint(in: analytics.strokeCountSeries)
    }

    private var selectedRouteElapsedText: String? {
        guard let timestamp = selectedRouteLocation?.timestamp else { return nil }
        let elapsed = max(0, timestamp.timeIntervalSince(analytics.workout.startDate))
        return workoutElapsedTimeText(elapsed)
    }

    private func nearestPoint(in data: [(Date, Double)], to date: Date) -> (Date, Double)? {
        data.min { lhs, rhs in
            abs(lhs.0.timeIntervalSince(date)) < abs(rhs.0.timeIntervalSince(date))
        }
    }

    private func selectedPoint(in data: [(Date, Double)]) -> (Date, Double)? {
        guard let selectedScrubbedDate else { return nil }
        return nearestPoint(in: data, to: selectedScrubbedDate)
    }

    private func nearestRouteLocation(to date: Date) -> CLLocation? {
        let locations = routeLookupLocations.isEmpty ? routeLocations : routeLookupLocations
        return locations.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    private func pointSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        data: [(Date, Double)]
    ) -> (Date, Double)? {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard let xPosition = ChartInteractionSmoothing.clampedXPosition(
            for: location,
            plotFrame: plotFrame
        ) else {
            return nil
        }

        let date = proxy.value(atX: xPosition) as Date?
            ?? ChartInteractionSmoothing.fallbackBoundaryDate(
                for: xPosition,
                plotFrame: plotFrame,
                data: data
            )
        guard let date else { return nil }
        return nearestPoint(in: data, to: date)
    }

    private func updateSelection(
        from location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        data: [(Date, Double)]
    ) {
        guard let point = pointSelection(at: location, proxy: proxy, geometry: geometry, data: data) else {
            return
        }
        if selectedScrubbedDate != point.0 {
            updateSelectedScrubbedDate(point.0)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func isHorizontalScrub(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height)
    }

    @ViewBuilder
    private func selectionOverlay(
        proxy: ChartProxy,
        geometry: GeometryProxy,
        data: [(Date, Double)]
    ) -> some View {
        HorizontalChartScrubOverlay(
            onChanged: { location in
                updateSelection(
                    from: location,
                    proxy: proxy,
                    geometry: geometry,
                    data: data
                )
            }
        )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateSelection(
                        from: location,
                        proxy: proxy,
                        geometry: geometry,
                        data: data
                    )
                case .ended:
                    break
                }
            }
    }

    @ChartContentBuilder
    private func selectionMarks(
        selected: (Date, Double)?,
        xLabel: String,
        yLabel: String,
        color: Color,
        secondaryText: String? = nil,
        valueText: @escaping (Double) -> String
    ) -> some ChartContent {
        if let selected {
            RuleMark(x: .value(xLabel, selected.0))
                .foregroundStyle(color.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

            PointMark(
                x: .value(xLabel, selected.0),
                y: .value(yLabel, selected.1)
            )
            .symbolSize(90)
            .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func selectionBubble(
        selected: (Date, Double)?,
        color: Color,
        secondaryText: String? = nil,
        valueText: @escaping (Double) -> String
    ) -> some View {
        if let selected {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.0, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(valueText(selected.1))
                    .font(.caption.bold())
                    .foregroundColor(color)
                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption2.bold())
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func chartYScaleDomain(
        for values: [Double],
        including extraValues: [Double] = [],
        minimumPadding: Double = 1
    ) -> ClosedRange<Double> {
        let allValues = (values + extraValues).filter { $0.isFinite }
        guard let minValue = allValues.min(), let maxValue = allValues.max() else {
            return 0...1
        }

        let span = max(maxValue - minValue, minimumPadding)
        let padding = max(span * 0.12, minimumPadding)
        return (minValue - padding)...(maxValue + padding)
    }

    private func zoneForHeartRate(_ heartRate: Double) -> HRZone? {
        heartRateZoneBreakdown.first { zone in
            zone.range.contains(heartRate)
        } ?? dynamicHeartRateZones.first { zone in
            zone.range.contains(heartRate)
        }
    }

    /// Convert hex color string to SwiftUI Color
    private func hexToColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }

    private var activeZoneProfile: HRZoneProfile? {
        switch hrZoneSettings.mode {
        case .intelligent:
            historicalZoneProfile ?? analytics.hrZoneProfile
        case .customSchema, .customZones:
            historicalZoneProfile
        }
    }

    private var shouldWaitForResolvedZoneProfile: Bool {
        hrZoneSettings.mode != .intelligent && !hasResolvedZoneProfile
    }

    private var customZoneProfile: HRZoneProfile? {
        let bounds = hrZoneSettings.customZoneUpperBounds
        guard bounds.count == 5 else { return nil }
        guard zip(bounds, bounds.dropFirst()).allSatisfy({ pair in pair.0 < pair.1 }) else { return nil }

        let lowerBounds = [0.0] + Array(bounds.dropLast())
        let colors = ["0099FF", "00CC00", "FFCC00", "FF6600", "FF0000"]
        let zones = zip(Array(1...5), zip(lowerBounds, bounds)).map { zoneNumber, pair in
            HeartRateZone(
                name: "Zone \(zoneNumber)",
                range: pair.0...pair.1,
                color: colors[zoneNumber - 1],
                zoneNumber: zoneNumber
            )
        }

        return HRZoneProfile(
            sport: analytics.workout.workoutActivityType.rawValue,
            schema: hrZoneSettings.customSchema,
            maxHR: bounds.last,
            restingHR: nil,
            lactateThresholdHR: nil,
            zones: zones,
            lastUpdated: Date(),
            adaptive: false
        )
    }

    /// Dynamic heart rate zones from analytics profile
    private var dynamicHeartRateZones: [HRZone] {
        if shouldWaitForResolvedZoneProfile {
            return []
        }

        guard let profile = activeZoneProfile else {
            // Fallback if no profile available
            return generateFallbackZones()
        }
        
        // Convert HeartRateZone to HRZone for display
        return profile.zones.map { zone in
            HRZone(
                name: zone.name,
                color: hexToColor(zone.color),
                time: 0,
                range: zone.range
            )
        }
    }

    /// Fallback zone generation if profile unavailable
    private func generateFallbackZones() -> [HRZone] {
        let maxHR = maxHeartRate ?? 190
        return [
            HRZone(name: "Zone 1: Easy", color: .blue, time: 0.0, range: 0.0...(maxHR * 0.60)),
            HRZone(name: "Zone 2: Base", color: .cyan, time: 0.0, range: (maxHR * 0.60)...(maxHR * 0.70)),
            HRZone(name: "Zone 3: Tempo", color: .green, time: 0.0, range: (maxHR * 0.70)...(maxHR * 0.80)),
            HRZone(name: "Zone 4: Threshold", color: .orange, time: 0.0, range: (maxHR * 0.80)...(maxHR * 0.90)),
            HRZone(name: "Zone 5: Max", color: .red, time: 0.0, range: (maxHR * 0.90)...(maxHR * 1.00))
        ]
    }

    private var heartRateZoneThresholds: [Double] {
        // Using approximate % of avg recorded max HR (or 190 if unknown)
        let maxHR = maxHeartRate ?? 190
        return [0.6, 0.7, 0.8, 0.9, 1.0].map { $0 * maxHR }
    }

    private var heartRateZoneBreakdown: [HRZone] {
        if shouldWaitForResolvedZoneProfile {
            return []
        }

        if let profile = activeZoneProfile {
            return healthKitManager.calculateZoneBreakdown(heartRates: analytics.heartRates, zoneProfile: profile).map { breakdown in
                HRZone(
                    name: breakdown.zone.name,
                    color: hexToColor(breakdown.zone.color),
                    time: breakdown.timeInZone,
                    range: breakdown.zone.range
                )
            }
        }

        // Fallback to manual calculation
        let zones = dynamicHeartRateZones
        var updatedZones = zones
        
        let samples = analytics.heartRates.sorted { $0.0 < $1.0 }
        for i in 0..<(samples.count - 1) {
            let hr = samples[i].1
            let next = samples[i + 1].0
            let duration = next.timeIntervalSince(samples[i].0)
            if let idx = updatedZones.firstIndex(where: { $0.range.contains(hr) }) {
                updatedZones[idx].time += duration
            }
        }
        return updatedZones
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsSummaryContent ? 16 : 12) {
            if showsMapSection, !coloredSegments.isEmpty {
                RouteMapView(
                    segments: coloredSegments,
                    startCoordinate: routeLocations.first?.coordinate,
                    endCoordinate: routeLocations.last?.coordinate,
                    highlightedCoordinate: selectedRouteLocation?.coordinate
                )
                    .frame(height: 300)
                    .cornerRadius(16)

                if let coordinateText = selectedRouteCoordinateText {
                    HStack(spacing: 12) {
                        Label(selectedScrubbedDate == nil ? "Route Start" : "Selected Route Point", systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let elapsedText = selectedRouteElapsedText {
                            Text(elapsedText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(coordinateText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if allowsMapExpansion {
                    Button {
                        showMapDetail = true
                    } label: {
                        HStack {
                            Text("View More")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsSummaryContent {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    if let formattedDistanceMetric {
                        WorkoutMetricCard(title: "Distance", value: formattedDistanceMetric.value, unit: formattedDistanceMetric.unit, icon: "ruler", color: .blue)
                    }
                    if let formattedAvgSpeedMetric {
                        WorkoutMetricCard(title: "Avg Speed", value: formattedAvgSpeedMetric.value, unit: formattedAvgSpeedMetric.unit, icon: "speedometer", color: .teal)
                    }
                    if (analytics.workout.workoutActivityType == .running || analytics.workout.workoutActivityType == .hiking || analytics.workout.workoutActivityType == .walking), let formattedAvgPaceMetric {
                        WorkoutMetricCard(title: "Avg Pace", value: formattedAvgPaceMetric.value, unit: formattedAvgPaceMetric.unit, icon: "stopwatch", color: .blue)
                    }
                    if let power = avgPower {
                        WorkoutMetricCard(title: "Avg Power", value: String(format: "%.0f", power), unit: "W", icon: "bolt.fill", color: .purple)
                    }
                    if let cadence = avgCadence {
                        WorkoutMetricCard(title: "Avg Cadence", value: String(format: "%.0f", cadence), unit: "rpm", icon: "waveform.path.ecg", color: .mint)
                    }
                    if let kcal = analytics.workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
                        WorkoutMetricCard(title: "Active KCAL", value: String(format: "%.0f", kcal), unit: "kcal", icon: "flame.fill", color: .orange)
                    }
                    if let elevation = analytics.elevationGain {
                        let formattedElevation = unitPreferences.formattedElevation(fromMeters: elevation)
                        WorkoutMetricCard(title: "Elevation Gain", value: formattedElevation.value, unit: formattedElevation.unit, icon: "mountain.2.fill", color: .green)
                    }
                    if let hr = avgHeartRate {
                        WorkoutMetricCard(title: "Avg HR", value: String(format: "%.0f", hr), unit: "bpm", icon: "heart.fill", color: .red)
                    }
                    if let pause = pausedDuration {
                        WorkoutMetricCard(title: "Paused", value: workoutElapsedTimeText(pause), unit: "", icon: "pause.fill", color: .gray)
                    }
                    if let vo = analytics.verticalOscillation {
                        WorkoutMetricCard(title: "Vert Osc", value: String(format: "%.1f", vo), unit: "cm", icon: "waveform", color: .cyan)
                    }
                    if let gct = analytics.groundContactTime {
                        WorkoutMetricCard(title: "GCT", value: String(format: "%.0f", gct), unit: "ms", icon: "figure.run", color: .indigo)
                    }
                    if let sl = analytics.strideLength {
                        let formattedStride = unitPreferences.formattedElevation(fromMeters: sl, digits: 2)
                        WorkoutMetricCard(title: "Stride", value: formattedStride.value, unit: formattedStride.unit, icon: "ruler.fill", color: .pink)
                    }
                }
            }

            if showsSummaryContent {
                if let profile = activeZoneProfile {
                    if hrZoneSettings.mode == .customZones {
                        HeartRateZoneProfileSummaryView(
                            profile: profile,
                            displayedMaxHR: historicalMaxHR,
                            displayedRestingHR: historicalRestingHR,
                            maxHRLabel: historicalMaxHR == nil ? "Max HR" : "7d Max HR",
                            restingHRLabel: historicalRestingHR == nil ? "Resting HR" : "7d Avg Resting HR",
                            schemaTitleOverride: "Custom",
                            showsDescription: false
                        )
                    } else {
                        HeartRateZoneProfileSummaryView(
                            profile: profile,
                            displayedMaxHR: historicalMaxHR,
                            displayedRestingHR: historicalRestingHR,
                            maxHRLabel: historicalMaxHR == nil ? "Max HR" : "7d Max HR",
                            restingHRLabel: historicalRestingHR == nil ? "Resting HR" : "7d Avg Resting HR"
                        )
                    }
                }
            }

            // MET Time Series
            VStack(alignment: .leading) {
                Text("MET Time Series")
                    .font(.subheadline)
                    .bold()
                Chart {
                    ForEach(analytics.metSeries, id: \.0) { point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("MET", point.1)
                        )
                        .foregroundStyle(.green)
                    }
                    selectionMarks(
                        selected: selectedMETPoint,
                        xLabel: "Time",
                        yLabel: "MET",
                        color: .green,
                        valueText: { String(format: "%.1f MET", $0) }
                    )
                }
                .chartYScale(domain: chartYScaleDomain(for: analytics.metSeries.map(\.1), minimumPadding: 0.5))
                .frame(height: standardChartHeight)
                .overlay(alignment: .topLeading) {
                    selectionBubble(
                        selected: selectedMETPoint,
                        color: .green,
                        valueText: { String(format: "%.1f MET", $0) }
                    )
                    .padding(8)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.metSeries
                        )
                    }
                }
                if let selected = selectedMETPoint {
                    Text("Selected: \(selected.0, style: .time) — \(String(format: "%.1f", selected.1)) MET")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack {
                    if let metTotal = analytics.metTotal {
                        Text("Total MET-min: \(String(format: "%.1f", metTotal))")
                    }
                    if let metAvg = analytics.metAverage {
                        Text("Avg MET: \(String(format: "%.1f", metAvg))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // HR Time Series
            VStack(alignment: .leading) {
                HStack {
                    Text("Heart Rate During Workout")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    Button(action: { withAnimation { showHRZones.toggle() } }) {
                        Text(showHRZones ? "Hide Zones" : "Show Zones")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(6)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
                let selectedZone = showHRZones ? selectedHRPoint.flatMap { zoneForHeartRate($0.1) } : nil
                Chart {
                    ForEach(analytics.heartRates, id: \.0) { point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("HR", point.1)
                        )
                        .foregroundStyle(.red)
                    }
                    if showHRZones {
                        ForEach(heartRateZoneBreakdown, id: \.name) { zone in
                            RuleMark(y: .value("Zone", zone.range.upperBound))
                                .foregroundStyle(zone.color.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        }
                    }
                    selectionMarks(
                        selected: selectedHRPoint,
                        xLabel: "Time",
                        yLabel: "HR",
                        color: selectedZone?.color ?? .red,
                        secondaryText: selectedZone?.name,
                        valueText: { "\(Int($0)) bpm" }
                    )
                }
                .chartYScale(
                    domain: chartYScaleDomain(
                        for: analytics.heartRates.map(\.1),
                        including: showHRZones ? heartRateZoneBreakdown.map { $0.range.upperBound } : []
                    )
                )
                .frame(height: heartRateChartHeight)
                .overlay(alignment: .topLeading) {
                    selectionBubble(
                        selected: selectedHRPoint,
                        color: selectedZone?.color ?? .red,
                        secondaryText: selectedZone?.name,
                        valueText: { "\(Int($0)) bpm" }
                    )
                    .padding(8)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.heartRates
                        )
                    }
                }

                HStack {
                    if let avgHR = avgHeartRate {
                        Text("Avg: \(Int(avgHR)) bpm")
                    }
                    if let maxHR = maxHeartRate {
                        Text("Max: \(Int(maxHR)) bpm")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if showHRZones {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(heartRateZoneBreakdown, id: \.name) { zone in
                            if zone.time > 0 {
                                HStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(zone.color.opacity(0.7))
                                        .frame(width: 18, height: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(zone.name) \(workoutElapsedTimeText(zone.time)) < \(Int(zone.range.upperBound)) BPM")
                                            .font(.caption2)
                                        GeometryReader { geo in
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.25))
                                                .frame(height: 6)
                                                .overlay(
                                                    Rectangle()
                                                        .fill(zone.color)
                                                        .frame(width: geo.size.width * CGFloat(zone.time / (heartRateZoneBreakdown.map { $0.time }.reduce(0, +) + 0.001)), height: 6),
                                                    alignment: .leading
                                                )
                                        }
                                        .frame(height: 6)
                                    }
                                }
                            }
                        }
                        Text("HR zones are based on estimated max heart rate and can be adjusted in settings.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                }
            }

            // Post-Workout HR
            VStack(alignment: .leading) {
                Text("Post-Workout HR (0-2 min)")
                    .font(.subheadline)
                    .bold()
                Chart {
                    ForEach(analytics.postWorkoutHRSeries, id: \.0) { point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("HR", point.1)
                        )
                        .foregroundStyle(.orange)
                    }
                    if let peak = analytics.peakHR {
                        RuleMark(y: .value("Peak HR", peak))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    selectionMarks(
                        selected: selectedPostHRPoint,
                        xLabel: "Time",
                        yLabel: "HR",
                        color: .orange,
                        valueText: { "\(Int($0)) bpm" }
                    )
                }
                .chartYScale(
                    domain: chartYScaleDomain(
                        for: analytics.postWorkoutHRSeries.map(\.1),
                        including: analytics.peakHR.map { [$0] } ?? []
                    )
                )
                .frame(height: standardChartHeight)
                .overlay(alignment: .topLeading) {
                    selectionBubble(
                        selected: selectedPostHRPoint,
                        color: .orange,
                        valueText: { "\(Int($0)) bpm" }
                    )
                    .padding(8)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.postWorkoutHRSeries
                        )
                    }
                }
                HStack {
                    if let hrr0 = analytics.hrr0 {
                        Text("HRR 0min: \(Int(hrr0))")
                    }
                    if let hrr1 = analytics.hrr1 {
                        Text("HRR 1min: \(Int(hrr1))")
                    }
                    if let hrr2 = analytics.hrr2 {
                        Text("HRR 2min: \(Int(hrr2))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Cycling Power if applicable
            if !analytics.powerSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Power")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(analytics.powerSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Power", point.1)
                            )
                            .foregroundStyle(.purple)
                        }
                        selectionMarks(
                            selected: selectedPowerPoint,
                            xLabel: "Time",
                            yLabel: "Power",
                            color: .purple,
                            valueText: { String(format: "%.0f W", $0) }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: analytics.powerSeries.map(\.1)))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedPowerPoint,
                            color: .purple,
                            valueText: { String(format: "%.0f W", $0) }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.powerSeries
                        )
                    }
                }
                    HStack {
                        let avgPower = analytics.powerSeries.map { $0.1 }.average
                        Text("Avg Power: \(avgPower.map { String(format: "%.1f", $0) } ?? "-") W")
                        if let point = selectedPowerPoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.1f", point.1)) W")
                                .foregroundColor(.blue)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Cycling Speed if applicable
            if !analytics.speedSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Speed")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(displaySpeedSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Speed", point.1)
                            )
                            .foregroundStyle(.blue)
                        }
                        selectionMarks(
                            selected: selectedSpeedPoint,
                            xLabel: "Time",
                            yLabel: "Speed",
                            color: .blue,
                            valueText: { String(format: "%.1f %@", $0, unitPreferences.resolvedSpeedUnit == .milesPerHour ? "mph" : "km/h") }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: displaySpeedSeries.map(\.1), minimumPadding: 0.5))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedSpeedPoint,
                            color: .blue,
                            valueText: { String(format: "%.1f %@", $0, unitPreferences.resolvedSpeedUnit == .milesPerHour ? "mph" : "km/h") }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: displaySpeedSeries
                            )
                        }
                    }
                    HStack {
                        let avgSpeed = displaySpeedSeries.map(\.1).average
                        Text("Avg Speed: \(avgSpeed.map { String(format: "%.1f", $0) } ?? "-") \(unitPreferences.resolvedSpeedUnit == .milesPerHour ? "mph" : "km/h")")
                        if let point = selectedSpeedPoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.1f", point.1)) \(unitPreferences.resolvedSpeedUnit == .milesPerHour ? "mph" : "km/h")")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if !analytics.cadenceSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Cadence")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(analytics.cadenceSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Cadence", point.1)
                            )
                            .foregroundStyle(.mint)
                        }
                        selectionMarks(
                            selected: selectedCadencePoint,
                            xLabel: "Time",
                            yLabel: "Cadence",
                            color: .mint,
                            valueText: { String(format: "%.0f rpm", $0) }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: analytics.cadenceSeries.map(\.1)))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedCadencePoint,
                            color: .mint,
                            valueText: { String(format: "%.0f rpm", $0) }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.cadenceSeries
                        )
                    }
                }
                    HStack {
                        let avgCadence = analytics.cadenceSeries.map { $0.1 }.average
                        Text("Avg Cadence: \(avgCadence.map { String(format: "%.0f", $0) } ?? "-") rpm")
                        if let point = selectedCadencePoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.0f", point.1)) rpm")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Elevation for eligible workouts
            if !analytics.elevationSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Elevation")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(displayElevationSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Elevation", point.1)
                            )
                            .foregroundStyle(.green)
                        }
                        selectionMarks(
                            selected: selectedElevationPoint,
                            xLabel: "Time",
                            yLabel: "Elevation",
                            color: .green,
                            valueText: { String(format: "%.0f %@", $0, unitPreferences.resolvedElevationUnit == .feet ? "ft" : "m") }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: displayElevationSeries.map(\.1)))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedElevationPoint,
                            color: .green,
                            valueText: { String(format: "%.0f %@", $0, unitPreferences.resolvedElevationUnit == .feet ? "ft" : "m") }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: displayElevationSeries
                        )
                    }
                }
                    HStack {
                        if let gain = analytics.elevationGain {
                            let formattedGain = unitPreferences.formattedElevation(fromMeters: gain)
                            Text("Total Gain: \(formattedGain.value) \(formattedGain.unit)")
                        }
                        if let point = selectedElevationPoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.0f", point.1)) \(unitPreferences.resolvedElevationUnit == .feet ? "ft" : "m")")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if !analytics.verticalOscillationSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Vertical Oscillation")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(analytics.verticalOscillationSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Vertical Oscillation", point.1)
                            )
                            .foregroundStyle(.cyan)
                        }
                        selectionMarks(
                            selected: selectedVerticalOscillationPoint,
                            xLabel: "Time",
                            yLabel: "Vertical Oscillation",
                            color: .cyan,
                            valueText: { String(format: "%.1f cm", $0) }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: analytics.verticalOscillationSeries.map(\.1), minimumPadding: 0.2))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedVerticalOscillationPoint,
                            color: .cyan,
                            valueText: { String(format: "%.1f cm", $0) }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: analytics.verticalOscillationSeries
                            )
                        }
                    }
                    HStack {
                        if let vo = analytics.verticalOscillation {
                            Text("Avg Vertical Oscillation: \(String(format: "%.1f", vo)) cm")
                        }
                        if let point = selectedVerticalOscillationPoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.1f", point.1)) cm")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if !analytics.groundContactTimeSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Ground Contact Time")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(analytics.groundContactTimeSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Ground Contact Time", point.1)
                            )
                            .foregroundStyle(.indigo)
                        }
                        selectionMarks(
                            selected: selectedGroundContactTimePoint,
                            xLabel: "Time",
                            yLabel: "Ground Contact Time",
                            color: .indigo,
                            valueText: { String(format: "%.0f ms", $0) }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: analytics.groundContactTimeSeries.map(\.1), minimumPadding: 1))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedGroundContactTimePoint,
                            color: .indigo,
                            valueText: { String(format: "%.0f ms", $0) }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: analytics.groundContactTimeSeries
                            )
                        }
                    }
                    HStack {
                        if let gct = analytics.groundContactTime {
                            Text("Avg GCT: \(String(format: "%.0f", gct)) ms")
                        }
                        if let point = selectedGroundContactTimePoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.0f", point.1)) ms")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if !analytics.strideLengthSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Stride Length")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(displayStrideLengthSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Stride Length", point.1)
                            )
                            .foregroundStyle(.pink)
                        }
                        selectionMarks(
                            selected: selectedStrideLengthPoint,
                            xLabel: "Time",
                            yLabel: "Stride Length",
                            color: .pink,
                            valueText: { String(format: "%.2f %@", $0, unitPreferences.resolvedElevationUnit == .feet ? "ft" : "m") }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: displayStrideLengthSeries.map(\.1), minimumPadding: 0.05))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedStrideLengthPoint,
                            color: .pink,
                            valueText: { String(format: "%.2f %@", $0, unitPreferences.resolvedElevationUnit == .feet ? "ft" : "m") }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: displayStrideLengthSeries
                            )
                        }
                    }
                    HStack {
                        if let sl = analytics.strideLength {
                            let formattedStride = unitPreferences.formattedElevation(fromMeters: sl, digits: 2)
                            Text("Avg Stride Length: \(formattedStride.value) \(formattedStride.unit)")
                        }
                        if let point = selectedStrideLengthPoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.2f", point.1)) \(unitPreferences.resolvedElevationUnit == .feet ? "ft" : "m")")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Pace for running/hiking
            if (analytics.workout.workoutActivityType == .running || analytics.workout.workoutActivityType == .hiking || analytics.workout.workoutActivityType == .walking || analytics.workout.workoutActivityType == .cycling) && !analytics.speedSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Pace")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(paceSeries, id: \.0) { point in
                            LineMark(
                                x: .value("Time", point.0),
                                y: .value("Pace", point.1)
                            )
                            .foregroundStyle(.teal)
                        }
                        selectionMarks(
                            selected: selectedPacePoint,
                            xLabel: "Time",
                            yLabel: "Pace",
                            color: .teal,
                            valueText: { String(format: "%.2f %@", $0, unitPreferences.resolvedPaceUnit == .perMile ? "min/mi" : "min/km") }
                        )
                    }
                    .chartYScale(
                        domain: chartYScaleDomain(
                            for: paceSeries.map(\.1),
                            minimumPadding: 0.25
                        )
                    )
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedPacePoint,
                            color: .teal,
                            valueText: { String(format: "%.2f %@", $0, unitPreferences.resolvedPaceUnit == .perMile ? "min/mi" : "min/km") }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: paceSeries
                            )
                        }
                    }
                    HStack {
                        let avgPace = paceSeries.map(\.1).average
                        Text("Avg Pace: \(avgPace.map { String(format: "%.1f", $0) } ?? "-") \(unitPreferences.resolvedPaceUnit == .perMile ? "min/mi" : "min/km")")
                        if let point = selectedPacePoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.2f", point.1)) \(unitPreferences.resolvedPaceUnit == .perMile ? "min/mi" : "min/km")")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if !analytics.strokeCountSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Stroke Count")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(analytics.strokeCountSeries, id: \.0) { point in
                            BarMark(
                                x: .value("Time", point.0),
                                y: .value("Stroke Count", point.1)
                            )
                            .foregroundStyle(.blue)
                        }
                        selectionMarks(
                            selected: selectedStrokeCountPoint,
                            xLabel: "Time",
                            yLabel: "Stroke Count",
                            color: .blue,
                            valueText: { String(format: "%.0f strokes", $0) }
                        )
                    }
                    .chartYScale(domain: chartYScaleDomain(for: analytics.strokeCountSeries.map(\.1), minimumPadding: 1))
                    .frame(height: standardChartHeight)
                    .overlay(alignment: .topLeading) {
                        selectionBubble(
                            selected: selectedStrokeCountPoint,
                            color: .blue,
                            valueText: { String(format: "%.0f strokes", $0) }
                        )
                        .padding(8)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: analytics.strokeCountSeries
                            )
                        }
                    }
                    HStack {
                        let averageStrokeCount = analytics.strokeCountSeries.map(\.1).average
                        if let averageStrokeCount {
                            Text("Avg Stroke Count: \(String(format: "%.0f", averageStrokeCount))")
                        }
                        if let point = selectedStrokeCountPoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.0f", point.1)) strokes")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Splits for eligible workouts
            if analytics.workout.workoutActivityType == .running || analytics.workout.workoutActivityType == .cycling || analytics.workout.workoutActivityType == .hiking {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Splits")
                        .font(.subheadline)
                        .bold()
                    let splits = generateSplits()
                    ForEach(splits, id: \.distance) { split in
                        HStack {
                            Text("\(String(format: "%.1f", split.distance)) \(unitPreferences.resolvedDistanceUnit == .miles ? "mi" : "km")")
                                .font(.caption)
                                .frame(width: 72, alignment: .leading)
                            Text(workoutElapsedTimeText(split.time))
                                .font(.caption)
                            if let pace = split.pace {
                                Text(String(format: "%.1f %@", pace, unitPreferences.resolvedPaceUnit == .perMile ? "min/mi" : "min/km"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let hr = split.avgHR {
                                Text(String(format: "%.0f bpm", hr))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
        .onAppear {
            if showsMapSection || showsSummaryContent {
                loadRoute()
            }
        }
        .task(id: analytics.workout.startDate) {
            await loadHistoricalZoneProfile()
        }
        .fullScreenCover(isPresented: $showMapDetail) {
            MapDetailView(
                analytics: analytics,
                hrZoneSettings: hrZoneSettings
            )
        }
    }

    private func loadHistoricalZoneProfile() async {
        hasResolvedZoneProfile = false
        switch hrZoneSettings.mode {
        case .customZones:
            let workoutDate = analytics.workout.startDate
            historicalMaxHR = await healthKitManager.fetchMaxHR(workoutDate: workoutDate)
            historicalRestingHR = await healthKitManager.fetchRHR(workoutDate: workoutDate)
            historicalZoneProfile = customZoneProfile

        case .customSchema:
            let rebuiltProfile = await healthKitManager.createHRZoneProfile(
                for: analytics.workout.workoutActivityType,
                schema: hrZoneSettings.customSchema,
                customMaxHR: hrZoneSettings.fixedMaxHR,
                customRestingHR: hrZoneSettings.fixedRestingHR,
                customLTHR: hrZoneSettings.fixedLTHR
            )

            historicalMaxHR = rebuiltProfile.maxHR
            historicalRestingHR = rebuiltProfile.restingHR
            historicalZoneProfile = rebuiltProfile

        case .intelligent:
            let workoutDate = analytics.workout.startDate
            let maxHR = await healthKitManager.fetchMaxHR(workoutDate: workoutDate)
            let restingHR = await healthKitManager.fetchRHR(workoutDate: workoutDate)
            let schema = analytics.hrZoneProfile?.schema ?? healthKitManager.recommendedSchema(for: analytics.workout.workoutActivityType)
            let lactateThresholdHR = await healthKitManager.fetchLTHR(workoutDate: workoutDate, maxHR: maxHR)
            let rebuiltProfile = await healthKitManager.createHRZoneProfile(
                for: analytics.workout.workoutActivityType,
                schema: schema,
                customMaxHR: maxHR,
                customRestingHR: restingHR,
                customLTHR: lactateThresholdHR
            )

            historicalMaxHR = maxHR
            historicalRestingHR = restingHR
            historicalZoneProfile = rebuiltProfile
        }
        hasResolvedZoneProfile = true
    }

    private func loadRoute() {
        guard routeLocations.isEmpty else { return }
        guard analytics.workout.workoutActivityType == .running ||
              analytics.workout.workoutActivityType == .cycling ||
              analytics.workout.workoutActivityType == .walking ||
              analytics.workout.workoutActivityType == .hiking else { return }

        isLoadingRoute = true
        Task {
            let allLocations = await WorkoutRouteStore.shared.locations(for: analytics.workout)
            let displayLocations = sampledLocations(from: allLocations, maxPoints: 700)
            let displaySegments = buildColoredRouteSegments(
                locations: displayLocations,
                heartRates: analytics.heartRates
            )

            await MainActor.run {
                self.routeLookupLocations = allLocations
                self.routeLocations = displayLocations
                self.routePoints = displayLocations.map { RoutePoint(coordinate: $0.coordinate) }
                self.coloredSegments = displaySegments
                self.isLoadingRoute = false
            }
        }
    }

    private func generateSplits() -> [Split] {
        guard let totalDistance = analytics.workout.totalDistance?.doubleValue(for: .meter()) else { return [] }
        let splitDistanceKilometers = unitPreferences.resolvedDistanceUnit == .miles ? 1.609344 : 1.0
        let totalDistanceInDisplayUnits = totalDistance / (splitDistanceKilometers * 1000)
        var splits: [Split] = []
        for displayedSplitDistance in stride(from: 1.0, through: totalDistanceInDisplayUnits, by: 1.0) {
            let splitDistanceKilometersValue = displayedSplitDistance * splitDistanceKilometers
            let timeAtKm = analytics.workout.startDate.addingTimeInterval((splitDistanceKilometersValue / (totalDistance / 1000)) * analytics.workout.duration)
            let time = timeAtKm.timeIntervalSince(analytics.workout.startDate)
            let pace = analytics.speedSeries.isEmpty ? nil : paceSeries.map(\.1).average
            let hrSamplesInSplit = analytics.heartRates.filter { $0.0 <= timeAtKm }
            let avgHR = hrSamplesInSplit.isEmpty ? nil : hrSamplesInSplit.map { $0.1 }.average
            splits.append(Split(distance: displayedSplitDistance, time: time, pace: pace, avgHR: avgHR))
        }
        return splits
    }
}

private struct HorizontalChartScrubOverlay: UIViewRepresentable {
    let onChanged: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(panGesture)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGPoint) -> Void

        init(onChanged: @escaping (CGPoint) -> Void) {
            self.onChanged = onChanged
        }

        @objc
        func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed, .ended:
                onChanged(gesture.location(in: gesture.view))
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = panGesture.view else {
                return false
            }

            let velocity = panGesture.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

private struct VerticalResizeHandleOverlay: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(panGesture)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc
        func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translationY = gesture.translation(in: gesture.view).y

            switch gesture.state {
            case .began, .changed:
                onChanged(translationY)
            case .ended, .cancelled, .failed:
                onEnded(translationY)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = panGesture.view else {
                return false
            }

            let velocity = panGesture.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

private struct MapDetailView: View {
    let analytics: WorkoutAnalytics
    let hrZoneSettings: HRZoneUserSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScrubbedDate: Date? = nil
    @State private var routeLocations: [CLLocation] = []
    @State private var routeLookupLocations: [CLLocation] = []
    @State private var coloredSegments: [ColoredRouteSegment] = []
    @State private var isLoadingRoute = false
    @State private var showExpandedMap = false
    @State private var preferredMapSectionHeight: CGFloat = 374
    @State private var liveMapSectionDragTranslation: CGFloat = 0

    private var selectedRouteLocation: CLLocation? {
        let referenceDate = selectedScrubbedDate ?? analytics.workout.startDate
        let locations = routeLookupLocations.isEmpty ? routeLocations : routeLookupLocations
        return locations.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(referenceDate)) < abs(rhs.timestamp.timeIntervalSince(referenceDate))
        }
    }

    private var selectedRouteCoordinateText: String? {
        guard let coordinate = selectedRouteLocation?.coordinate else { return nil }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private var selectedRouteElapsedText: String? {
        guard let timestamp = selectedRouteLocation?.timestamp else { return nil }
        let elapsed = max(0, timestamp.timeIntervalSince(analytics.workout.startDate))
        return workoutElapsedTimeText(elapsed)
    }

    private let defaultMapSectionHeight: CGFloat = 374
    private let minimumMapSectionHeight: CGFloat = 250
    private let minimumScrollSectionHeight: CGFloat = 240
    private let resizeHandleHeight: CGFloat = 28

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let clampedMapSectionHeight = resolvedMapSectionHeight(
                    for: geometry.size.height,
                    translation: liveMapSectionDragTranslation
                )

                VStack(spacing: 0) {
                    pinnedMapSection
                        .frame(height: clampedMapSectionHeight)

                    resizeHandle(maxTotalHeight: geometry.size.height)

                    ScrollView {
                        WorkoutDetailView(
                            analytics: analytics,
                            hrZoneSettings: hrZoneSettings,
                            allowsMapExpansion: false,
                            showsSummaryContent: false,
                            showsMapSection: false,
                            scrubbedDate: $selectedScrubbedDate
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .frame(
                        width: geometry.size.width,
                        height: max(0, geometry.size.height - clampedMapSectionHeight - resizeHandleHeight),
                        alignment: .top
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .background(Color.black)
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: analytics.workout.uuid.uuidString) {
                preferredMapSectionHeight = defaultMapSectionHeight
                liveMapSectionDragTranslation = 0
                await loadRoute()
            }
            .fullScreenCover(isPresented: $showExpandedMap) {
                RouteMapFullscreenView(
                    segments: coloredSegments,
                    startCoordinate: routeLocations.first?.coordinate,
                    endCoordinate: routeLocations.last?.coordinate,
                    highlightedCoordinate: selectedRouteLocation?.coordinate
                )
            }
        }
    }

    private func resolvedMapSectionHeight(
        for totalHeight: CGFloat,
        translation: CGFloat = 0
    ) -> CGFloat {
        let maxAllowedHeight = max(
            minimumMapSectionHeight,
            totalHeight - minimumScrollSectionHeight - resizeHandleHeight
        )
        let proposedHeight = preferredMapSectionHeight + translation
        return min(max(proposedHeight, minimumMapSectionHeight), maxAllowedHeight)
    }

    @ViewBuilder
    private func resizeHandle(maxTotalHeight: CGFloat) -> some View {
        ZStack {
            Color.black

            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 56, height: 6)
        }
        .frame(height: resizeHandleHeight)
        .contentShape(Rectangle())
        .overlay {
            VerticalResizeHandleOverlay(
                onChanged: { translation in
                    liveMapSectionDragTranslation = translation
                },
                onEnded: { translation in
                    preferredMapSectionHeight = resolvedMapSectionHeight(
                        for: maxTotalHeight,
                        translation: translation
                    )
                    liveMapSectionDragTranslation = 0
                }
            )
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var pinnedMapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showExpandedMap = true
            } label: {
                ZStack {
                    if !coloredSegments.isEmpty {
                        RouteMapView(
                            segments: coloredSegments,
                            startCoordinate: routeLocations.first?.coordinate,
                            endCoordinate: routeLocations.last?.coordinate,
                            highlightedCoordinate: selectedRouteLocation?.coordinate,
                            isInteractive: false
                        )
                    } else if isLoadingRoute {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .overlay {
                                Label("No route available", systemImage: "map")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("Open Map", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .buttonStyle(.plain)

            if let coordinateText = selectedRouteCoordinateText {
                HStack(spacing: 12) {
                    Label(selectedScrubbedDate == nil ? "Route Start" : "Selected Route Point", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let elapsedText = selectedRouteElapsedText {
                        Text(elapsedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(coordinateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.black)
    }

    private func loadRoute() async {
        guard coloredSegments.isEmpty, !isLoadingRoute else { return }

        await MainActor.run {
            isLoadingRoute = true
        }

        let allLocations = await WorkoutRouteStore.shared.locations(for: analytics.workout)
        let displayLocations = sampledLocations(from: allLocations, maxPoints: 700)
        let displaySegments = buildColoredRouteSegments(
            locations: displayLocations,
            heartRates: analytics.heartRates
        )

        await MainActor.run {
            routeLookupLocations = allLocations
            routeLocations = displayLocations
            coloredSegments = displaySegments
            isLoadingRoute = false
        }
    }

}

private struct RouteMapFullscreenView: View {
    let segments: [ColoredRouteSegment]
    let startCoordinate: CLLocationCoordinate2D?
    let endCoordinate: CLLocationCoordinate2D?
    let highlightedCoordinate: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                RouteMapView(
                    segments: segments,
                    startCoordinate: startCoordinate,
                    endCoordinate: endCoordinate,
                    highlightedCoordinate: highlightedCoordinate,
                    isInteractive: true
                )
                .ignoresSafeArea()

                Button("Done") {
                    dismiss()
                }
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

struct HRZoneSettingsSheet: View {
    @Binding var isPresented: Bool
    @Binding var configurationMode: HRZoneConfigurationMode
    @Binding var selectedSchema: HRZoneSchema
    @Binding var fixedMaxHR: Double?
    @Binding var fixedRestingHR: Double?
    @Binding var fixedLTHR: Double?
    @Binding var customZone1Upper: Double
    @Binding var customZone2Upper: Double
    @Binding var customZone3Upper: Double
    @Binding var customZone4Upper: Double
    @Binding var customZone5Upper: Double

    private var customZoneBoundsAreAscending: Bool {
        let bounds = [
            customZone1Upper,
            customZone2Upper,
            customZone3Upper,
            customZone4Upper,
            customZone5Upper
        ]
        return zip(bounds, bounds.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        }
    }

    private var selectedSchemaTitle: String {
        switch selectedSchema {
        case .mhrPercentage:
            return "Max HR Percentage"
        case .karvonen:
            return "Karvonen"
        case .lactatThreshold:
            return "Lactate Threshold"
        case .polarized:
            return "Polarized 3-Zone"
        }
    }

    private var formulaDetailsSymbol: String {
        if configurationMode == .intelligent {
            return configurationMode.symbol
        }

        switch selectedSchema {
        case .mhrPercentage:
            return "heart.circle"
        case .karvonen:
            return "waveform.path.ecg"
        case .lactatThreshold:
            return "figure.run"
        case .polarized:
            return "line.3.horizontal.decrease.circle"
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Zone Strategy") {
                    Picker("Mode", selection: $configurationMode) {
                        ForEach(HRZoneConfigurationMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(configurationMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if configurationMode != .customZones {
                    Section("Schema") {
                        if configurationMode == .intelligent {
                            Text("Best schema is intelligently selected for each workout.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("The app analyzes the workout type (e.g. running, cycling), along with your recent max HR, resting HR, and threshold estimates, then chooses the most appropriate formula (e.g. Lactate Threshold, Karvonen, or Max HR %) to generate zones.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Formula", selection: $selectedSchema) {
                                Text("Lactate Threshold").tag(HRZoneSchema.lactatThreshold)
                                Text("Karvonen").tag(HRZoneSchema.karvonen)
                                Text("Max HR Percentage").tag(HRZoneSchema.mhrPercentage)
                                Text("Polarized 3-Zone").tag(HRZoneSchema.polarized)
                            }

                            Text("Selected formula: \(selectedSchemaTitle)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Set HR Zones") {
                    switch configurationMode {
                    case .intelligent:
                        Text("Each workout uses the schema that best fits the sport and rebuilds zones from recent metrics such as resting HR, max HR, threshold estimates, and workout context.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                    case .customSchema:
                        if selectedSchema == .mhrPercentage || selectedSchema == .karvonen {
                            HStack {
                                Text("Max HR")
                                Spacer()
                                TextField("Optional", value: $fixedMaxHR, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
                            }
                        }

                        if selectedSchema == .karvonen {
                            HStack {
                                Text("Resting HR")
                                Spacer()
                                TextField("Optional", value: $fixedRestingHR, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
                            }
                        }

                        if selectedSchema == .lactatThreshold || selectedSchema == .polarized {
                            HStack {
                                Text("LTHR")
                                Spacer()
                                TextField("Optional", value: $fixedLTHR, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
                            }
                        }

                        Text("Leave any field empty to keep the formula fixed while allowing the app to fall back to its baseline estimate for that variable.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                    case .customZones:
                        HStack {
                            Text("Zone 1 ceiling")
                            Spacer()
                            TextField("bpm", value: $customZone1Upper, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        HStack {
                            Text("Zone 2 ceiling")
                            Spacer()
                            TextField("bpm", value: $customZone2Upper, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        HStack {
                            Text("Zone 3 ceiling")
                            Spacer()
                            TextField("bpm", value: $customZone3Upper, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        HStack {
                            Text("Zone 4 ceiling")
                            Spacer()
                            TextField("bpm", value: $customZone4Upper, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        HStack {
                            Text("Zone 5 ceiling")
                            Spacer()
                            TextField("bpm", value: $customZone5Upper, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        if customZoneBoundsAreAscending {
                            Text("Zone ceilings are valid. Each higher zone begins where the previous one ends.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Each higher zone must have a larger heart-rate ceiling than the previous zone.")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section("Formula Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(configurationMode == .intelligent ? "Intelligent" : selectedSchemaTitle, systemImage: formulaDetailsSymbol)
                            .font(.caption.weight(.semibold))

                        if configurationMode == .intelligent {
                            Text("Understanding HR Zone Schemas")
                                .font(.caption)
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 10) {

                                // Lactate Threshold
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Lactate Threshold (Running / Cycling)")
                                        .font(.caption.weight(.semibold))

                                    Text("• Best for performance and endurance training")
                                    Text("• Anchored to your sustainable hard effort (threshold)")
                                    Text("• Most accurate when LTHR is available")

                                    Text("Uses: Lactate Threshold HR")
                                        .foregroundColor(.secondary)
                                }

                                // Karvonen
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Karvonen (Recovery / Low Intensity)")
                                        .font(.caption.weight(.semibold))

                                    Text("• Adjusts intensity based on resting HR")
                                    Text("• Good for recovery, walking, and base workouts")
                                    Text("• Reflects day-to-day readiness")

                                    Text("Uses: Max HR + Resting HR")
                                        .foregroundColor(.secondary)
                                }

                                // Max HR Percentage
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Max HR % (General Use)")
                                        .font(.caption.weight(.semibold))

                                    Text("• Simple and widely applicable")
                                    Text("• Works when limited personal data is available")
                                    Text("• Less individualized but very robust")

                                    Text("Uses: Max HR")
                                        .foregroundColor(.secondary)
                                }

                                // Polarized
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Polarized (Structured Training)")
                                        .font(.caption.weight(.semibold))

                                    Text("• Splits effort into low, threshold, and high zones")
                                    Text("• Encourages proper training distribution (80/20)")
                                    Text("• Great for structured programs")

                                    Text("Uses: Lactate Threshold HR")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)

                            Text("The app selects the schema that best matches the workout type and your available physiological data to produce the most meaningful zones.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            switch selectedSchema {
                            case .mhrPercentage:
                                Text("Formula: zone boundary = maxHR × intensity")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("This is the simplest model. It uses max HR only and ignores resting HR.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                            case .karvonen:
                                Text("Formula: HRR = maxHR - restingHR, then boundary = (HRR × intensity) + restingHR")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("This works well for recovery and lower-intensity sessions because it reacts to changes in resting HR.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                            case .lactatThreshold:
                                Text("Formula: zone boundary = LTHR × percentage band")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("This is the performance-focused option for running, cycling, and rowing when threshold data is available.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                            case .polarized:
                                Text("Formula: Zone 1 < 0.80 × LTHR, Zone 2 = 0.80-1.00 × LTHR, Zone 3 > 1.00 × LTHR")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("This keeps training distribution simple and is useful when you want a clear low / threshold / high split.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Reset") {
                    Button {
                        configurationMode = .intelligent
                        selectedSchema = .lactatThreshold
                        fixedMaxHR = nil
                        fixedRestingHR = nil
                        fixedLTHR = nil
                        customZone1Upper = 120
                        customZone2Upper = 140
                        customZone3Upper = 160
                        customZone4Upper = 180
                        customZone5Upper = 200
                    } label: {
                        HStack {
                            Image(systemName: "goforward")
                            Text("Reset HR Zone Settings")
                        }
                    }
                }
            }
            .navigationTitle("HR Zone Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

struct WorkoutMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

struct CompactWorkoutMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(color)
                if unit.isEmpty == false {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct RouteMapView: UIViewRepresentable {
    let segments: [ColoredRouteSegment]
    let startCoordinate: CLLocationCoordinate2D?
    let endCoordinate: CLLocationCoordinate2D?
    let highlightedCoordinate: CLLocationCoordinate2D?
    var isInteractive: Bool = true

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.isRotateEnabled = false
        map.showsScale = false
        map.isScrollEnabled = isInteractive
        map.isZoomEnabled = isInteractive
        map.isPitchEnabled = isInteractive
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let routeSignature = Coordinator.routeSignature(
            segments: segments,
            startCoordinate: startCoordinate,
            endCoordinate: endCoordinate
        )

        if context.coordinator.routeSignature != routeSignature {
            mapView.removeOverlays(mapView.overlays)

            var polylines: [ColoredPolyline] = []
            polylines.reserveCapacity(segments.count)
            for segment in segments {
                let coords = segment.coordinates
                let poly = ColoredPolyline(coordinates: coords, count: coords.count)
                poly.color = segment.color
                polylines.append(poly)
            }

            mapView.addOverlays(polylines)
            context.coordinator.routeSignature = routeSignature
            context.coordinator.didSetInitialRegion = false
            context.coordinator.updateStaticAnnotations(
                on: mapView,
                startCoordinate: startCoordinate,
                endCoordinate: endCoordinate
            )
        }

        context.coordinator.updateHighlightAnnotation(
            on: mapView,
            coordinate: highlightedCoordinate
        )

        if context.coordinator.didSetInitialRegion == false {
            if let routeRect = Coordinator.boundingMapRect(for: segments), routeRect.isNull == false {
                let fittedRect = mapView.mapRectThatFits(
                    routeRect,
                    edgePadding: UIEdgeInsets(top: 44, left: 28, bottom: 44, right: 28)
                )
                mapView.setVisibleMapRect(fittedRect, animated: false)
                context.coordinator.didSetInitialRegion = true
            } else if let first = segments.first?.coordinates.first {
                let region = MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                mapView.setRegion(region, animated: false)
                context.coordinator.didSetInitialRegion = true
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Subclass MKPolyline to carry a color with the overlay
    class ColoredPolyline: MKPolyline {
        var color: UIColor = .systemBlue
    }

    final class RouteMarkerAnnotation: NSObject, MKAnnotation {
        dynamic var coordinate: CLLocationCoordinate2D
        let tintColor: UIColor

        init(coordinate: CLLocationCoordinate2D, tintColor: UIColor) {
            self.coordinate = coordinate
            self.tintColor = tintColor
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var didSetInitialRegion = false
        var routeSignature = ""
        private var startAnnotation: RouteMarkerAnnotation?
        private var endAnnotation: RouteMarkerAnnotation?
        private var highlightAnnotation: RouteMarkerAnnotation?

        static func routeSignature(
            segments: [ColoredRouteSegment],
            startCoordinate: CLLocationCoordinate2D?,
            endCoordinate: CLLocationCoordinate2D?
        ) -> String {
            let first = segments.first?.coordinates.first
            let last = segments.last?.coordinates.last
            let start = startCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
            let end = endCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
            let firstPoint = first.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
            let lastPoint = last.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
            return "\(segments.count)|\(firstPoint)|\(lastPoint)|\(start)|\(end)"
        }

        static func boundingMapRect(for segments: [ColoredRouteSegment]) -> MKMapRect? {
            let coordinates = segments.flatMap(\.coordinates)
            guard let first = coordinates.first else { return nil }

            var rect = MKMapRect(
                origin: MKMapPoint(first),
                size: MKMapSize(width: 0, height: 0)
            )

            for coordinate in coordinates.dropFirst() {
                let point = MKMapPoint(coordinate)
                let pointRect = MKMapRect(
                    origin: point,
                    size: MKMapSize(width: 0, height: 0)
                )
                rect = rect.union(pointRect)
            }

            if rect.size.width < 1 || rect.size.height < 1 {
                let point = MKMapPoint(first)
                rect = MKMapRect(
                    x: point.x - 600,
                    y: point.y - 600,
                    width: 1200,
                    height: 1200
                )
            }

            return rect
        }

        func updateStaticAnnotations(
            on mapView: MKMapView,
            startCoordinate: CLLocationCoordinate2D?,
            endCoordinate: CLLocationCoordinate2D?
        ) {
            if let annotation = startAnnotation {
                mapView.removeAnnotation(annotation)
                startAnnotation = nil
            }
            if let annotation = endAnnotation {
                mapView.removeAnnotation(annotation)
                endAnnotation = nil
            }

            if let startCoordinate {
                let annotation = RouteMarkerAnnotation(coordinate: startCoordinate, tintColor: .systemGreen)
                startAnnotation = annotation
                mapView.addAnnotation(annotation)
            }

            if let endCoordinate {
                let annotation = RouteMarkerAnnotation(coordinate: endCoordinate, tintColor: .systemRed)
                endAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func updateHighlightAnnotation(
            on mapView: MKMapView,
            coordinate: CLLocationCoordinate2D?
        ) {
            guard let coordinate else {
                if let highlightAnnotation {
                    mapView.removeAnnotation(highlightAnnotation)
                    self.highlightAnnotation = nil
                }
                return
            }

            if let highlightAnnotation {
                if highlightAnnotation.coordinate.latitude != coordinate.latitude ||
                    highlightAnnotation.coordinate.longitude != coordinate.longitude {
                    highlightAnnotation.coordinate = coordinate
                }
            } else {
                let annotation = RouteMarkerAnnotation(coordinate: coordinate, tintColor: .systemBlue)
                highlightAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? ColoredPolyline {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.strokeColor = poly.color
                renderer.lineJoin = .round
                renderer.lineCap = .round
                // Adjust width based on approximate zoom (latitudeDelta) — thinner strokes
                let span = max(0.0001, mapView.region.span.latitudeDelta)
                let width = max(1.0, min(6.0, 3.0 / CGFloat(span)))
                renderer.lineWidth = width
                return renderer
            }
            return MKOverlayRenderer()
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? RouteMarkerAnnotation else { return nil }
            let identifier = "RouteMarkerAnnotation"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = annotation.tintColor
            view.glyphImage = UIImage(systemName: "circle.fill")
            view.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            for overlay in mapView.overlays {
                if let poly = overlay as? ColoredPolyline,
                   let renderer = mapView.renderer(for: poly) as? MKPolylineRenderer {
                    let span = max(0.0001, mapView.region.span.latitudeDelta)
                    renderer.lineWidth = max(1.0, min(6.0, 3.0 / CGFloat(span)))
                }
            }
        }
    }
}

extension HKWorkoutActivityType {
    var activityTypeSymbol: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .stairClimbing: return "figure.stairs"
        case .yoga: return "figure.mind.and.body"
        case .pilates: return "figure.core.training"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .mixedCardio: return "figure.mixed.cardio"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .jumpRope: return "figure.jumprope"
        case .taiChi: return "figure.taichi"
        case .golf: return "figure.golf"
        case .tennis: return "figure.tennis"
        case .soccer: return "figure.soccer"
        case .basketball: return "figure.basketball"
        case .baseball: return "figure.baseball"
        case .americanFootball: return "figure.american.football"
        case .rugby: return "figure.rugby"
        case .volleyball: return "figure.volleyball"
        case .handball: return "figure.handball"
        case .racquetball: return "figure.racquetball"
        case .squash: return "figure.squash"
        case .badminton: return "figure.badminton"
        case .pickleball: return "figure.pickleball"
        case .lacrosse: return "figure.lacrosse"
        case .softball: return "figure.softball"
        case .bowling: return "figure.bowling"
        case .cricket: return "figure.cricket"
        case .skatingSports: return "figure.skating"
        case .snowSports: return "figure.snowboarding"
        case .waterSports: return "figure.water.fitness"
        case .dance: return "figure.dance"
        case .barre: return "figure.barre"
        case .flexibility: return "figure.flexibility"
        case .gymnastics: return "figure.gymnastics"
        case .martialArts: return "figure.martial.arts"
        case .climbing: return "figure.climbing"
        case .equestrianSports: return "figure.equestrian.sports"
        case .fishing: return "figure.fishing"
        case .hunting: return "figure.hunting"
        case .play: return "figure.play"
        case .preparationAndRecovery: return "figure.cooldown"
        case .other: return "figure"
        default: return "figure"
        }
    }
}

/// Lightweight preview that loads route points for a workout and renders a small `RouteMapView`.
struct RoutePreviewView: View {
    let workout: HKWorkout
    let heartRates: [(Date, Double)]

    @State private var coloredSegments: [ColoredRouteSegment] = []
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if !coloredSegments.isEmpty {
                RouteMapView(
                    segments: coloredSegments,
                    startCoordinate: nil,
                    endCoordinate: nil,
                    highlightedCoordinate: nil,
                    isInteractive: false
                )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isLoading {
                ProgressView()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(Text("No route") .font(.caption).foregroundColor(.secondary))
            }
        }
        .onAppear(perform: loadRoute)
    }

    private func loadRoute() {
        guard coloredSegments.isEmpty else { return }
        isLoading = true
        Task {
            let allLocations = await WorkoutRouteStore.shared.locations(for: workout)
            let displayLocations = sampledLocations(from: allLocations, maxPoints: 180)
            let segments = buildColoredRouteSegments(locations: displayLocations, heartRates: heartRates)

            await MainActor.run {
                self.coloredSegments = segments
                self.isLoading = false
            }
        }
    }
}
