import SwiftUI
import HealthKit
import Charts
import MapKit

struct WorkoutHistoryView: View {
    @StateObject private var engine = HealthStateEngine()
    @State private var expandedWorkout: HKWorkout? = nil
    @State private var isLoading = false
    @State private var animationPhase: Double = 0
    @State private var sportFilter: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var scrollProxy: ScrollViewProxy?

    var filteredWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        engine.workoutAnalytics.filter { sportFilter == nil || $0.workout.workoutActivityType.name == sportFilter }
    }

    var uniqueSports: [String] {
        engine.workoutAnalytics.map { $0.workout.workoutActivityType.name }.unique
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
                                        WorkoutCard(workout: pair.workout, analytics: pair.analytics, isExpanded: expandedWorkout == pair.workout)
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
                    HStack {
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
            .task {
                isLoading = true
                await engine.refreshWorkoutAnalytics(days: 3650) // Load all workouts (10 years)
                isLoading = false
            }
            .background(
               GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                   .onAppear {
                       withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                           animationPhase = 20
                       }
                   }
           )
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
                WorkoutDetailView(analytics: analytics)
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

private struct HRZone {
    let name: String
    let color: Color
    var time: TimeInterval
    let range: ClosedRange<Double>
}

struct WorkoutDetailView: View {
    let analytics: WorkoutAnalytics

    @State private var selectedMETPoint: (Date, Double)? = nil
    @State private var selectedHRPoint: (Date, Double)? = nil
    @State private var selectedPostHRPoint: (Date, Double)? = nil
    @State private var selectedPowerPoint: (Date, Double)? = nil

    @State private var showHRZones = false
    @State private var routePoints: [RoutePoint] = []
    @State private var isLoadingRoute = false
    @State private var avgCadence: Double? = nil
    @State private var isLoadingCadence = false

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
                if let power = avgPower {
                    WorkoutMetricCard(title: "Avg Power", value: String(format: "%.0f", power), unit: "W", icon: "bolt.fill", color: .purple)
                }
                if let cadence = avgCadence {
                    WorkoutMetricCard(title: "Avg Cadence", value: String(format: "%.0f", cadence), unit: "rpm", icon: "waveform.path.ecg", color: .mint)
                }
                if let hr = avgHeartRate {
                    WorkoutMetricCard(title: "Avg HR", value: String(format: "%.0f", hr), unit: "bpm", icon: "heart.fill", color: .red)
                }
                if let pause = pausedDuration {
                    WorkoutMetricCard(title: "Paused", value: formattedTime(pause), unit: "", icon: "pause.fill", color: .gray)
                }
            }

            // MET Time Series
            VStack(alignment: .leading) {
                Text("MET Time Series")
                    .font(.subheadline)
                    .bold()
                Chart(analytics.metSeries, id: \.0) { point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("MET", point.1)
                    )
                    .foregroundStyle(.green)
                }
                .frame(height: 150)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let location = value.location
                                        if let date = proxy.value(atX: location.x, as: Date.self),
                                           let met = proxy.value(atY: location.y, as: Double.self) {
                                            selectedMETPoint = (date, met)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
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
                    if let selected = selectedHRPoint {
                        PointMark(
                            x: .value("Time", selected.0),
                            y: .value("HR", selected.1)
                        )
                        .symbolSize(120)
                        .foregroundStyle(.yellow)
                    }
                }
                .frame(height: 180)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let location = value.location
                                        if let date = proxy.value(atX: location.x, as: Date.self),
                                           let hr = proxy.value(atY: location.y, as: Double.self) {
                                            selectedHRPoint = (date, hr)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
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
                Chart(analytics.postWorkoutHRSeries, id: \.0) { point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("HR", point.1)
                    )
                    .foregroundStyle(.orange)
                    if let peak = analytics.peakHR {
                        RuleMark(y: .value("Peak HR", peak))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                }
                .frame(height: 150)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let location = value.location
                                        if let date = proxy.value(atX: location.x, as: Date.self),
                                           let hr = proxy.value(atY: location.y, as: Double.self) {
                                            selectedPostHRPoint = (date, hr)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
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
                    Chart(analytics.powerSeries, id: \.0) { point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("Power", point.1)
                        )
                        .foregroundStyle(.purple)
                    }
                    .frame(height: 150)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            let location = value.location
                                            if let date = proxy.value(atX: location.x, as: Date.self),
                                               let power = proxy.value(atY: location.y, as: Double.self) {
                                                selectedPowerPoint = (date, power)
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                        }
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

            // Route map (if available)
            if !routePoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Route")
                        .font(.subheadline)
                        .bold()
                    Map(
                        coordinateRegion: .constant(MKCoordinateRegion(
                            center: routePoints.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        )),
                        interactionModes: [.pan, .zoom],
                        showsUserLocation: false,
                        annotationItems: routePoints
                    ) { point in
                        MapMarker(coordinate: point.coordinate, tint: .orange)
                    }
                    .frame(height: 200)
                    .cornerRadius(12)
                }
            }
        }
        .padding(.top, 8)
        .onAppear {
            loadRoute()
            loadCadence()
        }
    }

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

    private var avgHeartRate: Double? {
        let hr = analytics.heartRates.map { $0.1 }
        guard !hr.isEmpty else { return nil }
        return hr.reduce(0, +) / Double(hr.count)
    }

    private var maxHeartRate: Double? {
        analytics.heartRates.map { $0.1 }.max()
    }

    private var heartRateZoneThresholds: [Double] {
        // Using approximate % of avg recorded max HR (or 190 if unknown)
        let maxHR = maxHeartRate ?? 190
        return [0.6, 0.7, 0.8, 0.9, 1.0].map { $0 * maxHR }
    }

    private var heartRateZoneBreakdown: [HRZone] {
        let thresholds = heartRateZoneThresholds
        var zones = [
            HRZone(name: "Zone 1", color: .blue, time: 0.0, range: 0.0...thresholds[0]),
            HRZone(name: "Zone 2", color: .cyan, time: 0.0, range: thresholds[0]...thresholds[1]),
            HRZone(name: "Zone 3", color: .green, time: 0.0, range: thresholds[1]...thresholds[2]),
            HRZone(name: "Zone 4", color: .orange, time: 0.0, range: thresholds[2]...thresholds[3]),
            HRZone(name: "Zone 5", color: .red, time: 0.0, range: thresholds[3]...thresholds[4])
        ]

        let samples = analytics.heartRates.sorted { $0.0 < $1.0 }
        for i in 0..<(samples.count - 1) {
            let hr = samples[i].1
            let next = samples[i + 1].0
            let duration = next.timeIntervalSince(samples[i].0)
            if let idx = zones.firstIndex(where: { $0.range.contains(hr) }) {
                zones[idx].time += duration
            }
        }
        return zones
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

    private func loadCadence() {
        guard avgCadence == nil else { return }
        isLoadingCadence = true
        let healthStore = HKHealthStore()
        guard let cadenceType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence) else {
            isLoadingCadence = false
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: analytics.workout.startDate, end: analytics.workout.endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: cadenceType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let values = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())) } ?? []
            let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            DispatchQueue.main.async {
                self.avgCadence = avg
                self.isLoadingCadence = false
            }
        }
        healthStore.execute(query)
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
