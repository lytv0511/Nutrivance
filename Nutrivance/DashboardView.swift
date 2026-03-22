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

private enum DashboardLayoutPersistence {
    static let storageKey = "dashboard_layout_settings_v1"

    static let fallback = DashboardLayoutSettings(
        groupSummaryCards: false,
        dashboardItemOrder: ["SummaryCards", "HRVTrend"],
        summaryCardsOrder: ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]
    )

    static func load() -> DashboardLayoutSettings {
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()

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
        cloudStore.synchronize()
    }
}

struct DashboardView: View {
    @StateObject var engine = HealthStateEngine.shared
    @State private var selectedChartRange: ChartRange = .month
    @State private var selectedMetric: MetricType = .recovery
    @State private var animationPhase: Double = 0
    
    enum DetailViewType {
        case none
        case feelGood
        case metric(MetricType)
    }
    
    @State private var activeDetailView: DetailViewType = .none

    enum ChartRange: String, CaseIterable {
        case day24h = "24h"
        case week = "7d"
        case month = "30d"
    }
    enum MetricType: String {
        case recovery, readiness, strain, allostatic, autonomic
    }

    struct DashboardLoadSnapshot {
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

    // Customization State
    @State private var showCustomizationSheet: Bool = false
    @State private var showArrangementSheet: Bool = false
    @State private var groupSummaryCards: Bool = false
    @State private var dashboardItemOrder: [String] = ["SummaryCards", "HRVTrend"]
    @State private var summaryCardsOrder: [String] = ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]
    @State private var hasLoadedLayoutSettings = false
    @State private var isRefreshingDashboardMetrics = false
    @State private var hasStartedBackgroundRefresh = false
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
        _dashboardItemOrder = State(initialValue: saved.dashboardItemOrder)
        _summaryCardsOrder = State(initialValue: saved.summaryCardsOrder)
        _hasLoadedLayoutSettings = State(initialValue: true)
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
        case .day24h:
            return "The 24h view shows intraday HRV context only. Use it to spot short swings, not long-term readiness."
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dashboardItemsSection()
                    feelGoodScoreSection()
                    acwrSection()
                    navigationLinksSection()
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
                    Button(action: { showArrangementSheet = true
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()}) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showArrangementSheet) {
                DashboardArrangementSheet(
                    isPresented: $showArrangementSheet,
                    dashboardItemOrder: $dashboardItemOrder,
                    summaryCardsOrder: $summaryCardsOrder
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .task {
                guard !hasStartedBackgroundRefresh else { return }
                hasStartedBackgroundRefresh = true
                liveLoadSnapshot = calculateLatestLoadSnapshot()
                await refreshDashboardMetricsInBackground()
            }
            .onChange(of: layoutSettings) { _, newValue in
                guard hasLoadedLayoutSettings else { return }
                DashboardLayoutPersistence.save(newValue)
            }
            .onChange(of: engine.workoutAnalytics.count) { _, _ in
                liveLoadSnapshot = calculateLatestLoadSnapshot()
            }
            .onChange(of: engine.workoutAnalytics.last?.workout.endDate) { _, _ in
                liveLoadSnapshot = calculateLatestLoadSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                let saved = DashboardLayoutPersistence.load()
                groupSummaryCards = saved.groupSummaryCards
                dashboardItemOrder = saved.dashboardItemOrder
                summaryCardsOrder = saved.summaryCardsOrder
            }
        }
    }

    private func refreshDashboardMetricsInBackground() async {
        guard !isRefreshingDashboardMetrics else { return }
        isRefreshingDashboardMetrics = true
        defer { isRefreshingDashboardMetrics = false }

        engine.refreshAllMetrics()
        if !hasEnoughLoadedWorkoutsForDashboard {
            await engine.refreshWorkoutAnalytics(days: 35)
        }
        liveLoadSnapshot = calculateLatestLoadSnapshot()
    }

    // MARK: - Dashboard Sections as ViewBuilder functions

    @ViewBuilder
    private func dashboardItemsSection() -> some View {
        ForEach(dashboardItemOrder, id: \.self) { item in
            Group {
                // Show the collapsible button before Summary Cards
                if item == "SummaryCards" {
                    HStack {
                        Button(action: { withAnimation { groupSummaryCards.toggle() }
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()}) {
                            HStack(spacing: 6) {
                                Image(systemName: groupSummaryCards ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Summary Cards")
                                    .font(.headline)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                switch item {
                case "SummaryCards":
                    if groupSummaryCards {
                        summaryCardsTabView()
                    } else {
                        summaryCardsInline()
                    }
                case "HRVTrend":
                    hrvTrendSection()
                default:
                    EmptyView()
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
                .padding(.bottom)
                .padding(.horizontal)
            }
        }
        .frame(height: 200)
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
    private func hrvTrendSection() -> some View {
        VStack(spacing: 8) {
            // Chart Filters - pill-shaped buttons
            HStack(spacing: 12) {
                ForEach(ChartRange.allCases, id: \.self) { range in
                    Button(action: { selectedChartRange = range
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()}) {
                        Text(range.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(selectedChartRange == range ? .white : .accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .background(
                        Capsule()
                            .fill(selectedChartRange == range ? Color.accentColor : Color.gray.opacity(0.2))
                    )
                    .buttonStyle(.glass)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)

            // HRV Trend Chart
            VStack(alignment: .leading) {
                Text("HRV Trend")
                    .font(.headline)
                    .padding(.horizontal)
                let chartPoints = chartData(
                    for: engine.dailyHRV,
                    sampleHistory: engine.hrvSampleHistory
                )
                Chart {
                    ForEach(chartPoints, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("HRV", point.value)
                        )
                        .foregroundStyle(.green)
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)

                Text(hrvTrendSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
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
        VStack(alignment: .leading) {
            Text("Training Load (ACWR)")
                .font(.headline)
                .padding(.horizontal)
            HStack {
                Text("Acute: \(String(format: "%.1f", snapshot.acuteLoad))")
                Spacer()
                Text("ACWR: \(String(format: "%.2f", snapshot.acwr))")
            }
            .padding(.horizontal)
            Text(loadSummary.detail)
                .font(.caption)
                .foregroundColor(loadSummary.color)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func navigationLinksSection() -> some View {
        VStack(spacing: 10) {
            NavigationLink("Recovery Details", destination: RecoveryScoreView())
            NavigationLink("Readiness Details", destination: ReadinessCheckView())
            NavigationLink("Strain & Recovery", destination: StrainRecoveryView())
            NavigationLink("Fuel Check", destination: FuelCheckView())
        }
        .padding(.vertical)
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
                    .padding(.horizontal)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if isAvailable {
                        Text(String(format: "%.0f", score))
                            .font(.system(size: 36, weight: .bold))
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
        Button {
            HapticFeedback.selection()
            activeDetailView = .metric(metric)
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
        .sheet(isPresented: Binding(
            get: { 
                if case .metric(let m) = activeDetailView, m == metric { return true } else { return false }
            },
            set: { if !$0 { activeDetailView = .none } }
        )) {
            MetricDetailModal(
                engine: engine,
                metric: metric
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // Chart Data Filter
    private func chartData(
        for dailyHRV: [HealthStateEngine.DailyHRVPoint],
        sampleHistory: [HealthStateEngine.HRVSamplePoint]
    ) -> [HRVChartPoint] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedChartRange {
        case .day24h:
            guard let start = calendar.date(byAdding: .hour, value: -24, to: now) else { return [] }
            return sampleHistory
                .filter { $0.date >= start && $0.date <= now }
                .map { HRVChartPoint(date: $0.date, value: $0.value) }
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
    
    let mainItems = [
        ("A", "Summary Cards", ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]),
        ("B", "HRV Trend", [])
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Arrange Dashboard")
                            .font(.largeTitle.bold())
                        Text("Reorder the major dashboard blocks and the summary cards inside the summary section.")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Dashboard Layout")
                            .font(.headline)

                        ForEach(0..<localDashboardOrder.count, id: \.self) { mainIndex in
                            let mainItemName = localDashboardOrder[mainIndex]
                            let letter = mainItemName == "SummaryCards" ? "A" : "B"
                            let displayName = mainItemName == "SummaryCards" ? "Summary Cards" : "HRV Trend"

                            VStack(alignment: .leading, spacing: 12) {
                                Text(letter + ". " + displayName)
                                    .font(.subheadline.weight(.semibold))

                                if mainItemName == "SummaryCards" {
                                    ForEach(0..<localSummaryCardsOrder.count, id: \.self) { itemIndex in
                                        HStack {
                                            Text("\(itemIndex + 1). \(localSummaryCardsOrder[itemIndex])")
                                            Spacer()
                                            if isEditingMode {
                                                HStack(spacing: 8) {
                                                    Button {
                                                        if itemIndex > 0 {
                                                            localSummaryCardsOrder.swapAt(itemIndex, itemIndex - 1)
                                                        }
                                                    } label: {
                                                        Image(systemName: "chevron.up")
                                                    }
                                                    Button {
                                                        if itemIndex < localSummaryCardsOrder.count - 1 {
                                                            localSummaryCardsOrder.swapAt(itemIndex, itemIndex + 1)
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
                            }
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        if isEditingMode {
                            Button {
                                if localDashboardOrder.count == 2 {
                                    localDashboardOrder.swapAt(0, 1)
                                }
                            } label: {
                                Label("Swap A & B", systemImage: "arrow.up.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
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
                    .foregroundColor(.blue)
                }
            }
            .onAppear {
                localDashboardOrder = dashboardItemOrder
                localSummaryCardsOrder = summaryCardsOrder
            }
        }
    }
}
