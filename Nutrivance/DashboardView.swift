import SwiftUI
import Charts
import HealthKit

// MARK: - BlurView for Liquid Glass Effect
import UIKit

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

private struct DashboardLayoutSettings: Codable, Equatable {
    var groupSummaryCards: Bool
    var dashboardItemOrder: [String]
    var summaryCardsOrder: [String]
}

private enum DashboardSectionID {
    static let summaryCards = "SummaryCards"
    static let trainingLoadTrend = "TrainingLoadTrend"
    static let feelGoodScore = "FeelGoodScore"
    static let trainingLoadCard = "TrainingLoadCard"
    static let workoutHistory = "WorkoutHistory"

    static let defaultOrder = [
        summaryCards,
        trainingLoadTrend,
        feelGoodScore,
        trainingLoadCard,
        workoutHistory
    ]

    static func normalizedOrder(from savedOrder: [String]) -> [String] {
        let validSavedItems = savedOrder.filter { defaultOrder.contains($0) }
        let missingItems = defaultOrder.filter { validSavedItems.contains($0) == false }
        return validSavedItems + missingItems
    }

    static func displayName(for itemID: String) -> String {
        switch itemID {
        case summaryCards:
            return "Summary Cards"
        case trainingLoadTrend:
            return "Training Load Trend"
        case feelGoodScore:
            return "Feel-Good Score"
        case trainingLoadCard:
            return "Training Load"
        case workoutHistory:
            return "Workout History"
        default:
            return itemID
        }
    }
}

private enum DashboardLayoutPersistence {
    static let storageKey = "dashboard_layout_settings_v1"

    static let fallback = DashboardLayoutSettings(
        groupSummaryCards: false,
        dashboardItemOrder: DashboardSectionID.defaultOrder,
        summaryCardsOrder: ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]
    )

    static func load() -> DashboardLayoutSettings {
        let cloudStore = NSUbiquitousKeyValueStore.default

        if let cloudData = cloudStore.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DashboardLayoutSettings.self, from: cloudData) {
            return decoded
        }

        if let localData = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DashboardLayoutSettings.self, from: localData) {
            return decoded
        }

        return fallback
    }

    static func save(_ settings: DashboardLayoutSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(encoded, forKey: storageKey)
    }
}

private enum DashboardSnapshotPersistence {
    static let storageKey = "dashboard_load_snapshot_v1"

    static func load() -> DashboardView.DashboardLoadSnapshot? {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DashboardView.DashboardLoadSnapshot.self, from: data) {
            return decoded
        }
        return nil
    }

    static func save(_ snapshot: DashboardView.DashboardLoadSnapshot) {
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}

struct DashboardView: View {
    @StateObject var engine = HealthStateEngine.shared
    @EnvironmentObject private var unitPreferences: UnitPreferencesStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedChartRange: ChartRange = .month
    @State private var animationPhase: Double = 0
    @State private var selectedTrainingLoadPoint: TrainingLoadChartPoint? = nil
    
    enum DetailViewType {
        case none
        case feelGood
        case metric(MetricType)
    }
    
    @State private var activeDetailView: DetailViewType = .none

    enum ChartRange: String, CaseIterable {
        case week = "7d"
        case month = "30d"
    }
    enum MetricType: String {
        case recovery, readiness, strain, allostatic, autonomic
    }

    struct DashboardLoadSnapshot: Codable, Equatable {
        let acuteLoad: Double
        let acuteTotal: Double
        let chronicLoad: Double
        let chronicTotal: Double
        let acwr: Double
        let activeDaysLast28: Int
        let daysSinceLastWorkout: Int?
    }

    private struct HRVChartPoint {
        let date: Date
        let value: Double
    }

    private struct TrainingLoadChartPoint {
        let date: Date
        let value: Double
    }

    // Customization State
    @State private var showCustomizationSheet: Bool = false
    @State private var showArrangementSheet: Bool = false
    @State private var showUnitSettings = false
    @State private var groupSummaryCards: Bool = false
    @State private var dashboardItemOrder: [String] = DashboardSectionID.defaultOrder
    @State private var summaryCardsOrder: [String] = ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]
    @State private var hasLoadedLayoutSettings = false
    @State private var isRefreshingDashboardMetrics = false
    @State private var hasStartedBackgroundRefresh = false
    @State private var dashboardRefreshTask: Task<Void, Never>? = nil
    @State private var liveLoadSnapshot: DashboardLoadSnapshot = DashboardLoadSnapshot(
        acuteLoad: 0,
        acuteTotal: 0,
        chronicLoad: 0,
        chronicTotal: 0,
        acwr: 0,
        activeDaysLast28: 0,
        daysSinceLastWorkout: nil
    )

    init() {
        let saved = DashboardLayoutPersistence.load()
        _groupSummaryCards = State(initialValue: saved.groupSummaryCards)
        _dashboardItemOrder = State(initialValue: DashboardSectionID.normalizedOrder(from: saved.dashboardItemOrder))
        _summaryCardsOrder = State(initialValue: saved.summaryCardsOrder)
        _hasLoadedLayoutSettings = State(initialValue: true)
        _liveLoadSnapshot = State(initialValue: DashboardSnapshotPersistence.load() ?? DashboardLoadSnapshot(
            acuteLoad: 0,
            acuteTotal: 0,
            chronicLoad: 0,
            chronicTotal: 0,
            acwr: 0,
            activeDaysLast28: 0,
            daysSinceLastWorkout: nil
        ))
    }

    private var layoutSettings: DashboardLayoutSettings {
        DashboardLayoutSettings(
            groupSummaryCards: groupSummaryCards,
            dashboardItemOrder: dashboardItemOrder,
            summaryCardsOrder: summaryCardsOrder
        )
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
            if let value = value as? NSNumber {
                return value.doubleValue
            }
            if let value = value as? Double {
                return value
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

    private func calculateLatestLoadSnapshot() -> DashboardLoadSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let workouts = engine.workoutAnalytics

        var loadByDay: [Date: Double] = [:]
        for (workout, analytics) in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            loadByDay[day, default: 0] += sessionLoad(for: workout, analytics: analytics)
        }

        let acuteTotal = (0..<7).reduce(0.0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return partial + (loadByDay[day] ?? 0)
        }
        let chronicTotal = (0..<28).reduce(0.0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return partial + (loadByDay[day] ?? 0)
        }
        let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return partial + ((loadByDay[day] ?? 0) > 0 ? 1 : 0)
        }
        let daysSinceLastWorkout = (0..<28).first { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return (loadByDay[day] ?? 0) > 0
        }
        let acuteLoad = acuteTotal / 7.0
        let chronicLoad = chronicTotal / 28.0

        return DashboardLoadSnapshot(
            acuteLoad: acuteLoad,
            acuteTotal: acuteTotal,
            chronicLoad: chronicLoad,
            chronicTotal: chronicTotal,
            acwr: chronicLoad > 0 ? acuteLoad / chronicLoad : 0,
            activeDaysLast28: activeDaysLast28,
            daysSinceLastWorkout: daysSinceLastWorkout
        )
    }

    private var backgroundRefreshDelayNanoseconds: UInt64 {
        let processInfo = ProcessInfo.processInfo
        switch processInfo.thermalState {
        case .serious, .critical:
            return 2_500_000_000
        case .fair:
            return processInfo.isLowPowerModeEnabled ? 1_800_000_000 : 1_200_000_000
        case .nominal:
            return processInfo.isLowPowerModeEnabled ? 1_250_000_000 : 900_000_000
        @unknown default:
            return 1_500_000_000
        }
    }

    private var shouldFetchWorkoutHistoryNow: Bool {
        let processInfo = ProcessInfo.processInfo
        guard !processInfo.isLowPowerModeEnabled else { return false }
        switch processInfo.thermalState {
        case .serious, .critical:
            return false
        default:
            return true
        }
    }

    private func updateLiveLoadSnapshot() {
        let snapshot = calculateLatestLoadSnapshot()
        if snapshot != liveLoadSnapshot {
            liveLoadSnapshot = snapshot
            DashboardSnapshotPersistence.save(snapshot)
        }
    }

    private var hasEnoughLoadedWorkoutsForDashboard: Bool {
        guard !engine.workoutAnalytics.isEmpty else { return false }
        guard let oldestLoadedWorkout = engine.workoutAnalytics.map({ $0.workout.startDate }).min() else { return false }
        let requiredStart = Calendar.current.date(byAdding: .day, value: -35, to: Date()) ?? Date()
        return oldestLoadedWorkout <= requiredStart
    }

    private var dashboardLoadSummary: (title: String, detail: String, color: Color) {
        let snapshot = liveLoadSnapshot

        if snapshot.activeDaysLast28 < 14 {
            return ("Baseline Outdated", "Not enough recent training days to trust ACWR yet.", .orange)
        }

        if let daysSinceLastWorkout = snapshot.daysSinceLastWorkout {
            if daysSinceLastWorkout > 21 {
                return ("Reset", "Long inactivity detected. Baseline should be rebuilt.", .gray)
            }
            if daysSinceLastWorkout >= 8 {
                return ("Re-establishing", "Returning to training. Acute load may look jumpy for a few sessions.", .orange)
            }
        } else {
            return ("No Baseline", "No recent training load found.", .gray)
        }

        switch snapshot.acwr {
        case ..<0.8:
            return ("Detraining", "Load is below baseline and fitness may drift down.", .blue)
        case 0.8...1.2:
            return ("Optimal", "Acute load is tracking inside the usual sweet spot.", .green)
        case 1.3...1.5:
            return ("Aggressive", "Load is elevated. Recovery quality matters more here.", .yellow)
        default:
            return ("Spike", "Workload is spiking and injury risk is higher.", .red)
        }
    }

    private var hrvTrendSummary: String {
        let score = engine.hrvTrendScore
        switch selectedChartRange {
        case .week:
            if score >= 60 {
                return "Your 7-day HRV trend is running above baseline, which usually points to stronger recovery capacity."
            } else if score <= 40 {
                return "Your 7-day HRV trend is running below baseline, which can reflect fatigue, stress, or incomplete recovery."
            } else {
                return "Your 7-day HRV trend is close to baseline, suggesting your recovery state is fairly stable right now."
            }
        case .month:
            if score >= 60 {
                return "The 30-day HRV view suggests your longer recovery trend is improving over baseline."
            } else if score <= 40 {
                return "The 30-day HRV view suggests your recovery trend has been suppressed for a while and may need attention."
            } else {
                return "The 30-day HRV view is broadly steady, which usually means your autonomic load has been relatively balanced."
            }
        }
    }

    private var cacheRefreshStatusText: String? {
        if engine.isRefreshingCachedMetrics {
            if let updatedAt = engine.cachedMetricsUpdatedAt {
                return "Showing cached metrics from \(updatedAt.formatted(date: .abbreviated, time: .shortened)) while live values refresh in the background."
            }
            return "Refreshing live metrics in the background."
        }

        guard let updatedAt = engine.cachedMetricsUpdatedAt else { return nil }
        return "Cached metrics last updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let cacheRefreshStatusText {
                        Text(cacheRefreshStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    dashboardItemsSection()
                }
                .padding(.top)
            }
            .background(
                GradientBackgrounds()
                    .burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        showUnitSettings = true
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.orange)
                    }
                    Button(action: { showArrangementSheet = true
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()}) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showArrangementSheet) {
                DashboardArrangementSheet(
                    isPresented: $showArrangementSheet,
                    dashboardItemOrder: $dashboardItemOrder,
                    summaryCardsOrder: $summaryCardsOrder
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(isPresented: $showUnitSettings) {
                UnitSettingsView(isPresented: $showUnitSettings)
                    .environmentObject(unitPreferences)
            }
            .task {
                guard !hasStartedBackgroundRefresh else { return }
                hasStartedBackgroundRefresh = true
                updateLiveLoadSnapshot()
                dashboardRefreshTask?.cancel()
                dashboardRefreshTask = Task(priority: .utility) {
                    await refreshDashboardMetricsInBackground()
                }
            }
            .onChange(of: layoutSettings) { _, newValue in
                guard hasLoadedLayoutSettings else { return }
                DashboardLayoutPersistence.save(newValue)
            }
            .onChange(of: engine.workoutAnalytics.count) { _, _ in
                updateLiveLoadSnapshot()
            }
            .onChange(of: engine.workoutAnalytics.last?.workout.endDate) { _, _ in
                updateLiveLoadSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                let saved = DashboardLayoutPersistence.load()
                groupSummaryCards = saved.groupSummaryCards
                dashboardItemOrder = DashboardSectionID.normalizedOrder(from: saved.dashboardItemOrder)
                summaryCardsOrder = saved.summaryCardsOrder
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                dashboardRefreshTask?.cancel()
                isRefreshingDashboardMetrics = false
            }
            .onDisappear {
                dashboardRefreshTask?.cancel()
            }
        }
    }

    private func refreshDashboardMetricsInBackground() async {
        guard !isRefreshingDashboardMetrics else { return }
        isRefreshingDashboardMetrics = true
        defer { isRefreshingDashboardMetrics = false }

        try? await Task.sleep(nanoseconds: backgroundRefreshDelayNanoseconds)
        guard !Task.isCancelled else { return }

        await MainActor.run {
            engine.refreshStartupMetrics()
        }

        guard !Task.isCancelled else { return }

        // Let the initial screen animation and first render settle before heavier history fetches.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }

        if shouldFetchWorkoutHistoryNow && !hasEnoughLoadedWorkoutsForDashboard {
            await engine.refreshWorkoutAnalytics(days: 35)
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            updateLiveLoadSnapshot()
        }
    }

    // MARK: - Dashboard Sections as ViewBuilder functions

    @ViewBuilder
    private func dashboardItemsSection() -> some View {
        ForEach(dashboardItemOrder, id: \.self) { item in
            Group {
                if item == DashboardSectionID.summaryCards {
                    VStack(spacing: groupSummaryCards ? 4 : 8) {
                        HStack {
                            Button(action: { withAnimation { groupSummaryCards.toggle() }
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()}) {
                                HStack(spacing: 6) {
                                    Image(systemName: groupSummaryCards ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("Summary Cards")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal)

                        if groupSummaryCards {
                            summaryCardsTabView()
                        } else {
                            summaryCardsInline()
                        }
                    }
                } else {
                    switch item {
                    case DashboardSectionID.trainingLoadTrend:
                        trainingLoadTrendSection()
                    case DashboardSectionID.feelGoodScore:
                        feelGoodScoreSection()
                    case DashboardSectionID.trainingLoadCard:
                        acwrSection()
                    case DashboardSectionID.workoutHistory:
                        workoutHistoryPreviewSection()
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryCardsTabView() -> some View {
        TabView {
            ForEach(summaryCardsOrder, id: \.self) { title in
                summaryCard(
                    icon: iconFor(title),
                    title: title,
                    value: valueFor(title),
                    baseline: baselineFor(title),
                    description: descriptionFor(title),
                    color: colorFor(title),
                    metric: metricFor(title)
                )
                .padding(.horizontal)
            }
        }
        .frame(height: 140)
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func summaryCardsInline() -> some View {
        VStack(spacing: 12) {
            ForEach(summaryCardsOrder, id: \.self) { title in
                summaryCard(
                    icon: iconFor(title),
                    title: title,
                    value: valueFor(title),
                    baseline: baselineFor(title),
                    description: descriptionFor(title),
                    color: colorFor(title),
                    metric: metricFor(title)
                )
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func trainingLoadTrendSection() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(ChartRange.allCases, id: \.self) { range in
                    Button(action: {
                        selectedChartRange = range
                        selectedTrainingLoadPoint = trainingLoadChartData().last
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }) {
                        Text(range.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(selectedChartRange == range ? .white : .orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .background(
                        Capsule()
                            .fill(selectedChartRange == range ? Color.orange : Color.orange.opacity(0.16))
                    )
                    .buttonStyle(.glass)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Training Load")
                    .font(.headline)
                    .padding(.horizontal)
                let chartPoints = trainingLoadChartData()
                let maxValue = max(chartPoints.map(\.value).max() ?? 0, 1)
                Chart {
                    RuleMark(y: .value("Ideal Low", 70))
                        .foregroundStyle(.orange.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    RuleMark(y: .value("Ideal High", 90))
                        .foregroundStyle(.orange.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(chartPoints, id: \.date) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Load", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange.opacity(0.28), .orange.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Load", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Load", point.value)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(26)
                    }

                    if let selectedTrainingLoadPoint {
                        RuleMark(x: .value("Selected Date", selectedTrainingLoadPoint.date))
                            .foregroundStyle(.orange.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        PointMark(
                            x: .value("Selected Date", selectedTrainingLoadPoint.date),
                            y: .value("Selected Load", selectedTrainingLoadPoint.value)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(80)
                    }
                }
                .chartYScale(domain: 0...(maxValue * 1.18))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        trainingLoadSelectionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            points: chartPoints
                        )
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)

                if let selectedTrainingLoadPoint {
                    HStack {
                        Text(selectedTrainingLoadPoint.date, format: selectedChartRange == .week ? .dateTime.weekday(.abbreviated).month().day() : .dateTime.month().day())
                        Spacer()
                        Text(String(format: "%.0f TL", selectedTrainingLoadPoint.value))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                }

                Text(trainingLoadTrendSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            if selectedTrainingLoadPoint == nil {
                selectedTrainingLoadPoint = trainingLoadChartData().last
            }
        }
    }

    @ViewBuilder
    private func sleepWeightedSection() -> some View {
        let hrv = engine.latestHRV ?? 0
        let sleep = engine.sleepHours ?? 0
        let sleepWeight = min(max(sleep / 8.0, 0), 1) // normalize sleep to 0-1 (assuming 8h optimal)
        let sleepWeightedHRV = hrv * sleepWeight

        VStack(alignment: .leading) {
            Text("Sleep-Weighted HRV")
                .font(.headline)
                .padding(.horizontal)
            HStack {
                Text(String(format: "%.0f", sleepWeightedHRV))
                    .font(.largeTitle)
                    .bold()
                Text("(Sleep HRV)")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func acwrSection() -> some View {
        let loadSummary = dashboardLoadSummary
        let snapshot = liveLoadSnapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Training Load", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Text(String(format: "ACWR %.2f", snapshot.acwr))
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 12) {
                DashboardLoadMetricPill(title: "Acute", value: String(format: "%.1f", snapshot.acuteLoad), color: .orange)
                DashboardLoadMetricPill(title: "Chronic", value: String(format: "%.1f", snapshot.chronicLoad), color: .blue)
            }
            Text(loadSummary.detail)
                .font(.caption)
                .foregroundColor(loadSummary.color)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func workoutHistoryPreviewSection() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                WorkoutHistoryView()
            } label: {
                HStack {
                    Text("Workout History")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            workoutPreviewGroup(title: "Today", workouts: workoutsForPreview(dayOffset: 0))
            workoutPreviewGroup(title: "Yesterday", workouts: workoutsForPreview(dayOffset: -1))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func workoutPreviewGroup(
        title: String,
        workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if workouts.isEmpty {
                Text("No workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(workouts, id: \.analytics.workout.uuid) { pair in
                    NavigationLink {
                        WorkoutHistoryView(
                            initialScrollWorkoutID: workoutRowIdentifier(for: pair.workout)
                        )
                    } label: {
                        DashboardWorkoutPreviewCard(
                            workout: pair.workout,
                            analytics: pair.analytics
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    @ViewBuilder
    private func feelGoodScoreSection() -> some View {
        Button {
            activeDetailView = .feelGood
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } label: {
            let isAvailable = engine.feelGoodScoreInputsAvailable
            let score = engine.feelGoodScore

            VStack(alignment: .leading, spacing: 6) {
                Text("Feel-Good Score")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if isAvailable {
                        Text(String(format: "%.0f", score))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.orange)
                        Text("/100")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("Not available")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                Text(
                    isAvailable
                    ? "Your overall physiological readiness and recovery, based on multiple metrics."
                    : "Feel-Good Score needs recent HRV, resting heart rate, and sleep data before it can be calculated."
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.orange.opacity(0.28), lineWidth: 1)
            )
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding(.horizontal)
        }
        .navigationDestination(isPresented: Binding(
            get: { 
                if case .feelGood = activeDetailView { return true } else { return false }
            },
            set: { if !$0 { activeDetailView = .none } }
        )) {
            FeelGoodScoreDetailView(engine: engine, isPresented: Binding(
                get: { if case .feelGood = activeDetailView { return true } else { return false } },
                set: { if !$0 { activeDetailView = .none } }
            ))
        }
    }

    // customizationSheet() removed

    // Helper functions to map title to properties
    func iconFor(_ title: String) -> String {
        switch title {
        case "Recovery": return "heart.circle.fill"
        case "Readiness": return "bolt.heart.fill"
        case "Strain": return "flame.fill"
        case "Allostatic": return "waveform.path.ecg"
        case "Autonomic": return "heart.circle"
        default: return "questionmark"
        }
    }

    func valueFor(_ title: String) -> Double {
        switch title {
        case "Recovery": return engine.recoveryScore
        case "Readiness": return engine.readinessScore
        case "Strain": return engine.strainScore
        case "Allostatic": return engine.allostaticStressScore
        case "Autonomic": return engine.autonomicBalanceScore
        default: return 0
        }
    }

    func baselineFor(_ title: String) -> Double? {
        switch title {
        case "Recovery": return engine.hrvBaseline7Day
        default: return nil
        }
    }

    func descriptionFor(_ title: String) -> String {
        switch title {
        case "Recovery":
            return "Shows how ready your body is based on HRV, resting heart rate, and sleep. Higher numbers mean better recovery."
        case "Readiness":
            return "Indicates how prepared your body is today. Higher numbers mean you can perform well; lower numbers suggest taking it easier."
        case "Strain":
            return "Measures the stress your body has experienced from activity and lifestyle. Higher numbers mean more stress/load."
        case "Allostatic":
            return "Represents cumulative stress on your body over time. Higher numbers mean your body has been under repeated stress and may need recovery."
        case "Autonomic":
            return "Shows how well your body's nervous system is balanced. Higher numbers mean calm and balance; lower numbers may indicate stress."
        default:
            return ""
        }
    }

    func colorFor(_ title: String) -> Color {
        switch title {
        case "Recovery": return .green
        case "Readiness": return .blue
        case "Strain": return .orange
        case "Allostatic": return .red
        case "Autonomic": return .purple
        default: return .gray
        }
    }

    func metricFor(_ title: String) -> MetricType {
        switch title {
        case "Recovery": return .recovery
        case "Readiness": return .readiness
        case "Strain": return .strain
        case "Allostatic": return .allostatic
        case "Autonomic": return .autonomic
        default: return .recovery
        }
    }

    // Summary Card Factory
    private func summaryCard(icon: String, title: String, value: Double, baseline: Double?, description: String, color: Color, metric: MetricType) -> some View {
        NavigationLink {
            metricDestination(metric)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(value))")
                        .font(.system(size: 28, weight: .bold))
                    if let base = baseline {
                        Text("(\(Int(base)))")
                            .foregroundColor(.secondary)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Chart Data Filter
    private func chartData(
        for dailyHRV: [HealthStateEngine.DailyHRVPoint],
        sampleHistory: [HealthStateEngine.HRVSamplePoint]
    ) -> [HRVChartPoint] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedChartRange {
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return [] }
            return dailyHRV
                .filter { $0.date >= start && $0.date <= now }
                .map { HRVChartPoint(date: $0.date, value: $0.average) }
        case .month:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return [] }
            return dailyHRV
                .filter { $0.date >= start && $0.date <= now }
                .map { HRVChartPoint(date: $0.date, value: $0.average) }
        }
    }

    private func trainingLoadChartData() -> [TrainingLoadChartPoint] {
        let now = Date()

        switch selectedChartRange {
        case .week:
            return dailyTrainingLoadPoints(days: 7, endingAt: now)
        case .month:
            return dailyTrainingLoadPoints(days: 30, endingAt: now)
        }
    }

    private func dailyTrainingLoadPoints(days: Int, endingAt endDate: Date) -> [TrainingLoadChartPoint] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        let dates = (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: endDay) }.reversed()

        var dailyLoads: [Date: Double] = [:]
        for pair in engine.workoutAnalytics {
            let day = calendar.startOfDay(for: pair.workout.startDate)
            dailyLoads[day, default: 0] += sessionLoad(for: pair.workout, analytics: pair.analytics)
        }

        return dates.map { day in
            TrainingLoadChartPoint(date: day, value: dailyLoads[day, default: 0])
        }
    }

    private var trainingLoadTrendSummary: String {
        switch selectedChartRange {
        case .week:
            return dashboardLoadSummary.detail
        case .month:
            return "The 30-day view helps you see whether your load is building steadily, flattening out, or spiking."
        }
    }

    private func nearestTrainingLoadPoint(in points: [TrainingLoadChartPoint], to date: Date) -> TrainingLoadChartPoint? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func updateTrainingLoadSelection(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [TrainingLoadChartPoint]
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard plotFrame.contains(location) else { return }

        let plotX = location.x - plotFrame.origin.x
        guard plotX >= 0, plotX <= plotFrame.size.width,
              let date = proxy.value(atX: plotX) as Date? else { return }

        guard let nearestPoint = nearestTrainingLoadPoint(in: points, to: date) else { return }
        let previousSelectionDate = selectedTrainingLoadPoint?.date
        selectedTrainingLoadPoint = nearestPoint
        if previousSelectionDate != nearestPoint.date {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    @ViewBuilder
    private func trainingLoadSelectionOverlay(
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [TrainingLoadChartPoint]
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .overlay {
                DashboardHorizontalChartScrubOverlay { location in
                    updateTrainingLoadSelection(
                        location: location,
                        proxy: proxy,
                        geometry: geometry,
                        points: points
                    )
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        updateTrainingLoadSelection(
                            location: value.location,
                            proxy: proxy,
                            geometry: geometry,
                            points: points
                        )
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateTrainingLoadSelection(
                        location: location,
                        proxy: proxy,
                        geometry: geometry,
                        points: points
                    )
                case .ended:
                    break
                }
            }
    }

    private func workoutsForPreview(dayOffset: Int) -> [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) ?? Date()
        return engine.workoutAnalytics
            .filter { calendar.isDate($0.workout.startDate, inSameDayAs: targetDay) }
            .sorted { $0.workout.startDate > $1.workout.startDate }
    }

    @ViewBuilder
    private func metricDestination(_ metric: MetricType) -> some View {
        switch metric {
        case .recovery:
            RecoveryScoreView()
        case .readiness:
            ReadinessCheckView()
        case .strain:
            StrainRecoveryView()
        case .allostatic, .autonomic:
            StressView()
        }
    }
}

private struct DashboardWorkoutPreviewCard: View {
    let workout: HKWorkout
    let analytics: WorkoutAnalytics

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
        HStack {
            Image(systemName: workout.workoutActivityType.activityTypeSymbol)
                .foregroundColor(.orange)
            VStack(alignment: .leading) {
                Text(workout.workoutActivityType.name.capitalized)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(Self.dateFormatter.string(from: workout.startDate)) + Text(" • ") + Text(Self.timeFormatter.string(from: workout.startDate)) + Text(" • \(Int(workout.duration / 60)) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let avgHR = analytics.heartRates.map({ $0.1 }).average {
                    Text("Avg HR: \(Int(avgHR)) bpm")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                if let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
                    Text("Kcal: \(Int(kcal))")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                if let met = analytics.metTotal {
                    Text("MET-min: \(Int(met))")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
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

private struct DashboardLoadMetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardHorizontalChartScrubOverlay: UIViewRepresentable {
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

// Haptic Helper
struct HapticFeedback {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

// Metric Detail Modal
struct MetricDetailModal: View {
    @ObservedObject var engine: HealthStateEngine
    let metric: DashboardView.MetricType
    @Environment(\.dismiss) var dismiss
    @State private var loadSnapshot: DashboardView.DashboardLoadSnapshot = DashboardView.DashboardLoadSnapshot(
        acuteLoad: 0,
        acuteTotal: 0,
        chronicLoad: 0,
        chronicTotal: 0,
        acwr: 0,
        activeDaysLast28: 0,
        daysSinceLastWorkout: nil
    )

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
            if let value = value as? NSNumber {
                return value.doubleValue
            }
            if let value = value as? Double {
                return value
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

    private func calculateLatestLoadSnapshot() -> DashboardView.DashboardLoadSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var loadByDay: [Date: Double] = [:]

        for (workout, analytics) in engine.workoutAnalytics {
            let day = calendar.startOfDay(for: workout.startDate)
            loadByDay[day, default: 0] += sessionLoad(for: workout, analytics: analytics)
        }

        let acuteTotal = (0..<7).reduce(0.0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return partial + (loadByDay[day] ?? 0)
        }
        let chronicTotal = (0..<28).reduce(0.0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return partial + (loadByDay[day] ?? 0)
        }
        let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return partial + ((loadByDay[day] ?? 0) > 0 ? 1 : 0)
        }
        let daysSinceLastWorkout = (0..<28).first { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return (loadByDay[day] ?? 0) > 0
        }
        let acuteLoad = acuteTotal / 7.0
        let chronicLoad = chronicTotal / 28.0

        return DashboardView.DashboardLoadSnapshot(
            acuteLoad: acuteLoad,
            acuteTotal: acuteTotal,
            chronicLoad: chronicLoad,
            chronicTotal: chronicTotal,
            acwr: chronicLoad > 0 ? acuteLoad / chronicLoad : 0,
            activeDaysLast28: activeDaysLast28,
            daysSinceLastWorkout: daysSinceLastWorkout
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detailTitle)
                            .font(.largeTitle.bold())
                        Text(detailDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Group {
                        switch metric {
                        case .recovery:
                            detailCard(title: "Recovery Drivers", rows: [
                                ("Recovery Score", "\(Int(engine.recoveryScore))"),
                                ("HRV", "\(Int(engine.latestHRV ?? 0)) ms"),
                                ("Resting HR", "\(Int(engine.restingHeartRate ?? 0)) bpm"),
                                ("Sleep", "\(String(format: "%.1f", engine.sleepHours ?? 0)) h"),
                                ("Sleep-Weighted HRV", "\(Int(engine.sleepHRVScore))")
                            ])
                        case .readiness:
                            detailCard(title: "Readiness Drivers", rows: [
                                ("Readiness Score", "\(Int(engine.readinessScore))"),
                                ("HRV Trend", "\(Int(engine.hrvTrendScore))"),
                                ("Circadian HRV", "\(Int(engine.circadianHRVScore))"),
                                ("Sleep HRV", "\(Int(engine.sleepHRVScore))"),
                                ("Strain", "\(Int(engine.strainScore))")
                            ])
                        case .strain:
                            let snapshot = loadSnapshot
                            detailCard(title: "Training Load", rows: [
                                ("Strain Score", "\(Int(engine.strainScore))"),
                                ("Acute Load", "\(String(format: "%.1f", snapshot.acuteLoad))"),
                                ("Chronic Load", "\(String(format: "%.1f", snapshot.chronicLoad))"),
                                ("ACWR", "\(String(format: "%.2f", snapshot.acwr))")
                            ])
                        case .allostatic:
                            detailCard(title: "Allostatic Signals", rows: [
                                ("Allostatic Stress", "\(Int(engine.allostaticStressScore))"),
                                ("HRV", "\(Int(engine.latestHRV ?? 0)) ms"),
                                ("Resting HR", "\(Int(engine.restingHeartRate ?? 0)) bpm"),
                                ("Sleep", "\(String(format: "%.1f", engine.sleepHours ?? 0)) h"),
                                ("Strain", "\(Int(engine.strainScore))")
                            ])
                        case .autonomic:
                            detailCard(title: "Autonomic Signals", rows: [
                                ("Autonomic Balance", "\(Int(engine.autonomicBalanceScore))"),
                                ("HRV", "\(Int(engine.latestHRV ?? 0)) ms"),
                                ("Resting HR", "\(Int(engine.restingHeartRate ?? 0)) bpm")
                            ])
                        }
                    }
                }
                .padding()
            }
            .background(
                GradientBackgrounds().burningGradient(animationPhase: .constant(0))
                    .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                HapticFeedback.selection()
                loadSnapshot = calculateLatestLoadSnapshot()
            }
        }
    }

    @ViewBuilder
    private func detailCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(row.1)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var detailTitle: String {
        switch metric {
        case .recovery: return "Recovery"
        case .readiness: return "Readiness"
        case .strain: return "Strain"
        case .allostatic: return "Allostatic Stress"
        case .autonomic: return "Autonomic Balance"
        }
    }
    var detailDescription: String {
        switch metric {
        case .recovery:
            return "Recovery is a composite of HRV, resting heart rate, and sleep. Higher scores suggest you are well-recovered and ready for activity."
        case .readiness:
            return "Readiness reflects your physiological state today, including trends and circadian patterns. Use it to guide your training and recovery."
        case .strain:
            return "Strain measures training and lifestyle stress over the past week. Higher strain can reduce recovery if not balanced."
        case .allostatic:
            return "Allostatic stress represents the cumulative burden of stressors on your body, including physical and psychological load."
        case .autonomic:
            return "Autonomic balance compares your HRV and resting heart rate to assess nervous system balance."
        }
    }
}

// MARK: - Dashboard Arrangement Sheet
struct DashboardArrangementSheet: View {
    @Binding var isPresented: Bool
    @Binding var dashboardItemOrder: [String]
    @Binding var summaryCardsOrder: [String]
    
    @State private var isEditingMode: Bool = false
    @State private var localDashboardOrder: [String] = []
    @State private var localSummaryCardsOrder: [String] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Arrange Dashboard")
                            .font(.largeTitle.bold())
                        Text("Reorder the major dashboard cards and the summary cards inside the summary section.")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Dashboard Layout")
                            .font(.headline)

                        ForEach(0..<localDashboardOrder.count, id: \.self) { mainIndex in
                            let mainItemName = localDashboardOrder[mainIndex]
                            let displayName = DashboardSectionID.displayName(for: mainItemName)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(mainIndex + 1). " + displayName)
                                    .font(.subheadline.weight(.semibold))

                                if mainItemName == DashboardSectionID.summaryCards {
                                    ForEach(0..<localSummaryCardsOrder.count, id: \.self) { itemIndex in
                                        HStack {
                                            Text("\(itemIndex + 1). \(localSummaryCardsOrder[itemIndex])")
                                            Spacer()
                                            if isEditingMode {
                                                HStack(spacing: 8) {
                                                    Button {
                                                        if itemIndex > 0 {
                                                            localSummaryCardsOrder.swapAt(itemIndex, itemIndex - 1)
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                        }
                                                    } label: {
                                                        Image(systemName: "chevron.up")
                                                    }
                                                    Button {
                                                        if itemIndex < localSummaryCardsOrder.count - 1 {
                                                            localSummaryCardsOrder.swapAt(itemIndex, itemIndex + 1)
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                        }
                                                    } label: {
                                                        Image(systemName: "chevron.down")
                                                    }
                                                }
                                                .foregroundColor(.blue)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                                if isEditingMode {
                                    HStack(spacing: 8) {
                                        Button {
                                            if mainIndex > 0 {
                                                localDashboardOrder.swapAt(mainIndex, mainIndex - 1)
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            }
                                        } label: {
                                            Label("Move Up", systemImage: "chevron.up")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.orange)
                                        .disabled(mainIndex == 0)

                                        Button {
                                            if mainIndex < localDashboardOrder.count - 1 {
                                                localDashboardOrder.swapAt(mainIndex, mainIndex + 1)
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            }
                                        } label: {
                                            Label("Move Down", systemImage: "chevron.down")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.orange)
                                        .disabled(mainIndex == localDashboardOrder.count - 1)
                                    }
                                }
                            }
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding()
            .background(
                GradientBackgrounds().burningGradient(animationPhase: .constant(0))
                    .ignoresSafeArea()
            )
            .navigationTitle("Arrange Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditingMode ? "Done" : "Edit") {
                        if isEditingMode {
                            dashboardItemOrder = localDashboardOrder
                            summaryCardsOrder = localSummaryCardsOrder
                            isPresented = false
                        }
                        isEditingMode.toggle()
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
                    .foregroundColor(.orange)
                }
            }
            .onAppear {
                localDashboardOrder = DashboardSectionID.normalizedOrder(from: dashboardItemOrder)
                localSummaryCardsOrder = summaryCardsOrder
            }
        }
    }
}

struct UnitSettingsView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var unitPreferences: UnitPreferencesStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Automatic Defaults") {
                    Text(unitPreferences.automaticSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Distance") {
                    Picker("Distance", selection: $unitPreferences.distance) {
                        ForEach(DistanceUnitPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("Speed", selection: $unitPreferences.speed) {
                        ForEach(SpeedUnitPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("Pace", selection: $unitPreferences.pace) {
                        ForEach(PaceUnitPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("Elevation", selection: $unitPreferences.elevation) {
                        ForEach(ElevationUnitPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section("Temperature") {
                    Picker("Temperature", selection: $unitPreferences.temperature) {
                        ForEach(TemperatureUnitPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section("Reset") {
                    Button("Use Device Defaults") {
                        unitPreferences.resetToAutomatic()
                    }
                    .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Display Units")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}
