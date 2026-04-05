import SwiftUI
import HealthKit
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

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
        .fullScreenCover(isPresented: $showSheet) {
            HealthLineChartSheet(data: data, label: label, unit: unit, color: color)
        }
    }
}

// Main technical view for strain/recovery analytics

struct StrainRecoveryView: View {
    @StateObject private var engine = HealthStateEngine.shared
    @StateObject private var aggressiveCachingController = StrainRecoveryAggressiveCachingController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationPhase: Double = 0
    @State private var isLoadingHistoricalCoverage = false
    @State private var showsHistoricalCoverageOverlay = false
    @State private var historicalCoverageMessage = "Loading older strain and recovery history..."
    @State private var historicalCoverageTask: Task<Void, Never>?

    enum TimeFilter: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
    }

    @State private var timeFilter: TimeFilter = .day
    @State private var sportFilter: String? = nil // nil means all sports
    @State private var selectedDate = Date()
    @State private var showingSummarySettings = false
    
    private func selectTimeFilter(_ filter: TimeFilter) {
        timeFilter = filter
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    private func handleFilterShortcut(_ index: Int) {
        let filters = TimeFilter.allCases
        guard filters.indices.contains(index) else { return }
        selectTimeFilter(filters[index])
    }
    
    private func stepSelectedDate(by value: Int) {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: Date())
        let minimumDate = MacCatalystHealthDataPolicy.isActive ? MacCatalystHealthDataPolicy.minimumAllowedDate : .distantPast
        
        guard let steppedDate = calendar.date(byAdding: timeFilter.navigationComponent, value: value, to: currentDay) else {
            return
        }
        
        selectedDate = min(max(steppedDate, minimumDate), today)
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
    
    private func jumpToToday() {
        selectedDate = Date()
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    private var minimumSelectableDate: Date {
        MacCatalystHealthDataPolicy.isActive ? MacCatalystHealthDataPolicy.minimumAllowedDate : .distantPast
    }

    private var coachSummaryAnchorDate: Date {
        summaryReportPeriod(for: timeFilter, requestedDate: selectedDate).canonicalAnchorDate
    }

    private var graphTimeFilter: TimeFilter {
        timeFilter == .day ? .week : timeFilter
    }

    @ViewBuilder
    private var strainRecoveryTimeAndSportFilters: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    strainRecoveryTimeFilterButton(filter)
                }
            }
            if !MacCatalystHealthDataPolicy.isActive {
                Spacer()
                strainRecoverySportFilterMenu
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func strainRecoveryTimeFilterButton(_ filter: TimeFilter) -> some View {
        Button {
            selectTimeFilter(filter)
        } label: {
            Text(filter.rawValue)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(timeFilter == filter ? .orange : .orange.opacity(0.3))
    }

    @ViewBuilder
    private var strainRecoverySportFilterMenu: some View {
        Menu {
            Button("All Sports") {
                sportFilter = nil
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
            ForEach(engine.workoutAnalytics.map { $0.workout.workoutActivityType.name }.unique, id: \.self) { sport in
                Button(sport.capitalized) {
                    sportFilter = sport
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }
            }
        } label: {
            HStack {
                Text(sportFilter?.capitalized ?? "All Sports")
                Image(systemName: "chevron.down")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(.orange)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var strainRecoveryCatalystNotice: some View {
        if MacCatalystHealthDataPolicy.isActive {
            Text(MacCatalystHealthDataPolicy.historyNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var strainRecoveryAISummaryBlock: some View {
        StrainRecoveryAISummarySection(
            engine: engine,
            timeFilter: timeFilter,
            sportFilter: sportFilter,
            anchorDate: coachSummaryAnchorDate,
            aggressiveCachingController: aggressiveCachingController
        )
    }

    @ViewBuilder
    private var strainRecoveryTrainingLoadSection: some View {
        if MacCatalystHealthDataPolicy.isActive {
            MetricSectionGroup(title: "Training Load") {
                StrainRecoveryCatalystInfoCard(title: "Workout Insights") {
                    Text("Workout analytics are unavailable on Mac Catalyst.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            MetricSectionGroup(title: "Training Load") {
                StrainRecoveryMathSection(
                    engine: engine,
                    headlineTimeFilter: timeFilter,
                    chartTimeFilter: graphTimeFilter,
                    anchorDate: selectedDate
                )
                WorkoutContributionsSection(
                    engine: engine,
                    headlineTimeFilter: timeFilter,
                    chartTimeFilter: graphTimeFilter,
                    anchorDate: selectedDate,
                    sportFilter: nil
                )
                METAggregatesSection(
                    engine: engine,
                    headlineTimeFilter: timeFilter,
                    chartTimeFilter: graphTimeFilter,
                    sportFilter: sportFilter,
                    anchorDate: selectedDate
                )
                TrainingScheduleSection(
                    engine: engine,
                    sportFilter: sportFilter,
                    headlineTimeFilter: timeFilter,
                    chartTimeFilter: graphTimeFilter,
                    anchorDate: selectedDate
                )
                VO2AggregatesSection(
                    engine: engine,
                    headlineTimeFilter: timeFilter,
                    chartTimeFilter: graphTimeFilter,
                    sportFilter: sportFilter,
                    anchorDate: selectedDate
                )
            }
        }
    }

    @ViewBuilder
    private var strainRecoveryRecoverySection: some View {
        MetricSectionGroup(title: "Recovery") {
            RecoveryScoreSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            ReadinessScoreSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            HRVSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            RestingHeartRateSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            HRRAggregatesSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                sportFilter: sportFilter,
                anchorDate: selectedDate
            )
            RespiratoryRateSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            WristTemperatureSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            SpO2Section(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
        }
    }

    @ViewBuilder
    private var strainRecoverySleepSection: some View {
        MetricSectionGroup(title: "Sleep") {
            SleepRecoverySection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            SleepConsistencySection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
            SleepHeartRateSection(
                engine: engine,
                headlineTimeFilter: timeFilter,
                chartTimeFilter: graphTimeFilter,
                anchorDate: selectedDate
            )
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            strainRecoveryTimeAndSportFilters
                            strainRecoveryCatalystNotice
                            strainRecoveryAISummaryBlock
                            strainRecoveryTrainingLoadSection
                            strainRecoveryRecoverySection
                            strainRecoverySleepSection
                        }
                        .frame(maxWidth: max(0, geometry.size.width - 32), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .allowsHitTesting(!aggressiveCachingController.isActive)
                    .blur(radius: aggressiveCachingController.isActive ? 3 : 0)

                    if aggressiveCachingController.isActive {
                        aggressiveCachingOverlay
                    } else if showsHistoricalCoverageOverlay {
                        historicalCoverageOverlay
                    }
                }
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
                        jumpToToday()
                    } label: {
                        Text("Today")
                    }

                    Button {
                        showingSummarySettings = true
                    } label: {
                        Image(systemName: "gearshape")
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
                        in: minimumSelectableDate...Date(),
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
            .onChange(of: selectedDate) { _, newValue in
                guard MacCatalystHealthDataPolicy.isActive else { return }
                let clamped = max(Calendar.current.startOfDay(for: newValue), minimumSelectableDate)
                if clamped != newValue {
                    selectedDate = clamped
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlToday)) { _ in
                jumpToToday()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlPrevious)) { _ in
                stepSelectedDate(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlNext)) { _ in
                guard canStepForward else { return }
                stepSelectedDate(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter1)) { _ in
                handleFilterShortcut(0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter2)) { _ in
                handleFilterShortcut(1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter3)) { _ in
                handleFilterShortcut(2)
            }
            .task(id: historicalCoverageKey) {
                await ensureHistoricalCoverageIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                historicalCoverageTask?.cancel()
                isLoadingHistoricalCoverage = false
                AppResourceCoordinator.shared.setStrainRecoveryForegroundCritical(false)
            }
            .sheet(isPresented: $showingSummarySettings) {
                StrainRecoverySummarySettingsView(
                    engine: engine,
                    aggressiveCachingController: aggressiveCachingController
                )
            }
            .onDisappear {
                historicalCoverageTask?.cancel()
            }
        }
    }

    private var historicalCoverageKey: String {
        "\(timeFilter.rawValue)-\(Calendar.current.startOfDay(for: selectedDate).timeIntervalSinceReferenceDate)"
    }

    @MainActor
    private func ensureHistoricalCoverageIfNeeded() async {
        historicalCoverageTask?.cancel()
        
        let calendar = Calendar.current
        let window = chartWindow(for: timeFilter, anchorDate: selectedDate)
        let historicalWindowStart = calendar.date(byAdding: .day, value: -27, to: window.start) ?? window.start
        let interactiveThreshold = calendar.date(byAdding: .day, value: -engine.interactiveWorkoutLookbackDaysForUI, to: Date()) ?? Date()
        
        guard selectedDate < interactiveThreshold else { return }
        
        let task = Task { @MainActor in
            let selectedYearStart = calendar.dateInterval(of: .year, for: selectedDate)?.start ?? window.start
            let yearPrefetchStart = calendar.date(byAdding: .day, value: -27, to: selectedYearStart) ?? selectedYearStart
            let workoutCoverageStart = min(yearPrefetchStart, historicalWindowStart)
            let vitalCoverageStart = historicalWindowStart
            let needsWorkoutCoverage = engine.needsWorkoutAnalyticsCoverage(from: workoutCoverageStart, to: window.endExclusive)
            let needsRecoveryMetricsCoverage = engine.needsRecoveryMetricsCoverage(from: vitalCoverageStart, to: window.endExclusive)
            guard needsWorkoutCoverage || needsRecoveryMetricsCoverage else { return }

            historicalCoverageMessage = "Loading \(calendar.component(.year, from: selectedDate)) training and recovery history through \(selectedDate.formatted(date: .abbreviated, time: .omitted))..."
            isLoadingHistoricalCoverage = true
            showsHistoricalCoverageOverlay = false
            let overlayTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, isLoadingHistoricalCoverage else { return }
                showsHistoricalCoverageOverlay = true
            }
            defer {
                overlayTask.cancel()
                isLoadingHistoricalCoverage = false
                showsHistoricalCoverageOverlay = false
            }

            if needsWorkoutCoverage {
                await engine.ensureWorkoutAnalyticsCoverage(from: workoutCoverageStart, to: window.endExclusive)
            }
            if needsRecoveryMetricsCoverage {
                await engine.ensureRecoveryMetricsCoverage(from: vitalCoverageStart, to: window.endExclusive)
            }
        }
        historicalCoverageTask = task
        await task.value
    }

    private var historicalCoverageOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.95)
                    Text(historicalCoverageMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Fetching only the missing history in the background.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var aggressiveCachingOverlay: some View {
        VStack(spacing: 16) {
            Text("Aggressive Cache Mode")
                .font(.title3.bold())
            if aggressiveCachingController.isPreparing {
                ProgressView()
                    .tint(.orange)
            } else {
                ProgressView(value: aggressiveCachingController.progress)
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }
            Text(aggressiveCachingController.progressPercentText)
                .font(.system(.title2, design: .rounded, weight: .bold))
            if !aggressiveCachingController.currentBatchTitle.isEmpty {
                Text("Current Batch: \(aggressiveCachingController.currentBatchTitle)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(aggressiveCachingController.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel") {
                aggressiveCachingController.requestCancel()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }
}

// MARK: - Technical Sections

import Charts

private extension StrainRecoveryView.TimeFilter {
    var dayCount: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }
    
    var navigationComponent: Calendar.Component {
        switch self {
        case .day:
            return .day
        case .week:
            return .day
        case .month:
            return .weekOfYear
        }
    }

    var summaryPeriodTitle: String {
        switch self {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        }
    }
}

private struct SummaryReportPeriod {
    let canonicalAnchorDate: Date
    let start: Date
    let end: Date
    let endExclusive: Date
    let description: String
}

private func summaryReportPeriod(
    for timeFilter: StrainRecoveryView.TimeFilter,
    requestedDate: Date
) -> SummaryReportPeriod {
    let calendar = Calendar.current
    let safeRequestedDate = calendar.startOfDay(for: requestedDate)
    let today = calendar.startOfDay(for: Date())

    switch timeFilter {
    case .day:
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: safeRequestedDate) ?? safeRequestedDate
        return SummaryReportPeriod(
            canonicalAnchorDate: safeRequestedDate,
            start: safeRequestedDate,
            end: safeRequestedDate,
            endExclusive: endExclusive,
            description: safeRequestedDate.formatted(date: .abbreviated, time: .omitted)
        )
    case .week:
        let interval = calendar.dateInterval(of: .weekOfYear, for: safeRequestedDate)
        let start = interval.map { calendar.startOfDay(for: $0.start) } ?? safeRequestedDate
        let rawEndExclusive = interval?.end ?? (calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        let rawEnd = calendar.date(byAdding: .day, value: -1, to: rawEndExclusive) ?? start
        let end = min(calendar.startOfDay(for: rawEnd), today)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        return SummaryReportPeriod(
            canonicalAnchorDate: start,
            start: start,
            end: end,
            endExclusive: endExclusive,
            description: "\(start.formatted(date: .abbreviated, time: .omitted)) to \(end.formatted(date: .abbreviated, time: .omitted))"
        )
    case .month:
        let interval = calendar.dateInterval(of: .month, for: safeRequestedDate)
        let start = interval.map { calendar.startOfDay(for: $0.start) } ?? safeRequestedDate
        let rawEndExclusive = interval?.end ?? (calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        let rawEnd = calendar.date(byAdding: .day, value: -1, to: rawEndExclusive) ?? start
        let end = min(calendar.startOfDay(for: rawEnd), today)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        return SummaryReportPeriod(
            canonicalAnchorDate: start,
            start: start,
            end: end,
            endExclusive: endExclusive,
            description: start.formatted(.dateTime.month(.wide).year())
        )
    }
}

private enum TemporaryPrimarySelection: String, CaseIterable, Identifiable {
    case off
    case oneDay
    case oneWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .oneDay: return "1 Day"
        case .oneWeek: return "1 Week"
        }
    }

    var expirationDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .off:
            return nil
        case .oneDay:
            return calendar.date(byAdding: .day, value: 1, to: Date())
        case .oneWeek:
            return calendar.date(byAdding: .day, value: 7, to: Date())
        }
    }
}

enum AggressiveCachingAction: Equatable {
    case start
    case cancel
}

@MainActor
final class StrainRecoveryAggressiveCachingController: ObservableObject {
    static let shared = StrainRecoveryAggressiveCachingController()
    static let backgroundTaskIdentifier = "com.nutrivance.strain-recovery.aggressive-caching"

    @Published var isActive = false
    @Published var completedCount = 0
    @Published var totalCount = 0
    @Published var statusText = "Preparing aggressive cache run..."
    @Published var pendingAction: AggressiveCachingAction?
    @Published var currentBatchTitle = ""

    private var activeTask: Task<Void, Never>? = nil
#if canImport(BackgroundTasks)
    private var activeBackgroundTask: BGProcessingTask?
#endif

    private init() {}

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var isPreparing: Bool {
        isActive && totalCount == 0
    }

    var progressPercentText: String {
        guard totalCount > 0 else { return "Preparing..." }
        return "\(Int((progress * 100).rounded()))%"
    }

    func requestStart() {
        isActive = true
        completedCount = 0
        totalCount = 0
        statusText = "Preparing aggressive cache run..."
        pendingAction = .start
    }

    func requestCancel() {
        pendingAction = .cancel
    }

    func begin(totalCount: Int, completedCount: Int = 0, statusText: String, batchTitle: String = "") {
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.statusText = statusText
        self.currentBatchTitle = batchTitle
        self.isActive = true
    }

    func advance(statusText: String, batchTitle: String = "") {
        completedCount = min(completedCount + 1, totalCount)
        self.statusText = statusText
        self.currentBatchTitle = batchTitle
    }

    func finish(statusText: String) {
        self.statusText = statusText
        self.currentBatchTitle = ""
        self.isActive = false
        self.pendingAction = nil
    }

    func reset() {
        isActive = false
        completedCount = 0
        totalCount = 0
        statusText = "Preparing aggressive cache run..."
        currentBatchTitle = ""
        pendingAction = nil
    }

    func startIfNeeded() async {
        guard activeTask == nil else { return }

        let plan = await aggressiveCachingPlan()
        let totalBatchCount = plan.batches.count
        let completedBatchCount = plan.completedBatchCount
        let pendingBatches = plan.pendingBatches

        guard plan.isEligible else {
            markAggressiveCachingRequested(false)
            finish(statusText: "Aggressive cache mode is only available on the current primary Apple Intelligence device.")
            return
        }

        guard totalBatchCount > 0 else {
            markAggressiveCachingRequested(false)
            finish(statusText: "No coach summary batches are available for aggressive caching right now.")
            return
        }

        guard !pendingBatches.isEmpty else {
            markAggressiveCachingRequested(false)
            begin(
                totalCount: totalBatchCount,
                completedCount: totalBatchCount,
                statusText: "All day batches already have synced Apple Intelligence summaries."
            )
            finish(statusText: "All day batches already have synced Apple Intelligence summaries.")
            return
        }

        markAggressiveCachingRequested(true)
        scheduleBackgroundProcessingIfNeeded()
        begin(
            totalCount: totalBatchCount,
            completedCount: completedBatchCount,
            statusText: "Preparing \(pendingBatches.count) remaining day batches for Apple Intelligence generation and sync...",
            batchTitle: pendingBatches.first?.title ?? ""
        )

        activeTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            await self.runPendingBatches(pendingBatches, totalBatchCount: totalBatchCount)
        }
    }

    func cancelByUser() {
        activeTask?.cancel()
        activeTask = nil
        markAggressiveCachingRequested(false)
#if canImport(BackgroundTasks)
        activeBackgroundTask?.setTaskCompleted(success: false)
        activeBackgroundTask = nil
#endif
        reset()
    }

    func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        guard scenePhase == .background else { return }
        Task {
            if await shouldContinueAggressiveCachingInBackground() {
                scheduleBackgroundProcessingIfNeeded()
            }
        }
    }

    func registerBackgroundTasks() {
#if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self.handleBackgroundProcessingTask(processingTask)
            }
        }
#endif
    }

    private func runPendingBatches(
        _ batches: [StrainRecoveryAggressiveCachingDayBatch],
        totalBatchCount: Int
    ) async {
        for (index, batch) in batches.enumerated() {
            if Task.isCancelled { break }
            currentBatchTitle = batch.title
            statusText = "Processing \(batch.title) • \(index + 1) of \(batches.count) remaining day batches"

            for (requestIndex, request) in batch.pendingRequests.enumerated() {
                if Task.isCancelled { break }
                let latestCache = StrainRecoverySummaryPersistence.load()
                if let existing = latestCache[request.requestID], existing.source == .appleIntelligence {
                    statusText = "Skipping cached \(request.selectedSuggestionTitle) for \(batch.title) • \(request.timeFilter.rawValue) already has Apple Intelligence."
                    continue
                }
                statusText = "Generating \(request.selectedSuggestionTitle) • \(requestIndex + 1) of \(batch.pendingRequests.count) for \(batch.title)"
                _ = await generateAggressiveCachingSummary(for: request)
            }

            if Task.isCancelled { break }

            advance(
                statusText: "Synced batch \(min(completedCount + 1, totalBatchCount)) of \(totalBatchCount) • \(batch.title)",
                batchTitle: batch.title
            )
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        activeTask = nil
#if canImport(BackgroundTasks)
        activeBackgroundTask?.setTaskCompleted(success: !Task.isCancelled)
        activeBackgroundTask = nil
#endif

        if Task.isCancelled {
            if await markAggressiveCachingRequestedIfWorkRemains() {
                scheduleBackgroundProcessingIfNeeded()
            }
            finish(statusText: "Aggressive cache run paused. Finished summaries are already stored and synced.")
        } else {
            markAggressiveCachingRequested(false)
            finish(statusText: "Aggressive cache run finished. All completed summaries were stored and synced immediately.")
        }
    }

#if canImport(BackgroundTasks)
    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        Task { @MainActor in
            guard await shouldContinueAggressiveCachingInBackground() else {
                task.setTaskCompleted(success: true)
                return
            }

            activeBackgroundTask = task
            task.expirationHandler = { [weak self] in
                Task { @MainActor in
                    self?.activeTask?.cancel()
                    self?.activeTask = nil
                    self?.activeBackgroundTask?.setTaskCompleted(success: false)
                    self?.activeBackgroundTask = nil
                    if await self?.markAggressiveCachingRequestedIfWorkRemains() == true {
                        self?.scheduleBackgroundProcessingIfNeeded()
                    }
                }
            }

            await self.startIfNeeded()
        }
    }
#endif

    private func hasRemainingAggressiveCachingWork() async -> Bool {
        await aggressiveCachingPlan().pendingBatches.isEmpty == false
    }

    @discardableResult
    private func markAggressiveCachingRequestedIfWorkRemains() async -> Bool {
        let stillHasWork = await hasRemainingAggressiveCachingWork()
        markAggressiveCachingRequested(stillHasWork)
        return stillHasWork
    }

    private func shouldContinueAggressiveCachingInBackground() async -> Bool {
        let settings = StrainRecoverySummaryPersistence.loadSyncSettings()
        guard settings.aggressiveCachingRequested else { return false }
        return await hasRemainingAggressiveCachingWork()
    }

    private func markAggressiveCachingRequested(_ requested: Bool) {
        var settings = StrainRecoverySummaryPersistence.loadSyncSettings()
        settings.aggressiveCachingRequested = requested
        settings.intensiveFetchingEnabled = false
        StrainRecoverySummaryPersistence.saveSyncSettings(settings)
    }

    private func scheduleBackgroundProcessingIfNeeded() {
#if canImport(BackgroundTasks)
        Task {
            guard await shouldContinueAggressiveCachingInBackground() else { return }

            let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = false

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                // Failing to submit a background request should not interrupt the current aggressive caching run.
            }
        }
#endif
    }
}

private struct StrainRecoveryAggressiveCachingDayBatch {
    let anchorDate: Date
    let pendingRequests: [StrainRecoverySummaryRequest]

    var title: String {
        anchorDate.formatted(date: .abbreviated, time: .omitted)
    }
}

enum AggressiveSyncSelectionMode: String, Codable, CaseIterable, Identifiable {
    case expectedCache = "fullMonth"
    case selectedTimeRange = "selectedDate"
    case selectedReportType = "reportType"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expectedCache:
            return "Expected Cache"
        case .selectedTimeRange:
            return "Selected Time Range"
        case .selectedReportType:
            return "Selected Report Type"
        }
    }
}

enum AggressiveSyncTimeRangeType: String, Codable, CaseIterable, Identifiable {
    case weekOfDays
    case monthOfWeeks
    case yearOfMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekOfDays:
            return "Week Of Day Reports"
        case .monthOfWeeks:
            return "Month Of Week Reports"
        case .yearOfMonths:
            return "Year Of Month Reports"
        }
    }

    var detail: String {
        switch self {
        case .weekOfDays:
            return "Fetch all 1D reports for the calendar week containing the selected date."
        case .monthOfWeeks:
            return "Fetch all shared 1W reports that intersect the calendar month containing the selected date."
        case .yearOfMonths:
            return "Fetch all shared 1M reports for the calendar year containing the selected date."
        }
    }
}

private struct AggressiveSyncSelection {
    let mode: AggressiveSyncSelectionMode
    let timeRangeType: AggressiveSyncTimeRangeType
    let selectedDate: Date
    let selectedSuggestionID: String?
}

@MainActor
private func aggressiveCachingAnchorDates(
    for timeFilter: StrainRecoveryView.TimeFilter,
    relativeTo today: Date
) -> [Date] {
    let calendar = Calendar.current
    let safeToday = calendar.startOfDay(for: today)

    switch timeFilter {
    case .day:
        return (0..<28).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: safeToday)
        }
    case .week:
        return (0..<5).compactMap {
            guard let date = calendar.date(byAdding: .weekOfYear, value: -$0, to: safeToday) else { return nil }
            return summaryReportPeriod(for: .week, requestedDate: date).canonicalAnchorDate
        }
    case .month:
        return (0..<60).compactMap {
            guard let date = calendar.date(byAdding: .month, value: -$0, to: safeToday) else { return nil }
            return summaryReportPeriod(for: .month, requestedDate: date).canonicalAnchorDate
        }
    }
}

@MainActor
private func aggressiveCachingScopes(
    for selection: AggressiveSyncSelection,
    relativeTo today: Date
) -> [(filter: StrainRecoveryView.TimeFilter, anchors: [Date])] {
    let calendar = Calendar.current
    let safeToday = calendar.startOfDay(for: today)

    switch selection.mode {
    case .expectedCache:
        return [
            (.day, aggressiveCachingAnchorDates(for: .day, relativeTo: safeToday)),
            (.week, aggressiveCachingAnchorDates(for: .week, relativeTo: safeToday)),
            (.month, aggressiveCachingAnchorDates(for: .month, relativeTo: safeToday))
        ]
    case .selectedTimeRange, .selectedReportType:
        switch selection.timeRangeType {
        case .weekOfDays:
            let weekPeriod = summaryReportPeriod(for: .week, requestedDate: selection.selectedDate)
            let dayAnchors = dateSequence(from: weekPeriod.start, to: weekPeriod.end)
            return [(.day, dayAnchors)]
        case .monthOfWeeks:
            let monthPeriod = summaryReportPeriod(for: .month, requestedDate: selection.selectedDate)
            var weekAnchors: [Date] = []
            var seenWeekAnchors = Set<Date>()
            for date in dateSequence(from: monthPeriod.start, to: monthPeriod.end) {
                let weekAnchor = summaryReportPeriod(for: .week, requestedDate: date).canonicalAnchorDate
                if seenWeekAnchors.insert(weekAnchor).inserted {
                    weekAnchors.append(weekAnchor)
                }
            }
            return [(.week, weekAnchors.sorted())]
        case .yearOfMonths:
            guard let yearInterval = calendar.dateInterval(of: .year, for: selection.selectedDate) else {
                return []
            }
            let yearStart = calendar.startOfDay(for: yearInterval.start)
            let rawYearEnd = calendar.date(byAdding: .day, value: -1, to: yearInterval.end) ?? yearStart
            let yearEnd = min(calendar.startOfDay(for: rawYearEnd), safeToday)
            guard yearStart <= yearEnd else { return [] }

            var monthAnchors: [Date] = []
            var cursor = yearStart
            while cursor <= yearEnd {
                monthAnchors.append(summaryReportPeriod(for: .month, requestedDate: cursor).canonicalAnchorDate)
                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = nextMonth
            }
            return [(.month, monthAnchors)]
        }
    }
}

private struct StrainRecoveryAggressiveCachingPlan {
    let isEligible: Bool
    let batches: [StrainRecoveryAggressiveCachingDayBatch]
    let completedBatchCount: Int

    var pendingBatches: [StrainRecoveryAggressiveCachingDayBatch] {
        batches.filter { !$0.pendingRequests.isEmpty }
    }
}

@MainActor
private func aggressiveCachingPlan() async -> StrainRecoveryAggressiveCachingPlan {
    let settings = StrainRecoverySummaryPersistence.loadSyncSettings()
    guard settings.isPrimary(deviceID: StrainRecoverySummaryDevice.current.id),
          deviceSupportsAppleIntelligence() else {
        return StrainRecoveryAggressiveCachingPlan(
            isEligible: false,
            batches: [],
            completedBatchCount: 0
        )
    }

    let today = Date()
    let cache = StrainRecoverySummaryPersistence.load()
    let selection = AggressiveSyncSelection(
        mode: settings.aggressiveSyncSelectionMode,
        timeRangeType: settings.aggressiveSyncTimeRangeType,
        selectedDate: settings.aggressiveSyncSelectedDate,
        selectedSuggestionID: settings.aggressiveSyncSelectedSuggestionID
    )
    var batches: [StrainRecoveryAggressiveCachingDayBatch] = []
    var completedBatchCount = 0

    let filterScopes = aggressiveCachingScopes(for: selection, relativeTo: today)

    for scope in filterScopes {
        for date in scope.anchors {
            var pendingRequests: [StrainRecoverySummaryRequest] = []
            var seen = Set<String>()
            let suggestions = SummarySuggestion.buildSuggestions(
                engine: HealthStateEngine.shared,
                timeFilter: scope.filter,
                sportFilter: nil,
                anchorDate: date
            )

            for suggestion in suggestions {
                if selection.mode == .selectedReportType,
                   suggestion.id != selection.selectedSuggestionID {
                    continue
                }

                let request = await StrainRecoverySummaryRequest.build(
                    engine: HealthStateEngine.shared,
                    timeFilter: scope.filter,
                    sportFilter: nil,
                    anchorDate: date,
                    intentText: suggestion.queryText,
                    selectedSuggestion: suggestion,
                    refreshVersion: 0
                )
                guard seen.insert(request.requestID).inserted else { continue }
                if let existing = cache[request.requestID], existing.source == .appleIntelligence {
                    continue
                }
                pendingRequests.append(request)
            }

            if pendingRequests.isEmpty {
                completedBatchCount += 1
            }

            batches.append(
                StrainRecoveryAggressiveCachingDayBatch(
                    anchorDate: date,
                    pendingRequests: pendingRequests
                )
            )
        }
    }

    return StrainRecoveryAggressiveCachingPlan(
        isEligible: true,
        batches: batches,
        completedBatchCount: completedBatchCount
    )
}

@MainActor
@discardableResult
private func generateAggressiveCachingSummary(
    for request: StrainRecoverySummaryRequest
) async -> Bool {
    let cache = StrainRecoverySummaryPersistence.load()
    if let existing = cache[request.requestID], existing.source == .appleIntelligence {
        return true
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else {
            return false
        }

        do {
            let compactPrompt = enforceCoachPromptBudget(
                promptWithSiblingTimeFilterContext(for: request, cache: cache),
                timeFilter: request.timeFilter,
                instructions: strainRecoveryModelInstructions
            )
            let cleaned = try await generateValidatedAggressiveCachingSummary(
                model: model,
                prompt: compactPrompt
            )
            guard !cleaned.isEmpty else { return false }

            let entry = aggressiveCachingCacheEntry(
                for: request,
                summaryText: cleaned,
                statusText: aggressiveCachingLiveStatusText(
                    for: .background,
                    source: .appleIntelligence
                ),
                source: .appleIntelligence
            )
            StrainRecoverySummaryPersistence.saveEntry(entry)
            return true
        } catch {
            return false
        }
    }
    #endif

    return false
}

@available(iOS 26.0, *)
private func generateValidatedAggressiveCachingSummary(
    model: SystemLanguageModel,
    prompt: String
) async throws -> String {
    let maxAttempts = 3
    var effectivePrompt = prompt

    let totalEstimate = approximateTokenCount(strainRecoveryCoachInstructions)
        + approximateTokenCount(effectivePrompt)
        + coachReservedResponseTokens
    if totalEstimate > coachMaximumContextTokens - 100 {
        let safeBudget = coachMaximumContextTokens
            - approximateTokenCount(strainRecoveryCoachInstructions)
            - coachReservedResponseTokens - 100
        effectivePrompt = trimPromptToTokenBudget(
            abstractPromptToLevel(effectivePrompt, level: 1),
            budget: max(400, safeBudget)
        )
    }

    var didShrinkForContextOverflow = false

    for _ in 0..<maxAttempts {
        let session = LanguageModelSession(
            model: model,
            instructions: strainRecoveryModelInstructions
        )

        let cleaned: String
        do {
            let response = try await session.respond(
                to: effectivePrompt,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0,
                    maximumResponseTokens: coachReservedResponseTokens
                )
            )
            cleaned = collapseToSingleParagraph(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            let desc = String(describing: error)
            if desc.contains("exceededContextWindowSize") || desc.contains("exceeds the maximum allowed context size") {
                guard !didShrinkForContextOverflow else { throw error }
                didShrinkForContextOverflow = true
                effectivePrompt = trimPromptToTokenBudget(
                    abstractPromptToLevel(effectivePrompt, level: 2),
                    budget: max(400, approximateTokenCount(effectivePrompt) * 6 / 10)
                )
                continue
            }
            throw error
        }

        if !cleaned.isEmpty,
           !looksLikeInvalidAggressiveCachingSummary(cleaned),
           !containsDisallowedCoachFormatting(cleaned),
           !(effectivePrompt.contains(CoachPromptFragments.noSuggestions) && containsDisallowedAdvice(cleaned)) {
            return cleaned
        }
    }

    return ""
}

private func looksLikeInvalidAggressiveCachingSummary(_ summary: String) -> Bool {
    let normalized = summary
        .lowercased()
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")

    let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return true
    }

    let tokens = trimmed
        .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        .filter { !$0.isEmpty }

    if tokens.count < 40 {
        return true
    }

    let bigrams = zip(tokens, tokens.dropFirst()).map { "\($0.0) \($0.1)" }
    let bigramCounts = Dictionary(bigrams.map { ($0, 1) }, uniquingKeysWith: +)
    let repeatedBigrams = bigramCounts.values.filter { $0 >= 3 }.count
    if repeatedBigrams >= 2 {
        return true
    }

    let suspiciousPhrases = [
        "again and again",
        "over and over",
        "again again",
        "it is junk",
        "junk output"
    ]

    if suspiciousPhrases.contains(where: normalized.contains) {
        return true
    }

    return containsRepeatedPhrase(in: summary)
}

private func containsRepeatedPhrase(in text: String) -> Bool {
    let sentences = text
        .components(separatedBy: CharacterSet(charactersIn: ".!?"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty && $0.count > 100 }

    var sentenceCounts: [String: Int] = [:]
    for sentence in sentences {
        sentenceCounts[sentence, default: 0] += 1
    }
    if sentenceCounts.values.contains(where: { $0 >= 2 }) {
        print("[CoachAI][repeat] exact duplicate sentence detected")
        return true
    }

    let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    guard words.count > 120 else { return false }
    for phraseLength in [40, 50] {
        guard words.count > phraseLength * 3 else { continue }
        var phraseCounts: [String: Int] = [:]
        for i in 0..<(words.count - phraseLength) {
            let phrase = words[i..<(i + phraseLength)].joined(separator: " ")
            phraseCounts[phrase, default: 0] += 1
        }
        if phraseCounts.values.contains(where: { $0 >= 3 }) {
            print("[CoachAI][repeat] phrase loop detected (window=\(phraseLength), 3+ occurrences)")
            return true
        }
    }

    return false
}

private let strainRecoveryCoachInstructions = """
You are an experienced athletic performance coach writing exactly one short paragraph in plain text.
- Address the reader as \"you\" (second person). Do not refer to them as \"the athlete\" or other third-person labels for the person using the app.
- Sound human, not templated: avoid repeating the same scaffold (e.g. \"Your [metric] is…\", \"Your [score] shows…\") sentence after sentence. Mix subject and lead-in—sometimes start with the situation, the comparison, the date, or a short clause about load or recovery, then tie it to \"you\" where it fits. Use connectors (notably, still, meanwhile, that said, overall) so rhythm varies.
- Limit \"your\" to roughly once or twice in the paragraph unless grammar truly needs more; prefer varied phrasing like \"strain landed at…\", \"recovery reads…\", \"readiness sits…\", \"the window shows…\", \"that combination suggests…\".
- Vary how sentences begin: avoid many consecutive sentences that all start with \"You.\" Use natural connectors and transitions (e.g. notably, however, in addition, meanwhile, still, overall, that said) and occasional observational openers so the paragraph flows; keep it clear you are still speaking to the same person.
- Use actual numbers and dates from the prompt.
- Stay inside the allowed scope for the selected report.
- Treat secondary context as factual support, not the main topic.
- If evidence is thin, say so briefly instead of guessing.
- Do not invent trends, personal bests, warnings, or missing metrics.
- When the prompt includes [7D] or multi-day series alongside anchor-day scores, use that recent data only to judge where today sits (load rhythm, recovery tilt, consistency). Keep the answer sounding like a same-day coaching read: do not open with a week recap or enumerate the trailing window unless one short clause is truly needed. Never call a rolling or weekly figure \"today\" unless the prompt labels it as that day only.
- No bullets, numbering, headings, or line breaks.
"""

private let strainRecoveryModelInstructions = strainRecoveryCoachInstructions
private let strainRecoverySessionInstructions = strainRecoveryCoachInstructions

/// Coach-facing label: value is peak HR minus HR ~2 min after workout end (bpm dropped). Larger = faster recovery.
private let coachHRRMetricDisplayName = "HRR drop (peak − HR @2 min)"

private struct CoachPromptFragments {
    static let noMarkdown = "- Output exactly one paragraph of plain text with no bullets, numbering, headings, or line breaks."
    static let noInvention = "- Every meaningful claim must be traceable to a number or label in the prompt. If the data is thin, say so briefly."
    static let noRenamedCompositeScores = "- Do not invent or rename composite scores (for example \"performance score\"). Only use explicitly named metrics in the prompt: Strain /21, Recovery /100, Readiness /100, session load points, Window total training load points (sum of daily training load, same scale as [7D] Recent training load), internal effort-rating sum (only when printed), MET Minutes (cumulative), Refined HRR lines when printed, and other labels exactly as printed."
    static let hrrDropSemantics = "- \(coachHRRMetricDisplayName) when printed as a bpm drop is peak heart rate during the workout minus the post-workout heart rate sample closest to two minutes after workout end; larger drop means faster recovery (more bpm fallen), not a higher exercising heart rate. When a line begins with \"Refined\", it uses static vs active anchor from late-peak vs end HR (see confidence and scenario). Lines that say \"HRR 2m delta omitted\" suppress primary 2m deltas because late peak was within 30 bpm of resting HR. \"Recovery power\" is the steepest mean HR fall over ~10 seconds within 5 minutes after the late peak (bpm/s). \"HRR recovery proxy\" is a comparable scalar derived from recovery power when 2m is not primary—not the same units as bpm drop. \"HRR steady-state\" means near equilibrium vs anchor/resting—do not treat small negative 2m noise as pathology."
    static let metMinutesSemantics = "- MET Minutes are cumulative workload units from integrating MET over workout time, not a capped 0–100 score, percentage, or \"out of 1000\"; when a same-type prior-7d MET baseline line is present, use it for relative load, not an imaginary scale."
    static let priorDayVersusSevenDayRule = "- Prior calendar day vs series: use the line starting with [PRIOR_DAY] for \"yesterday\" Recovery and Readiness. Do not treat any value in [7D] Recovery or [7D] Readiness as yesterday unless that series entry's date equals the [PRIOR_DAY] date."
    static let citeOnlyPrintedMetricsReadiness = "- Anti-fabrication: Do not mention HRR, MET Minutes, session load points, Avg Power, or Avg Cadence unless this prompt prints that exact metric with a value (or an explicit \"unavailable\" line for it). Do not invent decimals such as \"11.5\" for load."
    static let weekTrendNarrative = "- Filter 1W / 1M: Default to period trends across the window. Do not center the narrative on today versus yesterday unless those exact calendar dates appear in the prompt. Whenever you cite a number, tie it to the date(s) shown."
    static let todayActionable = "- The answer must help with today's decision, not drift into a generic recap."
    static let statementOfFactOnly = "- Keep this report factual and observational."
    static let noSuggestions = "- DO NOT give advice, prescriptions, recommendations, or next steps. Avoid phrases like you should, try to, consider, next time, or focus on next."
    static let noShaming = "- Do not shame missed sessions or missing metrics. Focus on completed work and neutral phrasing."
    static let holdSteadyNotReduce = "- If caution is needed, prefer hold steady or stay controlled. Do not encourage cutting time or intensity unless the data explicitly demands it."
    static let useUIMetricNames = "- Use the exact metric labels from the prompt such as MET Minutes, Recovery, Readiness, Time in Zone 4, Time in Zone 5, Avg HR, \(coachHRRMetricDisplayName), Avg Power (only when present in the prompt), and Avg Cadence (only when present in the prompt). For distance, speed, and elevation, use only the unit system stated in the Unit contract line of this prompt."
    static let missingDataBehavior = "- If a metric family is unavailable, say it is limited or unavailable and continue with the remaining evidence. Never fabricate a replacement trend."
    static let bridgeToOtherData = "- Only when the primary evidence is genuinely thin, you may add one brief adjacent-domain bridge sentence. Do not switch topics."
    static let atypicalSessionDetection = "- If sport label and physiological load look mismatched, call it atypical or uncertain rather than making a bold sport-specific claim."
    static let secondaryContextFacts = "- Secondary context is compact factual support only. Do not retell it as a separate narrative unless it directly explains the primary scope."
    /// Sport-specific suggestion buttons: model must coach from evidence, not recite the metric bundle.
    static let sportAnalysisContract = "- Deliver coaching synthesis, not a data readout: infer the dominant pattern (volume vs intensity, repeatability vs spikes, progression vs plateau, scatter or consistency) and what it implies for this discipline before naming next-session direction."
    static let sportNoMetricInventory = "- Do not restate, enumerate, or summarize the evidence block line-by-line. Weave at most two quantitative anchors into prose; skip the rest unless essential for a single interpretive claim."
    static let sportInterpretLoadSignals = "- Treat load profile, quest progress, trend lines, and standout sessions as clues to training adaptation, not as labels to repeat. Explain why they matter for performance or recovery in this sport."
    /// 1D sport report: model must not treat day-scoped Training Focus metrics as weekly rolling averages.
    static let sportOneDayWindowContract = "- 1D sport report: Training Focus metrics and session lines are for the selected calendar day only; do not describe them as past seven days, weekly averages, or multi-day rolls unless a line explicitly labels a longer window."
    /// Global for Filter 1D prompts: keep [7D] in the prompt as silent context; answer should still read day-forward.
    static let metricWindowDiscipline = "- Metric window discipline: \"Scores [ANCHOR_DAY]\" is only the selected calendar date. Lines tagged \"[7D]\" or listing multiple dates are recent background—use them to interpret today's position (not as today's raw totals). Forbidden: treating a [7D] aggregate as the anchor day's numbers or calling it \"today.\" Preferred voice: coach today directly; do not lead with \"this week\" / \"past seven days\" or narrate the weekly series unless one brief clause is needed for a single interpretive point."
    /// 1W / 1M: any directional trend must cite dates from the prompt.
    static let trendRequiresExplicitDates = "- Trend citation (1W/1M): If you describe direction or a comparison across time (rising, falling, higher, lower, improving, sliding, from one level to another, building, or fading) on any metric, you must name the calendar date(s) or period endpoints exactly as shown in the prompt for those values. Do not state an undated trend."
    /// Sport (and similar) reports: reinforce second person + smooth prose (global instructions also cover this).
    static let sportSecondPersonVoice = "- Sport-specific read: speak directly to the reader as \"you\" throughout. Never \"the athlete\" or third-person distance for them."
    static let sportProseVariety = "- Sport-specific read: prioritize one or two strong \"you\" moments; otherwise link ideas with connectors (notably, however, in addition, meanwhile, still, overall) so the paragraph does not hammer \"You\" every sentence. Avoid chained \"Your [metric] is…\" / \"Your [x] shows…\" patterns; alternate sentence shapes and openings."
}

private struct FallbackPolicy {
    let unavailableLead: String
    let allowBridge: Bool
}

private struct CoachPromptSpec {
    let primaryScope: String
    let secondaryContextPolicy: String
    let fallbackPolicy: FallbackPolicy
    let negativeConstraints: [String]
    let uiTerminologyContract: String
    let requiredFragments: [String]
    let allowsSuggestions: Bool
}

private let strainRecoveryScorePromptReference = """
Score construction reference for this app:
- Recovery is an app-defined 0 to 100 coaching score, not a raw medical lab value.
- Recovery formula in this app uses Effect HRV, a special sleep-anchored HRV signal from the main sleep block rather than raw daytime HRV. Effect HRV uses the sleep-window median and temporal momentum smoothing. Composite X = (Effect HRV z-score x 0.85) - (RHR penalty z-score x 0.25), then Recovery base = sigmoid(0.6 x (X + 1.6)) x 100.
- Recovery is strongly baseline-aware. HRV and resting heart rate are judged against your rolling 60-day baseline when available, with 7-day fallback logic if long baseline data is missing.
- Effect HRV is anchored to the main sleep block and taken from the median of valid HRV samples in the final 3 hours of sleep when possible, with a full-sleep-window fallback if those samples are missing. Resting heart rate is estimated from the lowest 5-minute heart-rate average during sleep instead of a daytime average.
- Resting heart rate only penalizes recovery when it is above your own baseline. A lower-than-baseline resting heart rate does not artificially inflate recovery by itself.
- Recovery baseline stability is protected with log-normal HRV handling and a soft HRV SD floor of at least 12 percent of the 60-day mean, plus a resting-heart-rate SD floor of at least 3 bpm.
- Final recovery uses a softened sleep scalar, a tapered circadian penalty only when bedtime variability exceeds 90 minutes, and an efficiency cap of 70 when sleep efficiency is below 85 percent.
- Strain is an app-defined 0 to 21 load score. It is built from heart-rate-zone session load using weighted zone minutes plus a small base-load term, then log-scaled so the score rises quickly early and plateaus at higher loads.
- Zone weighting in this app is exponential in feel: Zone 1 is 1x, Zone 2 is 2x, Zone 3 is 3.5x, Zone 4 is 5x, and Zone 5 is 6x.
- Max heart rate is estimated as 211 minus 0.64 times age when a measured ceiling is unavailable, and the app updates upward if a workout exceeds that estimate.
- A daily base load is added to strain at about 0.1 times active minutes, with a fallback baseline when dedicated active-minute data is not available.
- \(coachHRRMetricDisplayName) is computed as peak heart rate during the workout minus the post-workout heart rate sample whose timestamp is closest to two minutes after workout end (bpm drop). The prompt repeats that computed drop; larger drop means faster recovery; do not confuse it with post-workout absolute heart rate alone.
- MET Minutes in this app are cumulative workload units integrated over workout time, not a normalized 0 to 100 score; compare same-sport MET to the prior-7d same-type baseline when the prompt includes it.
- Window total training load points (when mentioned) is the sum of daily training load across the report window, aligned with [7D] Recent training load, not a 0 to 100 score. Internal effort-rating sum (when mentioned) is a separate internal scale.
- Practical strain reading guide for this app: 0 to 5 low, 6 to 10 building, 11 to 14 productive, 15 to 17 high, and 18 to 21 overreaching territory. Recovery 90 to 100 is Full Send, 70 to 89 is Perform, 40 to 69 is Adapt, and 0 to 39 is Recover.
- Scenario labels you may use (coach-friendly shorthand):
  - Low Day: acute load ~8, chronic ~12 (low strain / light recent load).
  - Building: acute ~24, chronic ~24 (moderate strain / steady build).
  - Productive: acute ~60, chronic ~50 (trainable, strong work day).
  - Spike: acute ~120, chronic ~60 (unusually high acute load vs baseline; extra strain, not automatic overtraining).
- Interpret the scores as coaching signals, not diagnoses or disease severity scales.
- Low strain plus high recovery usually means you are fresh, recovered, or under-loaded, not automatically a problem.
- High strain plus high recovery can be a positive match when recovery is keeping pace with load.
- High strain plus low recovery is the clearest mismatch or overreach pattern.
- Treat match versus mismatch as central. Either score by itself is incomplete. The main question is whether recovery is supporting the current level of strain, lagging behind it, or comfortably exceeding it.
- High recovery and high readiness are positive coaching signals in this app and should be treated as supportive, not suspicious, unless there is unusually strong contradictory evidence.
- Full Send and Perform should usually sound encouraging and confident. Adapt should still sound supportive and capable, not deflating or parental.
- Avoid discouraging phrasing like this is concerning, you should take it easy, or keep it short and to the point unless the user explicitly asked for blunt caution.
- Nuance: Adapt 60–69 is still good/workable; Adapt 40–50 is the rougher end where you should suggest controlled intent.
"""

private let coachMaximumContextTokens = 4096
private let coachReservedResponseTokens = 350
private let coachReservedRetryTokens = 220
private let coachReservedSafetyTokens = 180
private let coachAbsolutePromptTokenCap = 2200

private let coachBPESafetyMultiplier = 1.35

private func approximateTokenCount(_ text: String) -> Int {
    guard !text.isEmpty else { return 0 }
    let pattern = #"[A-Za-z0-9]+(?:[./:%-][A-Za-z0-9]+)*|[^\s]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let raw = regex.numberOfMatches(in: text, options: [], range: range)
    return Int(ceil(Double(raw) * coachBPESafetyMultiplier))
}

private func coachPromptTokenBudget(instructions: String) -> Int {
    let remaining = coachMaximumContextTokens
        - approximateTokenCount(instructions)
        - coachReservedResponseTokens
        - coachReservedSafetyTokens
    return max(900, min(coachAbsolutePromptTokenCap, remaining))
}

private func coachPromptLinePriority(_ line: String) -> Int {
    if line == "Coach me directly as an athletic performance coach using the Equalizer Framework."
        || line == "Window"
        || line == "Scope contract"
        || line == "Focused evidence"
        || line == "Scores"
        || line.hasPrefix("Coach me based on this data")
        || line.hasPrefix("Coach prompt for ")
        || line.hasPrefix("Filter:")
        || line.hasPrefix("Focus:")
        || line.hasPrefix("Suggestion ID:")
        || line.hasPrefix("Scores:") || line.hasPrefix("Scores [ANCHOR_DAY]:")
        || line.hasPrefix("Metric window guide:") {
        return 0
    }

    if line.hasPrefix("- Filter:")
        || line.hasPrefix("- Report title:")
        || line.hasPrefix("- Intent focus:")
        || line.hasPrefix("- Focus mode:")
        || line.hasPrefix("- Focus rules:")
        || line.hasPrefix("- Suggestion-specific directive:")
        || line.hasPrefix("- Ignore list:")
        || line.hasPrefix("- Allowed topics:")
        || line.hasPrefix("- Banned topics:")
        || line.hasPrefix("- If there is no clear signal")
        || line.hasPrefix("- Every coaching claim")
        || line.hasPrefix("- Use uncertainty language")
        || line.hasPrefix("- Follow the selected report")
        || line.hasPrefix("- If a topic appears on the ignore list")
        || line.hasPrefix("- Pick a reasoning frame")
        || line.hasPrefix("- Do not use bullet points")
        || line.hasPrefix("- Metric window discipline:")
        || line.hasPrefix("Primary scope:")
        || line.hasPrefix("Fallback contract:")
        || line.hasPrefix("- When the prompt includes a date")
        || line.hasPrefix("- If the prompt includes a comparison")
        || line.hasPrefix("- Recovery classification for the selected anchor date:")
        || line.hasPrefix("- Recovery classification meaning:")
        || line.hasPrefix("Sport filter:")
        || line.hasPrefix("Strain 7d avg:")
        || line.hasPrefix("Strain consistency:")
        || line.hasPrefix("Z45 roles:")
        || line.hasPrefix("Z45 7d aggregate[")
        || line.hasPrefix("Z45 today[")
        || line.hasPrefix("Z45 today:")
        || line.hasPrefix("Z45 prior[") {
        return 1
    }

    if line.hasPrefix("- Requested date:")
        || line.hasPrefix("- Shared day summary period:")
        || line.hasPrefix("- Calendar week anchor:")
        || line.hasPrefix("- Shared week summary period:")
        || line.hasPrefix("- Calendar month anchor:")
        || line.hasPrefix("- Shared month summary period:")
        || line.hasPrefix("- Sport filter:")
        || line.hasPrefix("- Selected sport:")
        || line.hasPrefix("- Sport session count")
        || line.hasPrefix("- Workout count")
        || line.hasPrefix("- Total training minutes")
        || line.hasPrefix("- Total ")
        || line.hasPrefix("- Latest sleep duration:")
        || line.hasPrefix("- Average sleep duration:")
        || line.hasPrefix("- HRV:")
        || line.hasPrefix("- Resting heart rate:")
        || line.hasPrefix("- Sleep heart rate:")
        || line.hasPrefix("- Respiratory rate:")
        || line.hasPrefix("- Wrist temperature:")
        || line.hasPrefix("- SpO2:")
        || line.hasPrefix("- Average strain across the full")
        || line.hasPrefix("- Average recovery across the full")
        || line.hasPrefix("- Average readiness across the full")
        || line.hasPrefix("- End-of-period daily check-in")
        || line.hasPrefix("- Highest strain day")
        || line.hasPrefix("- Lowest recovery day")
        || line.hasPrefix("- Highest readiness day")
        || line.hasPrefix("Training load:")
        || line.hasPrefix("Recent training load:")
        || line.hasPrefix("Recent load context:")
        || line.hasPrefix("[7D]")
        || line.hasPrefix("[ANCHOR_DAY]")
        || line.hasPrefix("[7D prior window]")
        || line.hasPrefix("Zone data contract:")
        || line.hasPrefix("Vitals [selected day")
        || line.hasPrefix("Secondary context:")
        || line.hasPrefix("Bridge if needed:")
        || line.hasPrefix("Recovery:")
        || line.hasPrefix("Readiness:")
        || line.hasPrefix("MET:")
        || line.hasPrefix("MET today:")
        || line.hasPrefix("Schedule:")
        || line.hasPrefix("Efficiency ratio")
        || line.hasPrefix("Zones window[") {
        return 2
    }

    if line.hasPrefix("- Workout frequency")
        || line.hasPrefix("- Longest")
        || line.hasPrefix("- Highest")
        || line.hasPrefix("- Most frequent sport:")
        || line.hasPrefix("- Sport with the most total minutes:")
        || line.hasPrefix("- Total time in HR zone")
        || line.hasPrefix("- Single-workout")
        || line.hasPrefix("- Acute")
        || line.hasPrefix("- Chronic")
        || line.hasPrefix("- ACWR")
        || line.hasPrefix("- Load status:")
        || line.hasPrefix("- Load interpretation:")
        || line.hasPrefix("- Sleep consistency score:")
        || line.hasPrefix("- Sleep midpoint deviation:")
        || line.hasPrefix("- Average sleep efficiency:")
        || line.hasPrefix("- Sleep debt versus prior baseline:")
        || line.hasPrefix("- Recovery day minus training day sleep gap:")
        || line.hasPrefix("- Vital norms summary:")
        || line.hasPrefix("HRV:")
        || line.hasPrefix("RHR:")
        || line.hasPrefix("HRR:")
        || line.hasPrefix("Sleep:")
        || line.hasPrefix("Vitals:")
        || line.hasPrefix("Sleep HR:")
        || line.hasPrefix("Metrics:")
        || line.hasPrefix("Trend lines:")
        || line.hasPrefix("Sessions:")
        || line.hasPrefix("Score derivatives:") {
        return 3
    }

    if line == "Training load and workouts"
        || line == "Sleep"
        || line == "Recovery and vitals"
        || line.hasPrefix("- Analytical framework:")
        || line.hasPrefix("- Language style:")
        || line.hasPrefix("- Refresh generation:")
        || line.hasPrefix("- If refresh generation is greater than 0")
        || line.hasPrefix("- For 1D reports")
        || line.hasPrefix("- For 1W reports")
        || line.hasPrefix("- For 1M reports")
        || line.hasPrefix("- Do not take averages at face value")
        || line.hasPrefix("- If the early part")
        || line.hasPrefix("- For 1W and 1M reports")
        || line.hasPrefix("- When you mention a trend")
        || line.hasPrefix("- When you mention an average") {
        return 4
    }

    if line == "Interpretation rules"
        || line.hasPrefix("- Strain is")
        || line.hasPrefix("- Recovery is")
        || line.hasPrefix("- Approximate")
        || line.hasPrefix("- Higher HRV")
        || line.hasPrefix("- Lower resting heart rate")
        || line.hasPrefix("- Keep vitals")
        || line.hasPrefix("- A low strain score")
        || line.hasPrefix("- Do not judge strain or recovery")
        || line.hasPrefix("- High strain with")
        || line.hasPrefix("- Metrics are coaching references")
        || line.hasPrefix("- Do not demand a perfect score match")
        || line.hasPrefix("- Treat strain")
        || line.hasPrefix("- Example calibration")
        || line.hasPrefix("- Save stronger criticism")
        || line.hasPrefix("- When strain and recovery")
        || line.hasPrefix("- Avoid discouraging stock phrases")
        || line.hasPrefix("- Prioritize coaching")
        || line.hasPrefix("- Distinguish this report")
        || line.hasPrefix("- Avoid repeating")
        || line.hasPrefix("Zones[")
        || line.hasPrefix("Zone[")
        || line.hasPrefix("Zones 7d[")
        || line.hasPrefix("Workouts:")
        || line.hasPrefix("Personal bests:")
        || line.hasPrefix("Training quests:")
        || line.hasPrefix("Score table")
        || line.hasPrefix("Focus on consistent trends")
        || line.hasPrefix("Ratio guide:")
        || line.hasPrefix("Note: only mention") {
        return 5
    }

    if line == "Cross-filter context for the same report and anchor date"
        || line == "Context stitching rules"
        || line.hasPrefix("- 1W:")
        || line.hasPrefix("- 1M:")
        || line.hasPrefix("- Keep the 1D view")
        || line.hasPrefix("- Reconcile any tension")
        || line.hasPrefix("- Treat the day, week, and month")
        || line.hasPrefix("- If the horizons point")
        || line.hasPrefix("- Never attach a day-only metric") {
        return 6
    }

    return 4
}

private func trimPromptToTokenBudget(_ prompt: String, budget: Int) -> String {
    var lines = prompt
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    func joined() -> String {
        lines.joined(separator: "\n")
    }

    if approximateTokenCount(joined()) <= budget {
        return joined()
    }

    for priority in stride(from: 6, through: 2, by: -1) {
        var index = lines.count - 1
        while index >= 0 {
            if coachPromptLinePriority(lines[index]) == priority {
                lines.remove(at: index)
                if approximateTokenCount(joined()) <= budget {
                    return joined()
                }
            }
            index -= 1
        }
    }

    var finalLines: [String] = []
    var runningTokens = 0
    for line in lines where coachPromptLinePriority(line) <= 1 {
        let lineTokens = approximateTokenCount(line)
        guard runningTokens + lineTokens <= budget else { break }
        finalLines.append(line)
        runningTokens += lineTokens
    }
    return finalLines.joined(separator: "\n")
}

private func enforceCoachPromptBudget(
    _ prompt: String,
    timeFilter: StrainRecoveryView.TimeFilter,
    instructions: String,
    retryText: String = ""
) -> String {
    let instrTokens = approximateTokenCount(instructions)
    let retryTokens = approximateTokenCount(retryText)
    let rawBudget = coachPromptTokenBudget(instructions: instructions)
    let budget = max(600, rawBudget - retryTokens)
    print("[CoachAI][budget] instrTokens=\(instrTokens) retryTokens=\(retryTokens) rawBudget=\(rawBudget) effectiveBudget=\(budget)")

    let level0 = compactCoachGenerationPrompt(prompt, for: timeFilter)
    let level0Tokens = approximateTokenCount(level0)
    print("[CoachAI][budget] level0 tokens=\(level0Tokens) chars=\(level0.count)")
    if level0Tokens <= budget {
        print("[CoachAI][budget] -> using level0 (fits)")
        return level0
    }

    let trimmed0 = trimPromptToTokenBudget(level0, budget: budget)
    let trimmed0Tokens = approximateTokenCount(trimmed0)
    print("[CoachAI][budget] trimmed0 tokens=\(trimmed0Tokens) chars=\(trimmed0.count)")
    if trimmed0Tokens <= budget {
        print("[CoachAI][budget] -> using trimmed0")
        print("[CoachAI][budget] TRIMMED0:\n\(trimmed0)")
        return trimmed0
    }

    let level1 = abstractPromptToLevel(level0, level: 1)
    let level1Tokens = approximateTokenCount(level1)
    print("[CoachAI][budget] level1 tokens=\(level1Tokens) chars=\(level1.count)")
    if level1Tokens <= budget {
        print("[CoachAI][budget] -> using level1")
        return level1
    }
    let trimmed1 = trimPromptToTokenBudget(level1, budget: budget)
    let trimmed1Tokens = approximateTokenCount(trimmed1)
    print("[CoachAI][budget] trimmed1 tokens=\(trimmed1Tokens) chars=\(trimmed1.count)")
    if trimmed1Tokens <= budget {
        print("[CoachAI][budget] -> using trimmed1")
        return trimmed1
    }

    let level2 = abstractPromptToLevel(level0, level: 2)
    let result = trimPromptToTokenBudget(level2, budget: budget)
    print("[CoachAI][budget] -> using level2 (last resort) tokens=\(approximateTokenCount(result)) chars=\(result.count)")
    print("[CoachAI][budget] LEVEL2:\n\(result)")
    return result
}

// MARK: - Progressive Prompt Abstraction

private let coachSeriesPrefixes = [
    "Training load:", "Recovery:", "Readiness:", "HRV:", "RHR:", "HRR:",
    "Sleep:", "Efficiency ratio (restoration/strain):",
    "[7D] Recovery:", "[7D] Readiness:", "[7D] Sleep:", "[7D] RHR:", "[7D] HRV:", "[7D] Sleep HR:"
]

private func abstractPromptToLevel(_ prompt: String, level: Int) -> String {
    guard level >= 1 else { return prompt }
    var lines = prompt.components(separatedBy: .newlines)

    if level >= 1 {
        lines = lines.map { line in
            for prefix in coachSeriesPrefixes {
                if line.hasPrefix(prefix) {
                    return condenseSeriesToStats(line, prefix: prefix)
                }
            }
            if line.hasPrefix("Schedule:") {
                return condenseScheduleLine(line)
            }
            return line
        }
        lines = collapseScoreDerivativeBlock(lines)
    }

    if level >= 2 {
        let essentialPrefixes = [
            "Coach me", "Coach prompt for ", "Filter:", "Focus:", "Suggestion ID:", "Sport filter:", "Scores:",
            "Scores [ANCHOR_DAY]:", "Metric window guide:", "Primary scope:", "Fallback contract:", "Secondary context:", "Strain 7d avg:", "Strain consistency:", "Vitals:", "MET:"
        ]
        let dropPrefixes = [
            "Score table", "Focus on consistent", "Zones[", "Zone[", "Zones 7d[", "Zones window[",
            "Z45 roles:", "Z45 7d aggregate[", "Z45 today[", "Z45 today:", "Z45 prior[",
            "Workouts:", "Personal bests:", "Training quests:", "Ratio guide:",
            "Note:", "Schedule:"
        ]

        lines = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if line.hasPrefix("  ") && (line.contains("S:") || line.contains("dS:")) { return nil }
            for p in dropPrefixes where trimmed.hasPrefix(p) { return nil }
            for p in essentialPrefixes where trimmed.hasPrefix(p) { return line }
            for prefix in coachSeriesPrefixes where trimmed.hasPrefix(prefix) {
                return extractLastSeriesEntry(trimmed, prefix: prefix)
            }
            if trimmed.hasPrefix("Score derivatives:") { return nil }
            return line
        }
    }

    return lines
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .joined(separator: "\n")
}

private func condenseSeriesToStats(_ line: String, prefix: String) -> String {
    guard let prefixEnd = line.range(of: prefix)?.upperBound else { return line }
    let content = String(line[prefixEnd...]).trimmingCharacters(in: .whitespaces)
    guard !content.isEmpty else { return line }

    let separator = content.contains(" | ") ? " | " : nil
    let entryCount: Int
    if let sep = separator {
        entryCount = content.components(separatedBy: sep).filter { !$0.isEmpty }.count
    } else {
        entryCount = extractSeriesNumbers(from: content).count
    }
    guard entryCount > 5 else { return line }

    let numbers = extractSeriesNumbers(from: content)
    guard !numbers.isEmpty else { return line }

    let avg = numbers.reduce(0, +) / Double(numbers.count)
    let lo = numbers.min() ?? avg
    let hi = numbers.max() ?? avg
    let third = max(1, numbers.count / 3)
    let firstAvg = numbers.prefix(third).reduce(0, +) / Double(third)
    let lastAvg = numbers.suffix(third).reduce(0, +) / Double(third)
    let delta = lastAvg - firstAvg
    let trend: String
    if avg == 0 || abs(delta) < abs(avg) * 0.08 {
        trend = "flat"
    } else {
        trend = delta > 0 ? "rising" : "falling"
    }

    return "\(prefix) \(entryCount) entries, avg \(formatted(avg, digits: 1)), range \(formatted(lo, digits: 1))-\(formatted(hi, digits: 1)), trend \(trend)"
}

private func extractSeriesNumbers(from content: String) -> [Double] {
    let pattern = #":(-?\d+\.?\d*)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    return regex.matches(in: content, options: [], range: range).compactMap { match in
        guard let numRange = Range(match.range(at: 1), in: content) else { return nil }
        return Double(content[numRange])
    }
}

private func condenseScheduleLine(_ line: String) -> String {
    guard let prefixEnd = line.range(of: "Schedule:")?.upperBound else { return line }
    let content = String(line[prefixEnd...]).trimmingCharacters(in: .whitespaces)
    let entries = content.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard entries.count > 7 else { return line }
    let restDays = entries.filter { $0.lowercased().contains("rest") }.count
    let activeDays = entries.count - restDays
    return "Schedule: \(entries.count) days, \(activeDays) active, \(restDays) rest"
}

private func collapseScoreDerivativeBlock(_ lines: [String]) -> [String] {
    guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("Score table") }) else { return lines }
    var result = Array(lines.prefix(upTo: headerIdx))
    var derivRows: [(strain: Double, recovery: Double, readiness: Double)] = []
    var afterBlock: [String] = []
    var inBlock = true
    for i in (headerIdx + 1)..<lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        if inBlock {
            if trimmed.contains("S:") && trimmed.contains("dS:") {
                let nums = extractSeriesNumbers(from: trimmed)
                if nums.count >= 3 {
                    derivRows.append((nums[0], nums[1], nums[2]))
                }
                continue
            } else if trimmed == "Focus on consistent trends, not one-off spikes." {
                inBlock = false
                continue
            } else {
                inBlock = false
            }
        }
        afterBlock.append(lines[i])
    }

    if !derivRows.isEmpty {
        let sAvg = derivRows.map(\.strain).reduce(0, +) / Double(derivRows.count)
        let rAvg = derivRows.map(\.recovery).reduce(0, +) / Double(derivRows.count)
        let rdAvg = derivRows.map(\.readiness).reduce(0, +) / Double(derivRows.count)
        let first = derivRows.first!
        let last = derivRows.last!
        result.append("Score derivatives: \(derivRows.count) days, strain \(formatted(first.strain, digits: 1))->\(formatted(last.strain, digits: 1)) avg \(formatted(sAvg, digits: 1)), recovery \(formatted(first.recovery, digits: 0))->\(formatted(last.recovery, digits: 0)) avg \(formatted(rAvg, digits: 0)), readiness \(formatted(first.readiness, digits: 0))->\(formatted(last.readiness, digits: 0)) avg \(formatted(rdAvg, digits: 0))")
    }
    result.append(contentsOf: afterBlock)
    return result
}

private func extractLastSeriesEntry(_ line: String, prefix: String) -> String? {
    guard let prefixEnd = line.range(of: prefix)?.upperBound else { return line }
    let content = String(line[prefixEnd...]).trimmingCharacters(in: .whitespaces)
    guard !content.isEmpty else { return nil }

    if content.contains(" | ") {
        guard let last = content.components(separatedBy: " | ").last?.trimmingCharacters(in: .whitespaces),
              !last.isEmpty else { return nil }
        return "\(prefix) latest: \(last)"
    }

    let numbers = extractSeriesNumbers(from: content)
    guard let lastVal = numbers.last else { return nil }
    return "\(prefix) latest \(formatted(lastVal, digits: 1))"
}

private func collapseToSingleParagraph(_ text: String) -> String {
    let lines = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard lines.count > 1 else { return text }
    return lines.joined(separator: " ")
}

private func containsDisallowedCoachFormatting(_ text: String) -> Bool {
    let trimmedLines = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    for line in trimmedLines {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return true
        }
        if let first = line.first, first.isNumber, line.contains(". ") {
            let afterDot = line.drop(while: { $0.isNumber || $0 == "." || $0 == " " })
            if afterDot.count > 0 && line.first!.isNumber {
                let numPrefix = line.prefix(while: { $0.isNumber })
                if numPrefix.count <= 2 {
                    return true
                }
            }
        }
    }

    return false
}

private func containsDisallowedAdvice(_ text: String) -> Bool {
    let normalized = text.lowercased()
    let bannedPhrases = [
        "you should", "try to", "consider ", "next step", "next session", "focus on next",
        "aim to", "plan to", "it would be wise", "make sure to"
    ]
    return bannedPhrases.contains { normalized.contains($0) }
}

@MainActor
private func aggressiveCachingCacheEntry(
    for request: StrainRecoverySummaryRequest,
    summaryText: String,
    statusText: String,
    source: SummarySourceKind
) -> StrainRecoverySummaryCacheEntry {
    let device = StrainRecoverySummaryDevice.current
    return StrainRecoverySummaryCacheEntry(
        requestID: request.requestID,
        summaryText: summaryText,
        statusText: statusText,
        generatedAt: Date(),
        latestWorkoutTimestamp: request.latestWorkoutTimestamp,
        intentDisplayName: request.intent.displayName,
        anchorDate: request.anchorDate,
        timeFilterRawValue: request.timeFilter.rawValue,
        suggestionID: request.suggestionID,
        scopedSport: request.scopedSport,
        createdByDeviceID: device.id,
        createdByDeviceName: device.name,
        sourceRawValue: source.rawValue,
        generationModeRawValue: StrainRecoverySummaryGenerationMode.background.rawValue,
        expiresAt: request.expiresAt,
        lastRefreshedAt: nil,
        isRefreshOverride: false
    )
}

@MainActor
private func aggressiveCachingLiveStatusText(
    for generationMode: StrainRecoverySummaryGenerationMode,
    source: SummarySourceKind
) -> String {
    let deviceName = StrainRecoverySummaryDevice.current.name
    let sourceText = source == .appleIntelligence ? "Apple Intelligence" : "local metric rules"
    switch generationMode {
    case .live:
        return "Generated live on \(deviceName) using \(sourceText). Saved to cache and iCloud."
    case .background:
        return "Generated in background on \(deviceName) using \(sourceText). Saved to cache and iCloud."
    case .refresh:
        return "Refreshed live on \(deviceName) using \(sourceText). This version replaced cache and iCloud for this report."
    }
}

private struct CrossFilterSummaryContext {
    let timeFilter: StrainRecoveryView.TimeFilter
    let summaryText: String
}

private let strainRecoverySummaryRequestVersion = "strain-recovery-ai-v11"

private func summaryRequestID(
    timeFilter: StrainRecoveryView.TimeFilter,
    scopedSport: String?,
    anchorDate: Date,
    suggestionID: String
) -> String {
    let period = summaryReportPeriod(for: timeFilter, requestedDate: anchorDate)
    return [
        strainRecoverySummaryRequestVersion,
        timeFilter.rawValue,
        scopedSport ?? "all",
        String(period.canonicalAnchorDate.timeIntervalSince1970),
        suggestionID
    ].joined(separator: "|")
}

private func siblingTimeFilterContexts(
    for request: StrainRecoverySummaryRequest,
    cache: [String: StrainRecoverySummaryCacheEntry]
) -> [CrossFilterSummaryContext] {
    let crossFilterEligibleSuggestions: Set<String> = ["overall", "trend-balance", "equalizer", "consistency", "deload"]
    guard request.timeFilter == .day,
          crossFilterEligibleSuggestions.contains(request.suggestionID) else { return [] }
    return StrainRecoveryView.TimeFilter.allCases.compactMap { filter in
        guard filter != request.timeFilter else { return nil }
        let requestID = summaryRequestID(
            timeFilter: filter,
            scopedSport: request.scopedSport,
            anchorDate: request.anchorDate,
            suggestionID: request.suggestionID
        )
        guard let entry = cache[requestID],
              entry.source == .appleIntelligence else {
            return nil
        }
        return CrossFilterSummaryContext(
            timeFilter: filter,
            summaryText: entry.summaryText
        )
    }
}

private func promptWithSiblingTimeFilterContext(
    for request: StrainRecoverySummaryRequest,
    cache: [String: StrainRecoverySummaryCacheEntry]
) -> String {
    return request.prompt
}

private func coachSectionSelection(
    suggestionID: String,
    intent: SummaryIntent,
    focusMode: AthleticCoachFocusMode
) -> (training: Bool, sleep: Bool, recovery: Bool) {
    if focusMode == .sportDeepDive || focusMode == .latestWorkout || focusMode == .toughestWorkout {
        return (true, false, false)
    }

    switch suggestionID {
    case "recovery", "recovery-vitals", "sleep", "overreach", "hrr-hrv":
        return (false, true, true)
    case "pb", "strain-days", "intensity", "zones", "met", "undertraining":
        return (true, false, false)
    default:
        break
    }

    switch intent {
    case .recoveryVitals:
        return (false, true, true)
    case .sportSpecific, .intensityLoad:
        return (true, false, false)
    case .general, .trendPB:
        return (true, true, true)
    }
}

private func coachScopeContract(
    suggestionID: String,
    intent: SummaryIntent,
    focusMode: AthleticCoachFocusMode,
    scopedSport: String?
) -> String {
    let sportLabel = scopedSport?.capitalized ?? "the selected sport"

    switch suggestionID {
    case "pb":
        return """
        - Allowed topics: personal-best style markers, breakthroughs, best days, baseline improvements, and clear upward trajectory inside the selected window.
        - Banned topics: sleep, recovery, vitals, generic readiness caveats, and unrelated wellness commentary.
        - If there is no clear signal of a best, peak, max, or meaningful upward move in the selected window, say there is no meaningful personal-best signal here.
        """
    case "strain-days":
        return """
        - Allowed topics: strain, session load, workout density, time in zone 4 or 5, MET load, VO2 load, HRR cost, and the dates that drove the hardest loading.
        - Banned topics: recovery mismatch framing, sleep commentary, vitals commentary, and generic wellness recap.
        - If the selected window does not contain any unusually high strain days, say that the strain pattern looks unremarkable for this period.
        """
    case "recovery", "recovery-vitals", "sleep", "overreach", "hrr-hrv":
        return """
        - Allowed topics: sleep timing, sleep duration, sleep efficiency, HRV, resting heart rate, sleep heart rate, respiratory rate, wrist temperature, SpO2, and recovery or readiness signals.
        - Banned topics: workout-by-workout recaps, sport counts, HR zones, power, and load summaries unless one is absolutely needed as a brief cause.
        - If the biometrics are mostly steady, say that nothing especially unusual stands out in the recovery data.
        """
    default:
        if focusMode == .sportDeepDive || focusMode == .latestWorkout || focusMode == .toughestWorkout {
            return """
            - Allowed topics: \(sportLabel) training interpretation—how volume, intensity, and session quality combine; progression, plateau, scatter, or overload risk; and the implied next-step emphasis for this discipline.
            - Use \(sportLabel.lowercased()) workouts, zones, power, pace, cadence, VO2, HRR, and session-to-session markers only as support for that interpretation, not as a metric inventory.
            - Banned topics: other sports, sleep, recovery metrics, vitals, and general wellness commentary unless one is directly limiting \(sportLabel.lowercased()) output.
            - If the selected window has little sport-specific signal, say there is nothing especially notable in the \(sportLabel.lowercased()) data for this period.
            """
        }

        switch intent {
        case .intensityLoad:
            return """
            - Allowed topics: strain, load, workout density, acute versus chronic balance, intensity distribution, zones, and performance cost markers.
            - Banned topics: passive recovery commentary, sleep deep-dives, vitals digressions, and generic mismatch stories unless performance is clearly capped by them.
            - If the load pattern is ordinary, say there is no standout load signal in this window.
            """
        case .recoveryVitals:
            return """
            - Allowed topics: sleep and recovery biomarkers.
            - Banned topics: general training recap unless it is a short cause-and-effect bridge.
            - If the data is stable, say so instead of forcing a red flag.
            """
        case .sportSpecific:
            return """
            - Allowed topics: sport-specific coaching synthesis (patterns, adaptation, sustainability) grounded in that sport's evidence.
            - Banned topics: unrelated sports, broad wellness commentary, and readouts that only restate metrics without interpretation.
            - If there is no strong sport-specific pattern, say that clearly.
            """
        case .general, .trendPB:
            return """
            - Allowed topics: the evidence that most directly supports the selected report.
            - Banned topics: unrelated metric buckets and filler recap.
            - If the period is quiet, say that nothing especially notable stands out.
            """
        }
    }
}

private func compactCoachGenerationPrompt(_ prompt: String, for timeFilter: StrainRecoveryView.TimeFilter = .day) -> String {
    let lines = prompt
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return lines.joined(separator: "\n")
}

private struct StrainRecoverySummarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine: HealthStateEngine
    @State private var settings = StrainRecoverySummaryPersistence.loadSyncSettings()
    @State private var temporarySelection: TemporaryPrimarySelection = .off
    @State private var isClearingCaches = false
    @ObservedObject var aggressiveCachingController: StrainRecoveryAggressiveCachingController

    private let currentDevice = StrainRecoverySummaryDevice.current

    private var isCurrentDevicePrimary: Bool {
        settings.isPrimary(deviceID: currentDevice.id)
    }

    private var syncSelectionDateBinding: Binding<Date> {
        Binding(
            get: { settings.aggressiveSyncSelectedDate },
            set: { newValue in
                settings.aggressiveSyncSelectedDate = Calendar.current.startOfDay(for: newValue)
                StrainRecoverySummaryPersistence.saveSyncSettings(settings)
            }
        )
    }

    private var availablePrioritySuggestions: [SummarySuggestion] {
        SummarySuggestion.buildSuggestions(
            engine: engine,
            timeFilter: .day,
            sportFilter: nil,
            anchorDate: Date()
        )
    }

    private var selectedAggressiveSuggestion: SummarySuggestion {
        SummarySuggestion.resolveSuggestion(
            id: settings.aggressiveSyncSelectedSuggestionID ?? SummarySuggestion.defaultSuggestion.id,
            from: availablePrioritySuggestions,
            scopedSport: nil
        )
    }

    private func togglePassivePriority(_ suggestionID: String) {
        if settings.passivePrioritySuggestionIDs.contains(suggestionID) {
            settings.passivePrioritySuggestionIDs.removeAll { $0 == suggestionID }
        } else {
            guard settings.passivePrioritySuggestionIDs.count < 5 else { return }
            settings.passivePrioritySuggestionIDs.append(suggestionID)
        }
        StrainRecoverySummaryPersistence.saveSyncSettings(settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Device") {
                    LabeledContent("Device") {
                        Text(currentDevice.name)
                    }
                    LabeledContent("Role") {
                        Text(isCurrentDevicePrimary ? "Primary" : "Secondary")
                            .foregroundColor(isCurrentDevicePrimary ? .orange : .secondary)
                    }
                }

                Section("Primary Device") {
                    CatalystAccessibleToggle("Use This Device As Default Primary", isOn: Binding(
                        get: {
                            settings.primaryDeviceID == currentDevice.id
                        },
                        set: { newValue in
                            if newValue {
                                settings.primaryDeviceID = currentDevice.id
                            } else if settings.primaryDeviceID == nil {
                                settings.primaryDeviceID = currentDevice.id
                            }
                            StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                        }
                    ))
                    .disabled(!deviceSupportsAppleIntelligence())

                    Text("Only one device can be the default primary. To move primary status, turn this on from the device you want to promote.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !deviceSupportsAppleIntelligence() {
                        Text("This device does not support Apple Intelligence, so it cannot be the primary device for coach summary syncing.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Picker("Temporary Primary", selection: $temporarySelection) {
                        ForEach(TemporaryPrimarySelection.allCases) { selection in
                            Text(selection.title).tag(selection)
                        }
                    }
                    .catalystDesktopFocusable()
                    .disabled(!deviceSupportsAppleIntelligence())
                    .onChange(of: temporarySelection) { _, newValue in
                        settings.temporaryPrimaryDeviceID = newValue == .off ? nil : currentDevice.id
                        settings.temporaryPrimaryUntil = newValue.expirationDate
                        StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                    }

                    if let temporaryUntil = settings.temporaryPrimaryUntil,
                       settings.temporaryPrimaryDeviceID == currentDevice.id {
                        Text("Temporary primary active until \(temporaryUntil.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Sync Rules") {
                    Text("Primary-device summaries win when the same report exists from multiple devices.")
                    Text("Secondary devices can still generate missing reports and sync them to iCloud.")
                    Text("Refreshing a report always overwrites cache and iCloud for that exact date, filter, and coaching mode.")
                }
                .font(.footnote)
                .foregroundColor(.secondary)

                Section("Intensive Fetching") {
                    Picker("Aggressive Sync Scope", selection: Binding(
                        get: { settings.aggressiveSyncSelectionMode },
                        set: { newValue in
                            settings.aggressiveSyncSelectionMode = newValue
                            if newValue == .selectedReportType, settings.aggressiveSyncSelectedSuggestionID == nil {
                                settings.aggressiveSyncSelectedSuggestionID = SummarySuggestion.defaultSuggestion.id
                            }
                            StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                        }
                    )) {
                        ForEach(AggressiveSyncSelectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if settings.aggressiveSyncSelectionMode != .expectedCache {
                        Picker("Time Range Type", selection: Binding(
                            get: { settings.aggressiveSyncTimeRangeType },
                            set: { newValue in
                                settings.aggressiveSyncTimeRangeType = newValue
                                StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                            }
                        )) {
                            ForEach(AggressiveSyncTimeRangeType.allCases) { rangeType in
                                Text(rangeType.title).tag(rangeType)
                            }
                        }
                    }

                    if settings.aggressiveSyncSelectionMode != .expectedCache {
                        DatePicker(
                            "Sync Date",
                            selection: syncSelectionDateBinding,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }

                    if settings.aggressiveSyncSelectionMode == .selectedReportType {
                        Picker("Report Type", selection: Binding(
                            get: { settings.aggressiveSyncSelectedSuggestionID ?? SummarySuggestion.defaultSuggestion.id },
                            set: { newValue in
                                settings.aggressiveSyncSelectedSuggestionID = newValue
                                StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                            }
                        )) {
                            ForEach(availablePrioritySuggestions) { suggestion in
                                Text(suggestion.title).tag(suggestion.id)
                            }
                        }
                    }

                    Button {
                        if aggressiveCachingController.isActive {
                            aggressiveCachingController.requestCancel()
                        } else {
                            settings.intensiveFetchingEnabled = false
                            StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                            aggressiveCachingController.requestStart()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(aggressiveCachingController.isActive ? "Cancel Aggressive Cache Fill" : "Run Aggressive Cache Fill")
                            Spacer()
                            Image(systemName: aggressiveCachingController.isActive ? "xmark.circle.fill" : "bolt.fill")
                        }
                    }
                    .disabled(!aggressiveCachingController.isActive && (!isCurrentDevicePrimary || !deviceSupportsAppleIntelligence()))

                    Text("Runs immediately on the current primary Apple Intelligence device. Progress advances one shared period at a time, and each generated summary is stored and synced before the next one begins so the run can resume later without losing completed work.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if settings.aggressiveSyncSelectionMode == .selectedTimeRange {
                        Text("\(settings.aggressiveSyncTimeRangeType.detail) The selected date is \(settings.aggressiveSyncSelectedDate.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if settings.aggressiveSyncSelectionMode == .selectedReportType {
                        Text("This scope syncs only \(selectedAggressiveSuggestion.title) for the chosen time range type. \(settings.aggressiveSyncTimeRangeType.detail)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("This scope fills the expected cache tiers for all report types: all day reports for the last 28 days, 5 shared week reports for the last month, and 60 shared month reports for the last 5 years.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Passive Sync Priority") {
                    Text("Pick up to 5 report types to mark as important. While you are browsing this view, AI syncing stays paused so date and filter changes remain fast. Use manual aggressive sync later when the device is idle.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(availablePrioritySuggestions) { suggestion in
                        Button {
                            togglePassivePriority(suggestion.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                    if let scopedSport = suggestion.scopedSport {
                                        Text(scopedSport.capitalized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: settings.passivePrioritySuggestionIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(settings.passivePrioritySuggestionIDs.contains(suggestion.id) ? .orange : .secondary)
                            }
                        }
                        .disabled(
                            !settings.passivePrioritySuggestionIDs.contains(suggestion.id) &&
                            settings.passivePrioritySuggestionIDs.count >= 5
                        )
                    }
                }

                Section("Cache Maintenance") {
                    Button(role: .destructive) {
                        Task { @MainActor in
                            isClearingCaches = true
                            aggressiveCachingController.requestCancel()
                            StrainRecoverySummaryPersistence.clearAll()
                            engine.clearWorkoutAnalyticsCache()
                            engine.initializeWithCachedData()
                            isClearingCaches = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text("Clear All Caches")
                            Spacer()
                            if isClearingCaches {
                                ProgressView()
                            }
                        }
                    }

                    Text("Clears local and iCloud coach-summary cache plus the persisted workout analytics cache for this screen. Fresh data will be rebuilt on demand.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Coach Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                settings = StrainRecoverySummaryPersistence.loadSyncSettings()
                if settings.intensiveFetchingEnabled {
                    settings.intensiveFetchingEnabled = false
                    StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                }
                if let until = settings.temporaryPrimaryUntil,
                   settings.temporaryPrimaryDeviceID == currentDevice.id,
                   until > Date() {
                    if until <= Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? until {
                        temporarySelection = .oneDay
                    } else {
                        temporarySelection = .oneWeek
                    }
                } else {
                    temporarySelection = .off
                }
            }
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

private func summaryExpirationDate(anchorDate: Date, generatedAt: Date) -> Date? {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let normalizedAnchor = calendar.startOfDay(for: anchorDate)
    let last28Start = calendar.date(byAdding: .day, value: -27, to: today) ?? today

    let currentMonth = calendar.dateComponents([.year, .month], from: today)
    let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today
    let lastMonth = calendar.dateComponents([.year, .month], from: lastMonthDate)
    let anchorMonth = calendar.dateComponents([.year, .month], from: normalizedAnchor)

    let isCurrentMonth = anchorMonth.year == currentMonth.year && anchorMonth.month == currentMonth.month
    let isLastMonth = anchorMonth.year == lastMonth.year && anchorMonth.month == lastMonth.month
    let isPast28Days = normalizedAnchor >= last28Start

    return (isCurrentMonth || isLastMonth || isPast28Days)
        ? nil
        : generatedAt.addingTimeInterval(24 * 60 * 60)
}

private func average(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
}

private func metricValueContext(
    for timeFilter: StrainRecoveryView.TimeFilter,
    dayLabel: String = "today",
    aggregateKind: String
) -> String {
    switch timeFilter {
    case .day:
        return dayLabel
    case .week:
        return "weekly \(aggregateKind)"
    case .month:
        return "monthly \(aggregateKind)"
    }
}

private func standardDeviation(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
    return sqrt(variance)
}

/// Titled material card for Mac Catalyst-only placeholders (separate from StressView.MetricCard).
private struct StrainRecoveryCatalystInfoCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
    }
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

private enum SummarySourceKind: String, Codable {
    case appleIntelligence
    case localFallback
}

private func deviceSupportsAppleIntelligence() -> Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
        let model = SystemLanguageModel(useCase: .general)
        switch model.availability {
        case .available, .unavailable(.modelNotReady), .unavailable(.appleIntelligenceNotEnabled):
            return true
        case .unavailable(.deviceNotEligible):
            return false
        @unknown default:
            return false
        }
    }
    #endif
    return false
}

private func allowsBackgroundAISummaryUpgrades() -> Bool {
    let processInfo = ProcessInfo.processInfo
    if processInfo.isLowPowerModeEnabled {
        return false
    }
    switch processInfo.thermalState {
    case .serious, .critical:
        return false
    default:
        return true
    }
}

private struct StrainRecoveryAISummarySection: View {
    @ObservedObject var engine: HealthStateEngine
    @Environment(\.scenePhase) private var scenePhase
    let timeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?
    let anchorDate: Date
    @ObservedObject var aggressiveCachingController: StrainRecoveryAggressiveCachingController

    @State private var intentText = ""
    @State private var summaryText = ""
    @State private var isLoading = false
    @State private var statusText = "Preparing your summary..."
    @State private var activeRequestKey: String? = nil
    @State private var persistedEntry: StrainRecoverySummaryCacheEntry?
    @State private var displayedRequestID: String? = nil
    @State private var selectedSuggestionID: String? = nil
    @State private var refreshVersions: [String: Int] = [:]
    @State private var selectedComparisonInsight: CoachSummaryInsight?
    @State private var backgroundGenerationTask: Task<Void, Never>? = nil
    @State private var backgroundGenerationStarterTask: Task<Void, Never>? = nil
    @State private var deferredSummaryLoadingTask: Task<Void, Never>? = nil
    @State private var deferredSuggestionsRefreshTask: Task<Void, Never>? = nil
    @State private var summaryPrerequisiteTask: Task<Void, Never>? = nil
    @State private var requestedRequestID: String? = nil
    @State private var backgroundGenerationContextID: String? = nil
    @State private var backgroundFetchStatusText: String? = nil
    @State private var cacheSnapshot = StrainRecoverySummaryPersistence.load()
    @State private var syncSettingsSnapshot = StrainRecoverySummaryPersistence.loadSyncSettings()
    @State private var suggestionsSnapshot: [SummarySuggestion] = []
    @State private var isSavingToJournal = false
    @State private var showJournalSavedPopup = false
    @State private var journalSavedPopupTask: Task<Void, Never>? = nil
    @State private var showsAllSuggestions = false

    private struct SummaryGenerationReadiness {
        let canGenerate: Bool
        let statusText: String
        let placeholderText: String
        let triggerToken: String
    }

    private var detectedIntent: SummaryIntent {
        SummaryIntent.detect(from: intentText, sportFilter: sportFilter)
    }

    private var suggestions: [SummarySuggestion] {
        suggestionsSnapshot
    }

    private var filteredSuggestions: [SummarySuggestion] {
        let query = intentText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return suggestions }
        return suggestions.filter {
            $0.title.lowercased().contains(query) || $0.queryText.lowercased().contains(query)
        }
    }

    private var selectedSuggestion: SummarySuggestion? {
        filteredSuggestions.first(where: { $0.id == selectedSuggestionID })
            ?? suggestions.first(where: { $0.id == selectedSuggestionID })
            ?? suggestions.first
    }

    private var trainingFocusReport: TrainingFocusReportPayload? {
        guard let selectedSuggestion, selectedSuggestion.id.contains("sport-") else { return nil }
        let reportPeriod = summaryReportPeriod(for: timeFilter, requestedDate: Calendar.current.startOfDay(for: anchorDate))
        let window = (start: reportPeriod.start, end: reportPeriod.end, endExclusive: reportPeriod.endExclusive)
        let scopedSport = selectedSuggestion.scopedSport ?? sportFilter
        let sportWorkouts = engine.workoutAnalytics.filter { w, _ in
            w.startDate >= window.start && w.startDate < window.endExclusive &&
            (scopedSport == nil || w.workoutActivityType.name == scopedSport)
        }
        let sportName = scopedSport ?? sportWorkouts.first?.workout.workoutActivityType.name ?? ""
        let questSummary = StageQuestStore.shared.questSummary(forSport: sportName, from: window.start, to: window.end)
        let calendar = Calendar.current
        let metBaselineStart = calendar.date(byAdding: .day, value: -7, to: window.start) ?? window.start
        let priorSameTypeMET = engine.workoutAnalytics.filter { w, _ in
            !sportName.isEmpty &&
                w.startDate >= metBaselineStart && w.startDate < window.start &&
                w.workoutActivityType.name == sportName
        }
        return buildTrainingFocusReportPayload(
            sport: sportName,
            reportPeriod: reportPeriod,
            workouts: sportWorkouts,
            questSummary: questSummary,
            prior7dSameSportWorkouts: priorSameTypeMET
        )
    }

    private var keyboardPrimarySuggestion: SummarySuggestion? {
        let query = intentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return filteredSuggestions.first
    }

    private var collapsedSuggestions: [SummarySuggestion] {
        Array(filteredSuggestions.prefix(8))
    }

    private var shouldShowExpandedSuggestionToggle: Bool {
        !filteredSuggestions.isEmpty
    }

    private func estimatedSuggestionChipWidth(for suggestion: SummarySuggestion) -> CGFloat {
        CGFloat(max(90, min(210, 46 + (suggestion.title.count * 6))))
    }

    private func fittedCollapsedSuggestions(
        for availableWidth: CGFloat,
        reservingToggle: Bool
    ) -> [SummarySuggestion] {
        let reservedToggleWidth: CGFloat = reservingToggle ? 20 : 0
        let targetWidth = max(availableWidth - reservedToggleWidth, 120)
        var runningWidth: CGFloat = 0
        var visible: [SummarySuggestion] = []

        for suggestion in collapsedSuggestions {
            let chipWidth = estimatedSuggestionChipWidth(for: suggestion)
            let proposedWidth = runningWidth == 0 ? chipWidth : runningWidth + 10 + chipWidth
            if proposedWidth > targetWidth, !visible.isEmpty {
                break
            }
            visible.append(suggestion)
            runningWidth = proposedWidth
        }

        return visible
    }

    private func collapsedSuggestionLayout(for availableWidth: CGFloat) -> ([SummarySuggestion], Bool) {
        let fittedWithoutToggle = fittedCollapsedSuggestions(
            for: availableWidth,
            reservingToggle: false
        )

        guard filteredSuggestions.count > fittedWithoutToggle.count else {
            return (fittedWithoutToggle, false)
        }

        let fittedWithToggle = fittedCollapsedSuggestions(
            for: availableWidth,
            reservingToggle: true
        )
        return (fittedWithToggle, true)
    }

    private var selectedSuggestionRequestID: String {
        summaryRequestID(
            timeFilter: timeFilter,
            scopedSport: selectedSuggestion?.scopedSport ?? sportFilter,
            anchorDate: anchorDate,
            suggestionID: selectedSuggestion?.id ?? SummarySuggestion.defaultSuggestion.id
        )
    }

    private var latestWorkoutTimestamp: TimeInterval? {
        engine.workoutAnalytics
            .map(\.workout.endDate.timeIntervalSince1970)
            .max()
    }

    private var suggestionCacheStates: [String: (hasAISummary: Bool, isPassivePriority: Bool)] {
        let priorityIDs = Set(syncSettingsSnapshot.passivePrioritySuggestionIDs)
        var states: [String: (hasAISummary: Bool, isPassivePriority: Bool)] = [:]

        for suggestion in filteredSuggestions.prefix(24) {
            let suggestionRequestID = summaryRequestID(
                timeFilter: timeFilter,
                scopedSport: suggestion.scopedSport ?? sportFilter,
                anchorDate: anchorDate,
                suggestionID: suggestion.id
            )
            let hasAISummary = cacheSnapshot[suggestionRequestID]?.source == .appleIntelligence
            states[suggestion.id] = (hasAISummary, priorityIDs.contains(suggestion.id))
        }

        return states
    }

    private func applySuggestion(_ suggestion: SummarySuggestion) {
        selectedSuggestionID = suggestion.id
        intentText = suggestion.queryText
        requestedRequestID = nil
        displayedRequestID = nil
        persistedEntry = nil
        summaryText = ""
        selectedComparisonInsight = nil

        Task {
            let request = await StrainRecoverySummaryRequest.build(
                engine: engine,
                timeFilter: timeFilter,
                sportFilter: sportFilter,
                anchorDate: anchorDate,
                intentText: suggestion.queryText,
                selectedSuggestion: suggestion,
                refreshVersion: refreshVersions[suggestion.id, default: 0]
            )

            if let cachedEntry = cacheSnapshot[request.requestID],
               cachedEntry.source == .appleIntelligence {
                persistedEntry = cachedEntry
                summaryText = cachedEntry.summaryText
                statusText = cachedEntry.cacheStatusText(currentDeviceID: StrainRecoverySummaryDevice.current.id)
                displayedRequestID = cachedEntry.requestID
                requestedRequestID = cachedEntry.requestID
            } else {
                statusText = "Generating \(suggestion.title) with Apple Intelligence for \(anchorDate.formatted(date: .abbreviated, time: .omitted)) in the \(timeFilter.rawValue) view."
                await generateSummary(
                    for: request,
                    requireAppleIntelligence: shouldRequireAppleIntelligenceByDefault,
                    allowLocalRefreshFallback: !shouldRequireAppleIntelligenceByDefault
                )
            }
        } // Task
    }

    private var currentRequestDescriptor: String {
        let title = selectedSuggestion?.title ?? detectedIntent.displayName
        let period = summaryReportPeriod(for: timeFilter, requestedDate: anchorDate)
        let dateText = timeFilter == .day
            ? period.description
            : "\(period.description) (\(timeFilter.rawValue))"
        return "\(title) for \(dateText)"
    }

    private var summaryPeriodFooterText: String {
        let period = summaryReportPeriod(for: timeFilter, requestedDate: anchorDate)

        switch timeFilter {
        case .day:
            return period.start.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(period.start.formatted(date: .abbreviated, time: .omitted)) - \(period.end.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return period.start.formatted(.dateTime.month(.wide).year())
        }
    }

    private var liveOperationStatusText: String? {
        if summaryText.isEmpty && isLoading {
            return nil
        }
        if isLoading {
            return "Loading requested report of \(currentRequestDescriptor)"
        }
        return backgroundFetchStatusText
    }

    private var summaryGenerationReadiness: SummaryGenerationReadiness {
        let hasWorkoutContext = engine.hasInitializedWorkoutAnalytics
        let hasRecoveryCore = engine.feelGoodScoreInputsAvailable
        let hasRecoverySeries = !engine.dailyHRV.isEmpty || !engine.dailyRestingHeartRate.isEmpty
        let hasSleepContext = !engine.sleepStages.isEmpty || engine.sleepHours != nil

        let missing: [String] = [
            hasWorkoutContext ? nil : "workout history",
            hasRecoveryCore ? nil : "HRV, resting heart rate, and sleep",
            (hasRecoverySeries || hasSleepContext) ? nil : "trend data"
        ].compactMap { $0 }

        let isReady = hasWorkoutContext && hasRecoveryCore && (hasRecoverySeries || hasSleepContext)
        let statusText: String
        let placeholderText: String

        if isReady {
            statusText = "Coach summary ready to generate."
            placeholderText = ""
        } else {
            let joinedMissing = ListFormatter.localizedString(byJoining: missing)
            statusText = "Waiting for enough health data to generate your coach summary."
            placeholderText = "Loading \(joinedMissing.lowercased()) before generating your coach summary so the report does not lock onto empty startup values."
        }

        let triggerToken = [
            hasWorkoutContext ? "workouts-ready" : "workouts-waiting",
            hasRecoveryCore ? "core-ready" : "core-waiting",
            String(engine.workoutAnalytics.count),
            String(engine.dailyHRV.count),
            String(engine.dailyRestingHeartRate.count),
            String(engine.sleepStages.count),
            engine.latestHRV != nil ? "latest-hrv" : "no-latest-hrv",
            engine.restingHeartRate != nil ? "latest-rhr" : "no-latest-rhr",
            engine.sleepHours != nil ? "sleep-hours" : "no-sleep-hours"
        ].joined(separator: "|")

        return SummaryGenerationReadiness(
            canGenerate: isReady,
            statusText: statusText,
            placeholderText: placeholderText,
            triggerToken: triggerToken
        )
    }

    private var generationTaskID: String {
        [
            selectedSuggestionRequestID,
            summaryGenerationReadiness.triggerToken,
            String(suggestions.count)
        ].joined(separator: "|")
    }

    private var displayedSummaryBody: String {
        if !summaryText.isEmpty {
            return summaryText
        }
        if !summaryGenerationReadiness.canGenerate {
            return summaryGenerationReadiness.placeholderText
        }
        if isLoading && requestedRequestID == selectedSuggestionRequestID {
            return "This coach report is still being prepared for \(selectedSuggestion?.title ?? detectedIntent.displayName). The current filter does not have a finished summary yet."
        }
        let normalizedStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedStatus.isEmpty && (
            normalizedStatus.localizedCaseInsensitiveContains("failed")
            || normalizedStatus.localizedCaseInsensitiveContains("unavailable")
            || normalizedStatus.localizedCaseInsensitiveContains("did not return")
            || normalizedStatus.localizedCaseInsensitiveContains("waiting for enough health data")
        ) {
            return normalizedStatus
        }
        if suggestions.isEmpty {
            return "Preparing coaching suggestions for this date and filter before generating the first AI summary."
        }
        return "Preparing the \(selectedSuggestion?.title ?? detectedIntent.displayName) AI summary for this date and filter."
    }

    private var shouldShowRefresh: Bool {
        !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldRecommendRefresh: Bool {
        guard displayedRequestID == selectedSuggestionRequestID else { return false }
        guard let persistedEntry else { return false }
        if persistedEntry.source == .localFallback {
            return true
        }
        if Date().timeIntervalSince(persistedEntry.generatedAt) > 24 * 60 * 60 {
            return true
        }
        guard let cachedWorkoutTimestamp = persistedEntry.latestWorkoutTimestamp,
              let latestWorkoutTimestamp else {
            return false
        }
        return latestWorkoutTimestamp > cachedWorkoutTimestamp + 1
    }

    private var shouldRequireAppleIntelligenceByDefault: Bool {
        deviceSupportsAppleIntelligence()
    }

    private var suggestionsContextID: String {
        let period = summaryReportPeriod(for: timeFilter, requestedDate: anchorDate)
        return [
            timeFilter.rawValue,
            sportFilter ?? "all",
            Calendar.current.startOfDay(for: period.canonicalAnchorDate).formatted(date: .numeric, time: .omitted),
            String(engine.workoutAnalytics.count)
        ].joined(separator: "|")
    }

    @MainActor
    private func refreshLocalSnapshots(forceReload: Bool = false) {
        if forceReload {
            StrainRecoverySummaryPersistence.invalidateInMemoryState()
        }
        cacheSnapshot = StrainRecoverySummaryPersistence.load(forceReload: forceReload)
        syncSettingsSnapshot = StrainRecoverySummaryPersistence.loadSyncSettings(forceReload: forceReload)
    }

    @MainActor
    private func refreshSuggestionsSnapshot() {
        let period = summaryReportPeriod(for: timeFilter, requestedDate: anchorDate)
        suggestionsSnapshot = SummarySuggestion.buildSuggestions(
            engine: engine,
            timeFilter: timeFilter,
            sportFilter: sportFilter,
            anchorDate: period.canonicalAnchorDate
        )
        if selectedSuggestionID == nil || suggestionsSnapshot.contains(where: { $0.id == selectedSuggestionID }) == false {
            selectedSuggestionID = suggestionsSnapshot.first?.id
        }
        if intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intentText = suggestionsSnapshot.first?.queryText ?? ""
        }
    }

    @MainActor
    private func resetSummaryForNavigation() {
        deferredSummaryLoadingTask?.cancel()
        cancelBackgroundGeneration()
        selectedComparisonInsight = nil
        requestedRequestID = nil
        displayedRequestID = nil
        persistedEntry = nil
        summaryText = ""
        isLoading = false
        statusText = "Preparing the next AI coach summary for this date and filter."
    }

    @MainActor
    private func triggerAutoSummaryLoadIfNeeded() {
        guard summaryGenerationReadiness.canGenerate else { return }
        guard !isLoading else { return }
        guard !suggestions.isEmpty else { return }
        guard let selectedSuggestion else { return }
        guard summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if displayedRequestID == selectedSuggestionRequestID,
           !statusText.localizedCaseInsensitiveContains("failed"),
           !statusText.localizedCaseInsensitiveContains("unavailable"),
           !statusText.localizedCaseInsensitiveContains("did not return") {
            return
        }

        Task {
            let request = await StrainRecoverySummaryRequest.build(
                engine: engine,
                timeFilter: timeFilter,
                sportFilter: sportFilter,
                anchorDate: anchorDate,
                intentText: intentText.isEmpty ? selectedSuggestion.queryText : intentText,
                selectedSuggestion: selectedSuggestion,
                refreshVersion: refreshVersions[selectedSuggestion.id, default: 0]
            )
            statusText = "Generating \(selectedSuggestion.title) with Apple Intelligence for \(anchorDate.formatted(date: .abbreviated, time: .omitted)) in the \(timeFilter.rawValue) view."
            await generateSummary(
                for: request,
                requireAppleIntelligence: shouldRequireAppleIntelligenceByDefault,
                allowLocalRefreshFallback: !shouldRequireAppleIntelligenceByDefault
            )
        }
    }

    @MainActor
    private func scheduleAutoSummaryLoad() {
        deferredSummaryLoadingTask?.cancel()
        deferredSummaryLoadingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            triggerAutoSummaryLoadIfNeeded()
        }
    }

    @MainActor
    private func ensureSummaryPrerequisitesIfNeeded() {
        let isMissingCoreRecoveryInputs = !engine.feelGoodScoreInputsAvailable
        let isMissingRecoveryTrendSeries = engine.dailyHRV.isEmpty || engine.dailyRestingHeartRate.isEmpty
        let isMissingSleepContext = engine.sleepStages.isEmpty && engine.sleepHours == nil

        guard isMissingCoreRecoveryInputs || isMissingRecoveryTrendSeries || isMissingSleepContext else {
            return
        }

        summaryPrerequisiteTask?.cancel()
        summaryPrerequisiteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let chartFilter: StrainRecoveryView.TimeFilter = timeFilter == .day ? .week : timeFilter
            let window = chartWindow(for: chartFilter, anchorDate: anchorDate)
            let start = Calendar.current.date(byAdding: .day, value: -27, to: window.start) ?? window.start
            await engine.ensureRecoveryMetricsCoverage(from: start, to: window.endExclusive)
        }
    }

    @MainActor
    @discardableResult
    private func restoreCachedSummaryIfAvailable(requestID: String) -> Bool {
        guard let entry = cacheSnapshot[requestID] else {
            return false
        }
        guard !shouldRequireAppleIntelligenceByDefault || entry.source == .appleIntelligence else {
            return false
        }

        persistedEntry = entry
        summaryText = entry.summaryText
        statusText = entry.cacheStatusText(currentDeviceID: StrainRecoverySummaryDevice.current.id)
        displayedRequestID = entry.requestID
        requestedRequestID = entry.requestID
        isLoading = false
        return true
    }

    @MainActor
    private func performRefresh() {
        guard shouldShowRefresh else { return }

        let key = selectedSuggestion?.id ?? "default"
        refreshVersions[key, default: 0] += 1

        Task {
            let request = await StrainRecoverySummaryRequest.build(
                engine: engine,
                timeFilter: timeFilter,
                sportFilter: sportFilter,
                anchorDate: anchorDate,
                intentText: intentText,
                selectedSuggestion: selectedSuggestion,
                refreshVersion: refreshVersions[key, default: 0]
            )
            clearPersistedSummary(for: request)
            await generateSummary(
                for: request,
                forceRefresh: true,
                requireAppleIntelligence: true,
                allowLocalRefreshFallback: false
            )
        }
    }

    @ViewBuilder
    private func suggestionButton(for suggestion: SummarySuggestion) -> some View {
        let cacheState = suggestionCacheStates[suggestion.id] ?? (false, false)
        let isKeyboardPrimary = keyboardPrimarySuggestion?.id == suggestion.id

        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            applySuggestion(suggestion)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: suggestion.symbol)
                    .font(.caption.weight(.bold))
                Text(suggestion.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: cacheState.hasAISummary ? Color.orange.opacity(0.28) : .clear,
                radius: cacheState.isPassivePriority ? 16 : 10,
                x: 0,
                y: 0
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        (selectedSuggestionID == suggestion.id ? Color.orange : Color.orange.opacity(0.35)),
                        lineWidth: selectedSuggestionID == suggestion.id ? 1.4 : 1
                    )
            )
            .overlay {
                if cacheState.hasAISummary {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.45), lineWidth: cacheState.isPassivePriority ? 2.4 : 1.6)
                        .blur(radius: cacheState.isPassivePriority ? 8 : 4)
                        .padding(cacheState.isPassivePriority ? -8 : -3)
                }
            }
            .overlay {
                if isKeyboardPrimary {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.55), lineWidth: 1.4)
                        .blur(radius: 4)
                        .padding(2)
                        .mask(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white, Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var suggestionToggleButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                showsAllSuggestions.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                if showsAllSuggestions {
                    Text("Less")
                }
                Image(systemName: showsAllSuggestions ? "chevron.up" : "chevron.down")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.orange)
        }
        .buttonStyle(.plain)
        .catalystDesktopFocusable()
    }

    @MainActor
    private func performSaveToJournal() {
        guard !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isSavingToJournal else { return }

        isSavingToJournal = true
        NotificationCenter.default.post(
            name: .saveWorkoutReportToJournal,
            object: SavedWorkoutReportPayload(
                title: selectedSuggestion?.title ?? "Workout Report",
                content: JournalDisplaySanitizer.endUserText(summaryText),
                date: anchorDate
            )
        )
        statusText = "Saved as a workout report in Journal."

        journalSavedPopupTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showJournalSavedPopup = true
        }

        journalSavedPopupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showJournalSavedPopup = false
            }
            isSavingToJournal = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("AI Coach Summary")
                    .font(.title2.bold())
                Spacer()
                if shouldShowRefresh {
                    Button("Refresh") {
                        performRefresh()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .catalystDesktopFocusable()
                }
                if !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(isSavingToJournal ? "Saved" : "Save To Journal") {
                        performSaveToJournal()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .shadow(color: Color.purple.opacity(0.18), radius: 12, x: 0, y: 0)
                    .disabled(isSavingToJournal)
                    .catalystDesktopFocusable()
                }
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if isLoading, let liveOperationStatusText {
                Text(liveOperationStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                TextField("Search coaching suggestions", text: $intentText)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.search)
                    .onSubmit {
                        guard let keyboardPrimarySuggestion else { return }
                        applySuggestion(keyboardPrimarySuggestion)
                    }
                if !intentText.isEmpty {
                    Button {
                        intentText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.55), Color.blue.opacity(0.25)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )

            if shouldRecommendRefresh {
                Text("New summary available. A new workout was detected or this report is older than a day, so a refresh is recommended.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                if showsAllSuggestions {
                    HStack(spacing: 10) {
                        Text("Suggestions")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if shouldShowExpandedSuggestionToggle {
                            suggestionToggleButton
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(filteredSuggestions.prefix(24)) { suggestion in
                            suggestionButton(for: suggestion)
                        }
                    }
                } else {
                    GeometryReader { geometry in
                        let layout = collapsedSuggestionLayout(for: geometry.size.width)
                        let visibleSuggestions = layout.0
                        let shouldShowToggle = layout.1

                        HStack(spacing: 10) {
                            ForEach(visibleSuggestions) { suggestion in
                                suggestionButton(for: suggestion)
                                    .fixedSize(horizontal: true, vertical: false)
                            }

                            Spacer(minLength: 0)

                            if shouldShowToggle {
                                suggestionToggleButton
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(height: 48)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                let coachMarkdown = CoachResponseMarkdown.parse(displayedSummaryBody)
                let coachInsights = CoachSummaryNLP.detectInsights(
                    in: coachMarkdown.plain,
                    anchorDate: anchorDate,
                    timeFilter: timeFilter
                )

                if summaryText.isEmpty && isLoading {
                    SummaryPreparationAnimationView(
                        title: "Generating \(selectedSuggestion?.title ?? detectedIntent.displayName)",
                        subtitle: statusText
                    )
                } else {
                    CoachSummaryInteractiveText(
                        parsed: coachMarkdown,
                        insights: coachInsights
                    ) { insight in
                        selectedComparisonInsight = insight
                    }
                    .font(.body)
                    .foregroundColor(.primary)
                }

                if !(summaryText.isEmpty && isLoading) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !coachInsights.isEmpty {
                    Text("Tap the highlighted coach cues to compare the linked metrics on a shared whiteboard.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack {
                    Spacer()
                    Text(summaryPeriodFooterText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.orange.opacity(0.16), lineWidth: 1.1)
            )
            .overlay(alignment: .topTrailing) {
                if showJournalSavedPopup {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to Journal")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .padding(14)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }

            if let trainingFocusReport {
                TrainingFocusReportView(report: trainingFocusReport)
            }
        }
        .fullScreenCover(item: $selectedComparisonInsight) { insight in
            CoachComparisonView(
                engine: engine,
                insight: insight,
                summaryText: displayedSummaryBody,
                timeFilter: timeFilter,
                sportFilter: sportFilter,
                anchorDate: anchorDate
            )
        }
        .onDisappear {
            journalSavedPopupTask?.cancel()
            journalSavedPopupTask = nil
            showJournalSavedPopup = false
            isSavingToJournal = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlRefresh)) { _ in
            performRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlSaveToJournal)) { _ in
            performSaveToJournal()
        }
        .task(id: generationTaskID) {
            refreshLocalSnapshots()
            refreshSuggestionsSnapshot()
            if selectedSuggestionID == nil {
                selectedSuggestionID = suggestions.first?.id
                if intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    intentText = suggestions.first?.queryText ?? ""
                }
            }
            if !restoreCachedSummaryIfAvailable(requestID: selectedSuggestionRequestID) {
                resetSummaryForNavigation()
                if shouldRequireAppleIntelligenceByDefault,
                   let selectedSuggestion {
                    let request = await StrainRecoverySummaryRequest.build(
                        engine: engine,
                        timeFilter: timeFilter,
                        sportFilter: sportFilter,
                        anchorDate: anchorDate,
                        intentText: intentText.isEmpty ? selectedSuggestion.queryText : intentText,
                        selectedSuggestion: selectedSuggestion,
                        refreshVersion: refreshVersions[selectedSuggestion.id, default: 0]
                    )
                    await generateSummary(
                        for: request,
                        requireAppleIntelligence: true,
                        allowLocalRefreshFallback: false
                    )
                } else {
                    triggerAutoSummaryLoadIfNeeded()
                }
            }
        }
        .task(id: suggestionsContextID) {
            deferredSuggestionsRefreshTask?.cancel()
            deferredSuggestionsRefreshTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                showsAllSuggestions = false
                refreshSuggestionsSnapshot()
                scheduleAutoSummaryLoad()
            }
        }
        .onAppear {
            AppResourceCoordinator.shared.setStrainRecoveryForegroundCritical(true)
            refreshLocalSnapshots()
            refreshSuggestionsSnapshot()
            ensureSummaryPrerequisitesIfNeeded()
            scheduleAutoSummaryLoad()
        }
        .onChange(of: summaryGenerationReadiness.triggerToken) { _, _ in
            scheduleAutoSummaryLoad()
        }
        .onChange(of: selectedSuggestionRequestID) { _, _ in
            scheduleAutoSummaryLoad()
        }
        .onChange(of: suggestions.count) { _, _ in
            scheduleAutoSummaryLoad()
        }
        .onChange(of: aggressiveCachingController.isActive) { _, isActive in
            guard !isActive else { return }
            refreshLocalSnapshots(forceReload: true)
            refreshSuggestionsSnapshot()
            if !restoreCachedSummaryIfAvailable(requestID: selectedSuggestionRequestID) {
                scheduleAutoSummaryLoad()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            refreshLocalSnapshots(forceReload: true)
            scheduleAutoSummaryLoad()
        }
        .onChange(of: aggressiveCachingController.pendingAction) { _, action in
            guard let action else { return }
            switch action {
            case .start:
                Task { @MainActor in
                    await aggressiveCachingController.startIfNeeded()
                }
            case .cancel:
                aggressiveCachingController.cancelByUser()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            deferredSummaryLoadingTask?.cancel()
            deferredSuggestionsRefreshTask?.cancel()
            summaryPrerequisiteTask?.cancel()
            cancelBackgroundGeneration()
        }
        .onDisappear {
            AppResourceCoordinator.shared.setStrainRecoveryForegroundCritical(false)
            deferredSummaryLoadingTask?.cancel()
            deferredSuggestionsRefreshTask?.cancel()
            summaryPrerequisiteTask?.cancel()
            cancelBackgroundGeneration()
        }
    }

    @MainActor
    private func loadPersistedSummary(for request: StrainRecoverySummaryRequest) {
        guard let entry = cacheSnapshot[request.requestID] else {
            persistedEntry = nil
            if displayedRequestID != request.requestID {
                summaryText = ""
                statusText = "Preparing your summary..."
            }
            return
        }
        guard !shouldRequireAppleIntelligenceByDefault || entry.source == .appleIntelligence else {
            persistedEntry = nil
            summaryText = ""
            statusText = "Preparing Apple Intelligence summary..."
            return
        }
        persistedEntry = entry
        summaryText = entry.summaryText
        statusText = entry.cacheStatusText(currentDeviceID: StrainRecoverySummaryDevice.current.id)
        displayedRequestID = request.requestID
        requestedRequestID = request.requestID
    }

    @MainActor
    private func restorePreferredCachedSummary(
        for request: StrainRecoverySummaryRequest,
        fallbackStatus: String
    ) -> Bool {
        guard let entry = cacheSnapshot[request.requestID] else {
            statusText = fallbackStatus
            return false
        }

        persistedEntry = entry
        summaryText = entry.summaryText
        displayedRequestID = entry.requestID
        requestedRequestID = entry.requestID

        if entry.source == .appleIntelligence {
            statusText = "Apple Intelligence refresh used the synced AI summary from \(entry.createdByDeviceName)."
        } else {
            statusText = fallbackStatus
        }
        return entry.source == .appleIntelligence
    }

    @MainActor
    private func savePersistedSummary(_ entry: StrainRecoverySummaryCacheEntry, updateDisplayed: Bool = true) {
        StrainRecoverySummaryPersistence.saveEntry(
            entry,
            forceOverwrite: entry.isRefreshOverride
        )
        cacheSnapshot[entry.requestID] = entry
        if updateDisplayed {
            persistedEntry = entry
            summaryText = entry.summaryText
            displayedRequestID = entry.requestID
            requestedRequestID = entry.requestID
        }
    }

    @MainActor
    private func markUnresolvedAppleIntelligenceState(_ message: String, for request: StrainRecoverySummaryRequest) {
        summaryText = ""
        statusText = message
        requestedRequestID = request.requestID
        displayedRequestID = nil
    }

    @MainActor
    private func appleIntelligenceFailureMessage(
        base: String,
        error: Error?,
        prompt: String
    ) -> String {
        let promptCount = prompt.count
        let detail = error.map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if detail.isEmpty {
            return "\(base) Prompt size: \(promptCount) chars."
        }
        return "\(base) \(detail) Prompt size: \(promptCount) chars."
    }

    @MainActor
    private func clearPersistedSummary(for request: StrainRecoverySummaryRequest) {
        StrainRecoverySummaryPersistence.removeEntry(requestID: request.requestID)
        cacheSnapshot.removeValue(forKey: request.requestID)
        if persistedEntry?.requestID == request.requestID {
            persistedEntry = nil
        }
        if displayedRequestID == request.requestID {
            summaryText = ""
            statusText = "Refreshing with Apple Intelligence..."
            displayedRequestID = nil
        }
    }

    @MainActor
    private func cancelBackgroundGeneration() {
        backgroundGenerationStarterTask?.cancel()
        backgroundGenerationStarterTask = nil
        backgroundGenerationTask?.cancel()
        backgroundGenerationTask = nil
        backgroundGenerationContextID = nil
        backgroundFetchStatusText = nil
    }

    @MainActor
    private func requestForCachedEntry(_ entry: StrainRecoverySummaryCacheEntry) async -> StrainRecoverySummaryRequest? {
        guard let filter = StrainRecoveryView.TimeFilter(rawValue: entry.timeFilterRawValue) else {
            return nil
        }

        let suggestions = SummarySuggestion.buildSuggestions(
            engine: engine,
            timeFilter: filter,
            sportFilter: entry.scopedSport,
            anchorDate: entry.anchorDate
        )

        let suggestion = SummarySuggestion.resolveSuggestion(
            id: entry.suggestionID,
            from: suggestions,
            scopedSport: entry.scopedSport
        )

        return await StrainRecoverySummaryRequest.build(
            engine: engine,
            timeFilter: filter,
            sportFilter: entry.scopedSport,
            anchorDate: entry.anchorDate,
            intentText: suggestion.queryText,
            selectedSuggestion: suggestion,
            refreshVersion: 0
        )
    }

    @MainActor
    private func generateSummary(
        for request: StrainRecoverySummaryRequest,
        forceRefresh: Bool = false,
        updateDisplayed: Bool = true,
        generationMode: StrainRecoverySummaryGenerationMode = .live,
        requireAppleIntelligence: Bool = false,
        allowLocalRefreshFallback: Bool = false
    ) async {
        let requireAppleIntelligence = requireAppleIntelligence || shouldRequireAppleIntelligenceByDefault
        let allowLocalRefreshFallback = shouldRequireAppleIntelligenceByDefault ? false : allowLocalRefreshFallback
        if updateDisplayed {
            cancelBackgroundGeneration()
            requestedRequestID = request.requestID
            displayedRequestID = request.requestID
        }
        guard summaryGenerationReadiness.canGenerate else {
            if updateDisplayed {
                if summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayedRequestID != request.requestID {
                    summaryText = ""
                }
                statusText = summaryGenerationReadiness.statusText
            }
            return
        }

        if !forceRefresh, updateDisplayed, displayedRequestID == request.requestID,
           !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        if !forceRefresh, let persistedEntry, persistedEntry.requestID == request.requestID {
            if updateDisplayed {
                summaryText = persistedEntry.summaryText
                statusText = persistedEntry.cacheStatusText(currentDeviceID: StrainRecoverySummaryDevice.current.id)
                displayedRequestID = request.requestID
                requestedRequestID = request.requestID
            }
            return
        }

        guard activeRequestKey != request.requestID else { return }

        guard !request.prompt.isEmpty else {
            summaryText = request.fallbackSummary
            statusText = request.insufficiencyReason ?? "Not enough strain and recovery data yet."
            return
        }

        activeRequestKey = request.requestID
        isLoading = true
        defer {
            isLoading = false
            activeRequestKey = nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            let worstCaseRetry = coachRetryInstruction(
                forAttempt: 1,
                refreshVersion: request.refreshVersion,
                previousSummary: forceRefresh ? persistedEntry?.summaryText ?? summaryText : nil
            )
            let rawPrompt = promptWithSiblingTimeFilterContext(
                for: request,
                cache: StrainRecoverySummaryPersistence.load()
            )
            print("[CoachAI][summary] requestID=\(request.requestID) filter=\(request.timeFilter.rawValue) suggestion=\(request.selectedSuggestionTitle) rawPromptChars=\(rawPrompt.count) rawPromptEmpty=\(rawPrompt.isEmpty)")
            let generationPrompt = enforceCoachPromptBudget(
                rawPrompt,
                timeFilter: request.timeFilter,
                instructions: strainRecoverySessionInstructions,
                retryText: worstCaseRetry
            )
            print("[CoachAI][summary] generationPromptChars=\(generationPrompt.count) generationPromptEmpty=\(generationPrompt.isEmpty)")

            guard model.isAvailable else {
                if requireAppleIntelligence {
                    guard updateDisplayed else { return }
                    if updateDisplayed {
                        let fallbackMessage = "Apple Intelligence is unavailable on this device, and no synced AI summary is available yet."
                        let restoredAI = restorePreferredCachedSummary(
                            for: request,
                            fallbackStatus: fallbackMessage
                        )
                        if restoredAI || !allowLocalRefreshFallback {
                            if !restoredAI {
                                markUnresolvedAppleIntelligenceState(
                                    appleIntelligenceFailureMessage(
                                        base: fallbackMessage,
                                        error: nil,
                                        prompt: generationPrompt
                                    ),
                                    for: request
                                )
                            }
                            return
                        }
                    }
                }
                let resolvedSummary = request.fallbackSummary
                let resolvedStatus = request.unavailableStatusText(for: model.availability)
                if updateDisplayed {
                    summaryText = resolvedSummary
                    statusText = liveStatusText(for: generationMode, source: .localFallback)
                }
                savePersistedSummary(
                    buildCacheEntry(
                        for: request,
                        summaryText: resolvedSummary,
                        statusText: resolvedStatus,
                        source: .localFallback,
                        generationMode: generationMode,
                        isRefreshOverride: forceRefresh
                    ),
                    updateDisplayed: updateDisplayed
                )
                return
            }

            do {
                let cleaned = try await generateValidatedModelSummary(
                    model: model,
                    prompt: generationPrompt,
                    refreshVersion: request.refreshVersion,
                    previousSummary: forceRefresh ? persistedEntry?.summaryText ?? summaryText : nil
                )

                let resolvedSummary: String
                let resolvedStatus: String
                if cleaned.isEmpty {
                    if requireAppleIntelligence {
                        guard updateDisplayed else { return }
                        if updateDisplayed {
                            let fallbackMessage = "Apple Intelligence did not return a usable summary, and no synced AI summary is available yet."
                            let restoredAI = restorePreferredCachedSummary(
                                for: request,
                                fallbackStatus: fallbackMessage
                            )
                            if restoredAI || !allowLocalRefreshFallback {
                                if !restoredAI {
                                    markUnresolvedAppleIntelligenceState(
                                        appleIntelligenceFailureMessage(
                                            base: fallbackMessage,
                                            error: nil,
                                            prompt: generationPrompt
                                        ),
                                        for: request
                                    )
                                }
                                return
                            }
                        }
                    }
                    resolvedSummary = request.fallbackSummary
                    resolvedStatus = "Model returned an unusable response, so this summary is using local metric rules."
                } else {
                    resolvedSummary = cleaned
                    resolvedStatus = liveStatusText(for: generationMode, source: .appleIntelligence)
                }
                if updateDisplayed {
                    summaryText = resolvedSummary
                    statusText = resolvedStatus
                }
                savePersistedSummary(
                    buildCacheEntry(
                        for: request,
                        summaryText: resolvedSummary,
                        statusText: resolvedStatus,
                        source: cleaned.isEmpty ? .localFallback : .appleIntelligence,
                        generationMode: forceRefresh ? .refresh : generationMode,
                        isRefreshOverride: forceRefresh
                    ),
                    updateDisplayed: updateDisplayed
                )
                return
            } catch {
                print("[CoachAI] Apple Intelligence generation failed",
                      "requestID=\(request.requestID)",
                      "filter=\(request.timeFilter.rawValue)",
                      "suggestion=\(request.selectedSuggestionTitle)",
                      "promptChars=\(generationPrompt.count)",
                      "error=\(String(describing: error))")
                if requireAppleIntelligence {
                    guard updateDisplayed else { return }
                    if updateDisplayed {
                        let fallbackMessage = appleIntelligenceFailureMessage(
                            base: "Apple Intelligence summary generation failed, and no synced AI summary is available yet.",
                            error: error,
                            prompt: generationPrompt
                        )
                        let restoredAI = restorePreferredCachedSummary(
                            for: request,
                            fallbackStatus: fallbackMessage
                        )
                        if restoredAI || !allowLocalRefreshFallback {
                            if !restoredAI {
                                markUnresolvedAppleIntelligenceState(fallbackMessage, for: request)
                            }
                            return
                        }
                    }
                }
                let resolvedSummary = request.fallbackSummary
                let resolvedStatus = liveStatusText(for: generationMode, source: .localFallback)
                if updateDisplayed {
                    summaryText = resolvedSummary
                    statusText = resolvedStatus
                }
                savePersistedSummary(
                    buildCacheEntry(
                        for: request,
                        summaryText: resolvedSummary,
                        statusText: resolvedStatus,
                        source: .localFallback,
                        generationMode: generationMode,
                        isRefreshOverride: forceRefresh
                    ),
                    updateDisplayed: updateDisplayed
                )
                return
            }
        }
        #endif

        if requireAppleIntelligence {
            guard updateDisplayed else { return }
            if updateDisplayed {
                let fallbackMessage = "Apple Intelligence is unavailable here, and no synced AI summary is available yet."
                let restoredAI = restorePreferredCachedSummary(
                    for: request,
                    fallbackStatus: fallbackMessage
                )
                if restoredAI || !allowLocalRefreshFallback {
                    if !restoredAI {
                        markUnresolvedAppleIntelligenceState(
                            appleIntelligenceFailureMessage(
                                base: fallbackMessage,
                                error: nil,
                                prompt: ""
                            ),
                            for: request
                        )
                    }
                    return
                }
            }
        }

        let resolvedSummary = request.fallbackSummary
        let resolvedStatus = liveStatusText(for: generationMode, source: .localFallback)
        if updateDisplayed {
            summaryText = resolvedSummary
            statusText = resolvedStatus
        }
        savePersistedSummary(
            buildCacheEntry(
                for: request,
                summaryText: resolvedSummary,
                statusText: resolvedStatus,
                source: .localFallback,
                generationMode: generationMode,
                isRefreshOverride: forceRefresh
            ),
            updateDisplayed: updateDisplayed
        )
    }

    @available(iOS 26.0, *)
    private func generateValidatedModelSummary(
        model: SystemLanguageModel,
        prompt: String,
        refreshVersion: Int,
        previousSummary: String? = nil
    ) async throws -> String {
        let maxAttempts = refreshVersion > 0 ? 5 : 3
        var effectivePrompt = prompt

        print("[CoachAI][gen] START maxAttempts=\(maxAttempts) refreshVersion=\(refreshVersion) promptChars=\(prompt.count) promptTokens~\(approximateTokenCount(prompt))")

        let worstRetry = coachRetryInstruction(
            forAttempt: max(0, maxAttempts - 1),
            refreshVersion: refreshVersion,
            previousSummary: previousSummary
        )
        let instrTokens = approximateTokenCount(strainRecoveryCoachInstructions)
        let promptTokens = approximateTokenCount(effectivePrompt)
        let retryTokens = approximateTokenCount(worstRetry)
        let totalEstimate = instrTokens + promptTokens + retryTokens + coachReservedResponseTokens
        print("[CoachAI][gen] preSendCheck totalEstimate=\(totalEstimate) (instr=\(instrTokens) prompt=\(promptTokens) retry=\(retryTokens) resp=\(coachReservedResponseTokens)) limit=\(coachMaximumContextTokens - 100)")
        if totalEstimate > coachMaximumContextTokens - 100 {
            let safeBudget = coachMaximumContextTokens - instrTokens - retryTokens - coachReservedResponseTokens - 100
            print("[CoachAI][gen] preSendCheck TRIGGERED, trimming prompt to safeBudget=\(max(400, safeBudget))")
            effectivePrompt = trimPromptToTokenBudget(
                abstractPromptToLevel(effectivePrompt, level: 1),
                budget: max(400, safeBudget)
            )
            print("[CoachAI][gen] afterTrim promptChars=\(effectivePrompt.count) promptTokens~\(approximateTokenCount(effectivePrompt))")
        }

        var didShrinkForContextOverflow = false

        for attempt in 0..<maxAttempts {
            let retrySeedOffset = refreshVersion + attempt
            let retryText = coachRetryInstruction(
                forAttempt: attempt,
                refreshVersion: refreshVersion,
                previousSummary: previousSummary
            )
            let combinedPrompt = effectivePrompt + retryText

            print("[CoachAI][gen] attempt=\(attempt) combinedChars=\(combinedPrompt.count) combinedTokens~\(approximateTokenCount(combinedPrompt)) retryTextChars=\(retryText.count)")
            print("[CoachAI][gen] SENDING TO MODEL:\n\(combinedPrompt)\n[CoachAI][gen] END PROMPT")

            let session = LanguageModelSession(
                model: model,
                instructions: strainRecoverySessionInstructions
            )

            let cleaned: String
            do {
                let response = try await session.respond(
                    to: combinedPrompt,
                    options: GenerationOptions(
                        sampling: retrySeedOffset == 0 ? .greedy : .random(top: 6, seed: UInt64(retrySeedOffset)),
                        temperature: retrySeedOffset == 0 ? 0 : min(0.9, 0.42 + (Double(attempt) * 0.12)),
                        maximumResponseTokens: coachReservedResponseTokens
                    )
                )
                let rawCleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned = collapseToSingleParagraph(rawCleaned)
                print("[CoachAI][gen] attempt=\(attempt) responseChars=\(cleaned.count) isEmpty=\(cleaned.isEmpty)")
                if !cleaned.isEmpty {
                    print("[CoachAI][gen] RESPONSE:\n\(String(cleaned.prefix(500)))")
                }
            } catch {
                let desc = String(describing: error)
                print("[CoachAI][gen] attempt=\(attempt) ERROR: \(desc)")
                if desc.contains("exceededContextWindowSize") || desc.contains("exceeds the maximum allowed context size") {
                    guard !didShrinkForContextOverflow else {
                        print("[CoachAI][gen] already shrunk once, rethrowing")
                        throw error
                    }
                    didShrinkForContextOverflow = true
                    effectivePrompt = trimPromptToTokenBudget(
                        abstractPromptToLevel(effectivePrompt, level: 2),
                        budget: max(400, approximateTokenCount(effectivePrompt) * 6 / 10)
                    )
                    print("[CoachAI][gen] shrunk to level2, newPromptChars=\(effectivePrompt.count) newPromptTokens~\(approximateTokenCount(effectivePrompt))")
                    continue
                }
                throw error
            }

            let hasRepeated = containsRepeatedPhrase(in: cleaned)
            let hasDisallowed = containsDisallowedCoachFormatting(cleaned)
            let hasAdviceLeak = combinedPrompt.contains(CoachPromptFragments.noSuggestions) && containsDisallowedAdvice(cleaned)
            let citesHRRWithoutPrompt = !coachPromptAllowsHRRCitation(effectivePrompt) && coachResponseMentionsHRR(cleaned)
            let citesMETWithoutPrompt = !coachPromptAllowsMETCitation(effectivePrompt) && coachResponseMentionsMET(cleaned)
            print("[CoachAI][gen] attempt=\(attempt) validation: empty=\(cleaned.isEmpty) repeated=\(hasRepeated) disallowedFormat=\(hasDisallowed) adviceLeak=\(hasAdviceLeak) hrrLeak=\(citesHRRWithoutPrompt) metLeak=\(citesMETWithoutPrompt)")

            if !cleaned.isEmpty, !hasRepeated, !hasDisallowed, !hasAdviceLeak, !citesHRRWithoutPrompt, !citesMETWithoutPrompt {
                print("[CoachAI][gen] ACCEPTED on attempt=\(attempt)")
                return cleaned
            }
        }

        print("[CoachAI][gen] ALL ATTEMPTS EXHAUSTED, returning empty")
        return ""
    }

    private func coachRetryInstruction(
        forAttempt attempt: Int,
        refreshVersion: Int,
        previousSummary: String?
    ) -> String {
        guard attempt > 0 || refreshVersion > 0 else { return "" }
        let previousExcerpt: String
        if let previousSummary, !previousSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            previousExcerpt = String(previousSummary.prefix(220))
        } else {
            previousExcerpt = ""
        }
        return """

        Retry guidance:
        - The previous draft was rejected because it was repetitive, low-quality, or looped awkwardly.
        - Write one clean coaching paragraph with no repeated phrases, no filler, and no looping wording.
        - Do not use bullet points, numbering, headings, or multiple paragraphs.
        - Make every meaningful claim traceable to a number in the prompt, and use a date or time range when one exists.
        - If you critique a pattern, keep the wording tentative with terms like might, may, maybe, could, seems, or appears.
        - Check your output before finishing. If you find yourself repeating the same sentence, phrase, or paragraph, rewrite it.
        - If evidence is thin, say that briefly instead of guessing.
        \(refreshVersion > 0 ? "- This is a refresh. Do not reuse the same opening, same thesis sentence, or same evidence ordering as the prior summary." : "")
        \(refreshVersion > 0 ? "- Keep the same facts if they are true, but choose a materially different coaching angle, framing, and sentence structure." : "")
        \(!previousExcerpt.isEmpty ? "- Prior summary excerpt to avoid echoing: \(previousExcerpt)" : "")
        """
    }

    private func isEffectivelySameSummary(
        _ newSummary: String,
        as previousSummary: String?,
        isRefresh: Bool
    ) -> Bool {
        guard isRefresh,
              let previousSummary,
              !previousSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let normalizedNew = normalizedCoachComparisonText(newSummary)
        let normalizedPrevious = normalizedCoachComparisonText(previousSummary)
        guard !normalizedNew.isEmpty, !normalizedPrevious.isEmpty else { return false }

        if normalizedNew == normalizedPrevious {
            return true
        }

        let newWords = Set(normalizedNew.components(separatedBy: " ").filter { !$0.isEmpty })
        let previousWords = Set(normalizedPrevious.components(separatedBy: " ").filter { !$0.isEmpty })
        guard !newWords.isEmpty, !previousWords.isEmpty else { return false }

        let intersectionCount = newWords.intersection(previousWords).count
        let unionCount = newWords.union(previousWords).count
        guard unionCount > 0 else { return false }

        let overlapRatio = Double(intersectionCount) / Double(unionCount)
        return overlapRatio > 0.82
    }

    private func normalizedCoachComparisonText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isJunkCoachOutput(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return true }
        guard normalized.count >= 80 else { return true }

        let sentences = normalized
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sentences.isEmpty else { return true }

        let uniqueSentences = Set(sentences)
        if uniqueSentences.count * 2 <= sentences.count {
            return true
        }

        let words = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard words.count >= 20 else { return true }

        let uniqueWords = Set(words)
        if Double(uniqueWords.count) / Double(words.count) < 0.38 {
            return true
        }

        var bigramCounts: [String: Int] = [:]
        if words.count >= 2 {
            for index in 0..<(words.count - 1) {
                let bigram = words[index] + " " + words[index + 1]
                bigramCounts[bigram, default: 0] += 1
            }
        }

        let repeatedBigrams = bigramCounts.values.filter { $0 >= 3 }.count
        if repeatedBigrams >= 2 {
            return true
        }

        let suspiciousPhrases = [
            "again and again",
            "over and over",
            "again again",
            "it is junk",
            "junk output"
        ]

        if suspiciousPhrases.contains(where: normalized.contains) {
            return true
        }

        return false
    }

    @MainActor
    private func buildCacheEntry(
        for request: StrainRecoverySummaryRequest,
        summaryText: String,
        statusText: String,
        source: SummarySourceKind,
        generationMode: StrainRecoverySummaryGenerationMode,
        isRefreshOverride: Bool
    ) -> StrainRecoverySummaryCacheEntry {
        let device = StrainRecoverySummaryDevice.current
        return StrainRecoverySummaryCacheEntry(
            requestID: request.requestID,
            summaryText: summaryText,
            statusText: statusText,
            generatedAt: Date(),
            latestWorkoutTimestamp: request.latestWorkoutTimestamp,
            intentDisplayName: request.intent.displayName,
            anchorDate: request.anchorDate,
            timeFilterRawValue: request.timeFilter.rawValue,
            suggestionID: request.suggestionID,
            scopedSport: request.scopedSport,
            createdByDeviceID: device.id,
            createdByDeviceName: device.name,
            sourceRawValue: source.rawValue,
            generationModeRawValue: generationMode.rawValue,
            expiresAt: request.expiresAt,
            lastRefreshedAt: isRefreshOverride ? Date() : nil,
            isRefreshOverride: isRefreshOverride
        )
    }

    @MainActor
    private func liveStatusText(
        for generationMode: StrainRecoverySummaryGenerationMode,
        source: SummarySourceKind
    ) -> String {
        let deviceName = StrainRecoverySummaryDevice.current.name
        let sourceText = source == .appleIntelligence ? "Apple Intelligence" : "local metric rules"
        switch generationMode {
        case .live:
            return "Generated live on \(deviceName) using \(sourceText). Saved to cache and iCloud."
        case .background:
            return "Generated in background on \(deviceName) using \(sourceText). Saved to cache and iCloud."
        case .refresh:
            return "Refreshed live on \(deviceName) using \(sourceText). This version replaced cache and iCloud for this report."
        }
    }
}

private struct SummaryPreparationAnimationView: View {
    let title: String
    let subtitle: String
    @State private var travel: CGFloat = -160
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .leading) {
                let capsuleShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

                capsuleShape
                    .fill(Color.orange.opacity(0.08))
                    .frame(height: 58)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        Color.orange.opacity(0.12),
                                        Color.blue.opacity(0.18),
                                        Color.clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 170, height: 58)
                            .offset(x: travel)
                            .blur(radius: 1.2)
                    }
                    .clipShape(capsuleShape)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 28, height: 28)
                            .scaleEffect(pulse ? 1.08 : 0.92)
                        Image(systemName: "sparkles")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("Apple Intelligence is preparing a fresh coaching read.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            travel = -160
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                travel = 320
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct TrainingFocusReportView: View {
    let report: TrainingFocusReportPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Focus report view")
                        .font(.headline)
                    Text("\(report.sportLabel) • \(report.periodLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(report.physiologicalLoadProfile.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Confidence: \(report.dataConfidence)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(report.metrics) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(metric.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if !report.questSummary.isEmpty {
                Text("Quest summary: \(report.questSummary)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let metBase = report.sameSportMetBaselineLine {
                Text(metBase)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !report.trendLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trend lines")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    ForEach(Array(report.trendLines.prefix(4).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }

            if !report.standoutSessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent sessions")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    ForEach(report.standoutSessions) { session in
                        Text("\(session.date): \(session.summary)")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }

            if !report.coachValidationRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dated metrics (verify coach)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("Each row is the date, metric name, and value sent to the coach for this sport window—use it to check trend claims.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.coachValidationRows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.dateLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.orange.opacity(0.95))
                                    .frame(minWidth: 108, alignment: .leading)
                                Text(row.dataType)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 118, alignment: .leading)
                                Text(row.value)
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1.1)
        )
    }
}

private struct StrainRecoverySummaryRequest {
    let prompt: String
    let fallbackSummary: String
    let requestID: String
    let latestWorkoutTimestamp: TimeInterval?
    let intent: SummaryIntent
    let focusMode: AthleticCoachFocusMode
    let refreshVersion: Int
    let anchorDate: Date
    let timeFilter: StrainRecoveryView.TimeFilter
    let suggestionID: String
    let selectedSuggestionTitle: String
    let scopedSport: String?
    let expiresAt: Date?
    let insufficiencyReason: String?

    @MainActor
    static func build(
        engine: HealthStateEngine,
        timeFilter: StrainRecoveryView.TimeFilter,
        sportFilter: String?,
        anchorDate: Date,
        intentText: String,
        selectedSuggestion: SummarySuggestion?,
        refreshVersion: Int
    ) async -> Self {
        let calendar = Calendar.current
        let requestedDay = calendar.startOfDay(for: anchorDate)
        let reportPeriod = summaryReportPeriod(for: timeFilter, requestedDate: requestedDay)
        let window = (start: reportPeriod.start, end: reportPeriod.end, endExclusive: reportPeriod.endExclusive)
        let effectiveSuggestion = selectedSuggestion ?? SummarySuggestion.defaultSuggestion
        let intent = effectiveSuggestion.intent
        let focusMode = effectiveSuggestion.focusMode
        let scopedSport = effectiveSuggestion.scopedSport ?? sportFilter

        let latestWorkoutTimestamp = engine.workoutAnalytics
            .map(\.workout.endDate.timeIntervalSince1970)
            .max()

        let payload = await precomputeCoachPayload(
            engine: engine,
            timeFilter: timeFilter,
            anchorDate: anchorDate,
            suggestionID: effectiveSuggestion.id,
            sportFilter: scopedSport
        )

        let sleepTotals = engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        }
        let sleepData = filteredWindowSeries(values: sleepTotals, in: window)
        let hrvValues = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        let hrvData = filteredWindowSeries(values: hrvValues, in: window)
        let rhrData = filteredWindowSeries(values: engine.dailyRestingHeartRate, in: window)
        let sleepHRData = filteredWindowSeries(values: engine.dailySleepHeartRate, in: window)
        let hrrData = filteredWindowSeries(values: engine.dailyHRRAggregates, in: window)
        let respiratoryData = filteredWindowSeries(values: engine.respiratoryRate, in: window)
        let wristTempData = filteredWindowSeries(values: engine.wristTemperature, in: window)
        let spo2Data = filteredWindowSeries(values: engine.spO2, in: window)
        let metData = filteredWindowSeries(values: engine.dailyMETAggregates, in: window)
        let vo2Data = filteredWindowSeries(values: engine.dailyVO2Aggregates, in: window)

        let historicalWindowStart = calendar.date(byAdding: .day, value: -27, to: window.start) ?? window.start
        let allWorkouts = engine.workoutAnalytics.filter { workout, _ in
            let matchesDate = workout.startDate >= historicalWindowStart && workout.startDate < window.endExclusive
            let matchesSport = scopedSport == nil || workout.workoutActivityType.name == scopedSport
            return matchesDate && matchesSport
        }
        let displayWorkouts = allWorkouts.filter { $0.workout.startDate >= window.start && $0.workout.startDate < window.endExclusive }

        let insufficiencyReason = summaryInsufficiencyReason(
            focusMode: focusMode,
            scopedSport: scopedSport,
            displayWorkouts: displayWorkouts,
            sleepData: sleepData,
            hrvData: hrvData,
            rhrData: rhrData,
            sleepHRData: sleepHRData,
            hrrData: hrrData,
            respiratoryData: respiratoryData,
            wristTempData: wristTempData,
            spo2Data: spo2Data,
            metData: metData,
            vo2Data: vo2Data
        )

        let displayedStrain = payload.strainScore ?? engine.strainScore
        let selectedRecoveryScore = payload.recoveryScore ?? engine.recoveryScore
        let selectedReadinessScore = payload.readinessScore ?? engine.readinessScore

        let midpointSeries = filteredWindowSeries(values: engine.sleepMidpointHours, in: window)
        let effortData = filteredWindowSeries(values: engine.effortRating, in: window)
        let loadSnapshots = dailyLoadSnapshots(workouts: allWorkouts, estimatedMaxHeartRate: engine.estimatedMaxHeartRate, displayWindow: window)
        let selectedSnapshot = loadSnapshots.last(where: { calendar.isDate($0.date, inSameDayAs: reportPeriod.end) }) ?? loadSnapshots.last
        let reportDayCount = max(1, calendar.dateComponents([.day], from: window.start, to: window.endExclusive).day ?? timeFilter.dayCount)
        let workoutHighlightsVal = workoutHighlights(displayWorkouts: displayWorkouts, dayCount: reportDayCount)
        let consistencyScore = sleepConsistencyScore(midpointSeries: midpointSeries, fallback: engine.sleepConsistency ?? 0)
        let sleepDebtHours = sleepDebt(sleepData: sleepData)
        let activityRecoveryGap = activityRecoverySleepGap(engine: engine, midpointSeries: midpointSeries)
        let totalLoad = effortData.map(\.1).reduce(0, +)
        let scoreContext = periodScoreContext(
            timeFilter: timeFilter, reportPeriod: reportPeriod, loadSnapshots: loadSnapshots,
            engine: engine, displayWorkouts: displayWorkouts,
            anchorStrain: displayedStrain, anchorRecovery: selectedRecoveryScore,
            anchorReadiness: selectedReadinessScore, internalEffortRatingSum: totalLoad
        )

        let prompt: String
        if insufficiencyReason == nil {
            prompt = buildCompactPrompt(from: payload, suggestion: effectiveSuggestion)
                + "\n\nNamed period scores and load (use these labels verbatim; do not invent a separate \"performance score\"):\n"
                + scoreContext.promptBlock
        } else {
            prompt = ""
        }
        print("[CoachAI][build] rawPrompt chars=\(prompt.count) tokens~\(approximateTokenCount(prompt)) insufficiency=\(insufficiencyReason ?? "none")")
        if !prompt.isEmpty { print("[CoachAI][build] PROMPT START\n\(prompt)\n[CoachAI][build] PROMPT END") }
        if !payload.hrrSeries.isEmpty {
            print("[CoachAI][hrr-diag] HRR series: \(payload.hrrSeries.map { "\($0.date):\($0.value)bpm" }.joined(separator: " "))")
        }

        let selectedDayWorkouts = displayWorkouts.filter { calendar.isDate($0.workout.startDate, inSameDayAs: reportPeriod.canonicalAnchorDate) }
        let scenario = dayScenario(timeFilter: timeFilter, selectedDayWorkouts: selectedDayWorkouts)

        let fallbackSummary = insufficiencyReason.map { base in
            if let bridge = payload.fallbackBridge, !bridge.isEmpty {
                return "\(base) \(bridge)"
            }
            return base
        } ?? localFallbackSummary(
                displayedStrain: displayedStrain,
                recoveryScore: selectedRecoveryScore,
                scoreContextLead: scoreContext.fallbackLead,
                workoutHighlights: workoutHighlightsVal,
                selectedSnapshot: selectedSnapshot,
                scenario: scenario,
                intent: intent,
                timeFilter: timeFilter,
                sleepData: sleepData,
                sleepDebtHours: sleepDebtHours,
                consistencyScore: consistencyScore,
                activityRecoveryGap: activityRecoveryGap,
                hrvData: hrvData,
                rhrData: rhrData,
                sleepHRData: sleepHRData,
                hrrData: hrrData,
                respiratoryData: respiratoryData,
                wristTempData: wristTempData,
                spo2Data: spo2Data
            )

        let requestID = [
            strainRecoverySummaryRequestVersion,
            timeFilter.rawValue,
            scopedSport ?? "all",
            String(reportPeriod.canonicalAnchorDate.timeIntervalSince1970),
            effectiveSuggestion.id
        ].joined(separator: "|")

        let expiresAt = summaryExpirationDate(
            anchorDate: reportPeriod.canonicalAnchorDate,
            generatedAt: Date()
        )

        return Self(
            prompt: prompt,
            fallbackSummary: fallbackSummary,
            requestID: requestID,
            latestWorkoutTimestamp: latestWorkoutTimestamp,
            intent: intent,
            focusMode: focusMode,
            refreshVersion: refreshVersion,
            anchorDate: reportPeriod.canonicalAnchorDate,
            timeFilter: timeFilter,
            suggestionID: effectiveSuggestion.id,
            selectedSuggestionTitle: effectiveSuggestion.title,
            scopedSport: scopedSport,
            expiresAt: expiresAt,
            insufficiencyReason: insufficiencyReason
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func unavailableStatusText(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Generated from on-device Apple Intelligence."
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off on this device, so this summary is using local metric rules."
            case .deviceNotEligible:
                return "This device does not support Apple Intelligence, so this summary is using local metric rules."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready on this device, so this summary is using local metric rules."
            @unknown default:
                return "Apple Intelligence is unavailable, so this summary is using local metric rules."
            }
        }
    }
    #endif
}

private func summaryInsufficiencyReason(
    focusMode: AthleticCoachFocusMode,
    scopedSport: String?,
    displayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    sleepData: [(Date, Double)],
    hrvData: [(Date, Double)],
    rhrData: [(Date, Double)],
    sleepHRData: [(Date, Double)],
    hrrData: [(Date, Double)],
    respiratoryData: [(Date, Double)],
    wristTempData: [(Date, Double)],
    spo2Data: [(Date, Double)],
    metData: [(Date, Double)],
    vo2Data: [(Date, Double)]
) -> String? {
    let hasWorkouts = !displayWorkouts.isEmpty
    let hasRecoveryVitals = !hrvData.isEmpty || !rhrData.isEmpty || !sleepHRData.isEmpty || !respiratoryData.isEmpty || !wristTempData.isEmpty || !spo2Data.isEmpty
    let hasSleep = !sleepData.isEmpty
    let hasAutonomic = !hrrData.isEmpty || !hrvData.isEmpty
    let hasPerformanceLoad = hasWorkouts || !metData.isEmpty || !vo2Data.isEmpty

    switch focusMode {
    case .toughestWorkout:
        return hasWorkouts
            ? nil
            : "There are not enough workout metrics in this period to build a toughest-workout report yet."
    case .latestWorkout:
        return hasWorkouts
            ? nil
            : "There is no workout in this period yet, so there is not enough session data to make a latest-workout report."
    case .sportDeepDive:
        if hasWorkouts { return nil }
        if let scopedSport {
            return "There are not enough \(scopedSport.lowercased()) workouts or sport-specific metrics in this period to build that coach report yet."
        }
        return "There are not enough sport-specific workouts in this period to build that coach report yet."
    case .recoveryVitalsSleep:
        if hasSleep || hasRecoveryVitals || hasAutonomic { return nil }
        return "There are not enough sleep and recovery metrics in this period to make that report yet."
    case .trendBalance:
        if hasWorkouts || hasSleep || hasRecoveryVitals { return nil }
        return "There are not enough strain, recovery, sleep, or workout metrics in this period to identify a meaningful trend yet."
    case .general:
        if hasPerformanceLoad || hasSleep || hasRecoveryVitals { return nil }
        return "There are not enough health and training metrics in this period to make that coach report yet."
    }
}

private enum StrainRecoverySummaryGenerationMode: String, Codable {
    case live
    case background
    case refresh
}

private struct StrainRecoverySummaryCacheEntry: Codable, Equatable {
    let requestID: String
    let summaryText: String
    let statusText: String
    let generatedAt: Date
    let latestWorkoutTimestamp: TimeInterval?
    let intentDisplayName: String
    let anchorDate: Date
    let timeFilterRawValue: String
    let suggestionID: String
    let scopedSport: String?
    let createdByDeviceID: String
    let createdByDeviceName: String
    let sourceRawValue: String
    let generationModeRawValue: String
    let expiresAt: Date?
    let lastRefreshedAt: Date?
    let isRefreshOverride: Bool

    var source: SummarySourceKind {
        SummarySourceKind(rawValue: sourceRawValue) ?? .localFallback
    }

    var generationMode: StrainRecoverySummaryGenerationMode {
        StrainRecoverySummaryGenerationMode(rawValue: generationModeRawValue) ?? .live
    }

    var isExpired: Bool {
        if let expiresAt {
            return expiresAt < Date()
        }
        return false
    }

    func cacheStatusText(currentDeviceID: String) -> String {
        let sourceDevice = createdByDeviceID == currentDeviceID ? "this device" : createdByDeviceName
        let sourceMode: String
        switch generationMode {
        case .live:
            sourceMode = "generated live"
        case .background:
            sourceMode = "generated in background"
        case .refresh:
            sourceMode = "generated from refresh"
        }
        let sourceLabel = source == .appleIntelligence ? "Apple Intelligence" : "local metric rules"
        return "Loaded from cache. Originally \(sourceMode) on \(sourceDevice) using \(sourceLabel)."
    }
}

private enum StrainRecoverySummaryPersistence {
    static let storageKey = "strain_recovery_ai_summary_cache_v2"
    static let settingsKey = "strain_recovery_ai_summary_sync_settings_v1"
    private static var inMemoryCache: [String: StrainRecoverySummaryCacheEntry]?
    private static var inMemorySettings: StrainRecoverySummarySyncSettings?

    static func load(forceReload: Bool = false) -> [String: StrainRecoverySummaryCacheEntry] {
        if !forceReload, let inMemoryCache {
            let pruned = pruneExpiredEntries(from: inMemoryCache)
            if pruned != inMemoryCache {
                self.inMemoryCache = pruned
            }
            return pruned
        }

        let cloudStore = NSUbiquitousKeyValueStore.default

        let localCache: [String: StrainRecoverySummaryCacheEntry]
        if let localData = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: StrainRecoverySummaryCacheEntry].self, from: localData) {
            localCache = decoded
        } else {
            localCache = [:]
        }

        let cloudCache: [String: StrainRecoverySummaryCacheEntry]
        if let cloudData = cloudStore.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: StrainRecoverySummaryCacheEntry].self, from: cloudData) {
            cloudCache = decoded
        } else {
            cloudCache = [:]
        }

        let merged = mergeCaches(
            localCache,
            cloudCache,
            settings: loadSyncSettings(),
            currentDeviceID: StrainRecoverySummaryDevice.current.id
        )
        let pruned = pruneExpiredEntries(from: merged)
        if pruned != merged || pruned != localCache || pruned != cloudCache {
            save(pruned)
        }
        inMemoryCache = pruned
        return pruned
    }

    static func save(
        _ cache: [String: StrainRecoverySummaryCacheEntry],
        forceOverwriteRequestID: String? = nil
    ) {
        let settings = loadSyncSettings()
        let currentDeviceID = StrainRecoverySummaryDevice.current.id
        let cloudStore = NSUbiquitousKeyValueStore.default

        let existingLocal: [String: StrainRecoverySummaryCacheEntry]
        if let localData = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: StrainRecoverySummaryCacheEntry].self, from: localData) {
            existingLocal = decoded
        } else {
            existingLocal = [:]
        }

        let existingCloud: [String: StrainRecoverySummaryCacheEntry]
        if let cloudData = cloudStore.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: StrainRecoverySummaryCacheEntry].self, from: cloudData) {
            existingCloud = decoded
        } else {
            existingCloud = [:]
        }

        let mergedExisting = mergeCaches(existingLocal, existingCloud, settings: settings, currentDeviceID: currentDeviceID)
        var resolved = mergedExisting
        for (key, value) in cache {
            if let forceOverwriteRequestID, forceOverwriteRequestID == key {
                resolved[key] = value
            } else if value.source == .appleIntelligence {
                resolved[key] = value
            } else if let existing = resolved[key] {
                resolved[key] = preferredEntry(
                    existing: existing,
                    incoming: value,
                    settings: settings,
                    currentDeviceID: currentDeviceID
                )
            } else {
                resolved[key] = value
            }
        }

        let pruned = pruneExpiredEntries(from: resolved)
        guard let encoded = try? JSONEncoder().encode(pruned) else { return }
        inMemoryCache = pruned
        UserDefaults.standard.set(encoded, forKey: storageKey)
        cloudStore.set(encoded, forKey: storageKey)
    }

    static func saveEntry(_ entry: StrainRecoverySummaryCacheEntry, forceOverwrite: Bool = false) {
        save(
            [entry.requestID: entry],
            forceOverwriteRequestID: forceOverwrite ? entry.requestID : nil
        )
    }

    static func removeEntry(requestID: String) {
        var cache = load(forceReload: true)
        cache.removeValue(forKey: requestID)
        guard let encoded = try? JSONEncoder().encode(cache) else { return }
        inMemoryCache = cache
        UserDefaults.standard.set(encoded, forKey: storageKey)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(encoded, forKey: storageKey)
    }

    static func clearAll() {
        inMemoryCache = [:]
        UserDefaults.standard.removeObject(forKey: storageKey)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.removeObject(forKey: storageKey)
    }

    static func pruneExpiredEntries(from cache: [String: StrainRecoverySummaryCacheEntry]) -> [String: StrainRecoverySummaryCacheEntry] {
        cache.filter { _, entry in
            !entry.isExpired
        }
    }

    static func loadSyncSettings(forceReload: Bool = false) -> StrainRecoverySummarySyncSettings {
        if !forceReload, let inMemorySettings {
            return inMemorySettings.resolved()
        }

        let cloudStore = NSUbiquitousKeyValueStore.default
        let cloudSettings: StrainRecoverySummarySyncSettings?
        let localSettings: StrainRecoverySummarySyncSettings?

        if let cloudData = cloudStore.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(StrainRecoverySummarySyncSettings.self, from: cloudData) {
            cloudSettings = decoded.resolved()
        } else {
            cloudSettings = nil
        }

        if let localData = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(StrainRecoverySummarySyncSettings.self, from: localData) {
            localSettings = decoded.resolved()
        } else {
            localSettings = nil
        }

        let resolved = mergedSyncSettings(
            local: localSettings,
            cloud: cloudSettings
        )
        inMemorySettings = resolved
        return resolved
    }

    static func saveSyncSettings(_ settings: StrainRecoverySummarySyncSettings) {
        var resolved = settings.resolved()
        if resolved.primaryDeviceID == StrainRecoverySummaryDevice.current.id,
           !deviceSupportsAppleIntelligence() {
            resolved.primaryDeviceID = nil
        }
        if resolved.temporaryPrimaryDeviceID == StrainRecoverySummaryDevice.current.id,
           !deviceSupportsAppleIntelligence() {
            resolved.temporaryPrimaryDeviceID = nil
            resolved.temporaryPrimaryUntil = nil
        }
        guard let encoded = try? JSONEncoder().encode(resolved) else { return }
        inMemorySettings = resolved
        UserDefaults.standard.set(encoded, forKey: settingsKey)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(encoded, forKey: settingsKey)
    }

    static func invalidateInMemoryState() {
        inMemoryCache = nil
        inMemorySettings = nil
    }

    private static func mergeCaches(
        _ lhs: [String: StrainRecoverySummaryCacheEntry],
        _ rhs: [String: StrainRecoverySummaryCacheEntry],
        settings: StrainRecoverySummarySyncSettings,
        currentDeviceID: String
    ) -> [String: StrainRecoverySummaryCacheEntry] {
        var merged = lhs
        for (key, value) in rhs {
            if let existing = merged[key] {
                merged[key] = preferredEntry(
                    existing: existing,
                    incoming: value,
                    settings: settings,
                    currentDeviceID: currentDeviceID
                )
            } else {
                merged[key] = value
            }
        }
        return merged
    }

    private static func mergedSyncSettings(
        local: StrainRecoverySummarySyncSettings?,
        cloud: StrainRecoverySummarySyncSettings?
    ) -> StrainRecoverySummarySyncSettings {
        let resolvedLocal = local?.resolved()
        let resolvedCloud = cloud?.resolved()

        if let resolvedCloud, resolvedCloud.hasExplicitPrimarySelection {
            return resolvedCloud
        }

        if let resolvedLocal, resolvedLocal.hasExplicitPrimarySelection {
            return resolvedLocal
        }

        if let resolvedCloud {
            return resolvedCloud
        }

        if let resolvedLocal {
            return resolvedLocal
        }

        return .defaultValue
    }

    private static func preferredEntry(
        existing: StrainRecoverySummaryCacheEntry,
        incoming: StrainRecoverySummaryCacheEntry,
        settings: StrainRecoverySummarySyncSettings,
        currentDeviceID: String
    ) -> StrainRecoverySummaryCacheEntry {
        if existing.isExpired { return incoming }
        if incoming.isExpired { return existing }
        if incoming.source == .appleIntelligence && existing.source != .appleIntelligence {
            return incoming
        }
        if existing.source == .appleIntelligence && incoming.source != .appleIntelligence {
            return existing
        }
        if incoming.isRefreshOverride && incoming.generatedAt >= existing.generatedAt {
            return incoming
        }
        if existing.isRefreshOverride && existing.generatedAt >= incoming.generatedAt {
            return existing
        }

        if existing.source != incoming.source {
            if incoming.source == .appleIntelligence {
                return incoming
            }
            if existing.source == .appleIntelligence {
                return existing
            }
        }

        let existingPrimary = settings.isPrimary(deviceID: existing.createdByDeviceID)
        let incomingPrimary = settings.isPrimary(deviceID: incoming.createdByDeviceID)
        if incomingPrimary != existingPrimary {
            return incomingPrimary ? incoming : existing
        }

        if incoming.generatedAt != existing.generatedAt {
            return incoming.generatedAt > existing.generatedAt ? incoming : existing
        }

        if incoming.createdByDeviceID == currentDeviceID {
            return incoming
        }
        return existing
    }
}

private struct StrainRecoverySummaryDevice {
    let id: String
    let name: String

    static var current: StrainRecoverySummaryDevice {
        let storageKey = "strain_recovery_ai_summary_device_id"
        let id: String
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            id = existing
        } else {
            let created = UUID().uuidString
            UserDefaults.standard.set(created, forKey: storageKey)
            id = created
        }
        return StrainRecoverySummaryDevice(id: id, name: UIDevice.current.name)
    }
}

private struct StrainRecoverySummarySyncSettings: Codable {
    var primaryDeviceID: String?
    var temporaryPrimaryDeviceID: String?
    var temporaryPrimaryUntil: Date?
    var intensiveFetchingEnabled: Bool
    var aggressiveCachingRequested: Bool
    var aggressiveSyncSelectionMode: AggressiveSyncSelectionMode
    var aggressiveSyncTimeRangeType: AggressiveSyncTimeRangeType
    var aggressiveSyncSelectedDate: Date
    var aggressiveSyncSelectedSuggestionID: String?
    var passivePrioritySuggestionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case primaryDeviceID
        case temporaryPrimaryDeviceID
        case temporaryPrimaryUntil
        case intensiveFetchingEnabled
        case aggressiveCachingRequested
        case aggressiveSyncSelectionMode
        case aggressiveSyncTimeRangeType
        case aggressiveSyncSelectedDate
        case aggressiveSyncSelectedSuggestionID
        case passivePrioritySuggestionIDs
    }

    static let defaultValue = StrainRecoverySummarySyncSettings(
        primaryDeviceID: nil,
        temporaryPrimaryDeviceID: nil,
        temporaryPrimaryUntil: nil,
        intensiveFetchingEnabled: false,
        aggressiveCachingRequested: false,
        aggressiveSyncSelectionMode: .expectedCache,
        aggressiveSyncTimeRangeType: .weekOfDays,
        aggressiveSyncSelectedDate: Calendar.current.startOfDay(for: Date()),
        aggressiveSyncSelectedSuggestionID: SummarySuggestion.defaultSuggestion.id,
        passivePrioritySuggestionIDs: []
    )

    init(
        primaryDeviceID: String?,
        temporaryPrimaryDeviceID: String?,
        temporaryPrimaryUntil: Date?,
        intensiveFetchingEnabled: Bool,
        aggressiveCachingRequested: Bool,
        aggressiveSyncSelectionMode: AggressiveSyncSelectionMode,
        aggressiveSyncTimeRangeType: AggressiveSyncTimeRangeType,
        aggressiveSyncSelectedDate: Date,
        aggressiveSyncSelectedSuggestionID: String?,
        passivePrioritySuggestionIDs: [String]
    ) {
        self.primaryDeviceID = primaryDeviceID
        self.temporaryPrimaryDeviceID = temporaryPrimaryDeviceID
        self.temporaryPrimaryUntil = temporaryPrimaryUntil
        self.intensiveFetchingEnabled = intensiveFetchingEnabled
        self.aggressiveCachingRequested = aggressiveCachingRequested
        self.aggressiveSyncSelectionMode = aggressiveSyncSelectionMode
        self.aggressiveSyncTimeRangeType = aggressiveSyncTimeRangeType
        self.aggressiveSyncSelectedDate = aggressiveSyncSelectedDate
        self.aggressiveSyncSelectedSuggestionID = aggressiveSyncSelectedSuggestionID
        self.passivePrioritySuggestionIDs = Array(passivePrioritySuggestionIDs.prefix(5))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryDeviceID = try container.decodeIfPresent(String.self, forKey: .primaryDeviceID)
        temporaryPrimaryDeviceID = try container.decodeIfPresent(String.self, forKey: .temporaryPrimaryDeviceID)
        temporaryPrimaryUntil = try container.decodeIfPresent(Date.self, forKey: .temporaryPrimaryUntil)
        intensiveFetchingEnabled = try container.decodeIfPresent(Bool.self, forKey: .intensiveFetchingEnabled) ?? false
        aggressiveCachingRequested = try container.decodeIfPresent(Bool.self, forKey: .aggressiveCachingRequested) ?? false
        aggressiveSyncSelectionMode = try container.decodeIfPresent(AggressiveSyncSelectionMode.self, forKey: .aggressiveSyncSelectionMode) ?? .expectedCache
        aggressiveSyncTimeRangeType = try container.decodeIfPresent(AggressiveSyncTimeRangeType.self, forKey: .aggressiveSyncTimeRangeType) ?? .weekOfDays
        aggressiveSyncSelectedDate = try container.decodeIfPresent(Date.self, forKey: .aggressiveSyncSelectedDate).map { Calendar.current.startOfDay(for: $0) } ?? Calendar.current.startOfDay(for: Date())
        aggressiveSyncSelectedSuggestionID = try container.decodeIfPresent(String.self, forKey: .aggressiveSyncSelectedSuggestionID) ?? SummarySuggestion.defaultSuggestion.id
        passivePrioritySuggestionIDs = Array((try container.decodeIfPresent([String].self, forKey: .passivePrioritySuggestionIDs) ?? []).prefix(5))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(primaryDeviceID, forKey: .primaryDeviceID)
        try container.encodeIfPresent(temporaryPrimaryDeviceID, forKey: .temporaryPrimaryDeviceID)
        try container.encodeIfPresent(temporaryPrimaryUntil, forKey: .temporaryPrimaryUntil)
        try container.encode(intensiveFetchingEnabled, forKey: .intensiveFetchingEnabled)
        try container.encode(aggressiveCachingRequested, forKey: .aggressiveCachingRequested)
        try container.encode(aggressiveSyncSelectionMode, forKey: .aggressiveSyncSelectionMode)
        try container.encode(aggressiveSyncTimeRangeType, forKey: .aggressiveSyncTimeRangeType)
        try container.encode(Calendar.current.startOfDay(for: aggressiveSyncSelectedDate), forKey: .aggressiveSyncSelectedDate)
        try container.encodeIfPresent(aggressiveSyncSelectedSuggestionID, forKey: .aggressiveSyncSelectedSuggestionID)
        try container.encode(Array(passivePrioritySuggestionIDs.prefix(5)), forKey: .passivePrioritySuggestionIDs)
    }

    var hasExplicitPrimarySelection: Bool {
        let resolved = resolved()
        return resolved.primaryDeviceID != nil || resolved.temporaryPrimaryDeviceID != nil
    }

    func resolved() -> Self {
        if let until = temporaryPrimaryUntil, until < Date() {
            return StrainRecoverySummarySyncSettings(
                primaryDeviceID: primaryDeviceID,
                temporaryPrimaryDeviceID: nil,
                temporaryPrimaryUntil: nil,
                intensiveFetchingEnabled: intensiveFetchingEnabled,
                aggressiveCachingRequested: aggressiveCachingRequested,
                aggressiveSyncSelectionMode: aggressiveSyncSelectionMode,
                aggressiveSyncTimeRangeType: aggressiveSyncTimeRangeType,
                aggressiveSyncSelectedDate: aggressiveSyncSelectedDate,
                aggressiveSyncSelectedSuggestionID: aggressiveSyncSelectedSuggestionID,
                passivePrioritySuggestionIDs: passivePrioritySuggestionIDs
            )
        }
        return self
    }

    func isPrimary(deviceID: String) -> Bool {
        let resolved = resolved()
        if let temporaryPrimaryDeviceID = resolved.temporaryPrimaryDeviceID,
           resolved.temporaryPrimaryUntil != nil {
            return temporaryPrimaryDeviceID == deviceID
        }
        return resolved.primaryDeviceID == deviceID
    }
}

private enum SummaryIntent: String, Codable {
    case general
    case trendPB
    case sportSpecific
    case intensityLoad
    case recoveryVitals

    static func detect(from text: String, sportFilter: String?) -> SummaryIntent {
        let normalized = text.lowercased()

        if normalized.contains("pb") || normalized.contains("personal best") || normalized.contains("trend") || normalized.contains("trajectory") || normalized.contains("progress") {
            return .trendPB
        }

        if sportFilter != nil || normalized.contains("cycling") || normalized.contains("running") || normalized.contains("sport") || normalized.contains("discipline") {
            return .sportSpecific
        }

        if normalized.contains("load") || normalized.contains("intensity") || normalized.contains("vo2") || normalized.contains("push") || normalized.contains("pull") {
            return .intensityLoad
        }

        if normalized.contains("recovery") || normalized.contains("vitals") || normalized.contains("sleep") || normalized.contains("biometric") {
            return .recoveryVitals
        }

        return .general
    }

    var displayName: String {
        switch self {
        case .general: return "Overall Coaching"
        case .trendPB: return "Trend and PB Focus"
        case .sportSpecific: return "Sport-Specific Focus"
        case .intensityLoad: return "Intensity and Load Focus"
        case .recoveryVitals: return "Recovery and Vitals Focus"
        }
    }

    var storageKey: String {
        rawValue
    }

    var promptFocus: String {
        displayName
    }

    var promptInstruction: String {
        switch self {
        case .general:
            return "Give the most balanced coaching read on strain, recovery, readiness, and training direction."
        case .trendPB:
            return "Prioritize long-term trajectory, standout improvements, and personal-best style efforts."
        case .sportSpecific:
            return "Turn sport-specific metrics into a short coaching narrative: what the block of training is actually doing for fitness, where overload or under-stimulus shows up, and how to steer the next one to three sessions—without sounding like a metrics export."
        case .intensityLoad:
            return "Prioritize VO2 max, load optimality, acute versus chronic balance, and whether to push or pull back."
        case .recoveryVitals:
            return "Prioritize sleep architecture, biometric recovery, and whether you are absorbing training well."
        }
    }
}

private struct SummarySuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let queryText: String
    let symbol: String
    let intent: SummaryIntent
    let focusMode: AthleticCoachFocusMode
    let scopedSport: String?
    let promptInstructions: String
    let analyticalFramework: String
    let negativeConstraints: String
    let languageStyle: String

    var coachPromptSpec: CoachPromptSpec {
        promptSpec(for: self)
    }

    static let defaultSuggestion = SummarySuggestion(
        id: "1d-readiness",
        title: "Today's Readiness",
        queryText: "today readiness assessment",
        symbol: "bolt.heart",
        intent: .general,
        focusMode: .general,
        scopedSport: nil,
        promptInstructions: "",
        analyticalFramework: "",
        negativeConstraints: "",
        languageStyle: ""
    )

    private static func compact(id: String, title: String, queryText: String, symbol: String, intent: SummaryIntent, focusMode: AthleticCoachFocusMode, scopedSport: String? = nil) -> SummarySuggestion {
        SummarySuggestion(id: id, title: title, queryText: queryText, symbol: symbol, intent: intent, focusMode: focusMode, scopedSport: scopedSport, promptInstructions: "", analyticalFramework: "", negativeConstraints: "", languageStyle: "")
    }

    @MainActor
    static func buildSuggestions(
        engine: HealthStateEngine,
        timeFilter: StrainRecoveryView.TimeFilter,
        sportFilter: String?,
        anchorDate: Date
    ) -> [SummarySuggestion] {
        let calendar = Calendar.current
        let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
        let last7 = calendar.date(byAdding: .day, value: -6, to: window.end) ?? window.end
        let last28 = calendar.date(byAdding: .day, value: -27, to: window.end) ?? window.end

        let workouts7 = engine.workoutAnalytics.filter {
            $0.workout.startDate >= last7 && $0.workout.startDate < window.endExclusive
        }
        let workouts28 = engine.workoutAnalytics.filter {
            $0.workout.startDate >= last28 && $0.workout.startDate < window.endExclusive
        }

        let grouped7 = Dictionary(grouping: workouts7, by: { $0.workout.workoutActivityType.name })
        let grouped28 = Dictionary(grouping: workouts28, by: { $0.workout.workoutActivityType.name })

        var suggestions: [SummarySuggestion] = []

        switch timeFilter {
        case .day:
            suggestions = [
                compact(id: "1d-readiness", title: "Today's Readiness", queryText: "readiness assessment", symbol: "bolt.heart", intent: .general, focusMode: .general),
                compact(id: "1d-sleep-bio", title: "Sleep & Biometrics", queryText: "sleep biometrics", symbol: "bed.double", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep),
                compact(id: "1d-zones", title: "Zone 4/5 Focus", queryText: "high intensity zones", symbol: "waveform.path.ecg", intent: .intensityLoad, focusMode: .general),
                compact(id: "1d-consistency", title: "Consistency", queryText: "training consistency", symbol: "calendar.badge.clock", intent: .trendPB, focusMode: .trendBalance),
            ]

            let candidateSports = sportFilter.map { [$0] } ?? Array(grouped7.keys).sorted()
            for sport in candidateSports.prefix(4) {
                let count7 = grouped7[sport]?.count ?? 0
                guard count7 >= 3 else { continue }
                let sportID = sport.lowercased().replacingOccurrences(of: " ", with: "-")
                suggestions.append(compact(id: "1d-sport-\(sportID)", title: "\(sport.capitalized) Report", queryText: "\(sport) report", symbol: "scope", intent: .sportSpecific, focusMode: .sportDeepDive, scopedSport: sport))
            }

            if grouped7.keys.count > 1 {
                suggestions.append(compact(id: "1d-all-sports", title: "All Sports", queryText: "all sports overview", symbol: "figure.run", intent: .sportSpecific, focusMode: .general))
            }

        case .week:
            suggestions = [
                compact(id: "1w-svr", title: "Strain vs Recovery", queryText: "strain vs recovery trends", symbol: "slider.horizontal.3", intent: .trendPB, focusMode: .trendBalance),
                compact(id: "1w-sleep-bio", title: "Sleep & Bios", queryText: "sleep biometrics trends", symbol: "bed.double", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep),
                compact(id: "1w-zones", title: "Zone 4/5 Focus", queryText: "high intensity zones", symbol: "waveform.path.ecg", intent: .intensityLoad, focusMode: .general),
                compact(id: "1w-pb", title: "Personal Best", queryText: "personal bests", symbol: "trophy", intent: .trendPB, focusMode: .trendBalance),
                compact(id: "1w-consistency", title: "Consistency", queryText: "training consistency", symbol: "calendar.badge.clock", intent: .trendPB, focusMode: .trendBalance),
            ]

            let candidateSports = sportFilter.map { [$0] } ?? Array(grouped7.keys).sorted()
            for sport in candidateSports.prefix(4) {
                let count7 = grouped7[sport]?.count ?? 0
                guard count7 >= 3 else { continue }
                let sportID = sport.lowercased().replacingOccurrences(of: " ", with: "-")
                suggestions.append(compact(id: "1w-sport-\(sportID)", title: "\(sport.capitalized) Report", queryText: "\(sport) report", symbol: "scope", intent: .sportSpecific, focusMode: .sportDeepDive, scopedSport: sport))
            }

        case .month:
            suggestions = [
                compact(id: "1m-overall", title: "Overall Coaching", queryText: "overall coaching", symbol: "sparkles", intent: .general, focusMode: .general),
                compact(id: "1m-consistency", title: "Consistency", queryText: "training consistency", symbol: "calendar.badge.clock", intent: .trendPB, focusMode: .trendBalance),
            ]

            let candidateSports = sportFilter.map { [$0] } ?? Array(grouped28.keys).sorted()
            for sport in candidateSports.prefix(4) {
                let count28 = grouped28[sport]?.count ?? 0
                guard count28 >= 14 else { continue }
                let sportID = sport.lowercased().replacingOccurrences(of: " ", with: "-")
                suggestions.append(compact(id: "1m-sport-\(sportID)", title: "\(sport.capitalized) Report", queryText: "\(sport) report", symbol: "scope", intent: .sportSpecific, focusMode: .sportDeepDive, scopedSport: sport))
            }
        }

        var seenIDs = Set<String>()
        return suggestions.filter { suggestion in
            seenIDs.insert(suggestion.id).inserted
        }
    }

    static func resolveSuggestion(
        id: String,
        from suggestions: [SummarySuggestion],
        scopedSport: String?
    ) -> SummarySuggestion {
        if let directMatch = suggestions.first(where: { $0.id == id }) {
            return directMatch
        }

        if let scopedSport,
           let sportMatch = suggestions.first(where: { $0.scopedSport == scopedSport && $0.id.contains(id) }) {
            return sportMatch
        }

        return suggestions.first ?? defaultSuggestion
    }
}

private func promptSpec(for suggestion: SummarySuggestion) -> CoachPromptSpec {
    let baseFragments = [
        CoachPromptFragments.noMarkdown,
        CoachPromptFragments.noInvention,
        CoachPromptFragments.useUIMetricNames,
        CoachPromptFragments.missingDataBehavior
    ]

    switch suggestion.id {
    case "1d-readiness":
        return CoachPromptSpec(
            primaryScope: "Primary scope: yesterday Recovery and Readiness labels and scores, recent load and strain, and whether today looks ready to push, hold steady, or stay controlled.",
            secondaryContextPolicy: "Secondary context: compact sleep facts and last-workout facts for causality only.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough readiness context to make a strong today call.", allowBridge: true),
            negativeConstraints: [
                "- Do not turn this into a sleep deep dive.",
                "- Do not drift into a week trend report.",
                "- Do not describe [7D] averages or multi-day series values as if they were the anchor-day Strain/Recovery/Readiness in Scores."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.todayActionable, CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    case "1d-sleep-bio":
        return CoachPromptSpec(
            primaryScope: "Primary scope: last night's sleep hours, detailed stages, sleep consistency, Sleep HR, vitals, and sleep-linked reasons for today's Recovery and Readiness.",
            secondaryContextPolicy: "Secondary context: compact load or workout facts only when they explain the sleep-first story.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "Sleep-focused analysis is limited for this report.", allowBridge: true),
            negativeConstraints: [
                "- Sleep must remain the main lens.",
                "- Do not write a workout recap.",
                "- Mention RHR or HRV only as supporting sleep-related evidence.",
                "- Multi-day vitals series are [7D] context; last night is the primary sleep story—do not collapse series into \"last night\" unless dates match."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.todayActionable, CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    case "1d-zones":
        return CoachPromptSpec(
            primaryScope: "Primary scope: (1) Anchor-day high zones: Time in Zone 4 and Time in Zone 5 **only for workouts on the selected calendar day** (see \"Today zone sessions\" lines). (2) Rolling 7d sport-separated totals are **separate**—they summarize the Heart Zones–style 7-day window ending on the selected day, **not** the same thing as \"today\" minutes. Use (1) for what actually happened that day; use (2) for recent high-zone load pattern. Optional 28d context only as support.",
            secondaryContextPolicy: "Secondary context: compact Recovery and Readiness facts only if they materially change the today recommendation.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough meaningful high-zone evidence to call a clear zone trend.", allowBridge: false),
            negativeConstraints: [
                "- Do not turn this into a generic strain versus recovery report.",
                "- Separate sports rather than blending unlike modalities.",
                "- Ignore weak or irrelevant high-zone contributors when the evidence says they are not meaningful drivers.",
                "- Do not describe rolling 7d Z4/Z5 totals as the selected day's Z4/Z5; keep labels and numbers distinct."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.atypicalSessionDetection, CoachPromptFragments.secondaryContextFacts, CoachPromptFragments.todayActionable],
            allowsSuggestions: true
        )
    case "1w-zones":
        return CoachPromptSpec(
            primaryScope: "Primary scope: weekly Time in Zone 4 and Time in Zone 5 totals, averages, standout days, and sport-separated high-zone patterns.",
            secondaryContextPolicy: "Secondary context: compact 28d non-zero cardio context only.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough meaningful high-zone evidence to call a clear zone trend.", allowBridge: false),
            negativeConstraints: [
                "- Do not turn this into a generic strain versus recovery report.",
                "- Separate sports rather than blending unlike modalities.",
                "- Ignore weak or irrelevant high-zone contributors when the evidence says they are not meaningful drivers.",
                "- Do not frame the week as today versus yesterday; describe dated trends across the selected window."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.atypicalSessionDetection, CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: false
        )
    case "1d-consistency":
        return CoachPromptSpec(
            primaryScope: "Primary scope: the past 7 days of training schedule, completed volume, average training time, and standout completed sessions, framed around what you actually completed.",
            secondaryContextPolicy: "Secondary context: compact Recovery and Readiness facts only for today's suggestion.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "Consistency analysis is unavailable because there is too little completed training in the past 7 days.", allowBridge: false),
            negativeConstraints: [
                "- Do not shame missed sessions.",
                "- Do not center the report on what was not done.",
                "- \"Scores [ANCHOR_DAY]\" is not a 7-day total; schedule and load lines are [7D] background—do not merge them into today's score line or call weekly volume \"today.\""
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.todayActionable, CoachPromptFragments.noShaming, CoachPromptFragments.holdSteadyNotReduce, CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    case "1w-svr":
        return CoachPromptSpec(
            primaryScope: "Primary scope: the 7-day Strain, Recovery, and Readiness series plus the derivative table. Only sustained patterns count as trends.",
            secondaryContextPolicy: "Secondary context: compact 28d baseline facts only.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough strain and recovery history in this week to call a reliable trend.", allowBridge: false),
            negativeConstraints: [
                "- Do not call one-off spikes a trend.",
                "- Do not drift into an advice-heavy daily recommendation.",
                "- Do not frame the narrative as today versus yesterday; anchor claims to dated series rows in the prompt."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    case "1w-sleep-bio":
        return CoachPromptSpec(
            primaryScope: "Primary scope: this week's sleep stages, sleep consistency, Sleep HR, vitals, and how those sleep-related patterns shaped weekly Recovery and Readiness.",
            secondaryContextPolicy: "Secondary context: compact load facts only when they explain the sleep-related trend.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "Sleep and biometrics trend analysis is limited for this week.", allowBridge: true),
            negativeConstraints: [
                "- Sleep-related evidence must remain primary.",
                "- Do not turn this into a workout summary.",
                "- Do not default to today versus yesterday; cite dated sleep and vitals rows from the prompt."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    case "1w-pb":
        return CoachPromptSpec(
            primaryScope: "Primary scope: weekly personal-best candidates from workout types with enough frequency signal, validated against 28d context.",
            secondaryContextPolicy: "Secondary context: compact 28d comparison facts only.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough repeated workout signal this week to call a meaningful personal best.", allowBridge: false),
            negativeConstraints: [
                "- Do not promote one-off low-frequency sessions as a meaningful best.",
                "- Keep praise grounded in the actual metrics.",
                "- Tie highlights to explicit workout dates from the prompt, not an undated today versus yesterday story."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    case "1w-consistency", "1m-consistency":
        return CoachPromptSpec(
            primaryScope: suggestion.id == "1w-consistency"
                ? "Primary scope: this week's schedule pattern, average volume, and the specific sports that show commitment."
                : "Primary scope: the past 28 days of schedule pattern, average volume, and the specific sports that show commitment.",
            secondaryContextPolicy: "Secondary context: none unless needed for one short bridge when the primary evidence is too thin.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "Consistency analysis is limited for this period.", allowBridge: true),
            negativeConstraints: [
                "- This report is statement of fact only.",
                "- No advice, no prescriptions, and no coaching next steps.",
                "- Do not frame the period as today versus yesterday; cite dated schedule lines from the prompt."
            ],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.statementOfFactOnly, CoachPromptFragments.noSuggestions, CoachPromptFragments.noShaming, CoachPromptFragments.bridgeToOtherData],
            allowsSuggestions: false
        )
    case "1m-overall":
        return CoachPromptSpec(
            primaryScope: "Primary scope: broad monthly state, trend summaries, and whether current metric levels look productive, steady, or limited.",
            secondaryContextPolicy: "Secondary context: compact standout facts only when they materially define the month.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough monthly signal to give a strong big-picture coaching read.", allowBridge: true),
            negativeConstraints: ["- Do not fake a granular day-by-day debrief.", "- Keep the report broad and trend-oriented."],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.bridgeToOtherData, CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    default:
        if suggestion.id.contains("sport-") {
            let sportLabel = suggestion.scopedSport ?? "this sport"
            let (timeHint, primaryLead): (String, String) = {
                if suggestion.id.hasPrefix("1m-sport-") {
                    return ("across the past 28 days", "Use \(sportLabel) evidence from the selected month to explain trends, durability, and what deserves emphasis next.")
                }
                if suggestion.id.hasPrefix("1w-sport-") {
                    return ("across the past 7 days", "Use \(sportLabel) evidence from the selected week to explain how the block is landing and what to emphasize next.")
                }
                if suggestion.id.hasPrefix("1d-sport-") {
                    return (
                        "for the selected calendar day only (Filter 1D)",
                        "Interpret **that day's** \(sportLabel) sessions and Training Focus metrics only—session quality, intensity bias versus easy volume, and how it fits recovery today. Do not narrate multi-day or weekly load unless you clearly separate it as optional context and the prompt supplies it."
                    )
                }
                return ("for the selected period", "Use \(sportLabel) evidence in the prompt to explain how training is landing and what matters next.")
            }()

            var negatives = [
                "- Do not recite the Training Focus evidence as your answer; interpret it.",
                "- Do not lead with or mirror labels such as Load profile, Data confidence, Quest summary, Metrics, or Trend lines unless you immediately explain what they imply for training.",
                "- Do not write about sleep or general wellness unless the fallback bridge is triggered.",
                "- Stay inside \(sportLabel) only."
            ]
            if suggestion.id.hasPrefix("1d-sport-") {
                negatives.append("- Forbidden: calling MET minutes, Time in Zone 4 or 5, or workload “the past seven days,” “weekly,” or “on average this week” when Filter is 1D and the Training Focus block is day-scoped.")
            }
            if suggestion.id.hasPrefix("1w-sport-") {
                negatives.append("- Forbidden: centering the narrative on today versus yesterday for a 1W sport report; describe week-level patterns with explicit session or series dates from the prompt.")
            }

            var fragments = baseFragments + [
                CoachPromptFragments.sportSecondPersonVoice,
                CoachPromptFragments.sportProseVariety,
                CoachPromptFragments.sportAnalysisContract,
                CoachPromptFragments.sportNoMetricInventory,
                CoachPromptFragments.sportInterpretLoadSignals,
                CoachPromptFragments.bridgeToOtherData,
                CoachPromptFragments.secondaryContextFacts,
                CoachPromptFragments.atypicalSessionDetection
            ]
            if suggestion.id.hasPrefix("1d-sport-") {
                fragments.append(CoachPromptFragments.sportOneDayWindowContract)
                fragments.append(CoachPromptFragments.todayActionable)
            }

            let sportSecondaryContext: String = {
                if suggestion.id.hasPrefix("1d-sport-") {
                    return "Secondary context: at most one compact Recovery, Readiness, or strain fact only if it clearly constrains or unlocks \(sportLabel) for the selected day; otherwise omit."
                }
                if suggestion.id.hasPrefix("1w-sport-") {
                    return "Secondary context: at most one compact Recovery, Readiness, or strain fact only if it clearly constrains how to read the \(sportLabel) week pattern; use dated facts from the prompt—omit yesterday-style framing unless those dates appear."
                }
                if suggestion.id.hasPrefix("1m-sport-") {
                    return "Secondary context: at most one compact Recovery, Readiness, or strain fact only if it clearly constrains how to read the \(sportLabel) month pattern; use dated facts from the prompt."
                }
                return "Secondary context: at most one compact Recovery, Readiness, or strain fact only if it clearly constrains \(sportLabel) training interpretation; otherwise omit."
            }()

            return CoachPromptSpec(
                primaryScope: "Primary scope: \(sportLabel) coaching \(timeHint). \(primaryLead)",
                secondaryContextPolicy: sportSecondaryContext,
                fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough \(sportLabel) signal in this period for a confident sport-specific coaching read.", allowBridge: true),
                negativeConstraints: negatives,
                uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
                requiredFragments: fragments,
                allowsSuggestions: true
            )
        }
        if suggestion.id == "1d-all-sports" {
            return CoachPromptSpec(
                primaryScope: "Primary scope: all-sport context from the past 7 days, but the answer must still be about what makes sense today.",
                secondaryContextPolicy: "Secondary context: compact Recovery, Readiness, and last-workout facts only.",
                fallbackPolicy: FallbackPolicy(unavailableLead: "There is not enough cross-sport activity in the past week to build an all-sports read.", allowBridge: false),
                negativeConstraints: [
                    "- Do not turn this into a weekly trend report.",
                    "- \"Scores [ANCHOR_DAY]\" is only the selected date; 7-day schedule and load lines are [7D]—never describe weekly volume as the anchor day's totals."
                ],
                uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
                requiredFragments: baseFragments + [CoachPromptFragments.todayActionable, CoachPromptFragments.secondaryContextFacts],
                allowsSuggestions: true
            )
        }
        return CoachPromptSpec(
            primaryScope: "Primary scope: answer the selected coaching question using only the most relevant evidence in the prompt.",
            secondaryContextPolicy: "Secondary context: compact facts only.",
            fallbackPolicy: FallbackPolicy(unavailableLead: "The selected report has limited signal in this period.", allowBridge: true),
            negativeConstraints: ["- Stay tight to the selected report."],
            uiTerminologyContract: CoachPromptFragments.useUIMetricNames,
            requiredFragments: baseFragments + [CoachPromptFragments.secondaryContextFacts],
            allowsSuggestions: true
        )
    }
}

private func dayScenario(
    timeFilter: StrainRecoveryView.TimeFilter,
    selectedDayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
) -> String {
    guard timeFilter == .day else {
        return "Multi-day coaching window. Focus on trend interpretation and balance across the selected period."
    }

    if selectedDayWorkouts.isEmpty {
        return "Pre-workout day. Focus on readiness and whether the last 30 days suggest pushing or deloading."
    }

    return "Post-workout day. Focus on the specific session, how hard it was relative to recent baseline, and what recovery should do next."
}

private func vitalsNormSummary(
    respiratoryData: [(Date, Double)],
    wristTempData: [(Date, Double)],
    spo2Data: [(Date, Double)]
) -> String {
    let respiratory = vitalLabel(for: respiratoryData, higherIsWorse: true)
    let wristTemp = vitalLabel(for: wristTempData, higherIsWorse: true)
    let spo2 = vitalLabel(for: spo2Data, higherIsWorse: false)
    return "Respiratory rate is \(respiratory), wrist temperature is \(wristTemp), and SpO2 is \(spo2)."
}

private func focusedEvidenceBlock(
    focusMode: AthleticCoachFocusMode,
    scopedSport: String?,
    displayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    workoutHighlights: WorkoutHighlights,
    selectedSnapshot: WorkoutSummarySnapshot?,
    sleepData: [(Date, Double)],
    averageSleepEfficiency: Double,
    hrvData: [(Date, Double)],
    rhrData: [(Date, Double)],
    sleepHRData: [(Date, Double)],
    vitalsSummary: String
) -> String {
    switch focusMode {
    case .toughestWorkout:
        return toughestWorkoutEvidence(from: displayWorkouts, selectedSnapshot: selectedSnapshot)
    case .latestWorkout:
        return latestWorkoutEvidence(from: displayWorkouts, selectedSnapshot: selectedSnapshot)
    case .recoveryVitalsSleep:
        let sleepAverage = average(sleepData.map(\.1)) ?? 0
        return """
        - Keep the spotlight on sleep and recovery biomarkers.
        - Sleep trend: \(sleepAverage > 0 ? "average sleep is present and should be described qualitatively" : "sleep data is limited")
        - Sleep efficiency: \(averageSleepEfficiency >= 90 ? "consistently above 90%" : averageSleepEfficiency > 0 ? "irregular or below ideal at times" : "limited")
        - HRV trend: \(trendSummary(for: hrvData, digits: 0))
        - Resting HR trend: \(trendSummary(for: rhrData, digits: 0))
        - Sleep HR trend: \(trendSummary(for: sleepHRData, digits: 0))
        - Vitals: \(vitalsSummary)
        - Mention training only as supporting context, not as a list.
        """
    case .trendBalance:
        return """
        - Focus on repeated patterns across the selected scope.
        - Explain whether strain is repeatedly outrunning recovery, recovery is leading, or both are moving in balance.
        - Use the selected scope to tell the trend story, not isolated metrics.
        - Load status: \(workoutLoadStatus(for: selectedSnapshot).detail)
        """
    case .sportDeepDive:
        return """
        - Treat this as \(scopedSport?.capitalized ?? "sport") coaching: synthesize patterns; do not read metrics back as a list.
        - Use only \(scopedSport ?? "sport") workouts as evidence.
        - Prioritize sport-native signals (power, cadence, HR zones, VO2, HRR, session-to-session shape) to infer adaptation, not to inventory numbers.
        - Do not mention other sports, all-sport frequency, or generic wellness framing.
        - Anchor points for interpretation (cite sparingly in the answer): longest \(workoutHighlights.longestWorkout), heaviest load \(workoutHighlights.highestLoadWorkout), best power \(workoutHighlights.highestPowerWorkout), peak HR highlight \(workoutHighlights.highestPeakHRWorkout).
        - Load context to interpret: \(workoutLoadStatus(for: selectedSnapshot).detail)
        """
    case .general:
        return """
        - Use broad context, but still narrow the report to the most meaningful themes.
        - Dominant sport: \(workoutHighlights.favoriteSport ?? workoutHighlights.mostFrequentSport ?? "Unavailable")
        - Load status: \(workoutLoadStatus(for: selectedSnapshot).detail)
        """
    }
}

private func toughestWorkoutEvidence(
    from displayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    selectedSnapshot: WorkoutSummarySnapshot?
) -> String {
    guard let toughest = displayWorkouts.max(by: {
        workoutSessionLoad(for: $0.workout, analytics: $0.analytics) < workoutSessionLoad(for: $1.workout, analytics: $1.analytics)
    }) else {
        return "- No workout is available, so do not fake a toughest-workout report."
    }

    let dateText = toughest.workout.startDate.formatted(date: .abbreviated, time: .omitted)
    let sport = toughest.workout.workoutActivityType.name.capitalized
    let load = workoutSessionLoad(for: toughest.workout, analytics: toughest.analytics)
    let duration = toughest.workout.duration / 60.0
    let zone4 = zoneMinutes(for: toughest.analytics, zoneNumber: 4)
    let zone5 = zoneMinutes(for: toughest.analytics, zoneNumber: 5)
    let power = coachSessionAvgPowerWatts(toughest.analytics)
    let cadence = coachSessionAvgCadenceRpm(toughest.analytics)

    return """
    - Toughest workout date: \(dateText)
    - Toughest workout sport: \(sport)
    - Session load: \(formatted(load, digits: 0)) pts
    - Duration: \(formatted(duration, digits: 0)) min
    - Zone 4 time: \(formatted(zone4, digits: 0)) min
    - Zone 5 time: \(formatted(zone5, digits: 0)) min
    - Average power: \(power.map { formatted($0, digits: 0) + " W" } ?? "Unavailable (no power samples in Health data for this session)")
    - Average cadence: \(cadence.map { formatted($0, digits: 0) + " rpm" } ?? "Unavailable (no cadence samples in Health data for this session)")
    - Peak HR: \(toughest.analytics.peakHR.map { formatted($0, digits: 0) + " bpm" } ?? "Unavailable")
    - \(coachHRRPromptSnippet(workout: toughest.workout, analytics: toughest.analytics)) (larger drop = faster recovery)
    - Only mention broader strain if you connect it directly back to this workout's impact.
    - Current load context: \(workoutLoadStatus(for: selectedSnapshot).detail)
    """
}

private func latestWorkoutEvidence(
    from displayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    selectedSnapshot: WorkoutSummarySnapshot?
) -> String {
    guard let latest = displayWorkouts.max(by: { $0.workout.startDate < $1.workout.startDate }) else {
        return "- No latest workout is available."
    }

    let dateText = latest.workout.startDate.formatted(date: .abbreviated, time: .omitted)
    let sport = latest.workout.workoutActivityType.name.capitalized
    let load = workoutSessionLoad(for: latest.workout, analytics: latest.analytics)
    return """
    - Latest workout date: \(dateText)
    - Latest workout sport: \(sport)
    - Session load: \(formatted(load, digits: 0)) pts
    - Peak HR: \(latest.analytics.peakHR.map { formatted($0, digits: 0) + " bpm" } ?? "Unavailable")
    - \(coachHRRPromptSnippet(workout: latest.workout, analytics: latest.analytics)) (larger drop = faster recovery)
    - Explain what changed versus the recent baseline.
    - Current load context: \(workoutLoadStatus(for: selectedSnapshot).detail)
    """
}

private func vitalLabel(for series: [(Date, Double)], higherIsWorse: Bool) -> String {
    guard let latest = series.last?.1,
          let avg = average(series.map(\.1)),
          avg != 0 else {
        return "Baseline"
    }

    let deltaRatio = (latest - avg) / abs(avg)
    if abs(deltaRatio) < 0.03 {
        return "Stable"
    }

    if higherIsWorse {
        return deltaRatio > 0 ? "High" : "Baseline"
    }

    return deltaRatio < -0.02 ? "Low" : "Stable"
}

private struct WorkoutSummarySnapshot {
    let date: Date
    let sessionLoad: Double
    let totalDailyLoad: Double
    let acuteLoad: Double
    let chronicLoad: Double
    let acwr: Double
    let strainScore: Double
    let workoutCount: Int
    let activeDaysLast28: Int
    let daysSinceLastWorkout: Int?
}

private struct WorkoutHighlights {
    let totalMinutes: Double
    let sessionsPerWeek: Double
    let mostFrequentSport: String?
    let favoriteSport: String?
    let longestWorkout: String
    let highestLoadWorkout: String
    let highestPowerWorkout: String
    let highestPeakHRWorkout: String
    let totalZone4Minutes: Double
    let totalZone5Minutes: Double
    let maxZone4Workout: String
    let maxZone5Workout: String
}

private func filteredWindowSeries(
    values: [Date: Double],
    in window: (start: Date, end: Date, endExclusive: Date)
) -> [(Date, Double)] {
    values
        .filter { date, value in
            date >= window.start && date <= window.end && value > 0
        }
        .sorted { $0.0 < $1.0 }
}

private func workoutSessionLoad(for workout: HKWorkout, analytics: WorkoutAnalytics) -> Double {
    HealthStateEngine.proWorkoutLoad(
        for: workout,
        analytics: analytics,
        estimatedMaxHeartRate: HealthStateEngine.estimateMaxHeartRateNes(age: nil)
    )
}

@MainActor
private func recoveryScore(
    for day: Date,
    engine: HealthStateEngine
) -> Double? {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
    let inputs = HealthStateEngine.proRecoveryInputs(
        latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.effectHRV) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: hrvLookup),
        restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate),
        sleepDurationHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
        timeInBedHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
        hrvBaseline60Day: engine.hrvBaseline60Day,
        rhrBaseline60Day: engine.rhrBaseline60Day,
        sleepBaseline60Day: engine.sleepBaseline60Day,
        hrvBaseline7Day: engine.hrvBaseline7Day,
        rhrBaseline7Day: engine.rhrBaseline7Day,
        sleepBaseline7Day: engine.sleepBaseline7Day,
        bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: normalizedDay)
    )

    guard !inputs.isInconclusive else { return nil }
    guard inputs.hrvZScore != nil || inputs.restingHeartRateZScore != nil || inputs.sleepRatio != nil else {
        return nil
    }
    return HealthStateEngine.proRecoveryScore(from: inputs)
}

private struct RecoveryClassification {
    let title: String
    let detail: String
    let color: Color
}

private func recoveryClassification(for score: Double) -> RecoveryClassification {
    switch score {
    case 90...100:
        return RecoveryClassification(title: "Full Send", detail: "Strong state for ambitious work if it matches your goal.", color: .green)
    case 70..<90:
        return RecoveryClassification(title: "Perform", detail: "Solid state for quality work and good momentum.", color: .green)
    case 40..<70:
        return RecoveryClassification(title: "Adapt", detail: "A bit less ready than ideal, so aim for sharp execution and controlled intent.", color: .orange)
    default:
        return RecoveryClassification(title: "Recover", detail: "Recovery reserve looks limited, so keep the focus on rebuilding support for the next push.", color: .red)
    }
}

private struct StrainClassification {
    let title: String
    let detail: String
    let color: Color
}

private struct StrainConsistencyClassification {
    let title: String
    let detail: String
    let color: Color
}

private func strainClassification(for score: Double) -> StrainClassification {
    switch score {
    case ..<6:
        return StrainClassification(title: "Low", detail: "Light load day with minimal accumulated strain.", color: .blue)
    case ..<11:
        return StrainClassification(title: "Building", detail: "Moderate load that adds work without heavy fatigue cost.", color: .green)
    case ..<15:
        return StrainClassification(title: "Productive", detail: "Solid training stress with meaningful adaptation potential.", color: .orange)
    default:
        return StrainClassification(title: "High", detail: "Heavy load day that needs strong recovery support.", color: .red)
    }
}

private func strainScoreStandardDeviation(_ values: [Double]) -> Double {
    guard values.count > 1 else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values
        .map { pow($0 - mean, 2) }
        .reduce(0, +) / Double(values.count)
    return sqrt(variance)
}

private func strainConsistencyClassification(for scores: [Double]) -> StrainConsistencyClassification {
    let deviation = strainScoreStandardDeviation(scores)
    switch deviation {
    case ..<1.75:
        return StrainConsistencyClassification(
            title: "Consistent",
            detail: "Strain stayed tightly clustered across this period with only small day-to-day swings.",
            color: .green
        )
    case ..<3.5:
        return StrainConsistencyClassification(
            title: "Fairly Consistent",
            detail: "Strain had some meaningful variation, but the overall load pattern still stayed reasonably steady.",
            color: .yellow
        )
    default:
        return StrainConsistencyClassification(
            title: "Inconsistent",
            detail: "Strain swung sharply across the period, suggesting a more uneven load pattern.",
            color: .red
        )
    }
}

@MainActor
private func readinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    engine: HealthStateEngine
) -> Double? {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
    let hrvValue = hrvLookup[normalizedDay]
    let hrvTrendComponent: Double
    if let hrvValue, let baseline = engine.hrvBaseline7Day, baseline > 0 {
        let deviation = (hrvValue - baseline) / baseline
        hrvTrendComponent = max(0, min(100, (deviation * 200) + 50))
    } else {
        hrvTrendComponent = engine.hrvTrendScore
    }

    return HealthStateEngine.proReadinessScore(
        recoveryScore: recoveryScore,
        strainScore: strainScore,
        hrvTrendComponent: hrvTrendComponent
    )
}

private func dailyLoadSnapshots(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    estimatedMaxHeartRate: Double,
    displayWindow: (start: Date, end: Date, endExclusive: Date)
) -> [WorkoutSummarySnapshot] {
    let calendar = Calendar.current
    var sessionLoadByDay: [Date: Double] = [:]
    var workoutCountByDay: [Date: Int] = [:]
    let loadWindowStart = calendar.date(byAdding: .day, value: -27, to: displayWindow.start) ?? displayWindow.start

    for (workout, analytics) in workouts {
        let day = calendar.startOfDay(for: workout.startDate)
        let load = HealthStateEngine.proWorkoutLoad(
            for: workout,
            analytics: analytics,
            estimatedMaxHeartRate: estimatedMaxHeartRate
        )
        sessionLoadByDay[day, default: 0] += load
        workoutCountByDay[day, default: 0] += 1
    }

    let loadDates = dateSequence(from: loadWindowStart, to: displayWindow.end)
    let orderedLoads = loadDates.map { day in
        let sessionLoad = sessionLoadByDay[day, default: 0]
        let activeMinutes = workouts
            .filter { calendar.isDate($0.workout.startDate, inSameDayAs: day) }
            .reduce(0.0) { $0 + ($1.workout.duration / 60.0) }
        return sessionLoad + HealthStateEngine.passiveDailyBaseLoad(activeMinutes: activeMinutes)
    }

    return dateSequence(from: displayWindow.start, to: displayWindow.end).map { day in
        let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
            let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
            return partial + ((sessionLoadByDay[sourceDay] ?? 0) > 0 ? 1 : 0)
        }
        let daysSinceLastWorkout = (0..<28).first(where: { offset in
            let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
            return (sessionLoadByDay[sourceDay] ?? 0) > 0
        })
        let stateIndex = loadDates.firstIndex(of: day) ?? (orderedLoads.indices.last ?? 0)
        let state = HealthStateEngine.proTrainingLoadState(loads: orderedLoads, index: stateIndex)

        return WorkoutSummarySnapshot(
            date: day,
            sessionLoad: sessionLoadByDay[day] ?? 0,
            totalDailyLoad: orderedLoads[stateIndex],
            acuteLoad: state.acuteLoad,
            chronicLoad: state.chronicLoad,
            acwr: state.acwr,
            strainScore: HealthStateEngine.proStrainScore(
                acuteLoad: state.acuteLoad,
                chronicLoad: state.chronicLoad
            ),
            workoutCount: workoutCountByDay[day] ?? 0,
            activeDaysLast28: activeDaysLast28,
            daysSinceLastWorkout: daysSinceLastWorkout
        )
    }
}

private func workoutLoadStatus(for snapshot: WorkoutSummarySnapshot?) -> WorkoutLoadStatus {
    guard let snapshot else {
        return WorkoutLoadStatus(
            title: "No Baseline",
            color: .gray,
            detail: "No recent training load found. The model needs fresh workouts to establish readiness.",
            hidesRatio: true
        )
    }

    if snapshot.activeDaysLast28 < 14 {
        return WorkoutLoadStatus(
            title: "Baseline Outdated",
            color: .orange,
            detail: "Baseline out of date. 14 active days in the last 28 are recommended to recalculate your fitness floor.",
            hidesRatio: true
        )
    }

    if let daysSinceLastWorkout = snapshot.daysSinceLastWorkout {
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

    switch snapshot.acwr {
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

private func workoutHighlights(
    displayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    dayCount: Int
) -> WorkoutHighlights {
    let totalMinutes = displayWorkouts.reduce(0.0) { $0 + ($1.workout.duration / 60.0) }
    let sessionsPerWeek = dayCount > 0 ? (Double(displayWorkouts.count) / Double(dayCount)) * 7.0 : 0

    let sportCount = Dictionary(grouping: displayWorkouts, by: { $0.workout.workoutActivityType.name })
        .mapValues(\.count)
    let sportMinutes = Dictionary(grouping: displayWorkouts, by: { $0.workout.workoutActivityType.name })
        .mapValues { items in
            items.reduce(0.0) { $0 + ($1.workout.duration / 60.0) }
        }

    let longestWorkout = displayWorkouts.max { lhs, rhs in
        lhs.workout.duration < rhs.workout.duration
    }.map { pair in
        "\(pair.workout.workoutActivityType.name.capitalized) for \(formatted(pair.workout.duration / 60.0, digits: 0)) min on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
    } ?? "Unavailable"

    let highestLoadWorkout = displayWorkouts.max { lhs, rhs in
        workoutSessionLoad(for: lhs.workout, analytics: lhs.analytics) < workoutSessionLoad(for: rhs.workout, analytics: rhs.analytics)
    }.map { pair in
        "\(pair.workout.workoutActivityType.name.capitalized) at \(formatted(workoutSessionLoad(for: pair.workout, analytics: pair.analytics), digits: 0)) load points on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
    } ?? "Unavailable"

    let highestPowerWorkout = displayWorkouts.compactMap { pair -> (String, Double)? in
        guard let avgPower = coachSessionAvgPowerWatts(pair.analytics) else { return nil }
        let description = "\(pair.workout.workoutActivityType.name.capitalized) at \(formatted(avgPower, digits: 0)) W average on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, avgPower)
    }.max { $0.1 < $1.1 }?.0 ?? "Unavailable (no power samples in window)"

    let highestPeakHRWorkout = displayWorkouts.compactMap { pair -> (String, Double)? in
        guard let peakHR = pair.analytics.peakHR else { return nil }
        let description = "\(pair.workout.workoutActivityType.name.capitalized) peaked at \(formatted(peakHR, digits: 0)) bpm on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, peakHR)
    }.max { $0.1 < $1.1 }?.0 ?? "Unavailable"

    let zone4Entries = displayWorkouts.compactMap { pair -> (String, Double)? in
        let workoutMinutes = zoneMinutes(for: pair.analytics, zoneNumber: 4)
        guard workoutMinutes > 0 else { return nil }
        let description = "\(pair.workout.workoutActivityType.name.capitalized) with \(formatted(workoutMinutes, digits: 0)) min in Zone 4 on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, workoutMinutes)
    }

    let zone5Entries = displayWorkouts.compactMap { pair -> (String, Double)? in
        let workoutMinutes = zoneMinutes(for: pair.analytics, zoneNumber: 5)
        guard workoutMinutes > 0 else { return nil }
        let description = "\(pair.workout.workoutActivityType.name.capitalized) with \(formatted(workoutMinutes, digits: 0)) min in Zone 5 on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, workoutMinutes)
    }

    let totalZone4Minutes = zone4Entries.reduce(0.0) { $0 + $1.1 }
    let totalZone5Minutes = zone5Entries.reduce(0.0) { $0 + $1.1 }

    return WorkoutHighlights(
        totalMinutes: totalMinutes,
        sessionsPerWeek: sessionsPerWeek,
        mostFrequentSport: sportCount.max(by: { $0.value < $1.value })?.key,
        favoriteSport: sportMinutes.max(by: { $0.value < $1.value })?.key,
        longestWorkout: longestWorkout,
        highestLoadWorkout: highestLoadWorkout,
        highestPowerWorkout: highestPowerWorkout,
        highestPeakHRWorkout: highestPeakHRWorkout,
        totalZone4Minutes: totalZone4Minutes,
        totalZone5Minutes: totalZone5Minutes,
        maxZone4Workout: zone4Entries.max(by: { $0.1 < $1.1 })?.0 ?? "Unavailable",
        maxZone5Workout: zone5Entries.max(by: { $0.1 < $1.1 })?.0 ?? "Unavailable"
    )
}

private func sleepConsistencyScore(midpointSeries: [(Date, Double)], fallback: Double) -> Double {
    let midpointDeviationHours = (standardDeviation(midpointSeries.map(\.1)) ?? fallback)
    let best = 0.25
    let worst = 3.0
    let clamped = min(max(midpointDeviationHours, best), worst)
    return ((worst - clamped) / (worst - best)) * 100
}

private func sleepMidpointDeviationMinutes(midpointSeries: [(Date, Double)], fallback: Double) -> Double {
    (standardDeviation(midpointSeries.map(\.1)) ?? fallback) * 60
}

@MainActor
private func averageSleepEfficiency(engine: HealthStateEngine, midpointSeries: [(Date, Double)]) -> Double {
    let values = midpointSeries.compactMap { day, _ -> Double? in
        guard let stages = engine.sleepStages[day] else { return nil }
        let asleep = ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        let awake = stages["awake"] ?? 0
        let denominator = asleep + awake
        guard denominator > 0 else { return nil }
        return asleep / denominator
    }
    return (average(values) ?? 0) * 100
}

private func sleepDebt(sleepData: [(Date, Double)]) -> Double {
    let series = sleepData.filter { $0.1 > 0 }.sorted { $0.0 < $1.0 }
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

@MainActor
private func activityRecoverySleepGap(
    engine: HealthStateEngine,
    midpointSeries: [(Date, Double)]
) -> Double {
    let calendar = Calendar.current
    let sleepHoursByDay = midpointSeries.compactMap { day, _ -> (Date, Double)? in
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

    return recoveryAverage - activityAverage
}

private func formatted(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
}

private func signedFormatted(_ value: Double, digits: Int) -> String {
    String(format: "%+.\(digits)f", value)
}

private func bestDayDescription(
    for series: [(Date, Double)],
    unit: String,
    digits: Int
) -> String {
    guard let best = series.max(by: { $0.1 < $1.1 }) else { return "Unavailable" }
    return "\(formatted(best.1, digits: digits)) \(unit) on \(best.0.formatted(date: .abbreviated, time: .omitted))"
}

private func seriesSummary(
    _ series: [(Date, Double)],
    unit: String,
    digits: Int
) -> String {
    guard !series.isEmpty else { return "Unavailable" }
    let latest = series.last?.1 ?? 0
    let avg = average(series.map(\.1)) ?? 0
    return "latest \(formatted(latest, digits: digits)) \(unit), average \(formatted(avg, digits: digits)) \(unit), trend \(trendSummary(for: series, digits: digits))"
}

private struct CoachWindowSegment {
    let start: Date
    let end: Date
}

private func segmentedCoachWindows(
    for timeFilter: StrainRecoveryView.TimeFilter,
    reportPeriod: SummaryReportPeriod
) -> [CoachWindowSegment] {
    let calendar = Calendar.current

    switch timeFilter {
    case .day:
        return [CoachWindowSegment(start: reportPeriod.start, end: reportPeriod.end)]
    case .week:
        let totalDays = max(1, (calendar.dateComponents([.day], from: reportPeriod.start, to: reportPeriod.end).day ?? 0) + 1)
        let segmentLengths: [Int]
        if totalDays >= 7 {
            segmentLengths = [2, 2, totalDays - 4]
        } else if totalDays >= 5 {
            segmentLengths = [2, totalDays - 2]
        } else {
            segmentLengths = [totalDays]
        }

        var segments: [CoachWindowSegment] = []
        var cursor = reportPeriod.start
        for length in segmentLengths where length > 0 {
            let rawEnd = calendar.date(byAdding: .day, value: length - 1, to: cursor) ?? cursor
            let clampedEnd = min(rawEnd, reportPeriod.end)
            segments.append(CoachWindowSegment(start: cursor, end: clampedEnd))
            guard let next = calendar.date(byAdding: .day, value: 1, to: clampedEnd),
                  next <= reportPeriod.end else {
                break
            }
            cursor = next
        }
        return segments
    case .month:
        var segments: [CoachWindowSegment] = []
        var cursor = reportPeriod.start
        while cursor <= reportPeriod.end {
            let interval = calendar.dateInterval(of: .weekOfYear, for: cursor)
            let rawStart = interval.map { calendar.startOfDay(for: $0.start) } ?? cursor
            let rawEndExclusive = interval?.end ?? (calendar.date(byAdding: .day, value: 7, to: rawStart) ?? cursor)
            let rawEnd = calendar.date(byAdding: .day, value: -1, to: rawEndExclusive) ?? cursor
            let start = max(rawStart, reportPeriod.start)
            let end = min(calendar.startOfDay(for: rawEnd), reportPeriod.end)
            if segments.last?.end != end || segments.last?.start != start {
                segments.append(CoachWindowSegment(start: start, end: end))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: end),
                  next <= reportPeriod.end else {
                break
            }
            cursor = next
        }
        return segments
    }
}

private func describeMetricExtreme(
    label: String,
    series: [(Date, Double)],
    prefersMinimum: Bool,
    digits: Int,
    scaleSuffix: String
) -> String {
    guard !series.isEmpty else { return "\(label): unavailable" }
    let point = prefersMinimum
        ? series.min(by: { $0.1 < $1.1 })
        : series.max(by: { $0.1 < $1.1 })

    guard let point else { return "\(label): unavailable" }
    return "\(label): \(formatted(point.1, digits: digits))\(scaleSuffix) on \(point.0.formatted(date: .abbreviated, time: .omitted))"
}

@MainActor
private func periodScoreContext(
    timeFilter: StrainRecoveryView.TimeFilter,
    reportPeriod: SummaryReportPeriod,
    loadSnapshots: [WorkoutSummarySnapshot],
    engine: HealthStateEngine,
    displayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    anchorStrain: Double,
    anchorRecovery: Double,
    anchorReadiness: Double,
    internalEffortRatingSum: Double
) -> (promptBlock: String, fallbackLead: String) {
    let calendar = Calendar.current
    let windowTrainingLoadPoints = loadSnapshots
        .filter { $0.date >= reportPeriod.start && $0.date <= reportPeriod.end }
        .map(\.totalDailyLoad)
        .reduce(0, +)
    let strainSeries = loadSnapshots.map { ($0.date, $0.strainScore) }
    let recoverySeries = dateSequence(from: reportPeriod.start, to: reportPeriod.end).compactMap { day -> (Date, Double)? in
        recoveryScore(for: day, engine: engine).map { (day, $0) }
    }
    let readinessSeries = dateSequence(from: reportPeriod.start, to: reportPeriod.end).compactMap { day -> (Date, Double)? in
        guard let strain = strainSeries.first(where: { calendar.isDate($0.0, inSameDayAs: day) })?.1,
              let recovery = recoveryScore(for: day, engine: engine),
              let readiness = readinessScore(for: day, recoveryScore: recovery, strainScore: strain, engine: engine) else {
            return nil
        }
        return (day, readiness)
    }

    let averageStrain = average(strainSeries.map(\.1)) ?? anchorStrain
    let averageRecovery = average(recoverySeries.map(\.1)) ?? anchorRecovery
    let averageReadiness = average(readinessSeries.map(\.1)) ?? anchorReadiness
    let trainingDays = loadSnapshots.filter { $0.workoutCount > 0 }.count
    let workoutCount = displayWorkouts.count

    let segmentLines = segmentedCoachWindows(for: timeFilter, reportPeriod: reportPeriod).compactMap { segment -> String? in
        let segmentStrain = strainSeries.filter { $0.0 >= segment.start && $0.0 <= segment.end }.map(\.1)
        let segmentRecovery = recoverySeries.filter { $0.0 >= segment.start && $0.0 <= segment.end }.map(\.1)
        let segmentReadiness = readinessSeries.filter { $0.0 >= segment.start && $0.0 <= segment.end }.map(\.1)
        let segmentSnapshots = loadSnapshots.filter { $0.date >= segment.start && $0.date <= segment.end }
        let segmentWorkoutCount = segmentSnapshots.reduce(0) { $0 + $1.workoutCount }
        let segmentTotalLoad = segmentSnapshots.map(\.totalDailyLoad).reduce(0, +)

        guard !segmentStrain.isEmpty || !segmentRecovery.isEmpty || !segmentReadiness.isEmpty else {
            return nil
        }

        let label = segment.start == segment.end
            ? segment.start.formatted(date: .abbreviated, time: .omitted)
            : "\(segment.start.formatted(date: .abbreviated, time: .omitted)) to \(segment.end.formatted(date: .abbreviated, time: .omitted))"

        return "- \(label): avg strain \(formatted(average(segmentStrain) ?? 0, digits: 1))/21, avg recovery \(formatted(average(segmentRecovery) ?? 0, digits: 0))/100, avg readiness \(formatted(average(segmentReadiness) ?? 0, digits: 0))/100, workouts \(segmentWorkoutCount), total load \(formatted(segmentTotalLoad, digits: 1))"
    }

    let fullRangeLabel = timeFilter == .day
        ? reportPeriod.start.formatted(date: .abbreviated, time: .omitted)
        : "\(reportPeriod.start.formatted(date: .abbreviated, time: .omitted)) to \(reportPeriod.end.formatted(date: .abbreviated, time: .omitted))"

    let promptBlock: String
    let fallbackLead: String

    let effortLine: String = internalEffortRatingSum > 0.05
        ? "\n        - Internal effort-rating sum (separate internal scale, not training load points): \(formatted(internalEffortRatingSum, digits: 1))"
        : ""

    switch timeFilter {
    case .day:
        promptBlock = """
        - Selected day strain score: \(formatted(anchorStrain, digits: 0))/21
        - Recovery score for the selected day: \(formatted(anchorRecovery, digits: 0))/100
        - Readiness score for the selected day: \(formatted(anchorReadiness, digits: 0))/100
        - Window total training load points (sum of daily training load for the report window, same scale as [7D] Recent training load; not a 0–100 score): \(formatted(windowTrainingLoadPoints, digits: 1))\(effortLine)
        """
        fallbackLead = "Your current strain is \(formatted(anchorStrain, digits: 0))/21, recovery is \(formatted(anchorRecovery, digits: 0))/100, and readiness is \(formatted(anchorReadiness, digits: 0))/100."
    case .week, .month:
        promptBlock = """
        - Full \(timeFilter.summaryPeriodTitle) score range: \(fullRangeLabel)
        - Average strain across the full \(timeFilter.summaryPeriodTitle): \(formatted(averageStrain, digits: 1))/21
        - Average recovery across the full \(timeFilter.summaryPeriodTitle): \(formatted(averageRecovery, digits: 0))/100
        - Average readiness across the full \(timeFilter.summaryPeriodTitle): \(formatted(averageReadiness, digits: 0))/100
        - Total workouts in the full \(timeFilter.summaryPeriodTitle): \(workoutCount)
        - Training days in the full \(timeFilter.summaryPeriodTitle): \(trainingDays)
        - Window total training load points (sum of daily training load across the report window, same scale as training load series; not a 0–100 score): \(formatted(windowTrainingLoadPoints, digits: 1))\(effortLine)
        - End-of-period daily check-in on \(reportPeriod.end.formatted(date: .abbreviated, time: .omitted)): strain \(formatted(anchorStrain, digits: 0))/21, recovery \(formatted(anchorRecovery, digits: 0))/100, readiness \(formatted(anchorReadiness, digits: 0))/100
        - Internal \(timeFilter.summaryPeriodTitle) shape:
        \(segmentLines.isEmpty ? "- No subrange score breakdown is available." : segmentLines.joined(separator: "\n"))
        - \(describeMetricExtreme(label: "Highest strain day", series: strainSeries, prefersMinimum: false, digits: 0, scaleSuffix: "/21"))
        - \(describeMetricExtreme(label: "Lowest recovery day", series: recoverySeries, prefersMinimum: true, digits: 0, scaleSuffix: "/100"))
        - \(describeMetricExtreme(label: "Lowest readiness day", series: readinessSeries, prefersMinimum: true, digits: 0, scaleSuffix: "/100"))
        """
        fallbackLead = "Across \(fullRangeLabel), strain averaged \(formatted(averageStrain, digits: 1))/21, recovery averaged \(formatted(averageRecovery, digits: 0))/100, and readiness averaged \(formatted(averageReadiness, digits: 0))/100. The shape of the period matters more than the average alone, so the key question is where the load built, where recovery sagged, and which dates drove that change."
    }

    return (promptBlock, fallbackLead)
}

private func trendSummary(
    for series: [(Date, Double)],
    digits: Int
) -> String {
    guard series.count >= 4 else { return "insufficient data" }

    let values = series.map(\.1)
    let splitIndex = values.count / 2
    let earlier = Array(values.prefix(splitIndex))
    let recent = Array(values.suffix(values.count - splitIndex))
    guard let earlierAverage = average(earlier),
          let recentAverage = average(recent) else {
        return "insufficient data"
    }

    let delta = recentAverage - earlierAverage
    let threshold = max(abs(earlierAverage) * 0.03, 0.5)
    if abs(delta) < threshold {
        return "stable (\(signedFormatted(delta, digits: digits)))"
    }
    return delta > 0
        ? "rising (\(signedFormatted(delta, digits: digits)))"
        : "falling (\(signedFormatted(delta, digits: digits)))"
}

// MARK: - Precomputed Coach Metric Payload

private struct CoachMetricPayload {
    let timeFilter: StrainRecoveryView.TimeFilter
    let suggestionID: String
    let dateLabel: String
    let periodLabel: String

    var strainScore: Double?
    var strainWeekAvg: Double?
    var strainConsistencyLabel: String?

    var trainingLoadSeries: [(date: String, load: Double, acwr: Double?, label: String?)] = []
    var metToday: Double?
    var metWeekAvg: Double?
    var trainingSchedule: String?

    var recoveryScore: Double?
    var readinessScore: Double?
    var recoveryLabel: String?
    var recoverySeries: [(date: String, score: Double)] = []
    var readinessSeries: [(date: String, score: Double)] = []
    /// Explicit yesterday line for 1D prompts so the model does not mine [7D] series for "yesterday."
    var priorDayScoresLine: String?

    var hrvSeries: [(date: String, value: Double)] = []
    var rhrSeries: [(date: String, value: Double)] = []
    var hrrSeries: [(date: String, value: Double)] = []
    var sleepHeartRateSeries: [(date: String, value: Double)] = []
    var sleepSeries: [(date: String, hours: Double, core: Double, deep: Double, rem: Double)] = []

    var vitalsStatus: String = ""

    var efficiencyRatios: [(date: String, ratio: Double, label: String)] = []

    var scoreDerivatives: [(date: String, strain: Double, recovery: Double, readiness: Double, strainDelta: Double, recoveryDelta: Double, readinessDelta: Double)] = []

    var workoutSummary: String = ""
    var zoneDataBySport: [(sport: String, z4min: Double, z5min: Double, totalMin: Double, avgHR: Double?)] = []
    var zoneSessionEntries: [(sport: String, date: String, z4min: Double, z5min: Double, durationMin: Double, avgHR: Double?)] = []
    /// 1D Zone focus only: qualifying high-zone sessions on the anchor (selected) day.
    var zoneTodaySessions: [(sport: String, date: String, z4min: Double, z5min: Double, durationMin: Double, avgHR: Double?)] = []
    /// 1D Zone focus only: same window as 7d aggregate but excluding anchor day.
    var zonePriorWindowSessions: [(sport: String, date: String, z4min: Double, z5min: Double, durationMin: Double, avgHR: Double?)] = []
    var zoneConfidenceNotes: [String] = []
    var questSummary: String = ""
    var personalBests: String = ""
    var sportFilter: String?
    var trainingFocusReport: TrainingFocusReportPayload?
    var secondaryContext = CoachSecondaryContext()
    var fallbackBridge: String?
    var monthlyAggregateLines: [String] = []
}

private struct CoachSecondaryContext {
    var facts: [(String, String)] = []

    var isEmpty: Bool { facts.isEmpty }

    func renderedLine() -> String? {
        guard !facts.isEmpty else { return nil }
        let compact = facts.map { "\($0.0): \($0.1)" }.joined(separator: " | ")
        return "Secondary context: \(compact)"
    }
}

private struct TrainingFocusMetric: Identifiable {
    let id: String
    let label: String
    let value: String
}

private struct TrainingFocusSessionDigest: Identifiable {
    let id: String
    let date: String
    let summary: String
}

/// Dated metric rows aligned with sport coach evidence (same workout window as Training Focus).
private struct TrainingFocusCoachValidationRow: Identifiable {
    let id: String
    let dateLabel: String
    let dataType: String
    let value: String
}

private struct TrainingFocusReportPayload {
    let sportLabel: String
    let physiologicalLoadProfile: String
    let dataConfidence: String
    let manualOverride: Bool
    let periodLabel: String
    let questSummary: String
    let metrics: [TrainingFocusMetric]
    let trendLines: [String]
    let standoutSessions: [TrainingFocusSessionDigest]
    /// MET from same activity type in the 7 calendar days immediately before the report window (for relative load, not a score scale).
    let sameSportMetBaselineLine: String?
    /// Per-session dated facts for validating coach trend claims (chronological within the report window).
    let coachValidationRows: [TrainingFocusCoachValidationRow]
}

private func computeEfficiencyRatio(
    strainSeries: [(Date, Double)],
    recoverySeries: [(Date, Double)],
    readinessSeries: [(Date, Double)]
) -> [(date: String, ratio: Double, label: String)] {
    let calendar = Calendar.current
    let recoveryByDay = Dictionary(uniqueKeysWithValues: recoverySeries.map { (calendar.startOfDay(for: $0.0), $0.1) })
    let readinessByDay = Dictionary(uniqueKeysWithValues: readinessSeries.map { (calendar.startOfDay(for: $0.0), $0.1) })

    return strainSeries.compactMap { date, strain -> (date: String, ratio: Double, label: String)? in
        let day = calendar.startOfDay(for: date)
        guard let recovery = recoveryByDay[day], let readiness = readinessByDay[day] else { return nil }
        let strainNorm = max(strain, 0.001) / 21.0
        let restorationNorm = (recovery + readiness) / 200.0
        let ratio = restorationNorm / strainNorm
        let label: String
        switch ratio {
        case ..<0.8: label = "overreaching"
        case 0.8..<0.9: label = "slightly overreaching"
        case 0.9...1.1: label = "in sync"
        case 1.1..<1.2: label = "slightly under-loaded"
        default: label = "capacity available"
        }
        return (date: day.formatted(date: .abbreviated, time: .omitted), ratio: (ratio * 100).rounded() / 100, label: label)
    }
}

private func vitalsStatusLabel(
    dayValue: Double?,
    avg28d: Double?,
    higherIsWorse: Bool
) -> String {
    guard let day = dayValue, let avg = avg28d, avg != 0 else { return "no data" }
    let deviation = (day - avg) / abs(avg)
    if abs(deviation) < 0.05 { return "ok" }
    if higherIsWorse {
        return deviation > 0.05 ? "elevated" : "ok"
    }
    return deviation < -0.05 ? "low" : "ok"
}

@MainActor
private func computeVitalsStatus(
    engine: HealthStateEngine,
    selectedDay: Date,
    window28dStart: Date
) -> String {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: selectedDay)

    func dayVal(_ dict: [Date: Double]) -> Double? { dict[day] }
    func avg28(_ dict: [Date: Double]) -> Double? {
        let vals = dict.filter { $0.key >= window28dStart && $0.key < day }.map(\.value)
        return average(vals)
    }

    let respStatus = vitalsStatusLabel(dayValue: dayVal(engine.respiratoryRate), avg28d: avg28(engine.respiratoryRate), higherIsWorse: true)
    let wristTempStatus = vitalsStatusLabel(dayValue: dayVal(engine.wristTemperature), avg28d: avg28(engine.wristTemperature), higherIsWorse: true)
    let spo2Status = vitalsStatusLabel(dayValue: dayVal(engine.spO2), avg28d: avg28(engine.spO2), higherIsWorse: false)
    let sleepHRStatus = vitalsStatusLabel(dayValue: dayVal(engine.dailySleepHeartRate), avg28d: avg28(engine.dailySleepHeartRate), higherIsWorse: true)

    let midpointHours = engine.sleepMidpointHours
    let midpointVals = midpointHours.filter { $0.key >= window28dStart && $0.key <= day }.map(\.value)
    let consistencyStatus: String
    if midpointVals.count >= 5 {
        let mean = midpointVals.reduce(0, +) / Double(midpointVals.count)
        let variance = midpointVals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(midpointVals.count)
        let stddev = sqrt(variance)
        consistencyStatus = stddev < 1.0 ? "ok" : (stddev < 1.5 ? "moderate" : "low")
    } else {
        consistencyStatus = "no data"
    }

    return "resp rate: \(respStatus), wrist temp: \(wristTempStatus), SpO2: \(spo2Status), sleep HR: \(sleepHRStatus), sleep consistency: \(consistencyStatus)"
}

private func computeScoreDerivatives(
    strainSeries: [(Date, Double)],
    recoverySeries: [(Date, Double)],
    readinessSeries: [(Date, Double)]
) -> [(date: String, strain: Double, recovery: Double, readiness: Double, strainDelta: Double, recoveryDelta: Double, readinessDelta: Double)] {
    let calendar = Calendar.current
    let recoveryByDay = Dictionary(uniqueKeysWithValues: recoverySeries.map { (calendar.startOfDay(for: $0.0), $0.1) })
    let readinessByDay = Dictionary(uniqueKeysWithValues: readinessSeries.map { (calendar.startOfDay(for: $0.0), $0.1) })

    let sorted = strainSeries.sorted { $0.0 < $1.0 }
    var result: [(date: String, strain: Double, recovery: Double, readiness: Double, strainDelta: Double, recoveryDelta: Double, readinessDelta: Double)] = []
    var prevStrain: Double?
    var prevRecovery: Double?
    var prevReadiness: Double?

    for (date, strain) in sorted {
        let day = calendar.startOfDay(for: date)
        let rec = recoveryByDay[day] ?? 0
        let rdy = readinessByDay[day] ?? 0

        let sDelta = prevStrain.map { strain - $0 } ?? 0
        let rDelta = prevRecovery.map { rec - $0 } ?? 0
        let rdDelta = prevReadiness.map { rdy - $0 } ?? 0

        result.append((
            date: day.formatted(date: .abbreviated, time: .omitted),
            strain: (strain * 10).rounded() / 10,
            recovery: rec.rounded(),
            readiness: rdy.rounded(),
            strainDelta: (sDelta * 10).rounded() / 10,
            recoveryDelta: rDelta.rounded(),
            readinessDelta: rdDelta.rounded()
        ))

        prevStrain = strain
        prevRecovery = rec
        prevReadiness = rdy
    }
    return result
}

@MainActor
private func computeZoneDataBySport(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    context28dWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]? = nil,
    zoneProfiles: [UUID: HRZoneProfile] = [:]
) -> [(sport: String, z4min: Double, z5min: Double, totalMin: Double, avgHR: Double?)] {
    let grouped = Dictionary(grouping: workouts, by: { $0.workout.workoutActivityType.name })
    let cardioTypes: Set<String> = ["Running", "Cycling", "Swimming", "Rowing", "Elliptical", "Stair Climbing",
                                     "Cross Country Skiing", "Hiking", "Jump Rope", "Kickboxing", "Dance",
                                     "High Intensity Interval Training", "Mixed Cardio"]

    return grouped.compactMap { sport, pairs in
        let isCardio = cardioTypes.contains(sport) || pairs.contains(where: { pair in
            let z45 = resolvedZoneBreakdownAsync(for: pair.analytics, profile: zoneProfiles[pair.workout.uuid]).filter { $0.zone.zoneNumber >= 4 }.reduce(0.0) { $0 + $1.timeInZone }
            return z45 > 60
        })
        guard isCardio else { return nil }

        let z4 = pairs.reduce(0.0) { total, pair in total + zoneMinutesAsync(for: pair.analytics, zoneNumber: 4, profile: zoneProfiles[pair.workout.uuid]) }
        let z5 = pairs.reduce(0.0) { total, pair in total + zoneMinutesAsync(for: pair.analytics, zoneNumber: 5, profile: zoneProfiles[pair.workout.uuid]) }
        let totalMin = pairs.reduce(0.0) { $0 + $1.workout.duration / 60.0 }
        let allHR = pairs.flatMap { $0.analytics.heartRates.map(\.1) }
        let avgHR = allHR.isEmpty ? nil : allHR.reduce(0, +) / Double(allHR.count)

        guard z4 + z5 > 0.5 else { return nil }

        return (sport: sport, z4min: (z4 * 10).rounded() / 10, z5min: (z5 * 10).rounded() / 10, totalMin: totalMin.rounded(), avgHR: avgHR.map { ($0 * 10).rounded() / 10 })
    }.sorted { $0.z4min + $0.z5min > $1.z4min + $1.z5min }
}

private func computeZoneSessionEntries(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    zoneProfiles: [UUID: HRZoneProfile] = [:]
) -> [(sport: String, date: String, z4min: Double, z5min: Double, durationMin: Double, avgHR: Double?)] {
    let cardioTypes: Set<String> = ["Running", "Cycling", "Swimming", "Rowing", "Elliptical", "Stair Climbing",
                                     "Cross Country Skiing", "Hiking", "Jump Rope", "Kickboxing", "Dance",
                                     "High Intensity Interval Training", "Mixed Cardio"]

    return workouts.compactMap { pair in
        let sport = pair.workout.workoutActivityType.name
        let profile = zoneProfiles[pair.workout.uuid]
        let isCardio = cardioTypes.contains(sport) || {
            let z45 = resolvedZoneBreakdownAsync(for: pair.analytics, profile: profile).filter { $0.zone.zoneNumber >= 4 }.reduce(0.0) { $0 + $1.timeInZone }
            return z45 > 60
        }()
        guard isCardio else { return nil }

        let z4 = zoneMinutesAsync(for: pair.analytics, zoneNumber: 4, profile: profile)
        let z5 = zoneMinutesAsync(for: pair.analytics, zoneNumber: 5, profile: profile)
        print("[CoachAI][zone-session-diag] \(sport) \(pair.workout.startDate.formatted(date: .abbreviated, time: .shortened)) Z4=\(String(format: "%.1f", z4))min Z5=\(String(format: "%.1f", z5))min profile=\(profile != nil ? "resolved" : "fallback")")
        guard z4 + z5 > 0.5 else { return nil }

        let durationMin = pair.workout.duration / 60.0
        let allHR = pair.analytics.heartRates.map(\.1)
        let avgHR = allHR.isEmpty ? nil : allHR.reduce(0, +) / Double(allHR.count)
        let dateStr = pair.workout.startDate.formatted(date: .abbreviated, time: .omitted)

        return (sport: sport,
                date: dateStr,
                z4min: (z4 * 10).rounded() / 10,
                z5min: (z5 * 10).rounded() / 10,
                durationMin: durationMin.rounded(),
                avgHR: avgHR.map { ($0 * 10).rounded() / 10 })
    }.sorted { $0.date > $1.date }
}

private func resolvedZoneBreakdown(for analytics: WorkoutAnalytics) -> [(zone: HeartRateZone, timeInZone: TimeInterval)] {
    if let profile = analytics.hrZoneProfile {
        return HealthKitManager().calculateZoneBreakdown(
            heartRates: analytics.heartRates,
            zoneProfile: profile
        )
    }
    return analytics.hrZoneBreakdown
}

private func zoneMinutes(for analytics: WorkoutAnalytics, zoneNumber: Int) -> Double {
    let seconds = resolvedZoneBreakdown(for: analytics)
        .first(where: { $0.zone.zoneNumber == zoneNumber })?
        .timeInZone ?? 0
    return seconds / 60.0
}

/// Same resolution path as `HeartZoneEngine.resolveProfile` in `HeartZonesView` so coach Z4/Z5 minutes match the Heart Zones screen.
private func resolveZoneProfile(
    for workout: HKWorkout,
    analytics: WorkoutAnalytics,
    settings: HRZoneUserSettings,
    healthKitManager: HealthKitManager
) async -> HRZoneProfile {
    switch settings.mode {
    case .customZones:
        let bounds = settings.customZoneUpperBounds
        guard bounds.count == 5, zip(bounds, bounds.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            return await healthKitManager.createHRZoneProfile(for: workout.workoutActivityType)
        }
        let lowerBounds = [0.0] + Array(bounds.dropLast())
        let colors = ["0099FF", "00CC00", "FFCC00", "FF6600", "FF0000"]
        let zones = zip(Array(1...5), zip(lowerBounds, bounds)).map { zoneNumber, pair in
            HeartRateZone(name: "Zone \(zoneNumber)", range: pair.0...pair.1, color: colors[zoneNumber - 1], zoneNumber: zoneNumber)
        }
        return HRZoneProfile(
            sport: workout.workoutActivityType.rawValue,
            schema: settings.customSchema,
            maxHR: bounds.last,
            restingHR: nil,
            lactateThresholdHR: nil,
            zones: zones,
            lastUpdated: Date(),
            adaptive: false
        )

    case .customSchema:
        return await healthKitManager.createHRZoneProfile(
            for: workout.workoutActivityType,
            schema: settings.customSchema,
            customMaxHR: settings.fixedMaxHR,
            customRestingHR: settings.fixedRestingHR,
            customLTHR: settings.fixedLTHR
        )

    case .intelligent:
        let workoutDate = workout.startDate
        let maxHR = await healthKitManager.fetchMaxHR(workoutDate: workoutDate)
        let restingHR = await healthKitManager.fetchRHR(workoutDate: workoutDate)
        let schema = analytics.hrZoneProfile?.schema ?? healthKitManager.recommendedSchema(for: workout.workoutActivityType)
        let lactateThresholdHR = await healthKitManager.fetchLTHR(workoutDate: workoutDate, maxHR: maxHR)
        return await healthKitManager.createHRZoneProfile(
            for: workout.workoutActivityType,
            schema: schema,
            customMaxHR: maxHR,
            customRestingHR: restingHR,
            customLTHR: lactateThresholdHR
        )
    }
}

private func resolvedZoneBreakdownAsync(
    for analytics: WorkoutAnalytics,
    profile: HRZoneProfile?
) -> [(zone: HeartRateZone, timeInZone: TimeInterval)] {
    if let profile {
        return HealthKitManager().calculateZoneBreakdown(heartRates: analytics.heartRates, zoneProfile: profile)
    }
    return resolvedZoneBreakdown(for: analytics)
}

private func zoneMinutesAsync(for analytics: WorkoutAnalytics, zoneNumber: Int, profile: HRZoneProfile?) -> Double {
    let seconds = resolvedZoneBreakdownAsync(for: analytics, profile: profile)
        .first(where: { $0.zone.zoneNumber == zoneNumber })?
        .timeInZone ?? 0
    return seconds / 60.0
}

private func loadCoachZoneSettings() -> HRZoneUserSettings {
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

private func bulkResolveZoneProfiles(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
) async -> [UUID: HRZoneProfile] {
    let settings = loadCoachZoneSettings()
    let hkm = HealthKitManager()
    var profiles: [UUID: HRZoneProfile] = [:]
    for (workout, analytics) in workouts {
        profiles[workout.uuid] = await resolveZoneProfile(for: workout, analytics: analytics, settings: settings, healthKitManager: hkm)
    }
    return profiles
}

@MainActor
private func computePersonalBests(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    context28dWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
) -> String {
    let grouped = Dictionary(grouping: workouts, by: { $0.workout.workoutActivityType.name })

    var bests: [String] = []

    for (sport, pairs) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
        guard pairs.count >= 3 else { continue }

        if let longest = pairs.max(by: { $0.workout.duration < $1.workout.duration }) {
            let mins = (longest.workout.duration / 60.0).rounded()
            let date = longest.workout.startDate.formatted(date: .abbreviated, time: .omitted)
            bests.append("\(sport) longest session: \(formatted(mins, digits: 0))min on \(date)")
        }

        if let highestHR = pairs.compactMap({ p -> (HKWorkout, Double)? in p.analytics.peakHR.map { (p.workout, $0) } }).max(by: { $0.1 < $1.1 }) {
            let date = highestHR.0.startDate.formatted(date: .abbreviated, time: .omitted)
            bests.append("\(sport) peak HR: \(formatted(highestHR.1, digits: 0))bpm on \(date)")
        }

        if let highestPower = pairs.compactMap({ p -> (HKWorkout, Double)? in
            guard let avg = coachSessionAvgPowerWatts(p.analytics) else { return nil }
            return (p.workout, avg)
        }).max(by: { $0.1 < $1.1 }) {
            let date = highestPower.0.startDate.formatted(date: .abbreviated, time: .omitted)
            bests.append("\(sport) avg power: \(formatted(highestPower.1, digits: 0))W on \(date)")
        }
    }

    if bests.isEmpty { return "" }

    let context28dGrouped = Dictionary(grouping: context28dWorkouts, by: { $0.workout.workoutActivityType.name })
    var contextLines: [String] = []
    for (sport, pairs) in context28dGrouped {
        if let longestCtx = pairs.max(by: { $0.workout.duration < $1.workout.duration }) {
            contextLines.append("28d \(sport) longest: \(formatted(longestCtx.workout.duration / 60.0, digits: 0))min")
        }
    }

    return (bests + contextLines).joined(separator: "; ")
}

private func statsLine(label: String, values: [Double], digits: Int = 1, singleCalendarDay: Bool = false) -> String? {
    let nonZero = values.filter { $0 > 0 }
    guard !nonZero.isEmpty else { return nil }
    let avg = average(nonZero) ?? 0
    let lo = nonZero.min() ?? avg
    let hi = nonZero.max() ?? avg
    let trend: String
    // Same calendar day: ordering is not a week-long trend—avoid "rising/falling" misreads.
    if singleCalendarDay || nonZero.count < 4 {
        trend = singleCalendarDay ? "mixed (same calendar day)" : "limited"
    } else {
        let chunk = max(1, nonZero.count / 3)
        let first = nonZero.prefix(chunk).reduce(0, +) / Double(chunk)
        let last = nonZero.suffix(chunk).reduce(0, +) / Double(chunk)
        if abs(last - first) < max(avg * 0.08, 0.2) {
            trend = "steady"
        } else {
            trend = last > first ? "rising" : "falling"
        }
    }
    return "\(label): avg \(formatted(avg, digits: digits)), range \(formatted(lo, digits: digits))-\(formatted(hi, digits: digits)), trend \(trend)"
}

private func sportPhysiologicalLoadProfile(
    sport: String,
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
) -> (profile: String, confidence: String, atypicalNotes: [String]) {
    let lowerSport = sport.lowercased()
    let highZoneSessions = workouts.filter { pair in
        let z45 = resolvedZoneBreakdown(for: pair.analytics).filter { $0.zone.zoneNumber >= 4 }.reduce(0.0) { $0 + $1.timeInZone }
        return z45 >= 60
    }
    let avgHighZoneMinutes = average(highZoneSessions.map {
        resolvedZoneBreakdown(for: $0.analytics).filter { $0.zone.zoneNumber >= 4 }.reduce(0.0) { $0 + $1.timeInZone } / 60.0
    }) ?? 0
    let avgHR = average(workouts.flatMap { $0.analytics.heartRates.map(\.1) }) ?? 0
    let likelyCardioLabel = ["run", "cycle", "bike", "swim", "row", "hike", "walk", "cardio", "ski", "elliptical"].contains { lowerSport.contains($0) }
    let atypical = !likelyCardioLabel && (avgHighZoneMinutes >= 8 || avgHR >= 150)
    let confidence: String
    if atypical {
        confidence = "low"
    } else if avgHighZoneMinutes > 0 || avgHR > 120 {
        confidence = "high"
    } else {
        confidence = "medium"
    }
    let profile: String
    if avgHighZoneMinutes >= 12 {
        profile = "high-zone driven"
    } else if avgHR >= 135 {
        profile = "cardio-forward"
    } else if avgHR > 0 {
        profile = "mixed-load"
    } else {
        profile = "limited physiology"
    }
    let notes = atypical ? ["Atypical session detection: \(sport) logged unusually high heart-rate load, so treat sport-labeled high-zone claims cautiously."] : []
    return (profile, confidence, notes)
}

// MARK: - Coach HRR (explicit peak − HR @~2 min post-end)

private func coachHRRPeakBpm(analytics: WorkoutAnalytics) -> Double? {
    analytics.peakHR ?? analytics.heartRates.map(\.1).max()
}

private func coachHRRClosestPostWorkoutBpm(minutesAfterEnd: Double, analytics: WorkoutAnalytics) -> Double? {
    let end = analytics.workout.endDate
    let target = end.addingTimeInterval(minutesAfterEnd * 60)
    guard !analytics.postWorkoutHRSeries.isEmpty else { return nil }
    let closest = analytics.postWorkoutHRSeries.min(by: { abs($0.0.timeIntervalSince(target)) < abs($1.0.timeIntervalSince(target)) })
    return closest?.1
}

/// Peak HR during workout minus post-workout HR nearest **2 minutes after workout end** (same construction as analytics pipeline); falls back to `hrr2` only if post-workout series is empty.
private func coachHRR2MinuteDropBpm(analytics: WorkoutAnalytics) -> Double? {
    guard let peak = coachHRRPeakBpm(analytics: analytics) else { return nil }
    guard let hr2 = coachHRRClosestPostWorkoutBpm(minutesAfterEnd: 2, analytics: analytics) else { return analytics.hrr2 }
    return peak - hr2
}

private func coachHRRPromptSnippet(analytics: WorkoutAnalytics) -> String {
    guard let drop = coachHRR2MinuteDropBpm(analytics: analytics) else {
        return "\(coachHRRMetricDisplayName) unavailable (need peak HR and post-workout HR near 2 min after end)"
    }
    let peakStr = coachHRRPeakBpm(analytics: analytics).map { formatted($0, digits: 0) } ?? "—"
    let hr2Str = coachHRRClosestPostWorkoutBpm(minutesAfterEnd: 2, analytics: analytics).map { formatted($0, digits: 0) } ?? "—"
    return "\(coachHRRMetricDisplayName) \(formatted(drop, digits: 0)) bpm drop (= peak \(peakStr) bpm - HR ~2m post-end \(hr2Str) bpm)"
}

private func coachCachedOrAnalyzedHRR(workout: HKWorkout, analytics: WorkoutAnalytics) -> HeartRateRecoveryResult {
    let rhr = CoachHRRRestingGate.shared.current()
    let rhrKey = Int(rhr.rounded())
    if let c = HRRAnalysisCache.shared.result(for: workout.uuid),
       c.restingHRUsed.map({ Int($0.rounded()) }) == Optional(rhrKey) {
        return c
    }
    let r = HeartRateRecoveryAnalysis.analyze(workout: workout, analytics: analytics, restingHRBpm: rhr)
    HRRAnalysisCache.shared.store(r, workoutUUID: workout.uuid)
    return r
}

private func coachEffectiveHRRDropBpm(workout: HKWorkout, analytics: WorkoutAnalytics) -> Double? {
    let r = coachCachedOrAnalyzedHRR(workout: workout, analytics: analytics)
    if let d = HeartRateRecoveryAnalysis.coachPreferredDropBpm(result: r) { return d }
    if let s = HeartRateRecoveryAnalysis.coachComparableRecoveryScore(result: r) { return s }
    return coachHRR2MinuteDropBpm(analytics: analytics)
}

private func coachHRRPromptSnippet(workout: HKWorkout, analytics: WorkoutAnalytics) -> String {
    let r = coachCachedOrAnalyzedHRR(workout: workout, analytics: analytics)
    if let d = HeartRateRecoveryAnalysis.coachPreferredDropBpm(result: r) {
        return "Refined \(coachHRRMetricDisplayName) \(formatted(d, digits: 0)) bpm drop (2m after workout end; \(r.isStaticRecovery ? "static peak anchor" : "active end-HR anchor"); confidence \(Int(r.confidence * 100))%; \(r.scenario.rawValue))"
    }
    if r.excludeTwoMinuteFromPrimaryMetrics {
        var s = "HRR 2m delta omitted (late peak within 30 bpm of resting; RHR \(r.restingHRUsed.map { String(format: "%.0f bpm", $0) } ?? "unknown"))."
        if let rp = r.recoveryPowerBpmPerSec { s += " Recovery power (10s max slope after late peak): \(formatted(rp, digits: 2)) bpm/s." }
        if let tt = r.secondsToDrop20Bpm { s += " Time to −20 bpm post-end: \(formatted(tt, digits: 0)) s." }
        return s
    }
    if r.scenario == .steadyStateMaintained {
        var s = "HRR steady-state (\(r.scenario.rawValue), confidence \(Int(r.confidence * 100))%): near equilibrium vs anchor vs resting—avoid over-reading small 2m changes."
        if let rp = r.recoveryPowerBpmPerSec { s += " Recovery power: \(formatted(rp, digits: 2)) bpm/s." }
        if let tt = r.secondsToDrop20Bpm { s += " Time to −20 bpm: \(formatted(tt, digits: 0)) s." }
        if let d2 = r.dropBpm2m { s += " Internal 2m signed drop: \(formatted(d2, digits: 0)) bpm (not primary)." }
        return s
    }
    if let proxy = HeartRateRecoveryAnalysis.coachComparableRecoveryScore(result: r) {
        return "HRR recovery proxy \(formatted(proxy, digits: 0)) (from recovery power; refined 2m drop unavailable). Scenario: \(r.scenario.rawValue)."
    }
    return coachHRRPromptSnippet(analytics: analytics)
}

@MainActor
private func coachUnitContractLine(store: UnitPreferencesStore) -> String {
    let d = store.resolvedDistanceUnit == .miles ? "miles (mi)" : "kilometers (km)"
    let s = store.resolvedSpeedUnit == .milesPerHour ? "mph" : "km/h"
    let e = store.resolvedElevationUnit == .feet ? "feet (ft)" : "meters (m)"
    return "Unit contract: Quote distances in \(d), speeds in \(s), and elevation gain in \(e) exactly as shown in this prompt—do not convert to other unit systems in your answer."
}

/// Avg power for coach payloads only when discrete power samples exist and average is meaningful.
private func coachSessionAvgPowerWatts(_ analytics: WorkoutAnalytics) -> Double? {
    guard !analytics.powerSeries.isEmpty,
          let v = average(analytics.powerSeries.map(\.1)),
          v > 0 else { return nil }
    return v
}

/// Avg cadence for coach payloads only when cadence samples exist and average is meaningful.
private func coachSessionAvgCadenceRpm(_ analytics: WorkoutAnalytics) -> Double? {
    guard !analytics.cadenceSeries.isEmpty,
          let v = average(analytics.cadenceSeries.map(\.1)),
          v > 0 else { return nil }
    return v
}

private func sameSportMetBaselineCoachLine(
    prior7dSameSportWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    reportWindowStart: Date,
    calendar: Calendar = .current
) -> String? {
    guard !prior7dSameSportWorkouts.isEmpty else { return nil }
    let endExclusive = reportWindowStart
    let rangeStart = calendar.date(byAdding: .day, value: -7, to: endExclusive) ?? endExclusive
    let lastDay = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
    let label = "\(rangeStart.formatted(date: .abbreviated, time: .omitted))–\(lastDay.formatted(date: .abbreviated, time: .omitted))"
    let sessionCount = prior7dSameSportWorkouts.count
    let mets = prior7dSameSportWorkouts.compactMap { $0.analytics.metTotal }.filter { $0 > 0 }
    if mets.isEmpty {
        return "Same-type MET baseline (7d before report window, \(label)): \(sessionCount) session(s); MET Minutes missing—treat MET in the report window as cumulative load only, not a normalized score."
    }
    let sum = mets.reduce(0, +)
    let avgAmongSessionsWithMET = sum / Double(mets.count)
    return "Same-type MET baseline (7d before report window, \(label)): \(sessionCount) session(s), \(formatted(sum, digits: 0)) MET Minutes total, ~\(formatted(avgAmongSessionsWithMET, digits: 0)) MET Minutes avg among sessions with MET data (cumulative workload units, not 0–100 or “out of 1000”)."
}

/// Chronological, dated facts per workout—matches Training Focus / sport coach session evidence so users can check trend claims.
private func coachValidationRowsForSportTrainingFocus(
    sport: String,
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    zoneProfiles: [UUID: HRZoneProfile],
    maxRows: Int = 56
) -> [TrainingFocusCoachValidationRow] {
    let sorted = workouts.sorted { $0.workout.startDate < $1.workout.startDate }
    var rows: [TrainingFocusCoachValidationRow] = []
    func push(date: Date, dataType: String, value: String) {
        guard rows.count < maxRows else { return }
        let dateLabel = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        let id = "\(sport)-\(dataType)-\(date.timeIntervalSince1970)-\(rows.count)"
        rows.append(TrainingFocusCoachValidationRow(id: id, dateLabel: dateLabel, dataType: dataType, value: value))
    }
    for pair in sorted {
        let d = pair.workout.startDate
        let w = pair.workout
        let a = pair.analytics
        let profile = zoneProfiles[w.uuid]
        push(date: d, dataType: "Session duration", value: "\(Int((w.duration / 60.0).rounded())) min")
        if let met = a.metTotal, met > 0 { push(date: d, dataType: "MET Minutes", value: formatted(met, digits: 0)) }
        if let hr = average(a.heartRates.map(\.1)), hr > 0 { push(date: d, dataType: "Avg HR", value: "\(formatted(hr, digits: 0)) bpm") }
        let z4 = zoneMinutesAsync(for: a, zoneNumber: 4, profile: profile)
        let z5 = zoneMinutesAsync(for: a, zoneNumber: 5, profile: profile)
        if z4 > 0.05 { push(date: d, dataType: "Time in Zone 4", value: "\(formatted(z4, digits: 1)) min") }
        if z5 > 0.05 { push(date: d, dataType: "Time in Zone 5", value: "\(formatted(z5, digits: 1)) min") }
        let hrrLine = coachHRRPromptSnippet(workout: w, analytics: a)
        if !hrrLine.contains("unavailable") {
            push(date: d, dataType: coachHRRMetricDisplayName, value: hrrLine)
        }
        if let pwr = coachSessionAvgPowerWatts(a) {
            push(date: d, dataType: "Avg Power", value: "\(formatted(pwr, digits: 0)) W")
        }
        if let cad = coachSessionAvgCadenceRpm(a) {
            push(date: d, dataType: "Avg Cadence", value: "\(formatted(cad, digits: 0)) rpm")
        }
    }
    return rows
}

@MainActor
private func buildTrainingFocusReportPayload(
    sport: String,
    reportPeriod: SummaryReportPeriod,
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    questSummary: String,
    zoneProfiles: [UUID: HRZoneProfile] = [:],
    prior7dSameSportWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []
) -> TrainingFocusReportPayload? {
    guard !workouts.isEmpty else { return nil }
    let units = UnitPreferencesStore()
    let calendar = Calendar.current
    let singleCalendarDayWindow = calendar.isDate(reportPeriod.start, inSameDayAs: reportPeriod.end)
    let durations = workouts.map { $0.workout.duration / 60.0 }
    let distanceMetersValues = workouts.compactMap { pair -> Double? in
        pair.workout.totalDistance?.doubleValue(for: .meter())
    }
    let distanceDisplayValues = distanceMetersValues.map { meters in
        units.resolvedDistanceUnit == .miles ? meters / 1609.344 : meters / 1000.0
    }
    let distanceSuffix = units.resolvedDistanceUnit == .miles ? " mi" : " km"
    let distanceTrendLabel = units.resolvedDistanceUnit == .miles ? "Distance (mi)" : "Distance (km)"
    let energyValues = workouts.compactMap { $0.workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) }
    let avgHRValues = workouts.map { average($0.analytics.heartRates.map(\.1)) ?? 0 }.filter { $0 > 0 }
    let metValues = workouts.compactMap { $0.analytics.metTotal }
    let z4Values = workouts.map { zoneMinutesAsync(for: $0.analytics, zoneNumber: 4, profile: zoneProfiles[$0.workout.uuid]) }
    let z5Values = workouts.map { zoneMinutesAsync(for: $0.analytics, zoneNumber: 5, profile: zoneProfiles[$0.workout.uuid]) }
    let hrrValues = workouts.compactMap { coachEffectiveHRRDropBpm(workout: $0.workout, analytics: $0.analytics) }
    let powerValues = workouts.compactMap { coachSessionAvgPowerWatts($0.analytics) }
    let cadenceValues = workouts.compactMap { coachSessionAvgCadenceRpm($0.analytics) }
    let elevationMetersValues = workouts.compactMap { $0.analytics.elevationGain }
    let elevationDisplayValues = elevationMetersValues.map { meters in
        units.resolvedElevationUnit == .feet ? meters * 3.28084 : meters
    }
    let elevationSuffix = units.resolvedElevationUnit == .feet ? " ft" : " m"
    let elevationTrendLabel = units.resolvedElevationUnit == .feet ? "Elevation gain (ft)" : "Elevation gain (m)"
    let speedKphValues = workouts.compactMap { pair -> Double? in
        guard let meters = pair.workout.totalDistance?.doubleValue(for: .meter()),
              pair.workout.duration > 0 else { return nil }
        let kph = (meters / 1000.0) / (pair.workout.duration / 3600.0)
        return kph > 0 ? kph : nil
    }
    let speedDisplayValues = speedKphValues.map { kph in
        units.resolvedSpeedUnit == .milesPerHour ? kph / 1.609344 : kph
    }
    let speedSuffix = units.resolvedSpeedUnit == .milesPerHour ? " mph" : " km/h"
    let speedTrendLabel = units.resolvedSpeedUnit == .milesPerHour ? "Avg speed (mph)" : "Avg speed (km/h)"

    let profile = sportPhysiologicalLoadProfile(sport: sport, workouts: workouts)
    var metrics: [TrainingFocusMetric] = [
        .init(id: "sessions", label: "Sessions", value: "\(workouts.count)"),
        .init(id: "duration", label: "Total Time", value: "\(Int(durations.reduce(0, +).rounded())) min")
    ]

    func appendMetric(id: String, label: String, values: [Double], digits: Int = 0, suffix: String = "") {
        guard let avg = average(values.filter { $0 > 0 }), avg > 0 else { return }
        metrics.append(.init(id: id, label: label, value: "\(formatted(avg, digits: digits))\(suffix)"))
    }

    func appendSumMetric(id: String, label: String, values: [Double], digits: Int = 0, suffix: String = "") {
        let sum = values.filter { $0 > 0 }.reduce(0, +)
        guard sum > 0 else { return }
        metrics.append(.init(id: id, label: label, value: "\(formatted(sum, digits: digits))\(suffix)"))
    }

    appendSumMetric(id: "distance", label: "Distance", values: distanceDisplayValues, digits: 1, suffix: distanceSuffix)
    appendMetric(id: "speed", label: "Avg Speed", values: speedDisplayValues, digits: 1, suffix: speedSuffix)
    appendSumMetric(id: "energy", label: "Active kcal", values: energyValues, digits: 0)
    appendSumMetric(id: "elevation", label: "Elevation Gain", values: elevationDisplayValues, digits: 0, suffix: elevationSuffix)
    appendMetric(id: "hr", label: "Avg HR", values: avgHRValues, digits: 0, suffix: " bpm")
    appendSumMetric(id: "met", label: "MET Minutes", values: metValues, digits: 0)
    appendSumMetric(id: "z4", label: "Time in Zone 4", values: z4Values, digits: 1, suffix: " min")
    appendSumMetric(id: "z5", label: "Time in Zone 5", values: z5Values, digits: 1, suffix: " min")
    appendMetric(id: "hrr", label: "HRR (2m drop or recovery-power proxy)", values: hrrValues, digits: 0, suffix: "")
    appendMetric(id: "power", label: "Avg Power", values: powerValues, digits: 0, suffix: " W")
    appendMetric(id: "cadence", label: "Avg Cadence", values: cadenceValues, digits: 0, suffix: " rpm")

    let trendLines = [
        statsLine(label: "Duration", values: durations, digits: 0, singleCalendarDay: singleCalendarDayWindow).map { "Training Focus report view | \($0)" },
        statsLine(label: distanceTrendLabel, values: distanceDisplayValues, digits: 1, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: "MET Minutes", values: metValues, digits: 0, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: "Avg HR", values: avgHRValues, digits: 0, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: "Time in Zone 4", values: z4Values, digits: 1, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: "Time in Zone 5", values: z5Values, digits: 1, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: speedTrendLabel, values: speedDisplayValues, digits: 1, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: elevationTrendLabel, values: elevationDisplayValues, digits: 0, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: "Avg Power", values: powerValues, digits: 0, singleCalendarDay: singleCalendarDayWindow),
        statsLine(label: "Avg Cadence", values: cadenceValues, digits: 0, singleCalendarDay: singleCalendarDayWindow)
    ].compactMap { $0 }

    let standoutSessions = workouts
        .sorted { $0.workout.startDate > $1.workout.startDate }
        .prefix(3)
        .map { pair in
            let date = pair.workout.startDate.formatted(date: .abbreviated, time: .omitted)
            let duration = Int((pair.workout.duration / 60.0).rounded())
            let profile = zoneProfiles[pair.workout.uuid]
            let z4 = zoneMinutesAsync(for: pair.analytics, zoneNumber: 4, profile: profile)
            let z5 = zoneMinutesAsync(for: pair.analytics, zoneNumber: 5, profile: profile)
            let power = coachSessionAvgPowerWatts(pair.analytics).map { " | Avg Power \(formatted($0, digits: 0)) W" } ?? ""
            let cadence = coachSessionAvgCadenceRpm(pair.analytics).map { " | Avg Cadence \(formatted($0, digits: 0)) rpm" } ?? ""
            return TrainingFocusSessionDigest(
                id: "\(sport)-\(pair.workout.startDate.timeIntervalSince1970)",
                date: date,
                summary: "\(duration) min | Time in Zone 4 \(formatted(z4, digits: 1)) min | Time in Zone 5 \(formatted(z5, digits: 1)) min | \(coachHRRPromptSnippet(workout: pair.workout, analytics: pair.analytics))\(power)\(cadence)"
            )
        }

    let metBaselineLine = sameSportMetBaselineCoachLine(
        prior7dSameSportWorkouts: prior7dSameSportWorkouts,
        reportWindowStart: reportPeriod.start
    )

    let coachValidationRows = coachValidationRowsForSportTrainingFocus(
        sport: sport,
        workouts: workouts,
        zoneProfiles: zoneProfiles
    )

    return TrainingFocusReportPayload(
        sportLabel: sport,
        physiologicalLoadProfile: profile.profile,
        dataConfidence: profile.confidence,
        manualOverride: false,
        periodLabel: reportPeriod.description,
        questSummary: questSummary,
        metrics: metrics,
        trendLines: trendLines + profile.atypicalNotes,
        standoutSessions: standoutSessions,
        sameSportMetBaselineLine: metBaselineLine,
        coachValidationRows: coachValidationRows
    )
}

@MainActor
private func precomputeCoachPayload(
    engine: HealthStateEngine,
    timeFilter: StrainRecoveryView.TimeFilter,
    anchorDate: Date,
    suggestionID: String,
    sportFilter: String?
) async -> CoachMetricPayload {
    let coachRHR = await HealthKitManager().fetchRestingHeartRateLatest()
    CoachHRRRestingGate.shared.update(coachRHR)

    let calendar = Calendar.current
    let requestedDay = calendar.startOfDay(for: anchorDate)
    let reportPeriod = summaryReportPeriod(for: timeFilter, requestedDate: requestedDay)
    let window = (start: reportPeriod.start, end: reportPeriod.end, endExclusive: reportPeriod.endExclusive)
    let selectedDay = reportPeriod.canonicalAnchorDate
    let yesterday = calendar.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay

    let past7dStart = calendar.date(byAdding: .day, value: -7, to: requestedDay) ?? requestedDay
    let past28dStart = calendar.date(byAdding: .day, value: -28, to: requestedDay) ?? requestedDay

    let scopedSport = sportFilter
    let historicalWindowStart = calendar.date(byAdding: .day, value: -27, to: window.start) ?? window.start
    let allWorkouts = engine.workoutAnalytics.filter { workout, _ in
        let matchesDate = workout.startDate >= historicalWindowStart && workout.startDate < window.endExclusive
        let matchesSport = scopedSport == nil || workout.workoutActivityType.name == scopedSport
        return matchesDate && matchesSport
    }
    let displayWorkouts = allWorkouts.filter { $0.workout.startDate >= window.start && $0.workout.startDate < window.endExclusive }

    let zoneProfiles = await bulkResolveZoneProfiles(workouts: allWorkouts)
    for (uuid, profile) in zoneProfiles {
        if let workout = allWorkouts.first(where: { $0.workout.uuid == uuid })?.workout {
            let z4Bounds = profile.zones.first(where: { $0.zoneNumber == 4 })
            let z5Bounds = profile.zones.first(where: { $0.zoneNumber == 5 })
            print("[CoachAI][zone-diag] \(workout.workoutActivityType.name) \(workout.startDate.formatted(date: .abbreviated, time: .shortened)) schema=\(profile.schema.rawValue) maxHR=\(profile.maxHR.map { String(format: "%.0f", $0) } ?? "?") Z4=[\(z4Bounds.map { String(format: "%.0f-%.0f", $0.range.lowerBound, $0.range.upperBound) } ?? "?")] Z5=[\(z5Bounds.map { String(format: "%.0f-%.0f", $0.range.lowerBound, $0.range.upperBound) } ?? "?")]")
        }
    }

    let loadSnapshots = dailyLoadSnapshots(
        workouts: allWorkouts,
        estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
        displayWindow: window
    )
    let selectedSnapshot = loadSnapshots.last(where: { calendar.isDate($0.date, inSameDayAs: reportPeriod.end) }) ?? loadSnapshots.last

    let displayedStrain = selectedSnapshot?.strainScore ?? engine.strainScore
    let selectedRecoveryScore = recoveryScore(for: reportPeriod.end, engine: engine) ?? engine.recoveryScore
    let selectedReadinessScore = readinessScore(for: reportPeriod.end, recoveryScore: selectedRecoveryScore, strainScore: displayedStrain, engine: engine) ?? engine.readinessScore

    var payload = CoachMetricPayload(
        timeFilter: timeFilter,
        suggestionID: suggestionID,
        dateLabel: selectedDay.formatted(date: .abbreviated, time: .omitted),
        periodLabel: reportPeriod.description,
        sportFilter: sportFilter
    )
    payload.strainScore = displayedStrain
    payload.recoveryScore = selectedRecoveryScore
    payload.readinessScore = selectedReadinessScore
    payload.recoveryLabel = recoveryClassification(for: selectedRecoveryScore).title

    // Yesterday vs today framing is for 1D coach reads only; week/month prompts should stay trend- and date-grounded.
    if timeFilter == .day {
        let priorDayWindow = (
            start: yesterday,
            end: yesterday,
            endExclusive: calendar.date(byAdding: .day, value: 1, to: yesterday) ?? yesterday.addingTimeInterval(86400)
        )
        let workoutsForPriorSnapshots = engine.workoutAnalytics.filter { w, _ in
            w.startDate >= historicalWindowStart && w.startDate < window.endExclusive
        }
        let priorDaySnapshots = dailyLoadSnapshots(
            workouts: workoutsForPriorSnapshots,
            estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
            displayWindow: priorDayWindow
        )
        let yesterdayStrainForReadiness = priorDaySnapshots.first?.strainScore

        if let yesterdayRecovery = recoveryScore(for: yesterday, engine: engine) {
            let yClass = recoveryClassification(for: yesterdayRecovery).title
            payload.secondaryContext.facts.append(("YesterdayRecovery", "\(yClass) (\(formatted(yesterdayRecovery, digits: 0)))"))
            if let yStrain = yesterdayStrainForReadiness,
               let yReadiness = readinessScore(for: yesterday, recoveryScore: yesterdayRecovery, strainScore: yStrain, engine: engine) {
                payload.secondaryContext.facts.append(("YesterdayReadiness", "\(formatted(yReadiness, digits: 0))/100"))
                let yLabel = yesterday.formatted(date: .abbreviated, time: .omitted)
                payload.priorDayScoresLine = "[PRIOR_DAY] \(yLabel) Recovery: \(formatted(yesterdayRecovery, digits: 0))/100 \(yClass), Readiness: \(formatted(yReadiness, digits: 0))/100"
            }
        }
        if let yesterdayStrain = yesterdayStrainForReadiness, let snap = priorDaySnapshots.first {
            let label = workoutLoadStatus(for: snap).title
            payload.secondaryContext.facts.append(("YesterdayStrain", "\(label) (\(formatted(yesterdayStrain, digits: 1)))"))
        }
    }

    let strainSeries = loadSnapshots.map { ($0.date, $0.strainScore) }
    let recoverySeries = dateSequence(from: reportPeriod.start, to: reportPeriod.end).compactMap { day -> (Date, Double)? in
        recoveryScore(for: day, engine: engine).map { (day, $0) }
    }
    let readinessSeries = dateSequence(from: reportPeriod.start, to: reportPeriod.end).compactMap { day -> (Date, Double)? in
        guard let strain = strainSeries.first(where: { calendar.isDate($0.0, inSameDayAs: day) })?.1,
              let rec = recoveryScore(for: day, engine: engine),
              let rdy = readinessScore(for: day, recoveryScore: rec, strainScore: strain, engine: engine) else { return nil }
        return (day, rdy)
    }

    func fmtDate(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .omitted) }

    switch timeFilter {
    case .day:
        /// Matches `HeartZonesView` 1W window (`windowStart` = anchor−6) and baseline (`baselineStart` = windowStart−7).
        let heartZonesRolling7Start = calendar.date(byAdding: .day, value: -6, to: requestedDay) ?? requestedDay
        let heartZonesPriorStart = calendar.date(byAdding: .day, value: -7, to: requestedDay) ?? requestedDay
        let heartZonesEndExclusive = window.endExclusive

        let past7dStrainScores = loadSnapshots.filter { $0.date >= past7dStart && $0.date < requestedDay }.map(\.strainScore)
        payload.strainWeekAvg = average(past7dStrainScores)
        payload.strainConsistencyLabel = strainConsistencyClassification(for: past7dStrainScores + [displayedStrain]).title

        let loadWindow = (start: past7dStart, end: requestedDay, endExclusive: calendar.date(byAdding: .day, value: 1, to: requestedDay) ?? requestedDay)
        let past7dWorkouts = engine.workoutAnalytics.filter { w, _ in w.startDate >= past7dStart && w.startDate < window.endExclusive }
        let past7dSnapshots = dailyLoadSnapshots(workouts: past7dWorkouts, estimatedMaxHeartRate: engine.estimatedMaxHeartRate, displayWindow: loadWindow)
        payload.trainingLoadSeries = past7dSnapshots.map { snap in
            (date: fmtDate(snap.date), load: (snap.totalDailyLoad * 10).rounded() / 10,
             acwr: snap.activeDaysLast28 >= 14 ? ((snap.acwr * 100).rounded() / 100) : nil,
             label: workoutLoadStatus(for: snap).title)
        }

        let metValues = engine.dailyMETAggregates
        payload.metToday = metValues[requestedDay]
        let past7dMet = metValues.filter { $0.key >= past7dStart && $0.key < requestedDay }.map(\.value)
        payload.metWeekAvg = average(past7dMet)

        let hrvValues = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        let hrvWindow = (start: past7dStart, end: requestedDay, endExclusive: calendar.date(byAdding: .day, value: 1, to: requestedDay) ?? requestedDay)
        payload.hrvSeries = filteredWindowSeries(values: hrvValues, in: hrvWindow).map { (fmtDate($0.0), ($0.1 * 10).rounded() / 10) }
        payload.rhrSeries = filteredWindowSeries(values: engine.dailyRestingHeartRate, in: hrvWindow).map { (fmtDate($0.0), $0.1.rounded()) }
        payload.hrrSeries = filteredWindowSeries(values: engine.dailyHRRAggregates, in: hrvWindow).map { (fmtDate($0.0), $0.1.rounded()) }
        payload.sleepHeartRateSeries = filteredWindowSeries(values: engine.dailySleepHeartRate, in: hrvWindow).map { (fmtDate($0.0), $0.1.rounded()) }

        payload.recoverySeries = dateSequence(from: past7dStart, to: requestedDay).compactMap { day -> (date: String, score: Double)? in
            recoveryScore(for: day, engine: engine).map { (fmtDate(day), $0.rounded()) }
        }
        payload.readinessSeries = dateSequence(from: past7dStart, to: requestedDay).compactMap { day -> (date: String, score: Double)? in
            guard let strainVal = past7dSnapshots.first(where: { calendar.isDate($0.date, inSameDayAs: day) })?.strainScore,
                  let rec = recoveryScore(for: day, engine: engine),
                  let rdy = readinessScore(for: day, recoveryScore: rec, strainScore: strainVal, engine: engine) else { return nil }
            return (fmtDate(day), rdy.rounded())
        }

        let sleepTotals = engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        }
        payload.sleepSeries = dateSequence(from: past7dStart, to: requestedDay).compactMap { day -> (date: String, hours: Double, core: Double, deep: Double, rem: Double)? in
            guard let total = sleepTotals[day], total > 0 else { return nil }
            let stages = engine.sleepStages[day] ?? [:]
            return (fmtDate(day), (total * 10).rounded() / 10, (stages["core"] ?? 0).rounded(toPlaces: 1), (stages["deep"] ?? 0).rounded(toPlaces: 1), (stages["rem"] ?? 0).rounded(toPlaces: 1))
        }

        payload.vitalsStatus = computeVitalsStatus(engine: engine, selectedDay: requestedDay, window28dStart: past28dStart)

        if timeFilter == .day,
           let lastWorkout = engine.workoutAnalytics
            .filter({ $0.workout.startDate < window.endExclusive })
            .max(by: { $0.workout.startDate < $1.workout.startDate }) {
            payload.secondaryContext.facts.append(("LastWorkoutType", lastWorkout.workout.workoutActivityType.name))
            payload.secondaryContext.facts.append(("WorkoutTime", lastWorkout.workout.startDate.formatted(date: .omitted, time: .shortened)))
        }

        let past7dAllWorkouts = engine.workoutAnalytics.filter { w, _ in w.startDate >= past7dStart && w.startDate < window.endExclusive }
        let workoutDays = dateSequence(from: past7dStart, to: requestedDay)
        let scheduleEntries = workoutDays.map { day -> String in
            let dayWorkouts = past7dAllWorkouts.filter { calendar.isDate($0.workout.startDate, inSameDayAs: day) }
            if dayWorkouts.isEmpty { return "\(fmtDate(day)):rest" }
            let totalMin = dayWorkouts.reduce(0.0) { $0 + $1.workout.duration / 60.0 }
            let sports = Set(dayWorkouts.map { $0.workout.workoutActivityType.name }).joined(separator: ",")
            return "\(fmtDate(day)):\(formatted(totalMin, digits: 0))min(\(sports))"
        }
        payload.trainingSchedule = scheduleEntries.joined(separator: "; ")

        // 1D sport / all-sports: zone totals must be anchor-day only. Never substitute rolling 7d here—
        // that made the coach treat weekly aggregates as "today's session."
        if suggestionID.hasPrefix("1d-sport-") || suggestionID == "1d-all-sports" {
            let sportW: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
            if suggestionID.hasPrefix("1d-sport-"), let sportID = extractSportFromSuggestionID(suggestionID) {
                sportW = displayWorkouts.filter {
                    $0.workout.workoutActivityType.name.lowercased().replacingOccurrences(of: " ", with: "-") == sportID
                }
            } else {
                sportW = displayWorkouts
            }
            if !sportW.isEmpty {
                payload.zoneDataBySport = computeZoneDataBySport(workouts: sportW, zoneProfiles: zoneProfiles)
            }
        }
        if suggestionID == "1d-zones" {
            let rolling7ZoneWorkouts = engine.workoutAnalytics.filter { w, _ in
                w.startDate >= heartZonesRolling7Start && w.startDate < heartZonesEndExclusive &&
                    (scopedSport == nil || w.workoutActivityType.name == scopedSport)
            }
            let todayW = rolling7ZoneWorkouts.filter { calendar.isDate($0.workout.startDate, inSameDayAs: requestedDay) }
            let priorW = engine.workoutAnalytics.filter { w, _ in
                w.startDate >= heartZonesPriorStart && w.startDate < requestedDay &&
                    (scopedSport == nil || w.workoutActivityType.name == scopedSport)
            }
            payload.zoneTodaySessions = computeZoneSessionEntries(workouts: todayW, zoneProfiles: zoneProfiles)
            payload.zonePriorWindowSessions = computeZoneSessionEntries(workouts: priorW, zoneProfiles: zoneProfiles)
            payload.zoneDataBySport = computeZoneDataBySport(workouts: rolling7ZoneWorkouts, zoneProfiles: zoneProfiles)
            payload.zoneConfidenceNotes = Dictionary(grouping: rolling7ZoneWorkouts, by: { $0.workout.workoutActivityType.name }).compactMap { sport, pairs in
                let profile = sportPhysiologicalLoadProfile(sport: sport, workouts: pairs)
                return profile.confidence == "low" ? "\(sport): atypical high-HR pattern, treat literal sport-specific zone claims cautiously." : nil
            }
        }

    case .week:
        payload.strainConsistencyLabel = strainConsistencyClassification(for: strainSeries.map(\.1)).title

        payload.trainingLoadSeries = loadSnapshots.map { snap in
            (date: fmtDate(snap.date), load: (snap.totalDailyLoad * 10).rounded() / 10,
             acwr: snap.activeDaysLast28 >= 14 ? ((snap.acwr * 100).rounded() / 100) : nil,
             label: workoutLoadStatus(for: snap).title)
        }

        let metValues = engine.dailyMETAggregates
        let metInWindow = filteredWindowSeries(values: metValues, in: window)
        payload.metToday = metInWindow.last?.1
        payload.metWeekAvg = average(metInWindow.map(\.1))

        let hrvValues = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        payload.hrvSeries = filteredWindowSeries(values: hrvValues, in: window).map { (fmtDate($0.0), ($0.1 * 10).rounded() / 10) }
        payload.rhrSeries = filteredWindowSeries(values: engine.dailyRestingHeartRate, in: window).map { (fmtDate($0.0), $0.1.rounded()) }
        payload.hrrSeries = filteredWindowSeries(values: engine.dailyHRRAggregates, in: window).map { (fmtDate($0.0), $0.1.rounded()) }
        payload.sleepHeartRateSeries = filteredWindowSeries(values: engine.dailySleepHeartRate, in: window).map { (fmtDate($0.0), $0.1.rounded()) }

        payload.recoverySeries = recoverySeries.map { (fmtDate($0.0), $0.1.rounded()) }
        payload.readinessSeries = readinessSeries.map { (fmtDate($0.0), $0.1.rounded()) }

        let sleepTotals = engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        }
        payload.sleepSeries = dateSequence(from: window.start, to: window.end).compactMap { day -> (date: String, hours: Double, core: Double, deep: Double, rem: Double)? in
            guard let total = sleepTotals[day], total > 0 else { return nil }
            let stages = engine.sleepStages[day] ?? [:]
            return (fmtDate(day), (total * 10).rounded() / 10, (stages["core"] ?? 0).rounded(toPlaces: 1), (stages["deep"] ?? 0).rounded(toPlaces: 1), (stages["rem"] ?? 0).rounded(toPlaces: 1))
        }

        payload.vitalsStatus = computeVitalsStatus(engine: engine, selectedDay: window.end, window28dStart: past28dStart)

        if suggestionID == "1w-svr" {
            payload.scoreDerivatives = computeScoreDerivatives(strainSeries: strainSeries, recoverySeries: recoverySeries, readinessSeries: readinessSeries)
            let ctx28dStrainScores = loadSnapshots.filter { $0.date >= past28dStart && $0.date < window.start }.map(\.strainScore)
            let ctx28dRecovery = dateSequence(from: past28dStart, to: calendar.date(byAdding: .day, value: -1, to: window.start) ?? window.start).compactMap { day -> Double? in recoveryScore(for: day, engine: engine) }
            payload.workoutSummary = "28d context: strain avg \(formatted(average(ctx28dStrainScores) ?? 0, digits: 1)), recovery avg \(formatted(average(ctx28dRecovery) ?? 0, digits: 0))"
        }

        if suggestionID == "1w-pb" {
            let ctx28dWorkouts = engine.workoutAnalytics.filter { w, _ in w.startDate >= past28dStart && w.startDate < window.start }
            payload.personalBests = computePersonalBests(workouts: displayWorkouts, context28dWorkouts: ctx28dWorkouts)
        }

        if suggestionID == "1w-zones" {
            let ctx28dWorkouts = engine.workoutAnalytics.filter { w, _ in w.startDate >= past28dStart && w.startDate < window.endExclusive }
            payload.zoneSessionEntries = computeZoneSessionEntries(workouts: displayWorkouts, zoneProfiles: zoneProfiles)
            payload.zoneDataBySport = computeZoneDataBySport(workouts: displayWorkouts, context28dWorkouts: ctx28dWorkouts, zoneProfiles: zoneProfiles)
            payload.zoneConfidenceNotes = Dictionary(grouping: displayWorkouts, by: { $0.workout.workoutActivityType.name }).compactMap { sport, pairs in
                let profile = sportPhysiologicalLoadProfile(sport: sport, workouts: pairs)
                return profile.confidence == "low" ? "\(sport): atypical high-HR pattern, treat literal sport-specific zone claims cautiously." : nil
            }
        }

        let scheduleEntries = dateSequence(from: window.start, to: window.end).map { day -> String in
            let dayWorkouts = displayWorkouts.filter { calendar.isDate($0.workout.startDate, inSameDayAs: day) }
            if dayWorkouts.isEmpty { return "\(fmtDate(day)):rest" }
            let totalMin = dayWorkouts.reduce(0.0) { $0 + $1.workout.duration / 60.0 }
            let sports = Set(dayWorkouts.map { $0.workout.workoutActivityType.name }).joined(separator: ",")
            return "\(fmtDate(day)):\(formatted(totalMin, digits: 0))min(\(sports))"
        }
        payload.trainingSchedule = scheduleEntries.joined(separator: "; ")

    case .month:
        payload.strainConsistencyLabel = strainConsistencyClassification(for: strainSeries.map(\.1)).title

        payload.trainingLoadSeries = loadSnapshots.map { snap in
            (date: fmtDate(snap.date), load: (snap.totalDailyLoad * 10).rounded() / 10,
             acwr: snap.activeDaysLast28 >= 14 ? ((snap.acwr * 100).rounded() / 100) : nil,
             label: workoutLoadStatus(for: snap).title)
        }

        payload.efficiencyRatios = computeEfficiencyRatio(
            strainSeries: strainSeries,
            recoverySeries: recoverySeries,
            readinessSeries: readinessSeries
        )
        payload.monthlyAggregateLines = [
            statsLine(label: "Training load", values: loadSnapshots.map(\.totalDailyLoad), digits: 1),
            statsLine(label: "Strain", values: strainSeries.map(\.1), digits: 1),
            statsLine(label: "Recovery", values: recoverySeries.map(\.1), digits: 0),
            statsLine(label: "Readiness", values: readinessSeries.map(\.1), digits: 0)
        ].compactMap { $0 }

        var weeklyTotals: [String] = []
        let weeks = segmentedCoachWindows(for: .month, reportPeriod: reportPeriod)
        for segment in weeks {
            let weekWorkouts = displayWorkouts.filter { $0.workout.startDate >= segment.start && $0.workout.startDate <= segment.end }
            let totalMin = weekWorkouts.reduce(0.0) { $0 + $1.workout.duration / 60.0 }
            let label = "\(fmtDate(segment.start))-\(fmtDate(segment.end))"
            weeklyTotals.append("\(label): \(formatted(totalMin, digits: 0))min")
        }
        payload.trainingSchedule = weeklyTotals.joined(separator: "; ")

        if suggestionID.hasPrefix("1m-sport-") {
            payload.zoneDataBySport = computeZoneDataBySport(workouts: displayWorkouts, zoneProfiles: zoneProfiles)
        }
    }

    if suggestionID.contains("sport-") {
        let sportWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]
        let resolvedSportName: String?
        if let sportID = extractSportFromSuggestionID(suggestionID) {
            sportWorkouts = displayWorkouts.filter { $0.workout.workoutActivityType.name.lowercased().replacingOccurrences(of: " ", with: "-") == sportID }
            resolvedSportName = sportWorkouts.first?.workout.workoutActivityType.name ?? sportID
        } else {
            sportWorkouts = displayWorkouts
            resolvedSportName = nil
        }

        var lines: [String] = []
        lines.append("sessions: \(sportWorkouts.count)")
        let totalMin = sportWorkouts.reduce(0.0) { $0 + $1.workout.duration / 60.0 }
        lines.append("total min: \(formatted(totalMin, digits: 0))")

        // Zone minutes must match `StrainRecoveryView.trainingFocusReport` / the on-screen Training Focus card.
        // Do not pass HeartZones-resolved profiles here—they can massively reclassify minutes vs analytics breakdown.
        for pair in sportWorkouts.prefix(10) {
            let date = fmtDate(pair.workout.startDate)
            let dur = formatted(pair.workout.duration / 60.0, digits: 0)
            let z4 = zoneMinutesAsync(for: pair.analytics, zoneNumber: 4, profile: nil)
            let z5 = zoneMinutesAsync(for: pair.analytics, zoneNumber: 5, profile: nil)
            let peakHR = pair.analytics.peakHR.map { formatted($0, digits: 0) + "bpm" } ?? "-"
            let hrrR = coachCachedOrAnalyzedHRR(workout: pair.workout, analytics: pair.analytics)
            let hrrDrop: String
            if let ref = HeartRateRecoveryAnalysis.coachPreferredDropBpm(result: hrrR) {
                hrrDrop = "\(formatted(ref, digits: 0))bpmDropRefined2m"
            } else if let proxy = HeartRateRecoveryAnalysis.coachComparableRecoveryScore(result: hrrR) {
                hrrDrop = "\(formatted(proxy, digits: 0))hrrProxy"
            } else if let leg = coachHRR2MinuteDropBpm(analytics: pair.analytics) {
                hrrDrop = "\(formatted(leg, digits: 0))bpmDrop"
            } else {
                hrrDrop = "-"
            }
            let power = coachSessionAvgPowerWatts(pair.analytics).map { formatted($0, digits: 0) + "W" } ?? ""
            let cadence = coachSessionAvgCadenceRpm(pair.analytics).map { formatted($0, digits: 0) + "rpm" } ?? ""
            lines.append("\(date) \(dur)min z4:\(formatted(z4, digits: 1)) z5:\(formatted(z5, digits: 1)) pk:\(peakHR) hrrDrop:\(hrrDrop) \(power) \(cadence)".trimmingCharacters(in: .whitespaces))
        }
        payload.workoutSummary = lines.joined(separator: "\n")

        if let sportName = resolvedSportName {
            payload.questSummary = StageQuestStore.shared.questSummary(forSport: sportName, from: window.start, to: window.end)
            let metBaselineStart = calendar.date(byAdding: .day, value: -7, to: window.start) ?? window.start
            let priorSameTypeMET = engine.workoutAnalytics.filter { w, _ in
                w.startDate >= metBaselineStart && w.startDate < window.start &&
                    w.workoutActivityType.name == sportName
            }
            payload.trainingFocusReport = buildTrainingFocusReportPayload(
                sport: sportName,
                reportPeriod: reportPeriod,
                workouts: sportWorkouts,
                questSummary: payload.questSummary,
                zoneProfiles: [:],
                prior7dSameSportWorkouts: priorSameTypeMET
            )
        }
        payload.fallbackBridge = "Not enough \(resolvedSportName?.lowercased() ?? "sport-specific") signal here to call a clear trend, but overall consistency across other activities can still provide context."
    } else if suggestionID == "1w-consistency" || suggestionID == "1m-consistency" {
        payload.fallbackBridge = "Primary evidence is thin, but overall activity consistency across the available workouts still gives some useful context."
    }

    return payload
}

private func extractSportFromSuggestionID(_ id: String) -> String? {
    let prefixes = ["1d-sport-", "1w-sport-", "1m-sport-"]
    for prefix in prefixes {
        if id.hasPrefix(prefix) {
            return String(id.dropFirst(prefix.count))
        }
    }
    return nil
}

private func filteredPayload(for suggestion: SummarySuggestion, base: CoachMetricPayload) -> CoachMetricPayload {
    var payload = base
    let id = suggestion.id

    if id == "1d-sleep-bio" || id == "1w-sleep-bio" {
        payload.trainingLoadSeries = []
        payload.zoneDataBySport = []
        payload.zoneSessionEntries = []
        payload.zoneTodaySessions = []
        payload.zonePriorWindowSessions = []
    }

    if id == "1d-consistency" || id == "1w-consistency" || id == "1m-consistency" {
        payload.personalBests = ""
        payload.zoneDataBySport = []
        payload.zoneSessionEntries = []
        payload.zoneTodaySessions = []
        payload.zonePriorWindowSessions = []
        payload.workoutSummary = ""
    }

    if id.contains("sport-") {
        payload.hrvSeries = []
        payload.rhrSeries = []
        payload.hrrSeries = []
        payload.sleepHeartRateSeries = []
        payload.sleepSeries = []
        payload.recoverySeries = []
        payload.readinessSeries = []
        payload.vitalsStatus = ""
        payload.zoneDataBySport = []
    }

    if id == "1m-overall" {
        payload.recoverySeries = []
        payload.readinessSeries = []
        payload.hrvSeries = []
        payload.rhrSeries = []
        payload.hrrSeries = []
        payload.sleepHeartRateSeries = []
        payload.sleepSeries = []
        payload.zoneDataBySport = []
        payload.zoneSessionEntries = []
        payload.zoneTodaySessions = []
        payload.zonePriorWindowSessions = []
    }

    return payload
}

private func secondaryContext(for suggestion: SummarySuggestion, payload: CoachMetricPayload) -> String? {
    let limit = suggestion.id.hasPrefix("1d-") ? 6 : 4
    let facts = Array(payload.secondaryContext.facts.prefix(limit))
    guard !facts.isEmpty else { return nil }
    switch suggestion.id {
    case "1d-readiness", "1d-sleep-bio", "1d-zones", "1d-consistency", "1d-all-sports":
        return CoachSecondaryContext(facts: facts).renderedLine()
    case "1w-sleep-bio", "1w-svr", "1w-zones", "1w-pb", "1m-overall":
        return CoachSecondaryContext(facts: Array(facts.prefix(2))).renderedLine()
    default:
        return suggestion.id.contains("sport-") ? CoachSecondaryContext(facts: Array(facts.prefix(1))).renderedLine() : nil
    }
}

private func fallbackBridge(for suggestion: SummarySuggestion, payload: CoachMetricPayload) -> String? {
    guard suggestion.coachPromptSpec.fallbackPolicy.allowBridge else { return nil }
    return payload.fallbackBridge
}

private func promptDataLines(for suggestion: SummarySuggestion, payload: CoachMetricPayload) -> [String] {
    var lines: [String] = []
    let id = suggestion.id

    func appendSeries<T>(_ prefix: String, _ values: [T], transform: (T) -> String) {
        guard !values.isEmpty else { return }
        lines.append("\(prefix): \(values.map(transform).joined(separator: " "))")
    }

    if let strain = payload.strainScore {
        let scorePrefix = id.hasPrefix("1d-") ? "Scores [ANCHOR_DAY]:" : "Scores:"
        var scoreLine = "\(scorePrefix) Strain \(formatted(strain, digits: 1))/21"
        if let recovery = payload.recoveryScore {
            scoreLine += ", Recovery \(formatted(recovery, digits: 0))/100 \(payload.recoveryLabel ?? "")"
        }
        if let readiness = payload.readinessScore {
            scoreLine += ", Readiness \(formatted(readiness, digits: 0))/100"
        }
        lines.append(scoreLine)
    }

    let priorDaySuggestionIDs: Set<String> = [
        "1d-readiness", "1d-sleep-bio", "1d-zones", "1d-consistency", "1d-all-sports"
    ]
    if priorDaySuggestionIDs.contains(id), let prior = payload.priorDayScoresLine {
        lines.append(prior)
        lines.append(CoachPromptFragments.priorDayVersusSevenDayRule)
    }

    switch id {
    case "1d-readiness":
        if let avg = payload.strainWeekAvg {
            lines.append("[7D] Recent load context: 7d Strain avg \(formatted(avg, digits: 1)); consistency \(payload.strainConsistencyLabel ?? "N/A")")
        }
        appendSeries("[7D] Recovery", payload.recoverySeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        appendSeries("[7D] Readiness", payload.readinessSeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        if !payload.trainingLoadSeries.isEmpty {
            let lastLoads = payload.trainingLoadSeries.suffix(4).map { "\($0.date):\(formatted($0.load, digits: 1)) \($0.label ?? "")".trimmingCharacters(in: .whitespaces) }
            lines.append("[7D] Recent training load (multi-day): \(lastLoads.joined(separator: " | "))")
        }
    case "1d-sleep-bio":
        appendSeries("[7D] Sleep", payload.sleepSeries) { "\($0.date):\($0.hours)h(core \($0.core) deep \($0.deep) rem \($0.rem))" }
        appendSeries("[7D] Recovery", payload.recoverySeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        appendSeries("[7D] Readiness", payload.readinessSeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        appendSeries("[7D] RHR", payload.rhrSeries) { "\($0.date):\($0.value)bpm" }
        appendSeries("[7D] HRV", payload.hrvSeries) { "\($0.date):\($0.value)ms" }
        appendSeries("[7D] Sleep HR", payload.sleepHeartRateSeries) { "\($0.date):\($0.value)bpm" }
        if !payload.vitalsStatus.isEmpty { lines.append("Vitals [selected day / anchor context]: \(payload.vitalsStatus)") }
    case "1w-sleep-bio":
        appendSeries("Sleep", payload.sleepSeries) { "\($0.date):\($0.hours)h(core \($0.core) deep \($0.deep) rem \($0.rem))" }
        appendSeries("Recovery", payload.recoverySeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        appendSeries("Readiness", payload.readinessSeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        appendSeries("RHR", payload.rhrSeries) { "\($0.date):\($0.value)bpm" }
        appendSeries("HRV", payload.hrvSeries) { "\($0.date):\($0.value)ms" }
        appendSeries("Sleep HR", payload.sleepHeartRateSeries) { "\($0.date):\($0.value)bpm" }
        if !payload.vitalsStatus.isEmpty { lines.append("Vitals: \(payload.vitalsStatus)") }
    case "1d-zones":
        lines.append("Zone data contract: [ANCHOR_DAY] \"Today zone sessions\" = selected day only. [7D] \"Rolling 7d sport totals\" = sum across 7 calendar days ending on the selected day (not the same as today-only minutes).")
        if !payload.zoneTodaySessions.isEmpty {
            lines.append("[ANCHOR_DAY] Today zone sessions: \(payload.zoneTodaySessions.map { "\($0.sport) \($0.date): Z4 \(formatted($0.z4min, digits: 1)) min, Z5 \(formatted($0.z5min, digits: 1)) min" }.joined(separator: " | "))")
        } else {
            lines.append("[ANCHOR_DAY] Today zone sessions: unavailable")
        }
        if !payload.zoneConfidenceNotes.isEmpty {
            lines.append("Zone confidence: \(payload.zoneConfidenceNotes.joined(separator: " | "))")
        }
        if !payload.zoneDataBySport.isEmpty {
            lines.append("[7D] Rolling sport-separated zone totals (7 days ending selected day; not anchor-day minutes): \(payload.zoneDataBySport.map { "\($0.sport): Z4 \(formatted($0.z4min, digits: 1)) min, Z5 \(formatted($0.z5min, digits: 1)) min, Avg HR \($0.avgHR.map { formatted($0, digits: 0) } ?? "-") bpm" }.joined(separator: " | "))")
        }
        if !payload.zonePriorWindowSessions.isEmpty {
            lines.append("[7D prior window] High-zone sessions (7 days before selected day): \(payload.zonePriorWindowSessions.prefix(8).map { "\($0.sport) \($0.date): Z4 \(formatted($0.z4min, digits: 1)) min, Z5 \(formatted($0.z5min, digits: 1)) min" }.joined(separator: " | "))")
        }
    case "1d-consistency":
        if let schedule = payload.trainingSchedule { lines.append("[7D] Schedule: \(schedule)") }
        if !payload.trainingLoadSeries.isEmpty {
            lines.append("[7D] Completed load: \(payload.trainingLoadSeries.map { "\($0.date):\(formatted($0.load, digits: 1))" }.joined(separator: " | "))")
        }
    case "1d-all-sports":
        if let schedule = payload.trainingSchedule { lines.append("[7D] All-sport schedule: \(schedule)") }
        if !payload.trainingLoadSeries.isEmpty {
            lines.append("[7D] All-sport load: \(payload.trainingLoadSeries.map { "\($0.date):\(formatted($0.load, digits: 1))" }.joined(separator: " | "))")
        }
    case "1w-svr":
        appendSeries("Recovery", payload.recoverySeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        appendSeries("Readiness", payload.readinessSeries) { "\($0.date):\(formatted($0.score, digits: 0))" }
        if !payload.trainingLoadSeries.isEmpty {
            lines.append("Strain/load series: \(payload.trainingLoadSeries.map { "\($0.date):\(formatted($0.load, digits: 1)) \($0.label ?? "")".trimmingCharacters(in: .whitespaces) }.joined(separator: " | "))")
        }
        if !payload.scoreDerivatives.isEmpty {
            lines.append("Derivative table: \(payload.scoreDerivatives.map { "\($0.date): S \($0.strain), R \($0.recovery), Rd \($0.readiness), dS \($0.strainDelta), dR \($0.recoveryDelta), dRd \($0.readinessDelta)" }.joined(separator: " | "))")
        }
        if !payload.workoutSummary.isEmpty { lines.append(payload.workoutSummary) }
    case "1w-zones":
        if !payload.zoneConfidenceNotes.isEmpty {
            lines.append("Zone confidence: \(payload.zoneConfidenceNotes.joined(separator: " | "))")
        }
        if !payload.zoneDataBySport.isEmpty {
            lines.append("Weekly zone totals: \(payload.zoneDataBySport.map { "\($0.sport): Time in Zone 4 \(formatted($0.z4min, digits: 1)) min, Time in Zone 5 \(formatted($0.z5min, digits: 1)) min, Avg HR \($0.avgHR.map { formatted($0, digits: 0) } ?? "-") bpm" }.joined(separator: " | "))")
        }
        if !payload.zoneSessionEntries.isEmpty {
            lines.append("Standout zone sessions: \(payload.zoneSessionEntries.prefix(6).map { "\($0.sport) \($0.date): Z4 \(formatted($0.z4min, digits: 1)) min, Z5 \(formatted($0.z5min, digits: 1)) min" }.joined(separator: " | "))")
        }
    case "1w-pb":
        if !payload.personalBests.isEmpty { lines.append("Weekly best candidates: \(payload.personalBests)") }
        if !payload.workoutSummary.isEmpty { lines.append("Support context: \(payload.workoutSummary)") }
    case "1w-consistency", "1m-consistency":
        if let schedule = payload.trainingSchedule { lines.append("Schedule: \(schedule)") }
        if let consistency = payload.strainConsistencyLabel { lines.append("Consistency: \(consistency)") }
    case "1m-overall":
        if !payload.monthlyAggregateLines.isEmpty {
            lines.append("Monthly aggregates: \(payload.monthlyAggregateLines.joined(separator: " | "))")
        }
        if !payload.efficiencyRatios.isEmpty {
            lines.append("Efficiency ratio: \(payload.efficiencyRatios.map { "\($0.date):\($0.ratio) \($0.label)" }.joined(separator: " | "))")
        }
        if let schedule = payload.trainingSchedule { lines.append("Weekly schedule totals: \(schedule)") }
    default:
        if id.contains("sport-"), let report = payload.trainingFocusReport {
            if payload.timeFilter == .day && id.hasPrefix("1d-sport-") {
                lines.append("Window: 1D only — Training Focus metrics and sessions below are \(report.sportLabel) totals for \(report.periodLabel) (selected day), not 7-day rolling averages unless a line explicitly says so.")
            }
            lines.append("Authoritative Time in Zone 4 and Time in Zone 5: cite only Metric anchors, Trend hints, and session lines below—the same analytics breakdown as the Training Focus card.")
            lines.append("Integrated \(report.sportLabel) evidence (for coaching synthesis only—do not recite as a report):")
            lines.append("Load story: \(report.physiologicalLoadProfile); evidence strength: \(report.dataConfidence)")
            if !report.questSummary.isEmpty {
                lines.append("Quest arc: \(report.questSummary)")
            }
            if !report.metrics.isEmpty {
                lines.append("Metric anchors: \(report.metrics.map { "\($0.label) \($0.value)" }.joined(separator: " | "))")
            }
            if let metBase = report.sameSportMetBaselineLine {
                lines.append(metBase)
            }
            if !report.trendLines.isEmpty {
                lines.append("Trend hints: \(report.trendLines.joined(separator: " | "))")
            }
            if !report.standoutSessions.isEmpty {
                lines.append("Notable sessions: \(report.standoutSessions.map { "\($0.date) \($0.summary)" }.joined(separator: " | "))")
            }
            if !payload.workoutSummary.isEmpty {
                lines.append("Session detail lines (same sport and calendar window as Training Focus; use for coaching, not as a list to read aloud):\n\(payload.workoutSummary)")
            }
        } else {
            let isSport = id.contains("sport-")
            if isSport, id.hasPrefix("1d-sport-"), payload.timeFilter == .day {
                lines.append("[7D] No integrated Training Focus block for this sport on the anchor day (no sessions or build failed). Schedule and load below are the trailing 7-day window ending on the anchor date—not that day's session totals.")
            } else if isSport, id.hasPrefix("1w-sport-") {
                lines.append("[1W] No integrated Training Focus block for this sport in the selected week. Schedule/load below are week-scoped.")
            } else if isSport, id.hasPrefix("1m-sport-") {
                lines.append("[1M] No integrated Training Focus block for this sport in the selected month. Schedule/load below are month-scoped.")
            }
            let schedulePrefix: String = {
                if isSport, id.hasPrefix("1d-sport-"), payload.timeFilter == .day { return "[7D] Schedule" }
                if isSport, id.hasPrefix("1w-sport-") { return "[1W] Schedule" }
                if isSport, id.hasPrefix("1m-sport-") { return "[1M] Schedule" }
                return "Schedule"
            }()
            let loadPrefix: String = {
                if isSport, id.hasPrefix("1d-sport-"), payload.timeFilter == .day { return "[7D] Training load" }
                if isSport, id.hasPrefix("1w-sport-") { return "[1W] Training load" }
                if isSport, id.hasPrefix("1m-sport-") { return "[1M] Training load" }
                return "Training load"
            }()
            if let schedule = payload.trainingSchedule { lines.append("\(schedulePrefix): \(schedule)") }
            if !payload.trainingLoadSeries.isEmpty {
                lines.append("\(loadPrefix): \(payload.trainingLoadSeries.map { "\($0.date):\(formatted($0.load, digits: 1))" }.joined(separator: " | "))")
            }
        }
    }

    return lines
}

private func metricWindowGuide(for suggestion: SummarySuggestion) -> String {
        switch suggestion.id {
        case "1d-consistency", "1d-all-sports":
            return """
            Metric window guide: \"Scores [ANCHOR_DAY]\" is only Strain/Recovery/Readiness for the selected calendar date. Primary training tables here are [7D] (schedule, load, volume)—use them to infer consistency and how today fits the pattern; do not equate those weekly totals with today's score line. You may still sound day-forward for what to do next.
            """
        default:
            return """
            Metric window guide: \"Scores [ANCHOR_DAY]\" is only the selected calendar date. \"[7D]\" and multi-date lines are recent context so you can place today in its load-and-recovery lane—they are not the same numbers as today's session totals. Use them for judgment; default answer stays anchored on today without a weekly recap opener.
            """
        }
}

private func coachPromptEvidenceContainsHRR(dataLines: [String], contextLine: String?, payload: CoachMetricPayload) -> Bool {
    let blob = (dataLines + [contextLine ?? ""]).joined(separator: "\n")
    if blob.contains(coachHRRMetricDisplayName) { return true }
    if blob.contains("hrrDrop:") || blob.contains("bpmDrop") { return true }
    if blob.contains("Refined HRR") || blob.contains("Refined \(coachHRRMetricDisplayName)") { return true }
    return false
}

private func coachPromptEvidenceContainsMET(dataLines: [String], payload: CoachMetricPayload) -> Bool {
    let blob = dataLines.joined(separator: "\n")
    if blob.contains("MET Minutes") { return true }
    if let report = payload.trainingFocusReport, report.sameSportMetBaselineLine != nil { return true }
    return false
}

private func coachPromptAllowsHRRCitation(_ prompt: String) -> Bool {
    prompt.contains(coachHRRMetricDisplayName)
        || prompt.contains("hrrDrop:")
        || prompt.contains("bpmDrop")
        || prompt.contains("bpmDropRefined2m")
        || prompt.contains("hrrProxy")
        || prompt.contains("Refined HRR")
        || prompt.contains("Recovery power")
        || prompt.contains("HRR 2m delta omitted")
        || prompt.contains("HRR steady-state")
        || prompt.contains("HRR recovery proxy")
}

private func coachResponseMentionsHRR(_ text: String) -> Bool {
    text.range(of: "HRR", options: .caseInsensitive) != nil
        || text.localizedCaseInsensitiveContains("heart rate recovery")
}

private func coachPromptAllowsMETCitation(_ prompt: String) -> Bool {
    prompt.contains("MET Minutes")
}

private func coachResponseMentionsMET(_ text: String) -> Bool {
    text.localizedCaseInsensitiveContains("MET Minutes")
}

@MainActor
private func buildCompactPrompt(from payload: CoachMetricPayload, suggestion: SummarySuggestion) -> String {
    let spec = suggestion.coachPromptSpec
    let filtered = filteredPayload(for: suggestion, base: payload)
    let dataLines = promptDataLines(for: suggestion, payload: filtered)
    let contextLine = secondaryContext(for: suggestion, payload: filtered)
    var lines: [String] = []

    lines.append("Coach prompt for \(suggestion.title).")
    lines.append("Filter: \(filtered.timeFilter.rawValue), Date: \(filtered.dateLabel), Period: \(filtered.periodLabel)")
    lines.append(coachUnitContractLine(store: UnitPreferencesStore()))
    lines.append("Suggestion ID: \(filtered.suggestionID)")
    if let sport = filtered.sportFilter {
        lines.append("Sport filter: \(sport)")
    }
    if suggestion.id.hasPrefix("1d-") {
        lines.append(metricWindowGuide(for: suggestion))
        lines.append(CoachPromptFragments.metricWindowDiscipline)
    }
    if suggestion.id.hasPrefix("1w-") || suggestion.id.hasPrefix("1m-") {
        lines.append(CoachPromptFragments.trendRequiresExplicitDates)
        lines.append(CoachPromptFragments.weekTrendNarrative)
    }
    lines.append(CoachPromptFragments.noRenamedCompositeScores)
    if coachPromptEvidenceContainsHRR(dataLines: dataLines, contextLine: contextLine, payload: filtered) {
        lines.append(CoachPromptFragments.hrrDropSemantics)
    }
    if coachPromptEvidenceContainsMET(dataLines: dataLines, payload: filtered) {
        lines.append(CoachPromptFragments.metMinutesSemantics)
    }
    lines.append(spec.primaryScope)
    lines.append(spec.secondaryContextPolicy)
    lines.append("Fallback contract: \(spec.fallbackPolicy.unavailableLead)")
    lines.append(spec.uiTerminologyContract)
    lines.append(contentsOf: spec.requiredFragments)
    lines.append(contentsOf: spec.negativeConstraints)
    if suggestion.id == "1d-readiness" {
        lines.append(CoachPromptFragments.citeOnlyPrintedMetricsReadiness)
    }
    if let contextLine {
        lines.append(contextLine)
    }
    if let bridge = fallbackBridge(for: suggestion, payload: filtered) {
        lines.append("Bridge if needed: \(bridge)")
    }
    lines.append(contentsOf: dataLines)
    return lines.joined(separator: "\n")
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}

private extension Array where Element == (Date, Double) {
    var average: Double? {
        guard !isEmpty else { return nil }
        return map(\.1).reduce(0, +) / Double(count)
    }
}

// MARK: - End Precomputed Coach Infrastructure

private func localFallbackSummary(
    displayedStrain: Double,
    recoveryScore: Double,
    scoreContextLead: String,
    workoutHighlights: WorkoutHighlights,
    selectedSnapshot: WorkoutSummarySnapshot?,
    scenario: String,
    intent: SummaryIntent,
    timeFilter: StrainRecoveryView.TimeFilter,
    sleepData: [(Date, Double)],
    sleepDebtHours: Double,
    consistencyScore: Double,
    activityRecoveryGap: Double,
    hrvData: [(Date, Double)],
    rhrData: [(Date, Double)],
    sleepHRData: [(Date, Double)],
    hrrData: [(Date, Double)],
    respiratoryData: [(Date, Double)],
    wristTempData: [(Date, Double)],
    spo2Data: [(Date, Double)]
) -> String {
    let periodMetricLabel = switch timeFilter {
    case .day: "selected day"
    case .week: "selected week"
    case .month: "selected month"
    }
    let loadStatus = workoutLoadStatus(for: selectedSnapshot)
    let recoveryState = recoveryClassification(for: recoveryScore)
    let latestSleep = sleepData.last?.1 ?? 0
    let averageSleep = average(sleepData.map(\.1)) ?? 0
    let hrvTrend = trendSummary(for: hrvData, digits: 0)
    let rhrTrend = trendSummary(for: rhrData, digits: 0)
    let sleepHRTrend = trendSummary(for: sleepHRData, digits: 0)
    let vitalsState = vitalsNormSummary(
        respiratoryData: respiratoryData,
        wristTempData: wristTempData,
        spo2Data: spo2Data
    )
    let equalizerSignal: String = {
        if recoveryScore >= 70 && displayedStrain >= 11 {
            return "Your Equalizer is working. You are asking more from training and your recovery is rising with it."
        }

        if loadStatus.title == "Spike" || loadStatus.title == "Aggressive" {
            return "Your Equalizer is tilting toward strain, so the best move is to stay precise and make the next push count."
        }

        return "Your Equalizer looks manageable right now, and the next step is to keep the work purposeful as recovery tracks the load."
    }()
    let overreachSignal: String = {
        guard let latestHRR = hrrData.last?.1,
              let averageHRR = average(hrrData.map(\.1)),
              averageHRR > 0,
              let acwr = selectedSnapshot?.acwr else {
            return ""
        }

        if latestHRR < averageHRR * 0.92 && acwr > 1.2 {
            return " Your heart rate recovery is a bit softer than its recent baseline while load is elevated, so that is a useful context signal as you decide how aggressive to be."
        }

        return ""
    }()

    return """
    \(scenario) \(equalizerSignal)\(overreachSignal) \(scoreContextLead) Recovery is classified as \(recoveryState.title.lowercased()). Recovery state meaning: \(recoveryState.detail) Your load status is \(loadStatus.title.lowercased()), with \(formatted(workoutHighlights.totalMinutes, digits: 0)) total training minutes in the \(periodMetricLabel) and \(formatted(workoutHighlights.sessionsPerWeek, digits: 1)) sessions per week normalized from the \(periodMetricLabel). Your standout work came from \(workoutHighlights.longestWorkout.lowercased()) and \(workoutHighlights.highestLoadWorkout.lowercased()). You also spent \(formatted(workoutHighlights.totalZone4Minutes, digits: 0)) minutes in Zone 4 and \(formatted(workoutHighlights.totalZone5Minutes, digits: 0)) minutes in Zone 5 during the \(periodMetricLabel), so intensity is a real part of the story.

    Your sleep is averaging \(formatted(averageSleep, digits: 1)) hours, with \(formatted(latestSleep, digits: 1)) hours most recently. Sleep consistency is \(formatted(consistencyScore, digits: 0))%, and sleep debt is \(formatted(sleepDebtHours, digits: 1)) hours. HRV is \(hrvTrend), resting heart rate is \(rhrTrend), and sleep heart rate is \(sleepHRTrend). \(vitalsState) A recovery-day sleep gap of \(signedFormatted(activityRecoveryGap, digits: 1)) hours is worth keeping if you want better absorption of training. Coaching focus right now: \(intent.promptInstruction)
    """
}

struct StrainRecoveryMathSection: View {
    @ObservedObject var engine: HealthStateEngine
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    @State private var showTechnicalSheet = false
    @State private var cachedLoadSnapshots: [WorkoutSummarySnapshot] = []
    @State private var cachedLoadSnapshotsKey: String = ""
    
    private var totalLoad: Double {
        loadSnapshots.map(\.totalDailyLoad).reduce(0, +)
    }
    
    private var averageLoad: Double {
        average(loadSnapshots.map(\.totalDailyLoad)) ?? 0
    }
    
    private var strainValue: Double {
        selectedSnapshot?.strainScore ?? engine.strainScore
    }

    private var selectedDay: Date {
        Calendar.current.startOfDay(for: anchorDate)
    }

    private var loadSnapshotsKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(engine.workoutAnalytics.count)"
    }
    
    private var loadSnapshots: [WorkoutSummarySnapshot] {
        if cachedLoadSnapshotsKey == loadSnapshotsKey {
            return cachedLoadSnapshots
        }
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
        let snapshots = dailyLoadSnapshots(
            workouts: engine.workoutAnalytics,
            estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
            displayWindow: window
        )
        cachedLoadSnapshotsKey = loadSnapshotsKey
        cachedLoadSnapshots = snapshots
        return snapshots
    }

    private var selectedSnapshot: WorkoutSummarySnapshot? {
        loadSnapshots.last(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }) ?? loadSnapshots.last
    }

    private var estimatedMaxHR: Double {
        HealthStateEngine.estimateMaxHeartRateNes(age: engine.userAge)
    }

    private var loadRatioAdjustment: Double {
        guard let snapshot = selectedSnapshot else { return 0 }
        if snapshot.acwr > 1.5 { return 2.0 }
        if snapshot.acwr < 0.8 { return -1.5 }
        return 0
    }

    private var logarithmicLoad: Double {
        guard let snapshot = selectedSnapshot else { return 0 }
        return 5.0 * log10(snapshot.totalDailyLoad + 1)
    }

    private var strainChartData: [(Date, Double)] {
        loadSnapshots.map { ($0.date, $0.strainScore) }
    }
    
    var body: some View {
        let headlineStrainValue: Double = {
            switch headlineTimeFilter {
            case .day:
                return strainValue
            case .week, .month:
                return average(loadSnapshots.map(\.strainScore)) ?? strainValue
            }
        }()
        let dailyStrainState = strainClassification(for: strainValue)
        let periodStrainConsistencyState = strainConsistencyClassification(for: loadSnapshots.map(\.strainScore))
        let headlineStrainState: (title: String, color: Color) = {
            switch headlineTimeFilter {
            case .day:
                return (dailyStrainState.title, dailyStrainState.color)
            case .week, .month:
                return (periodStrainConsistencyState.title, periodStrainConsistencyState.color)
            }
        }()
        HealthCard(
            symbol: "flame.fill",
            title: "Strain",
            value: String(Int(headlineStrainValue.rounded())),
            unit: "/21",
            valueContext: metricValueContext(
                for: headlineTimeFilter,
                dayLabel: "today",
                aggregateKind: "avg"
            ),
            trend: "\(chartTimeFilter.rawValue) load: " + String(format: "%.1f", totalLoad),
            color: headlineStrainState.color,
            chartData: strainChartData,
            chartLabel: "Strain",
            chartUnit: "/21",
            badgeText: headlineStrainState.title,
            badgeColor: headlineStrainState.color,
            chartStatusProvider: { value in
                let state = strainClassification(for: value)
                return HealthChartStatusDescriptor(
                    title: state.title,
                    color: state.color,
                    detail: state.detail
                )
            },
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strain uses weighted heart-rate-zone load plus a small base-load term, then log-scales that day and nudges it up only when acute load clearly outruns chronic load.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if headlineTimeFilter != .day {
                        Text("For \(headlineTimeFilter.rawValue), the headline label reflects consistency based on the standard deviation of strain scores across the visible period, not the most recent day alone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let snapshot = selectedSnapshot {
                        Text("For \(selectedDay.formatted(date: .abbreviated, time: .omitted)), daily load is \(formatted(snapshot.totalDailyLoad, digits: 2)), acute/chronic ratio is \(formatted(snapshot.acwr, digits: 2)), and the final score lands at \(formatted(snapshot.strainScore, digits: 1))/21.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(
                        headlineTimeFilter == .day
                        ? "\(dailyStrainState.title) means \(dailyStrainState.detail) Strain bands are 0-5 Low, 6-10 Building, 11-14 Productive, and 15+ High."
                        : "\(periodStrainConsistencyState.title) means \(periodStrainConsistencyState.detail)"
                    )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("View more") {
                        showTechnicalSheet = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        )
        .fullScreenCover(isPresented: $showTechnicalSheet) {
            StrainScoreTechnicalSheet(
                snapshot: selectedSnapshot,
                selectedDay: selectedDay,
                estimatedMaxHR: estimatedMaxHR,
                logarithmicLoad: logarithmicLoad,
                loadRatioAdjustment: loadRatioAdjustment,
                averageLoad: averageLoad
            )
        }
    }
}

struct RecoveryScoreSection: View {
    @ObservedObject var engine: HealthStateEngine
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    @State private var showTechnicalSheet = false
    @State private var cachedRecoveryData: [(Date, Double)] = []
    @State private var cachedRecoveryDataKey: String = ""

    private var selectedDay: Date {
        Calendar.current.startOfDay(for: anchorDate)
    }

    private var recoveryDataCacheKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(engine.recoveryScore)-\(engine.latestHRV ?? 0)"
    }

    private var recoveryData: [(Date, Double)] {
        if recoveryDataCacheKey == cachedRecoveryDataKey {
            return cachedRecoveryData
        }
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
        let data = dateSequence(from: window.start, to: window.end).compactMap { day in
            recoveryScore(for: day, engine: engine).map { (day, $0) }
        }
        cachedRecoveryDataKey = recoveryDataCacheKey
        cachedRecoveryData = data
        return data
    }

    private var selectedRecoveryScore: Double {
        recoveryScore(for: selectedDay, engine: engine) ?? engine.recoveryScore
    }

    private var selectedRecoveryInputsAreInconclusive: Bool {
        selectedInputs.isInconclusive
    }

    private var isSuppressedRelativeToSevenDayAverage: Bool {
        let calendar = Calendar.current
        let priorScores = (1...7).compactMap { offset -> Double? in
            guard let sourceDay = calendar.date(byAdding: .day, value: -offset, to: selectedDay) else { return nil }
            return recoveryScore(for: sourceDay, engine: engine)
        }
        guard !priorScores.isEmpty else { return false }
        let average = priorScores.reduce(0, +) / Double(priorScores.count)
        guard average > 0 else { return false }
        return selectedRecoveryScore < (average * 0.8)
    }

    private var selectedInputs: HealthStateEngine.ProRecoveryInputs {
        let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        return HealthStateEngine.proRecoveryInputs(
            latestHRV: HealthStateEngine.smoothedValue(for: selectedDay, values: engine.effectHRV) ?? HealthStateEngine.smoothedValue(for: selectedDay, values: hrvLookup),
            restingHeartRate: HealthStateEngine.smoothedValue(for: selectedDay, values: engine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: selectedDay, values: engine.dailyRestingHeartRate),
            sleepDurationHours: HealthStateEngine.smoothedValue(for: selectedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: selectedDay, values: engine.dailySleepDuration),
            timeInBedHours: HealthStateEngine.smoothedValue(for: selectedDay, values: engine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: selectedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: selectedDay, values: engine.dailySleepDuration),
            hrvBaseline60Day: engine.hrvBaseline60Day,
            rhrBaseline60Day: engine.rhrBaseline60Day,
            sleepBaseline60Day: engine.sleepBaseline60Day,
            hrvBaseline7Day: engine.hrvBaseline7Day,
            rhrBaseline7Day: engine.rhrBaseline7Day,
            sleepBaseline7Day: engine.sleepBaseline7Day,
            bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: selectedDay)
        )
    }

    private var hrvValue: Double? {
        engine.effectHRV[selectedDay] ?? Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })[selectedDay]
    }

    private var rhrValue: Double? {
        engine.basalSleepingHeartRate[selectedDay] ?? engine.dailyRestingHeartRate[selectedDay]
    }

    private var sleepValue: Double? {
        engine.anchoredSleepDuration[selectedDay] ?? engine.dailySleepDuration[selectedDay]
    }

    private var timeInBedValue: Double? {
        engine.anchoredTimeInBed[selectedDay] ?? sleepValue
    }

    var body: some View {
        let averageRecovery = average(recoveryData.map(\.1)) ?? selectedRecoveryScore
        let headlineRecoveryValue = headlineTimeFilter == .day ? selectedRecoveryScore : averageRecovery
        let recoveryState = recoveryClassification(for: selectedRecoveryScore)
        HealthCard(
            symbol: "heart.circle.fill",
            title: "Recovery Score",
            value: selectedRecoveryInputsAreInconclusive ? "Inconclusive" : String(format: "%.0f", headlineRecoveryValue),
            unit: "/100",
            valueContext: selectedRecoveryInputsAreInconclusive
                ? nil
                : metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.0f", averageRecovery),
            color: recoveryState.color,
            chartData: recoveryData,
            chartLabel: "Recovery",
            chartUnit: "%",
            badgeText: selectedRecoveryInputsAreInconclusive ? "Effect HRV Invalid" : recoveryState.title,
            badgeColor: selectedRecoveryInputsAreInconclusive ? .red : recoveryState.color,
            chartStatusProvider: { value in
                let state = recoveryClassification(for: value)
                return HealthChartStatusDescriptor(
                    title: state.title,
                    color: state.color,
                    detail: state.detail
                )
            },
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery starts from Effect HRV, a momentum-smoothed sleep-anchored HRV signal, plus basal sleeping heart rate against your own baseline.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("For \(selectedDay.formatted(date: .abbreviated, time: .omitted)), Effect HRV z is \(selectedInputs.hrvZScore.map { formatted($0, digits: 2) } ?? "nil"), RHR penalty z is \(selectedInputs.restingHeartRatePenaltyZScore.map { formatted($0, digits: 2) } ?? "nil"), circadian penalty is \(formatted(selectedInputs.circadianPenalty, digits: 1)) points, and sleep then gates the result before the final score of \(selectedRecoveryInputsAreInconclusive ? "inconclusive" : "\(formatted(selectedRecoveryScore, digits: 1))/100").")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(recoveryState.title) means \(recoveryState.detail) Recovery bands are 90-100 Full Send, 70-89 Perform, 40-69 Adapt, and 0-39 Recover.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("View more") {
                        showTechnicalSheet = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }
        )
        .fullScreenCover(isPresented: $showTechnicalSheet) {
            RecoveryScoreTechnicalSheet(
                selectedDay: selectedDay,
                hrvValue: hrvValue,
                rhrValue: rhrValue,
                sleepValue: sleepValue,
                timeInBedValue: timeInBedValue,
                inputs: selectedInputs,
                hrvBaseline: engine.hrvBaseline60Day ?? HealthStateEngine.fallbackStats(
                    mean: engine.hrvBaseline7Day,
                    coefficientOfVariation: 0.12,
                    minimumStandardDeviation: 10
                ),
                rhrBaseline: engine.rhrBaseline60Day ?? HealthStateEngine.fallbackStats(
                    mean: engine.rhrBaseline7Day,
                    coefficientOfVariation: 0.06,
                    minimumStandardDeviation: 3
                )
            )
        }
    }
}

@MainActor
struct ReadinessScoreSection: View {
    @ObservedObject var engine: HealthStateEngine
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    @State private var cachedLoadSnapshots: [WorkoutSummarySnapshot] = []
    @State private var cachedReadinessData: [(Date, Double)] = []
    @State private var cachedReadinessDataKey: String = ""

    private var selectedDay: Date {
        Calendar.current.startOfDay(for: anchorDate)
    }

    private var readinessDataCacheKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(engine.workoutAnalytics.count)-\(engine.readinessScore)"
    }

    private var readinessData: [(Date, Double)] {
        if readinessDataCacheKey == cachedReadinessDataKey {
            return cachedReadinessData
        }
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
        let loadSnapshots = dailyLoadSnapshots(
            workouts: engine.workoutAnalytics,
            estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
            displayWindow: window
        )
        cachedLoadSnapshots = loadSnapshots
        let strainLookup = Dictionary(uniqueKeysWithValues: loadSnapshots.map { ($0.date, $0.strainScore) })
        let data = dateSequence(from: window.start, to: window.end).compactMap { day -> (Date, Double)? in
            guard let strain = strainLookup[day],
                  let recovery = recoveryScore(for: day, engine: engine),
                  let readiness = readinessScore(for: day, recoveryScore: recovery, strainScore: strain, engine: engine) else {
                return nil
            }
            return (day, readiness)
        }
        cachedReadinessDataKey = readinessDataCacheKey
        cachedReadinessData = data
        return data
    }

    private var selectedReadinessScore: Double {
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
        let loadSnapshots: [WorkoutSummarySnapshot]
        if cachedReadinessDataKey == readinessDataCacheKey && !cachedLoadSnapshots.isEmpty {
            loadSnapshots = cachedLoadSnapshots
        } else {
            loadSnapshots = dailyLoadSnapshots(
                workouts: engine.workoutAnalytics,
                estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
                displayWindow: window
            )
        }
        let selectedStrain = loadSnapshots.last(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) })?.strainScore ?? engine.strainScore
        let selectedRecovery = recoveryScore(for: selectedDay, engine: engine) ?? engine.recoveryScore
        return readinessScore(
            for: selectedDay,
            recoveryScore: selectedRecovery,
            strainScore: selectedStrain,
            engine: engine
        ) ?? engine.readinessScore
    }

    private func readinessClassification(for score: Double) -> RecoveryClassification {
        recoveryClassification(for: score)
    }

    var body: some View {
        let averageReadiness = average(readinessData.map(\.1)) ?? selectedReadinessScore
        let headlineReadiness = headlineTimeFilter == .day ? selectedReadinessScore : averageReadiness
        let readinessState = readinessClassification(for: selectedReadinessScore)

        HealthCard(
            symbol: "figure.run.circle.fill",
            title: "Readiness Score",
            value: String(format: "%.0f", headlineReadiness),
            unit: "/100",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.0f", averageReadiness),
            color: readinessState.color,
            chartData: readinessData,
            chartLabel: "Readiness",
            chartUnit: "%",
            badgeText: readinessState.title,
            badgeColor: readinessState.color,
            chartStatusProvider: { value in
                let state = readinessClassification(for: value)
                return HealthChartStatusDescriptor(
                    title: state.title,
                    color: state.color,
                    detail: state.detail
                )
            },
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Readiness blends recovery reserve, HRV trend support, and strain drag into one training-day score.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("For \(selectedDay.formatted(date: .abbreviated, time: .omitted)), readiness lands at \(formatted(selectedReadinessScore, digits: 1))/100 after recovery support and strain cost are combined.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

private struct StrainScoreTechnicalSheet: View {
    let snapshot: WorkoutSummarySnapshot?
    let selectedDay: Date
    let estimatedMaxHR: Double
    let logarithmicLoad: Double
    let loadRatioAdjustment: Double
    let averageLoad: Double
    @Environment(\.dismiss) private var dismiss

    private var currentDebugSnapshot: HealthStateEngine.StrainDebugSnapshot? {
        guard let snapshot else { return nil }
        return HealthStateEngine.debugStrainSnapshot(
            label: "Selected Day",
            acuteLoad: snapshot.acuteLoad,
            chronicLoad: snapshot.chronicLoad
        )
    }

    private var scenarioSnapshots: [HealthStateEngine.StrainDebugSnapshot] {
        [
            HealthStateEngine.debugStrainSnapshot(
                label: "Low Day",
                acuteLoad: 8,
                chronicLoad: 12
            ),
            HealthStateEngine.debugStrainSnapshot(
                label: "Building",
                acuteLoad: 24,
                chronicLoad: 24
            ),
            HealthStateEngine.debugStrainSnapshot(
                label: "Productive",
                acuteLoad: 60,
                chronicLoad: 50
            ),
            HealthStateEngine.debugStrainSnapshot(
                label: "Spike",
                acuteLoad: 120,
                chronicLoad: 60
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Strain uses heart-rate-zone weighted load, a small base-load term for normal daily stress, then a safety-valve adjustment if acute load is clearly outrunning or trailing chronic load.")
                        .font(.body)
                    Text("Max HR estimate")
                        .font(.headline)
                    Text("maxHR = max(150, 211 - 0.64 x age) = \(formatted(estimatedMaxHR, digits: 1)) bpm")
                        .foregroundColor(.secondary)
                    if let snapshot {
                        Text("Selected day")
                            .font(.headline)
                        Text("\(selectedDay.formatted(date: .abbreviated, time: .omitted)) total session load = \(formatted(snapshot.sessionLoad, digits: 2))")
                            .foregroundColor(.secondary)
                        Text("Daily load = session load + base load = \(formatted(snapshot.totalDailyLoad, digits: 2))")
                            .foregroundColor(.secondary)
                        Text("Acute load = \(formatted(snapshot.acuteLoad, digits: 2)), chronic load = \(formatted(snapshot.chronicLoad, digits: 2)), ACWR = \(formatted(snapshot.acwr, digits: 2))")
                            .foregroundColor(.secondary)
                        Text("L = 6.2 x log10(acute + 1) = 6.2 x log10(\(formatted(snapshot.acuteLoad + 1, digits: 2))) = \(formatted(logarithmicLoad, digits: 2))")
                            .foregroundColor(.secondary)
                        Text("L' = L^1.08 = \(formatted(pow(max(logarithmicLoad, 0), 1.08), digits: 2))")
                            .foregroundColor(.secondary)
                        Text("Adjustment = clamp(8 x (ratio - 1.0), -1.5, 4.5) = \(signedFormatted(loadRatioAdjustment, digits: 2))")
                            .foregroundColor(.secondary)
                        Text("Final strain applies soft cap and a +0.5 baseline lift, landing at \(formatted(snapshot.strainScore, digits: 2))/21")
                            .foregroundColor(.secondary)
                    }
                    Text("Window context")
                        .font(.headline)
                    Text("Visible-chart average effort proxy = \(formatted(averageLoad, digits: 1))")
                        .foregroundColor(.secondary)
                    Text("Debug helper")
                        .font(.headline)
                    Button("Print Debug Snapshots") {
                        printStrainDebugSnapshots()
                    }
                    .buttonStyle(.bordered)
                    if let currentDebugSnapshot {
                        debugSnapshotView(
                            currentDebugSnapshot,
                            subtitle: "Selected-day load inputs and score"
                        )
                    } else {
                        Text("Selected-day debug snapshot is unavailable until a load snapshot exists for the selected date.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(Array(scenarioSnapshots.enumerated()), id: \.offset) { _, snapshot in
                        debugSnapshotView(
                            snapshot,
                            subtitle: "Reference scenario"
                        )
                    }
                    Text("Reading guide: 0-5 Low, 6-10 Building, 11-14 Productive, and 15+ High.")
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Strain Formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func debugSnapshotView(
        _ snapshot: HealthStateEngine.StrainDebugSnapshot,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(snapshot.label): \(subtitle)")
                .font(.subheadline.weight(.semibold))
            Text("Inputs -> acute load \(formatted(snapshot.acuteLoad, digits: 2)), chronic load \(formatted(snapshot.chronicLoad, digits: 2)), ACWR \(formatted(snapshot.loadRatio, digits: 2))")
                .foregroundColor(.secondary)
            Text("Outputs -> L \(formatted(snapshot.logarithmicLoad, digits: 2)), L' \(formatted(snapshot.expandedLoad, digits: 2)), adjustment \(signedFormatted(snapshot.ratioAdjustment, digits: 2)), pre-soft-cap \(formatted(snapshot.preSoftCapScore, digits: 2)), soft-cap \(formatted(snapshot.softCappedScore, digits: 2)), final \(formatted(snapshot.finalStrainScore, digits: 2))/21")
                .foregroundColor(.secondary)
        }
    }

    private func printStrainDebugSnapshots() {
        if let currentDebugSnapshot {
            printStrainDebugSnapshot(currentDebugSnapshot)
        } else {
            print("[StrainDebug] Selected Day snapshot unavailable: no load snapshot exists for the selected date.")
        }

        scenarioSnapshots.forEach(printStrainDebugSnapshot)
    }

    private func printStrainDebugSnapshot(_ snapshot: HealthStateEngine.StrainDebugSnapshot) {
        print("""
        [StrainDebug] \(snapshot.label)
          Inputs: acute load=\(formatted(snapshot.acuteLoad, digits: 2)), chronic load=\(formatted(snapshot.chronicLoad, digits: 2)), ACWR=\(formatted(snapshot.loadRatio, digits: 2))
          Outputs: L=\(formatted(snapshot.logarithmicLoad, digits: 2)), L'=\(formatted(snapshot.expandedLoad, digits: 2)), adjustment=\(signedFormatted(snapshot.ratioAdjustment, digits: 2)), pre-soft-cap=\(formatted(snapshot.preSoftCapScore, digits: 2)), soft-cap=\(formatted(snapshot.softCappedScore, digits: 2)), final=\(formatted(snapshot.finalStrainScore, digits: 2))/21
        """)
    }
}

private struct RecoveryScoreTechnicalSheet: View {
    let selectedDay: Date
    let hrvValue: Double?
    let rhrValue: Double?
    let sleepValue: Double?
    let timeInBedValue: Double?
    let inputs: HealthStateEngine.ProRecoveryInputs
    let hrvBaseline: HealthStateEngine.RollingBaselineStats?
    let rhrBaseline: HealthStateEngine.RollingBaselineStats?
    @Environment(\.dismiss) private var dismiss

    private var currentDebugSnapshot: HealthStateEngine.RecoveryDebugSnapshot? {
        guard let hrvZ = inputs.hrvZScore, let rhrPenaltyZ = inputs.restingHeartRatePenaltyZScore else {
            return nil
        }
        return HealthStateEngine.debugRecoverySnapshot(
            label: "Selected Day",
            hrvZScore: hrvZ,
            rhrPenaltyZScore: rhrPenaltyZ,
            sleepRatio: inputs.sleepRatio ?? 1.0,
            sleepEfficiency: inputs.sleepEfficiency ?? 1.0,
            bedtimeVarianceMinutes: inputs.bedtimeVarianceMinutes ?? 0
        )
    }

    private var scenarioSnapshots: [HealthStateEngine.RecoveryDebugSnapshot] {
        [
            HealthStateEngine.debugRecoverySnapshot(
                label: "Standard",
                hrvZScore: 0.0,
                rhrPenaltyZScore: 0.0,
                sleepRatio: 1.0,
                sleepEfficiency: 0.92,
                bedtimeVarianceMinutes: 30
            ),
            HealthStateEngine.debugRecoverySnapshot(
                label: "Primed",
                hrvZScore: 0.5,
                rhrPenaltyZScore: 0.0,
                sleepRatio: 1.0,
                sleepEfficiency: 0.95,
                bedtimeVarianceMinutes: 20
            ),
            HealthStateEngine.debugRecoverySnapshot(
                label: "Tired",
                hrvZScore: -0.5,
                rhrPenaltyZScore: 0.5,
                sleepRatio: 0.875,
                sleepEfficiency: 0.88,
                bedtimeVarianceMinutes: 60
            ),
            HealthStateEngine.debugRecoverySnapshot(
                label: "Suppressed",
                hrvZScore: -1.5,
                rhrPenaltyZScore: 1.0,
                sleepRatio: 0.625,
                sleepEfficiency: 0.82,
                bedtimeVarianceMinutes: 120
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recovery uses Effect HRV, a special sleep-anchored HRV signal rather than raw daytime HRV. It uses the sleep-window median from the last 3 hours when possible, then momentum-smooths that signal across nights. Basal sleeping heart rate comes from the lowest 5-minute heart-rate average during sleep.")
                        .font(.body)
                    Text("Selected day")
                        .font(.headline)
                    Text(selectedDay.formatted(date: .abbreviated, time: .omitted))
                        .foregroundColor(.secondary)
                    Text("Inputs")
                        .font(.headline)
                    Text("Effect HRV_day = \(hrvValue.map { formatted($0, digits: 1) } ?? "nil") ms")
                        .foregroundColor(.secondary)
                    Text("RHR_day = \(rhrValue.map { formatted($0, digits: 1) } ?? "nil") bpm")
                        .foregroundColor(.secondary)
                    Text("Sleep_duration = \(sleepValue.map { formatted($0, digits: 2) } ?? "nil") h, Time_in_bed = \(timeInBedValue.map { formatted($0, digits: 2) } ?? "nil") h")
                        .foregroundColor(.secondary)
                    Text("Baselines")
                        .font(.headline)
                    Text("Effect HRV baseline mean = \(hrvBaseline.map { formatted($0.mean, digits: 1) } ?? "nil"), soft SD floor = at least 12% of mean")
                        .foregroundColor(.secondary)
                    Text("RHR baseline mean = \(rhrBaseline.map { formatted($0.mean, digits: 1) } ?? "nil"), SD = \(rhrBaseline.map { formatted(max($0.standardDeviation, 3), digits: 2) } ?? "nil")")
                        .foregroundColor(.secondary)
                    Text("Math")
                        .font(.headline)
                    Text("Z_effectHRV is computed on ln(HRV) rather than raw HRV = \(inputs.hrvZScore.map { formatted($0, digits: 2) } ?? "nil")")
                        .foregroundColor(.secondary)
                    Text("RHR penalty z = max((RHR_day - mean_rhr) / SD_rhr, 0) = \(inputs.restingHeartRatePenaltyZScore.map { formatted($0, digits: 2) } ?? "nil")")
                        .foregroundColor(.secondary)
                    Text("Sleep ratio = sleep duration / sleep goal = \(inputs.sleepRatio.map { formatted($0, digits: 2) } ?? "nil") with goal \(formatted(inputs.sleepGoalHours, digits: 2)) h")
                        .foregroundColor(.secondary)
                    Text("Sleep scalar = 0.85 + (0.15 x sleep ratio) = \(inputs.sleepScalar.map { formatted($0, digits: 2) } ?? "nil")")
                        .foregroundColor(.secondary)
                    Text("Composite X = (Z_effectHRV x 0.85) - (RHR penalty z x 0.25) = \(formatted(inputs.composite, digits: 2))")
                        .foregroundColor(.secondary)
                    Text("Base recovery = 1 / (1 + e^(-0.6 x (X + 1.6))) x 100 = \(formatted(inputs.baseRecoveryScore, digits: 2))")
                        .foregroundColor(.secondary)
                    Text("Sleep debt penalty = removed, circadian penalty = \(formatted(inputs.circadianPenalty, digits: 1)), bedtime variance = \(inputs.bedtimeVarianceMinutes.map { formatted($0, digits: 0) } ?? "nil") min")
                        .foregroundColor(.secondary)
                    Text("Sleep efficiency = \(inputs.sleepEfficiency.map { formatted($0 * 100, digits: 0) } ?? "nil")%, efficiency cap = \(inputs.efficiencyCap.map { formatted($0, digits: 0) } ?? "none")")
                        .foregroundColor(.secondary)
                    Text("Final recovery after circadian penalty, softened sleep gate, and efficiency cap = \(formatted(inputs.finalRecoveryScore, digits: 2))/100")
                        .foregroundColor(.secondary)
                    Text("Debug helper")
                        .font(.headline)
                    Button("Print Debug Snapshots") {
                        printRecoveryDebugSnapshots()
                    }
                    .buttonStyle(.bordered)
                    if let currentDebugSnapshot {
                        debugSnapshotView(
                            currentDebugSnapshot,
                            subtitle: "Selected-day normalized inputs and score"
                        )
                    } else {
                        Text("Selected-day debug snapshot is unavailable until both Effect HRV z and RHR penalty z can be computed.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(Array(scenarioSnapshots.enumerated()), id: \.offset) { _, snapshot in
                        debugSnapshotView(
                            snapshot,
                            subtitle: "Reference scenario"
                        )
                    }
                    Text("Interpretation")
                        .font(.headline)
                    Text("Recovery bands are 90-100 Full Send, 70-89 Perform, 40-69 Adapt, and 0-39 Recover. The main coaching read is whether recovery and strain are matching or mismatching, not whether one number alone is high or low.")
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Recovery Formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func debugSnapshotView(
        _ snapshot: HealthStateEngine.RecoveryDebugSnapshot,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(snapshot.label): \(subtitle)")
                .font(.subheadline.weight(.semibold))
            Text("Inputs -> HRV z \(formatted(snapshot.hrvZScore, digits: 2)), RHR penalty z \(formatted(snapshot.rhrPenaltyZScore, digits: 2)), sleep ratio \(formatted(snapshot.sleepRatio, digits: 2)), sleep efficiency \(formatted(snapshot.sleepEfficiency * 100, digits: 0))%, bedtime variance \(formatted(snapshot.bedtimeVarianceMinutes, digits: 0)) min")
                .foregroundColor(.secondary)
            Text("Outputs -> composite \(formatted(snapshot.composite, digits: 2)), base \(formatted(snapshot.baseRecoveryScore, digits: 1)), circadian penalty \(formatted(snapshot.circadianPenalty, digits: 1)), gated \(formatted(snapshot.gatedRecoveryScore, digits: 1)), cap \(snapshot.efficiencyCap.map { formatted($0, digits: 0) } ?? "none"), final \(formatted(snapshot.finalRecoveryScore, digits: 1))/100, class \(recoveryClassification(for: snapshot.finalRecoveryScore).title)")
                .foregroundColor(.secondary)
        }
    }

    private func printRecoveryDebugSnapshots() {
        if let currentDebugSnapshot {
            printRecoveryDebugSnapshot(currentDebugSnapshot)
        } else {
            print("[RecoveryDebug] Selected Day snapshot unavailable: missing Effect HRV z and/or RHR penalty z.")
        }

        scenarioSnapshots.forEach(printRecoveryDebugSnapshot)
    }

    private func printRecoveryDebugSnapshot(_ snapshot: HealthStateEngine.RecoveryDebugSnapshot) {
        print("""
        [RecoveryDebug] \(snapshot.label)
          Inputs: HRV z=\(formatted(snapshot.hrvZScore, digits: 2)), RHR penalty z=\(formatted(snapshot.rhrPenaltyZScore, digits: 2)), sleep ratio=\(formatted(snapshot.sleepRatio, digits: 2)), sleep efficiency=\(formatted(snapshot.sleepEfficiency * 100, digits: 0))%, bedtime variance=\(formatted(snapshot.bedtimeVarianceMinutes, digits: 0)) min
          Outputs: composite=\(formatted(snapshot.composite, digits: 2)), base=\(formatted(snapshot.baseRecoveryScore, digits: 1)), circadian penalty=\(formatted(snapshot.circadianPenalty, digits: 1)), gated=\(formatted(snapshot.gatedRecoveryScore, digits: 1)), cap=\(snapshot.efficiencyCap.map { formatted($0, digits: 0) } ?? "none"), final=\(formatted(snapshot.finalRecoveryScore, digits: 1))/100, class=\(recoveryClassification(for: snapshot.finalRecoveryScore).title)
        """)
    }
}

struct SleepRecoverySection: View {
    @ObservedObject var engine: HealthStateEngine
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var sleepData: [(Date, Double)] {
        let totals = engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        }
        return filteredDailyValues(totals, timeFilter: chartTimeFilter, anchorDate: anchorDate)
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
        let headlineSleep = headlineTimeFilter == .day ? latestSleep : averageSleep
        let efficiency = (engine.sleepEfficiency[activeDay] ?? 0) * 100
        HealthCard(
            symbol: "bed.double.fill",
            title: "Sleep Hours",
            value: String(format: "%.1f", headlineSleep),
            unit: "hrs",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.1f", averageSleep),
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var midpointData: [(Date, Double)] {
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
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
            timeFilter: chartTimeFilter,
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
        let latestDeviationHours = (midpointDeviationData.last?.1 ?? midpointDeviationMinutes) / 60
        let latestConsistencyScore: Double = {
            let best = 0.25
            let worst = 3.0
            let clamped = min(max(latestDeviationHours, best), worst)
            return ((worst - clamped) / (worst - best)) * 100
        }()
        let headlineConsistencyValue = headlineTimeFilter == .day ? latestConsistencyScore : consistencyScore
        HealthCard(
            symbol: "moon.zzz.fill",
            title: "Sleep Consistency",
            value: String(format: "%.0f", headlineConsistencyValue),
            unit: "%",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "score"),
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var sleepHeartRateData: [(Date, Double)] {
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
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
        let headlineSleepHR = headlineTimeFilter == .day ? latestSleepHR : averageSleepHR
        
        HealthCard(
            symbol: "heart.text.square.fill",
            title: "Sleep HR",
            value: String(format: "%.0f", headlineSleepHR),
            unit: "bpm",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.0f", averageSleepHR),
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var hrvData: [(Date, Double)] {
        let values = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        return filteredDailyValues(values, timeFilter: chartTimeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let latestHRV = hrvData.last?.1 ?? 0
        let averageHRV = average(hrvData.map(\.1)) ?? 0
        let headlineHRV = headlineTimeFilter == .day ? latestHRV : averageHRV
        HealthCard(
            symbol: "waveform.path.ecg",
            title: "HRV",
            value: String(format: "%.0f", headlineHRV),
            unit: "ms",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.0f", averageHRV),
            color: .purple,
            chartData: hrvData,
            chartLabel: "HRV",
            chartUnit: "ms",
            badgeText: "Raw",
            badgeColor: .purple,
            expandedContent: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This is raw HRV within the selected window, not the special Effect HRV signal used for recovery scoring.")
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var rhrData: [(Date, Double)] {
        filteredDailyValues(engine.dailyRestingHeartRate, timeFilter: chartTimeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let latestRHR = rhrData.last?.1 ?? engine.restingHeartRate ?? 0
        let averageRHR = average(rhrData.map(\.1)) ?? engine.rhrBaseline7Day ?? 0
        let headlineRHR = headlineTimeFilter == .day ? latestRHR : averageRHR
        
        HealthCard(
            symbol: "heart.fill",
            title: "RHR",
            value: String(format: "%.0f", headlineRHR),
            unit: "bpm",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.0f", averageRHR),
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
    var onSelectionChange: ((Date) -> Void)? = nil

    @State private var interactionSelectedDate: Date? = nil

    private var effectiveSelectedDate: Date? {
        interactionSelectedDate ?? selectedDate ?? snapshots.last?.date
    }

    private var selectedSnapshot: WorkoutContributionsSection.DailyLoadSnapshot? {
        guard let effectiveSelectedDate else { return snapshots.last }
        return snapshots.first(where: { Calendar.current.isDate($0.date, inSameDayAs: effectiveSelectedDate) }) ?? snapshots.last
    }

    private func rangeColor(for snapshot: WorkoutContributionsSection.DailyLoadSnapshot) -> Color {
        snapshot.baselineIsReliable ? .green : .gray
    }

    private func syncSelection(to date: Date) {
        interactionSelectedDate = date
        onSelectionChange?(date)
    }

    private func updateSelection(
        from location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard let xPosition = ChartInteractionSmoothing.clampedXPosition(
            for: location,
            plotFrame: plotFrame
        ) else {
            return
        }

        let resolvedDate = proxy.value(atX: xPosition) as Date?
            ?? ChartInteractionSmoothing.fallbackBoundaryDate(
                for: xPosition,
                plotFrame: plotFrame,
                data: snapshots.map { ($0.date, $0.acuteLoad) }
            )

        guard let resolvedDate,
              let closest = snapshots.min(by: {
                  abs($0.date.timeIntervalSince1970 - resolvedDate.timeIntervalSince1970) <
                  abs($1.date.timeIntervalSince1970 - resolvedDate.timeIntervalSince1970)
              }) else {
            return
        }

        if interactionSelectedDate == nil || !Calendar.current.isDate(interactionSelectedDate!, inSameDayAs: closest.date) {
            syncSelection(to: closest.date)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    var body: some View {
        Chart {
            ForEach(snapshots) { snapshot in
                AreaMark(
                    x: .value("Date", snapshot.date),
                    yStart: .value("Sweet Spot Low", snapshot.sweetSpotLower),
                    yEnd: .value("Sweet Spot High", snapshot.sweetSpotUpper)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [
                            rangeColor(for: snapshot).opacity(isExpanded ? 0.20 : 0.13),
                            rangeColor(for: snapshot).opacity(isExpanded ? 0.12 : 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(snapshots) { snapshot in
                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Sweet Spot High Glow", snapshot.sweetSpotUpper)
                )
                .foregroundStyle(rangeColor(for: snapshot).opacity(isExpanded ? 0.15 : 0.10))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: isExpanded ? 10 : 7, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Sweet Spot Low Glow", snapshot.sweetSpotLower)
                )
                .foregroundStyle(rangeColor(for: snapshot).opacity(isExpanded ? 0.15 : 0.10))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: isExpanded ? 10 : 7, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Sweet Spot High", snapshot.sweetSpotUpper)
                )
                .foregroundStyle(rangeColor(for: snapshot).opacity(isExpanded ? 0.52 : 0.38))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: isExpanded ? 2.2 : 1.7, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value("Date", snapshot.date),
                    y: .value("Sweet Spot Low", snapshot.sweetSpotLower)
                )
                .foregroundStyle(rangeColor(for: snapshot).opacity(isExpanded ? 0.52 : 0.38))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: isExpanded ? 2.2 : 1.7, lineCap: .round, lineJoin: .round))

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
            
            if let selected = selectedSnapshot {
                RuleMark(x: .value("Selected Day", selected.date))
                    .foregroundStyle(Color.primary.opacity(0.22))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Date", selected.date),
                    y: .value("Acute Load", selected.acuteLoad)
                )
                .foregroundStyle(acuteColor)
                .symbolSize(isExpanded ? 90 : 45)

                if isExpanded {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Chronic Load", selected.chronicLoad)
                    )
                    .foregroundStyle(Color.gray)
                    .symbolSize(72)
                    .annotation(position: .top, alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold))
                            Text("Acute \(formatted(selected.acuteLoad, digits: 1)) • Chronic \(formatted(selected.chronicLoad, digits: 1))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(acuteColor.opacity(0.18), lineWidth: 1)
                        )
                    }
                }
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
        .chartOverlay { proxy in
            if isExpanded {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(from: value.location, proxy: proxy, geometry: geo)
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateSelection(from: location, proxy: proxy, geometry: geo)
                            case .ended:
                                break
                            }
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 22 : 16, style: .continuous))
        .compositingGroup()
        .drawingGroup(opaque: false, colorMode: .linear)
        .onAppear {
            if interactionSelectedDate == nil, let selectedDate {
                interactionSelectedDate = selectedDate
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            if let newValue {
                interactionSelectedDate = newValue
            }
        }
    }
}

private struct WorkoutLoadChartSheet: View {
    let snapshots: [WorkoutContributionsSection.DailyLoadSnapshot]
    let status: WorkoutLoadStatus
    @Binding var chartSelectedDate: Date?

    @Environment(\.dismiss) private var dismiss

    private var selectedSnapshot: WorkoutContributionsSection.DailyLoadSnapshot? {
        guard let chartSelectedDate else { return snapshots.last }
        return snapshots.first(where: { Calendar.current.isDate($0.date, inSameDayAs: chartSelectedDate) }) ?? snapshots.last
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Load vs Baseline")
                        .font(.title.bold())
                        .foregroundColor(status.color)

                    WorkoutLoadChart(
                        snapshots: snapshots,
                        acuteColor: status.color,
                        selectedDate: chartSelectedDate,
                        isExpanded: true,
                        onSelectionChange: { chartSelectedDate = $0 }
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
                        if let selectedSnapshot {
                            Text("Selected day: \(selectedSnapshot.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text("Acute \(formatted(selectedSnapshot.acuteLoad, digits: 1)) pts/day • Chronic \(formatted(selectedSnapshot.chronicLoad, digits: 1)) pts/day • ACWR \(formatted(selectedSnapshot.acwr, digits: 2))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Training Load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if chartSelectedDate == nil {
                    chartSelectedDate = snapshots.last?.date
                }
            }
            .onDisappear {
                chartSelectedDate = nil
            }
        }
    }
}

struct WorkoutContributionsSection: View {
    @ObservedObject var engine: HealthStateEngine
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    let sportFilter: String?
    @State private var chartSelectedDate: Date? = nil
    @State private var cachedWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []
    @State private var cachedWorkoutsKey: String = ""
    
    struct DailyLoadSnapshot: Identifiable {
        let date: Date
        let sessionLoad: Double
        let totalDailyLoad: Double
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
        chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
    }
    
    private var historicalWindowStart: Date {
        Calendar.current.date(byAdding: .day, value: -27, to: displayWindow.start) ?? displayWindow.start
    }
    
    private var workoutsCacheKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(sportFilter ?? "all")-\(engine.workoutAnalytics.count)"
    }
    
    private var workoutsForComputation: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        if cachedWorkoutsKey == workoutsCacheKey {
            return cachedWorkouts
        }
        let filtered = engine.workoutAnalytics.filter { workout, _ in
            let matchesDate = workout.startDate >= historicalWindowStart && workout.startDate < displayWindow.endExclusive
            let matchesSport = sportFilter == nil || workout.workoutActivityType.name == sportFilter
            return matchesDate && matchesSport
        }
        cachedWorkoutsKey = workoutsCacheKey
        cachedWorkouts = filtered
        return filtered
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
        var activeMinutesByDay: [Date: Double] = [:]
        let loadWindowStart = calendar.date(byAdding: .day, value: -27, to: displayWindow.start) ?? displayWindow.start
        
        for (workout, analytics) in workoutsForComputation {
            let day = calendar.startOfDay(for: workout.startDate)
            let load = HealthStateEngine.proWorkoutLoad(
                for: workout,
                analytics: analytics,
                estimatedMaxHeartRate: engine.estimatedMaxHeartRate
            )
            sessionLoadByDay[day, default: 0] += load
            workoutCountByDay[day, default: 0] += 1
            activeMinutesByDay[day, default: 0] += workout.duration / 60.0
        }

        let loadDates = dateSequence(from: loadWindowStart, to: displayWindow.end)
        let orderedLoads = loadDates.map { day in
            let sessionLoad = sessionLoadByDay[day, default: 0]
            let activeMinutes = activeMinutesByDay[day, default: 0]
            return sessionLoad + HealthStateEngine.passiveDailyBaseLoad(activeMinutes: activeMinutes)
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
            let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return partial + ((sessionLoadByDay[sourceDay] ?? 0) > 0 ? 1 : 0)
            }
            let daysSinceLastWorkout = (0..<28).first(where: { offset in
                let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
                return (sessionLoadByDay[sourceDay] ?? 0) > 0
            })
            let stateIndex = loadDates.firstIndex(of: day) ?? (orderedLoads.indices.last ?? 0)
            let state = HealthStateEngine.proTrainingLoadState(loads: orderedLoads, index: stateIndex)
            
            return DailyLoadSnapshot(
                date: day,
                sessionLoad: sessionLoadByDay[day] ?? 0,
                totalDailyLoad: orderedLoads[stateIndex],
                acuteLoad: state.acuteLoad,
                acuteTotal: acuteTotal,
                chronicLoad: state.chronicLoad,
                chronicTotal: chronicTotal,
                acwr: state.acwr,
                workoutCount: workoutCountByDay[day] ?? 0,
                activeDaysLast28: activeDaysLast28,
                daysSinceLastWorkout: daysSinceLastWorkout
            )
        }
    }
    
    private var selectedSnapshot: DailyLoadSnapshot {
        let activeDate = chartSelectedDate ?? dailyLoadSnapshots.last?.date
        if let activeDate,
           let matched = dailyLoadSnapshots.last(where: { Calendar.current.isDate($0.date, inSameDayAs: activeDate) }) {
            return matched
        }

        return dailyLoadSnapshots.last ?? DailyLoadSnapshot(
            date: displayWindow.end,
            sessionLoad: 0,
            totalDailyLoad: HealthStateEngine.passiveDailyBaseLoad(),
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
                title: "Gathering Baseline",
                color: .orange,
                detail: "Training-load baseline is still calibrating. Aim for 14 active days in the last 28 before trusting ACWR-driven risk calls.",
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
                    detail: "Recent return from a break detected. Acute load will rise faster than chronic load for a while, so ACWR is being treated as calibration only.",
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
        let headlineLoad = headlineTimeFilter == .day
            ? selectedSnapshot.acuteLoad
            : (average(dailyLoadSnapshots.map(\.acuteLoad)) ?? selectedSnapshot.acuteLoad)
        HealthCard(
            symbol: "figure.strengthtraining.traditional",
            title: "Workouts",
            value: String(format: "%.0f", headlineLoad),
            unit: "load",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today avg", aggregateKind: "avg"),
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
                WorkoutLoadChartSheet(
                    snapshots: dailyLoadSnapshots,
                    status: status,
                    chartSelectedDate: $chartSelectedDate
                )
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
                    Text("Acute Load (7-day EWMA): " + String(format: "%.1f", selectedSnapshot.acuteLoad) + " pts/day")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Chronic Load (28-day EWMA): " + String(format: "%.1f", selectedSnapshot.chronicLoad) + " pts/day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Window context: last 7 days session load " + String(format: "%.0f", selectedSnapshot.acuteTotal) + " pts • last 28 days session load " + String(format: "%.0f", selectedSnapshot.chronicTotal) + " pts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if status.hidesRatio {
                        Text("ACWR is hidden while the baseline is being rebuilt and calibrated.")
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
                    Text("Acute vs Chronic (\(chartTimeFilter.rawValue))")
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
                        isExpanded: true,
                        onSelectionChange: { chartSelectedDate = $0 }
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
        .onAppear {
            if chartSelectedDate == nil {
                chartSelectedDate = dailyLoadSnapshots.last?.date
            }
        }
        .onChange(of: anchorDate) { _, _ in
            chartSelectedDate = dailyLoadSnapshots.last?.date
        }
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date

    var filteredWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let window = chartWindow(for: chartTimeFilter, anchorDate: anchorDate)
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
        guard chartTimeFilter.dayCount > 0 else { return 0 }
        return (Double(filteredWorkouts.count) / Double(chartTimeFilter.dayCount)) * 7
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
        let latestDayMinutes = minutesPerDay.last?.1 ?? 0
        let totalMinutes = minutesPerDay.map { $0.1 }.reduce(0, +)
        let headlineMinutes = headlineTimeFilter == .day ? latestDayMinutes : totalMinutes
        HealthCard(
            symbol: "calendar",
            title: "Training Schedule",
            value: String(format: "%.0f", headlineMinutes),
            unit: "min",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today total", aggregateKind: "total"),
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
                    Text("\(chartTimeFilter.rawValue) frequency: " + String(format: "%.1f", frequency) + " sessions/week")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Total minutes (\(chartTimeFilter.rawValue)): " + String(format: "%.0f", totalMinutes))
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var respArray: [(Date, Double)] {
        filteredDailyValues(engine.respiratoryRate, timeFilter: chartTimeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let current = respArray.last?.1 ?? 0
        let averageValue = average(respArray.map(\.1)) ?? 0
        let headlineValue = headlineTimeFilter == .day ? current : averageValue
        
        HealthCard(
            symbol: "lungs.fill",
            title: "Respiratory Rate",
            value: String(format: "%.1f", headlineValue),
            unit: "bpm",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.1f", averageValue),
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var tempArray: [(Date, Double)] {
        filteredDailyValues(engine.wristTemperature, timeFilter: chartTimeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let current = tempArray.last?.1 ?? 0
        let averageValue = average(tempArray.map(\.1)) ?? 0
        let headlineValue = headlineTimeFilter == .day ? current : averageValue
        
        HealthCard(
            symbol: "thermometer.medium",
            title: "Wrist Temperature",
            value: String(format: "%.2f", headlineValue),
            unit: "°C",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.2f", averageValue),
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let anchorDate: Date
    
    private var spo2Array: [(Date, Double)] {
        filteredDailyValues(engine.spO2, timeFilter: chartTimeFilter, anchorDate: anchorDate)
    }
    
    var body: some View {
        let current = spo2Array.last?.1 ?? 0
        let averageValue = average(spo2Array.map(\.1)) ?? 0
        let headlineValue = headlineTimeFilter == .day ? current : averageValue
        
        HealthCard(
            symbol: "drop.fill",
            title: "SpO₂",
            value: String(format: "%.1f", headlineValue),
            unit: "%",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "\(chartTimeFilter.rawValue) avg: " + String(format: "%.1f", averageValue),
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
            if !hasData {
                ProgressView("Loading vitals...")
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?
    let anchorDate: Date
    @State private var cachedFilteredData: [(Date, Double)] = []
    @State private var cachedKey: String = ""

    private var cacheKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(sportFilter ?? "all")-\(engine.workoutAnalytics.count)"
    }

    var filteredData: [(Date, Double)] {
        if cacheKey == cachedKey {
            return cachedFilteredData
        }
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
        let result = filteredDailyValues(base, timeFilter: chartTimeFilter, anchorDate: anchorDate)
        cachedKey = cacheKey
        cachedFilteredData = result
        return result
    }

    var body: some View {
        let latestValue = filteredData.last?.1 ?? 0
        let totalValue = filteredData.map { $0.1 }.reduce(0, +)
        let headlineValue = headlineTimeFilter == .day ? latestValue : totalValue
        HealthCard(
            symbol: "flame.fill",
            title: "Daily MET-minutes",
            value: String(format: "%.1f", headlineValue),
            unit: "MET-min",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today total", aggregateKind: "total"),
            trend: "Total: \(String(format: "%.1f", totalValue))",
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
                        Text("\(chartTimeFilter.rawValue) avg: " + String(format: "%.1f", averageValue) + " MET-min/day")
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?
    let anchorDate: Date
    @State private var cachedFilteredData: [(Date, Double)] = []
    @State private var cachedKey: String = ""

    private var cacheKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(sportFilter ?? "all")-\(engine.workoutAnalytics.count)"
    }

    var filteredData: [(Date, Double)] {
        if cacheKey == cachedKey {
            return cachedFilteredData
        }
        var base = engine.dailyVO2Aggregates
        if let sport = sportFilter {
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
        let result = filteredDailyValues(base, timeFilter: chartTimeFilter, anchorDate: anchorDate)
        cachedKey = cacheKey
        cachedFilteredData = result
        return result
    }

    var body: some View {
        let latestValue = filteredData.last?.1 ?? 0
        let averageValue = average(filteredData.map(\.1)) ?? latestValue
        let headlineValue = headlineTimeFilter == .day ? latestValue : averageValue
        HealthCard(
            symbol: "lungs.fill",
            title: "Daily VO2 Max",
            value: String(format: "%.1f", headlineValue),
            unit: "ml/kg/min",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
            trend: "Avg: \(averageValue.formatted())",
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
                        Text("\(chartTimeFilter.rawValue) avg: " + String(format: "%.1f", averageValue) + " ml/kg/min")
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
    let headlineTimeFilter: StrainRecoveryView.TimeFilter
    let chartTimeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?
    let anchorDate: Date
    @State private var cachedFilteredData: [(Date, Double)] = []
    @State private var cachedKey: String = ""

    private var cacheKey: String {
        "\(chartTimeFilter.rawValue)-\(anchorDate.timeIntervalSince1970)-\(sportFilter ?? "all")-\(engine.workoutAnalytics.count)"
    }

    var filteredData: [(Date, Double)] {
        if cacheKey == cachedKey {
            return cachedFilteredData
        }
        var base = engine.dailyHRRAggregates
        if let sport = sportFilter {
            let filteredWorkouts = engine.workoutAnalytics.filter { $0.workout.workoutActivityType.name == sport }
            var aggregates: [Date: Double] = [:]
            let calendar = Calendar.current
            let resting = CoachHRRRestingGate.shared.current()
            let restingKey = Int(resting.rounded())
            for (workout, analytics) in filteredWorkouts {
                let day = calendar.startOfDay(for: workout.startDate)
                let result: HeartRateRecoveryResult
                if let cached = HRRAnalysisCache.shared.result(for: workout.uuid),
                   cached.restingHRUsed.map({ Int($0.rounded()) }) == Optional(restingKey) {
                    result = cached
                } else {
                    let analyzed = HeartRateRecoveryAnalysis.analyze(workout: workout, analytics: analytics, restingHRBpm: resting)
                    HRRAnalysisCache.shared.store(analyzed, workoutUUID: workout.uuid)
                    result = analyzed
                }
                if let hrr2 = HeartRateRecoveryAnalysis.trendPreferredDropBpm(result: result) {
                    aggregates[day] = max(aggregates[day] ?? 0, hrr2)
                }
            }
            base = aggregates
        }
        let result = filteredDailyValues(base, timeFilter: chartTimeFilter, anchorDate: anchorDate)
        cachedKey = cacheKey
        cachedFilteredData = result
        return result
    }

    var body: some View {
        let latestValue = filteredData.last?.1 ?? 0
        let averageValue = average(filteredData.map(\.1)) ?? latestValue
        let headlineValue = headlineTimeFilter == .day ? latestValue : averageValue
        HealthCard(
            symbol: "heart.fill",
            title: "Daily HRR (2min)",
            value: String(format: "%.0f", headlineValue),
            unit: "bpm",
            valueContext: metricValueContext(for: headlineTimeFilter, dayLabel: "today", aggregateKind: "avg"),
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
                        Text("\(chartTimeFilter.rawValue) avg: " + String(format: "%.0f", averageValue) + " bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Max day in window: " + String(format: "%.0f", maxValue) + " bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("HRR (2 min) uses the refined stop anchor: smoothed peak in the final minute before the detected end of effort minus smoothed HR about 2 minutes later.")
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
