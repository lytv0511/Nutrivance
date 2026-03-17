import SwiftUI
import HealthKit

// Inline TappableChartPreview definition
struct TappableChartPreview: View {
    let data: [(Date, Double)]
    let label: String
    let unit: String
    let color: Color
    @State private var showSheet = false
    var body: some View {
        Button {
            showSheet = true
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } label: {
            HealthLineChartPreview(data: data, label: label, unit: unit, color: color)
                .frame(height: 60)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            HealthLineChartSheet(data: data, label: label, unit: unit, color: color)
        }
    }
}

// Main technical view for strain/recovery analytics

struct StrainRecoveryView: View {
    @StateObject private var engine = HealthStateEngine()
    @State private var animationPhase: Double = 0

    enum TimeFilter: String, CaseIterable {
        case week = "1W"
        case month = "1M"
        case year = "1Y"
    }

    @State private var timeFilter: TimeFilter = .week
    @State private var sportFilter: String? = nil // nil means all sports

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Time and Sport Filters
                    HStack {
                        Picker("Time", selection: $timeFilter) {
                            ForEach(TimeFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        Spacer()
                        Menu {
                            Button("All Sports") { sportFilter = nil
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()}
                            ForEach(engine.workoutAnalytics.map { $0.workout.workoutActivityType.name }.unique, id: \.self) { sport in
                                Button(sport.capitalized) { sportFilter = sport
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()}
                            }
                        } label: {
                            HStack {
                                Text(sportFilter?.capitalized ?? "All Sports")
                                Image(systemName: "chevron.down")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)

                    // ML-powered summary (placeholder)
                    Section {
                        Text("\u{1F916} ML-powered summary goes here.\nExplain how your sleep, HRV, RHR, mood, and workouts contributed to your current strain and recovery.")
                            .font(.headline)
                            .padding(.bottom, 8)
                    } header: {
                        Text("AI Coach Summary").font(.title2.bold())
                    }

                    // Strain & Recovery Math
                    StrainRecoveryMathSection(engine: engine)

                    // Sleep & Recovery
                    SleepRecoverySection(engine: engine)

                    // HRV & RHR
                    HRVSection(engine: engine)

                    // Workout Contributions
                    WorkoutContributionsSection(engine: engine)

                    // MET Aggregates
                    METAggregatesSection(engine: engine, timeFilter: timeFilter, sportFilter: sportFilter)

                    // VO2 Aggregates
                    VO2AggregatesSection(engine: engine, timeFilter: timeFilter, sportFilter: sportFilter)

                    // HRR Aggregates
                    HRRAggregatesSection(engine: engine, timeFilter: timeFilter, sportFilter: sportFilter)

                    // Mood & Recovery
                    MoodSection(engine: engine)

                    // Post-Workout HR & VO2 Max
                    PostWorkoutSection(engine: engine)

                    // Training Schedule & Favorite Sport
                    TrainingScheduleSection(engine: engine, sportFilter: sportFilter)

                    // Vitals Table/Graph
                    VitalsSection(engine: engine)
                }
                .padding()
            }
            .background(
                GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Strain vs Recovery")
            .task {
                await engine.refreshWorkoutAnalytics(days: 365) // Load more for year view
            }
        }
    }
}

// MARK: - Technical Sections

import Charts

struct StrainRecoveryMathSection: View {
    @ObservedObject var engine: HealthStateEngine
    var body: some View {
        HealthCard(
            symbol: "flame.fill",
            title: "Strain",
            value: String(Int(engine.strainScore)),
            unit: "/100",
            trend: "ACWR: " + String(format: "%.2f", engine.activityLoad / max(engine.activityLoad / 4, 1)),
            color: Color.orange,
            chartData: engine.timeSeries(for: "effort", days: 28),
            chartLabel: "Effort",
            chartUnit: "pts",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery Score: \(Int(engine.recoveryScore))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Readiness Score: \(Int(engine.readinessScore))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct SleepRecoverySection: View {
    @ObservedObject var engine: HealthStateEngine
    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let stages = engine.sleepStages[today] ?? [:]
        let totalStages = ["core", "deep", "rem", "awake"].compactMap { stages[$0] }.reduce(0, +)
        HealthCard(
            symbol: "bed.double.fill",
            title: "Sleep",
            value: String(format: "%.1f", engine.sleepHours ?? 0),
            unit: "hrs",
            trend: "7d avg: " + String(format: "%.1f", engine.sleepBaseline7Day ?? 0),
            color: .blue,
            chartData: engine.timeSeries(for: "sleep", days: 28),
            chartLabel: "Sleep",
            chartUnit: "hrs",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Consistency: " + String(format: "%.2f", engine.sleepConsistency ?? 0) + "h stddev")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Efficiency: " + String(format: "%.0f%%", (engine.sleepEfficiency[engine.sleepEfficiency.keys.max() ?? Date()] ?? 0) * 100))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if !stages.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(["core", "deep", "rem", "awake"], id: \ .self) { stage in
                                let hours = stages[stage] ?? 0
                                Text("\(stage.capitalized): " + String(format: "%.1f", hours) + "h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("Total: " + String(format: "%.1f", totalStages) + "h (should match main value)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        )
    }
}

struct HRVSection: View {
    @ObservedObject var engine: HealthStateEngine
    var body: some View {
        HealthCard(
            symbol: "waveform.path.ecg",
            title: "HRV",
            value: String(format: "%.0f", engine.latestHRV ?? 0),
            unit: "ms",
            trend: "7d avg: " + String(format: "%.0f", engine.hrvBaseline7Day ?? 0),
            color: .purple,
            chartData: engine.timeSeries(for: "hrv", days: 28),
            chartLabel: "HRV",
            chartUnit: "ms",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current HRV is your most recent SDNN measurement. 7d avg is the rolling average.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("RHR: " + String(format: "%.0f", engine.restingHeartRate ?? 0) + " bpm")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("RHR 7d avg: " + String(format: "%.0f", engine.rhrBaseline7Day ?? 0))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TappableChartPreview(data: engine.timeSeries(for: "rhr", days: 28), label: "RHR", unit: "bpm", color: .red)
                }
            }
        )
    }
}

struct WorkoutContributionsSection: View {
    @ObservedObject var engine: HealthStateEngine
    var body: some View {
        HealthCard(
            symbol: "figure.strengthtraining.traditional",
            title: "Workouts",
            value: String(format: "%.0f", engine.activityLoad),
            unit: "load",
            trend: "Effort 7d avg",
            color: .green,
            chartData: engine.timeSeries(for: "effort", days: 28),
            chartLabel: "Effort",
            chartUnit: "pts",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Training Load is a composite score based on effort, duration, and intensity. Higher is more strenuous.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Kcal Burned (28d)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TappableChartPreview(data: engine.timeSeries(for: "kcal", days: 28), label: "Kcal", unit: "kcal", color: .orange)
                    if let latestDate = engine.heartRateZones.keys.max(), let zones = engine.heartRateZones[latestDate] {
                        HStack(spacing: 12) {
                            ForEach(zones.sorted(by: { $0.key < $1.key }), id: \ .key) { zone, min in
                                Text("\(zone): " + String(format: "%.0f", min) + " min")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        )
    }
}

struct MoodSection: View {
    @ObservedObject var engine: HealthStateEngine
    var body: some View {
        HealthCard(
            symbol: "face.smiling",
            title: "Mood",
            value: String(format: "%.0f", engine.moodScore),
            unit: "/100",
            trend: "7d avg: " + String(format: "%.0f", engine.moodBaseline7Day ?? 0),
            color: .yellow,
            chartData: engine.timeSeries(for: "mood", days: 28),
            chartLabel: "Mood",
            chartUnit: "pts",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mood trend and notes coming soon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct PostWorkoutSection: View {
    @ObservedObject var engine: HealthStateEngine
    var body: some View {
        let latestDate = engine.postWorkoutHR.keys.max()
        let latestHR = latestDate.flatMap { engine.postWorkoutHR[$0] }
        let latestVO2Date = engine.vo2Max.keys.max()
        let latestVO2 = latestVO2Date.flatMap { engine.vo2Max[$0] }

        let hrWarning: String? = {
            guard let hr = latestHR else { return "No recent post-workout HR data." }
            if hr < 40 || hr > 120 {
                return "Unusual post-workout HR detected. Please check your device or consult a physician."
            }
            return nil
        }()

        let vo2Warning: String? = {
            guard let vo2 = latestVO2 else { return "No recent VO2 max data." }
            if vo2 < 20 || vo2 > 70 {
                return "VO2 max value is outside typical range."
            }
            return nil
        }()

//        HealthCard(
//            symbol: "heart.fill",
//            title: "Post-Workout HR",
//            value: latestHR.map { String(format: "%.0f", $0) } ?? "-",
//            unit: "bpm",
//            trend: "VO2 Max: " + (latestVO2.map { String(format: "%.1f", $0) } ?? "-") + " ml/kg/min",
//            color: .red,
//            chartData: engine.timeSeries(for: "postworkouthr", days: 28),
//            chartLabel: "Post-Workout HR",
//            chartUnit: "bpm",
//            expandedContent: {
//                VStack(alignment: .leading, spacing: 8) {
//                    if let hrWarning { Text(hrWarning).foregroundColor(.red).font(.caption) }
//                    if let vo2Warning { Text(vo2Warning).foregroundColor(.orange).font(.caption) }
//                    if let hr = latestHR, let vo2 = latestVO2 {
//                        if hr > 100 {
//                            Text("Elevated post-workout HR. Consider a longer cool-down or monitor for overtraining.")
//                                .foregroundColor(.orange)
//                                .font(.caption2)
//                        }
//                        if vo2 < 30 {
//                            Text("VO2 max is below average for most adults. Improving aerobic fitness may help.")
//                                .foregroundColor(.orange)
//                                .font(.caption2)
//                        }
//                    }
//                    Divider().padding(.vertical, 2)
//                    Text("VO2 Max (28d)")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary)
//                    TappableChartPreview(data: engine.timeSeries(for: "vo2max", days: 28), label: "VO2 Max", unit: "ml/kg/min", color: .blue)
//                    Text("VO2 max is estimated using workout HR and sport-specific formulas. If a more accurate method is available for your sport, it will be used.")
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
//                }
//            }
//        )
    }
}

struct TrainingScheduleSection: View {
    @ObservedObject var engine: HealthStateEngine
    let sportFilter: String?

    var filteredWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        
        return engine.workoutAnalytics.filter { workout, _ in
            let isInRange = workout.startDate >= startDate && workout.startDate <= endDate
            let matchesSport = sportFilter == nil || workout.workoutActivityType.name == sportFilter
            return isInRange && matchesSport
        }
    }

    var minutesPerDay: [(Date, Double)] {
        let calendar = Calendar.current
        var minutes: [Date: Double] = [:]
        
        for (workout, _) in filteredWorkouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let duration = workout.duration / 60.0 // convert to minutes
            minutes[day, default: 0] += duration
        }
        
        return minutes.sorted { $0.0 < $1.0 }
    }

    var frequency: Double {
        return Double(filteredWorkouts.count)
    }

    var body: some View {
        let totalMinutes = minutesPerDay.map { $0.1 }.reduce(0, +)
        
        HealthCard(
            symbol: "calendar",
            title: "Training Schedule",
            value: String(format: "%.1f", frequency),
            unit: "sessions/week",
            trend: "Favorite: " + (engine.favoriteSport ?? "-"),
            color: .teal,
            chartData: minutesPerDay,
            chartLabel: "Minutes",
            chartUnit: "min",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter: " + (sportFilter?.capitalized ?? "All Sports"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("7-day frequency: " + String(format: "%.0f", frequency) + " sessions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Total minutes (7d): " + String(format: "%.0f", totalMinutes))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Overall favorite sport: " + (engine.favoriteSport ?? "-"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct VitalsSection: View {
    @ObservedObject var engine: HealthStateEngine
    @State private var isLoading = true
    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let respCurrent = engine.respiratoryRate[today] ?? 0
        let resp7dAvg = engine.vitalsSummary["RespiratoryRate"]?.baseline ?? 0
        let spo2Current = engine.spO2[today] ?? 0
        let spo27dAvg = engine.vitalsSummary["SpO2"]?.baseline ?? 0
        let respArray = engine.timeSeries(for: "respiratoryrate", days: 28)
        let tempArray = engine.timeSeries(for: "wristtemp", days: 28)
        let spo2Array = engine.timeSeries(for: "spo2", days: 28)
        let hasData = !respArray.isEmpty || !tempArray.isEmpty || !spo2Array.isEmpty
        VStack {
            if isLoading && !hasData {
                ProgressView("Loading vitals...")
                    .onAppear {
                        // Force refresh in case data is not loaded
                        engine.refreshAllMetrics()
                        // Simulate loading delay for demo; in production, observe data changes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isLoading = false
                        }
                    }
            } else {
                HealthCard(
                    symbol: "lungs.fill",
                    title: "Respiratory Rate",
                    value: String(format: "%.1f", respCurrent),
                    unit: "bpm",
                    trend: "7d avg: " + String(format: "%.1f", resp7dAvg),
                    color: .indigo,
                    chartData: respArray,
                    chartLabel: "Respiratory Rate",
                    chartUnit: "bpm"
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        if respArray.isEmpty {
                            Text("No respiratory rate data available.")
                                .foregroundColor(.red)
                        }
                        Text("Wrist Temp (28d)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if tempArray.isEmpty {
                            Text("No wrist temperature data available.")
                                .foregroundColor(.red)
                        }
                        TappableChartPreview(data: tempArray, label: "Wrist Temp", unit: "°C", color: .pink)
//                            .frame(height: 60)
                        Text("SpO₂ (28d)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Current: " + String(format: "%.1f", spo2Current) + "% | 7d avg: " + String(format: "%.1f", spo27dAvg) + "%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if spo2Array.isEmpty {
                            Text("No SpO₂ data available.")
                                .foregroundColor(.red)
                        }
                        TappableChartPreview(data: spo2Array, label: "SpO₂", unit: "%", color: .mint)
//                            .frame(height: 60)
                        Divider().padding(.vertical, 2)
                        ForEach(engine.vitalsSummary.sorted(by: { $0.key < $1.key }), id: \ .key) { key, val in
                            HStack {
                                Text("\(key):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Current: \(val.current.map { String(format: "%.1f", $0) } ?? "-")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("7d Avg: \(val.baseline.map { String(format: "%.1f", $0) } ?? "-")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Simple Line Graph (placeholder)
struct MetricLineGraph: View {
    let title: String
    let data: [(Date, Double)]
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption.bold())
            if data.isEmpty {
                Text("No data").foregroundColor(.secondary)
            } else {
                GeometryReader { geo in
                    let maxVal = data.map { $0.1 }.max() ?? 1
                    let minVal = data.map { $0.1 }.min() ?? 0
                    let points = data.enumerated().map { (i, pair) in
                        CGPoint(
                            x: geo.size.width * CGFloat(i) / CGFloat(max(data.count-1,1)),
                            y: geo.size.height * CGFloat(1 - (pair.1 - minVal) / max(0.01, maxVal - minVal))
                        )
                    }
                    Path { path in
                        if let first = points.first {
                            path.move(to: first)
                            for pt in points.dropFirst() { path.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.accentColor, lineWidth: 2)
                }
                .frame(height: 60)
            }
        }
        .padding(.vertical, 4)
    }
}

struct METAggregatesSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?

    var filteredData: [(Date, Double)] {
        let base = engine.dailyMETAggregates
        let filtered = base.filter { date, _ in
            // Apply time filter
            let days: Int
            switch timeFilter {
            case .week: days = 7
            case .month: days = 30
            case .year: days = 365
            }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return date >= cutoff
        }
        return filtered.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        HealthCard(
            symbol: "flame.fill",
            title: "Daily MET-minutes",
            value: filteredData.last.map { String(format: "%.1f", $0.1) } ?? "-",
            unit: "MET-min",
            trend: "Total: \(String(format: "%.1f", filteredData.map { $0.1 }.reduce(0, +)))",
            color: .orange,
            chartData: filteredData,
            chartLabel: "MET-min",
            chartUnit: "min",
            expandedContent: { EmptyView() }
        )
    }
}

struct VO2AggregatesSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?

    var filteredData: [(Date, Double)] {
        var base = engine.dailyVO2Aggregates
        if let sport = sportFilter {
            // Filter workouts by sport and recompute aggregates
            let filteredWorkouts = engine.workoutAnalytics.filter { $0.workout.workoutActivityType.name == sport }
            var aggregates: [Date: [Double]] = [:]
            let calendar = Calendar.current
            for (workout, analytics) in filteredWorkouts {
                let day = calendar.startOfDay(for: workout.startDate)
                if let vo2 = analytics.vo2Max {
                    aggregates[day, default: []].append(vo2)
                }
            }
            base = aggregates.mapValues { $0.reduce(0, +) / Double($0.count) }
        }
        let filtered = base.filter { date, _ in
            let days: Int
            switch timeFilter {
            case .week: days = 7
            case .month: days = 30
            case .year: days = 365
            }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return date >= cutoff
        }
        return filtered.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        HealthCard(
            symbol: "lungs.fill",
            title: "Daily VO2 Max",
            value: filteredData.last.map { String(format: "%.1f", $0.1) } ?? "-",
            unit: "ml/kg/min",
            trend: "Avg: \(filteredData.map { $0.1 }.average?.formatted() ?? "-")",
            color: .blue,
            chartData: filteredData,
            chartLabel: "VO2 Max",
            chartUnit: "ml/kg/min",
            expandedContent: { EmptyView() }
        )
    }
}

struct HRRAggregatesSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?

    var filteredData: [(Date, Double)] {
        var base = engine.dailyHRRAggregates
        if let sport = sportFilter {
            // Filter workouts by sport and recompute aggregates
            let filteredWorkouts = engine.workoutAnalytics.filter { $0.workout.workoutActivityType.name == sport }
            var aggregates: [Date: Double] = [:]
            let calendar = Calendar.current
            for (workout, analytics) in filteredWorkouts {
                let day = calendar.startOfDay(for: workout.startDate)
                if let hrr2 = analytics.hrr2 {
                    aggregates[day] = max(aggregates[day] ?? 0, hrr2)
                }
            }
            base = aggregates
        }
        let filtered = base.filter { date, _ in
            let days: Int
            switch timeFilter {
            case .week: days = 7
            case .month: days = 30
            case .year: days = 365
            }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return date >= cutoff
        }
        return filtered.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        HealthCard(
            symbol: "heart.fill",
            title: "Daily HRR (2min)",
            value: filteredData.last.map { String(format: "%.0f", $0.1) } ?? "-",
            unit: "bpm",
            trend: "Max: \(filteredData.map { $0.1 }.max()?.formatted() ?? "-")",
            color: .red,
            chartData: filteredData,
            chartLabel: "HRR",
            chartUnit: "bpm",
            expandedContent: { EmptyView() }
        )
    }
}

extension Array where Element: Hashable {
    var unique: [Element] {
        Array(Set(self))
    }
}
