import SwiftUI
import HealthKit
import Charts
import MapKit

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
        ubiquitousStore.synchronize()

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
        ubiquitousStore.synchronize()
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

struct WorkoutHistoryView: View {
    @ObservedObject var engine = HealthStateEngine.shared
    @State private var expandedWorkout: HKWorkout? = nil
    @State private var isLoading = false
    @State private var animationPhase: Double = 0
    @State private var sportFilter: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var scrollProxy: ScrollViewProxy?
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

    init() {
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
                                Section(header: Text("\(Calendar.current.monthSymbols[key.month! - 1]) \(String(format: "%d", key.year!))").font(.headline).foregroundColor(.orange)) {
                                    ForEach(workouts.sorted(by: { $0.workout.startDate > $1.workout.startDate }), id: \.workout.startDate) { pair in
                                        WorkoutCard(
                                            workout: pair.workout,
                                            analytics: pair.analytics,
                                            isExpanded: expandedWorkout == pair.workout,
                                            hrZoneSettings: hrZoneSettings
                                        )
                                            .id(pair.workout.startDate)
                                            .onTapGesture {
                                                withAnimation {
                                                    expandedWorkout = expandedWorkout == pair.workout ? nil : pair.workout
                                                }
                                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                                impact.impactOccurred()
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .onAppear { scrollProxy = proxy }
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
                        scrollToClosestWorkout(to: selectedDate)
                        showDatePicker = false
                    }
                    .padding()
                    .foregroundColor(.orange)
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
        }
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

    func scrollToClosestWorkout(to date: Date) {
        let closest = filteredWorkouts.min(by: { abs($0.workout.startDate.timeIntervalSince(date)) < abs($1.workout.startDate.timeIntervalSince(date)) })
        if let closest = closest {
            withAnimation {
                scrollProxy?.scrollTo(closest.workout.startDate, anchor: .top)
            }
        }
    }
}

struct WorkoutCard: View {
    let workout: HKWorkout
    let analytics: WorkoutAnalytics
    let isExpanded: Bool
    let hrZoneSettings: HRZoneUserSettings

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            if isExpanded {
                WorkoutDetailView(analytics: analytics, hrZoneSettings: hrZoneSettings)
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

struct WorkoutDetailView: View {
    let analytics: WorkoutAnalytics
    let hrZoneSettings: HRZoneUserSettings

    @StateObject private var healthKitManager = HealthKitManager()
    @State private var selectedMETPoint: (Date, Double)? = nil
    @State private var selectedHRPoint: (Date, Double)? = nil
    @State private var selectedPostHRPoint: (Date, Double)? = nil
    @State private var selectedPowerPoint: (Date, Double)? = nil
    @State private var selectedCadencePoint: (Date, Double)? = nil
    @State private var selectedPacePoint: (Date, Double)? = nil

    @State private var showHRZones = false
    @State private var routePoints: [RoutePoint] = []
    @State private var isLoadingRoute = false
    @State private var historicalZoneProfile: HRZoneProfile? = nil
    @State private var historicalMaxHR: Double? = nil
    @State private var historicalRestingHR: Double? = nil
    @State private var hasResolvedZoneProfile = false

    private var activeDuration: TimeInterval {
        analytics.workout.duration
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

    private func nearestPoint(in data: [(Date, Double)], to date: Date) -> (Date, Double)? {
        data.min { lhs, rhs in
            abs(lhs.0.timeIntervalSince(date)) < abs(rhs.0.timeIntervalSince(date))
        }
    }

    private func pointSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        data: [(Date, Double)]
    ) -> (Date, Double)? {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard plotFrame.contains(location) else { return nil }

        let xPosition = location.x - plotFrame.origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return nil }
        return nearestPoint(in: data, to: date)
    }

    private func updateSelection(
        from location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        data: [(Date, Double)],
        selection: Binding<(Date, Double)?>
    ) {
        guard let point = pointSelection(at: location, proxy: proxy, geometry: geometry, data: data) else {
            selection.wrappedValue = nil
            return
        }
        if selection.wrappedValue?.0 != point.0 || selection.wrappedValue?.1 != point.1 {
            selection.wrappedValue = point
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @ViewBuilder
    private func selectionOverlay(
        proxy: ChartProxy,
        geometry: GeometryProxy,
        data: [(Date, Double)],
        selection: Binding<(Date, Double)?>
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSelection(
                            from: value.location,
                            proxy: proxy,
                            geometry: geometry,
                            data: data,
                            selection: selection
                        )
                    }
                    .onEnded { value in
                        updateSelection(
                            from: value.location,
                            proxy: proxy,
                            geometry: geometry,
                            data: data,
                            selection: selection
                        )
                        selection.wrappedValue = nil
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateSelection(
                        from: location,
                        proxy: proxy,
                        geometry: geometry,
                        data: data,
                        selection: selection
                    )
                case .ended:
                    selection.wrappedValue = nil
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
                .annotation(position: .top, spacing: 8) {
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

            PointMark(
                x: .value(xLabel, selected.0),
                y: .value(yLabel, selected.1)
            )
            .symbolSize(90)
            .foregroundStyle(color)
        }
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
        VStack(alignment: .leading, spacing: 16) {
            // High-level metrics
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                if let dist = distanceMeters {
                    WorkoutMetricCard(title: "Distance", value: String(format: "%.2f", dist / 1000), unit: "km", icon: "ruler", color: .blue)
                }
                if let spd = avgSpeedKPH {
                    WorkoutMetricCard(title: "Avg Speed", value: String(format: "%.1f", spd), unit: "km/h", icon: "speedometer", color: .teal)
                }
                if (analytics.workout.workoutActivityType == .running || analytics.workout.workoutActivityType == .hiking || analytics.workout.workoutActivityType == .walking), let spd = avgSpeedKPH, spd > 0 {
                    let pace = 60 / spd
                    WorkoutMetricCard(title: "Avg Pace", value: String(format: "%.1f", pace), unit: "min/km", icon: "stopwatch", color: .blue)
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
                    WorkoutMetricCard(title: "Elevation Gain", value: String(format: "%.0f", elevation), unit: "m", icon: "mountain.2.fill", color: .green)
                }
                if let hr = avgHeartRate {
                    WorkoutMetricCard(title: "Avg HR", value: String(format: "%.0f", hr), unit: "bpm", icon: "heart.fill", color: .red)
                }
                if let pause = pausedDuration {
                    WorkoutMetricCard(title: "Paused", value: formattedTime(pause), unit: "", icon: "pause.fill", color: .gray)
                }
                if let vo = analytics.verticalOscillation {
                    WorkoutMetricCard(title: "Vert Osc", value: String(format: "%.1f", vo), unit: "cm", icon: "waveform", color: .cyan)
                }
                if let gct = analytics.groundContactTime {
                    WorkoutMetricCard(title: "GCT", value: String(format: "%.0f", gct), unit: "ms", icon: "figure.run", color: .indigo)
                }
                if let sl = analytics.strideLength {
                    WorkoutMetricCard(title: "Stride", value: String(format: "%.2f", sl), unit: "m", icon: "ruler.fill", color: .pink)
                }
            }

            // HR Zone Profile Information
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
                .frame(height: 150)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.metSeries,
                            selection: $selectedMETPoint
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
                    let selectedZone = showHRZones ? selectedHRPoint.flatMap { zoneForHeartRate($0.1) } : nil
                    selectionMarks(
                        selected: selectedHRPoint,
                        xLabel: "Time",
                        yLabel: "HR",
                        color: selectedZone?.color ?? .red,
                        secondaryText: selectedZone?.name,
                        valueText: { "\(Int($0)) bpm" }
                    )
                }
                .frame(height: 180)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.heartRates,
                            selection: $selectedHRPoint
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
                                        Text("\(zone.name) \(formattedTime(zone.time)) < \(Int(zone.range.upperBound)) BPM")
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
                .frame(height: 150)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        selectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            data: analytics.postWorkoutHRSeries,
                            selection: $selectedPostHRPoint
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
            if analytics.workout.workoutActivityType == .cycling && !analytics.powerSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Cycling Power")
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
                    .frame(height: 150)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: analytics.powerSeries,
                                selection: $selectedPowerPoint
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
            if analytics.workout.workoutActivityType == .cycling && !analytics.speedSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Cycling Speed")
                        .font(.subheadline)
                        .bold()
                    Chart(analytics.speedSeries, id: \.0) { point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("Speed", point.1 * 3.6) // m/s to km/h
                        )
                        .foregroundStyle(.blue)
                    }
                    .frame(height: 150)
                    HStack {
                        let avgSpeed = analytics.speedSeries.map { $0.1 * 3.6 }.average
                        Text("Avg Speed: \(avgSpeed.map { String(format: "%.1f", $0) } ?? "-") km/h")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Cycling Cadence if applicable
            if analytics.workout.workoutActivityType == .cycling && !analytics.cadenceSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Cycling Cadence")
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
                    .frame(height: 150)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: analytics.cadenceSeries,
                                selection: $selectedCadencePoint
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
                    Chart(analytics.elevationSeries, id: \.0) { point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("Elevation", point.1)
                        )
                        .foregroundStyle(.green)
                    }
                    .frame(height: 150)
                    HStack {
                        if let gain = analytics.elevationGain {
                            Text("Total Gain: \(String(format: "%.0f", gain)) m")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Pace for running/hiking
            if (analytics.workout.workoutActivityType == .running || analytics.workout.workoutActivityType == .hiking || analytics.workout.workoutActivityType == .walking) && !analytics.speedSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Pace")
                        .font(.subheadline)
                        .bold()
                    Chart {
                        ForEach(analytics.speedSeries, id: \.0) { point in
                            let paceMinKm = 60 / (point.1 * 3.6) // min/km
                            BarMark(
                                x: .value("Time", point.0),
                                y: .value("Pace", paceMinKm)
                            )
                            .foregroundStyle(.teal)
                        }
                        selectionMarks(
                            selected: selectedPacePoint,
                            xLabel: "Time",
                            yLabel: "Pace",
                            color: .teal,
                            valueText: { String(format: "%.2f min/km", $0) }
                        )
                    }
                    .frame(height: 150)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            let paceSeries = analytics.speedSeries.map { point in
                                (point.0, 60 / (point.1 * 3.6))
                            }
                            selectionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                data: paceSeries,
                                selection: $selectedPacePoint
                            )
                        }
                    }
                    HStack {
                        let avgPace = analytics.speedSeries.map { 60 / ($0.1 * 3.6) }.average
                        Text("Avg Pace: \(avgPace.map { String(format: "%.1f", $0) } ?? "-") min/km")
                        if let point = selectedPacePoint {
                            Text("Selected: \(point.0, style: .time) - \(String(format: "%.2f", point.1)) min/km")
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
                            Text(String(format: "%.1f km", split.distance))
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)
                            Text(formattedTime(split.time))
                                .font(.caption)
                            if let pace = split.pace {
                                Text(String(format: "%.1f min/km", pace))
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
            loadRoute()
        }
        .task(id: analytics.workout.startDate) {
            await loadHistoricalZoneProfile()
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

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        } else {
            return String(format: "%02dm %02ds", m, s)
        }
    }

    private func loadRoute() {
        guard routePoints.isEmpty else { return }
        guard analytics.workout.workoutActivityType == .running || analytics.workout.workoutActivityType == .cycling || analytics.workout.workoutActivityType == .walking || analytics.workout.workoutActivityType == .hiking else { return }
        isLoadingRoute = true

        let healthStore = HKHealthStore()
        let predicate = HKQuery.predicateForObjects(from: analytics.workout)
        let routeType = HKSeriesType.workoutRoute()

        let sampleQuery = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            guard error == nil, let routes = samples as? [HKWorkoutRoute], let route = routes.first else {
                DispatchQueue.main.async { isLoadingRoute = false }
                return
            }

            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                guard error == nil else {
                    DispatchQueue.main.async { isLoadingRoute = false }
                    return
                }
                if done, let locations = locations {
                    let points = locations.map { RoutePoint(coordinate: $0.coordinate) }
                    DispatchQueue.main.async {
                        self.routePoints = points
                        self.isLoadingRoute = false
                    }
                }
            }
            healthStore.execute(routeQuery)
        }

        healthStore.execute(sampleQuery)
    }

    private func generateSplits() -> [Split] {
        guard let totalDistance = analytics.workout.totalDistance?.doubleValue(for: .meter()) else { return [] }
        let totalKm = totalDistance / 1000
        let splitDistance = 1.0 // km
        var splits: [Split] = []
        for km in stride(from: splitDistance, through: totalKm, by: splitDistance) {
            let timeAtKm = analytics.workout.startDate.addingTimeInterval((km / totalKm) * analytics.workout.duration)
            let time = timeAtKm.timeIntervalSince(analytics.workout.startDate)
            let pace = analytics.speedSeries.isEmpty ? nil : 60 / (analytics.speedSeries.map { $0.1 * 3.6 }.average ?? 0)
            let hrSamplesInSplit = analytics.heartRates.filter { $0.0 <= timeAtKm }
            let avgHR = hrSamplesInSplit.isEmpty ? nil : hrSamplesInSplit.map { $0.1 }.average
            splits.append(Split(distance: km, time: time, pace: pace, avgHR: avgHR))
        }
        return splits
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
