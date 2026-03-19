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
//                .frame(height: 60)
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
    @State private var selectedDate = Date()

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
                    StrainRecoveryMathSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        anchorDate: selectedDate
                    )

                    // Sleep & Recovery
                    SleepRecoverySection(
                        engine: engine,
                        timeFilter: timeFilter,
                        anchorDate: selectedDate
                    )

                    // HRV & RHR
                    HRVSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        anchorDate: selectedDate
                    )

                    // Workout Contributions
                    WorkoutContributionsSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        anchorDate: selectedDate,
                        sportFilter: sportFilter
                    )

                    // MET Aggregates
                    METAggregatesSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        sportFilter: sportFilter,
                        anchorDate: selectedDate
                    )

                    // VO2 Aggregates
                    VO2AggregatesSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        sportFilter: sportFilter,
                        anchorDate: selectedDate
                    )

                    // HRR Aggregates
                    HRRAggregatesSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        sportFilter: sportFilter,
                        anchorDate: selectedDate
                    )

                    // Mood & Recovery
                    MoodSection(engine: engine)

                    // Post-Workout HR & VO2 Max
                    PostWorkoutSection(engine: engine)

                    // Training Schedule & Favorite Sport
                    TrainingScheduleSection(
                        engine: engine,
                        sportFilter: sportFilter,
                        timeFilter: timeFilter,
                        anchorDate: selectedDate
                    )

                    // Vitals Table/Graph
                    VitalsSection(
                        engine: engine,
                        timeFilter: timeFilter,
                        anchorDate: selectedDate
                    )
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker(
                        "Reference Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
            }
            .task {
                await engine.refreshWorkoutAnalytics(days: 365) // Load more for year view
            }
        }
    }
}

// MARK: - Technical Sections

import Charts

private extension StrainRecoveryView.TimeFilter {
    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
}

private func chartWindow(
    for timeFilter: StrainRecoveryView.TimeFilter,
    anchorDate: Date
) -> (start: Date, end: Date, endExclusive: Date) {
    let calendar = Calendar.current
    let end = calendar.startOfDay(for: anchorDate)
    let start = calendar.date(byAdding: .day, value: -(timeFilter.dayCount - 1), to: end) ?? end
    let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    return (start, end, endExclusive)
}

private func filteredDailyValues(
    _ values: [Date: Double],
    timeFilter: StrainRecoveryView.TimeFilter,
    anchorDate: Date
) -> [(Date, Double)] {
    let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
    
    return values
        .filter { date, _ in
            date >= window.start && date <= window.end
        }
        .sorted { $0.0 < $1.0 }
}

private func dateSequence(from start: Date, to end: Date) -> [Date] {
    let calendar = Calendar.current
    let safeStart = calendar.startOfDay(for: start)
    let safeEnd = calendar.startOfDay(for: end)
    guard safeStart <= safeEnd else { return [] }
    
    let dayCount = (calendar.dateComponents([.day], from: safeStart, to: safeEnd).day ?? 0) + 1
    return (0..<dayCount).compactMap {
        calendar.date(byAdding: .day, value: $0, to: safeStart)
    }
}

private func average(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
}

struct StrainRecoveryMathSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var effortData: [(Date, Double)] {
        filteredDailyValues(engine.effortRating, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    private var totalLoad: Double {
        effortData.map(\.1).reduce(0, +)
    }
    
    private var averageLoad: Double {
        average(effortData.map(\.1)) ?? 0
    }
    
    private var strainValue: Double {
        min(100, averageLoad * 10)
    }
    
    var body: some View {
        HealthCard(
            symbol: "flame.fill",
            title: "Strain",
            value: String(Int(strainValue)),
            unit: "/100",
            trend: "\(timeFilter.rawValue) load: " + String(format: "%.1f", totalLoad),
            color: Color.orange,
            chartData: effortData,
            chartLabel: "Effort",
            chartUnit: "pts",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(timeFilter.rawValue) average effort: " + String(format: "%.1f", averageLoad))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var sleepData: [(Date, Double)] {
        let totals = engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem"].compactMap { stages[$0] }.reduce(0, +)
        }
        return filteredDailyValues(totals, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    private var selectedDay: Date {
        Calendar.current.startOfDay(for: anchorDate)
    }
    
    private var activeDay: Date {
        sleepData.last?.0 ?? selectedDay
    }
    
    var body: some View {
        let stages = engine.sleepStages[activeDay] ?? [:]
        let totalStages = ["core", "deep", "rem", "awake"].compactMap { stages[$0] }.reduce(0, +)
        let latestSleep = sleepData.last?.1 ?? 0
        let averageSleep = average(sleepData.map(\.1)) ?? 0
        let efficiency = (engine.sleepEfficiency[activeDay] ?? 0) * 100
        HealthCard(
            symbol: "bed.double.fill",
            title: "Sleep",
            value: String(format: "%.1f", latestSleep),
            unit: "hrs",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.1f", averageSleep),
            color: .blue,
            chartData: sleepData,
            chartLabel: "Sleep",
            chartUnit: "hrs",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Consistency: " + String(format: "%.2f", engine.sleepConsistency ?? 0) + "h stddev")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Efficiency: " + String(format: "%.0f%%", efficiency))
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
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var hrvData: [(Date, Double)] {
        let values = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        return filteredDailyValues(values, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    private var rhrData: [(Date, Double)] {
        filteredDailyValues(engine.dailyRestingHeartRate, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let latestHRV = hrvData.last?.1 ?? 0
        let averageHRV = average(hrvData.map(\.1)) ?? 0
        let latestRHR = rhrData.last?.1 ?? engine.restingHeartRate ?? 0
        let averageRHR = average(rhrData.map(\.1)) ?? engine.rhrBaseline7Day ?? 0
        HealthCard(
            symbol: "waveform.path.ecg",
            title: "HRV",
            value: String(format: "%.0f", latestHRV),
            unit: "ms",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.0f", averageHRV),
            color: .purple,
            chartData: hrvData,
            chartLabel: "HRV",
            chartUnit: "ms",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HRV reflects the latest value within the selected window ending on \(anchorDate.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("RHR: " + String(format: "%.0f", latestRHR) + " bpm")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("RHR \(timeFilter.rawValue) avg: " + String(format: "%.0f", averageRHR))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TappableChartPreview(data: rhrData, label: "RHR", unit: "bpm", color: .red)
                }
            }
        )
    }
}

struct WorkoutContributionsSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    let sportFilter: String?
    
    private struct DailyLoadSnapshot: Identifiable {
        let date: Date
        let sessionLoad: Double
        let acuteLoad: Double
        let acuteTotal: Double
        let chronicLoad: Double
        let chronicTotal: Double
        let acwr: Double
        let workoutCount: Int
        
        var id: Date { date }
    }
    
    private var displayWindow: (start: Date, end: Date, endExclusive: Date) {
        chartWindow(for: timeFilter, anchorDate: anchorDate)
    }
    
    private var historicalWindowStart: Date {
        Calendar.current.date(byAdding: .day, value: -27, to: displayWindow.start) ?? displayWindow.start
    }
    
    private var workoutsForComputation: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        return engine.workoutAnalytics.filter { workout, _ in
            let matchesDate = workout.startDate >= historicalWindowStart && workout.startDate < displayWindow.endExclusive
            let matchesSport = sportFilter == nil || workout.workoutActivityType.name == sportFilter
            return matchesDate && matchesSport
        }
    }
    
    private func workoutEffortScore(from workout: HKWorkout) -> Double? {
        guard let metadata = workout.metadata else { return nil }
        
        let preferredKeys = [
            "HKMetadataKeyWorkloadEffortScore",
            "HKMetadataKeyWorkoutEffortScore"
        ]
        
        for key in preferredKeys {
            if let value = metadata[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = metadata[key] as? Double {
                return value
            }
        }
        
        for (key, value) in metadata where key.localizedCaseInsensitiveContains("effort") {
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let doubleValue = value as? Double {
                return doubleValue
            }
        }
        
        return nil
    }
    
    private func sessionLoad(for workout: HKWorkout, analytics: WorkoutAnalytics) -> Double {
        let zoneWeightedLoad = analytics.hrZoneBreakdown.reduce(0.0) { partial, entry in
            let zoneWeight = Double(min(max(entry.zone.zoneNumber, 1), 5))
            let zoneMinutes = entry.timeInZone / 60.0
            return partial + (zoneMinutes * zoneWeight)
        }
        
        if zoneWeightedLoad > 0 {
            return zoneWeightedLoad.rounded()
        }
        
        let durationMinutes = workout.duration / 60.0
        if let effortScore = workoutEffortScore(from: workout) {
            return (durationMinutes * max(1, effortScore)).rounded()
        }
        
        return 0
    }
    
    private var dailyLoadSnapshots: [DailyLoadSnapshot] {
        let calendar = Calendar.current
        var sessionLoadByDay: [Date: Double] = [:]
        var workoutCountByDay: [Date: Int] = [:]
        
        for (workout, analytics) in workoutsForComputation {
            let day = calendar.startOfDay(for: workout.startDate)
            let load = sessionLoad(for: workout, analytics: analytics)
            sessionLoadByDay[day, default: 0] += load
            workoutCountByDay[day, default: 0] += 1
        }
        
        return dateSequence(from: displayWindow.start, to: displayWindow.end).map { day in
            let acuteLoad = (0..<7).reduce(0.0) { partial, offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return partial + (sessionLoadByDay[sourceDay] ?? 0)
            }
            
            let chronicTotal = (0..<28).reduce(0.0) { partial, offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return partial + (sessionLoadByDay[sourceDay] ?? 0)
            }
            
            let acuteAverage = acuteLoad / 7.0
            let chronicLoad = chronicTotal / 28.0
            
            return DailyLoadSnapshot(
                date: day,
                sessionLoad: sessionLoadByDay[day] ?? 0,
                acuteLoad: acuteAverage,
                acuteTotal: acuteLoad,
                chronicLoad: chronicLoad,
                chronicTotal: chronicTotal,
                acwr: chronicLoad > 0 ? acuteAverage / chronicLoad : 0,
                workoutCount: workoutCountByDay[day] ?? 0
            )
        }
    }
    
    private var selectedSnapshot: DailyLoadSnapshot {
        dailyLoadSnapshots.last ?? DailyLoadSnapshot(
            date: displayWindow.end,
            sessionLoad: 0,
            acuteLoad: 0,
            acuteTotal: 0,
            chronicLoad: 0,
            chronicTotal: 0,
            acwr: 0,
            workoutCount: 0
        )
    }
    
    private var acuteLoadChartData: [(Date, Double)] {
        dailyLoadSnapshots.map { ($0.date, $0.acuteLoad) }
    }
    
    private var selectedWeekBreakdown: [DailyLoadSnapshot] {
        Array(dailyLoadSnapshots.suffix(7))
    }
    
    var body: some View {
        HealthCard(
            symbol: "figure.strengthtraining.traditional",
            title: "Workouts",
            value: String(format: "%.0f", selectedSnapshot.acuteLoad),
            unit: "load",
            trend: "ACWR " + String(format: "%.2f", selectedSnapshot.acwr) + " • Chronic " + String(format: "%.1f", selectedSnapshot.chronicLoad),
            color: .green,
            chartData: acuteLoadChartData,
            chartLabel: "Acute Load",
            chartUnit: "pts",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected day: \(selectedSnapshot.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Session load on selected day: " + String(format: "%.0f", selectedSnapshot.sessionLoad) + " pts across \(selectedSnapshot.workoutCount) workout\(selectedSnapshot.workoutCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Acute Load (7-day daily average): " + String(format: "%.1f", selectedSnapshot.acuteLoad) + " pts/day = " + String(format: "%.0f", selectedSnapshot.acuteTotal) + " / 7")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Chronic Load (28-day average): " + String(format: "%.1f", selectedSnapshot.chronicLoad) + " pts/day = " + String(format: "%.0f", selectedSnapshot.chronicTotal) + " / 28")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("ACWR = " + String(format: "%.1f", selectedSnapshot.acuteLoad) + " / " + String(format: "%.1f", selectedSnapshot.chronicLoad) + " = " + String(format: "%.2f", selectedSnapshot.acwr))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Session load formula: sum of minutes spent in HR zones, weighted Zone 1-5. If HR data is missing, duration x effort metadata is used.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Acute Load History (\(timeFilter.rawValue))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TappableChartPreview(data: acuteLoadChartData, label: "Acute Load", unit: "pts", color: .green)
                    if !selectedWeekBreakdown.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("Past 7 days used for acute load")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        ForEach(Array(selectedWeekBreakdown.reversed())) { snapshot in
                            HStack {
                                Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.0f pts", snapshot.sessionLoad))
                                    .font(.caption2)
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
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date

    var filteredWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
        
        return engine.workoutAnalytics.filter { workout, _ in
            let isInRange = workout.startDate >= window.start && workout.startDate < window.endExclusive
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
        guard timeFilter.dayCount > 0 else { return 0 }
        return (Double(filteredWorkouts.count) / Double(timeFilter.dayCount)) * 7
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
                    Text("\(timeFilter.rawValue) frequency: " + String(format: "%.1f", frequency) + " sessions/week")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Total minutes (\(timeFilter.rawValue)): " + String(format: "%.0f", totalMinutes))
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
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    @State private var isLoading = true
    
    private var respArray: [(Date, Double)] {
        filteredDailyValues(engine.respiratoryRate, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    private var tempArray: [(Date, Double)] {
        filteredDailyValues(engine.wristTemperature, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    private var spo2Array: [(Date, Double)] {
        filteredDailyValues(engine.spO2, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    private var respCurrent: Double {
        respArray.last?.1 ?? 0
    }
    
    private var respAverage: Double {
        average(respArray.map(\.1)) ?? 0
    }
    
    private var tempCurrent: Double {
        tempArray.last?.1 ?? 0
    }
    
    private var tempAverage: Double {
        average(tempArray.map(\.1)) ?? 0
    }
    
    private var spo2Current: Double {
        spo2Array.last?.1 ?? 0
    }
    
    private var spo2Average: Double {
        average(spo2Array.map(\.1)) ?? 0
    }
    
    var body: some View {
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
                    trend: "\(timeFilter.rawValue) avg: " + String(format: "%.1f", respAverage),
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
                        Text("Wrist Temp (\(timeFilter.rawValue))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Current: " + String(format: "%.2f", tempCurrent) + "°C | Avg: " + String(format: "%.2f", tempAverage) + "°C")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if tempArray.isEmpty {
                            Text("No wrist temperature data available.")
                                .foregroundColor(.red)
                        }
                        TappableChartPreview(data: tempArray, label: "Wrist Temp", unit: "°C", color: .pink)
//                            .frame(height: 60)
                        Text("SpO₂ (\(timeFilter.rawValue))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Current: " + String(format: "%.1f", spo2Current) + "% | Avg: " + String(format: "%.1f", spo2Average) + "%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if spo2Array.isEmpty {
                            Text("No SpO₂ data available.")
                                .foregroundColor(.red)
                        }
                        TappableChartPreview(data: spo2Array, label: "SpO₂", unit: "%", color: .mint)
//                            .frame(height: 60)
                        Divider().padding(.vertical, 2)
                        ForEach([
                            ("RespiratoryRate", respCurrent, respAverage),
                            ("WristTemp", tempCurrent, tempAverage),
                            ("SpO2", spo2Current, spo2Average)
                        ], id: \.0) { key, current, average in
                            HStack {
                                Text("\(key):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Current: \(String(format: "%.1f", current))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(timeFilter.rawValue) Avg: \(String(format: "%.1f", average))")
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
//                .frame(height: 60)
            }
        }
        .padding(.vertical, 4)
    }
}

struct METAggregatesSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?
    let anchorDate: Date

    var filteredData: [(Date, Double)] {
        filteredDailyValues(engine.dailyMETAggregates, timeFilter: timeFilter, anchorDate: anchorDate)
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
    let anchorDate: Date

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
        return filteredDailyValues(base, timeFilter: timeFilter, anchorDate: anchorDate)
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
    let anchorDate: Date

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
        return filteredDailyValues(base, timeFilter: timeFilter, anchorDate: anchorDate)
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
