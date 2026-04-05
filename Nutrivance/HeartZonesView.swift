import SwiftUI
import UIKit
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
    /// Shared instance so `HeartZonesView` keeps zone data when iPad split view / Stage Manager recreates the detail `NavigationStack` (a new `@StateObject` would otherwise flash loading and re-resolve every workout).
    static let shared = HeartZoneEngine()

    @Published var entries: [ZoneBreakdownEntry] = []
    @Published var isLoading = false
    @Published var resolvedSportNames: [String] = []

    private let hkm = HealthKitManager()
    /// Last completed fetch range; used to avoid redundant async work when `.task` re-runs after view re-insertion with the same parameters.
    private var lastCompletedLoadKey: String?

    func load(engine: HealthStateEngine, from start: Date, to end: Date) async {
        let key = Self.loadKey(from: start, to: end)
        if key == lastCompletedLoadKey {
            return
        }

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
        lastCompletedLoadKey = key
    }

    private static func loadKey(from start: Date, to end: Date) -> String {
        "\(start.timeIntervalSince1970)_\(end.timeIntervalSince1970)"
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

// MARK: - Heart rate recovery (1D/1W/1M + sport only; not tied to zone Total/Avg or baseline pickers)

@MainActor
final class HeartZonesHRRLoader: ObservableObject {
    static let shared = HeartZonesHRRLoader()

    @Published private(set) var resultsByUUID: [UUID: HeartRateRecoveryResult] = [:]
    @Published private(set) var isLoading = false

    private var lastKey: String?

    func load(pairs: [(workout: HKWorkout, analytics: WorkoutAnalytics)], restingHRBpm: Double) async {
        if pairs.isEmpty {
            lastKey = ""
            resultsByUUID = [:]
            return
        }
        let restingKey = Int(restingHRBpm.rounded())
        let key = "\(restingKey)|" + pairs
            .map { "\($0.workout.uuid.uuidString)-\($0.workout.startDate.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        if key == lastKey, resultsByUUID.count == pairs.count { return }
        lastKey = key
        isLoading = true
        defer { isLoading = false }
        var map: [UUID: HeartRateRecoveryResult] = [:]
        for pair in pairs {
            let uuid = pair.workout.uuid
            if let cached = HRRAnalysisCache.shared.result(for: uuid),
               cached.restingHRUsed.map({ Int($0.rounded()) }) == Optional(restingKey) {
                map[uuid] = cached
                continue
            }
            let r = HeartRateRecoveryAnalysis.analyze(workout: pair.workout, analytics: pair.analytics, restingHRBpm: restingHRBpm)
            HRRAnalysisCache.shared.store(r, workoutUUID: uuid)
            map[uuid] = r
        }
        resultsByUUID = map
    }
}

// MARK: - Liquid glass surfaces

private struct GlassCapsuleBackground: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(isSelected ? Color.orange.opacity(0.44) : Color.primary.opacity(0.06))
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [Color.primary.opacity(0.28), Color.primary.opacity(0.06)],
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
            Circle().fill(Color.primary.opacity(0.06))
            Circle().strokeBorder(
                LinearGradient(
                    colors: [Color.primary.opacity(0.25), Color.primary.opacity(0.08)],
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
                .fill(Color.primary.opacity(0.06))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.22), Color.primary.opacity(0.06)],
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
            .foregroundStyle(isSelected ? Color.black : Color.primary)
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
                    Capsule().fill(isSelected ? Color.orange.opacity(0.32) : Color.primary.opacity(0.06))
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.orange.opacity(0.65), Color.orange.opacity(0.2)]
                                : [Color.primary.opacity(0.22), Color.primary.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
            }
            .foregroundStyle(isSelected ? Color.orange : Color.primary)
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
            .catalystDesktopFocusable()

            Button(action: onToday) {
                Text("Today")
            }
            .buttonStyle(LiquidGlassTodayButtonStyle())
            .accessibilityLabel("Jump to today")
            .catalystDesktopFocusable()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(LiquidGlassCircleButtonStyle())
            .accessibilityLabel("Next period")
            .catalystDesktopFocusable()
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

    /// Survives iPad `NavigationSplitView` / `NavigationStack` tearing down the detail column so filters, date, and `.task(id:)` stay stable (avoids full reload + reset UI).
    @MainActor
    final class ScreenState: ObservableObject {
        static let shared = ScreenState()

        @Published var timeFilter: TimeFilter = .day
        @Published var selectedDate: Date = Date()
        @Published var sportFilter: String?
        @Published var aggregationMode: AggregationMode = .total
        @Published var baselineWindow: BaselineWindow = .week7
        @Published var expandedWorkoutID: UUID?
        @Published var selectedChartZoneNumber: Int?

        private init() {}
    }

    @ObservedObject private var zoneEngine = HeartZoneEngine.shared
    @ObservedObject private var hrrLoader = HeartZonesHRRLoader.shared
    @ObservedObject private var ui = ScreenState.shared
    @State private var animationPhase: Double = 0

    private var calendar: Calendar { Calendar.current }

    private var windowStart: Date {
        let anchor = calendar.startOfDay(for: ui.selectedDate)
        switch ui.timeFilter {
        case .day: return anchor
        case .week: return calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        case .month: return calendar.date(byAdding: .day, value: -27, to: anchor) ?? anchor
        }
    }

    private var windowEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: ui.selectedDate)) ?? ui.selectedDate
    }

    private var baselineStart: Date {
        calendar.date(byAdding: .day, value: -ui.baselineWindow.days, to: windowStart) ?? windowStart
    }

    private var filteredEntries: [ZoneBreakdownEntry] {
        let sportOk = { (entry: ZoneBreakdownEntry) in ui.sportFilter == nil || entry.sport == ui.sportFilter }
        switch ui.timeFilter {
        case .day:
            // Calendar-day membership so 1D Z4/Z5 totals cannot pick up adjacent days at boundaries.
            return zoneEngine.entries.filter { entry in
                sportOk(entry) && calendar.isDate(entry.workoutDate, inSameDayAs: ui.selectedDate)
            }
        case .week, .month:
            return zoneEngine.entries.filter { entry in
                entry.workoutDate >= windowStart && entry.workoutDate < windowEnd && sportOk(entry)
            }
        }
    }

    private var baselineEntries: [ZoneBreakdownEntry] {
        zoneEngine.entries.filter { entry in
            entry.workoutDate >= baselineStart && entry.workoutDate < windowStart &&
            (ui.sportFilter == nil || entry.sport == ui.sportFilter)
        }
    }

    /// Workouts with HR in the visible window and sport filter (independent of zone aggregation controls).
    private var hrrWorkoutPairs: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let sportOK: (HKWorkout) -> Bool = { w in
            ui.sportFilter == nil || w.workoutActivityType.name == ui.sportFilter
        }
        return engine.workoutAnalytics.compactMap { pair -> (HKWorkout, WorkoutAnalytics)? in
            let w = pair.workout
            guard w.startDate >= windowStart && w.startDate < windowEnd else { return nil }
            guard sportOK(w) else { return nil }
            let a = pair.analytics
            guard !a.heartRates.isEmpty || !a.postWorkoutHRSeries.isEmpty else { return nil }
            return (w, a)
        }
        .sorted { $0.workout.startDate > $1.workout.startDate }
    }

    private var hrrTaskID: String {
        "\(ui.selectedDate.timeIntervalSince1970)-\(ui.timeFilter.rawValue)-\(ui.sportFilter ?? "all")-\(hrrWorkoutPairs.map(\.workout.uuid.uuidString).joined(separator: ","))"
    }

    var body: some View {
        scrollableContent
            .background {
                GradientBackgrounds()
                    .burningGradientFull(animationPhase: $animationPhase)
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
                        onToday: { ui.selectedDate = Date() },
                        onNext: { navigateDate(by: 1) }
                    )
                }
            }
            .tint(.orange)
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlToday)) { _ in
                ui.selectedDate = Date()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlPrevious)) { _ in
                navigateDate(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlNext)) { _ in
                navigateDate(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter1)) { _ in
                ui.timeFilter = .day
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter2)) { _ in
                ui.timeFilter = .week
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter3)) { _ in
                ui.timeFilter = .month
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlHeartZonesSportSlot)) { output in
                guard let slot = output.userInfo?["slot"] as? Int else { return }
                applyHeartZonesSportShortcutSlot(slot)
            }
            .task(id: taskID) {
                let loadStart = calendar.date(byAdding: .day, value: -(28 + ui.baselineWindow.days), to: calendar.startOfDay(for: ui.selectedDate)) ?? ui.selectedDate
                await zoneEngine.load(engine: engine, from: loadStart, to: windowEnd)
            }
            .task(id: hrrTaskID) {
                let resting = await HealthKitManager().fetchRestingHeartRateLatest()
                CoachHRRRestingGate.shared.update(resting)
                await hrrLoader.load(pairs: hrrWorkoutPairs, restingHRBpm: resting)
            }
    }

    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(dateRangeLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                filterBar
                sportFilterBar

                if zoneEngine.isLoading {
                    ProgressView("Resolving zone profiles...")
                        .tint(.orange)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if filteredEntries.isEmpty && hrrWorkoutPairs.isEmpty {
                    emptyState
                } else {
                    if !filteredEntries.isEmpty {
                        aggregationControls
                        zoneSummaryCards
                        zoneDistributionChart
                        workoutList
                    } else {
                        Text("No zone breakdown in this range (HR samples may be missing for zone math). Heart rate recovery below still uses raw HR when available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    heartRateRecoverySection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private var taskID: String {
        "\(ui.selectedDate.timeIntervalSince1970)-\(ui.timeFilter.rawValue)-\(ui.baselineWindow.rawValue)"
    }

    /// Shown after trend %, e.g. `today vs 28d` — visible range label vs baseline picker (`7d` / `28d`).
    private var zoneTrendComparisonCaption: String {
        let currentLabel: String
        switch ui.timeFilter {
        case .day: currentLabel = "selected day"
        case .week: currentLabel = "visible week"
        case .month: currentLabel = "visible 28d"
        }
        return "\(currentLabel) vs prior \(ui.baselineWindow.rawValue) baseline"
    }

    private var dateRangeLabel: String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        switch ui.timeFilter {
        case .day:
            return ui.selectedDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(windowStart.formatted(fmt)) – \(ui.selectedDate.formatted(fmt))"
        case .month:
            return "\(windowStart.formatted(fmt)) – \(ui.selectedDate.formatted(fmt))"
        }
    }

    private func navigateDate(by direction: Int) {
        let unit: Calendar.Component = ui.timeFilter == .month ? .day : .day
        let amount = direction * ui.timeFilter.dayCount
        if let newDate = calendar.date(byAdding: unit, value: amount, to: ui.selectedDate) {
            ui.selectedDate = min(newDate, Date())
        }
    }

    private func applyHeartZonesSportShortcutSlot(_ slot: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            if slot == 0 {
                ui.sportFilter = nil
                return
            }
            let names = zoneEngine.resolvedSportNames
            let idx = slot - 1
            guard names.indices.contains(idx) else { return }
            ui.sportFilter = names[idx]
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 10) {
            ForEach(TimeFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { ui.timeFilter = filter }
                } label: {
                    Text(filter.rawValue)
                }
                .buttonStyle(LiquidGlassSegmentButtonStyle(isSelected: ui.timeFilter == filter))
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { ui.sportFilter = sport }
        } label: {
            Text(label)
        }
        .buttonStyle(LiquidGlassSportChipStyle(isSelected: ui.sportFilter == sport))
        .catalystDesktopFocusable()
    }

    // MARK: - Aggregation Controls

    private var aggregationControls: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $ui.aggregationMode) {
                ForEach(AggregationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(.orange)
            .catalystDesktopFocusable()

            Picker("Baseline", selection: $ui.baselineWindow) {
                ForEach(BaselineWindow.allCases, id: \.self) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .tint(.orange)
            .catalystDesktopFocusable()
        }
        .padding(12)
        .background {
            GlassRoundedRectBackground(cornerRadius: 28)
        }
    }

    // MARK: - Summary Cards

    /// Zone tiles share width evenly when the row fits; below threshold the row scrolls horizontally with wide tiles.
    private enum ZoneCardRowLayout {
        static let spacing: CGFloat = 8
        /// Used only for scroll-vs-equal **threshold** math (not scroll tile width).
        static let thresholdUnitWidth: CGFloat = 92
        static let estimatedRowHeight: CGFloat = 144
        /// Require this much *extra* width (vs bare tile minimum) before using equal-width row; below that use horizontal scroll.
        static let equalLayoutWidthMultiplier: CGFloat = 1.75
        /// Horizontal-scroll cards: wide tiles; scale with container, clamped for phone vs iPad.
        static let scrollCardMinWidth: CGFloat = 168
        static let scrollCardMaxWidth: CGFloat = 280
        static let scrollCardWidthFraction: CGFloat = 0.50
    }

    private var zoneSummaryCards: some View {
        let zoneTotals = computeZoneTotals(from: filteredEntries)
        let baseline = computeBaseline(from: baselineEntries)
        let sessionCount = filteredEntries.count
        let zoneNumbers = Array(zoneTotals.keys).sorted()

        return VStack(spacing: 8) {
            HStack(spacing: ZoneCardRowLayout.spacing) {
                summaryPill(
                    title: "Sessions",
                    value: "\(sessionCount)",
                    subtitle: ui.sportFilter ?? "All Sports"
                )
                summaryPill(
                    title: "Total Time",
                    value: formatMinutes(zoneTotals.values.reduce(0, +)),
                    subtitle: "in zones"
                )
            }

            if !zoneNumbers.isEmpty {
                GeometryReader { proxy in
                    let spacing = ZoneCardRowLayout.spacing
                    let count = zoneNumbers.count
                    let bareMinimumWidth =
                        CGFloat(count) * ZoneCardRowLayout.thresholdUnitWidth + CGFloat(max(count - 1, 0)) * spacing
                    let widthToUseEqualRow = bareMinimumWidth * ZoneCardRowLayout.equalLayoutWidthMultiplier
                    let useScroll = proxy.size.width < widthToUseEqualRow
                    let scrollCardWidth = min(
                        ZoneCardRowLayout.scrollCardMaxWidth,
                        max(
                            ZoneCardRowLayout.scrollCardMinWidth,
                            proxy.size.width * ZoneCardRowLayout.scrollCardWidthFraction
                        )
                    )

                    Group {
                        if useScroll {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: spacing) {
                                    ForEach(zoneNumbers, id: \.self) { zoneNum in
                                        zoneCardCell(
                                            zoneNum: zoneNum,
                                            zoneTotals: zoneTotals,
                                            baseline: baseline,
                                            sessionCount: sessionCount
                                        )
                                        .frame(width: scrollCardWidth)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: spacing) {
                                ForEach(zoneNumbers, id: \.self) { zoneNum in
                                    zoneCardCell(
                                        zoneNum: zoneNum,
                                        zoneTotals: zoneTotals,
                                        baseline: baseline,
                                        sessionCount: sessionCount
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: ZoneCardRowLayout.estimatedRowHeight)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func zoneCardCell(
        zoneNum: Int,
        zoneTotals: [Int: Double],
        baseline: BaselineZoneStats?,
        sessionCount: Int
    ) -> some View {
        let totalMin = zoneTotals[zoneNum] ?? 0
        let displayValue: Double = ui.aggregationMode == .average && sessionCount > 0
            ? totalMin / Double(sessionCount)
            : totalMin
        let delta = zoneTrendPercentDelta(
            zoneNum: zoneNum,
            zoneMinuteTotal: totalMin,
            baseline: baseline,
            sessionCount: sessionCount
        )
        let color = filteredEntries.first?.zones.first(where: { $0.zoneNumber == zoneNum })?.color ?? .gray

        zoneCard(
            zoneNum: zoneNum,
            minutes: displayValue,
            delta: delta,
            color: color,
            isSelected: ui.selectedChartZoneNumber == zoneNum
        ) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                ui.selectedChartZoneNumber = ui.selectedChartZoneNumber == zoneNum ? nil : zoneNum
            }
        }
    }

    private func summaryPill(title: String, value: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background {
            GlassRoundedRectBackground(cornerRadius: 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func zoneCard(
        zoneNum: Int,
        minutes: Double,
        delta: Double?,
        color: Color,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text("Z\(zoneNum)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Text(formatMinutes(minutes))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let delta {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(delta >= 0 ? .green : .red)
                        Text(String(format: "%+.0f%%", delta))
                            .font(.caption2.bold())
                            .foregroundStyle(delta >= 0 ? .green : .red)
                        Text("(\(zoneTrendComparisonCaption))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
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
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(color.opacity(0.95), lineWidth: 2.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Distribution Chart

    private var zoneDistributionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(ui.selectedChartZoneNumber.map { focusedZoneChartTitle(zone: $0) } ?? chartTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if ui.selectedChartZoneNumber != nil {
                    Button("All zones") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            ui.selectedChartZoneNumber = nil
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .catalystDesktopFocusable()
                }
            }

            if let z = ui.selectedChartZoneNumber {
                focusedZoneComparisonChart(zone: z)
            } else {
                let chartData = buildChartData()
                if chartData.isEmpty {
                    Text("No zone data available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    Chart {
                        ForEach(chartData, id: \.id) { bar in
                            BarMark(
                                x: .value("Date", bar.label),
                                y: .value("Minutes", bar.minutes)
                            )
                            .foregroundStyle(bar.color.opacity(0.52))
                            .cornerRadius(10, style: .continuous)
                        }
                    }
                    .chartYAxisLabel(position: .leading, alignment: .center) {
                        Text("min")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                                .foregroundStyle(Color.primary.opacity(0.12))
                            AxisValueLabel()
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel()
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                    .frame(height: 220)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .background {
            GlassRoundedRectBackground(cornerRadius: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func focusedZoneChartTitle(zone: Int) -> String {
        let modeLabel = ui.aggregationMode == .total ? "Total" : "Avg"
        switch ui.timeFilter {
        case .day:
            return "Z\(zone) \(modeLabel) vs \(ui.baselineWindow.rawValue)"
        case .week:
            return "Z\(zone) daily \(modeLabel) vs \(ui.baselineWindow.rawValue)"
        case .month:
            return "Z\(zone) weekly \(modeLabel) vs \(ui.baselineWindow.rawValue)"
        }
    }

    @ViewBuilder
    private func focusedZoneComparisonChart(zone: Int) -> some View {
        let items = buildFocusedZoneChartItems(zone: zone)
        let baselineY = baselineReferenceLineMinutes(forZone: zone)
        let theme = zoneColorMap()[zone] ?? .gray

        if items.isEmpty {
            Text("No data for Z\(zone) in this range")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            Chart {
                ForEach(items) { item in
                    if baselineY > 0.25,
                       abs(item.current - baselineY) > 0.25 {
                        RectangleMark(
                            x: .value("Period", item.label),
                            yStart: .value("diffLo", min(item.current, baselineY)),
                            yEnd: .value("diffHi", max(item.current, baselineY))
                        )
                        .foregroundStyle(theme.opacity(0.22))
                    }

                    BarMark(
                        x: .value("Period", item.label),
                        y: .value("Minutes", item.current)
                    )
                    .foregroundStyle(theme.opacity(0.52))
                    .cornerRadius(10, style: .continuous)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Text(
                            baselineY > 0.25
                                ? formatSignedMinutesDelta(item.current - baselineY)
                                : formatMinutes(item.current)
                        )
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(theme)
                    }
                }

                if baselineY > 0.25 {
                    RuleMark(y: .value("Baseline", baselineY))
                        .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [6, 5]))
                        .foregroundStyle(theme.opacity(0.92))
                }
            }
            .chartYAxisLabel(position: .leading, alignment: .center) {
                Text("min")
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Color.primary.opacity(0.12))
                    AxisValueLabel()
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            .frame(height: 240)
            .padding(.vertical, 4)
        }
    }

    /// Horizontal baseline in the same units as focused bar heights (totals or per-session, per day/week bucket).
    private func baselineReferenceLineMinutes(forZone zone: Int) -> Double {
        guard let bl = computeBaseline(from: baselineEntries) else { return 0 }
        let bTotal = bl.perZoneTotalMinutes[zone] ?? 0
        switch ui.aggregationMode {
        case .average:
            guard bl.sessionCount > 0 else { return 0 }
            return bTotal / Double(bl.sessionCount)
        case .total:
            switch ui.timeFilter {
            case .day, .week:
                return bTotal / Double(max(1, ui.baselineWindow.days))
            case .month:
                let baselineWeeks = max(1, ui.baselineWindow.days / 7)
                return bTotal / Double(baselineWeeks)
            }
        }
    }

    private struct FocusedZoneChartItem: Identifiable {
        let id = UUID()
        let label: String
        let current: Double
    }

    private func buildFocusedZoneChartItems(zone: Int) -> [FocusedZoneChartItem] {
        let sessionCount = max(filteredEntries.count, 1)
        var items: [FocusedZoneChartItem] = []

        switch ui.timeFilter {
        case .day:
            let totals = computeZoneTotals(from: filteredEntries)
            let raw = totals[zone] ?? 0
            let current: Double = ui.aggregationMode == .average && sessionCount > 0
                ? raw / Double(sessionCount)
                : raw
            let label = ui.selectedDate.formatted(date: .abbreviated, time: .omitted)
            items.append(FocusedZoneChartItem(label: label, current: current))

        case .week:
            let dailyAggs = aggregateByDay(entries: filteredEntries).sorted(by: { $0.date < $1.date })
            for agg in dailyAggs {
                let dayLabel = agg.date.formatted(.dateTime.weekday(.abbreviated))
                let raw = agg.zones[zone] ?? 0
                let divisor = ui.aggregationMode == .average && agg.sessionCount > 0 ? Double(agg.sessionCount) : 1.0
                items.append(FocusedZoneChartItem(label: dayLabel, current: raw / divisor))
            }

        case .month:
            let weeklyAggs = aggregateByWeek(entries: filteredEntries)
            for (weekLabel, zones, weekSessionCount) in weeklyAggs {
                let raw = zones[zone] ?? 0
                let divisor = ui.aggregationMode == .average && weekSessionCount > 0 ? Double(weekSessionCount) : 1.0
                items.append(FocusedZoneChartItem(label: weekLabel, current: raw / divisor))
            }
        }

        return items
    }

    private func formatSignedMinutesDelta(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "0m" }
        let sign = delta > 0 ? "+" : "−"
        return sign + formatMinutes(abs(delta))
    }

    private var chartTitle: String {
        let modeLabel = ui.aggregationMode == .total ? "Total" : "Average"
        switch ui.timeFilter {
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

        switch ui.timeFilter {
        case .day:
            let totals = computeZoneTotals(from: filteredEntries)
            let sessionCount = max(filteredEntries.count, 1)
            for zoneNum in totals.keys.sorted() {
                let min = ui.aggregationMode == .average
                    ? totals[zoneNum, default: 0] / Double(sessionCount)
                    : totals[zoneNum, default: 0]
                bars.append(ChartBar(label: "Z\(zoneNum)", zoneNumber: zoneNum, minutes: min, color: colorMap[zoneNum] ?? .gray))
            }

        case .week:
            let dailyAggs = aggregateByDay(entries: filteredEntries)
            for agg in dailyAggs.sorted(by: { $0.date < $1.date }) {
                let dayLabel = agg.date.formatted(.dateTime.weekday(.abbreviated))
                let divisor = ui.aggregationMode == .average && agg.sessionCount > 0 ? Double(agg.sessionCount) : 1.0
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
                let divisor = ui.aggregationMode == .average && sessionCount > 0 ? Double(sessionCount) : 1.0
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
                .foregroundStyle(.primary)

            ForEach(filteredEntries) { entry in
                workoutRow(entry)
            }
        }
    }

    private func workoutRow(_ entry: ZoneBreakdownEntry) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    ui.expandedWorkoutID = ui.expandedWorkoutID == entry.workoutUUID ? nil : entry.workoutUUID
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.sport)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(entry.workoutDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    miniZoneBar(entry.zones, totalDuration: entry.duration)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatMinutes(entry.duration / 60.0))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.primary)
                        if let avg = entry.avgHR {
                            Text("\(Int(avg)) bpm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(ui.expandedWorkoutID == entry.workoutUUID ? 180 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            if ui.expandedWorkoutID == entry.workoutUUID {
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(zone.lowerBound))–\(Int(zone.upperBound)) bpm")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(formatDuration(zone.seconds))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }

            Divider().background(Color.primary.opacity(0.12))

            HStack {
                if let peak = entry.peakHR {
                    Label("Peak \(Int(peak)) bpm", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
                Spacer()
                Text("Schema: \(entry.profile.schema.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let maxHR = entry.profile.maxHR {
                    Text("Max HR: \(Int(maxHR))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Heart Rate Recovery (filters: 1D/1W/1M + sport only)

    private func hrrScenarioDisplayName(_ scenario: HRRRecoveryScenario) -> String {
        switch scenario {
        case .staticHRR: return "Static HRR"
        case .activeRecovery: return "Active HRR"
        case .falsePeakSustained: return "False peak sustained"
        case .steadyStateMaintained: return "Steady state maintained"
        case .lowConfidence: return "Low confidence"
        case .insufficientData: return "Insufficient data"
        }
    }

    private var heartRateRecoverySection: some View {
        Group {
            if !hrrWorkoutPairs.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Heart Rate Recovery")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Uses 1D / 1W / 1M and sport filters only. Recovery is anchored to the detected end of the last hard segment when available, with a smoothed peak from the final minute before that stop and smoothed 1m/2m HR checkpoints after it. Recovery power is the steepest mean fall (bpm/s) over ~10s in the next 5 minutes. If headroom above resting HR is too small, 2m deltas are hidden as too noisy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if hrrLoader.isLoading && hrrLoader.resultsByUUID.isEmpty {
                        ProgressView("Loading recovery models…")
                            .tint(.orange)
                    }
                    ForEach(Array(hrrWorkoutPairs), id: \.workout.uuid) { pair in
                        hrrWorkoutCard(
                            workout: pair.workout,
                            analytics: pair.analytics,
                            result: hrrLoader.resultsByUUID[pair.workout.uuid]
                        )
                    }
                    effectiveHRRSummaryChart
                    Text("Heart rate metrics are for wellness trends only, not medical diagnosis. Unexpected symptoms warrant a clinician.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GlassRoundedRectBackground(cornerRadius: 28)
                }
            }
        }
    }

    @ViewBuilder
    private func hrrWorkoutCard(workout: HKWorkout, analytics: WorkoutAnalytics, result: HeartRateRecoveryResult?) -> some View {
        let samples = HeartRateRecoveryAnalysis.mergedSamples(analytics: analytics)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.workoutActivityType.name)
                        .font(.subheadline.bold())
                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let r = result {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.isStaticRecovery ? "Static HRR" : "Active HRR")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if r.excludeTwoMinuteFromPrimaryMetrics {
                            Text("2m HRR omitted (low headroom vs resting)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        } else if let d2 = r.dropBpm2m {
                            Text("2m Δ: \(d2 >= 0 ? "+" : "")\(Int(d2)) bpm")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(d2 > 0 ? .green : (d2 < 0 ? .red : .orange))
                        }
                        if let rp = r.recoveryPowerBpmPerSec {
                            Text(String(format: "Power: %.2f bpm/s", rp))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                        if let tt = r.secondsToDrop20Bpm {
                            Text(String(format: "Time −20 bpm: %.0f s", tt))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let idx = r.recoveryIndex60s {
                            let pct = idx * 100
                            Text(pct > 150 ? "Index @60s: >150%" : String(format: "Index @60s: %.0f%%", pct))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let idx120 = r.recoveryIndex120s {
                            let pct = idx120 * 100
                            Text(pct > 150 ? "Index @120s: >150%" : String(format: "Index @120s: %.0f%%", pct))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let k = r.recoveryRateConstantK {
                            Text(String(format: "Decay k: %.4f", k))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(hrrScenarioDisplayName(r.scenario))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if let r = result, samples.count >= 2 {
                hrrChartKeyLegend(workout: workout, r: r)
                Chart {
                    if let rs = r.recoveryStartDate, let re = r.recoveryWindowEnd {
                        RectangleMark(
                            xStart: .value("Time", rs),
                            xEnd: .value("Time", re),
                            yStart: .value("HR", 40),
                            yEnd: .value("HR", 220)
                        )
                        .foregroundStyle(.orange.opacity(0.18))
                    }
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, pt in
                        LineMark(
                            x: .value("Time", pt.0),
                            y: .value("HR", pt.1)
                        )
                        .foregroundStyle(.red.opacity(0.88))
                        .interpolationMethod(.catmullRom)
                    }
                    RuleMark(x: .value("Workout end", workout.endDate))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundStyle(.primary.opacity(0.4))
                    if let pt = r.effectivePeakDate {
                        PointMark(
                            x: .value("Time", pt),
                            y: .value("HR", r.windowedPeakBpm)
                        )
                        .foregroundStyle(.yellow)
                        .symbolSize(80)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
                Text(r.debugNotes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if result == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text("Not enough HR samples for a chart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private var effectiveHRRSummaryChart: some View {
        let pts: [(Date, Double)] = hrrWorkoutPairs.compactMap { pair in
            guard let r = hrrLoader.resultsByUUID[pair.workout.uuid] else { return nil }
            if r.scenario == .insufficientData || r.scenario == .falsePeakSustained { return nil }
            if r.excludeTwoMinuteFromPrimaryMetrics || r.scenario == .steadyStateMaintained { return nil }
            guard let d2 = r.dropBpm2m, r.confidence >= 0.35 else { return nil }
            return (pair.workout.startDate, d2)
        }
        return Group {
            if pts.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signed 2 min HRR (after workout end)")
                        .font(.subheadline.weight(.semibold))
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .foregroundStyle(.secondary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [5, 4]))
                        ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                            BarMark(
                                x: .value("Session", p.0.formatted(date: .abbreviated, time: .shortened)),
                                y: .value("Δ bpm", p.1)
                            )
                            .foregroundStyle(p.1 > 0 ? Color.green.opacity(0.75) : (p.1 < 0 ? Color.red.opacity(0.7) : Color.orange.opacity(0.5)))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption2)
                        }
                    }
                    .frame(height: 180)
                    Text("Positive = HR fell within 2 min (recovering). Sessions with low headroom vs resting or steady-state classification are omitted. See per-workout cards for recovery power and time to −20 bpm.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.4))
            Text("No workouts with HR data")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Complete a workout with heart rate monitoring to see zone breakdowns here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - HRR chart legend

    @ViewBuilder
    private func hrrChartKeyLegend(workout: HKWorkout, r: HeartRateRecoveryResult) -> some View {
        let shadedExplanation =
            "Orange tint: fixed window from the detected stop point through ~2½ minutes after, where the smoothed 1-minute and 2-minute recovery HR checkpoints are read (when shown)."
        let powerNote = r.recoveryPowerBpmPerSec != nil
            ? " Recovery power (bpm/s): steepest mean HR fall over ~10 seconds anywhere from the late-peak time through the following 5 minutes (merged in-workout + post-workout samples)."
            : ""
        VStack(alignment: .leading, spacing: 6) {
            Text("What you’re seeing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
            if r.effectivePeakDate != nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .frame(width: 14, alignment: .center)
                    Text("Yellow dot: smoothed max heart rate in the last 60 seconds before the detected stop point, used as the static HRR anchor when cooldown before workout end was minimal.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if r.recoveryStartDate != nil, r.recoveryWindowEnd != nil {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.4))
                        .frame(width: 14, height: 11)
                    Text(shadedExplanation + powerNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 14, height: 2)
                Text("Dashed vertical line: workout end. Recovery scoring prefers the detected stop point when it lands before workout end, which is common when a cooldown is still inside the workout.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
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
            windowLabel: ui.baselineWindow.rawValue,
            perZoneAvgMinutes: avgPerSession,
            perZoneTotalMinutes: totals,
            sessionCount: sessionCount,
            dayCount: days
        )
    }

    /// Trend % compares the **current chart range** to the **prior** baseline window (same sport filter).
    /// - **Total**: mean zone minutes **per calendar day** in the visible range vs mean per day across the whole baseline span (so 1D vs 7d/28d is not apples-to-oranges).
    /// - **Avg/Session**: mean minutes in that zone **per workout** in the visible range vs per workout in the baseline span.
    private func zoneTrendPercentDelta(
        zoneNum: Int,
        zoneMinuteTotal: Double,
        baseline: BaselineZoneStats?,
        sessionCount: Int
    ) -> Double? {
        guard let bl = baseline else { return nil }

        let current: Double?
        let baselineCompare: Double?

        switch ui.aggregationMode {
        case .average:
            guard sessionCount > 0, bl.sessionCount > 0 else { return nil }
            current = zoneMinuteTotal / Double(sessionCount)
            let bTotal = bl.perZoneTotalMinutes[zoneNum] ?? 0
            baselineCompare = bTotal / Double(bl.sessionCount)
        case .total:
            let cd = max(1, ui.timeFilter.dayCount)
            let bd = max(1, ui.baselineWindow.days)
            current = zoneMinuteTotal / Double(cd)
            let bTotal = bl.perZoneTotalMinutes[zoneNum] ?? 0
            baselineCompare = bTotal / Double(bd)
        }

        guard let c = current, let bv = baselineCompare, bv > 0 else { return nil }
        return ((c - bv) / bv) * 100
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
                sport: ui.sportFilter,
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
