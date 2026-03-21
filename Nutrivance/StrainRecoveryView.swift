import SwiftUI
import HealthKit

#if !os(visionOS)
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
    
    private func stepSelectedDate(by value: Int) {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: Date())
        
        guard let steppedDate = calendar.date(byAdding: timeFilter.navigationComponent, value: value, to: currentDay) else {
            return
        }
        
        selectedDate = min(steppedDate, today)
    }
    
    private var canStepForward: Bool {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: Date())
        
        guard let steppedDate = calendar.date(byAdding: timeFilter.navigationComponent, value: 1, to: currentDay) else {
            return false
        }
        
        return steppedDate <= today
    }

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

                    MetricSectionGroup(title: "Training Load") {
                        StrainRecoveryMathSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        WorkoutContributionsSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate,
                            sportFilter: nil
                        )
                        METAggregatesSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            sportFilter: sportFilter,
                            anchorDate: selectedDate
                        )
                        TrainingScheduleSection(
                            engine: engine,
                            sportFilter: sportFilter,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        VO2AggregatesSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            sportFilter: sportFilter,
                            anchorDate: selectedDate
                        )
                    }

                    MetricSectionGroup(title: "Recovery") {
                        HRVSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        RestingHeartRateSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        HRRAggregatesSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            sportFilter: sportFilter,
                            anchorDate: selectedDate
                        )
                        RespiratoryRateSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        WristTemperatureSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        SpO2Section(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                    }

                    MetricSectionGroup(title: "Sleep") {
                        SleepRecoverySection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        SleepConsistencySection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                        SleepHeartRateSection(
                            engine: engine,
                            timeFilter: timeFilter,
                            anchorDate: selectedDate
                        )
                    }
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        selectedDate = Date()
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    } label: {
                        Text("Today")
                    }
                    Button {
                        stepSelectedDate(by: -1)
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    
                    DatePicker(
                        "Reference Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    
                    Button {
                        stepSelectedDate(by: 1)
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canStepForward)
                }
            }
            .task {
                await engine.refreshWorkoutAnalytics(days: 3650) // Load long-term history for aggregation cards
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
    
    var navigationComponent: Calendar.Component {
        switch self {
        case .week:
            return .day
        case .month:
            return .weekOfYear
        case .year:
            return .month
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

private func standardDeviation(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
    return sqrt(variance)
}

struct MetricSectionGroup<Content: View>: View {
    let title: String
    let content: () -> Content
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            content()
        }
    }
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
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
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
        // "Sleep Hours" is based on asleep time (core/deep/rem), not awake time.
        let totalStages = ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        let latestSleep = sleepData.last?.1 ?? 0
        let averageSleep = average(sleepData.map(\.1)) ?? 0
        let efficiency = (engine.sleepEfficiency[activeDay] ?? 0) * 100
        HealthCard(
            symbol: "bed.double.fill",
            title: "Sleep Hours",
            value: String(format: "%.1f", latestSleep),
            unit: "hrs",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.1f", averageSleep),
            color: .blue,
            chartData: sleepData,
            chartLabel: "Sleep",
            chartUnit: "hrs",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Efficiency: " + String(format: "%.0f%%", efficiency))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if !stages.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(["core", "deep", "rem", "unspecified"], id: \.self) { stage in
                                let hours = stages[stage] ?? 0
                                Text("\(stage.capitalized): " + String(format: "%.1f", hours) + "h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("Total: " + String(format: "%.1f", totalStages) + "h (matches main value)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        )
    }
}

struct SleepConsistencySection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var midpointData: [(Date, Double)] {
        let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
        let dates = dateSequence(from: window.start, to: window.end)
        let raw = engine.sleepMidpointHours
        return dates.compactMap { day in
            guard let value = raw[day], value > 0 else { return nil }
            return (day, value)
        }
    }
    
    private var midpointDeviationHours: Double {
        standardDeviation(midpointData.map(\.1)) ?? engine.sleepConsistency ?? 0
    }
    
    private var midpointDeviationMinutes: Double {
        midpointDeviationHours * 60
    }
    
    private var consistencyScore: Double {
        let best = 0.25
        let worst = 3.0
        let clamped = min(max(midpointDeviationHours, best), worst)
        return ((worst - clamped) / (worst - best)) * 100
    }
    
    private var midpointDeviationData: [(Date, Double)] {
        let valid = midpointData.map(\.1)
        guard let center = average(valid) else { return [] }

        return midpointData.map { date, midpoint in
            (date, abs(midpoint - center) * 60)
        }
    }
    
    private var averageEfficiency: Double {
        // Align with SleepView semantics: actual sleep is asleep stages (including unspecified)
        // and denominator includes awake periods for the same sleep day.
        let efficiencyValues = midpointData.compactMap { day, _ -> Double? in
            guard let stages = engine.sleepStages[day] else { return nil }
            let asleep = ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
            let awake = stages["awake"] ?? 0
            let denominator = asleep + awake
            guard denominator > 0 else { return nil }
            return asleep / denominator
        }
        return (average(efficiencyValues) ?? 0) * 100
    }
    
    private var sleepDebtHours: Double {
        // Debt model: compare recent 7-day average actual sleep against prior 28-day baseline.
        let sleepByDay = filteredDailyValues(
            engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
            },
            timeFilter: timeFilter,
            anchorDate: anchorDate
        ).filter { $0.1 > 0 }
        
        let series = sleepByDay.sorted { $0.0 < $1.0 }
        
        guard !series.isEmpty else { return 0 }
        let last7 = Array(series.suffix(7)).map(\.1)
        guard !last7.isEmpty else { return 0 }
        
        let previousSeries = Array(series.dropLast(last7.count))
        let baseline28 = Array(previousSeries.suffix(28)).map(\.1)
        guard !baseline28.isEmpty else { return 0 }
        
        let recentAverage = average(last7) ?? 0
        let baselineAverage = average(baseline28) ?? 0
        return max(0, (baselineAverage - recentAverage) * 7.0)
    }
    
    private var activityRecoverySleepGapHours: Double {
        let calendar = Calendar.current
        let sleepHoursByDay = midpointData.compactMap { day, _ -> (Date, Double)? in
            guard let stages = engine.sleepStages[day] else { return nil }
            let sleepHours = ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
            guard sleepHours > 0 else { return nil }
            return (day, sleepHours)
        }
        
        let activityDaySleep = sleepHoursByDay.filter { day, _ in
            engine.workoutAnalytics.contains { calendar.isDate($0.workout.startDate, inSameDayAs: day) }
        }.map(\.1)
        
        let recoveryDaySleep = sleepHoursByDay.filter { day, _ in
            !engine.workoutAnalytics.contains { calendar.isDate($0.workout.startDate, inSameDayAs: day) }
        }.map(\.1)
        
        guard let activityAverage = average(activityDaySleep),
              let recoveryAverage = average(recoveryDaySleep) else { return 0 }
        
        // Positive means recovery days get more sleep than activity days.
        return recoveryAverage - activityAverage
    }
    
    var body: some View {
        HealthCard(
            symbol: "moon.zzz.fill",
            title: "Sleep Consistency",
            value: String(format: "%.0f", consistencyScore),
            unit: "%",
            trend: "Midpoint dev: " + String(format: "%.0f", midpointDeviationMinutes) + " min",
            color: .indigo,
            chartData: midpointDeviationData,
            chartLabel: "Midpoint Deviation",
            chartUnit: "min",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Consistency is based on the standard deviation of sleep midpoints in the selected window.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Midpoint deviation: " + String(format: "%.0f", midpointDeviationMinutes) + " min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Efficiency: " + String(format: "%.0f%%", averageEfficiency))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Activity vs recovery sleep gap: " + String(format: "%+.1f", activityRecoverySleepGapHours) + "h")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Sleep debt (7d vs prior 28d baseline): " + String(format: "%.1f", sleepDebtHours) + "h")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct SleepHeartRateSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var sleepHeartRateData: [(Date, Double)] {
        let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
        let dates = dateSequence(from: window.start, to: window.end)
        let raw = engine.dailySleepHeartRate
        return dates.compactMap { day in
            guard let value = raw[day], value > 0 else { return nil }
            return (day, value)
        }
    }
    
    var body: some View {
        let valid = sleepHeartRateData.map(\.1)
        let latestSleepHR = valid.last ?? 0
        let averageSleepHR = average(valid) ?? 0
        
        HealthCard(
            symbol: "heart.text.square.fill",
            title: "Sleep HR",
            value: String(format: "%.0f", latestSleepHR),
            unit: "bpm",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.0f", averageSleepHR),
            color: .mint,
            chartData: sleepHeartRateData,
            chartLabel: "Sleep HR",
            chartUnit: "bpm",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Average heart rate recorded during each detected sleep window.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
    
    var body: some View {
        let latestHRV = hrvData.last?.1 ?? 0
        let averageHRV = average(hrvData.map(\.1)) ?? 0
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
                    Text("Higher HRV generally suggests better recovery capacity and autonomic readiness.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct RestingHeartRateSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var rhrData: [(Date, Double)] {
        filteredDailyValues(engine.dailyRestingHeartRate, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let latestRHR = rhrData.last?.1 ?? engine.restingHeartRate ?? 0
        let averageRHR = average(rhrData.map(\.1)) ?? engine.rhrBaseline7Day ?? 0
        
        HealthCard(
            symbol: "heart.fill",
            title: "RHR",
            value: String(format: "%.0f", latestRHR),
            unit: "bpm",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.0f", averageRHR),
            color: .red,
            chartData: rhrData,
            chartLabel: "RHR",
            chartUnit: "bpm",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lower resting heart rate usually reflects stronger aerobic recovery and lower fatigue.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

private struct WorkoutLoadStatus {
    let title: String
    let color: Color
    let detail: String
    let hidesRatio: Bool
}

private struct WorkoutLoadChart: View {
    let snapshots: [WorkoutContributionsSection.DailyLoadSnapshot]
    let acuteColor: Color
    let selectedDate: Date?
    let isExpanded: Bool
    
    private func xStart(for date: Date) -> Date {
        date.addingTimeInterval(-12 * 60 * 60)
    }
    
    private func xEnd(for date: Date) -> Date {
        date.addingTimeInterval(12 * 60 * 60)
    }
    
    var body: some View {
        Chart {
            ForEach(snapshots) { snapshot in
                RectangleMark(
                    xStart: .value("Band Start", xStart(for: snapshot.date)),
                    xEnd: .value("Band End", xEnd(for: snapshot.date)),
                    yStart: .value("Sweet Spot Low", snapshot.sweetSpotLower),
                    yEnd: .value("Sweet Spot High", snapshot.sweetSpotUpper)
                )
                .foregroundStyle(
                    snapshot.baselineIsReliable
                    ? Color.green.opacity(isExpanded ? 0.16 : 0.12)
                    : Color.gray.opacity(isExpanded ? 0.12 : 0.08)
                )
            }
            
            ForEach(snapshots) { snapshot in
                AreaMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Chronic Load", snapshot.chronicLoad)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.gray.opacity(isExpanded ? 0.22 : 0.16), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Chronic Load", snapshot.chronicLoad)
                )
                .foregroundStyle(Color.gray.opacity(0.8))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: isExpanded ? 2.0 : 1.6, lineCap: .round, lineJoin: .round))
                
                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Acute Load", snapshot.acuteLoad)
                )
                .foregroundStyle(snapshot.baselineIsReliable ? acuteColor : Color.gray)
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: isExpanded ? 2.8 : 2.3, lineCap: .round, lineJoin: .round))
            }
            
            if let selectedDate,
               let selected = snapshots.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                RuleMark(x: .value("Selected Day", selected.date))
                    .foregroundStyle(Color.primary.opacity(0.18))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                PointMark(
                    x: .value("Date", selected.date),
                    y: .value("Acute Load", selected.acuteLoad)
                )
                .foregroundStyle(acuteColor)
                .symbolSize(isExpanded ? 90 : 45)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: isExpanded ? 6 : 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}

struct WorkoutContributionsSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    let sportFilter: String?
    
    struct DailyLoadSnapshot: Identifiable {
        let date: Date
        let sessionLoad: Double
        let acuteLoad: Double
        let acuteTotal: Double
        let chronicLoad: Double
        let chronicTotal: Double
        let acwr: Double
        let workoutCount: Int
        let activeDaysLast28: Int
        let daysSinceLastWorkout: Int?
        
        var id: Date { date }
        
        var sweetSpotLower: Double { chronicLoad * 0.8 }
        var sweetSpotUpper: Double { chronicLoad * 1.3 }
        var baselineIsReliable: Bool { activeDaysLast28 >= 14 && (daysSinceLastWorkout ?? 0) < 8 && chronicLoad > 0 }
        var isRestDay: Bool { sessionLoad == 0 && workoutCount == 0 }
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

    private var selectedDayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let calendar = Calendar.current
        return workoutsForComputation
            .filter { calendar.isDate($0.workout.startDate, inSameDayAs: selectedSnapshot.date) }
            .sorted { $0.workout.startDate > $1.workout.startDate }
    }

    private var selectedZoneProfile: HRZoneProfile? {
        selectedDayWorkouts
            .compactMap { $0.analytics.hrZoneProfile }
            .first
    }

    private var selectedWeekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: selectedSnapshot.date) ?? selectedSnapshot.date
    }

    private var selectedWeekAveragePeakHR: Double? {
        let calendar = Calendar.current
        let values = workoutsForComputation.compactMap { pair -> Double? in
            let workoutDate = calendar.startOfDay(for: pair.workout.startDate)
            guard workoutDate >= selectedWeekStartDate && workoutDate <= selectedSnapshot.date else {
                return nil
            }
            return pair.analytics.peakHR
        }
        return average(values)
    }

    private var selectedWeekAverageRestingHR: Double? {
        let calendar = Calendar.current
        let values = (0..<7).compactMap { offset -> Double? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: selectedSnapshot.date) else {
                return nil
            }
            return engine.dailyRestingHeartRate[calendar.startOfDay(for: date)]
        }
        return average(values)
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
            let acuteTotal = (0..<7).reduce(0.0) { partial, offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return partial + (sessionLoadByDay[sourceDay] ?? 0)
            }
            
            let chronicTotal = (0..<28).reduce(0.0) { partial, offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return partial + (sessionLoadByDay[sourceDay] ?? 0)
            }
            
            let acuteAverage = acuteTotal / 7.0
            let chronicLoad = chronicTotal / 28.0
            let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return partial + ((sessionLoadByDay[sourceDay] ?? 0) > 0 ? 1 : 0)
            }
            let daysSinceLastWorkout = (0..<28).first(where: { offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return (sessionLoadByDay[sourceDay] ?? 0) > 0
            })
            
            return DailyLoadSnapshot(
                date: day,
                sessionLoad: sessionLoadByDay[day] ?? 0,
                acuteLoad: acuteAverage,
                acuteTotal: acuteTotal,
                chronicLoad: chronicLoad,
                chronicTotal: chronicTotal,
                acwr: chronicLoad > 0 ? acuteAverage / chronicLoad : 0,
                workoutCount: workoutCountByDay[day] ?? 0,
                activeDaysLast28: activeDaysLast28,
                daysSinceLastWorkout: daysSinceLastWorkout
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
            workoutCount: 0,
            activeDaysLast28: 0,
            daysSinceLastWorkout: nil
        )
    }
    
    private var acuteLoadChartData: [(Date, Double)] {
        dailyLoadSnapshots.map { ($0.date, $0.acuteLoad) }
    }
    
    private var selectedWeekBreakdown: [DailyLoadSnapshot] {
        Array(dailyLoadSnapshots.suffix(7))
    }
    
    private var status: WorkoutLoadStatus {
        if selectedSnapshot.activeDaysLast28 < 14 {
            return WorkoutLoadStatus(
                title: "Baseline Outdated",
                color: .orange,
                detail: "Baseline out of date. 14 active days in the last 28 are recommended to recalculate your fitness floor.",
                hidesRatio: true
            )
        }
        
        if let daysSinceLastWorkout = selectedSnapshot.daysSinceLastWorkout {
            if daysSinceLastWorkout > 21 {
                return WorkoutLoadStatus(
                    title: "Reset",
                    color: .gray,
                    detail: "More than 21 inactive days. Treat this as a new build and re-establish 28 days of baseline.",
                    hidesRatio: true
                )
            }
            if daysSinceLastWorkout >= 8 {
                return WorkoutLoadStatus(
                    title: "Re-establishing",
                    color: .orange,
                    detail: "Restarting training. ACWR may be sensitive for the next 7 days as you rebuild your acute baseline.",
                    hidesRatio: true
                )
            }
        } else {
            return WorkoutLoadStatus(
                title: "No Baseline",
                color: .gray,
                detail: "No recent training load found. The model needs fresh workouts to establish readiness.",
                hidesRatio: true
            )
        }
        
        switch selectedSnapshot.acwr {
        case ..<0.8:
            return WorkoutLoadStatus(
                title: "Detraining",
                color: .blue,
                detail: "Fitness baseline is dropping. Intensity may be too low to maintain gains.",
                hidesRatio: false
            )
        case 0.8...1.2:
            return WorkoutLoadStatus(
                title: "Optimal",
                color: .green,
                detail: "Acute load is tracking inside the sweet spot relative to your chronic load.",
                hidesRatio: false
            )
        case 1.3...1.5:
            return WorkoutLoadStatus(
                title: "Aggressive",
                color: .yellow,
                detail: "Pushing limits. Monitor fatigue, recovery quality, and the next session closely.",
                hidesRatio: false
            )
        default:
            return WorkoutLoadStatus(
                title: "Spike",
                color: .red,
                detail: "High workload spike. Risk of injury is increased. Consider a lower-intensity session.",
                hidesRatio: false
            )
        }
    }
    
    private var trendText: String {
        if status.hidesRatio {
            return status.detail
        }
        return "ACWR " + String(format: "%.2f", selectedSnapshot.acwr) + " • Chronic " + String(format: "%.1f", selectedSnapshot.chronicLoad)
    }
    
    private var baselineProgress: Double {
        min(Double(selectedSnapshot.activeDaysLast28) / 14.0, 1.0)
    }
    
    var body: some View {
        HealthCard(
            symbol: "figure.strengthtraining.traditional",
            title: "Workouts",
            value: String(format: "%.0f", selectedSnapshot.acuteLoad),
            unit: "load",
            trend: trendText,
            color: status.color,
            chartData: acuteLoadChartData,
            chartLabel: "Acute Load",
            chartUnit: "pts",
            badgeText: status.title,
            badgeColor: status.color,
            customChartPreview: AnyView(
                WorkoutLoadChart(
                    snapshots: dailyLoadSnapshots,
                    acuteColor: status.color,
                    selectedDate: selectedSnapshot.date,
                    isExpanded: false
                )
            ),
            customChartSheet: AnyView(
                VStack(spacing: 16) {
                    Text("Load vs Baseline")
                        .font(.title.bold())
                        .foregroundColor(status.color)
                    WorkoutLoadChart(
                        snapshots: dailyLoadSnapshots,
                        acuteColor: status.color,
                        selectedDate: selectedSnapshot.date,
                        isExpanded: true
                    )
                    .frame(height: 280)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status.title)
                            .font(.headline)
                            .foregroundColor(status.color)
                        Text(status.detail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Sweet spot: acute load should stay between 0.8x and 1.3x of chronic load.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            ),
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected day: \(selectedSnapshot.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if selectedSnapshot.isRestDay {
                        Text("Recovery Day: 0 pts across 0 workouts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Session load on selected day: " + String(format: "%.0f", selectedSnapshot.sessionLoad) + " pts across \(selectedSnapshot.workoutCount) workout\(selectedSnapshot.workoutCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Acute Load (7-day daily average): " + String(format: "%.1f", selectedSnapshot.acuteLoad) + " pts/day = " + String(format: "%.0f", selectedSnapshot.acuteTotal) + " / 7")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Chronic Load (28-day average): " + String(format: "%.1f", selectedSnapshot.chronicLoad) + " pts/day = " + String(format: "%.0f", selectedSnapshot.chronicTotal) + " / 28")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if status.hidesRatio {
                        Text("ACWR is hidden while the baseline is being rebuilt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("ACWR = " + String(format: "%.1f", selectedSnapshot.acuteLoad) + " / " + String(format: "%.1f", selectedSnapshot.chronicLoad) + " = " + String(format: "%.2f", selectedSnapshot.acwr))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(status.detail)
                        .font(.caption)
                        .foregroundColor(status.color)
                    if status.hidesRatio {
                        ProgressView(value: baselineProgress)
                            .tint(status.color)
                        Text("Baseline progress: \(selectedSnapshot.activeDaysLast28)/14 active days in the last 28")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("Session load formula: sum of minutes spent in HR zones, weighted Zone 1-5. If HR data is missing, duration x effort metadata is used.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let profile = selectedZoneProfile {
                        Divider().padding(.vertical, 2)
                        HeartRateZoneProfileSummaryView(
                            profile: profile,
                            displayedMaxHR: selectedWeekAveragePeakHR,
                            displayedRestingHR: selectedWeekAverageRestingHR,
                            maxHRLabel: "7d Peak HR",
                            restingHRLabel: "7d Resting HR"
                        )
                    }
                    Text("Acute vs Chronic (\(timeFilter.rawValue))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Text("Acute")
                            .font(.caption2.bold())
                            .foregroundColor(status.color)
                        Text("Chronic")
                            .font(.caption2.bold())
                            .foregroundColor(.gray)
                        Text("Sweet Spot 0.8x-1.3x")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                    }
                    WorkoutLoadChart(
                        snapshots: dailyLoadSnapshots,
                        acuteColor: status.color,
                        selectedDate: selectedSnapshot.date,
                        isExpanded: true
                    )
                    .frame(height: 190)
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

    // 1) Computed property for time-filtered favorite sport
    var favoriteSportInWindow: String? {
        let grouped = Dictionary(grouping: filteredWorkouts, by: { $0.workout.workoutActivityType.name })
        let totals = grouped.mapValues { workouts in
            workouts.reduce(0.0) { $0 + ($1.workout.duration / 60.0) }
        }
        return totals.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        let totalMinutes = minutesPerDay.map { $0.1 }.reduce(0, +)
        HealthCard(
            symbol: "calendar",
            title: "Training Schedule",
            value: String(format: "%.0f", totalMinutes),
            unit: "min",
            // 2) Update trend text to use time-filtered favorite sport
            trend: "Focus: " + (favoriteSportInWindow ?? "-"),
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
                    if sportFilter == nil {
                        // 3) Update expanded content “Focus” to use the new property
                        Text("Focus: " + (favoriteSportInWindow ?? "-"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        )
    }
}

struct RespiratoryRateSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var respArray: [(Date, Double)] {
        filteredDailyValues(engine.respiratoryRate, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let current = respArray.last?.1 ?? 0
        let averageValue = average(respArray.map(\.1)) ?? 0
        
        HealthCard(
            symbol: "lungs.fill",
            title: "Respiratory Rate",
            value: String(format: "%.1f", current),
            unit: "bpm",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.1f", averageValue),
            color: .indigo,
            chartData: respArray,
            chartLabel: "Respiratory Rate",
            chartUnit: "bpm",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nighttime respiratory rate can rise under illness, stress, heat load, or incomplete recovery.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct WristTemperatureSection: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var tempArray: [(Date, Double)] {
        filteredDailyValues(engine.wristTemperature, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let current = tempArray.last?.1 ?? 0
        let averageValue = average(tempArray.map(\.1)) ?? 0
        
        HealthCard(
            symbol: "thermometer.medium",
            title: "Wrist Temperature",
            value: String(format: "%.2f", current),
            unit: "°C",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.2f", averageValue),
            color: .pink,
            chartData: tempArray,
            chartLabel: "Wrist Temp",
            chartUnit: "°C",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wrist temperature trends help flag heat strain, illness, travel disruption, or menstrual-cycle related shifts.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

struct SpO2Section: View {
    @ObservedObject var engine: HealthStateEngine
    let timeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var spo2Array: [(Date, Double)] {
        filteredDailyValues(engine.spO2, timeFilter: timeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let current = spo2Array.last?.1 ?? 0
        let averageValue = average(spo2Array.map(\.1)) ?? 0
        
        HealthCard(
            symbol: "drop.fill",
            title: "SpO₂",
            value: String(format: "%.1f", current),
            unit: "%",
            trend: "\(timeFilter.rawValue) avg: " + String(format: "%.1f", averageValue),
            color: .mint,
            chartData: spo2Array,
            chartLabel: "SpO₂",
            chartUnit: "%",
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A stable oxygen saturation baseline supports better altitude, sleep, and respiratory readiness tracking.")
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
        var base = engine.dailyMETAggregates
        if let sport = sportFilter {
            let filteredWorkouts = engine.workoutAnalytics.filter { $0.workout.workoutActivityType.name == sport }
            var aggregates: [Date: Double] = [:]
            let calendar = Calendar.current
            for (workout, analytics) in filteredWorkouts {
                let day = calendar.startOfDay(for: workout.startDate)
                aggregates[day, default: 0] += analytics.metTotal ?? 0
            }
            base = aggregates
        }
        return filteredDailyValues(base, timeFilter: timeFilter, anchorDate: anchorDate)
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
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    if filteredData.isEmpty {
                        Text("No MET-minutes recorded in this window.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        let latest = filteredData.last?.1 ?? 0
                        let averageValue = average(filteredData.map(\.1)) ?? 0
                        let windowTotal = filteredData.map(\.1).reduce(0, +)

                        Text("Latest day: " + String(format: "%.1f", latest) + " MET-min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(timeFilter.rawValue) avg: " + String(format: "%.1f", averageValue) + " MET-min/day")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Window total: " + String(format: "%.1f", windowTotal) + " MET-min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("MET-minutes are estimated by integrating MET intensity over workout time.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let sportFilter {
                            Text("Filtered to: " + sportFilter.capitalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
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
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    if filteredData.isEmpty {
                        Text("No VO2 max estimates available in this window.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        let latest = filteredData.last?.1 ?? 0
                        let averageValue = average(filteredData.map(\.1)) ?? 0
                        let maxValue = filteredData.map(\.1).max() ?? latest

                        Text("Latest day: " + String(format: "%.1f", latest) + " ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(timeFilter.rawValue) avg: " + String(format: "%.1f", averageValue) + " ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Best day in window: " + String(format: "%.1f", maxValue) + " ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Daily VO2 max is averaged across workouts that include a VO2 estimate.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let sportFilter {
                            Text("Filtered to: " + sportFilter.capitalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
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
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    if filteredData.isEmpty {
                        Text("No HRR (2 min) values available in this window.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        let latest = filteredData.last?.1 ?? 0
                        let averageValue = average(filteredData.map(\.1)) ?? 0
                        let maxValue = filteredData.map(\.1).max() ?? latest

                        Text("Latest day: " + String(format: "%.0f", latest) + " bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(timeFilter.rawValue) avg: " + String(format: "%.0f", averageValue) + " bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Max day in window: " + String(format: "%.0f", maxValue) + " bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("HRR (2 min) is Peak HR minus HR measured ~2 minutes after workout end.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let sportFilter {
                            Text("Filtered to: " + sportFilter.capitalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        )
    }
}

extension Array where Element: Hashable {
    var unique: [Element] {
        Array(Set(self))
    }
}
#else
struct StrainRecoveryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Unavailable On Vision Pro",
                systemImage: "waveform.path.ecg.rectangle",
                description: Text("Strain and recovery analytics are currently disabled on visionOS.")
            )
            .navigationTitle("Strain vs Recovery")
        }
    }
}
#endif
