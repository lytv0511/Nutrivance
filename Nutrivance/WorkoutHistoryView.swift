import SwiftUI
import HealthKit
import Charts

struct WorkoutHistoryView: View {
    @StateObject private var engine = HealthStateEngine()
    @State private var expandedWorkout: HKWorkout? = nil
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView("Loading workouts...")
                            .padding()
                    } else if engine.workoutAnalytics.isEmpty {
                        Text("No workouts found.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(engine.workoutAnalytics, id: \.workout.startDate) { pair in
                            WorkoutCard(workout: pair.workout, analytics: pair.analytics, isExpanded: expandedWorkout == pair.workout)
                                .onTapGesture {
                                    withAnimation {
                                        expandedWorkout = expandedWorkout == pair.workout ? nil : pair.workout
                                    }
                                }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Workout History")
            .task {
                isLoading = true
                await engine.refreshWorkoutAnalytics(days: 30)
                isLoading = false
            }
        }
    }
}

struct WorkoutCard: View {
    let workout: HKWorkout
    let analytics: WorkoutAnalytics
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: workout.workoutActivityType.activityTypeSymbol)
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(workout.workoutActivityType.name.capitalized)
                        .font(.headline)
                    Text(workout.startDate, style: .date) + Text(" • ") + Text(workout.startDate, style: .time) + Text(" • \(Int(workout.duration/60)) min")
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
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct WorkoutDetailView: View {
    let analytics: WorkoutAnalytics
    @State private var selectedMETPoint: (Date, Double)? = nil
    @State private var selectedHRPoint: (Date, Double)? = nil
    @State private var selectedPostHRPoint: (Date, Double)? = nil
    @State private var selectedPowerPoint: (Date, Double)? = nil

    var body: some View {
        VStack(spacing: 16) {
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
                Text("Heart Rate During Workout")
                    .font(.subheadline)
                    .bold()
                Chart(analytics.heartRates, id: \.0) { point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("HR", point.1)
                    )
                    .foregroundStyle(.red)
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
                                            selectedHRPoint = (date, hr)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
                            )
                    }
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
        }
        .padding(.top, 8)
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
