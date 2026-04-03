import SwiftUI
import HealthKit
import Charts

// MARK: - Data Models

struct ZoneBreakdownEntry: Identifiable {
    let id = UUID()
    let workoutUUID: UUID
    let workoutDate: Date
    let sport: String
    let duration: TimeInterval
    let avgHR: Double?
    let peakHR: Double?
    let zones: [ZoneTimeEntry]
    let profile: HRZoneProfile
}

struct ZoneTimeEntry: Identifiable {
    let id = UUID()
    let zoneNumber: Int
    let zoneName: String
    let zoneColorHex: String
    let lowerBound: Double
    let upperBound: Double
    let seconds: TimeInterval

    var minutes: Double { seconds / 60.0 }
    var color: Color { hexToSwiftUIColor(zoneColorHex) }
}

struct DailyZoneAggregate: Identifiable {
    let id = UUID()
    let date: Date
    let sport: String?
    let sessionCount: Int
    let zones: [Int: Double]
    let totalMinutes: Double
}

struct BaselineZoneStats {
    let windowLabel: String
    let perZoneAvgMinutes: [Int: Double]
    let perZoneTotalMinutes: [Int: Double]
    let sessionCount: Int
    let dayCount: Int
}

private func hexToSwiftUIColor(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let scanner = Scanner(string: hex)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return Color(
        red: Double((rgb >> 16) & 0xFF) / 255.0,
        green: Double((rgb >> 8) & 0xFF) / 255.0,
        blue: Double(rgb & 0xFF) / 255.0
    )
}

// MARK: - Zone Resolution Engine

@MainActor
final class HeartZoneEngine: ObservableObject {
    @Published var entries: [ZoneBreakdownEntry] = []
    @Published var isLoading = false
    @Published var resolvedSportNames: [String] = []

    private let hkm = HealthKitManager()

    func load(engine: HealthStateEngine, from start: Date, to end: Date) async {
        isLoading = true
        defer { isLoading = false }

        let workouts = engine.workoutAnalytics.filter { pair in
            pair.workout.startDate >= start && pair.workout.startDate < end
        }

        let settings = loadSettings()
        var results: [ZoneBreakdownEntry] = []

        for (workout, analytics) in workouts {
            guard !analytics.heartRates.isEmpty else { continue }
            let profile = await resolveProfile(for: workout, analytics: analytics, settings: settings)
            let breakdown = hkm.calculateZoneBreakdown(heartRates: analytics.heartRates, zoneProfile: profile)

            let zoneEntries = profile.zones.map { zone in
                let time = breakdown.first(where: { $0.zone.zoneNumber == zone.zoneNumber })?.timeInZone ?? 0
                return ZoneTimeEntry(
                    zoneNumber: zone.zoneNumber,
                    zoneName: zone.name,
                    zoneColorHex: zone.color,
                    lowerBound: zone.range.lowerBound,
                    upperBound: zone.range.upperBound,
                    seconds: time
                )
            }

            let allHR = analytics.heartRates.map(\.1)
            results.append(ZoneBreakdownEntry(
                workoutUUID: workout.uuid,
                workoutDate: workout.startDate,
                sport: workout.workoutActivityType.name,
                duration: workout.duration,
                avgHR: allHR.isEmpty ? nil : allHR.reduce(0, +) / Double(allHR.count),
                peakHR: analytics.peakHR,
                zones: zoneEntries,
                profile: profile
            ))
        }

        entries = results.sorted { $0.workoutDate > $1.workoutDate }
        resolvedSportNames = Array(Set(results.map(\.sport))).sorted()
    }

    func loadSettings() -> HRZoneUserSettings {
        let persisted = HRZoneSettingsPersistence.load() ?? .fallback
        let mode = HRZoneConfigurationMode(rawValue: persisted.modeRawValue) ?? .intelligent
        let schema = HRZoneSchema(rawValue: persisted.schemaRawValue) ?? .lactatThreshold
        return HRZoneUserSettings(
            mode: mode,
            customSchema: schema,
            fixedMaxHR: persisted.fixedMaxHR,
            fixedRestingHR: persisted.fixedRestingHR,
            fixedLTHR: persisted.fixedLTHR,
            customZoneUpperBounds: persisted.customZoneUpperBounds
        )
    }

    private func resolveProfile(
        for workout: HKWorkout,
        analytics: WorkoutAnalytics,
        settings: HRZoneUserSettings
    ) async -> HRZoneProfile {
        switch settings.mode {
        case .customZones:
            let bounds = settings.customZoneUpperBounds
            guard bounds.count == 5, zip(bounds, bounds.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
                return await hkm.createHRZoneProfile(for: workout.workoutActivityType)
            }
            let lowerBounds = [0.0] + Array(bounds.dropLast())
            let colors = ["0099FF", "00CC00", "FFCC00", "FF6600", "FF0000"]
            let zones = zip(Array(1...5), zip(lowerBounds, bounds)).map { zoneNumber, pair in
                HeartRateZone(name: zoneName(zoneNumber), range: pair.0...pair.1, color: colors[zoneNumber - 1], zoneNumber: zoneNumber)
            }
            return HRZoneProfile(sport: workout.workoutActivityType.rawValue, schema: settings.customSchema, maxHR: bounds.last, restingHR: nil, lactateThresholdHR: nil, zones: zones, lastUpdated: Date(), adaptive: false)

        case .customSchema:
            return await hkm.createHRZoneProfile(
                for: workout.workoutActivityType,
                schema: settings.customSchema,
                customMaxHR: settings.fixedMaxHR,
                customRestingHR: settings.fixedRestingHR,
                customLTHR: settings.fixedLTHR
            )

        case .intelligent:
            let date = workout.startDate
            let maxHR = await hkm.fetchMaxHR(workoutDate: date)
            let restingHR = await hkm.fetchRHR(workoutDate: date)
            let schema = analytics.hrZoneProfile?.schema ?? hkm.recommendedSchema(for: workout.workoutActivityType)
            let lthr = await hkm.fetchLTHR(workoutDate: date, maxHR: maxHR)
            return await hkm.createHRZoneProfile(
                for: workout.workoutActivityType,
                schema: schema,
                customMaxHR: maxHR,
                customRestingHR: restingHR,
                customLTHR: lthr
            )
        }
    }

    private func zoneName(_ number: Int) -> String {
        switch number {
        case 1: return "Zone 1: Endurance"
        case 2: return "Zone 2: Endurance"
        case 3: return "Zone 3: Tempo"
        case 4: return "Zone 4: Threshold"
        case 5: return "Zone 5: VO₂ Max"
        default: return "Zone \(number)"
        }
    }
}

// MARK: - Liquid glass surfaces

private struct GlassCapsuleBackground: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(isSelected ? Color.orange.opacity(0.44) : Color.white.opacity(0.08))
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }
}

private struct GlassCircleBackground: View {
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.white.opacity(0.08))
            Circle().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }
}

private struct GlassRoundedRectBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

private struct LiquidGlassSegmentButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background { GlassCapsuleBackground(isSelected: isSelected) }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.92))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct LiquidGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .foregroundStyle(Color.orange)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private struct LiquidGlassTodayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Color.orange)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct LiquidGlassSportChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(isSelected ? Color.orange.opacity(0.32) : Color.white.opacity(0.07))
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.orange.opacity(0.65), Color.orange.opacity(0.2)]
                                : [.white.opacity(0.4), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
            }
            .foregroundStyle(isSelected ? Color.orange : Color.white.opacity(0.85))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Toolbar (extracted for faster type-checking)

private struct HeartZonesDateToolbarButtons: View {
    let onPrev: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(LiquidGlassCircleButtonStyle())
            .accessibilityLabel("Previous period")

            Button(action: onToday) {
                Text("Today")
            }
            .buttonStyle(LiquidGlassTodayButtonStyle())
            .accessibilityLabel("Jump to today")

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(LiquidGlassCircleButtonStyle())
            .accessibilityLabel("Next period")
        }
    }
}

// MARK: - View

struct HeartZonesView: View {
    @StateObject private var engine = HealthStateEngine.shared

    enum TimeFilter: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"

        var dayCount: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 28
            }
        }
    }

    enum AggregationMode: String, CaseIterable {
        case total = "Total"
        case average = "Avg/Session"
    }

    enum BaselineWindow: String, CaseIterable {
        case week7 = "7d"
        case month28 = "28d"

        var days: Int {
            switch self {
            case .week7: return 7
            case .month28: return 28
            }
        }
    }

    @StateObject private var zoneEngine = HeartZoneEngine()
    @State private var timeFilter: TimeFilter = .day
    @State private var selectedDate = Date()
    @State private var sportFilter: String?
    @State private var aggregationMode: AggregationMode = .total
    @State private var baselineWindow: BaselineWindow = .week7
    @State private var expandedWorkoutID: UUID?
    @State private var animationPhase: Double = 0

    private var calendar: Calendar { Calendar.current }

    private var windowStart: Date {
        let anchor = calendar.startOfDay(for: selectedDate)
        switch timeFilter {
        case .day: return anchor
        case .week: return calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        case .month: return calendar.date(byAdding: .day, value: -27, to: anchor) ?? anchor
        }
    }

    private var windowEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
    }

    private var baselineStart: Date {
        calendar.date(byAdding: .day, value: -baselineWindow.days, to: windowStart) ?? windowStart
    }

    private var filteredEntries: [ZoneBreakdownEntry] {
        zoneEngine.entries.filter { entry in
            entry.workoutDate >= windowStart && entry.workoutDate < windowEnd &&
            (sportFilter == nil || entry.sport == sportFilter)
        }
    }

    private var baselineEntries: [ZoneBreakdownEntry] {
        zoneEngine.entries.filter { entry in
            entry.workoutDate >= baselineStart && entry.workoutDate < windowStart &&
            (sportFilter == nil || entry.sport == sportFilter)
        }
    }

    var body: some View {
        scrollableContent
            .background {
                GradientBackgrounds()
                    .kineticPulseGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            }
            .navigationTitle("Heart Zones")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HeartZonesDateToolbarButtons(
                        onPrev: { navigateDate(by: -1) },
                        onToday: { selectedDate = Date() },
                        onNext: { navigateDate(by: 1) }
                    )
                }
            }
            .tint(.orange)
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlToday)) { _ in
                selectedDate = Date()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlPrevious)) { _ in
                navigateDate(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlNext)) { _ in
                navigateDate(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter1)) { _ in
                timeFilter = .day
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter2)) { _ in
                timeFilter = .week
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter3)) { _ in
                timeFilter = .month
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlHeartZonesSportSlot)) { output in
                guard let slot = output.userInfo?["slot"] as? Int else { return }
                applyHeartZonesSportShortcutSlot(slot)
            }
            .task(id: taskID) {
                let loadStart = calendar.date(byAdding: .day, value: -(28 + baselineWindow.days), to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
                await zoneEngine.load(engine: engine, from: loadStart, to: windowEnd)
            }
    }

    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(dateRangeLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                filterBar
                sportFilterBar

                if zoneEngine.isLoading {
                    ProgressView("Resolving zone profiles...")
                        .tint(.orange)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if filteredEntries.isEmpty {
                    emptyState
                } else {
                    aggregationControls
                    zoneSummaryCards
                    zoneDistributionChart
                    workoutList
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private var taskID: String {
        "\(selectedDate.timeIntervalSince1970)-\(timeFilter.rawValue)-\(baselineWindow.rawValue)"
    }

    private var dateRangeLabel: String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        switch timeFilter {
        case .day:
            return selectedDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(windowStart.formatted(fmt)) – \(selectedDate.formatted(fmt))"
        case .month:
            return "\(windowStart.formatted(fmt)) – \(selectedDate.formatted(fmt))"
        }
    }

    private func navigateDate(by direction: Int) {
        let unit: Calendar.Component = timeFilter == .month ? .day : .day
        let amount = direction * timeFilter.dayCount
        if let newDate = calendar.date(byAdding: unit, value: amount, to: selectedDate) {
            selectedDate = min(newDate, Date())
        }
    }

    private func applyHeartZonesSportShortcutSlot(_ slot: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            if slot == 0 {
                sportFilter = nil
                return
            }
            let names = zoneEngine.resolvedSportNames
            let idx = slot - 1
            guard names.indices.contains(idx) else { return }
            sportFilter = names[idx]
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 10) {
            ForEach(TimeFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { timeFilter = filter }
                } label: {
                    Text(filter.rawValue)
                }
                .buttonStyle(LiquidGlassSegmentButtonStyle(isSelected: timeFilter == filter))
            }
        }
    }

    private var sportFilterBar: some View {
        Group {
            if zoneEngine.resolvedSportNames.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        sportChip(label: "All Sports", sport: nil)
                        ForEach(zoneEngine.resolvedSportNames, id: \.self) { sport in
                            sportChip(label: sport, sport: sport)
                        }
                    }
                }
            }
        }
    }

    private func sportChip(label: String, sport: String?) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { sportFilter = sport }
        } label: {
            Text(label)
        }
        .buttonStyle(LiquidGlassSportChipStyle(isSelected: sportFilter == sport))
    }

    // MARK: - Aggregation Controls

    private var aggregationControls: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $aggregationMode) {
                ForEach(AggregationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(.orange)

            Picker("Baseline", selection: $baselineWindow) {
                ForEach(BaselineWindow.allCases, id: \.self) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .tint(.orange)
        }
        .padding(12)
        .background {
            GlassRoundedRectBackground(cornerRadius: 28)
        }
    }

    // MARK: - Summary Cards

    private var zoneSummaryCards: some View {
        let zoneTotals = computeZoneTotals(from: filteredEntries)
        let baseline = computeBaseline(from: baselineEntries)
        let sessionCount = filteredEntries.count
        let zoneNumbers = Array(zoneTotals.keys).sorted()

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                summaryPill(
                    title: "Sessions",
                    value: "\(sessionCount)",
                    subtitle: sportFilter ?? "All Sports"
                )
                summaryPill(
                    title: "Total Time",
                    value: formatMinutes(zoneTotals.values.reduce(0, +)),
                    subtitle: "in zones"
                )
            }

            HStack(spacing: 8) {
                ForEach(zoneNumbers, id: \.self) { zoneNum in
                    let totalMin = zoneTotals[zoneNum] ?? 0
                    let displayValue: Double = aggregationMode == .average && sessionCount > 0
                        ? totalMin / Double(sessionCount)
                        : totalMin
                    let baselineValue: Double? = {
                        guard let bl = baseline else { return nil }
                        return aggregationMode == .average
                            ? bl.perZoneAvgMinutes[zoneNum]
                            : bl.perZoneTotalMinutes[zoneNum]
                    }()
                    let delta: Double? = baselineValue.flatMap { bv in
                        guard bv > 0 else { return nil }
                        return ((displayValue - bv) / bv) * 100
                    }

                    let color = filteredEntries.first?.zones.first(where: { $0.zoneNumber == zoneNum })?.color ?? .gray

                    zoneCard(
                        zoneNum: zoneNum,
                        minutes: displayValue,
                        delta: delta,
                        color: color
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryPill(title: String, value: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background {
            GlassRoundedRectBackground(cornerRadius: 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func zoneCard(zoneNum: Int, minutes: Double, delta: Double?, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("Z\(zoneNum)")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(formatMinutes(minutes))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
            if let delta {
                HStack(spacing: 2) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(abs(delta), specifier: "%.0f")%")
                        .font(.caption2.bold())
                }
                .foregroundStyle(delta >= 0 ? .green : .red)
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background {
            ZStack {
                GlassRoundedRectBackground(cornerRadius: 24)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(color.opacity(0.14))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [color.opacity(0.45), color.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Distribution Chart

    private var zoneDistributionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chartTitle)
                .font(.headline)
                .foregroundStyle(.white)

            let chartData = buildChartData()
            if chartData.isEmpty {
                Text("No zone data available")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(chartData, id: \.id) { bar in
                        BarMark(
                            x: .value("Date", bar.label),
                            y: .value("Minutes", bar.minutes)
                        )
                        .foregroundStyle(bar.color)
                    }
                }
                .chartYAxisLabel("min")
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.white.opacity(0.15))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .frame(height: 220)
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background {
            GlassRoundedRectBackground(cornerRadius: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var chartTitle: String {
        let modeLabel = aggregationMode == .total ? "Total" : "Average"
        switch timeFilter {
        case .day: return "\(modeLabel) Time per Zone"
        case .week: return "\(modeLabel) Daily Zone Distribution"
        case .month: return "\(modeLabel) Weekly Zone Distribution"
        }
    }

    struct ChartBar: Identifiable {
        let id = UUID()
        let label: String
        let zoneNumber: Int
        let minutes: Double
        let color: Color
    }

    private func buildChartData() -> [ChartBar] {
        var bars: [ChartBar] = []
        let colorMap = zoneColorMap()

        switch timeFilter {
        case .day:
            let totals = computeZoneTotals(from: filteredEntries)
            let sessionCount = max(filteredEntries.count, 1)
            for zoneNum in totals.keys.sorted() {
                let min = aggregationMode == .average
                    ? totals[zoneNum, default: 0] / Double(sessionCount)
                    : totals[zoneNum, default: 0]
                bars.append(ChartBar(label: "Z\(zoneNum)", zoneNumber: zoneNum, minutes: min, color: colorMap[zoneNum] ?? .gray))
            }

        case .week:
            let dailyAggs = aggregateByDay(entries: filteredEntries)
            for agg in dailyAggs.sorted(by: { $0.date < $1.date }) {
                let dayLabel = agg.date.formatted(.dateTime.weekday(.abbreviated))
                let divisor = aggregationMode == .average && agg.sessionCount > 0 ? Double(agg.sessionCount) : 1.0
                for zoneNum in agg.zones.keys.sorted() {
                    bars.append(ChartBar(
                        label: dayLabel,
                        zoneNumber: zoneNum,
                        minutes: agg.zones[zoneNum, default: 0] / divisor,
                        color: colorMap[zoneNum] ?? .gray
                    ))
                }
            }

        case .month:
            let weeklyAggs = aggregateByWeek(entries: filteredEntries)
            for (weekLabel, zones, sessionCount) in weeklyAggs {
                let divisor = aggregationMode == .average && sessionCount > 0 ? Double(sessionCount) : 1.0
                for zoneNum in zones.keys.sorted() {
                    bars.append(ChartBar(
                        label: weekLabel,
                        zoneNumber: zoneNum,
                        minutes: zones[zoneNum, default: 0] / divisor,
                        color: colorMap[zoneNum] ?? .gray
                    ))
                }
            }
        }

        return bars
    }

    // MARK: - Workout List

    private var workoutList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workouts")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(filteredEntries) { entry in
                workoutRow(entry)
            }
        }
    }

    private func workoutRow(_ entry: ZoneBreakdownEntry) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedWorkoutID = expandedWorkoutID == entry.workoutUUID ? nil : entry.workoutUUID
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.sport)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text(entry.workoutDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()

                    miniZoneBar(entry.zones, totalDuration: entry.duration)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatMinutes(entry.duration / 60.0))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.white)
                        if let avg = entry.avgHR {
                            Text("\(Int(avg)) bpm")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                        .rotationEffect(.degrees(expandedWorkoutID == entry.workoutUUID ? 180 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            if expandedWorkoutID == entry.workoutUUID {
                expandedZoneDetail(entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            GlassRoundedRectBackground(cornerRadius: 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func miniZoneBar(_ zones: [ZoneTimeEntry], totalDuration: TimeInterval) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(zones.filter { $0.seconds > 0 }) { zone in
                    let fraction = totalDuration > 0 ? zone.seconds / totalDuration : 0
                    Rectangle()
                        .fill(zone.color)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
        }
        .frame(width: 60, height: 8)
        .clipShape(Capsule())
    }

    private func expandedZoneDetail(_ entry: ZoneBreakdownEntry) -> some View {
        VStack(spacing: 6) {
            ForEach(entry.zones) { zone in
                HStack {
                    Circle().fill(zone.color).frame(width: 8, height: 8)
                    Text(zone.zoneName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(Int(zone.lowerBound))–\(Int(zone.upperBound)) bpm")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                    Text(formatDuration(zone.seconds))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                if let peak = entry.peakHR {
                    Label("Peak \(Int(peak)) bpm", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
                Spacer()
                Text("Schema: \(entry.profile.schema.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                if let maxHR = entry.profile.maxHR {
                    Text("Max HR: \(Int(maxHR))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.4))
            Text("No workouts with HR data")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
            Text("Complete a workout with heart rate monitoring to see zone breakdowns here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Helpers

    private func computeZoneTotals(from entries: [ZoneBreakdownEntry]) -> [Int: Double] {
        var totals: [Int: Double] = [:]
        for entry in entries {
            for zone in entry.zones {
                totals[zone.zoneNumber, default: 0] += zone.minutes
            }
        }
        return totals
    }

    private func computeBaseline(from entries: [ZoneBreakdownEntry]) -> BaselineZoneStats? {
        guard !entries.isEmpty else { return nil }
        let totals = computeZoneTotals(from: entries)
        let sessionCount = entries.count
        let avgPerSession = totals.mapValues { $0 / Double(sessionCount) }
        let days = Set(entries.map { calendar.startOfDay(for: $0.workoutDate) }).count
        return BaselineZoneStats(
            windowLabel: baselineWindow.rawValue,
            perZoneAvgMinutes: avgPerSession,
            perZoneTotalMinutes: totals,
            sessionCount: sessionCount,
            dayCount: days
        )
    }

    private func aggregateByDay(entries: [ZoneBreakdownEntry]) -> [DailyZoneAggregate] {
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.workoutDate) }
        return grouped.map { date, dayEntries in
            var zones: [Int: Double] = [:]
            for entry in dayEntries {
                for zone in entry.zones {
                    zones[zone.zoneNumber, default: 0] += zone.minutes
                }
            }
            return DailyZoneAggregate(
                date: date,
                sport: sportFilter,
                sessionCount: dayEntries.count,
                zones: zones,
                totalMinutes: zones.values.reduce(0, +)
            )
        }
    }

    private func aggregateByWeek(entries: [ZoneBreakdownEntry]) -> [(String, [Int: Double], Int)] {
        let grouped = Dictionary(grouping: entries) { entry -> Int in
            calendar.component(.weekOfYear, from: entry.workoutDate)
        }
        return grouped.sorted { $0.key < $1.key }.map { weekNum, weekEntries in
            var zones: [Int: Double] = [:]
            for entry in weekEntries {
                for zone in entry.zones {
                    zones[zone.zoneNumber, default: 0] += zone.minutes
                }
            }
            let earliest = weekEntries.map(\.workoutDate).min() ?? Date()
            let label = "W\(earliest.formatted(.dateTime.month(.abbreviated).day()))"
            return (label, zones, weekEntries.count)
        }
    }

    private func zoneColorMap() -> [Int: Color] {
        var map: [Int: Color] = [:]
        for entry in zoneEngine.entries {
            for zone in entry.zones {
                if map[zone.zoneNumber] == nil {
                    map[zone.zoneNumber] = zone.color
                }
            }
        }
        if map.isEmpty {
            map = [1: .blue, 2: .green, 3: .yellow, 4: .orange, 5: .red]
        }
        return map
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let h = Int(minutes) / 60
            let m = Int(minutes) % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(Int(minutes.rounded()))m"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%dm %02ds", m, s)
    }
}
