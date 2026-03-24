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
        .sheet(isPresented: $showSheet) {
            HealthLineChartSheet(data: data, label: label, unit: unit, color: color)
        }
    }
}

// Main technical view for strain/recovery analytics

struct StrainRecoveryView: View {
    @StateObject private var engine = HealthStateEngine.shared
    @StateObject private var aggressiveCachingController = StrainRecoveryAggressiveCachingController.shared
    @State private var animationPhase: Double = 0

    enum TimeFilter: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
    }

    @State private var timeFilter: TimeFilter = .week
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
    
    private func jumpToToday() {
        selectedDate = Date()
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                    // Time and Sport Filters
                    HStack {
                        HStack(spacing: 8) {
                            ForEach(Array(TimeFilter.allCases.enumerated()), id: \.element) { index, filter in
                                Button {
                                    selectTimeFilter(filter)
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(timeFilter == filter ? .accentColor : .gray.opacity(0.35))
                            }
                        }
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

                        StrainRecoveryAISummarySection(
                            engine: engine,
                            timeFilter: timeFilter,
                            sportFilter: sportFilter,
                            anchorDate: selectedDate,
                            aggressiveCachingController: aggressiveCachingController
                        )

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
                        .frame(maxWidth: max(0, geometry.size.width - 32), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .allowsHitTesting(!aggressiveCachingController.isActive)
                    .blur(radius: aggressiveCachingController.isActive ? 3 : 0)

                    if aggressiveCachingController.isActive {
                        aggressiveCachingOverlay
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
            .sheet(isPresented: $showingSummarySettings) {
                StrainRecoverySummarySettingsView(
                    engine: engine,
                    aggressiveCachingController: aggressiveCachingController
                )
            }
        }
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

        let plan = aggressiveCachingPlan()
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
        if shouldContinueAggressiveCachingInBackground() {
            scheduleBackgroundProcessingIfNeeded()
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
            if markAggressiveCachingRequestedIfWorkRemains() {
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
        guard shouldContinueAggressiveCachingInBackground() else {
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
                if self?.markAggressiveCachingRequestedIfWorkRemains() == true {
                    self?.scheduleBackgroundProcessingIfNeeded()
                }
            }
        }

        Task { @MainActor in
            await self.startIfNeeded()
        }
    }
#endif

    private func hasRemainingAggressiveCachingWork() -> Bool {
        aggressiveCachingPlan().pendingBatches.isEmpty == false
    }

    @discardableResult
    private func markAggressiveCachingRequestedIfWorkRemains() -> Bool {
        let stillHasWork = hasRemainingAggressiveCachingWork()
        markAggressiveCachingRequested(stillHasWork)
        return stillHasWork
    }

    private func shouldContinueAggressiveCachingInBackground() -> Bool {
        let settings = StrainRecoverySummaryPersistence.loadSyncSettings()
        return settings.aggressiveCachingRequested && hasRemainingAggressiveCachingWork()
    }

    private func markAggressiveCachingRequested(_ requested: Bool) {
        var settings = StrainRecoverySummaryPersistence.loadSyncSettings()
        settings.aggressiveCachingRequested = requested
        settings.intensiveFetchingEnabled = false
        StrainRecoverySummaryPersistence.saveSyncSettings(settings)
    }

    private func scheduleBackgroundProcessingIfNeeded() {
#if canImport(BackgroundTasks)
        guard shouldContinueAggressiveCachingInBackground() else { return }

        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The foreground task is already running or queued. Failing to submit a background request
            // should not interrupt the current aggressive caching run.
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
    case fullMonth
    case selectedDate
    case reportType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullMonth:
            return "Past Month"
        case .selectedDate:
            return "Single Date"
        case .reportType:
            return "Single Report Type"
        }
    }
}

private struct AggressiveSyncSelection {
    let mode: AggressiveSyncSelectionMode
    let selectedDate: Date
    let selectedSuggestionID: String?
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
private func aggressiveCachingPlan() -> StrainRecoveryAggressiveCachingPlan {
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
    let calendar = Calendar.current
    let selection = AggressiveSyncSelection(
        mode: settings.aggressiveSyncSelectionMode,
        selectedDate: settings.aggressiveSyncSelectedDate,
        selectedSuggestionID: settings.aggressiveSyncSelectedSuggestionID
    )
    var batches: [StrainRecoveryAggressiveCachingDayBatch] = []
    var completedBatchCount = 0

    for dayOffset in 0..<28 {
        guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
        if selection.mode == .selectedDate,
           calendar.startOfDay(for: selection.selectedDate) != calendar.startOfDay(for: date) {
            continue
        }
        var pendingRequests: [StrainRecoverySummaryRequest] = []
        var seen = Set<String>()

        for filter in StrainRecoveryView.TimeFilter.allCases {
            let suggestions = SummarySuggestion.buildSuggestions(
                engine: HealthStateEngine.shared,
                timeFilter: filter,
                sportFilter: nil,
                anchorDate: date
            )

            for suggestion in suggestions {
                if selection.mode == .reportType,
                   suggestion.id != selection.selectedSuggestionID {
                    continue
                }
                let request = StrainRecoverySummaryRequest.build(
                    engine: HealthStateEngine.shared,
                    timeFilter: filter,
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
            let session = LanguageModelSession(
                model: model,
                instructions: strainRecoveryModelInstructions
            )
            let cleaned = try await generateValidatedAggressiveCachingSummary(
                session: session,
                prompt: promptWithSiblingTimeFilterContext(for: request, cache: cache)
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
    session: LanguageModelSession,
    prompt: String
) async throws -> String {
    let maxAttempts = 3

    for _ in 0..<maxAttempts {
        let response = try await session.respond(to: prompt)
        let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, !looksLikeInvalidAggressiveCachingSummary(cleaned) {
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

    return suspiciousPhrases.contains(where: normalized.contains)
}

private let strainRecoveryModelInstructions = """
You are an AI Athletic Coach. Analyze the provided health data through the Equalizer Framework. Your goal is to identify how Strain and Recovery are balancing. Look for trends where metrics move in tandem or diverge. If vitals are within normal range, simply state they are Stable. Only call out specific vitals if they deviate from the athlete's norm. Speak directly to the athlete. Do not summarize, coach.
Your tone is direct, motivating, and professional.
Never refer to the athlete in the third person. Use You and Your.
Focus on actionable coaching, not generic explanation.
If strain and recovery rise together, recognize the athlete for matching recovery to load.
If heart rate recovery falls while strain or training load are above optimal, flag a possible overreach pattern.
Follow the selected report type strictly and do not drift into unrelated categories.
Use supporting metrics only when they directly strengthen the chosen focus.
Treat each report type like a distinct coaching mode with its own reasoning style and vocabulary.
Respect explicit ignore lists as hard constraints unless a forbidden topic is truly required for causal explanation.
Do not reuse the same generic paragraph structure across different report types.
Strain is a training-load/stress score, where higher usually means more accumulated recent load. Recovery is a recovery-readiness score, where higher is better.
Never describe strain near 20/100 as high. That is low strain in this app's logic.
Never describe recovery near 80/100 as a problem by itself. That is strong recovery in this app's logic.
A low strain score paired with a high recovery score is usually a positive fresh-state pattern unless the selected focus specifically suggests undertraining.
Keep the output plain text, no bullets, no markdown, and about 150 to 260 words.
"""

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

private func summaryRequestID(
    timeFilter: StrainRecoveryView.TimeFilter,
    scopedSport: String?,
    anchorDate: Date,
    suggestionID: String
) -> String {
    let selectedDay = Calendar.current.startOfDay(for: anchorDate)
    return [
        "strain-recovery-ai-v7",
        timeFilter.rawValue,
        scopedSport ?? "all",
        String(selectedDay.timeIntervalSince1970),
        suggestionID
    ].joined(separator: "|")
}

private func siblingTimeFilterContexts(
    for request: StrainRecoverySummaryRequest,
    cache: [String: StrainRecoverySummaryCacheEntry]
) -> [CrossFilterSummaryContext] {
    StrainRecoveryView.TimeFilter.allCases.compactMap { filter in
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
    guard !request.prompt.isEmpty else { return request.prompt }

    let siblings = siblingTimeFilterContexts(for: request, cache: cache)
    guard !siblings.isEmpty else { return request.prompt }

    let contextBlock = siblings
        .map { sibling in
            "- \(sibling.timeFilter.rawValue): \(sibling.summaryText)"
        }
        .joined(separator: "\n")

    return """
    \(request.prompt)

    Cross-filter context for the same report and anchor date
    \(contextBlock)

    Context stitching rules
    - Keep the \(request.timeFilter.rawValue) view as the primary lens.
    - Reconcile any tension with the sibling summaries by explicitly framing the different time horizons rather than contradicting them.
    - Treat the day, week, and month as one connected training story around the same anchor date.
    - If the horizons point in different directions, explain why that can still be true at the same time.
    """
}

private struct StrainRecoverySummarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine: HealthStateEngine
    @State private var settings = StrainRecoverySummaryPersistence.loadSyncSettings()
    @State private var temporarySelection: TemporaryPrimarySelection = .off
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
                    Toggle("Use This Device As Default Primary", isOn: Binding(
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
                            if newValue == .reportType, settings.aggressiveSyncSelectedSuggestionID == nil {
                                settings.aggressiveSyncSelectedSuggestionID = SummarySuggestion.defaultSuggestion.id
                            }
                            StrainRecoverySummaryPersistence.saveSyncSettings(settings)
                        }
                    )) {
                        ForEach(AggressiveSyncSelectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if settings.aggressiveSyncSelectionMode == .selectedDate {
                        DatePicker(
                            "Sync Date",
                            selection: syncSelectionDateBinding,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }

                    if settings.aggressiveSyncSelectionMode == .reportType {
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

                    Text("Runs immediately on the current primary Apple Intelligence device. Progress advances one day-batch at a time, and each generated summary is stored and synced before the next one begins so the run can resume later without losing completed work.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if settings.aggressiveSyncSelectionMode == .selectedDate {
                        Text("This scope syncs every report across 1D, 1W, and 1M for \(settings.aggressiveSyncSelectedDate.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if settings.aggressiveSyncSelectionMode == .reportType {
                        Text("This scope syncs \(selectedAggressiveSuggestion.title) across the past month, including all 1D, 1W, and 1M versions for each day.")
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
    @State private var requestedRequestID: String? = nil
    @State private var backgroundGenerationContextID: String? = nil
    @State private var backgroundFetchStatusText: String? = nil
    @State private var cacheSnapshot = StrainRecoverySummaryPersistence.load()
    @State private var syncSettingsSnapshot = StrainRecoverySummaryPersistence.loadSyncSettings()
    @State private var suggestionsSnapshot: [SummarySuggestion] = []

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

    private var currentRequestDescriptor: String {
        let title = selectedSuggestion?.title ?? detectedIntent.displayName
        let dateText = anchorDate.formatted(date: .abbreviated, time: .omitted)
        return "\(title) for \(dateText) for \(timeFilter.rawValue)"
    }

    private var liveOperationStatusText: String? {
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
        [selectedSuggestionRequestID, summaryGenerationReadiness.triggerToken].joined(separator: "|")
    }

    private var displayedSummaryBody: String {
        if displayedRequestID == selectedSuggestionRequestID,
           !summaryText.isEmpty {
            return summaryText
        }
        if !summaryGenerationReadiness.canGenerate {
            return summaryGenerationReadiness.placeholderText
        }
        if isLoading && requestedRequestID == selectedSuggestionRequestID {
            return "This coach report is still being prepared for \(selectedSuggestion?.title ?? detectedIntent.displayName). The current filter does not have a finished summary yet."
        }
        return "AI summaries are on-demand while you browse. Tap a suggestion to load \(selectedSuggestion?.title ?? detectedIntent.displayName) for this date and filter."
    }

    private var comparisonInsights: [CoachSummaryInsight] {
        CoachSummaryNLP.detectInsights(
            in: displayedSummaryBody,
            anchorDate: anchorDate,
            timeFilter: timeFilter
        )
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

    private var suggestionsContextID: String {
        [
            timeFilter.rawValue,
            sportFilter ?? "all",
            Calendar.current.startOfDay(for: anchorDate).formatted(date: .numeric, time: .omitted),
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
        suggestionsSnapshot = SummarySuggestion.buildSuggestions(
            engine: engine,
            timeFilter: timeFilter,
            sportFilter: sportFilter,
            anchorDate: anchorDate
        )
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
        statusText = "AI summaries are paused while browsing. Tap a suggestion to load one for this date and filter."
    }

    @MainActor
    @discardableResult
    private func restoreCachedSummaryIfAvailable(requestID: String) -> Bool {
        guard let entry = cacheSnapshot[requestID] else {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("AI Coach Summary")
                    .font(.title2.bold())
                Spacer()
                if shouldShowRefresh {
                    Button("Refresh") {
                        let key = selectedSuggestion?.id ?? "default"
                        refreshVersions[key, default: 0] += 1
                        Task {
                            let request = StrainRecoverySummaryRequest.build(
                                engine: engine,
                                timeFilter: timeFilter,
                                sportFilter: sportFilter,
                                anchorDate: anchorDate,
                                intentText: intentText,
                                selectedSuggestion: selectedSuggestion,
                                refreshVersion: refreshVersions[key, default: 0]
                            )
                            await generateSummary(
                                for: request,
                                forceRefresh: true,
                                requireAppleIntelligence: true,
                                allowLocalRefreshFallback: true
                            )
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                if !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Save To Journal") {
                        NotificationCenter.default.post(
                            name: .saveWorkoutReportToJournal,
                            object: SavedWorkoutReportPayload(
                                title: selectedSuggestion?.title ?? "Workout Report",
                                content: summaryText,
                                date: anchorDate
                            )
                        )
                        statusText = "Saved as a workout report in Journal."
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(filteredSuggestions.prefix(24)) { suggestion in
                    Button {
                        let request = StrainRecoverySummaryRequest.build(
                            engine: engine,
                            timeFilter: timeFilter,
                            sportFilter: sportFilter,
                            anchorDate: anchorDate,
                            intentText: suggestion.queryText,
                            selectedSuggestion: suggestion,
                            refreshVersion: refreshVersions[suggestion.id, default: 0]
                        )

                        selectedSuggestionID = suggestion.id
                        intentText = suggestion.queryText
                        requestedRequestID = nil
                        displayedRequestID = nil
                        persistedEntry = nil
                        summaryText = ""
                        selectedComparisonInsight = nil

                        if let cachedEntry = cacheSnapshot[request.requestID],
                           cachedEntry.source == .appleIntelligence {
                            persistedEntry = cachedEntry
                            summaryText = cachedEntry.summaryText
                            statusText = cachedEntry.cacheStatusText(currentDeviceID: StrainRecoverySummaryDevice.current.id)
                            displayedRequestID = cachedEntry.requestID
                            requestedRequestID = cachedEntry.requestID
                        } else {
                            Task {
                                statusText = "Loading requested report of \(suggestion.title) for \(anchorDate.formatted(date: .abbreviated, time: .omitted)) for \(timeFilter.rawValue)"
                                await generateSummary(for: request)
                            }
                        }
                    } label: {
                        let cacheState = suggestionCacheStates[suggestion.id] ?? (false, false)
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.symbol)
                                .font(.caption.weight(.bold))
                            Text(suggestion.title)
                                .font(.caption.weight(.semibold))
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
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if summaryText.isEmpty && isLoading {
                    Text("Generating new tailored response... focusing on \(selectedSuggestion?.title ?? detectedIntent.displayName).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    CoachSummaryInteractiveText(
                        text: displayedSummaryBody,
                        insights: comparisonInsights
                    ) { insight in
                        selectedComparisonInsight = insight
                    }
                    .font(.body)
                    .foregroundColor(.primary)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !comparisonInsights.isEmpty {
                    Text("Tap the highlighted coach cues to compare the linked metrics on a shared whiteboard.")
                        .font(.caption)
                        .foregroundColor(.orange)
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
        .task(id: generationTaskID) {
            refreshLocalSnapshots()
            if selectedSuggestionID == nil {
                selectedSuggestionID = suggestions.first?.id
                if intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    intentText = suggestions.first?.queryText ?? ""
                }
            }
            if !restoreCachedSummaryIfAvailable(requestID: selectedSuggestionRequestID) {
                resetSummaryForNavigation()
            }
        }
        .task(id: suggestionsContextID) {
            deferredSuggestionsRefreshTask?.cancel()
            deferredSuggestionsRefreshTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                refreshSuggestionsSnapshot()
                if selectedSuggestionID == nil || suggestions.contains(where: { $0.id == selectedSuggestionID }) == false {
                    selectedSuggestionID = suggestions.first?.id
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            refreshLocalSnapshots(forceReload: true)
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
        .onAppear {
            AppResourceCoordinator.shared.setStrainRecoveryForegroundCritical(true)
            refreshLocalSnapshots()
        }
        .onDisappear {
            AppResourceCoordinator.shared.setStrainRecoveryForegroundCritical(false)
            deferredSummaryLoadingTask?.cancel()
            deferredSuggestionsRefreshTask?.cancel()
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
            displayedRequestID = entry.requestID
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
    private func requestForCachedEntry(_ entry: StrainRecoverySummaryCacheEntry) -> StrainRecoverySummaryRequest? {
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

        return StrainRecoverySummaryRequest.build(
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
        if updateDisplayed {
            cancelBackgroundGeneration()
            requestedRequestID = request.requestID
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
            let generationPrompt = promptWithSiblingTimeFilterContext(
                for: request,
                cache: StrainRecoverySummaryPersistence.load()
            )

            guard model.isAvailable else {
                if requireAppleIntelligence {
                    guard updateDisplayed else { return }
                    if updateDisplayed {
                        let restoredAI = restorePreferredCachedSummary(
                            for: request,
                            fallbackStatus: "Apple Intelligence is unavailable on this device, and no synced AI summary was found yet. Your existing summary was kept."
                        )
                        if restoredAI || !allowLocalRefreshFallback {
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
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    You are an AI Athletic Coach. Analyze the provided health data through the Equalizer Framework. Your goal is to identify how Strain and Recovery are balancing. Look for trends where metrics move in tandem or diverge. If vitals are within normal range, simply state they are Stable. Only call out specific vitals if they deviate from the athlete's norm. Speak directly to the athlete. Do not summarize, coach.
                    Your tone is direct, motivating, and professional.
                    Never refer to the athlete in the third person. Use You and Your.
                    Focus on actionable coaching, not generic explanation.
                    If strain and recovery rise together, recognize the athlete for matching recovery to load.
                    If heart rate recovery falls while strain or training load are above optimal, flag a possible overreach pattern.
                    Follow the selected report type strictly and do not drift into unrelated categories.
                    Use supporting metrics only when they directly strengthen the chosen focus.
                    Treat each report type like a distinct coaching mode with its own reasoning style and vocabulary.
                    Respect explicit ignore lists as hard constraints unless a forbidden topic is truly required for causal explanation.
                    Do not reuse the same generic paragraph structure across different report types.
                    Strain is a training-load/stress score, where higher usually means more accumulated recent load. Recovery is a recovery-readiness score, where higher is better.
                    Never describe strain near 20/100 as high. That is low strain in this app's logic.
                    Never describe recovery near 80/100 as a problem by itself. That is strong recovery in this app's logic.
                    A low strain score paired with a high recovery score is usually a positive fresh-state pattern unless the selected focus specifically suggests undertraining.
                    Keep the output plain text, no bullets, no markdown, and about 150 to 260 words.
                    """
                )

                let cleaned = try await generateValidatedModelSummary(
                    session: session,
                    prompt: generationPrompt,
                    refreshVersion: request.refreshVersion
                )

                let resolvedSummary: String
                let resolvedStatus: String
                if cleaned.isEmpty {
                    if requireAppleIntelligence {
                        guard updateDisplayed else { return }
                        if updateDisplayed {
                            let restoredAI = restorePreferredCachedSummary(
                                for: request,
                                fallbackStatus: "Apple Intelligence did not return a usable summary, and no synced AI summary was found yet. Your existing summary was kept."
                            )
                            if restoredAI || !allowLocalRefreshFallback {
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
                if requireAppleIntelligence {
                    guard updateDisplayed else { return }
                    if updateDisplayed {
                        let restoredAI = restorePreferredCachedSummary(
                            for: request,
                            fallbackStatus: "Apple Intelligence refresh failed, and no synced AI summary was found yet. Your existing summary was kept."
                        )
                        if restoredAI || !allowLocalRefreshFallback {
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
                let restoredAI = restorePreferredCachedSummary(
                    for: request,
                    fallbackStatus: "Apple Intelligence is unavailable here, and no synced AI summary was found yet. Your existing summary was kept."
                )
                if restoredAI || !allowLocalRefreshFallback {
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
        session: LanguageModelSession,
        prompt: String,
        refreshVersion: Int
    ) async throws -> String {
        let maxAttempts = 3

        for attempt in 0..<maxAttempts {
            let retrySeedOffset = refreshVersion + attempt
            let response = try await session.respond(
                to: prompt + coachRetryInstruction(forAttempt: attempt),
                options: GenerationOptions(
                    sampling: retrySeedOffset == 0 ? .greedy : .random(top: 6, seed: UInt64(retrySeedOffset)),
                    temperature: retrySeedOffset == 0 ? 0 : min(0.6, 0.35 + (Double(attempt) * 0.08)),
                    maximumResponseTokens: 420
                )
            )

            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isJunkCoachOutput(cleaned) {
                return cleaned
            }
        }

        return ""
    }

    private func coachRetryInstruction(forAttempt attempt: Int) -> String {
        guard attempt > 0 else { return "" }
        return """

        Retry guidance:
        - The previous draft was rejected because it was repetitive, low-quality, or looped awkwardly.
        - Write one clean coaching paragraph with no repeated phrases, no filler, and no looping wording.
        - If evidence is thin, say that briefly instead of guessing.
        """
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
    ) -> Self {
        let calendar = Calendar.current
        let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
        let selectedDay = calendar.startOfDay(for: anchorDate)
        let effectiveSuggestion = selectedSuggestion ?? SummarySuggestion.defaultSuggestion
        let intent = effectiveSuggestion.intent
        let focusMode = effectiveSuggestion.focusMode
        let scopedSport = effectiveSuggestion.scopedSport ?? sportFilter

        let sleepTotals = engine.sleepStages.mapValues { stages in
            ["core", "deep", "rem", "unspecified"].compactMap { stages[$0] }.reduce(0, +)
        }

        let sleepData = filteredDailyValues(sleepTotals, timeFilter: timeFilter, anchorDate: anchorDate)
        let midpointSeries = filteredWindowSeries(
            values: engine.sleepMidpointHours,
            in: window
        )
        let sleepHRData = filteredWindowSeries(values: engine.dailySleepHeartRate, in: window)
        let rhrData = filteredDailyValues(engine.dailyRestingHeartRate, timeFilter: timeFilter, anchorDate: anchorDate)
        let hrvValues = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        let hrvData = filteredDailyValues(hrvValues, timeFilter: timeFilter, anchorDate: anchorDate)
        let respiratoryData = filteredDailyValues(engine.respiratoryRate, timeFilter: timeFilter, anchorDate: anchorDate)
        let wristTempData = filteredDailyValues(engine.wristTemperature, timeFilter: timeFilter, anchorDate: anchorDate)
        let spo2Data = filteredDailyValues(engine.spO2, timeFilter: timeFilter, anchorDate: anchorDate)
        let effortData = filteredDailyValues(engine.effortRating, timeFilter: timeFilter, anchorDate: anchorDate)
        let metData = filteredDailyValues(engine.dailyMETAggregates, timeFilter: timeFilter, anchorDate: anchorDate)
        let vo2Data = filteredDailyValues(engine.dailyVO2Aggregates, timeFilter: timeFilter, anchorDate: anchorDate)
        let hrrData = filteredDailyValues(engine.dailyHRRAggregates, timeFilter: timeFilter, anchorDate: anchorDate)

        let historicalWindowStart = calendar.date(byAdding: .day, value: -27, to: window.start) ?? window.start
        let workouts = engine.workoutAnalytics.filter { workout, _ in
            let matchesDate = workout.startDate >= historicalWindowStart && workout.startDate < window.endExclusive
            let matchesSport = scopedSport == nil || workout.workoutActivityType.name == scopedSport
            return matchesDate && matchesSport
        }

        let displayWorkouts = workouts.filter { pair in
            pair.workout.startDate >= window.start && pair.workout.startDate < window.endExclusive
        }
        let selectedDayWorkouts = displayWorkouts.filter { pair in
            calendar.isDate(pair.workout.startDate, inSameDayAs: selectedDay)
        }
        let scenario = dayScenario(
            timeFilter: timeFilter,
            selectedDayWorkouts: selectedDayWorkouts
        )
        let latestWorkoutTimestamp = engine.workoutAnalytics
            .map(\.workout.endDate.timeIntervalSince1970)
            .max()

        let loadSnapshots = dailyLoadSnapshots(
            workouts: workouts,
            displayWindow: window
        )
        let selectedSnapshot = loadSnapshots.last(where: { calendar.isDate($0.date, inSameDayAs: selectedDay) }) ?? loadSnapshots.last

        let workoutHighlights = workoutHighlights(
            displayWorkouts: displayWorkouts,
            dayCount: timeFilter.dayCount
        )

        let consistencyScore = sleepConsistencyScore(midpointSeries: midpointSeries, fallback: engine.sleepConsistency ?? 0)
        let midpointDeviationMinutes = sleepMidpointDeviationMinutes(midpointSeries: midpointSeries, fallback: engine.sleepConsistency ?? 0)
        let averageSleepEfficiency = averageSleepEfficiency(engine: engine, midpointSeries: midpointSeries)
        let sleepDebtHours = sleepDebt(
            sleepData: sleepData
        )
        let activityRecoveryGap = activityRecoverySleepGap(
            engine: engine,
            midpointSeries: midpointSeries
        )

        let displayedStrain = min(100, (average(effortData.map(\.1)) ?? 0) * 10)
        let totalLoad = effortData.map(\.1).reduce(0, +)
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

        let vitalsSummary = vitalsNormSummary(
            respiratoryData: respiratoryData,
            wristTempData: wristTempData,
            spo2Data: spo2Data
        )
        let focusedEvidence = focusedEvidenceBlock(
            focusMode: focusMode,
            scopedSport: scopedSport,
            displayWorkouts: displayWorkouts,
            workoutHighlights: workoutHighlights,
            selectedSnapshot: selectedSnapshot,
            sleepData: sleepData,
            averageSleepEfficiency: averageSleepEfficiency,
            hrvData: hrvData,
            rhrData: rhrData,
            sleepHRData: sleepHRData,
            vitalsSummary: vitalsSummary
        )

        let sportIdentityLine: String
        if let scopedSport, focusMode == .sportDeepDive {
            sportIdentityLine = "- You are acting as the athlete's dedicated \(scopedSport.capitalized) coach. Evaluate only \(scopedSport) performance and adaptation."
        } else {
            sportIdentityLine = ""
        }

        let trainingSection: String
        if focusMode == .sportDeepDive {
            trainingSection = """
            \(scopedSport.map { "- Selected sport: \($0.capitalized)" } ?? "- Selected sport: Unavailable")
            - \(scopedSport?.capitalized ?? "Sport") session count in display window: \(displayWorkouts.count)
            - \(scopedSport?.capitalized ?? "Sport") frequency normalized to weekly rate: \(formatted(workoutHighlights.sessionsPerWeek, digits: 1)) sessions/week
            - Total \(scopedSport ?? "sport") minutes: \(formatted(workoutHighlights.totalMinutes, digits: 0))
            - Longest \(scopedSport ?? "sport") workout: \(workoutHighlights.longestWorkout)
            - Highest \(scopedSport ?? "sport") session load workout: \(workoutHighlights.highestLoadWorkout)
            - Highest \(scopedSport ?? "sport") average power workout: \(workoutHighlights.highestPowerWorkout)
            - Highest \(scopedSport ?? "sport") peak HR workout: \(workoutHighlights.highestPeakHRWorkout)
            - Total \(scopedSport ?? "sport") time in HR zone 4: \(formatted(workoutHighlights.totalZone4Minutes, digits: 0)) min
            - Total \(scopedSport ?? "sport") time in HR zone 5: \(formatted(workoutHighlights.totalZone5Minutes, digits: 0)) min
            - Single-\(scopedSport ?? "sport") workout max zone 4 time: \(workoutHighlights.maxZone4Workout)
            - Single-\(scopedSport ?? "sport") workout max zone 5 time: \(workoutHighlights.maxZone5Workout)
            - Acute \(scopedSport ?? "sport") load selected day: \(formatted(selectedSnapshot?.acuteLoad ?? 0, digits: 1)) pts/day
            - Chronic \(scopedSport ?? "sport") load selected day: \(formatted(selectedSnapshot?.chronicLoad ?? 0, digits: 1)) pts/day
            - \(scopedSport?.capitalized ?? "Sport") ACWR selected day: \(formatted(selectedSnapshot?.acwr ?? 0, digits: 2))
            - \(scopedSport?.capitalized ?? "Sport") load status: \(workoutLoadStatus(for: selectedSnapshot).title)
            - \(scopedSport?.capitalized ?? "Sport") load interpretation: \(workoutLoadStatus(for: selectedSnapshot).detail)
            - Highest \(scopedSport ?? "sport") MET day: \(bestDayDescription(for: metData, unit: "MET-min", digits: 1))
            - Highest \(scopedSport ?? "sport") VO2 day: \(bestDayDescription(for: vo2Data, unit: "ml/kg/min", digits: 1))
            - Highest \(scopedSport ?? "sport") HRR day: \(bestDayDescription(for: hrrData, unit: "bpm", digits: 0))
            """
        } else {
            trainingSection = """
            - Workout count in display window: \(displayWorkouts.count)
            - Workout frequency normalized to weekly rate: \(formatted(workoutHighlights.sessionsPerWeek, digits: 1)) sessions/week
            - Total training minutes: \(formatted(workoutHighlights.totalMinutes, digits: 0))
            - Most frequent sport: \(workoutHighlights.mostFrequentSport ?? "Unavailable")
            - Sport with the most total minutes: \(workoutHighlights.favoriteSport ?? "Unavailable")
            - Longest workout: \(workoutHighlights.longestWorkout)
            - Highest session load workout: \(workoutHighlights.highestLoadWorkout)
            - Highest average power workout: \(workoutHighlights.highestPowerWorkout)
            - Highest peak HR workout: \(workoutHighlights.highestPeakHRWorkout)
            - Total time in HR zone 4: \(formatted(workoutHighlights.totalZone4Minutes, digits: 0)) min
            - Total time in HR zone 5: \(formatted(workoutHighlights.totalZone5Minutes, digits: 0)) min
            - Single-workout max zone 4 time: \(workoutHighlights.maxZone4Workout)
            - Single-workout max zone 5 time: \(workoutHighlights.maxZone5Workout)
            - Acute load selected day: \(formatted(selectedSnapshot?.acuteLoad ?? 0, digits: 1)) pts/day
            - Chronic load selected day: \(formatted(selectedSnapshot?.chronicLoad ?? 0, digits: 1)) pts/day
            - ACWR selected day: \(formatted(selectedSnapshot?.acwr ?? 0, digits: 2))
            - Load status: \(workoutLoadStatus(for: selectedSnapshot).title)
            - Load interpretation: \(workoutLoadStatus(for: selectedSnapshot).detail)
            - Highest MET day: \(bestDayDescription(for: metData, unit: "MET-min", digits: 1))
            - Highest VO2 day: \(bestDayDescription(for: vo2Data, unit: "ml/kg/min", digits: 1))
            - Highest HRR day: \(bestDayDescription(for: hrrData, unit: "bpm", digits: 0))
            """
        }

        let sleepSection = focusMode == .sportDeepDive ? "" : """
        Sleep
        - Latest sleep duration: \(formatted(sleepData.last?.1 ?? 0, digits: 1)) h
        - Average sleep duration: \(formatted(average(sleepData.map(\.1)) ?? 0, digits: 1)) h
        - Longest sleep night: \(bestDayDescription(for: sleepData, unit: "h", digits: 1))
        - Sleep consistency score: \(formatted(consistencyScore, digits: 0))%
        - Sleep midpoint deviation: \(formatted(midpointDeviationMinutes, digits: 0)) min
        - Average sleep efficiency: \(formatted(averageSleepEfficiency, digits: 0))%
        - Sleep debt versus prior baseline: \(formatted(sleepDebtHours, digits: 1)) h
        - Recovery day minus training day sleep gap: \(signedFormatted(activityRecoveryGap, digits: 1)) h
        """

        let recoverySection = focusMode == .sportDeepDive ? "" : """
        Recovery and vitals
        - HRV: \(seriesSummary(hrvData, unit: "ms", digits: 0))
        - Resting heart rate: \(seriesSummary(rhrData, unit: "bpm", digits: 0))
        - Sleep heart rate: \(seriesSummary(sleepHRData, unit: "bpm", digits: 0))
        - Respiratory rate: \(seriesSummary(respiratoryData, unit: "breaths/min", digits: 1))
        - Wrist temperature: \(seriesSummary(wristTempData, unit: "C", digits: 2))
        - SpO2: \(seriesSummary(spo2Data, unit: "%", digits: 1))
        - Vital norms summary: \(vitalsSummary)
        """

        let prompt = insufficiencyReason == nil ? """
        Coach me directly as an athletic performance coach using the Equalizer Framework.

        Window
        - Filter: \(timeFilter.rawValue) view
        - Anchor date: \(anchorDate.formatted(date: .abbreviated, time: .omitted))
        - Sport filter: \(scopedSport ?? "All Sports")
        - Report title: \(effectiveSuggestion.title)
        - Intent focus: \(intent.promptFocus)
        - Analysis scenario: \(scenario)
        - Focus mode: \(focusMode.rawValue)
        - Focus rules: \(focusMode.promptRules)
        - Suggestion-specific directive: \(effectiveSuggestion.promptInstructions)
        - Analytical framework: \(effectiveSuggestion.analyticalFramework)
        - Ignore list: \(effectiveSuggestion.negativeConstraints)
        - Language style: \(effectiveSuggestion.languageStyle)
        - Refresh generation: \(refreshVersion)
        - If refresh generation is greater than 0, produce a genuinely fresh angle for the same focus and avoid reusing the same opening or evidence ordering.
        - Treat this selected report as its own mini-app. Stay in its lane and do not collapse back into a general summary.
        - If a topic appears on the ignore list, do not mention it unless it is strictly necessary to explain the selected focus.
        - Pick a reasoning frame that matches the selected report and keep the entire answer inside that frame.
        \(sportIdentityLine)

        Focused evidence
        \(focusedEvidence)

        Scores
        - Displayed strain score: \(formatted(displayedStrain, digits: 0))/100
        - Recovery score: \(formatted(engine.recoveryScore, digits: 0))/100
        - Readiness score: \(formatted(engine.readinessScore, digits: 0))/100
        - Window total effort load: \(formatted(totalLoad, digits: 1))

        Training load and workouts
        \(trainingSection)

        \(sleepSection)

        \(recoverySection)

        Interpretation rules
        - Strain is load/stress. Higher means more accumulated recent load.
        - Recovery is readiness/recovery reserve. Higher is better.
        - Approximate strain reading guide for this app: 0-30 low, 31-60 moderate, 61-80 high, 81-100 very high.
        - Approximate recovery reading guide for this app: 0-30 suppressed, 31-60 mixed, 61-100 strong.
        - Higher HRV is generally favorable for recovery.
        - Lower resting heart rate and lower sleep heart rate are generally favorable for recovery.
        - If strain and recovery both rise, recognize that synergy.
        - If heart rate recovery drops while acute load or strain are above optimal, flag a possible overreach pattern.
        - If sleep debt is elevated or sleep consistency is poor, connect that to readiness and recovery quality.
        - Keep vitals as Stable or Baseline unless there is a meaningful outlier.
        - A low strain score with a high recovery score is usually a fresh or well-recovered state, not a mismatch problem.
        - Prioritize coaching based on this intent: \(intent.promptInstruction)
        - Distinguish this report from other filters through both content selection and vocabulary.
        - Avoid repeating the same stock explanation patterns across different filters.
        """
        : ""

        let fallbackSummary = insufficiencyReason
            ?? localFallbackSummary(
                displayedStrain: displayedStrain,
                recoveryScore: engine.recoveryScore,
                readinessScore: engine.readinessScore,
                workoutHighlights: workoutHighlights,
                selectedSnapshot: selectedSnapshot,
                scenario: scenario,
                intent: intent,
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
            "strain-recovery-ai-v7",
            timeFilter.rawValue,
            scopedSport ?? "all",
            String(selectedDay.timeIntervalSince1970),
            effectiveSuggestion.id
        ].joined(separator: "|")

        let expiresAt = summaryExpirationDate(
            anchorDate: selectedDay,
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
            anchorDate: selectedDay,
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
        aggressiveSyncSelectionMode: .fullMonth,
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
        aggressiveSyncSelectionMode = try container.decodeIfPresent(AggressiveSyncSelectionMode.self, forKey: .aggressiveSyncSelectionMode) ?? .fullMonth
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
            return "Coach through the lens of the selected discipline and the demands of that sport."
        case .intensityLoad:
            return "Prioritize VO2 max, load optimality, acute versus chronic balance, and whether to push or pull back."
        case .recoveryVitals:
            return "Prioritize sleep architecture, biometric recovery, and whether the athlete is absorbing training well."
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

    static let defaultSuggestion = SummarySuggestion(
        id: "overall",
        title: "Overall Coaching",
        queryText: "overall coaching on strain and recovery balance",
        symbol: "sparkles",
        intent: .general,
        focusMode: .general,
        scopedSport: nil,
        promptInstructions: "Synthesize the selected period into one high-level narrative. Avoid lists. Bridge the gap between effort and restoration.",
        analyticalFramework: "Use a whole-system coaching lens. Find the main tension between load and restoration, then explain what that means next.",
        negativeConstraints: "Do not break the report into category-by-category recitation and do not dump every metric that exists.",
        languageStyle: "Sound like an executive performance briefing with one central thesis."
    )

    @MainActor
    static func buildSuggestions(
        engine: HealthStateEngine,
        timeFilter: StrainRecoveryView.TimeFilter,
        sportFilter: String?,
        anchorDate: Date
    ) -> [SummarySuggestion] {
        let calendar = Calendar.current
        let window = chartWindow(for: timeFilter, anchorDate: anchorDate)
        let last30 = calendar.date(byAdding: .day, value: -29, to: window.end) ?? window.end
        let last365 = calendar.date(byAdding: .day, value: -364, to: window.end) ?? window.end

        let workouts30 = engine.workoutAnalytics.filter {
            $0.workout.startDate >= last30 && $0.workout.startDate < window.endExclusive
        }
        let workouts365 = engine.workoutAnalytics.filter {
            $0.workout.startDate >= last365 && $0.workout.startDate < window.endExclusive
        }

        let grouped30 = Dictionary(grouping: workouts30, by: { $0.workout.workoutActivityType.name })
        let grouped365 = Dictionary(grouping: workouts365, by: { $0.workout.workoutActivityType.name })

        var suggestions: [SummarySuggestion] = [
            .init(id: "overall", title: "Overall Coaching", queryText: "overall balance", symbol: "sparkles", intent: .general, focusMode: .general, scopedSport: nil, promptInstructions: "Synthesize the period into one high-level narrative. Avoid lists. Bridge the gap between effort and restoration.", analyticalFramework: "Use a whole-system coaching lens and identify the single most important balance story.", negativeConstraints: "Do not break the answer into metric buckets and do not recite raw stats line by line.", languageStyle: "Use concise executive-coach language with one thesis and one implication."),
            .init(id: "recovery", title: "Recovery Focus", queryText: "recovery absorption", symbol: "heart.circle", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep, scopedSport: nil, promptInstructions: "Focus on how well your body is absorbing training. Ignore workout specifics unless they explain a recovery failure.", analyticalFramework: "Treat recovery as the body's ability to absorb stress and turn work into adaptation.", negativeConstraints: "Ignore workout-by-workout details, zone totals, and sport counts unless they clearly explain suppressed recovery.", languageStyle: "Sound like a readiness coach interpreting whether the system is absorbing load or not."),
            .init(id: "recovery-vitals", title: "Sleep & Biometrics", queryText: "biometric stability", symbol: "bed.double", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep, scopedSport: nil, promptInstructions: "Analyze sleep architecture and autonomic stability. Exclude all workout data. Focus on baseline deviations only.", analyticalFramework: "Use a recovery physiology lens centered on sleep timing, sleep quality, HRV, resting trends, and autonomic stability.", negativeConstraints: "Exclude workout counts, HR zones, sport frequency, power, and load descriptions unless there is absolutely no other useful evidence.", languageStyle: "Use calm biometric language such as stable, elevated, suppressed, irregular, and restoring."),
            .init(id: "trend-balance", title: "Trend Focus", queryText: "long term patterns", symbol: "chart.line.uptrend.xyaxis", intent: .trendPB, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Speak only in gradients: accelerating, plateauing, declining, stabilizing. Do not mention today's specific numbers.", analyticalFramework: "Think like a trend analyst reading the slope of training and recovery over the selected scope.", negativeConstraints: "Do not anchor on one workout, one night of sleep, or isolated daily values.", languageStyle: "Use trajectory words and gradient language rather than static descriptions."),
            .init(id: "equalizer", title: "Equalizer Balance", queryText: "strain vs recovery ledger", symbol: "slider.horizontal.3", intent: .trendPB, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Contrast Strain vs Recovery as a financial ledger. Identify where you are in debt, balanced, or in surplus.", analyticalFramework: "Use the Equalizer as a ledger: strain spends, recovery restores, readiness reflects net position.", negativeConstraints: "Do not drift into generic wellness commentary or list unrelated fitness stats.", languageStyle: "Use balance-sheet language like overspend, surplus, payback, buffer, and debt."),
            .init(id: "intensity", title: "Intensity & Load", queryText: "training load dynamics", symbol: "flame", intent: .intensityLoad, focusMode: .general, scopedSport: nil, promptInstructions: "Focus on push-pull dynamics. Analyze Training Load versus fitness upside. Ignore sleep and vitals unless they limit your ceiling.", analyticalFramework: "Treat the period like a load-management problem: what is pushing adaptation and what is limiting productive intensity.", negativeConstraints: "Ignore passive recovery detail, sleep architecture, and generic wellness chatter unless they directly cap performance.", languageStyle: "Use direct training language about ceiling, dose, push, pull back, and productive load."),
            .init(id: "zones", title: "Zone 4/5 Focus", queryText: "high intensity exposure", symbol: "waveform.path.ecg", intent: .intensityLoad, focusMode: .general, scopedSport: nil, promptInstructions: "Analyze time spent at the ceiling. Ignore low-intensity work. Explain the cost of the highest-intensity efforts.", analyticalFramework: "Use a high-intensity exposure lens centered on threshold and above-threshold work.", negativeConstraints: "Ignore low-zone volume, recovery vitals, and broad weekly counts unless they directly explain tolerance to high intensity.", languageStyle: "Use language about ceiling, sharp efforts, neurological cost, and recovery toll."),
            .init(id: "overreach", title: "Overreach Watch", queryText: "risk audit", symbol: "exclamationmark.triangle", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep, scopedSport: nil, promptInstructions: "Act as a risk auditor. Look for red flags in HRR and HRV. Ignore fitness gains and focus on systemic fatigue.", analyticalFramework: "Audit for warning signals that say stress is outrunning adaptation.", negativeConstraints: "Do not celebrate PRs or fitness upside in this mode unless the pattern is clearly safe.", languageStyle: "Sound like a performance risk audit using terms like red flag, suppressed, lagging, and accumulating."),
            .init(id: "deload", title: "Deload Readiness", queryText: "recovery suppression", symbol: "arrow.down.circle", intent: .intensityLoad, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Build a case for or against a deload. If recovery is stagnant despite lower load, advocate for immediate rest.", analyticalFramework: "Use a decision memo framework: evidence for continuing versus evidence for backing off.", negativeConstraints: "Do not meander into broad summaries. End with a directional coaching call.", languageStyle: "Use decisive coaching language with a verdict and rationale."),
            .init(id: "sleep", title: "Sleep Depth", queryText: "sleep debt and quality", symbol: "moon.zzz", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep, scopedSport: nil, promptInstructions: "Spotlight sleep debt and consistency. Treat training only as the cause for the sleep effect.", analyticalFramework: "Use a sleep-first framework: debt, timing regularity, efficiency, and downstream readiness impact.", negativeConstraints: "Do not list sports, zone totals, or workout counts unless they explain why sleep shifted.", languageStyle: "Use restorative language about debt, rebound, irregularity, timing, and overnight repair."),
            .init(id: "pb", title: "PB & Trajectory", queryText: "performance peaks", symbol: "trophy", intent: .trendPB, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Ignore daily fatigue. Highlight only personal-best style progress and all-time trajectory markers.", analyticalFramework: "Think like a performance storyteller highlighting breakthrough signals and long-arc progress.", negativeConstraints: "Do not spend time on routine fatigue commentary or generic wellness caveats.", languageStyle: "Use celebratory but precise performance language around breakthroughs, upward trajectory, and markers."),
            .init(id: "consistency", title: "Sustainability", queryText: "training streaks", symbol: "calendar.badge.clock", intent: .trendPB, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Evaluate the rhythm of training. Is this pace sustainable for 90 days? Identify erratic versus steady behavior.", analyticalFramework: "Treat the block like a pacing pattern and evaluate whether it looks steady, chaotic, or brittle.", negativeConstraints: "Do not over-focus on one standout session or one biometric datapoint.", languageStyle: "Use rhythm language such as cadence, steadiness, drift, spikes, and sustainability."),
            .init(id: "met", title: "MET Spike Focus", queryText: "effort density", symbol: "bolt.heart", intent: .intensityLoad, focusMode: .general, scopedSport: nil, promptInstructions: "Analyze effort density. Focus on high-MET shocks to the system and the recovery lag that follows.", analyticalFramework: "Use a density-and-shock framework centered on clustered effort spikes and their aftereffects.", negativeConstraints: "Ignore routine background training and low-signal recovery commentary.", languageStyle: "Use energetic language around spikes, shocks, density, and rebound."),
            .init(id: "hrr-hrv", title: "HRR + HRV Link", queryText: "autonomic relationship", symbol: "heart.text.square", intent: .recoveryVitals, focusMode: .recoveryVitalsSleep, scopedSport: nil, promptInstructions: "Strictly analyze the interplay between Heart Rate Recovery and HRV. Ignore sleep stages and caloric burn.", analyticalFramework: "Use an autonomic-control lens centered on recovery speed and parasympathetic readiness.", negativeConstraints: "Ignore sleep architecture, calorie burn, session counts, and sports unless they directly explain HRR-HRV divergence.", languageStyle: "Use autonomic language such as rebound, suppression, restoration, and nervous-system tone."),
            .init(id: "undertraining", title: "Base Building", queryText: "load sufficiency", symbol: "figure.walk", intent: .intensityLoad, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Assess whether you are under-dosed. Is the load too low to trigger adaptation? Be direct.", analyticalFramework: "Use an adaptation-dose framework and ask whether the current block is enough stimulus to move fitness.", negativeConstraints: "Do not frame low strain plus high recovery as a problem unless the sustained pattern truly suggests insufficient stimulus.", languageStyle: "Use direct developmental language around dosage, headroom, and untapped capacity."),
            .init(id: "strain-days", title: "Strain Review", queryText: "high strain patterns", symbol: "gauge.with.dots.needle.bottom.50percent", intent: .trendPB, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Isolate days where Strain exceeded Recovery. Identify the specific behavior that caused the over-spend.", analyticalFramework: "Use a forensic review of strain-led days and what behavior repeatedly tipped the balance.", negativeConstraints: "Do not spend equal time on recovery-led days unless they clearly resolved the strain problem.", languageStyle: "Use causal language around triggers, overspend, stacking, and consequences."),
            .init(id: "recovery-days", title: "Rest Review", queryText: "rest day impact", symbol: "cross.case", intent: .trendPB, focusMode: .trendBalance, scopedSport: nil, promptInstructions: "Analyze the return on recovery-led days. Did they actually move the needle, or were they wasted?", analyticalFramework: "Use an ROI framework for rest and lighter days: did they restore readiness, stabilize vitals, or fail to help.", negativeConstraints: "Do not dwell on hardest sessions except as the setup for whether recovery worked.", languageStyle: "Use efficiency language like payoff, carryover, reset, and return on recovery."),
            .init(id: "ask-latest", title: "Latest Workout", queryText: "recent session analysis", symbol: "figure.run", intent: .sportSpecific, focusMode: .latestWorkout, scopedSport: sportFilter, promptInstructions: "Analyze only the most recent session. Compare it to your 30-day baseline for that specific sport.", analyticalFramework: "Use a session-review framework: what was done, how hard it was, and what changed versus norm.", negativeConstraints: "Ignore general weekly trends, unrelated sleep commentary, and broader wellness data unless they explain this exact session.", languageStyle: "Sound like a post-session debrief with concrete evidence."),
            .init(id: "ask-hardest", title: "Toughest Workout", queryText: "peak effort analysis", symbol: "figure.strengthtraining.traditional", intent: .sportSpecific, focusMode: .toughestWorkout, scopedSport: sportFilter, promptInstructions: "Deconstruct the highest-intensity effort. Analyze the mechanical and cardiovascular cost versus your norm.", analyticalFramework: "Use a peak-effort autopsy: identify why this session was the hardest and what cost markers prove it.", negativeConstraints: "Do not wander into generic sleep or week summaries unless they directly explain the response to this workout.", languageStyle: "Use high-intensity deconstruction language around cost, toll, demand, and exceptional effort.")
        ]

        let candidateSports = (sportFilter.map { [$0] } ?? Array(grouped30.keys).sorted())
        for sport in candidateSports.prefix(4) {
            let workoutsIn30 = grouped30[sport]?.count ?? 0
            let workoutsIn365 = grouped365[sport]?.count ?? 0
            guard workoutsIn30 > 0 || workoutsIn365 > 0 else { continue }

            let sportID = sport.lowercased().replacingOccurrences(of: " ", with: "-")
            suggestions.append(
                .init(
                    id: "sport-\(sportID)",
                    title: "\(sport.capitalized) Focus",
                    queryText: "\(sport) focus on training direction, readiness, and performance trends",
                    symbol: "scope",
                    intent: .sportSpecific,
                    focusMode: .sportDeepDive,
                    scopedSport: sport,
                    promptInstructions: "Isolate \(sport) and compare performance metrics against that discipline's own baseline.",
                    analyticalFramework: "Use a discipline-only lens and judge \(sport) on its own terms, not against the athlete's other activities.",
                    negativeConstraints: "Ignore other sports and irrelevant modalities unless they materially affect \(sport) performance.",
                    languageStyle: "Sound like a specialized \(sport) coach."
                )
            )
            suggestions.append(
                .init(
                    id: "sport-load-\(sportID)",
                    title: "\(sport.capitalized) Load",
                    queryText: "\(sport) load focus on zones, load, and whether you are pushing or pulling back",
                    symbol: "chart.bar",
                    intent: .intensityLoad,
                    focusMode: .sportDeepDive,
                    scopedSport: sport,
                    promptInstructions: "Focus on \(sport) load, zones, and adaptation signals only.",
                    analyticalFramework: "Use a sport-specific load-management lens for \(sport), centered on dose, tolerance, and fitness return.",
                    negativeConstraints: "Ignore general recovery commentary and other sports unless they directly cap \(sport) output.",
                    languageStyle: "Sound like a performance planner for \(sport)."
                )
            )

            if workoutsIn30 >= 14 || workoutsIn365 >= 30 {
                suggestions.append(
                    .init(
                        id: "sport-deep-\(sportID)",
                        title: "\(sport.capitalized) Deep Dive",
                        queryText: "\(sport) deep dive on training load, heart rate zones, VO2 max, personal records, cadence or power when available, and baseline progress",
                        symbol: "brain.head.profile",
                        intent: .sportSpecific,
                        focusMode: .sportDeepDive,
                        scopedSport: sport,
                        promptInstructions: "Deliver a deep \(sport) report using only sport-relevant metrics and exclude zeros or irrelevant modalities.",
                        analyticalFramework: "Use a full discipline synthesis for \(sport): load, zones, power or pace, cadence, HR behavior, and adaptation signals.",
                        negativeConstraints: "Ignore unrelated modalities, zero-valued fields, and generic wellness talk that does not change the \(sport) read.",
                        languageStyle: "Sound like an elite \(sport) coach writing a detailed performance report."
                    )
                )
                suggestions.append(
                    .init(
                        id: "sport-pr-\(sportID)",
                        title: "\(sport.capitalized) PR Story",
                        queryText: "\(sport) personal records and baseline changes including power, cadence, and lactate threshold if supported",
                        symbol: "medal",
                        intent: .trendPB,
                        focusMode: .sportDeepDive,
                        scopedSport: sport,
                        promptInstructions: "Focus on how \(sport) performance is improving, what metrics moved, and why those changes matter.",
                        analyticalFramework: "Use a breakthrough-story framework for \(sport) and connect changed metrics to changed performance.",
                        negativeConstraints: "Do not waste space on routine sessions or non-\(sport) details.",
                        languageStyle: "Use celebratory but evidence-backed \(sport) progression language."
                    )
                )
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
        - Treat this as a pure \(scopedSport?.capitalized ?? "sport") report, written by a dedicated coach for that discipline.
        - Use only \(scopedSport ?? "sport") workouts as evidence.
        - Prioritize sport-native evidence such as power, cadence, HR zones, VO2, HRR, and session-to-session progression when available.
        - Do not mention other sports, all-sport frequency, or generic wellness framing.
        - Strongest \(scopedSport ?? "sport") markers: longest session \(workoutHighlights.longestWorkout), highest load \(workoutHighlights.highestLoadWorkout), highest power \(workoutHighlights.highestPowerWorkout), highest peak HR \(workoutHighlights.highestPeakHRWorkout).
        - \(scopedSport?.capitalized ?? "Sport") load context: \(workoutLoadStatus(for: selectedSnapshot).detail)
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
    let zone4 = (toughest.analytics.hrZoneBreakdown.first(where: { $0.zone.zoneNumber == 4 })?.timeInZone ?? 0) / 60.0
    let zone5 = (toughest.analytics.hrZoneBreakdown.first(where: { $0.zone.zoneNumber == 5 })?.timeInZone ?? 0) / 60.0
    let power = toughest.analytics.powerSeries.map(\.1).average
    let cadence = toughest.analytics.cadenceSeries.map(\.1).average

    return """
    - Toughest workout date: \(dateText)
    - Toughest workout sport: \(sport)
    - Session load: \(formatted(load, digits: 0)) pts
    - Duration: \(formatted(duration, digits: 0)) min
    - Zone 4 time: \(formatted(zone4, digits: 0)) min
    - Zone 5 time: \(formatted(zone5, digits: 0)) min
    - Average power: \(power.map { formatted($0, digits: 0) + " W" } ?? "Unavailable")
    - Average cadence: \(cadence.map { formatted($0, digits: 0) + " rpm" } ?? "Unavailable")
    - Peak HR: \(toughest.analytics.peakHR.map { formatted($0, digits: 0) + " bpm" } ?? "Unavailable")
    - HRR: \(toughest.analytics.hrr2.map { formatted($0, digits: 0) + " bpm" } ?? "Unavailable")
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
    - HRR: \(latest.analytics.hrr2.map { formatted($0, digits: 0) + " bpm" } ?? "Unavailable")
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
    let acuteLoad: Double
    let chronicLoad: Double
    let acwr: Double
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

private func workoutSessionLoad(for workout: HKWorkout, analytics: WorkoutAnalytics) -> Double {
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

private func dailyLoadSnapshots(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    displayWindow: (start: Date, end: Date, endExclusive: Date)
) -> [WorkoutSummarySnapshot] {
    let calendar = Calendar.current
    var sessionLoadByDay: [Date: Double] = [:]
    var workoutCountByDay: [Date: Int] = [:]

    for (workout, analytics) in workouts {
        let day = calendar.startOfDay(for: workout.startDate)
        sessionLoadByDay[day, default: 0] += workoutSessionLoad(for: workout, analytics: analytics)
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

        let chronicLoad = chronicTotal / 28.0
        let acuteLoad = acuteTotal / 7.0
        let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
            let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
            return partial + ((sessionLoadByDay[sourceDay] ?? 0) > 0 ? 1 : 0)
        }
        let daysSinceLastWorkout = (0..<28).first(where: { offset in
            let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
            return (sessionLoadByDay[sourceDay] ?? 0) > 0
        })

        return WorkoutSummarySnapshot(
            date: day,
            sessionLoad: sessionLoadByDay[day] ?? 0,
            acuteLoad: acuteLoad,
            chronicLoad: chronicLoad,
            acwr: chronicLoad > 0 ? acuteLoad / chronicLoad : 0,
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
        guard let avgPower = pair.analytics.powerSeries.map(\.1).average else { return nil }
        let description = "\(pair.workout.workoutActivityType.name.capitalized) at \(formatted(avgPower, digits: 0)) W average on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, avgPower)
    }.max { $0.1 < $1.1 }?.0 ?? "Unavailable"

    let highestPeakHRWorkout = displayWorkouts.compactMap { pair -> (String, Double)? in
        guard let peakHR = pair.analytics.peakHR else { return nil }
        let description = "\(pair.workout.workoutActivityType.name.capitalized) peaked at \(formatted(peakHR, digits: 0)) bpm on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, peakHR)
    }.max { $0.1 < $1.1 }?.0 ?? "Unavailable"

    let zone4Entries = displayWorkouts.compactMap { pair -> (String, Double)? in
        let minutes = pair.analytics.hrZoneBreakdown.first(where: { $0.zone.zoneNumber == 4 })?.timeInZone ?? 0
        guard minutes > 0 else { return nil }
        let workoutMinutes = minutes / 60.0
        let description = "\(pair.workout.workoutActivityType.name.capitalized) with \(formatted(workoutMinutes, digits: 0)) min in Zone 4 on \(pair.workout.startDate.formatted(date: .abbreviated, time: .omitted))"
        return (description, workoutMinutes)
    }

    let zone5Entries = displayWorkouts.compactMap { pair -> (String, Double)? in
        let minutes = pair.analytics.hrZoneBreakdown.first(where: { $0.zone.zoneNumber == 5 })?.timeInZone ?? 0
        guard minutes > 0 else { return nil }
        let workoutMinutes = minutes / 60.0
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

private func localFallbackSummary(
    displayedStrain: Double,
    recoveryScore: Double,
    readinessScore: Double,
    workoutHighlights: WorkoutHighlights,
    selectedSnapshot: WorkoutSummarySnapshot?,
    scenario: String,
    intent: SummaryIntent,
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
    let loadStatus = workoutLoadStatus(for: selectedSnapshot)
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
        if recoveryScore >= 70 && displayedStrain >= 60 {
            return "Your Equalizer is working. You are asking more from training and your recovery is rising with it."
        }

        if loadStatus.title == "Spike" || loadStatus.title == "Aggressive" {
            return "Your Equalizer is tilting toward strain. You need recovery to catch up before you keep pressing."
        }

        return "Your Equalizer looks manageable right now, but the next step depends on whether recovery keeps pace with load."
    }()
    let overreachSignal: String = {
        guard let latestHRR = hrrData.last?.1,
              let averageHRR = average(hrrData.map(\.1)),
              averageHRR > 0,
              let acwr = selectedSnapshot?.acwr else {
            return ""
        }

        if latestHRR < averageHRR * 0.92 && acwr > 1.2 {
            return " Your heart rate recovery is softer than its recent baseline while load is elevated, so treat that as an overreach warning."
        }

        return ""
    }()

    return """
    \(scenario) \(equalizerSignal)\(overreachSignal) Your current strain is \(formatted(displayedStrain, digits: 0))/100, recovery is \(formatted(recoveryScore, digits: 0))/100, and readiness is \(formatted(readinessScore, digits: 0))/100. Your load status is \(loadStatus.title.lowercased()), with \(formatted(workoutHighlights.totalMinutes, digits: 0)) total training minutes and \(formatted(workoutHighlights.sessionsPerWeek, digits: 1)) sessions per week in this window. Your standout work came from \(workoutHighlights.longestWorkout.lowercased()) and \(workoutHighlights.highestLoadWorkout.lowercased()). You also spent \(formatted(workoutHighlights.totalZone4Minutes, digits: 0)) minutes in Zone 4 and \(formatted(workoutHighlights.totalZone5Minutes, digits: 0)) minutes in Zone 5, so intensity is a real part of the story.

    Your sleep is averaging \(formatted(averageSleep, digits: 1)) hours, with \(formatted(latestSleep, digits: 1)) hours most recently. Sleep consistency is \(formatted(consistencyScore, digits: 0))%, and sleep debt is \(formatted(sleepDebtHours, digits: 1)) hours. HRV is \(hrvTrend), resting heart rate is \(rhrTrend), and sleep heart rate is \(sleepHRTrend). \(vitalsState) A recovery-day sleep gap of \(signedFormatted(activityRecoveryGap, digits: 1)) hours is worth keeping if you want better absorption of training. Coaching focus right now: \(intent.promptInstruction)
    """
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
