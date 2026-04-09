import SwiftUI
import HealthKit
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

private extension View {
    /// `WheelPickerStyle` is unsupported for Mac idiom under Catalyst.
    @ViewBuilder
    func programBuilderWheelPickerCompatible(height: CGFloat) -> some View {
        #if targetEnvironment(macCatalyst)
        self.pickerStyle(.menu)
        #else
        self
            .pickerStyle(.wheel)
            .frame(height: height)
            .clipped()
        #endif
    }
}

private struct UniformChipWidthGrid: View {
    let activities: [ProgramWorkoutType]
    let allocationText: (String) -> String
    let removeAction: (String) -> Void

    var body: some View {
        AdaptiveChipGrid(activities) { activity in
            ProgramSelectedActivityChip(
                activity: activity,
                allocationText: allocationText(activity.id),
                removeAction: { removeAction(activity.id) }
            )
        }
        .animation(.default, value: activities)
    }
}
private enum ProgramBuilderTab: String, CaseIterable, Identifiable {
    case overview
    case workoutStages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .workoutStages:
            return "Workout Stages"
        }
    }
}

private struct ProgramStageCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProgramLaunchButtonHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ProgramBuilderView: View {
    @StateObject private var engine = HealthStateEngine.shared
    @StateObject private var planner = ProgramBuilderAIPlanner()
    @StateObject private var liveWorkoutManager = CompanionWorkoutLiveManager.shared
    @StateObject private var planStore = ProgramWorkoutPlanStore.shared
    @StateObject private var stageQuestStore = StageQuestStore.shared
    @EnvironmentObject private var navigationState: NavigationState

    @State private var searchText = ""
    @State private var selectedMode: ProgramBuilderMode = .guided
    @State private var selectedPlanDepth: ProgramPlanDepth = .comprehensive
    @State private var selectedActivityIDs: [String] = ["running"]
    @State private var allocationWeights: [String: Double] = ["running": 1]
    @State private var customActivities: [ProgramWorkoutType] = []
    @State private var customActivityName = ""
    @State private var activityMinutes: [String: Int] = ["running": 30]
    @State private var availableMinutes: Double = 30
    @State private var selectedRouteWorkoutID: String?
    @State private var selectedTargetMetric: ProgramTargetMetric = .pace
    @State private var selectedZone = 3
    @State private var targetValueText = ""
    @State private var routeObjectiveName = ""
    @State private var routeRepeats = 1
    @State private var selectedRouteTemplateID: UUID?
    @State private var selectedBuilderTab: ProgramBuilderTab = .overview
    @State private var selectedStageActivityID: String?
    @State private var customMicroStagesByActivityID: [String: [ProgramCustomWorkoutMicroStage]] = [:]
    @State private var customCircuitGroupsByActivityID: [String: [ProgramWorkoutCircuitGroup]] = [:]
    @State private var coachRegenerationNotesByActivityID: [String: String] = [:]
    @State private var stagePromptTextByStageID: [UUID: String] = [:]
    @State private var stageCardHeightByActivityID: [String: CGFloat] = [:]
    @State private var collapsedStageIDs: Set<UUID> = []
    @State private var launchButtonHeight: CGFloat = 0
    @State private var plannedRouteLaunchMetadata: RouteLaunchMetadata?
    @State private var routeTemplateIDsWithSavedRoutes: Set<UUID> = []
    @State private var hasLoadedRouteTemplateAvailability = false
    @State private var isSearchSectionExpanded = false
    @State private var hasRestoredCachedDraft = false
    @State private var isWorkoutStagesViewPresented = false
    @State private var planSyncStatusMessage: String?
    @State private var stageRegenerationStatusByActivityID: [String: String] = [:]
    @State private var stageManagerPromptByActivityID: [String: String] = [:]
    @State private var stageManagerSuggestedStagesByActivityID: [String: [ProgramCustomWorkoutMicroStage]] = [:]
    @State private var stageManagerBannedRoles: Set<ProgramMicroStageRole> = []
    @State private var stageManagerBannedGoals: Set<ProgramMicroStageGoal> = []
    @State private var isStageManagerBanSheetPresented = false
    @State private var navigateToWorkoutViewsLayout = false
    @State private var navigateToMetricLayout = false

    private var catalog: [ProgramWorkoutType] {
        ProgramWorkoutType.catalog + customActivities
    }

    private var filteredCatalog: [ProgramWorkoutType] {
        ProgramWorkoutType.searchResults(for: searchText, in: catalog)
    }

    private var selectedActivities: [ProgramWorkoutType] {
        selectedActivityIDs.compactMap { id in
            catalog.first(where: { $0.id == id })
        }
    }

    private var isPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var frequentHistorySuggestions: [ProgramWorkoutType] {
        let ranked = ProgramWorkoutType.rankFromHistory(engine.workoutAnalytics)
        let selected = Set(selectedActivityIDs)
        return ranked.filter { !selected.contains($0.id) }
    }

    private var todaySuggestions: [ProgramWorkoutType] {
        var suggestions = frequentHistorySuggestions
        if let firstSelected = selectedActivities.first {
            suggestions = ProgramWorkoutType.companionSuggestions(for: firstSelected, history: frequentHistorySuggestions)
        }
        return Array(suggestions.prefix(8))
    }

    private var routeTemplateCandidates: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let routeFriendlyRawValues = Set(
            selectedActivities
                .filter(\.routeFriendly)
                .map { $0.hkWorkoutActivityType.rawValue }
        )
        return engine.workoutAnalytics
            .filter { pair in
                if routeFriendlyRawValues.isEmpty {
                    return [.running, .walking, .hiking, .cycling].contains(pair.workout.workoutActivityType)
                }
                return routeFriendlyRawValues.contains(pair.workout.workoutActivityType.rawValue)
            }
            .sorted { $0.workout.startDate > $1.workout.startDate }
            .map { $0 }
    }

    private var routeTemplates: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        guard hasLoadedRouteTemplateAvailability else { return [] }
        return routeTemplateCandidates.filter { routeTemplateIDsWithSavedRoutes.contains($0.workout.uuid) }
    }

    private var selectedRouteTemplate: (workout: HKWorkout, analytics: WorkoutAnalytics)? {
        routeTemplates.first { $0.workout.uuid == selectedRouteTemplateID }
    }

    private var coachContextID: String {
        [
            selectedMode.rawValue,
            selectedPlanDepth.rawValue,
            selectedActivityIDs.joined(separator: ","),
            String(Int(availableMinutes.rounded())),
            targetValueText,
            String(selectedZone),
            routeObjectiveName,
            String(routeRepeats)
        ].joined(separator: "|")
    }

    private var routePlanningContextID: String {
        [
            selectedMode.rawValue,
            selectedRouteTemplateID?.uuidString ?? "",
            routeObjectiveName,
            String(routeRepeats)
        ].joined(separator: "|")
    }

    private var routeTemplateRefreshID: [UUID] {
        routeTemplateCandidates.map(\.workout.uuid)
    }

    private var draftCacheID: String {
        let allocationKey = allocationWeights
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let customStageKey = customMicroStagesByActivityID
            .sorted { $0.key < $1.key }
            .map { key, stages in
                "\(key):" + stages.map { "\($0.title):\($0.plannedMinutes):\($0.repeats):\($0.repeatSetLabel):\($0.circuitGroupID?.uuidString ?? "none"):\($0.targetBehavior.rawValue)" }.joined(separator: ",")
            }
            .joined(separator: "|")
        let circuitGroupKey = customCircuitGroupsByActivityID
            .sorted { $0.key < $1.key }
            .map { key, groups in
                "\(key):" + groups.map { "\($0.id.uuidString):\($0.title):\($0.repeats)" }.joined(separator: ",")
            }
            .joined(separator: "|")
        let regenerationKey = coachRegenerationNotesByActivityID
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")
        return [
            selectedMode.rawValue,
            selectedPlanDepth.rawValue,
            selectedBuilderTab.rawValue,
            selectedActivityIDs.joined(separator: ","),
            String(availableMinutes),
            allocationKey,
            selectedTargetMetric.rawValue,
            String(selectedZone),
            targetValueText,
            customStageKey,
            circuitGroupKey,
            regenerationKey,
            routeObjectiveName,
            String(routeRepeats),
            selectedRouteTemplateID?.uuidString ?? "",
            planner.coachAdvice,
            planner.generatedBlueprint?.title ?? ""
        ].joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                contentLayout(for: proxy.size.width)
            }
            .scrollBounceBehavior(.basedOnSize)
            .foregroundStyle(.orange)
            .tint(.orange)
            .background(GradientBackgrounds().programBuilderMeshBackground())
        }
        .navigationTitle("Program Builder")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    navigateToWorkoutViewsLayout = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                Button {
                    navigateToMetricLayout = true
                } label: {
                    Image(systemName: "gauge")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissProgramBuilderKeyboard()
                }
            }
        }
        .navigationDestination(isPresented: $navigateToWorkoutViewsLayout) {
            ProgramBuilderWorkoutViewsLayoutView()
        }
        .navigationDestination(isPresented: $navigateToMetricLayout) {
            ProgramBuilderMetricLayoutView()
        }
        .fullScreenCover(isPresented: $isWorkoutStagesViewPresented) {
            NavigationStack {
                workoutStagesExpandedView
            }
        }
        .sheet(isPresented: $isStageManagerBanSheetPresented) {
            stageManagerBanListSheet
        }
        .task(id: coachContextID) {
            await planner.refreshCoachAdvice(
                for: buildPlannerRequest(),
                engine: engine
            )
        }
        .task(id: routeTemplateRefreshID) {
            await loadRouteTemplateAvailability()
        }
        .onChange(of: selectedActivityIDs) { _, newValue in
            rebalanceWeights(for: newValue)
            syncTargetMetric()
            syncStageActivitySelection()
            ensureMicroStagesAreReady()
        }
        .onChange(of: selectedPlanDepth) { _, _ in
            ensureMicroStagesAreReady()
        }
        .onChange(of: routePlanningContextID) { _, _ in
            plannedRouteLaunchMetadata = nil
        }
        .onChange(of: draftCacheID) { _, _ in
            persistBuilderDraft()
        }
        .onChange(of: customMicroStagesByActivityID) { _, _ in
            syncAvailableMinutesWithStages()
        }
        .onChange(of: activityMinutes) { _, _ in
            syncAvailableMinutesWithStages()
        }
        .onAppear {
            handleViewAppear()
        }
        .onReceiveViewControl(.nutrivanceViewControlWorkoutViews) {
            guard navigationState.isGloballyActiveRootTab(.programBuilder) else { return }
            navigateToWorkoutViewsLayout = true
        }
        .onReceiveViewControl(.nutrivanceViewControlWorkoutMetricLayout) {
            guard navigationState.isGloballyActiveRootTab(.programBuilder) else { return }
            navigateToMetricLayout = true
        }
    }

    @ViewBuilder
    private func contentLayout(for width: CGFloat) -> some View {
        if shouldUseWideLayout(for: width) {
            HStack(alignment: .top, spacing: 24) {
                leftColumn
                    .frame(width: min(430, width * 0.36))
                rightColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(24)
        } else {
            VStack(spacing: 20) {
                if isPhoneLayout,
                   let inboxPlan = planStore.activeInboxPlan,
                   inboxPlan.sourceDeviceLabel == "iPad" {
                    phoneInboxSection(inboxPlan)
                }
                leftColumn
                rightColumn
            }
            .padding(16)
        }
    }

    private func shouldUseWideLayout(for width: CGFloat) -> Bool {
        isPadDevice && width >= 980
    }

    private func handleViewAppear() {
        restoreCachedDraftIfNeeded()
        rebalanceWeights(for: selectedActivityIDs)
        syncTargetMetric()
        syncStageActivitySelection()
        ensureMicroStagesAreReady()
        syncAvailableMinutesWithStages()
    }

    private func syncAvailableMinutesWithStages() {
        availableMinutes = Double(activityMinutes.values.reduce(0, +))
    }

    private func stageTotalMinutes(_ stages: [ProgramCustomWorkoutMicroStage]) -> Int {
        max(stages.reduce(0) { $0 + max($1.plannedMinutes, 1) * max($1.repeats, 1) }, 0)
    }

    private func buildPlanPhases() -> [ProgramWorkoutPlanPhase] {
        let activities = selectedActivities
        guard !activities.isEmpty else { return [] }

        let normalizedWeights = activities.reduce(into: [String: Double]()) { result, activity in
            result[activity.id] = max(0.15, allocationWeights[activity.id, default: 1])
        }
        let totalWeight = normalizedWeights.values.reduce(0, +)
        let totalMinutes = max(Int(availableMinutes.rounded()), activities.count)
        guard totalWeight > 0 else { return [] }

        var plannedMinutesByActivity: [String: Int] = [:]
        var consumedMinutes = 0

        for (index, activity) in activities.enumerated() {
            let weight = normalizedWeights[activity.id, default: 1]
            let assignedMinutes = index == activities.count - 1
                ? max(totalMinutes - consumedMinutes, 1)
                : max(Int(((weight / totalWeight) * Double(totalMinutes)).rounded()), 1)
            plannedMinutesByActivity[activity.id] = assignedMinutes
            consumedMinutes += assignedMinutes
        }

        if consumedMinutes != totalMinutes, let lastID = activities.last?.id {
            plannedMinutesByActivity[lastID] = max((plannedMinutesByActivity[lastID] ?? 1) + (totalMinutes - consumedMinutes), 1)
        }

        return activities.map { activity in
            ProgramWorkoutPlanPhase(
                title: activity.title,
                subtitle: "\(plannedMinutesByActivity[activity.id] ?? 1) min planned",
                activityID: activity.id,
                activityRawValue: activity.hkWorkoutActivityType.rawValue,
                locationRawValue: activity.preferredLocationType(for: selectedMode).rawValue,
                plannedMinutes: max(plannedMinutesByActivity[activity.id] ?? 1, 1),
                microStages: resolvedMicroStages(for: activity, totalMinutes: plannedMinutesByActivity[activity.id] ?? 1),
                circuitGroups: resolvedCircuitGroups(for: activity, totalMinutes: plannedMinutesByActivity[activity.id] ?? 1)
            )
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgramSectionCard {
                ProgramBuilderCoachSection(
                    planner: planner,
                    request: buildPlannerRequest(),
                    refreshAction: {
                        Task {
                            await planner.refreshCoachAdvice(
                                for: buildPlannerRequest(),
                                engine: engine
                            )
                        }
                    }
                )
            }

            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What do you want to do today?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Pick from your usual patterns, then shape the session the way you actually want it today.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))

                    AdaptiveChipGrid(todaySuggestions) { suggestion in
                        ProgramSuggestionChip(
                            title: suggestion.title,
                            symbol: suggestion.symbol,
                            isSelected: selectedActivityIDs.contains(suggestion.id),
                            tint: suggestion.tint
                        ) {
                            toggleActivity(suggestion.id)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                }
            }

            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("Search Every Activity")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        if isPhoneLayout {
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    isSearchSectionExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isSearchSectionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.86))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !isPhoneLayout || isSearchSectionExpanded {
                        TextField("Search running, ski touring, yoga, triathlon...", text: $searchText)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )

                        HStack(spacing: 10) {
                            TextField("Add your own activity", text: $customActivityName)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Button("Add") {
                                addCustomActivity()
                            }
                            .buttonStyle(.glass)
                            .foregroundStyle(.white)
                            .disabled(customActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(filteredCatalog) { activity in
                                ProgramWorkoutTypeRow(
                                    activity: activity,
                                    isSelected: selectedActivityIDs.contains(activity.id),
                                    action: { toggleActivity(activity.id) }
                                )
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if isPhoneLayout {
                        Text("Collapsed for easier picking from your suggested workouts.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Builder Tab", selection: $selectedBuilderTab) {
                        ForEach(ProgramBuilderTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedBuilderTab {
                    case .overview:
                        planningOverviewTab
                    case .workoutStages:
                        workoutStagesTab
                    }

                    if let _ = planner.generatedBlueprint {
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await saveCurrentPlanToRepository()
                                }
                            } label: {
                                Label("Save to Repository", systemImage: "square.and.arrow.down")
                                    .font(.subheadline.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.18))
                            .disabled(selectedActivities.isEmpty)

                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
            }

            ProgramSectionCard {
                workoutLaunchSection
            }

            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stage Manager")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Generate 3 workout-stage suggestions from your activity, intensity profile, and optional intent.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Button("Ban List") {
                            isStageManagerBanSheetPresented = true
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(.white)
                    }

                    if selectedActivities.isEmpty {
                        ProgramEmptyState(
                            title: "No workout selected",
                            subtitle: "Pick at least one workout type first. Stage Manager uses this as a hard constraint."
                        )
                    } else {
                        stageManagerActivitySelector
                        if let activity = selectedStageActivityForSuggestions {
                            stageManagerCard(for: activity)
                        }
                    }

                    if let planSyncStatusMessage, !planSyncStatusMessage.isEmpty {
                        Text(planSyncStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            ProgramSectionCard {
                workoutRepositorySection
            }
        }
    }

    private var selectedStageActivityForSuggestions: ProgramWorkoutType? {
        if let selectedStageActivityID,
           let resolved = selectedActivities.first(where: { $0.id == selectedStageActivityID }) {
            return resolved
        }
        return selectedActivities.first
    }

    private var stageManagerActivitySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedActivities) { activity in
                    Button {
                        selectedStageActivityID = activity.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: activity.symbol)
                            Text(activity.title)
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            (selectedStageActivityID == activity.id ? activity.tint.opacity(0.85) : Color.white.opacity(0.14)),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func stageManagerCard(for activity: ProgramWorkoutType) -> some View {
        let promptBinding = Binding(
            get: { stageManagerPromptByActivityID[activity.id, default: ""] },
            set: { stageManagerPromptByActivityID[activity.id] = $0 }
        )
        let suggestions = stageManagerSuggestedStagesByActivityID[activity.id] ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Stage Suggestions • \(activity.title)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            TextField("Optional intent: improve stamina, push FTP, better threshold control...", text: promptBinding, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Button {
                    generateStageManagerSuggestions(for: activity)
                } label: {
                    Label("Generate 3 Suggestions", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))

                Spacer()

                if !stageManagerBannedRoles.isEmpty {
                    Text("Banned: \(stageManagerBannedRoles.map(\.title).sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }
            }

            if suggestions.isEmpty {
                Text("No suggestions yet. Generate to see compact stage cards, then add any stage to your current workout.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.66))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(suggestions) { stage in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(stage.displaySummary)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Add Stage") {
                                addSuggestedStage(stage, to: activity)
                            }
                            .buttonStyle(.glass)
                            .foregroundStyle(.white)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stageManagerBanListSheet: some View {
        NavigationStack {
            List {
                Section("ProgramMicroStageRole Ban List") {
                    ForEach(ProgramMicroStageRole.allCases) { role in
                        Button {
                            toggleStageManagerBanRole(role)
                        } label: {
                            HStack {
                                Label(role.title, systemImage: stageManagerBannedRoles.contains(role) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(stageManagerBannedRoles.contains(role) ? .orange : .secondary)
                                Spacer()
                            }
                        }
                    }
                }
                Section("ProgramMicroStageGoal Ban List") {
                    ForEach(ProgramMicroStageGoal.allCases.filter { $0 != .open }) { goal in
                        Button {
                            toggleStageManagerBanGoal(goal)
                        } label: {
                            HStack {
                                Label(goal.title, systemImage: stageManagerBannedGoals.contains(goal) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(stageManagerBannedGoals.contains(goal) ? .orange : .secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Never Suggest")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isStageManagerBanSheetPresented = false
                    }
                }
            }
        }
    }

    private func toggleStageManagerBanRole(_ role: ProgramMicroStageRole) {
        if stageManagerBannedRoles.contains(role) {
            stageManagerBannedRoles.remove(role)
        } else {
            stageManagerBannedRoles.insert(role)
        }
    }

    private func toggleStageManagerBanGoal(_ goal: ProgramMicroStageGoal) {
        if stageManagerBannedGoals.contains(goal) {
            stageManagerBannedGoals.remove(goal)
        } else {
            stageManagerBannedGoals.insert(goal)
        }
    }

    private func generateStageManagerSuggestions(for activity: ProgramWorkoutType) {
        let prompt = stageManagerPromptByActivityID[activity.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let request = buildPlannerRequest()
        let intensityBias = (request.readinessScore + request.recoveryScore - request.strainScore) / 3.0
        let candidateRoles = ProgramMicroStageRole.allCases.filter { !stageManagerBannedRoles.contains($0) }
        guard !candidateRoles.isEmpty else {
            stageManagerSuggestedStagesByActivityID[activity.id] = []
            return
        }

        let preferredRoles: [ProgramMicroStageRole]
        if prompt.contains("stamina") {
            preferredRoles = [.steady, .recovery, .goal]
        } else if prompt.contains("ftp") || prompt.contains("threshold") || prompt.contains("power") {
            preferredRoles = [.work, .steady, .recovery]
        } else if intensityBias > 15 {
            preferredRoles = [.work, .steady, .goal]
        } else if intensityBias < -5 {
            preferredRoles = [.steady, .recovery, .cooldown]
        } else {
            preferredRoles = [.steady, .work, .recovery]
        }

        var roles = preferredRoles.filter { candidateRoles.contains($0) }
        for role in candidateRoles where roles.count < 3 {
            if !roles.contains(role) {
                roles.append(role)
            }
        }

        var suggestions: [ProgramCustomWorkoutMicroStage] = []
        for (index, role) in Array(roles.prefix(3)).enumerated() {
            let allowed = allowedGoals(for: role, activity: activity).filter { !stageManagerBannedGoals.contains($0) }
            guard !allowed.isEmpty else { continue }
            let goal: ProgramMicroStageGoal = {
                if prompt.contains("cadence"), allowed.contains(.cadence) { return .cadence }
                if (prompt.contains("hr") || prompt.contains("heart")), allowed.contains(.heartRateZone) { return .heartRateZone }
                if (prompt.contains("ftp") || prompt.contains("power")), allowed.contains(.power) { return .power }
                if prompt.contains("speed"), allowed.contains(.speed) { return .speed }
                return allowed[0]
            }()

            let fallbackTargetValueText = suggestedTargetText(for: role, goal: goal, prompt: prompt, intensityBias: intensityBias)
            let portedTargetValueText = stageManagerTargetValueTextPortedFromPastQuests(
                for: activity,
                role: role,
                goal: goal
            )

            suggestions.append(
                normalizeStage(
                ProgramCustomWorkoutMicroStage(
                    title: defaultStageTitle(for: role, goal: goal),
                    notes: stageManagerNote(for: role, goal: goal, prompt: prompt, intensityBias: intensityBias),
                    role: role,
                    goal: goal,
                    plannedMinutes: suggestedMinutes(for: role, index: index),
                    repeats: suggestedRepeats(for: role),
                    targetValueText: portedTargetValueText ?? fallbackTargetValueText,
                    targetBehavior: role.defaultTargetBehavior
                ),
                for: activity
            )
            )
        }
        stageManagerSuggestedStagesByActivityID[activity.id] = suggestions
    }

    private func stageManagerTargetValueTextPortedFromPastQuests(
        for activity: ProgramWorkoutType,
        role: ProgramMicroStageRole,
        goal: ProgramMicroStageGoal
    ) -> String? {
        guard goal.requiresDescriptorInput else { return nil }

        let key = "\(activity.id)|\(goal.rawValue)|\(role.rawValue)"
        guard let rec = stageQuestStore.recommendations[key] else { return nil }

        // Map comfortable vs pushing to roles.
        let rangeText: String = {
            switch role {
            case .work:
                return rec.pushingRange
            case .steady, .warmup, .goal, .recovery, .cooldown:
                return rec.comfortableRange
            }
        }()

        // Format per goal so the stage editor / wheel pickers understand the descriptor.
        return formatStageTargetValueText(rangeText: rangeText, goal: goal)
    }

    private func formatStageTargetValueText(rangeText: String, goal: ProgramMicroStageGoal) -> String? {
        let parts = rangeText
            .components(separatedBy: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Ensure we can parse both ends for range-style strings.
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else {
            // Single-value recommendations are not expected, but handle gracefully.
            if let value = Double(rangeText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return formatStageTargetValueText(rangeValues: (value, value), goal: goal)
            }
            return nil
        }
        return formatStageTargetValueText(rangeValues: (a, b), goal: goal)
    }

    private func formatStageTargetValueText(rangeValues: (Double, Double), goal: ProgramMicroStageGoal) -> String? {
        let low = min(rangeValues.0, rangeValues.1)
        let high = max(rangeValues.0, rangeValues.1)

        switch goal {
        case .cadence:
            return "\(Int(low))-\(Int(high)) rpm"
        case .speed:
            return "\(Int(low))-\(Int(high)) mph"
        case .power:
            return "\(Int(low))-\(Int(high)) W"
        case .heartRateZone:
            let z1 = Int(low)
            let z2 = Int(high)
            if z1 == z2 { return "Zone \(z1)" }
            return "Zone \(min(z1, z2))-\(max(z1, z2))"
        case .pace:
            // Past Quests recommendations for pace are in seconds per mile; convert to m:ss.
            let toPaceText: (Double) -> String = { seconds in
                let total = max(0, Int(seconds.rounded()))
                let minutes = total / 60
                let secs = total % 60
                return "\(minutes):\(String(format: "%02d", secs))"
            }
            let start = toPaceText(low)
            let end = toPaceText(high)
            return "\(start)-\(end) /mi"
        case .distance:
            return "\(Int(low))-\(Int(high)) km"
        case .energy:
            return "\(Int(low))-\(Int(high)) kcal"
        case .open, .time:
            return nil
        }
    }

    private func suggestedMinutes(for role: ProgramMicroStageRole, index: Int) -> Int {
        switch role {
        case .warmup: return 8
        case .goal: return 15
        case .steady: return 10
        case .work: return 8
        case .recovery: return 4
        case .cooldown: return 6 + index
        }
    }

    private func suggestedRepeats(for role: ProgramMicroStageRole) -> Int {
        switch role {
        case .work, .recovery:
            return 4
        default:
            return 1
        }
    }

    private func suggestedTargetText(
        for role: ProgramMicroStageRole,
        goal: ProgramMicroStageGoal,
        prompt: String,
        intensityBias: Double
    ) -> String {
        switch goal {
        case .cadence:
            if role == .steady { return "90-110 rpm" }
            if role == .work { return ">= 100 rpm" }
            return "80-95 rpm"
        case .heartRateZone:
            return role == .work ? "Zone 4+" : "Zone 2-3"
        case .power:
            return role == .work ? "FTP + 5-12%" : "70-80% FTP"
        case .speed:
            return role == .work ? "Above tempo speed" : "Steady speed band"
        case .pace:
            return role == .work ? "5k-10k effort" : "Comfortable pace"
        case .time:
            return role == .goal ? (intensityBias > 0 ? "continuous push" : "smooth aerobic") : ""
        default:
            if prompt.contains("stamina") { return "sustainable range" }
            return defaultDescriptor(for: goal)
        }
    }

    private func stageManagerNote(
        for role: ProgramMicroStageRole,
        goal: ProgramMicroStageGoal,
        prompt: String,
        intensityBias: Double
    ) -> String {
        if !prompt.isEmpty {
            return "Generated from intent: \(prompt). Keep \(goal.title.lowercased()) aligned with \(role.title.lowercased()) execution."
        }
        if intensityBias > 10 {
            return "Higher readiness day: controlled but assertive stage execution."
        }
        if intensityBias < -5 {
            return "Lower readiness day: keep this stage smooth and sustainable."
        }
        return "Baseline stage generated from your recent workout intensity profile."
    }

    private func addSuggestedStage(_ stage: ProgramCustomWorkoutMicroStage, to activity: ProgramWorkoutType) {
        var stages = customMicroStagesByActivityID[activity.id] ?? defaultMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        stages.append(normalizeStage(stage, for: activity))
        customMicroStagesByActivityID[activity.id] = stages
        stageRegenerationStatusByActivityID[activity.id] = "Added \(stage.title) to \(activity.title)."
    }

    private var workoutLaunchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPadDevice ? "Send This Workout" : "Start This Workout")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(isPadDevice
                         ? "On iPad, save the generated plan and send it to iPhone. It will also float to the top of Apple Watch for quick access for the next 24 hours."
                         : "Run it here on iPhone or hand it straight to Apple Watch. Outdoor starts use device GPS, and connected HealthKit-compatible sensors can flow into the live view.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if !isPadDevice, liveWorkoutManager.isWorkoutActive {
                    Text("Live")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange, in: Capsule())
                }
            }

            if let activity = selectedActivities.first {
                let launchTitle = planner.generatedBlueprint?.title ?? activity.title
                let launchSubtitle = launchSubtitle(for: activity)

                if isPadDevice {
                    ProgramLaunchButton(
                        title: "Save Plan & Send to iPhone",
                        subtitle: "Shows on iPhone and Apple Watch for 24 hours",
                        symbol: "iphone.badge.arrow.forward",
                        tint: .orange,
                        fixedHeight: nil
                    ) {
                        Task {
                            await sendCurrentPlanToIPhone()
                        }
                    }
                    .disabled(planner.generatedBlueprint == nil)
                } else {
                    HStack(spacing: 12) {
                        ProgramLaunchButton(
                            title: "Start on iPhone",
                            subtitle: activity.routeFriendly ? "GPS + phone-connected feeds" : "Local live workout",
                            symbol: "iphone",
                            tint: .cyan,
                            fixedHeight: launchButtonHeight > 0 ? launchButtonHeight : nil
                        ) {
                            liveWorkoutManager.startWorkoutOnThisDevice(
                                title: launchTitle,
                                subtitle: launchSubtitle,
                                activity: activity.hkWorkoutActivityType,
                                location: activity.preferredLocationType(for: selectedMode)
                            )
                        }

                        ProgramLaunchButton(
                            title: "Start on Watch",
                            subtitle: "Mirror back to phone",
                            symbol: "applewatch",
                            tint: .orange,
                            fixedHeight: launchButtonHeight > 0 ? launchButtonHeight : nil
                        ) {
                            Task {
                                let routeLaunch: RouteLaunchMetadata
                                if let plannedRouteLaunchMetadata {
                                    routeLaunch = plannedRouteLaunchMetadata
                                } else if let fetchedRouteLaunch = await routeLaunchMetadata() {
                                    routeLaunch = fetchedRouteLaunch
                                } else {
                                    routeLaunch = RouteLaunchMetadata(name: "", trailhead: nil, coordinates: [])
                                }
                                liveWorkoutManager.startWorkoutOnWatch(
                                    title: launchTitle,
                                    subtitle: launchSubtitle,
                                    activity: activity.hkWorkoutActivityType,
                                    location: activity.preferredLocationType(for: selectedMode),
                                    phases: buildPlanPhases(),
                                    routeName: routeLaunch.name.isEmpty ? nil : routeLaunch.name,
                                    trailheadCoordinate: routeLaunch.trailhead,
                                    routeCoordinates: routeLaunch.coordinates
                                )
                            }
                        }

                        if selectedActivities.count == 1 {
                            ProgramLaunchButton(
                                title: "Workout App",
                                subtitle: "Open in first-party Apple Workout",
                                symbol: "figure.outdoor.cycle",
                                tint: .white,
                                fixedHeight: launchButtonHeight > 0 ? launchButtonHeight : nil
                            ) {
                                liveWorkoutManager.sendWorkoutToAppleWorkoutAppOnWatch(
                                    title: launchTitle,
                                    subtitle: launchSubtitle,
                                    activity: activity.hkWorkoutActivityType,
                                    location: activity.preferredLocationType(for: selectedMode),
                                    phases: buildPlanPhases()
                                )
                            }
                        }
                    }
                    #if !targetEnvironment(macCatalyst)
                    .onPreferenceChange(ProgramLaunchButtonHeightPreferenceKey.self) { newHeight in
                        guard newHeight > 0 else { return }
                        // Avoid a layout↔preference feedback loop (sub-pixel height churn).
                        if abs(newHeight - launchButtonHeight) > 0.75 {
                            launchButtonHeight = newHeight
                        }
                    }
                    #endif

                    if let launchStatusMessage = liveWorkoutManager.launchStatusMessage, !launchStatusMessage.isEmpty {
                        Text(launchStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                if isPadDevice, let planSyncStatusMessage, !planSyncStatusMessage.isEmpty {
                    Text(planSyncStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                ProgramEmptyState(
                    title: "Pick the primary activity first",
                    subtitle: isPadDevice
                        ? "The first selected activity becomes the primary plan type that gets sent to iPhone and Apple Watch."
                        : "The first selected activity becomes the live workout type for iPhone or Apple Watch."
                )
            }
        }
    }

    private var guidedPlanningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Taste-Led Session Design")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Blend sports or support work the way you want. If you add cooldown, stretch, yoga, or a second sport here, the generator can include it. If you do not add it, it should not invent it.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            if selectedActivities.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time Allocation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    ForEach(selectedActivities) { activity in
                        let minutes = Binding<Int>(
                            get: { activityMinutes[activity.id, default: 30] },
                            set: { activityMinutes[activity.id] = max(1, $0) }
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(activity.title, systemImage: activity.symbol)
                                Spacer()
                                Text("\(minutes.wrappedValue) min")
                                    .foregroundStyle(activity.tint)
                            }
                            .font(.subheadline.weight(.semibold))

                            HStack(spacing: 14) {
                                Slider(
                                    value: Binding(
                                        get: { Double(min(activityMinutes[activity.id, default: 30], 120)) },
                                        set: { newValue in
                                            let scaled = Int((newValue / 5).rounded()) * 5
                                            activityMinutes[activity.id] = max(5, scaled)
                                        }
                                    ),
                                    in: 5...120,
                                    step: 5
                                )
                                .tint(activity.tint)

                                TextField(
                                    "Min",
                                    value: minutes,
                                    format: .number
                                )
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 56)
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            } else {
                Text("Single-sport today. Add more activities if you want a brick, combo day, mobility pairing, or explicit cooldown block.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }

            if !todaySuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Helpful Add-Ons From Your Patterns")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    AdaptiveChipGrid(Array(todaySuggestions.filter { !selectedActivityIDs.contains($0.id) }.prefix(6))) { suggestion in
                            ProgramSuggestionChip(
                                title: suggestion.title,
                                symbol: suggestion.symbol,
                                isSelected: false,
                                tint: suggestion.tint
                            ) {
                                toggleActivity(suggestion.id)
                            }
                    }
                }
            }
        }
    }

    private var targetPlanningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Target-Led Session Design")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Sometimes the session is really about a feeling or target: a pace band, a power range, a heart-rate zone, or simply controlled completion.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            if !selectedActivities.isEmpty {
                HStack(spacing: 12) {
                    Text(targetApplicabilitySummary)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(targetCompatibleActivities.count)/\(selectedActivities.count) workouts")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }

                Picker("Target", selection: $selectedTargetMetric) {
                    ForEach(availableTargetMetrics) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                targetMetricEditor

                Text(selectedTargetMetric.guidance)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))

                if !targetIncompatibleActivities.isEmpty {
                    Text("Time-led handling for: \(targetIncompatibleActivities.map(\.title).joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.62))
                }
            } else {
                ProgramEmptyState(
                    title: "Pick a sport first",
                    subtitle: "Choose the primary sport, then set the target you care about today."
                )
            }
        }
    }

    @ViewBuilder
    private var targetMetricEditor: some View {
        switch selectedTargetMetric {
        case .heartRateZone:
            Picker("HR Zone", selection: targetZoneWheelBinding) {
                ForEach(zoneWheelOptions, id: \.self) { zone in
                    Text(zone).tag(zone)
                }
            }
            .programBuilderWheelPickerCompatible(height: 120)

        case .power, .cadence:
            HStack(spacing: 10) {
                wheelMetricPicker(title: "Min", selection: targetRangeComponentBinding(.lower), options: targetWheelOptions)
                wheelMetricPicker(title: "Max", selection: targetRangeComponentBinding(.upper), options: targetWheelOptions)
            }

        case .distance:
            wheelMetricPicker(title: "Distance", selection: targetSingleValueBinding(), options: targetWheelOptions)

        case .pace:
            HStack(spacing: 10) {
                wheelMetricPicker(title: "Start Pace", selection: targetRangeComponentBinding(.lower), options: targetWheelOptions)
                wheelMetricPicker(title: "End Pace", selection: targetRangeComponentBinding(.upper), options: targetWheelOptions)
            }
        }
    }

    private enum TargetRangeComponent {
        case lower
        case upper
    }

    private var targetWheelOptions: [String] {
        switch selectedTargetMetric {
        case .power:
            return wheelOptions(for: .power)
        case .cadence:
            return wheelOptions(for: .cadence)
        case .distance:
            return wheelOptions(for: .distance)
        case .pace:
            return wheelOptions(for: .pace)
        case .heartRateZone:
            return zoneWheelOptions
        }
    }

    private var targetZoneWheelBinding: Binding<String> {
        Binding(
            get: { "Zone \(selectedZone)" },
            set: { newValue in
                let zone = newValue.captureGroups(for: #"zone\s*(\d+)"#).first?.first.flatMap(Int.init) ?? 3
                selectedZone = min(max(zone, 1), 5)
            }
        )
    }

    private func targetRangeComponentBinding(_ component: TargetRangeComponent) -> Binding<String> {
        Binding(
            get: {
                let options = targetWheelOptions
                let parts = targetValueText.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                switch component {
                case .lower:
                    return nearestWheelOption(for: parts.first ?? "", options: options, fallback: options.first ?? "")
                case .upper:
                    return nearestWheelOption(for: parts.count > 1 ? parts[1] : "", options: options, fallback: options.dropFirst().first ?? options.first ?? "")
                }
            },
            set: { newValue in
                var parts = targetValueText.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.isEmpty { parts = ["", ""] }
                if parts.count == 1 { parts.append("") }
                switch component {
                case .lower:
                    parts[0] = newValue
                case .upper:
                    parts[1] = newValue
                }
                targetValueText = parts.filter { !$0.isEmpty }.joined(separator: "-")
            }
        )
    }

    private func targetSingleValueBinding() -> Binding<String> {
        Binding(
            get: { nearestWheelOption(for: targetValueText, options: targetWheelOptions, fallback: targetWheelOptions.first ?? "") },
            set: { newValue in
                targetValueText = newValue
            }
        )
    }

    private var routePlanningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Route-Led Session Design")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text(routePlanningDescription)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            if selectedActivities.isEmpty {
                ProgramEmptyState(
                    title: "Pick a workout first",
                    subtitle: "Add a workout before choosing which one should follow the route." 
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedActivities) { activity in
                            Button {
                                selectedRouteWorkoutID = activity.id
                            } label: {
                                Text(activity.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(selectedRouteWorkout?.id == activity.id ? .white : .white.opacity(0.76))
                                    .background(
                                        (selectedRouteWorkout?.id == activity.id ? activity.tint : Color.white.opacity(0.12)),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Name the route, trail, climb, or course", text: $routeObjectiveName)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                wheelMetricPicker(title: "Repeats", selection: routeRepeatsWheelBinding, options: (1...10).map(String.init))
            }

            if !routeCompatibleActivities.isEmpty {
                Text("Route-aware phases: \(routeCompatibleActivities.map(\.title).joined(separator: ", "))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            if !routeIncompatibleActivities.isEmpty {
                Text("Non-route phases stay local: \(routeIncompatibleActivities.map(\.title).joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }

            if routeCompatibleActivities.isEmpty {
                ProgramEmptyState(
                    title: "No route-friendly workout selected",
                    subtitle: "Add running, walking, hiking, cycling, or another outdoor-capable activity to anchor the plan to a route."
                )
            } else if routeTemplates.isEmpty {
                ProgramEmptyState(
                    title: "No recent route templates",
                    subtitle: "Outdoor workouts with saved routes will show up here for reuse."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(routeTemplates, id: \.workout.uuid) { template in
                            ProgramRouteTemplateCard(
                                workout: template.workout,
                                analytics: template.analytics,
                                isSelected: selectedRouteTemplateID == template.workout.uuid
                            ) {
                                selectedRouteTemplateID = template.workout.uuid
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func phoneInboxSection(_ plan: ProgramWorkoutPlanRecord) -> some View {
        ProgramSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From iPad")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Expires \(plan.expirationDescription)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                    Text("24h")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange, in: Capsule())
                }

                Text(plan.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(plan.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))

                HStack(spacing: 10) {
                    Button("Use Plan") {
                        applyPlan(plan)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.white)

                    Button("Save") {
                        var saved = plan
                        saved.expiresAt = nil
                        saved.updatedAt = Date()
                        planStore.saveRepositoryPlan(saved)
                        planSyncStatusMessage = "Saved iPad plan to Workout Repository."
                    }
                    .buttonStyle(.bordered)

                    Button("Clear") {
                        planStore.clearInboxPlan()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var workoutRepositorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout Repository")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Permanent workout plans sync across iPhone, iPad, and Apple Watch.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if !planStore.repositoryPlans.isEmpty {
                    Text("\(planStore.repositoryPlans.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.88), in: Capsule())
                }
            }

            if planStore.repositoryPlans.isEmpty {
                ProgramEmptyState(
                    title: "No saved plans yet",
                    subtitle: "Generate a workout, then save it here to keep it synced and ready on every device."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(planStore.repositoryPlans) { plan in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plan.title)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text(plan.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.72))
                                        .lineLimit(2)
                                    Text("Saved \(plan.sourceDeviceLabel) • \(plan.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button("Load") {
                                    applyPlan(plan)
                                }
                                .buttonStyle(.glass)
                                .foregroundStyle(.white)

                                Button("Delete", role: .destructive) {
                                    planStore.deleteRepositoryPlan(id: plan.id)
                                    planSyncStatusMessage = "Deleted workout plan."
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    private func saveCurrentPlanToRepository() async {
        guard let plan = await buildPlanRecord(expiresAt: nil) else {
            planSyncStatusMessage = "Generate a workout before saving it to the repository."
            return
        }
        planStore.saveRepositoryPlan(plan)
        planSyncStatusMessage = "Saved to Workout Repository."
    }

    private func sendCurrentPlanToIPhone() async {
        guard let temporaryPlan = await buildPlanRecord(expiresAt: Date().addingTimeInterval(24 * 60 * 60)) else {
            planSyncStatusMessage = "Generate a workout before sending it to iPhone."
            return
        }
        var permanentPlan = temporaryPlan
        permanentPlan.expiresAt = nil
        permanentPlan.updatedAt = Date()
        planStore.saveRepositoryPlan(permanentPlan)
        planStore.sendTemporaryPlan(temporaryPlan)
        planSyncStatusMessage = "Saved and sent from iPad. It will stay at the top of iPhone and Apple Watch for 24 hours."
    }

    private func buildPlanRecord(expiresAt: Date?) async -> ProgramWorkoutPlanRecord? {
        guard let activity = selectedActivities.first,
              let blueprint = planner.generatedBlueprint else {
            return nil
        }

        let routeLaunch: RouteLaunchMetadata?
        if selectedMode == .route {
            if let plannedRouteLaunchMetadata {
                routeLaunch = plannedRouteLaunchMetadata
            } else {
                routeLaunch = await routeLaunchMetadata()
            }
        } else {
            routeLaunch = nil
        }

        let phases = buildPlanPhases()

        return ProgramWorkoutPlanRecord(
            id: UUID(),
            title: blueprint.title,
            summary: blueprint.summary,
            todayFocus: blueprint.todayFocus,
            blocks: blueprint.blocks,
            cautionNote: blueprint.cautionNote,
            selectedActivityIDs: selectedActivityIDs,
            availableMinutes: Int(availableMinutes.rounded()),
            modeRawValue: selectedMode.rawValue,
            selectedPlanDepthRawValue: selectedPlanDepth.rawValue,
            allocationWeights: allocationWeights,
            targetMetricRawValue: selectedTargetMetric.rawValue,
            selectedZone: selectedZone,
            targetValueText: targetValueText,
            routeObjectiveName: routeObjectiveName,
            routeRepeats: routeRepeats,
            selectedRouteTemplateID: selectedRouteTemplateID,
            primaryActivityID: activity.id,
            activityRawValue: activity.hkWorkoutActivityType.rawValue,
            locationRawValue: activity.preferredLocationType(for: selectedMode).rawValue,
            routeName: routeLaunch?.name,
            trailhead: routeLaunch?.trailhead.map(ProgramStoredCoordinate.init),
            routeCoordinates: routeLaunch?.coordinates.map(ProgramStoredCoordinate.init) ?? [],
            phases: phases.count > 1 ? phases : nil,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: expiresAt,
            sourceDeviceLabel: isPadDevice ? "iPad" : "iPhone"
        )
    }

    private func applyPlan(_ plan: ProgramWorkoutPlanRecord) {
        selectedActivityIDs = plan.selectedActivityIDs
        availableMinutes = Double(plan.availableMinutes)
        selectedMode = ProgramBuilderMode(rawValue: plan.modeRawValue) ?? .guided
        selectedPlanDepth = ProgramPlanDepth(rawValue: plan.selectedPlanDepthRawValue) ?? .simple
        allocationWeights = plan.allocationWeights
        selectedTargetMetric = ProgramTargetMetric(rawValue: plan.targetMetricRawValue ?? ProgramTargetMetric.pace.rawValue) ?? .pace
        selectedZone = plan.selectedZone
        targetValueText = plan.targetValueText
        routeObjectiveName = plan.routeObjectiveName
        routeRepeats = plan.routeRepeats
        selectedRouteTemplateID = plan.selectedRouteTemplateID
        planner.generatedBlueprint = plan.blueprint
        let hydratedPhases = plan.resolvedPhases.map { phase -> (String, [ProgramCustomWorkoutMicroStage], [ProgramWorkoutCircuitGroup]) in
            let hydratedStages = hydratedCircuitStages(
                phase.microStages ?? [],
                existingGroups: phase.circuitGroups ?? []
            )
            return (phase.activityID, hydratedStages, inferredCircuitGroups(from: hydratedStages))
        }
        customMicroStagesByActivityID = Dictionary(
            uniqueKeysWithValues: hydratedPhases.map { ($0.0, $0.1) }
        )
        customCircuitGroupsByActivityID = Dictionary(
            uniqueKeysWithValues: hydratedPhases.map { ($0.0, $0.2) }
        )
        plannedRouteLaunchMetadata = RouteLaunchMetadata(
            name: plan.routeName ?? "",
            trailhead: plan.trailheadCoordinate,
            coordinates: plan.routeCoordinateValues
        )
        planSyncStatusMessage = plan.expiresAt == nil
            ? "Loaded repository plan into Program Builder."
            : "Loaded temporary plan from \(plan.sourceDeviceLabel)."
        rebalanceWeights(for: selectedActivityIDs)
        syncTargetMetric()
        syncStageActivitySelection()
        persistBuilderDraft()
    }

    private func persistBuilderDraft() {
        let draft = ProgramBuilderDraftState(
            selectedModeRawValue: selectedMode.rawValue,
            selectedPlanDepthRawValue: selectedPlanDepth.rawValue,
            selectedActivityIDs: selectedActivityIDs,
            availableMinutes: availableMinutes,
            allocationWeights: allocationWeights,
            activityMinutes: activityMinutes,
            selectedRouteWorkoutID: selectedRouteWorkoutID,
            selectedTargetMetricRawValue: selectedTargetMetric.rawValue,
            selectedZone: selectedZone,
            targetValueText: targetValueText,
            routeObjectiveName: routeObjectiveName,
            routeRepeats: routeRepeats,
            selectedRouteTemplateID: selectedRouteTemplateID,
            selectedBuilderTabRawValue: selectedBuilderTab.rawValue,
            selectedStageActivityID: selectedStageActivityID,
            customMicroStagesByActivityID: customMicroStagesByActivityID,
            customCircuitGroupsByActivityID: customCircuitGroupsByActivityID,
            coachRegenerationNotesByActivityID: coachRegenerationNotesByActivityID,
            coachAdvice: planner.coachAdvice,
            generatedBlueprint: planner.generatedBlueprint,
            updatedAt: Date()
        )
        planStore.saveDraft(draft)
    }

    private func restoreCachedDraftIfNeeded() {
        guard !hasRestoredCachedDraft else { return }
        hasRestoredCachedDraft = true
        guard let draft = planStore.cachedDraft else { return }

        selectedMode = ProgramBuilderMode(rawValue: draft.selectedModeRawValue) ?? .guided
        selectedPlanDepth = ProgramPlanDepth(rawValue: draft.selectedPlanDepthRawValue) ?? .simple
        selectedActivityIDs = draft.selectedActivityIDs
        availableMinutes = draft.availableMinutes
        allocationWeights = draft.allocationWeights
        selectedTargetMetric = ProgramTargetMetric(rawValue: draft.selectedTargetMetricRawValue) ?? .pace
        selectedZone = draft.selectedZone
        targetValueText = draft.targetValueText
        routeObjectiveName = draft.routeObjectiveName
        routeRepeats = draft.routeRepeats
        selectedRouteTemplateID = draft.selectedRouteTemplateID
        selectedRouteWorkoutID = draft.selectedRouteWorkoutID
        activityMinutes = draft.activityMinutes
        selectedBuilderTab = ProgramBuilderTab(rawValue: draft.selectedBuilderTabRawValue ?? ProgramBuilderTab.overview.rawValue) ?? .overview
        selectedStageActivityID = draft.selectedStageActivityID
        customMicroStagesByActivityID = draft.customMicroStagesByActivityID
        customCircuitGroupsByActivityID = draft.customCircuitGroupsByActivityID
        coachRegenerationNotesByActivityID = draft.coachRegenerationNotesByActivityID
        if let coachAdvice = draft.coachAdvice, !coachAdvice.isEmpty {
            planner.coachAdvice = coachAdvice
        }
        planner.generatedBlueprint = draft.generatedBlueprint
        syncStageActivitySelection()
    }

    private func toggleActivity(_ id: String) {
        if selectedActivityIDs.contains(id) {
            removeActivity(id)
        } else {
            selectedActivityIDs.append(id)
            activityMinutes[id] = activityMinutes[id] ?? 30
            selectedRouteWorkoutID = id
        }
    }

    private func removeActivity(_ id: String) {
        selectedActivityIDs.removeAll { $0 == id }
        activityMinutes.removeValue(forKey: id)
        customMicroStagesByActivityID.removeValue(forKey: id)
        customCircuitGroupsByActivityID.removeValue(forKey: id)
        coachRegenerationNotesByActivityID.removeValue(forKey: id)
        if selectedRouteWorkoutID == id {
            selectedRouteWorkoutID = selectedActivities.first?.id
        }
        if selectedActivities.isEmpty {
            targetValueText = ""
        }
    }

    private func addCustomActivity() {
        let trimmed = customActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slug = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !slug.isEmpty else { return }
        guard customActivities.contains(where: { $0.id == slug }) == false else {
            toggleActivity(slug)
            customActivityName = ""
            return
        }

        let item = ProgramWorkoutType(
            id: slug,
            title: trimmed,
            subtitle: "Custom activity",
            symbol: "sparkles",
            category: .hybrid,
            tint: .orange,
            keywords: [trimmed.lowercased(), "custom"],
            supportedTargets: [.heartRateZone, .pace, .power, .cadence, .distance],
            routeFriendly: true,
            aliasMatches: [trimmed.lowercased()]
        )
        customActivities.append(item)
        selectedActivityIDs.append(item.id)
        activityMinutes[item.id] = 30
        selectedRouteWorkoutID = item.id
        customActivityName = ""
    }

    private func rebalanceWeights(for ids: [String]) {
        let active = Set(ids)
        activityMinutes = activityMinutes.filter { active.contains($0.key) }
        for id in ids where activityMinutes[id] == nil {
            activityMinutes[id] = 30
        }
    }

    private func syncTargetMetric() {
        let supportedTargets = availableTargetMetrics
        guard !supportedTargets.isEmpty else { return }
        if !supportedTargets.contains(selectedTargetMetric) {
            selectedTargetMetric = supportedTargets.first ?? .heartRateZone
        }
    }

    private func syncStageActivitySelection() {
        if let selectedStageActivityID,
           selectedActivityIDs.contains(selectedStageActivityID) {
            return
        }
        self.selectedStageActivityID = selectedActivities.first?.id
    }

    private func allocationText(for id: String) -> String {
        let minutes = max(1, activityMinutes[id, default: 30])
        return "\(minutes) min"
    }

    private func buildPlannerRequest() -> ProgramPlannerRequest {
        let route = selectedMode == .route
            ? ProgramPlannerRequest.RoutePreference(
                name: routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines),
                repeats: routeRepeats,
                templateName: selectedRouteTemplate?.workout.workoutActivityType.name
            )
            : nil

        let totalMinutes = selectedActivities.reduce(0) { total, activity in
            total + allocationMinutes(for: activity.id)
        }

        return ProgramPlannerRequest(
            selectedActivities: selectedActivities,
            availableMinutes: totalMinutes,
            mode: selectedMode,
            planDepth: selectedPlanDepth,
            allocations: selectedActivities.reduce(into: [:]) { partial, activity in
                partial[activity.title] = allocationText(for: activity.id)
            },
            target: nil,
            route: route,
            microStagesByActivity: Dictionary(
                uniqueKeysWithValues: selectedActivities.map { activity in
                    (activity.title, resolvedMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id)))
                }
            ),
            normalizedRegenerationNote: selectedStageActivity.flatMap { normalizedCoachRegenerationNote(for: $0) } ?? "",
            recentWorkouts: engine.workoutAnalytics.map { insight(from: $0.workout, analytics: $0.analytics) },
            recoveryScore: engine.recoveryScore,
            readinessScore: engine.readinessScore,
            strainScore: engine.strainScore
        )
    }

    private func normalizedCoachRegenerationNote(for activity: ProgramWorkoutType) -> String {
        normalizeCoachRegenerationText(coachRegenerationNotesByActivityID[activity.id, default: ""])
    }

    private func ensureMicroStagesAreReady() {
        let activeIDs = Set(selectedActivityIDs)
        customMicroStagesByActivityID = customMicroStagesByActivityID.filter { activeIDs.contains($0.key) }
        customCircuitGroupsByActivityID = customCircuitGroupsByActivityID.filter { activeIDs.contains($0.key) }
        coachRegenerationNotesByActivityID = coachRegenerationNotesByActivityID.filter { activeIDs.contains($0.key) }

        guard selectedPlanDepth == .comprehensive else { return }

        for activity in selectedActivities where (customMicroStagesByActivityID[activity.id] ?? []).isEmpty {
            customMicroStagesByActivityID[activity.id] = defaultMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
            customCircuitGroupsByActivityID[activity.id] = defaultCircuitGroups(for: activity, stages: customMicroStagesByActivityID[activity.id] ?? [])
        }
    }

    private func resolvedMicroStages(for activity: ProgramWorkoutType, totalMinutes: Int? = nil) -> [ProgramCustomWorkoutMicroStage] {
        let resolvedMinutes = max(totalMinutes ?? allocationMinutes(for: activity.id), 5)
        guard selectedPlanDepth == .comprehensive else {
            return [simpleStage(for: activity, totalMinutes: resolvedMinutes)]
        }
        if let stored = customMicroStagesByActivityID[activity.id], !stored.isEmpty {
            return hydratedCircuitStages(
                stored.map { normalizeStage($0, for: activity) },
                existingGroups: customCircuitGroupsByActivityID[activity.id] ?? []
            )
        }
        return hydratedCircuitStages(
            defaultMicroStages(for: activity, totalMinutes: resolvedMinutes),
            existingGroups: customCircuitGroupsByActivityID[activity.id] ?? []
        )
    }

    private func resolvedCircuitGroups(for activity: ProgramWorkoutType, totalMinutes: Int? = nil) -> [ProgramWorkoutCircuitGroup] {
        let resolvedStages = resolvedMicroStages(for: activity, totalMinutes: totalMinutes)
        let stored = customCircuitGroupsByActivityID[activity.id] ?? []
        let groups = inferredCircuitGroups(from: resolvedStages, existing: stored)
        if !groups.isEmpty {
            return groups
        }
        return defaultCircuitGroups(for: activity, stages: resolvedStages)
    }

    private func simpleStage(for activity: ProgramWorkoutType, totalMinutes: Int) -> ProgramCustomWorkoutMicroStage {
        let goal: ProgramMicroStageGoal
        let targetValue: String

        if selectedMode == .route, activity.routeFriendly {
            goal = .distance
            let routeName = routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
            targetValue = routeName.isEmpty ? "route x\(routeRepeats)" : "\(routeName) x\(routeRepeats)"
        } else {
            goal = .time
            targetValue = ""
        }

        return normalizeStage(ProgramCustomWorkoutMicroStage(
            title: activity.title,
            notes: "",
            role: .goal,
            goal: goal,
            plannedMinutes: max(totalMinutes, 5),
            repeats: 1,
            targetValueText: targetValue,
            repeatSetLabel: "",
            targetBehavior: .completionGoal
        ), for: activity)
    }

    private func defaultMicroStages(for activity: ProgramWorkoutType, totalMinutes: Int) -> [ProgramCustomWorkoutMicroStage] {
        [simpleStage(for: activity, totalMinutes: max(totalMinutes, 5))]
    }

    private func defaultCircuitGroups(for activity: ProgramWorkoutType, stages: [ProgramCustomWorkoutMicroStage]) -> [ProgramWorkoutCircuitGroup] {
        inferredCircuitGroups(from: stages).map { group in
            ProgramWorkoutCircuitGroup(id: group.id, title: group.title, repeats: group.repeats)
        }
    }

    private func normalizedTargetDescriptor() -> String {
        if selectedTargetMetric == .heartRateZone {
            return "Zone \(selectedZone)"
        }
        return targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func goalForActivity(_ activity: ProgramWorkoutType, defaultGoal: ProgramMicroStageGoal) -> ProgramMicroStageGoal {
        if selectedMode == .route, activity.routeFriendly {
            return .distance
        }
        return defaultGoal
    }

    private func targetDescriptorForActivity(_ activity: ProgramWorkoutType, defaultValue: String) -> String {
        if selectedMode == .route, activity.routeFriendly {
            let routeName = routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
            return routeName.isEmpty ? "route x\(routeRepeats)" : "\(routeName) x\(routeRepeats)"
        }
        return defaultValue
    }

    private func allowedGoals(for role: ProgramMicroStageRole, activity: ProgramWorkoutType) -> [ProgramMicroStageGoal] {
        activity.supportedMicroStageGoals(for: role)
    }

    private func defaultMainGoal(for activity: ProgramWorkoutType) -> ProgramMicroStageGoal {
        if selectedMode == .route, activity.routeFriendly {
            return .distance
        }
        return allowedGoals(for: .goal, activity: activity).first ?? .time
    }

    private func preferredSteadyOrWorkGoal(for activity: ProgramWorkoutType) -> ProgramMicroStageGoal {
        if selectedMode == .route, activity.routeFriendly {
            return .distance
        }
        return allowedGoals(for: .steady, activity: activity).first ?? .time
    }

    private func defaultDescriptor(for goal: ProgramMicroStageGoal) -> String {
        switch goal {
        case .heartRateZone:
            return "Zone 2"
        case .power:
            return "220-260 W"
        case .pace:
            return "7:10-7:30 /mi"
        case .speed:
            return "18-20 mph"
        case .cadence:
            return "100-110 rpm"
        case .distance:
            return "5 km"
        case .energy:
            return "300 kcal"
        case .open, .time:
            return ""
        }
    }

    private func normalizeStage(_ stage: ProgramCustomWorkoutMicroStage, for activity: ProgramWorkoutType?) -> ProgramCustomWorkoutMicroStage {
        guard let activity else { return stage }
        var updated = stage
        let allowed = allowedGoals(for: updated.role, activity: activity)
        if !allowed.contains(updated.goal) {
            updated.goal = allowed.first ?? .time
        }
        updated.targetBehavior = updated.role.defaultTargetBehavior
        if updated.goal.requiresDescriptorInput && updated.targetValueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.targetValueText = defaultDescriptor(for: updated.goal)
        }
        if !updated.goal.requiresDescriptorInput {
            updated.targetValueText = ""
        }
        if updated.circuitGroupID == nil {
            updated.repeatSetLabel = ""
        }
        return updated
    }

    private func inferredCircuitGroups(from stages: [ProgramCustomWorkoutMicroStage]) -> [ProgramWorkoutCircuitGroup] {
        Dictionary(grouping: hydratedCircuitStages(stages).compactMap { stage -> (UUID, String, Int)? in
            guard let circuitGroupID = stage.circuitGroupID else { return nil }
            return (circuitGroupID, stage.repeatSetLabel.isEmpty ? "Coupled Circuit" : stage.repeatSetLabel, max(stage.repeats, 1))
        }, by: { $0.0 }).values.compactMap { entries in
            guard let first = entries.first else { return nil }
            return ProgramWorkoutCircuitGroup(id: first.0, title: first.1, repeats: first.2)
        }
        .sorted { $0.title < $1.title }
    }

    private func inferredCircuitGroups(
        from stages: [ProgramCustomWorkoutMicroStage],
        existing: [ProgramWorkoutCircuitGroup]
    ) -> [ProgramWorkoutCircuitGroup] {
        let hydrated = hydratedCircuitStages(stages, existingGroups: existing)
        return Dictionary(grouping: hydrated.compactMap { stage -> (UUID, String, Int)? in
            guard let circuitGroupID = stage.circuitGroupID else { return nil }
            return (circuitGroupID, stage.repeatSetLabel.isEmpty ? "Coupled Circuit" : stage.repeatSetLabel, max(stage.repeats, 1))
        }, by: { $0.0 }).values.compactMap { entries in
            guard let first = entries.first else { return nil }
            if let existingGroup = existing.first(where: { $0.id == first.0 }) {
                return ProgramWorkoutCircuitGroup(id: existingGroup.id, title: existingGroup.title, repeats: first.2)
            }
            return ProgramWorkoutCircuitGroup(id: first.0, title: first.1, repeats: first.2)
        }
        .sorted { $0.title < $1.title }
    }

    private func hydratedCircuitStages(
        _ stages: [ProgramCustomWorkoutMicroStage],
        existingGroups: [ProgramWorkoutCircuitGroup] = []
    ) -> [ProgramCustomWorkoutMicroStage] {
        guard !stages.isEmpty else { return stages }

        var updated = stages
        let groupsByID = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.id, $0) })
        let groupsByTitle = Dictionary(uniqueKeysWithValues: existingGroups.map {
            ($0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
        })

        for index in updated.indices {
            if let groupID = updated[index].circuitGroupID,
               let existing = groupsByID[groupID] {
                updated[index].repeatSetLabel = existing.title
                updated[index].repeats = max(updated[index].repeats, existing.repeats)
            }
        }

        let groupedByLabel = Dictionary(grouping: updated.indices.filter {
            updated[$0].circuitGroupID == nil &&
            !updated[$0].repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, by: {
            updated[$0].repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        for (normalizedLabel, indices) in groupedByLabel where indices.count >= 2 {
            guard let firstIndex = indices.first else { continue }
            let rawLabel = updated[firstIndex].repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = groupsByTitle[normalizedLabel] ?? ProgramWorkoutCircuitGroup(
                title: rawLabel.isEmpty ? "Coupled Circuit" : rawLabel,
                repeats: indices.map { max(updated[$0].repeats, 1) }.max() ?? 1
            )
            for index in indices {
                updated[index].circuitGroupID = group.id
                updated[index].repeatSetLabel = group.title
                updated[index].repeats = max(updated[index].repeats, group.repeats)
            }
        }

        return updated
    }

    private func mappedGoal(for metric: ProgramTargetMetric) -> ProgramMicroStageGoal {
        switch metric {
        case .pace:
            return .pace
        case .power:
            return .power
        case .heartRateZone:
            return .heartRateZone
        case .cadence:
            return .cadence
        case .distance:
            return .distance
        }
    }

    private var planningOverviewTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Planning Mode", selection: $selectedMode) {
                ForEach([ProgramBuilderMode.guided, ProgramBuilderMode.route]) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch selectedMode {
            case .guided:
                guidedPlanningView
            case .route:
                routePlanningView
            }
        }
    }

    private var workoutStagesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout Stages")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Comprehensive lets each selected workout carry its own warmup, repeat sets, recovery steps, and cooldown.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Text(selectedPlanDepth.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
            }

            if selectedActivities.isEmpty {
                ProgramEmptyState(
                    title: "Choose a workout first",
                    subtitle: "Selected workouts show up here so you can shape each one from simple or comprehensive stages."
                )
            } else {
                stageActivityFilterBar

                if let activity = selectedStageActivity {
                    if selectedPlanDepth == .simple {
                        simpleWorkoutStageView(for: activity)
                    } else {
                        comprehensiveWorkoutStageEditor(for: activity)
                    }
                }
            }
        }
    }

    private var stageActivityFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(selectedActivities) { activity in
                    Button {
                        selectedStageActivityID = activity.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: activity.symbol)
                            Text(activity.title)
                                .font(.subheadline.weight(.semibold))
                            Text(allocationText(for: activity.id))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.2), in: Capsule())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            (selectedStageActivityID == activity.id ? activity.tint.opacity(0.9) : Color.white.opacity(0.14)),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func simpleWorkoutStageView(for activity: ProgramWorkoutType) -> some View {
        let stage = simpleStage(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        return VStack(alignment: .leading, spacing: 12) {
            Label(activity.title, systemImage: activity.symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(stage.simpleSummary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            Text("Switch to Comprehensive if you want repeatable micro-stages like warmup, pace work, HR resets, power work, and cooldown inside this one workout type.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(16)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func comprehensiveWorkoutStageEditor(for activity: ProgramWorkoutType) -> some View {
        let stages = resolvedMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(activity.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    addMicroStage(for: activity)
                } label: {
                    Label("Add Stage", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.glass)
                .foregroundStyle(.white)

                Button {
                    isWorkoutStagesViewPresented = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.black))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 14) {
                if !stages.isEmpty {
                    Text("Swipe through stages here, or open the full editor to see the whole workout at once.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))

                    stagePreviewRail(
                        activity: activity,
                        stages: stages,
                        totalStages: stages.count
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func stagePreviewRail(
        activity: ProgramWorkoutType,
        stages: [ProgramCustomWorkoutMicroStage],
        totalStages: Int
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(stages) { stage in
                    microStageEditorCard(
                        for: activity,
                        stage: stage,
                        index: stageIndex(for: activity.id, stageID: stage.id) ?? 0,
                        stageCount: totalStages,
                        isCollapsed: collapsedStageIDs.contains(stage.id),
                        onToggleCollapsed: {
                            toggleCollapsedState(for: stage.id)
                        }
                    )
                    .frame(width: 308)
                }
            }
        }
        .padding(.vertical, 2)
        .onPreferenceChange(ProgramStageCardHeightPreferenceKey.self) { newHeight in
            guard newHeight > 0 else { return }
            stageCardHeightByActivityID[activity.id] = newHeight
        }
    }

    @ViewBuilder
    private func stageEditorGrid(
        activity: ProgramWorkoutType,
        stages: [ProgramCustomWorkoutMicroStage],
        totalStages: Int,
        availableWidth: CGFloat? = nil
    ) -> some View {
        let width = availableWidth ?? 720
        let columns = stageEditorColumns(for: width)

        if columns.count == 1 {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(stages) { stage in
                    microStageEditorCard(
                        for: activity,
                        stage: stage,
                        index: stageIndex(for: activity.id, stageID: stage.id) ?? 0,
                        stageCount: totalStages,
                        isCollapsed: collapsedStageIDs.contains(stage.id),
                        onToggleCollapsed: {
                            toggleCollapsedState(for: stage.id)
                        }
                    )
                }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(stages) { stage in
                    microStageEditorCard(
                        for: activity,
                        stage: stage,
                        index: stageIndex(for: activity.id, stageID: stage.id) ?? 0,
                        stageCount: totalStages,
                        isCollapsed: collapsedStageIDs.contains(stage.id),
                        onToggleCollapsed: {
                            toggleCollapsedState(for: stage.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func circuitGroupEditorCard(
        for activity: ProgramWorkoutType,
        group: ProgramWorkoutCircuitGroup
    ) -> some View {
        let stages = stages(for: activity.id, in: group)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Alternates \(group.repeats)x")
                        .font(.footnote)
                        .foregroundStyle(.orange.opacity(0.88))
                }
                Spacer()
                wheelMetricPicker(title: "Repeats", selection: circuitRepeatsWheelBinding(activityID: activity.id, groupID: group.id), options: repeatWheelOptions)
                    .frame(width: 120)
                Button(role: .destructive) {
                    removeCircuitGroup(for: activity, groupID: group.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            if !stages.isEmpty {
                stageEditorGrid(activity: activity, stages: stages, totalStages: resolvedMicroStages(for: activity).count)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func microStageEditorCard(
        for activity: ProgramWorkoutType,
        stage: ProgramCustomWorkoutMicroStage,
        index: Int,
        stageCount: Int,
        isCollapsed: Bool = false,
        onToggleCollapsed: (() -> Void)? = nil
    ) -> some View {
        let stageBinding = comprehensiveStageBinding(activityID: activity.id, stageID: stage.id)
        let availableGoals = allowedGoals(for: stageBinding.role.wrappedValue, activity: activity)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Stage name", text: stageBinding.title)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(role: .destructive) {
                    removeMicroStage(for: activity, at: index)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.bordered)
                .disabled(stageCount <= 1)
            }

            HStack(spacing: 8) {
                if let onToggleCollapsed {
                    Button(action: onToggleCollapsed) {
                        Label(isCollapsed ? "Expand" : "Collapse", systemImage: isCollapsed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    moveMicroStage(for: activity, from: index, to: index - 1)
                } label: {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.bordered)
                .disabled(index == 0)

                Button {
                    moveMicroStage(for: activity, from: index, to: index + 1)
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.bordered)
                .disabled(index == stageCount - 1)

                Spacer()

                Text("Stage \(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.66))
            }

            if isCollapsed {
                collapsedStageSummary(for: stageBinding.wrappedValue, index: index)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    compactMenuField(title: "Role") {
                        Picker("Role", selection: stageBinding.role) {
                            ForEach(ProgramMicroStageRole.allCases) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    compactMenuField(title: "Goal") {
                        Picker("Goal", selection: stageBinding.goal) {
                            ForEach(availableGoals) { goal in
                                Text(goal.title).tag(goal)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    wheelMetricPicker(
                        title: "Minutes",
                        selection: plannedMinutesWheelBinding(activityID: activity.id, stageID: stage.id),
                        options: minuteWheelOptions
                    )

                    wheelMetricPicker(
                        title: "Repeats",
                        selection: stageRepeatsWheelBinding(activityID: activity.id, stageID: stage.id),
                        options: repeatWheelOptions
                    )
                }

                if stageBinding.goal.wrappedValue.requiresDescriptorInput {
                    stageTargetEditor(for: activity, stageID: stage.id)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe This Stage")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))

                    TextField(
                        "Example: hold 90-100 rpm for 5 minutes",
                        text: stagePromptBinding(stageID: stage.id),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        applyNaturalLanguageStagePrompt(for: activity, stageID: stage.id)
                    } label: {
                        Label("Apply Description", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.white)
                }

                TextField("Notes", text: stageBinding.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(alignment: .top, spacing: 10) {
                    Text(stageBinding.wrappedValue.displaySummary)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(stageBinding.wrappedValue.targetBehavior.editorDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }
        }
        .frame(minHeight: isCollapsed ? nil : stageCardHeightByActivityID[activity.id], alignment: .top)
        .padding(12)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ProgramStageCardHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
    }

    @ViewBuilder
    private func collapsedStageSummary(for stage: ProgramCustomWorkoutMicroStage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(stage.role.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange, in: Capsule())

                if !stage.goal.title.isEmpty {
                    Text(stage.goal.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Text(stage.displaySummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)

            if !stage.notes.isEmpty {
                Text(stage.notes)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

                Text("Stage \(index + 1) at a glance")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.top, 4)
    }

    private var workoutStagesExpandedView: some View {
        GeometryReader { proxy in
            ZStack {
                GradientBackgrounds().programBuilderMeshBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Review every stage in one place. Wide windows flow into multiple columns, while narrow windows fall back to a single readable stack.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))

                        ForEach(selectedActivities) { activity in
                            workoutStagesSection(for: activity, availableWidth: proxy.size.width)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Workout Stages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    isWorkoutStagesViewPresented = false
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(allSelectedStagesCollapsed ? "Expand All" : "Collapse All") {
                    if allSelectedStagesCollapsed {
                        expandAllStages()
                    } else {
                        collapseAllStages()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workoutStagesSection(for activity: ProgramWorkoutType, availableWidth: CGFloat) -> some View {
        let stages = resolvedMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(activity.title, systemImage: activity.symbol)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(stages.count) stages")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Button {
                    addMicroStage(for: activity)
                } label: {
                    Label("Add Stage", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.glass)
                .foregroundStyle(.white)
            }

            stageEditorGrid(
                activity: activity,
                stages: stages,
                totalStages: stages.count,
                availableWidth: max(availableWidth - 40, 320)
            )
        }
        .padding(18)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(activity.tint.opacity(0.35), lineWidth: 1)
        )
    }

    private func stageEditorColumns(for width: CGFloat) -> [GridItem] {
        if width < 760 {
            return [GridItem(.flexible(), spacing: 14, alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 14, alignment: .top)]
    }

    private var allSelectedStageIDs: Set<UUID> {
        Set(
            selectedActivities.flatMap { activity in
                resolvedMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id)).map(\.id)
            }
        )
    }

    private var allSelectedStagesCollapsed: Bool {
        let ids = allSelectedStageIDs
        return !ids.isEmpty && ids.isSubset(of: collapsedStageIDs)
    }

    private func toggleCollapsedState(for stageID: UUID) {
        if collapsedStageIDs.contains(stageID) {
            collapsedStageIDs.remove(stageID)
        } else {
            collapsedStageIDs.insert(stageID)
        }
    }

    private func collapseAllStages() {
        collapsedStageIDs.formUnion(allSelectedStageIDs)
    }

    private func expandAllStages() {
        collapsedStageIDs.subtract(allSelectedStageIDs)
    }

    @ViewBuilder
    private func stageTargetEditor(for activity: ProgramWorkoutType, stageID: UUID) -> some View {
        let binding = comprehensiveStageBinding(activityID: activity.id, stageID: stageID)
        let goal = binding.goal.wrappedValue
        let behavior = binding.wrappedValue.targetBehavior

        switch goal {
        case .heartRateZone:
            Picker("HR Zone", selection: heartRateZoneWheelBinding(activityID: activity.id, stageID: stageID)) {
                ForEach(zoneWheelOptions, id: \.self) { zone in
                    Text(zone).tag(zone)
                }
            }
            .programBuilderWheelPickerCompatible(height: compactWheelHeight)

        case .cadence, .power, .speed, .distance, .energy:
            if behavior == .range {
                HStack(spacing: 10) {
                    wheelMetricPicker(title: "Min", selection: rangeComponentWheelBinding(activityID: activity.id, stageID: stageID, component: .lower), options: wheelOptions(for: goal))
                    wheelMetricPicker(title: "Max", selection: rangeComponentWheelBinding(activityID: activity.id, stageID: stageID, component: .upper), options: wheelOptions(for: goal))
                }
            } else {
                wheelMetricPicker(title: numericTargetLabel(for: behavior), selection: singleMetricWheelBinding(activityID: activity.id, stageID: stageID), options: wheelOptions(for: goal))
            }

        case .pace:
            if behavior == .range {
                HStack(spacing: 10) {
                    wheelMetricPicker(title: "Start Pace", selection: rangeComponentWheelBinding(activityID: activity.id, stageID: stageID, component: .lower), options: wheelOptions(for: goal))
                    wheelMetricPicker(title: "End Pace", selection: rangeComponentWheelBinding(activityID: activity.id, stageID: stageID, component: .upper), options: wheelOptions(for: goal))
                }
            } else {
                wheelMetricPicker(title: numericTargetLabel(for: behavior), selection: singleMetricWheelBinding(activityID: activity.id, stageID: stageID), options: wheelOptions(for: goal))
            }

        case .open, .time:
            EmptyView()
        }
    }

    private func wheelMetricPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange.opacity(0.85))
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .programBuilderWheelPickerCompatible(height: compactWheelHeight)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func compactMenuField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange.opacity(0.85))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private enum StageRangeComponent {
        case lower
        case upper
    }

    private var compactWheelHeight: CGFloat { 84 }

    private var minuteWheelOptions: [String] {
        let short = (1...15).map(String.init)
        let longer = stride(from: 20, through: 240, by: 5).map(String.init)
        return Array(NSOrderedSet(array: short + longer)) as? [String] ?? (short + longer)
    }

    private var zoneWheelOptions: [String] {
        (1...5).map { "Zone \($0)" }
    }

    private var repeatWheelOptions: [String] {
        (1...12).map(String.init)
    }

    private func wheelOptions(for goal: ProgramMicroStageGoal) -> [String] {
        switch goal {
        case .power:
            return stride(from: 50, through: 600, by: 5).map(String.init)
        case .cadence:
            return stride(from: 50, through: 220, by: 5).map(String.init)
        case .speed:
            return stride(from: 1, through: 40, by: 1).map(String.init)
        case .distance:
            return stride(from: 1, through: 50, by: 1).map(String.init)
        case .energy:
            return stride(from: 25, through: 2000, by: 25).map(String.init)
        case .pace:
            return (180...900).filter { $0 % 5 == 0 }.map { seconds in
                String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
        case .heartRateZone:
            return zoneWheelOptions
        case .open, .time:
            return []
        }
    }

    private func nearestWheelOption(for current: String, options: [String], fallback: String) -> String {
        guard !options.isEmpty else { return fallback }
        if options.contains(current) {
            return current
        }
        if let currentValue = wheelComparableValue(for: current) {
            return options.min(by: {
                abs((wheelComparableValue(for: $0) ?? currentValue) - currentValue) <
                abs((wheelComparableValue(for: $1) ?? currentValue) - currentValue)
            }) ?? fallback
        }
        return fallback
    }

    private func wheelComparableValue(for value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("zone ") {
            return Double(trimmed.replacingOccurrences(of: "zone ", with: ""))
        }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            return (minutes * 60) + seconds
        }
        if let numeric = Double(trimmed) {
            return numeric
        }

        let numericCharacters = trimmed
            .replacingOccurrences(of: ",", with: "")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .joined()

        if !numericCharacters.isEmpty, let numeric = Double(numericCharacters) {
            return numeric
        }

        return nil
    }

    private func plannedMinutesWheelBinding(activityID: String, stageID: UUID) -> Binding<String> {
        Binding(
            get: {
                let current = String(comprehensiveStageBinding(activityID: activityID, stageID: stageID).plannedMinutes.wrappedValue)
                return nearestWheelOption(for: current, options: minuteWheelOptions, fallback: "5")
            },
            set: { newValue in
                let value = min(max(Int(newValue) ?? 1, 1), 240)
                comprehensiveStageBinding(activityID: activityID, stageID: stageID).plannedMinutes.wrappedValue = value
            }
        )
    }

    private var routeRepeatsWheelBinding: Binding<String> {
        Binding(
            get: { String(routeRepeats) },
            set: { newValue in
                routeRepeats = min(max(Int(newValue) ?? 1, 1), 10)
            }
        )
    }

    private func stageRepeatsWheelBinding(activityID: String, stageID: UUID) -> Binding<String> {
        Binding(
            get: { String(comprehensiveStageBinding(activityID: activityID, stageID: stageID).repeats.wrappedValue) },
            set: { newValue in
                comprehensiveStageBinding(activityID: activityID, stageID: stageID).repeats.wrappedValue = min(max(Int(newValue) ?? 1, 1), 12)
            }
        )
    }

    private func circuitRepeatsWheelBinding(activityID: String, groupID: UUID) -> Binding<String> {
        Binding(
            get: { String(circuitGroupBinding(activityID: activityID, groupID: groupID).repeats.wrappedValue) },
            set: { newValue in
                circuitGroupBinding(activityID: activityID, groupID: groupID).repeats.wrappedValue = min(max(Int(newValue) ?? 1, 1), 12)
            }
        )
    }

    private func heartRateZoneWheelBinding(activityID: String, stageID: UUID) -> Binding<String> {
        Binding(
            get: {
                let stage = comprehensiveStageBinding(activityID: activityID, stageID: stageID).wrappedValue
                let zone = stage.targetValueText.captureGroups(for: #"zone\s*(\d+)"#).first?.first.flatMap(Int.init) ?? 2
                return "Zone \(min(max(zone, 1), 5))"
            },
            set: { newValue in
                comprehensiveStageBinding(activityID: activityID, stageID: stageID).targetValueText.wrappedValue = newValue
            }
        )
    }

    private func rangeComponentWheelBinding(
        activityID: String,
        stageID: UUID,
        component: StageRangeComponent
    ) -> Binding<String> {
        Binding(
            get: {
                let goal = comprehensiveStageBinding(activityID: activityID, stageID: stageID).goal.wrappedValue
                let options = wheelOptions(for: goal)
                let raw = comprehensiveStageBinding(activityID: activityID, stageID: stageID).targetValueText.wrappedValue
                let parts = normalizedRangeParts(from: raw)
                switch component {
                case .lower:
                    return nearestWheelOption(for: parts.first ?? "", options: options, fallback: options.first ?? "")
                case .upper:
                    return nearestWheelOption(for: parts.count > 1 ? parts[1] : "", options: options, fallback: options.dropFirst().first ?? options.first ?? "")
                }
            },
            set: { newValue in
                let goal = comprehensiveStageBinding(activityID: activityID, stageID: stageID).goal.wrappedValue
                let current = comprehensiveStageBinding(activityID: activityID, stageID: stageID).targetValueText.wrappedValue
                var parts = normalizedRangeParts(from: current)
                if parts.isEmpty { parts = ["", ""] }
                if parts.count == 1 { parts.append("") }
                switch component {
                case .lower:
                    parts[0] = newValue
                case .upper:
                    parts[1] = newValue
                }
                comprehensiveStageBinding(activityID: activityID, stageID: stageID).targetValueText.wrappedValue = formattedRangeText(
                    from: parts,
                    goal: goal
                )
            }
        )
    }

    private func singleMetricWheelBinding(activityID: String, stageID: UUID) -> Binding<String> {
        Binding(
            get: {
                let goal = comprehensiveStageBinding(activityID: activityID, stageID: stageID).goal.wrappedValue
                let options = wheelOptions(for: goal)
                let current = comprehensiveStageBinding(activityID: activityID, stageID: stageID).targetValueText.wrappedValue
                return nearestWheelOption(for: current, options: options, fallback: options.first ?? "")
            },
            set: { newValue in
                comprehensiveStageBinding(activityID: activityID, stageID: stageID).targetValueText.wrappedValue = newValue
            }
        )
    }

    private func numericTargetLabel(for behavior: ProgramStageTargetBehavior) -> String {
        switch behavior {
        case .range:
            return "Range"
        case .aboveThreshold:
            return "Minimum"
        case .belowThreshold:
            return "Maximum"
        case .completionGoal:
            return "Target"
        }
    }

    private func normalizedRangeParts(from raw: String) -> [String] {
        raw.components(separatedBy: "-")
            .map { component in
                component
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: CharacterSet(charactersIn: "0123456789:.").inverted)
                    .joined()
            }
            .filter { !$0.isEmpty }
    }

    private func formattedRangeText(from parts: [String], goal: ProgramMicroStageGoal) -> String {
        let cleaned = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return "" }

        let joined = cleaned.joined(separator: "-")
        switch goal {
        case .power:
            return "\(joined) W"
        case .cadence:
            return "\(joined) rpm"
        case .speed:
            return "\(joined) mph"
        case .pace:
            return joined
        default:
            return joined
        }
    }

    private func stagePromptBinding(stageID: UUID) -> Binding<String> {
        Binding(
            get: { stagePromptTextByStageID[stageID, default: ""] },
            set: { stagePromptTextByStageID[stageID] = $0 }
        )
    }

    private func applyNaturalLanguageStagePrompt(for activity: ProgramWorkoutType, stageID: UUID) {
        let prompt = normalizeCoachRegenerationText(stagePromptTextByStageID[stageID, default: ""])
        guard !prompt.isEmpty else { return }
        var stages = customMicroStagesByActivityID[activity.id] ?? defaultMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index] = parsedStage(from: prompt, activity: activity, base: stages[index])
        customMicroStagesByActivityID[activity.id] = stages
    }

    private func parsedStage(
        from prompt: String,
        activity: ProgramWorkoutType,
        base: ProgramCustomWorkoutMicroStage
    ) -> ProgramCustomWorkoutMicroStage {
        let normalized = prompt.lowercased()
        var updated = base
        let inferredRole = stageRole(from: normalized, fallback: base.role)
        let allowed = allowedGoals(for: inferredRole, activity: activity)
        let inferredGoal = stageGoal(
            from: normalized,
            role: inferredRole,
            activity: activity,
            fallback: allowed.contains(base.goal) ? base.goal : (allowed.first ?? .time)
        )

        updated.role = inferredRole
        updated.goal = inferredGoal
        updated.targetBehavior = inferredTargetBehavior(from: normalized, goal: inferredGoal)
        updated.circuitGroupID = nil
        updated.repeatSetLabel = ""
        updated.notes = ""

        if let minutes = stageDurationMinutes(from: normalized) {
            updated.plannedMinutes = min(max(minutes, 1), 180)
        }

        if let repeats = stageRepeats(from: normalized) {
            updated.repeats = min(max(repeats, 1), 12)
        }

        if inferredGoal.requiresDescriptorInput {
            updated.targetValueText = stageDescriptor(
                from: normalized,
                goal: inferredGoal,
                fallback: updated.targetValueText.isEmpty ? defaultDescriptor(for: inferredGoal) : updated.targetValueText
            )
        } else {
            updated.targetValueText = ""
        }

        updated.title = defaultStageTitle(for: inferredRole, goal: inferredGoal)
        return normalizeStage(updated, for: activity)
    }

    private func stageRole(from text: String, fallback: ProgramMicroStageRole) -> ProgramMicroStageRole {
        if text.contains("warmup") || text.contains("warm up") {
            return .warmup
        }
        if text.contains("cooldown") || text.contains("cool down") {
            return .cooldown
        }
        if text.contains("recover") || text.contains("recovery") || text.contains("relax") || text.contains("easy") || text.contains("back off") || text.contains("tone down") {
            return .recovery
        }
        if text.contains("hold") || text.contains("maintain") || text.contains("steady") || text.contains("within") || text.contains("between") || text.contains("stay at") {
            return .steady
        }
        if text.contains("above") || text.contains("over") || text.contains("more than") || text.contains("push") || text.contains("hard") || text.contains("surge") {
            return .work
        }
        if text.contains("calorie") || text.contains("kcal") || text.contains("distance") || text.contains("mile") || text.contains("km") || text.contains("meter") || text.contains("minute") || text.contains("hour") {
            return .goal
        }
        return fallback
    }

    private func stageGoal(
        from text: String,
        role: ProgramMicroStageRole,
        activity: ProgramWorkoutType,
        fallback: ProgramMicroStageGoal
    ) -> ProgramMicroStageGoal {
        let allowed = allowedGoals(for: role, activity: activity)
        let candidates: [ProgramMicroStageGoal] = [
            text.contains("calorie") || text.contains("kcal") ? .energy : .open,
            text.contains("zone") || text.contains("heart rate") || text.contains(" hr") ? .heartRateZone : .open,
            text.contains("cadence") || text.contains("rpm") || text.contains("spm") ? .cadence : .open,
            text.contains("power") || text.contains(" watt") || text.contains("watts") ? .power : .open,
            text.contains("speed") || text.contains("mph") || text.contains("kph") || text.contains("km/h") || text.contains("m/s") ? .speed : .open,
            text.contains("/mi") || text.contains("/km") || text.contains("pace") || text.contains("split") ? .pace : .open,
            text.contains("distance") || text.contains("mile") || text.contains("km") || text.contains("lap") || text.contains("meter") ? .distance : .open,
            text.contains("minute") || text.contains("hour") || text.contains(" min") || text.contains("time") ? .time : .open
        ]

        if let goal = candidates.first(where: { $0 != .open && allowed.contains($0) }) {
            return goal
        }
        if allowed.contains(fallback) {
            return fallback
        }
        return allowed.first ?? .time
    }

    private func stageDurationMinutes(from text: String) -> Int? {
        if let hours = text.captureGroups(for: #"(\d+)\s*(hour|hours|hr|hrs)"#).first?.first,
           let value = Int(hours) {
            return value * 60
        }
        if let minutes = text.captureGroups(for: #"(\d+)\s*(minute|minutes|min|mins)"#).first?.first,
           let value = Int(minutes) {
            return value
        }
        return nil
    }

    private func stageRepeats(from text: String) -> Int? {
        if let match = text.captureGroups(for: #"(\d+)\s*(?:x|times|rounds|repeats)"#).first?.first,
           let value = Int(match) {
            return value
        }
        if let match = text.captureGroups(for: #"repeat\s*(\d+)"#).first?.first,
           let value = Int(match) {
            return value
        }
        return nil
    }

    private func inferredTargetBehavior(from text: String, goal: ProgramMicroStageGoal) -> ProgramStageTargetBehavior {
        let normalized = text.lowercased()
        // Check for threshold keywords
        if normalized.contains("above") || normalized.contains("at least") || normalized.contains("minimum") || 
           normalized.contains("more than") || normalized.contains("over ") || normalized.contains("exceeding") {
            // For certain goals, "above" means we want a minimum threshold
            switch goal {
            case .cadence, .power, .speed, .heartRateZone:
                return .aboveThreshold
            default:
                return .range
            }
        }
        if normalized.contains("below") || normalized.contains("at most") || normalized.contains("maximum") || 
           normalized.contains("less than") || normalized.contains("under ") || normalized.contains("not exceeding") {
            // For certain goals, "below" means we want a maximum threshold
            switch goal {
            case .cadence, .power, .speed, .heartRateZone:
                return .belowThreshold
            default:
                return .range
            }
        }
        // Check for range indicators - must match pattern like "90-100", "90 to 100", "90 - 100"
        let rangePatterns = [
            #"(\d+)\s*-\s*(\d+)"#,  // 90-100 or 90 - 100
            #"(\d+)\s+to\s+(\d+)"#, // 90 to 100
            #"(\d+)\s+through\s+(\d+)"#, // 90 through 100
            #"between\s+(\d+)\s+and\s+(\d+)"# // between 90 and 100
        ]
        for pattern in rangePatterns {
            if normalized.captureGroups(for: pattern).count > 0 {
                return .range
            }
        }
        return .range
    }

    private func extractRangeValues(from text: String) -> (first: String, second: String)? {
        let normalized = text.lowercased()
        // Try to extract explicit min/max range like "90-100" or "90 to 100"
        let patterns = [
            #"(\d+)\s*-\s*(\d+)"#,
            #"(\d+)\s+to\s+(\d+)"#,
            #"(\d+)\s+through\s+(\d+)"#,
            #"between\s+(\d+)\s+and\s+(\d+)"#
        ]
        for pattern in patterns {
            if let match = normalized.captureGroups(for: pattern).first, match.count >= 2 {
                return (first: match[0], second: match[1])
            }
        }
        return nil
    }

    private func stageDescriptor(from text: String, goal: ProgramMicroStageGoal, fallback: String) -> String {
        let normalized = text.lowercased()
        switch goal {
        case .heartRateZone:
            // Try extracting explicit zone range first (handles "zone 2-3", "zone 2 to 3")
            if let range = extractRangeValues(from: normalized) {
                if let val1 = Int(range.first), let val2 = Int(range.second), val1 > 0, val2 > 0 {
                    let minZone = Swift.min(val1, val2)
                    let maxZone = Swift.max(val1, val2)
                    if minZone != maxZone {
                        return "Zone \(minZone)-\(maxZone)"
                    }
                    return "Zone \(val1)"
                }
            }
            if let zone = normalized.captureGroups(for: #"zone\s*(\d+)"#).first?.first {
                return "Zone \(zone)"
            }
            // Try extracting from threshold phrases
            if let value = normalized.captureGroups(for: #"(?:above|at least|minimum|over|exceeding)\s+(?:zone\s+)?(\d+)"#).first?.first {
                return "Zone \(value)"
            }
            if let value = normalized.captureGroups(for: #"(?:below|at most|maximum|under|less than)\s+(?:zone\s+)?(\d+)"#).first?.first {
                return "Zone \(value)"
            }
        case .power:
            // Try extracting explicit range first
            if let range = extractRangeValues(from: normalized) {
                let val1 = Int(range.first) ?? 0
                let val2 = Int(range.second) ?? 0
                let minVal = Swift.min(val1, val2)
                let maxVal = Swift.max(val1, val2)
                if minVal > 0 && maxVal > 0 && minVal != maxVal {
                    return "\(minVal)-\(maxVal) W"
                }
            }
            if let value = normalized.captureGroups(for: #"(?:above|at least|minimum|over)\s+(\d+)\s*(?:w|watts?)"#).first?.first {
                return "\(value) W"
            }
            if let value = normalized.captureGroups(for: #"(?:below|at most|maximum|under)\s+(\d+)\s*(?:w|watts?)"#).first?.first {
                return "\(value) W"
            }
            if let value = normalized.captureGroups(for: #"(\d+)\s*(?:w|watts?)"#).first?.first {
                return "\(value) W"
            }
        case .cadence:
            // Try extracting explicit range first (handles "90-100 rpm", "90 - 100 rpm", "90 to 100 rpm")
            if let range = extractRangeValues(from: normalized) {
                let val1 = Int(range.first) ?? 0
                let val2 = Int(range.second) ?? 0
                let minVal = Swift.min(val1, val2)
                let maxVal = Swift.max(val1, val2)
                if minVal > 0 && maxVal > 0 && minVal != maxVal {
                    return "\(minVal)-\(maxVal) rpm"
                }
            }
            if let value = normalized.captureGroups(for: #"(?:above|at least|minimum|over|exceeding)\s+(\d+)\s*(?:rpm|spm)"#).first?.first {
                return "\(value) rpm"
            }
            if let value = normalized.captureGroups(for: #"(?:below|at most|maximum|under|less than)\s+(\d+)\s*(?:rpm|spm)"#).first?.first {
                return "\(value) rpm"
            }
            if let value = normalized.captureGroups(for: #"(\d+)\s*(?:rpm|spm)"#).first?.first {
                return "\(value) rpm"
            }
        case .pace:
            if let pace = normalized.captureGroups(for: #"(\d+:\d+(?:\s*-\s*\d+:\d+)?\s*/\s*(?:mi|km))"#).first?.first {
                return pace
            }
        case .speed:
            // Try extracting explicit range first (handles "12-15 mph", "12 - 15 kph")
            if let range = extractRangeValues(from: normalized) {
                if let unit = normalized.captureGroups(for: #"(mph|kph|km/h|m/s)"#).first?.first {
                    let val1 = Double(range.first) ?? 0
                    let val2 = Double(range.second) ?? 0
                    let minSpeed = Swift.min(val1, val2)
                    let maxSpeed = Swift.max(val1, val2)
                    if minSpeed > 0 && maxSpeed > 0 && minSpeed != maxSpeed {
                        return "\(Int(minSpeed))-\(Int(maxSpeed)) \(unit)"
                    }
                }
            }
            if let match = normalized.captureGroups(for: #"(?:above|at least|minimum|over)\s+(\d+(?:\.\d+)?)\s*(mph|kph|km/h|m/s)"#).first, match.count >= 2 {
                return "\(match[0]) \(match[1])"
            }
            if let match = normalized.captureGroups(for: #"(?:below|at most|maximum|under)\s+(\d+(?:\.\d+)?)\s*(mph|kph|km/h|m/s)"#).first, match.count >= 2 {
                return "\(match[0]) \(match[1])"
            }
            if let match = normalized.captureGroups(for: #"(\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?)\s*(mph|kph|km/h|m/s)"#).first, match.count >= 2 {
                return "\(match[0]) \(match[1])"
            }
        case .distance:
            if let match = normalized.captureGroups(for: #"(\d+(?:\.\d+)?)\s*(km|kilometers?|mi|miles?|m|meters?|laps?)"#).first {
                return "\(match[0]) \(match[1])"
            }
        case .energy:
            if let match = normalized.captureGroups(for: #"(\d+(?:\.\d+)?)\s*(kcal|calories?|cals?)"#).first {
                return "\(match[0]) \(match[1])"
            }
        case .open, .time:
            return ""
        }
        return fallback
    }

    private func defaultStageTitle(for role: ProgramMicroStageRole, goal: ProgramMicroStageGoal) -> String {
        switch role {
        case .warmup:
            return "Warmup"
        case .goal:
            switch goal {
            case .distance:
                return "Distance Goal"
            case .energy:
                return "Energy Goal"
            default:
                return "Main Goal"
            }
        case .steady:
            return "Steady \(goal.title)"
        case .work:
            return "Work \(goal.title)"
        case .recovery:
            return "Recovery"
        case .cooldown:
            return "Cooldown"
        }
    }

    private func comprehensiveStageBinding(activityID: String, stageID: UUID) -> Binding<ProgramCustomWorkoutMicroStage> {
        Binding(
            get: {
                let stages = customMicroStagesByActivityID[activityID] ?? []
                guard let stage = stages.first(where: { $0.id == stageID }) else {
                    return ProgramCustomWorkoutMicroStage(
                        title: "Stage",
                        notes: "",
                        role: .goal,
                        goal: .time,
                        plannedMinutes: 5,
                        repeats: 1,
                        targetValueText: "",
                        targetBehavior: .completionGoal
                    )
                }
                return stage
            },
            set: { newValue in
                var stages = customMicroStagesByActivityID[activityID] ?? []
                guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
                var normalized = normalizeStage(newValue, for: ProgramWorkoutType.resolve(id: activityID))
                if normalized.circuitGroupID != nil,
                   let groupID = normalized.circuitGroupID,
                   let group = customCircuitGroupsByActivityID[activityID]?.first(where: { $0.id == groupID }) {
                    normalized.repeats = group.repeats
                    normalized.repeatSetLabel = group.title
                }
                stages[index] = normalized
                customMicroStagesByActivityID[activityID] = stages
            }
        )
    }

    private func addMicroStage(for activity: ProgramWorkoutType) {
        var stages = customMicroStagesByActivityID[activity.id] ?? defaultMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        stages.append(
            normalizeStage(
                ProgramCustomWorkoutMicroStage.simpleDefault(
                    for: activity,
                    totalMinutes: max(Int(Double(allocationMinutes(for: activity.id)) / Double(max(stages.count + 1, 1))), 5)
                ),
                for: activity
            )
        )
        customMicroStagesByActivityID[activity.id] = stages
    }

    private func removeMicroStage(for activity: ProgramWorkoutType, at index: Int) {
        var stages = customMicroStagesByActivityID[activity.id] ?? []
        guard stages.indices.contains(index), stages.count > 1 else { return }
        stagePromptTextByStageID.removeValue(forKey: stages[index].id)
        stages.remove(at: index)
        customMicroStagesByActivityID[activity.id] = stages
    }

    private func moveMicroStage(for activity: ProgramWorkoutType, from source: Int, to destination: Int) {
        var stages = customMicroStagesByActivityID[activity.id] ?? []
        guard stages.indices.contains(source), stages.indices.contains(destination) else { return }
        let moved = stages.remove(at: source)
        stages.insert(moved, at: destination)
        customMicroStagesByActivityID[activity.id] = stages
    }

    private func stageIndex(for activityID: String, stageID: UUID) -> Int? {
        (customMicroStagesByActivityID[activityID] ?? []).firstIndex(where: { $0.id == stageID })
    }

    private func stages(for activityID: String, in group: ProgramWorkoutCircuitGroup) -> [ProgramCustomWorkoutMicroStage] {
        (customMicroStagesByActivityID[activityID] ?? []).filter { $0.circuitGroupID == group.id }
    }

    private func circuitGroupBinding(activityID: String, groupID: UUID) -> Binding<ProgramWorkoutCircuitGroup> {
        Binding(
            get: {
                (customCircuitGroupsByActivityID[activityID] ?? []).first(where: { $0.id == groupID })
                ?? ProgramWorkoutCircuitGroup(title: "Circuit", repeats: 2)
            },
            set: { newValue in
                var groups = customCircuitGroupsByActivityID[activityID] ?? []
                guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
                groups[index] = newValue
                customCircuitGroupsByActivityID[activityID] = groups
                var stages = customMicroStagesByActivityID[activityID] ?? []
                for stageIndex in stages.indices where stages[stageIndex].circuitGroupID == groupID {
                    stages[stageIndex].repeats = newValue.repeats
                    stages[stageIndex].repeatSetLabel = newValue.title
                }
                customMicroStagesByActivityID[activityID] = stages
            }
        )
    }

    private func addCircuitGroup(for activity: ProgramWorkoutType) {
        let group = ProgramWorkoutCircuitGroup(title: "Coupled Circuit", repeats: 4)
        var groups = customCircuitGroupsByActivityID[activity.id] ?? []
        groups.append(group)
        customCircuitGroupsByActivityID[activity.id] = groups

        var stages = customMicroStagesByActivityID[activity.id] ?? defaultMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        let primaryGoal = preferredSteadyOrWorkGoal(for: activity)
        stages.append(
            normalizeStage(
                ProgramCustomWorkoutMicroStage(
                    title: "Circuit Stage 1",
                    notes: "Maintain the assigned target for this repeat.",
                    role: .steady,
                    goal: primaryGoal,
                    plannedMinutes: 5,
                    repeats: group.repeats,
                    targetValueText: defaultDescriptor(for: primaryGoal),
                    repeatSetLabel: group.title,
                    targetBehavior: .range,
                    circuitGroupID: group.id
                ),
                for: activity
            )
        )
        stages.append(
            normalizeStage(
                ProgramCustomWorkoutMicroStage(
                    title: "Circuit Recovery",
                    notes: "Back off and reset before the next repeat.",
                    role: .recovery,
                    goal: allowedGoals(for: .recovery, activity: activity).contains(.time) ? .time : allowedGoals(for: .recovery, activity: activity).first ?? .time,
                    plannedMinutes: 1,
                    repeats: group.repeats,
                    targetValueText: "",
                    repeatSetLabel: group.title,
                    targetBehavior: .belowThreshold,
                    circuitGroupID: group.id
                ),
                for: activity
            )
        )
        customMicroStagesByActivityID[activity.id] = stages
    }

    private func removeCircuitGroup(for activity: ProgramWorkoutType, groupID: UUID) {
        customCircuitGroupsByActivityID[activity.id]?.removeAll { $0.id == groupID }
        customMicroStagesByActivityID[activity.id]?.removeAll { $0.circuitGroupID == groupID }
    }

    private func regenerateMicroStages(for activity: ProgramWorkoutType, note: String) -> [ProgramCustomWorkoutMicroStage] {
        var stages = defaultMicroStages(for: activity, totalMinutes: allocationMinutes(for: activity.id))
        guard !note.isEmpty else { return stages }

        if note.localizedCaseInsensitiveContains("longer cooldown"),
           let cooldownIndex = stages.lastIndex(where: { $0.role == .cooldown }) {
            stages[cooldownIndex].plannedMinutes += 5
        }

        if note.localizedCaseInsensitiveContains("shorter cooldown"),
           let cooldownIndex = stages.lastIndex(where: { $0.role == .cooldown }) {
            stages[cooldownIndex].plannedMinutes = max(5, stages[cooldownIndex].plannedMinutes - 5)
        }

        if note.localizedCaseInsensitiveContains("longer warmup"),
           let warmupIndex = stages.firstIndex(where: { $0.role == .warmup }) {
            stages[warmupIndex].plannedMinutes += 5
        }

        if note.localizedCaseInsensitiveContains("power"),
           let workIndices = stages.indices.filter({ stages[$0].role == .work }) as [Int]? {
            for index in workIndices {
                stages[index].goal = .power
                if stages[index].targetValueText.isEmpty {
                    stages[index].targetValueText = "steady power range"
                }
            }
        }

        if note.localizedCaseInsensitiveContains("pace"),
           let workIndices = stages.indices.filter({ stages[$0].role == .work }) as [Int]? {
            for index in workIndices {
                stages[index].goal = .pace
                if stages[index].targetValueText.isEmpty {
                    stages[index].targetValueText = "steady pace band"
                }
            }
        }

        if note.localizedCaseInsensitiveContains("zone"),
           let recoveryIndex = stages.firstIndex(where: { $0.role == .recovery || $0.goal == .heartRateZone }) {
            stages[recoveryIndex].goal = .heartRateZone
            if stages[recoveryIndex].targetValueText.isEmpty {
                stages[recoveryIndex].targetValueText = "Zone 2"
            }
        }

        if let repeats = note.firstPositiveInteger,
           let workIndex = stages.firstIndex(where: { $0.role == .work }) {
            stages[workIndex].repeats = min(max(repeats, 1), 12)
            if let recoveryIndex = stages.firstIndex(where: { $0.role == .recovery }) {
                stages[recoveryIndex].repeats = min(max(repeats, 1), 12)
            }
        }

        if note.localizedCaseInsensitiveContains("mountain biking") || note.localizedCaseInsensitiveContains("bike"),
           stages.count >= 6 {
            stages[1].repeatSetLabel = "Trail Rhythm Set"
            stages[2].repeatSetLabel = "Trail Rhythm Set"
            stages[3].repeatSetLabel = "Power Control Set"
            stages[4].repeatSetLabel = "Power Control Set"
        }

        return stages
    }

    private func launchSubtitle(for activity: ProgramWorkoutType) -> String {
        let minutesText = "\(allocationMinutes(for: activity.id)) min"
        switch selectedMode {
        case .guided:
            return "\(minutesText) • \(activity.title)"
        case .route:
            let routeName = routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
            if routeName.isEmpty {
                return "\(minutesText) • Route session"
            }
            return "\(routeName) • \(routeRepeats)x"
        }
    }

    private func routeLaunchMetadata() async -> RouteLaunchMetadata? {
        guard selectedMode == .route, !routeCompatibleActivities.isEmpty else { return nil }

        let name = routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workout = selectedRouteTemplate?.workout else {
            return name.isEmpty ? nil : RouteLaunchMetadata(name: name, trailhead: nil, coordinates: [])
        }

        let coordinates = await fetchRouteCoordinates(for: workout, maximumPoints: 120)
        let trailhead = coordinates.first
        let resolvedName = name.isEmpty ? workout.workoutActivityType.name.capitalized : name
        return RouteLaunchMetadata(name: resolvedName, trailhead: trailhead, coordinates: coordinates)
    }

    private var availableTargetMetrics: [ProgramTargetMetric] {
        guard !selectedActivities.isEmpty else { return ProgramTargetMetric.allCases }
        return ProgramTargetMetric.allCases.filter { metric in
            selectedActivities.contains { $0.supportedTargets.contains(metric) }
        }
    }

    private var targetCompatibleActivities: [ProgramWorkoutType] {
        selectedActivities.filter { $0.supportedTargets.contains(selectedTargetMetric) }
    }

    private var targetIncompatibleActivities: [ProgramWorkoutType] {
        selectedActivities.filter { !$0.supportedTargets.contains(selectedTargetMetric) }
    }

    private var targetApplicabilitySummary: String {
        if targetCompatibleActivities.count == selectedActivities.count {
            return "Target applies across every selected workout"
        }
        if targetCompatibleActivities.isEmpty {
            return "No selected workout uses this target directly"
        }
        return "Target applies to \(targetCompatibleActivities.map(\.title).joined(separator: ", "))"
    }

    private var routeCompatibleActivities: [ProgramWorkoutType] {
        selectedActivities.filter(\.routeFriendly)
    }

    private var routeIncompatibleActivities: [ProgramWorkoutType] {
        selectedActivities.filter { !$0.routeFriendly }
    }

    private var routePlanningDescription: String {
        if routeCompatibleActivities.isEmpty {
            return "Use a course, trail, or familiar loop as the anchor. Right now none of the selected workouts support route planning."
        }
        if routeIncompatibleActivities.isEmpty {
            return "Use a course, trail, or familiar loop as the anchor. The watch can show the route while the phone handles the planning step."
        }
        return "Use a course, trail, or familiar loop as the anchor for the outdoor phases, while the non-route phases keep their own structure."
    }

    private var selectedStageActivity: ProgramWorkoutType? {
        guard let selectedStageActivityID else { return selectedActivities.first }
        return selectedActivities.first(where: { $0.id == selectedStageActivityID }) ?? selectedActivities.first
    }

    private var selectedRouteWorkout: ProgramWorkoutType? {
        if let selectedRouteWorkoutID,
           let workout = selectedActivities.first(where: { $0.id == selectedRouteWorkoutID }) {
            return workout
        }
        return selectedActivities.first
    }

    private func allocationMinutes(for activityID: String) -> Int {
        return max(1, activityMinutes[activityID, default: 30])
    }

    private func loadRouteTemplateAvailability() async {
        let candidates = routeTemplateCandidates
        guard !candidates.isEmpty else {
            await MainActor.run {
                routeTemplateIDsWithSavedRoutes = []
                hasLoadedRouteTemplateAvailability = true
                if let selectedRouteTemplateID, !routeTemplateIDsWithSavedRoutes.contains(selectedRouteTemplateID) {
                    self.selectedRouteTemplateID = nil
                }
            }
            return
        }

        var idsWithRoutes: Set<UUID> = []
        for candidate in candidates {
            if await workoutHasSavedRoute(candidate.workout) {
                idsWithRoutes.insert(candidate.workout.uuid)
            }
        }

        await MainActor.run {
            routeTemplateIDsWithSavedRoutes = idsWithRoutes
            hasLoadedRouteTemplateAvailability = true
            if let selectedRouteTemplateID, !idsWithRoutes.contains(selectedRouteTemplateID) {
                self.selectedRouteTemplateID = nil
            }
        }
    }

    private func workoutHasSavedRoute(_ workout: HKWorkout) async -> Bool {
        let healthStore = HKHealthStore()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeType = HKSeriesType.workoutRoute()

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: !(samples?.isEmpty ?? true))
            }
            healthStore.execute(query)
        }
    }

    private func fetchRouteCoordinates(for workout: HKWorkout, maximumPoints: Int) async -> [CLLocationCoordinate2D] {
        let healthStore = HKHealthStore()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeType = HKSeriesType.workoutRoute()

        let route: HKWorkoutRoute? = await withCheckedContinuation { continuation in
            let sampleQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute])?.first)
            }
            healthStore.execute(sampleQuery)
        }

        guard let route else { return [] }

        let locations: [CLLocation] = await withCheckedContinuation { continuation in
            var resolvedLocations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                if let locations {
                    resolvedLocations.append(contentsOf: locations)
                }

                if done {
                    continuation.resume(returning: resolvedLocations)
                }
            }
            healthStore.execute(query)
        }

        return sampledCoordinates(from: locations.map(\.coordinate), maximumPoints: maximumPoints)
    }

    private func sampledCoordinates(from coordinates: [CLLocationCoordinate2D], maximumPoints: Int) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maximumPoints, maximumPoints > 1 else { return coordinates }

        let step = Double(coordinates.count - 1) / Double(maximumPoints - 1)
        return (0..<maximumPoints).map { index in
            let sampledIndex = Int((Double(index) * step).rounded())
            return coordinates[min(coordinates.count - 1, sampledIndex)]
        }
    }
}

private struct ProgramBuilderMetricLayoutView: View {
    @StateObject private var preferences = ProgramBuilderMetricPreferences()
    @State private var selectedActivity: HKWorkoutActivityType = .running

    private var metricOrder: [String] {
        preferences.orderedMetricIDs(for: selectedActivity)
    }

    private var metricRows: [String] {
        let disabled = preferences.availableMetricIDs(for: selectedActivity).filter { !metricOrder.contains($0) }
        return metricOrder + disabled
    }

    private struct MetricRowData {
        let metricID: String
        let position: Int?
        let positionValue: Int
        let atTop: Bool
        let atBottom: Bool
        let slotText: String
    }

    var body: some View {
        let currentMetricOrder = metricOrder
        let lastIndex = currentMetricOrder.count - 1
        
        let metricRowData: [MetricRowData] = metricRows.map { metricID in
            let position = currentMetricOrder.firstIndex(of: metricID)
            let positionValue = position ?? -1
            let atTop = positionValue == 0
            let atBottom = positionValue == lastIndex
            
            let slotText: String
            if let pos = position {
                let tabNumber = (pos / 3) + 1
                let slotNumber = (pos % 3) + 1
                slotText = "Tab \(tabNumber) · Slot \(slotNumber)"
            } else {
                slotText = "Hidden"
            }
            
            let isEnabled = preferences.isMetricEnabled(metricID, for: selectedActivity)
            
            return MetricRowData(
                metricID: metricID,
                position: position,
                positionValue: positionValue,
                atTop: atTop,
                atBottom: atBottom,
                slotText: slotText
            )
        }
        
        return ZStack {
            GradientBackgrounds().programBuilderMeshBackground()

            ScrollView {
                VStack(spacing: 12) {
                    Picker("Workout", selection: $selectedActivity) {
                        Text("Running").tag(HKWorkoutActivityType.running)
                        Text("Walking").tag(HKWorkoutActivityType.walking)
                        Text("Cycling").tag(HKWorkoutActivityType.cycling)
                        Text("Hiking").tag(HKWorkoutActivityType.hiking)
                        Text("Swimming").tag(HKWorkoutActivityType.swimming)
                    }
                    .programBuilderWheelPickerCompatible(height: 120)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Metric Order")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        VStack(spacing: 10) {
                            ForEach(metricRowData, id: \.metricID) { data in
                                let isEnabledBinding = Binding(
                                    get: { preferences.isMetricEnabled(data.metricID, for: selectedActivity) },
                                    set: { newValue in
                                        preferences.setMetricEnabled(newValue, metricID: data.metricID, for: selectedActivity)
                                    }
                                )
                                
                                let moveUpAction = { preferences.moveMetric(data.metricID, direction: -1, for: selectedActivity) }
                                let moveDownAction = { preferences.moveMetric(data.metricID, direction: 1, for: selectedActivity) }
                                let canMoveUp = preferences.isMetricEnabled(data.metricID, for: selectedActivity) && data.position != nil && !data.atTop
                                let canMoveDown = preferences.isMetricEnabled(data.metricID, for: selectedActivity) && data.position != nil && !data.atBottom

                                ProgramBuilderMetricRow(
                                    title: data.metricID,
                                    slotText: data.slotText,
                                    isEnabled: isEnabledBinding,
                                    moveUp: moveUpAction,
                                    moveDown: moveDownAction,
                                    canMoveUp: canMoveUp,
                                    canMoveDown: canMoveDown
                                )
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.black.opacity(0.36))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("Workout Metric Layout")
        .toolbar {
            Button("Reset") {
                let defaults = ProgramBuilderMetricPreferences.defaultMetricIDs(for: selectedActivity)
                defaults.forEach { preferences.setMetricEnabled(true, metricID: $0, for: selectedActivity) }
            }
        }
    }
}

private enum ProgramBuilderWorkoutPageKind: String, CaseIterable, Identifiable {
    case metricsPrimary
    case metricsSecondary
    case metricsTertiary
    case metricsQuaternary
    case planTracking
    case heartRateZones
    case segments
    case splits
    case elevationGraph
    case powerGraph
    case powerZones
    case pacer
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metricsPrimary:
            return "Main Metrics"
        case .metricsSecondary:
            return "Detail Metrics"
        case .metricsTertiary:
            return "More Metrics"
        case .metricsQuaternary:
            return "Extra Metrics"
        case .planTracking:
            return "Goals & Stages"
        case .heartRateZones:
            return "HR Zones"
        case .segments:
            return "Segments"
        case .splits:
            return "Splits"
        case .elevationGraph:
            return "Elevation"
        case .powerGraph:
            return "Power"
        case .powerZones:
            return "Power Zones"
        case .pacer:
            return "Pacer"
        case .map:
            return "Map"
        }
    }

    var isAutomaticMetricPage: Bool {
        switch self {
        case .metricsPrimary, .metricsSecondary, .metricsTertiary, .metricsQuaternary:
            return true
        default:
            return false
        }
    }
}

private struct ProgramBuilderWorkoutViewsLayoutView: View {
    @StateObject private var preferences = ProgramBuilderWorkoutTabPreferences()
    @State private var selectedActivity: HKWorkoutActivityType = .running

    private var availablePages: [ProgramBuilderWorkoutPageKind] {
        ProgramBuilderWorkoutTabPreferences.availableEditablePages(for: selectedActivity)
    }

    private var orderedEditablePages: [ProgramBuilderWorkoutPageKind] {
        preferences.orderedPages(for: selectedActivity)
            .filter { availablePages.contains($0) }
    }

    private var pageRows: [ProgramBuilderWorkoutPageKind] {
        let disabled = availablePages.filter { !orderedEditablePages.contains($0) }
        return orderedEditablePages + disabled
    }

    var body: some View {
        ZStack {
            GradientBackgrounds().programBuilderMeshBackground()

            ScrollView {
                VStack(spacing: 12) {
                    Picker("Workout", selection: $selectedActivity) {
                        Text("Running").tag(HKWorkoutActivityType.running)
                        Text("Walking").tag(HKWorkoutActivityType.walking)
                        Text("Cycling").tag(HKWorkoutActivityType.cycling)
                        Text("Hiking").tag(HKWorkoutActivityType.hiking)
                        Text("Swimming").tag(HKWorkoutActivityType.swimming)
                    }
                    .programBuilderWheelPickerCompatible(height: 120)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workout Views")
                            .font(.headline)
                            .foregroundStyle(.white)

                        VStack(spacing: 10) {
                            ForEach(pageRows) { page in
                                let position = orderedEditablePages.firstIndex(of: page)
                                let atTop = position == 0
                                let atBottom = position == orderedEditablePages.count - 1

                                ProgramBuilderWorkoutViewRow(
                                    page: page,
                                    isEnabled: Binding(
                                        get: { preferences.isPageEnabled(page, for: selectedActivity) },
                                        set: { preferences.setPageEnabled($0, page: page, for: selectedActivity) }
                                    ),
                                    moveUp: {
                                        preferences.movePage(page, direction: -1, for: selectedActivity)
                                    },
                                    moveDown: {
                                        preferences.movePage(page, direction: 1, for: selectedActivity)
                                    },
                                    canMoveUp: preferences.isPageEnabled(page, for: selectedActivity) && position != nil && !atTop,
                                    canMoveDown: preferences.isPageEnabled(page, for: selectedActivity) && position != nil && !atBottom
                                )
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.black.opacity(0.36))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto Metric Pages")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Metric pages are generated from the metric order and stay in sync with the watch.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))

                        Text("Enabled metrics: \(preferences.metricCount(for: selectedActivity))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("Current metric pages: \(preferences.metricPageCount(for: selectedActivity))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.black.opacity(0.36))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(12)
            }
        }
        .navigationTitle("Workout Views")
        .toolbar {
            Button("Reset") {
                preferences.resetPagesToDefault(for: selectedActivity)
            }
        }
    }
}

private final class ProgramBuilderMetricPreferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let storageKey = "watch.workout.metricPreferences"

    private func storedData() -> Data? {
        if let cloudData = ubiquitousStore.data(forKey: storageKey) {
            return cloudData
        }
        return defaults.data(forKey: storageKey)
    }

    private func persistData(_ data: Data) {
        defaults.set(data, forKey: storageKey)
        ubiquitousStore.set(data, forKey: storageKey)
        ubiquitousStore.synchronize()
    }

    func availableMetricIDs(for activity: HKWorkoutActivityType) -> [String] {
        Self.defaultMetricIDs(for: activity)
    }

    func orderedMetricIDs(for activity: HKWorkoutActivityType) -> [String] {
        let defaultMetricIDs = Self.defaultMetricIDs(for: activity)
        guard
            let data = storedData(),
            let stored = try? JSONDecoder().decode([String: [String]].self, from: data),
            let rawMetricIDs = stored[activity.preferenceKey]
        else {
            return defaultMetricIDs
        }

        let allowed = Set(defaultMetricIDs)
        return rawMetricIDs.filter { allowed.contains($0) }
    }

    func isMetricEnabled(_ metricID: String, for activity: HKWorkoutActivityType) -> Bool {
        orderedMetricIDs(for: activity).contains(metricID)
    }

    func setMetricEnabled(_ isEnabled: Bool, metricID: String, for activity: HKWorkoutActivityType) {
        let availableMetricIDs = Self.defaultMetricIDs(for: activity)
        guard availableMetricIDs.contains(metricID) else { return }
        var metricIDs = orderedMetricIDs(for: activity)

        if isEnabled {
            if !metricIDs.contains(metricID) {
                let defaultIndex = availableMetricIDs.firstIndex(of: metricID) ?? availableMetricIDs.count
                let insertionIndex = metricIDs.firstIndex(where: { currentID in
                    (availableMetricIDs.firstIndex(of: currentID) ?? availableMetricIDs.count) > defaultIndex
                }) ?? metricIDs.count
                metricIDs.insert(metricID, at: insertionIndex)
            }
        } else {
            metricIDs.removeAll { $0 == metricID }
        }

        persist(metricIDs, for: activity)
        objectWillChange.send()
    }

    func moveMetric(_ metricID: String, direction: Int, for activity: HKWorkoutActivityType) {
        var metricIDs = orderedMetricIDs(for: activity)
        guard let index = metricIDs.firstIndex(of: metricID) else { return }
        let destination = min(max(index + direction, 0), metricIDs.count - 1)
        guard destination != index else { return }
        metricIDs.move(fromOffsets: IndexSet(integer: index), toOffset: destination > index ? destination + 1 : destination)
        persist(metricIDs, for: activity)
        objectWillChange.send()
    }

    private func persist(_ metricIDs: [String], for activity: HKWorkoutActivityType) {
        var stored: [String: [String]] = [:]
        if
            let data = storedData(),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        {
            stored = decoded
        }

        stored[activity.preferenceKey] = metricIDs
        if let data = try? JSONEncoder().encode(stored) {
            persistData(data)
        }
    }

    static func defaultMetricIDs(for activity: HKWorkoutActivityType) -> [String] {
        switch activity {
        case .running:
            return ["rolling-mile", "avg-pace", "distance", "cadence", "stride", "gct", "vo", "elev", "speed-current", "energy"]
        case .walking:
            return ["avg-pace", "distance", "cadence", "stride", "gct", "vo", "elev", "speed-current", "energy"]
        case .hiking:
            return ["distance", "avg-pace", "elev", "flights", "cadence", "stride", "energy", "speed-current"]
        case .cycling:
            return ["avg-speed", "power-current", "distance", "cadence", "power-avg", "elev", "speed-current", "energy"]
        case .swimming:
            return ["distance", "strokes", "swim-pace", "energy", "hr-avg"]
        default:
            return ["distance", "energy", "avg-speed", "cadence", "power-current", "power-avg", "elev", "hr-avg"]
        }
    }
}

private final class ProgramBuilderWorkoutTabPreferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let storageKey = "watch.workout.tabPreferences"

    private func storedData() -> Data? {
        if let cloudData = ubiquitousStore.data(forKey: storageKey) {
            return cloudData
        }
        return defaults.data(forKey: storageKey)
    }

    private func persistData(_ data: Data) {
        defaults.set(data, forKey: storageKey)
        ubiquitousStore.set(data, forKey: storageKey)
        ubiquitousStore.synchronize()
    }

    func orderedPages(for activity: HKWorkoutActivityType) -> [ProgramBuilderWorkoutPageKind] {
        let defaultPages = Self.defaultPages(for: activity)
        guard
            let data = storedData(),
            let stored = try? JSONDecoder().decode([String: [String]].self, from: data),
            let rawPages = stored[activity.preferenceKey]
        else {
            return defaultPages
        }

        let decoded = rawPages.compactMap(ProgramBuilderWorkoutPageKind.init(rawValue:))
        let allowed = Set(defaultPages + [.planTracking])
        return decoded.filter { allowed.contains($0) }
    }

    func isPageEnabled(_ page: ProgramBuilderWorkoutPageKind, for activity: HKWorkoutActivityType) -> Bool {
        if page.isAutomaticMetricPage && page != .metricsPrimary { return false }
        if page == .planTracking { return false }
        return orderedPages(for: activity).contains(page)
    }

    func setPageEnabled(_ isEnabled: Bool, page: ProgramBuilderWorkoutPageKind, for activity: HKWorkoutActivityType) {
        guard !page.isAutomaticMetricPage || page == .metricsPrimary else { return }
        guard page != .planTracking else { return }
        var pages = orderedPages(for: activity)

        if isEnabled {
            if !pages.contains(page) {
                let defaultPages = Self.defaultPages(for: activity)
                let insertionIndex = defaultPages.firstIndex(of: page).map { desiredIndex in
                    pages.firstIndex(where: { current in
                        guard let currentIndex = defaultPages.firstIndex(of: current) else { return false }
                        return currentIndex > desiredIndex
                    }) ?? pages.count
                } ?? pages.count
                pages.insert(page, at: insertionIndex)
            }
        } else {
            pages.removeAll { $0 == page }
        }

        persist(pages, for: activity)
        objectWillChange.send()
    }

    func movePage(_ page: ProgramBuilderWorkoutPageKind, direction: Int, for activity: HKWorkoutActivityType) {
        guard !page.isAutomaticMetricPage || page == .metricsPrimary else { return }
        guard page != .planTracking else { return }
        var pages = orderedPages(for: activity)
        guard let index = pages.firstIndex(of: page) else { return }
        let destination = min(max(index + direction, 0), pages.count - 1)
        guard destination != index else { return }
        pages.move(fromOffsets: IndexSet(integer: index), toOffset: destination > index ? destination + 1 : destination)
        persist(pages, for: activity)
        objectWillChange.send()
    }

    func resetPagesToDefault(for activity: HKWorkoutActivityType) {
        let defaultPages = Self.defaultPages(for: activity)
        let editablePages = Self.availableEditablePages(for: activity)

        for page in editablePages {
            setPageEnabled(defaultPages.contains(page), page: page, for: activity)
        }
    }

    func metricCount(for activity: HKWorkoutActivityType) -> Int {
        ProgramBuilderMetricPreferences().orderedMetricIDs(for: activity).count
    }

    func metricPageCount(for activity: HKWorkoutActivityType) -> Int {
        max(1, Int(ceil(Double(max(metricCount(for: activity), 1)) / 3.0)))
    }

    private func persist(_ pages: [ProgramBuilderWorkoutPageKind], for activity: HKWorkoutActivityType) {
        var stored: [String: [String]] = [:]
        if
            let data = storedData(),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        {
            stored = decoded
        }

        stored[activity.preferenceKey] = pages.map(\.rawValue)
        if let data = try? JSONEncoder().encode(stored) {
            persistData(data)
        }
    }

    static func availableEditablePages(for activity: HKWorkoutActivityType) -> [ProgramBuilderWorkoutPageKind] {
        defaultPages(for: activity)
            .filter { !$0.isAutomaticMetricPage && $0 != .planTracking }
    }

    static func defaultPages(for activity: HKWorkoutActivityType) -> [ProgramBuilderWorkoutPageKind] {
        switch activity {
        case .cycling:
            return [.metricsPrimary, .heartRateZones, .splits, .elevationGraph, .powerGraph, .powerZones, .pacer, .map]
        case .running, .walking, .hiking:
            return [.metricsPrimary, .heartRateZones, .segments, .splits, .elevationGraph, .pacer, .map]
        case .swimming:
            return [.metricsPrimary, .heartRateZones, .splits, .segments]
        default:
            return [.metricsPrimary, .heartRateZones, .splits, .map]
        }
    }
}

private struct ProgramBuilderMetricRow: View {
    let title: String
    let slotText: String
    @Binding var isEnabled: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(slotText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 12) {
                CatalystAccessibleToggle("Visible", isOn: $isEnabled)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .foregroundStyle(canMoveUp ? .white : .gray)
                    }
                    .disabled(!canMoveUp)
                    .catalystDesktopFocusable()

                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(canMoveDown ? .white : .gray)
                    }
                    .disabled(!canMoveDown)
                    .catalystDesktopFocusable()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct ProgramBuilderWorkoutViewRow: View {
    let page: ProgramBuilderWorkoutPageKind
    @Binding var isEnabled: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(page.title, systemImage: programBuilderWorkoutPageSymbol(page))
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                CatalystAccessibleToggle("Visible", isOn: $isEnabled)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .foregroundStyle(canMoveUp ? .white : .gray)
                    }
                    .disabled(!canMoveUp)
                    .catalystDesktopFocusable()

                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(canMoveDown ? .white : .gray)
                    }
                    .disabled(!canMoveDown)
                    .catalystDesktopFocusable()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private func programBuilderWorkoutPageSymbol(_ page: ProgramBuilderWorkoutPageKind) -> String {
    switch page {
    case .metricsPrimary:
        return "gauge.open.with.lines.needle.33percent"
    case .metricsSecondary:
        return "list.bullet.rectangle"
    case .metricsTertiary:
        return "filemenu.and.selection"
    case .metricsQuaternary:
        return "rectangle.grid.2x2"
    case .planTracking:
        return "list.clipboard.fill"
    case .heartRateZones:
        return "heart.text.square.fill"
    case .segments:
        return "chart.bar.xaxis"
    case .splits:
        return "flag.checkered.2.crossed"
    case .elevationGraph:
        return "mountain.2.fill"
    case .powerGraph:
        return "bolt.fill"
    case .powerZones:
        return "bolt.heart.fill"
    case .pacer:
        return "speedometer"
    case .map:
        return "map.fill"
    }
}

private extension HKWorkoutActivityType {
    var preferenceKey: String {
        switch self {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        case .swimming: return "swimming"
        default: return "other"
        }
    }
}

private struct ProgramBuilderCoachSection: View {
    @ObservedObject var planner: ProgramBuilderAIPlanner
    let request: ProgramPlannerRequest
    let refreshAction: () -> Void
    @State private var isShowingCoachDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today Coach")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Advice for the next session, with most of the attention on what is realistic today.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Button {
                    refreshAction()
                } label: {
                    if planner.isGeneratingCoach {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .buttonStyle(.glass)
                .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                ProgramStatBadge(title: "Recovery", value: "\(Int(request.recoveryScore.rounded()))", tint: .green)
                ProgramStatBadge(title: "Readiness", value: "\(Int(request.readinessScore.rounded()))", tint: .cyan)
                ProgramStatBadge(title: "Strain", value: "\(Int(request.strainScore.rounded()))", tint: .orange)
            }

            Text(planner.coachAdvice)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxHeight: 120, alignment: .top)
                .onTapGesture {
                    isShowingCoachDetail = true
                }

            if let coachError = planner.coachErrorText {
                Text(coachError)
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.9))
            }
        }
        .sheet(isPresented: $isShowingCoachDetail) {
            NavigationStack {
                ScrollView {
                    Text(planner.coachAdvice)
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding()
                }
                .navigationTitle("Today Coach")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            isShowingCoachDetail = false
                        }
                    }
                }
                .background(Color.black)
            }
        }
    }
}

private struct ProgramGeneratedBlueprintView: View {
    let blueprint: ProgramGeneratedBlueprint

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(blueprint.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(blueprint.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            if !blueprint.todayFocus.isEmpty {
                Text(blueprint.todayFocus)
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.88))
            }

            VStack(spacing: 10) {
                ForEach(blueprint.blocks.indices, id: \.self) { index in
                    let block = blueprint.blocks[index]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(block.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(block.minutes) min")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        Text(block.focus)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                        Text(block.cue)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if let note = blueprint.cautionNote, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }
}

private struct ProgramWorkoutTypeRow: View {
    let activity: ProgramWorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .frame(width: 38, height: 38)
                    .background(activity.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(activity.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? activity.tint : .white.opacity(0.55))
            }
            .padding(14)
            .background(Color.white.opacity(isSelected ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(activity.tint.opacity(isSelected ? 0.55 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProgramRouteTemplateCard: View {
    let workout: HKWorkout
    let analytics: WorkoutAnalytics
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RoutePreviewView(workout: workout, heartRates: analytics.heartRates)
                    .frame(width: 220, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(workout.workoutActivityType.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(workout.startDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))

                Text("\(Int((workout.duration / 60).rounded())) min")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .frame(width: 244, alignment: .leading)
            .background(Color.white.opacity(isSelected ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.orange.opacity(isSelected ? 0.7 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProgramSelectedActivityChip: View {
    let activity: ProgramWorkoutType
    let allocationText: String
    let removeAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbol)
                .foregroundStyle(.white.opacity(0.9))

            Text(activity.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            Text(allocationText)
                .font(.caption.weight(.bold))
                .foregroundStyle(activity.tint)

            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.white.opacity(0.12), in: Capsule())
    }
}

private struct ProgramSuggestionChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background((isSelected ? tint : Color.white.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ProgramStatBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProgramSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProgramEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ProgramLaunchButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let fixedHeight: CGFloat?
    let action: () -> Void

    private var resolvedHeight: CGFloat? {
        guard let fixedHeight else { return nil }
        return min(fixedHeight, 84)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .frame(height: resolvedHeight, alignment: .topLeading)
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
            .background {
                #if targetEnvironment(macCatalyst)
                Color.clear
                #else
                GeometryReader { geometry in
                    Color.clear.preference(key: ProgramLaunchButtonHeightPreferenceKey.self, value: geometry.size.height)
                }
                #endif
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AdaptiveChipGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(data) { item in
                content(item)
            }
        }
    }
}

private enum ProgramBuilderMode: String, CaseIterable, Identifiable {
    case guided
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guided:
            return "Time Allocation"
        case .route:
            return "Route"
        }
    }
}

private enum ProgramPlanDepth: String, CaseIterable, Identifiable {
    case simple
    case comprehensive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple:
            return "Simple"
        case .comprehensive:
            return "Comprehensive"
        }
    }
}

private enum ProgramWorkoutCategory: String, CaseIterable {
    case run = "Running"
    case ride = "Cycling"
    case endurance = "Endurance"
    case strength = "Strength"
    case recovery = "Recovery"
    case hybrid = "Hybrid"

    var title: String { rawValue }
}

private enum ProgramTargetMetric: String, CaseIterable, Identifiable {
    case pace
    case power
    case heartRateZone
    case cadence
    case distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pace: return "Pace"
        case .power: return "Power"
        case .heartRateZone: return "HR Zone"
        case .cadence: return "Cadence"
        case .distance: return "Distance"
        }
    }

    var placeholder: String {
        switch self {
        case .pace: return "Target pace or speed band"
        case .power: return "Target watts or power band"
        case .heartRateZone: return "Zone"
        case .cadence: return "Target cadence"
        case .distance: return "Distance objective"
        }
    }

    var guidance: String {
        switch self {
        case .pace:
            return "Use this when the session should stay centered on a pace or speed feel."
        case .power:
            return "Use this when the main intent is holding or repeating a power range."
        case .heartRateZone:
            return "Use this when effort control matters more than exact speed."
        case .cadence:
            return "Use this when rhythm and turnover are the anchor."
        case .distance:
            return "Use this when finishing a set distance matters more than intensity details."
        }
    }
}

enum ProgramMicroStageRole: String, CaseIterable, Codable, Hashable, Identifiable {
    case warmup
    case goal
    case steady
    case work
    case recovery
    case cooldown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup: return "Warmup"
        case .goal: return "Goal"
        case .steady: return "Steady"
        case .work: return "Work"
        case .recovery: return "Recovery"
        case .cooldown: return "Cooldown"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "simpleGoal":
            self = .goal
        default:
            self.init(rawValue: storageValue)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = ProgramMicroStageRole(storageValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ProgramMicroStageRole: \(rawValue)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ProgramMicroStageGoal: String, CaseIterable, Codable, Hashable, Identifiable {
    case open
    case time
    case distance
    case energy
    case heartRateZone
    case power
    case pace
    case speed
    case cadence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .time: return "Time"
        case .distance: return "Distance"
        case .energy: return "Energy"
        case .heartRateZone: return "HR Zone"
        case .power: return "Power"
        case .pace: return "Pace"
        case .speed: return "Speed"
        case .cadence: return "Cadence"
        }
    }

    var placeholder: String {
        switch self {
        case .distance: return "Distance target, e.g. 10 km"
        case .energy: return "Energy target, e.g. 300 kcal"
        case .heartRateZone: return "Zone 2"
        case .power: return "Power range, e.g. 220-260 W"
        case .pace: return "Pace range, e.g. 7:10-7:30 /mi"
        case .speed: return "Speed range, e.g. 18-20 mph"
        case .cadence: return "Cadence target"
        case .open, .time: return ""
        }
    }

    var requiresDescriptorInput: Bool {
        switch self {
        case .open, .time:
            return false
        default:
            return true
        }
    }
}

enum ProgramStageTargetBehavior: String, CaseIterable, Codable, Hashable, Identifiable {
    case range
    case aboveThreshold
    case belowThreshold
    case completionGoal

    var id: String { rawValue }

    var editorDescription: String {
        switch self {
        case .range:
            return "Maintain within a target range."
        case .aboveThreshold:
            return "Match or stay above the target."
        case .belowThreshold:
            return "Stay below the target or keep it easy."
        case .completionGoal:
            return "Reach the goal without threshold/range enforcement."
        }
    }
}

struct ProgramWorkoutCircuitGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var repeats: Int

    init(id: UUID = UUID(), title: String, repeats: Int) {
        self.id = id
        self.title = title
        self.repeats = repeats
    }
}

struct ProgramCustomWorkoutMicroStage: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var roleRawValue: String
    var goalRawValue: String
    var targetBehaviorRawValue: String
    var plannedMinutes: Int
    var repeats: Int
    var targetValueText: String
    var repeatSetLabel: String
    var circuitGroupID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String,
        role: ProgramMicroStageRole,
        goal: ProgramMicroStageGoal,
        plannedMinutes: Int,
        repeats: Int,
        targetValueText: String,
        repeatSetLabel: String = "",
        targetBehavior: ProgramStageTargetBehavior? = nil,
        circuitGroupID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.roleRawValue = role.rawValue
        self.goalRawValue = goal.rawValue
        self.targetBehaviorRawValue = (targetBehavior ?? role.defaultTargetBehavior).rawValue
        self.plannedMinutes = plannedMinutes
        self.repeats = repeats
        self.targetValueText = targetValueText
        self.repeatSetLabel = repeatSetLabel
        self.circuitGroupID = circuitGroupID
    }

    var role: ProgramMicroStageRole {
        get { ProgramMicroStageRole(storageValue: roleRawValue) ?? .work }
        set { roleRawValue = newValue.rawValue }
    }

    var goal: ProgramMicroStageGoal {
        get { ProgramMicroStageGoal(rawValue: goalRawValue) ?? .time }
        set { goalRawValue = newValue.rawValue }
    }

    var targetBehavior: ProgramStageTargetBehavior {
        get { ProgramStageTargetBehavior(rawValue: targetBehaviorRawValue) ?? role.defaultTargetBehavior }
        set { targetBehaviorRawValue = newValue.rawValue }
    }

    var simpleSummary: String {
        let target = targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(max(plannedMinutes, 1)) min • \(goal.title)\(target.isEmpty ? "" : " • \(target)")"
    }

    var displaySummary: String {
        let target = targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = target.isEmpty ? goal.title : "\(goal.title) \(target)"
        let groupLabel = repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let repeatText = repeats > 1 ? " • Repeat \(repeats)x" : ""
        let groupText = groupLabel.isEmpty ? "" : " • \(groupLabel)"
        return "\(role.title) • \(max(plannedMinutes, 1)) min • \(descriptor)\(repeatText)\(groupText)"
    }

    fileprivate static func simpleDefault(for activity: ProgramWorkoutType, totalMinutes: Int) -> ProgramCustomWorkoutMicroStage {
        ProgramCustomWorkoutMicroStage(
            title: activity.title,
            notes: "",
            role: .goal,
            goal: .time,
            plannedMinutes: max(totalMinutes, 5),
            repeats: 1,
            targetValueText: "",
            repeatSetLabel: "",
            targetBehavior: .completionGoal
        )
    }
}

private extension ProgramMicroStageRole {
    var defaultTargetBehavior: ProgramStageTargetBehavior {
        switch self {
        case .warmup, .goal:
            return .completionGoal
        case .steady:
            return .range
        case .work:
            return .aboveThreshold
        case .recovery, .cooldown:
            return .belowThreshold
        }
    }
}

private struct ProgramWorkoutType: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let category: ProgramWorkoutCategory
    let tint: Color
    let keywords: [String]
    let supportedTargets: [ProgramTargetMetric]
    let routeFriendly: Bool
    let aliasMatches: [String]

    static let catalog: [ProgramWorkoutType] = [
        .init(id: "running", title: "Running", subtitle: "Road, track, trail, treadmill", symbol: "figure.run", category: .run, tint: .mint, keywords: ["run", "mile", "interval", "road", "track"], supportedTargets: [.pace, .heartRateZone, .power, .cadence, .distance], routeFriendly: true, aliasMatches: ["running", "run"]),
        .init(id: "walking", title: "Walking", subtitle: "Walks, brisk efforts, incline", symbol: "figure.walk", category: .run, tint: .green, keywords: ["walk", "steps", "incline"], supportedTargets: [.pace, .heartRateZone, .distance], routeFriendly: true, aliasMatches: ["walking", "walk"]),
        .init(id: "hiking", title: "Hiking", subtitle: "Climbs, vert, long trail time", symbol: "figure.hiking", category: .endurance, tint: .teal, keywords: ["hike", "trail", "vert", "mountain"], supportedTargets: [.heartRateZone, .distance], routeFriendly: true, aliasMatches: ["hiking", "hike"]),
        .init(id: "trail-running", title: "Trail Running", subtitle: "Trails, climbs, technical terrain", symbol: "figure.run.circle", category: .run, tint: .green, keywords: ["trail", "technical", "vert"], supportedTargets: [.pace, .heartRateZone, .power, .distance], routeFriendly: true, aliasMatches: ["trail running"]),
        .init(id: "cycling", title: "Cycling", subtitle: "Road, gravel, commuting, trainer", symbol: "bicycle", category: .ride, tint: .yellow, keywords: ["bike", "ride", "cycling", "gravel", "trainer"], supportedTargets: [.power, .heartRateZone, .cadence, .distance], routeFriendly: true, aliasMatches: ["cycling", "bike", "ride"]),
        .init(id: "mountain-biking", title: "Mountain Biking", subtitle: "Singletrack, skills, trail loops", symbol: "figure.outdoor.cycle", category: .ride, tint: .green, keywords: ["mtb", "singletrack", "trail bike"], supportedTargets: [.power, .heartRateZone, .cadence, .distance], routeFriendly: true, aliasMatches: ["mountain biking", "mtb"]),
        .init(id: "swimming", title: "Swimming", subtitle: "Pool, open water, skills", symbol: "figure.pool.swim", category: .endurance, tint: .blue, keywords: ["swim", "pool", "open water"], supportedTargets: [.pace, .heartRateZone, .distance], routeFriendly: false, aliasMatches: ["swimming", "swim"]),
        .init(id: "triathlon", title: "Triathlon", subtitle: "Multi-sport build or race prep", symbol: "figure.run.treadmill", category: .hybrid, tint: .orange, keywords: ["triathlon", "brick", "multisport"], supportedTargets: [.heartRateZone, .distance], routeFriendly: true, aliasMatches: ["triathlon"]),
        .init(id: "rowing", title: "Rowing", subtitle: "Erg or on-water effort", symbol: "figure.rower", category: .endurance, tint: .cyan, keywords: ["row", "erg", "rowing"], supportedTargets: [.power, .heartRateZone, .cadence, .distance], routeFriendly: false, aliasMatches: ["rowing", "row"]),
        .init(id: "skiing", title: "Skiing", subtitle: "Resort or endurance ski day", symbol: "figure.skiing.downhill", category: .endurance, tint: .indigo, keywords: ["ski", "snow"], supportedTargets: [.heartRateZone, .distance], routeFriendly: true, aliasMatches: ["skiing"]),
        .init(id: "snowboarding", title: "Snowboarding", subtitle: "Resort laps and skill work", symbol: "figure.snowboarding", category: .endurance, tint: .purple, keywords: ["snowboard", "board"], supportedTargets: [.heartRateZone], routeFriendly: true, aliasMatches: ["snowboarding"]),
        .init(id: "strength", title: "Strength", subtitle: "Gym, home, barbell, machine", symbol: "dumbbell.fill", category: .strength, tint: .orange, keywords: ["strength", "weights", "gym", "barbell"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["traditionalstrengthtraining", "functionalstrengthtraining", "strength"]),
        .init(id: "hiit", title: "HIIT", subtitle: "Condensed, hard, high output", symbol: "flame.fill", category: .strength, tint: .red, keywords: ["hiit", "interval", "conditioning"], supportedTargets: [.heartRateZone, .power], routeFriendly: false, aliasMatches: ["highintensityintervaltraining", "hiit"]),
        .init(id: "bootcamp", title: "Bootcamp", subtitle: "Mixed conditioning and strength", symbol: "figure.mixed.cardio", category: .strength, tint: .orange, keywords: ["bootcamp", "circuit"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["bootcamp"]),
        .init(id: "yoga", title: "Yoga", subtitle: "Flow, recovery, mobility", symbol: "figure.yoga", category: .recovery, tint: .purple, keywords: ["yoga", "mobility", "flow"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["yoga"]),
        .init(id: "pilates", title: "Pilates", subtitle: "Core, control, posture", symbol: "figure.cooldown", category: .recovery, tint: .pink, keywords: ["pilates", "core"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["pilates"]),
        .init(id: "mobility", title: "Mobility", subtitle: "Range, tissue prep, reset", symbol: "figure.flexibility", category: .recovery, tint: .mint, keywords: ["mobility", "stretch", "recovery"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["mobility", "stretching"]),
        .init(id: "stretching", title: "Stretching", subtitle: "Simple and explicit range work", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", category: .recovery, tint: .cyan, keywords: ["stretch", "cool down", "cooldown"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["stretching"]),
        .init(id: "cooldown", title: "Cooldown", subtitle: "Explicit low-intensity finish", symbol: "arrow.down.circle.fill", category: .recovery, tint: .blue, keywords: ["cooldown", "cool down"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["cooldown"]),
        .init(id: "boxing", title: "Boxing", subtitle: "Bag work, skill, rounds", symbol: "figure.boxing", category: .strength, tint: .red, keywords: ["boxing", "combat", "bag"], supportedTargets: [.heartRateZone, .power], routeFriendly: false, aliasMatches: ["boxing"]),
        .init(id: "dance", title: "Dance", subtitle: "Cardio, rhythm, expression", symbol: "figure.dance", category: .hybrid, tint: .pink, keywords: ["dance", "cardio dance"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["dance"]),
        .init(id: "elliptical", title: "Elliptical", subtitle: "Low-impact cardio builder", symbol: "figure.elliptical", category: .endurance, tint: .cyan, keywords: ["elliptical", "cross trainer"], supportedTargets: [.heartRateZone, .cadence, .distance], routeFriendly: false, aliasMatches: ["elliptical"]),
        .init(id: "stair-stepper", title: "Stair Stepper", subtitle: "Climbing-focused cardio", symbol: "stairs", category: .endurance, tint: .orange, keywords: ["stairs", "stepper", "climb"], supportedTargets: [.heartRateZone, .cadence], routeFriendly: false, aliasMatches: ["stairs"]),
        .init(id: "skating", title: "Skating", subtitle: "Ice or inline rhythm work", symbol: "figure.skating", category: .endurance, tint: .blue, keywords: ["skate", "skating"], supportedTargets: [.heartRateZone, .distance], routeFriendly: true, aliasMatches: ["skating"]),
        .init(id: "paddling", title: "Paddling", subtitle: "SUP, kayak, canoe", symbol: "figure.water.fitness", category: .endurance, tint: .teal, keywords: ["paddle", "kayak", "sup"], supportedTargets: [.heartRateZone, .cadence, .distance], routeFriendly: true, aliasMatches: ["paddling"]),
        .init(id: "surfing", title: "Surfing", subtitle: "Water time, paddling, waves", symbol: "figure.surfing", category: .endurance, tint: .blue, keywords: ["surf", "ocean"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["surfing"]),
        .init(id: "climbing", title: "Climbing", subtitle: "Bouldering, routes, volume", symbol: "figure.climbing", category: .strength, tint: .green, keywords: ["climb", "boulder", "wall"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["climbing"]),
        .init(id: "soccer", title: "Soccer", subtitle: "Field sport conditioning", symbol: "soccerball", category: .hybrid, tint: .green, keywords: ["soccer", "football"], supportedTargets: [.heartRateZone, .distance], routeFriendly: true, aliasMatches: ["soccer"]),
        .init(id: "basketball", title: "Basketball", subtitle: "Court conditioning and skill", symbol: "basketball.fill", category: .hybrid, tint: .orange, keywords: ["basketball", "court"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["basketball"]),
        .init(id: "tennis", title: "Tennis", subtitle: "Court movement and repeat efforts", symbol: "tennisball.fill", category: .hybrid, tint: .yellow, keywords: ["tennis", "court", "racket"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["tennis"])
    ]

    static func searchResults(for query: String, in catalog: [ProgramWorkoutType]) -> [ProgramWorkoutType] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return catalog }

        return catalog
            .map { item -> (ProgramWorkoutType, Int) in
                let haystacks = [item.title.lowercased(), item.subtitle.lowercased(), item.category.rawValue.lowercased()] + item.keywords + item.aliasMatches
                let score = haystacks.reduce(0) { partial, field in
                    if field == trimmed { return partial + 10 }
                    if field.contains(trimmed) { return partial + 4 }
                    return partial
                }
                return (item, score)
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.title < rhs.0.title }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    static func resolve(id: String) -> ProgramWorkoutType? {
        catalog.first { $0.id == id }
    }

    static func rankFromHistory(_ workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]) -> [ProgramWorkoutType] {
        var scores: [String: Int] = [:]
        for pair in workouts {
            let normalized = pair.workout.workoutActivityType.name.lowercased()
            for item in catalog where item.aliasMatches.contains(where: { normalized.contains($0.lowercased()) }) {
                scores[item.id, default: 0] += 1
            }
        }

        return catalog.sorted { lhs, rhs in
            let left = scores[lhs.id, default: 0]
            let right = scores[rhs.id, default: 0]
            if left == right { return lhs.title < rhs.title }
            return left > right
        }
    }

    static func companionSuggestions(for selected: ProgramWorkoutType, history: [ProgramWorkoutType]) -> [ProgramWorkoutType] {
        let defaults: [String]
        switch selected.id {
        case "cycling", "mountain-biking":
            defaults = ["mobility", "cooldown", "strength", "running", "yoga"]
        case "running", "trail-running", "walking", "hiking":
            defaults = ["mobility", "strength", "cooldown", "cycling", "yoga"]
        case "triathlon":
            defaults = ["swimming", "cycling", "running", "mobility", "cooldown"]
        default:
            defaults = ["mobility", "cooldown", "yoga", "strength", "walking"]
        }

        let defaultItems = defaults.compactMap { id in catalog.first(where: { $0.id == id }) }
        let combined = defaultItems + history
        var seen: Set<String> = []
        return combined.filter { seen.insert($0.id).inserted }
    }

    var hkWorkoutActivityType: HKWorkoutActivityType {
        switch id {
        case "running", "trail-running":
            return .running
        case "walking":
            return .walking
        case "hiking":
            return .hiking
        case "cycling", "mountain-biking":
            return .cycling
        case "swimming":
            return .swimming
        case "triathlon":
            return .transition
        case "rowing":
            return .rowing
        case "skiing":
            return .crossCountrySkiing
        case "snowboarding":
            return .snowboarding
        case "strength":
            return .traditionalStrengthTraining
        case "hiit":
            return .highIntensityIntervalTraining
        case "bootcamp":
            return .mixedCardio
        case "yoga":
            return .yoga
        case "pilates":
            return .pilates
        case "mobility", "stretching":
            return .flexibility
        case "cooldown":
            return .cooldown
        case "boxing":
            return .kickboxing
        case "dance":
            return .dance
        case "elliptical":
            return .elliptical
        case "stair-stepper":
            return .stairClimbing
        case "skating":
            return .skatingSports
        case "paddling":
            return .paddleSports
        case "surfing":
            return .surfingSports
        case "climbing":
            return .climbing
        case "soccer":
            return .soccer
        case "basketball":
            return .basketball
        case "tennis":
            return .tennis
        default:
            return .other
        }
    }

    func preferredLocationType(for mode: ProgramBuilderMode) -> HKWorkoutSessionLocationType {
        if mode == .route || routeFriendly {
            return .outdoor
        }
        return .indoor
    }

    var supportedMicroStageGoals: [ProgramMicroStageGoal] {
        supportedMicroStageGoals(for: .goal)
    }

    func supportedMicroStageGoals(for role: ProgramMicroStageRole) -> [ProgramMicroStageGoal] {
        let activitySpecific: [ProgramMicroStageGoal]
        switch id {
        case "running", "trail-running":
            activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .pace, .cadence]
        case "walking", "hiking":
            activitySpecific = [.time, .distance, .heartRateZone, .pace]
        case "cycling", "mountain-biking":
            activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .speed, .cadence]
        case "swimming":
            activitySpecific = [.time, .distance, .energy, .heartRateZone, .pace]
        case "rowing":
            activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .pace, .cadence]
        case "elliptical", "stair-stepper":
            activitySpecific = [.time, .distance, .energy, .heartRateZone, .cadence, .speed]
        case "yoga", "pilates", "mobility", "stretching":
            activitySpecific = [.time, .energy]
        default:
            activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .cadence, .speed]
        }

        let roleMatrix: [ProgramMicroStageGoal]
        switch role {
        case .warmup:
            roleMatrix = [.time, .distance]
        case .goal:
            roleMatrix = [.time, .distance, .energy]
        case .steady:
            roleMatrix = [.power, .heartRateZone, .cadence, .speed, .pace]
        case .work:
            roleMatrix = [.power, .heartRateZone, .cadence, .speed, .pace]
        case .recovery:
            roleMatrix = [.time, .power, .cadence, .speed, .pace, .distance]
        case .cooldown:
            roleMatrix = [.time, .power, .cadence, .speed, .pace, .distance]
        }

        return roleMatrix.filter { activitySpecific.contains($0) }
    }
}

private struct ProgramPlannerRequest {
    struct TargetPreference {
        let metric: ProgramTargetMetric
        let descriptor: String
    }

    struct RoutePreference {
        let name: String
        let repeats: Int
        let templateName: String?
    }

    let selectedActivities: [ProgramWorkoutType]
    let availableMinutes: Int
    let mode: ProgramBuilderMode
    let planDepth: ProgramPlanDepth
    let allocations: [String: String]
    let target: TargetPreference?
    let route: RoutePreference?
    let microStagesByActivity: [String: [ProgramCustomWorkoutMicroStage]]
    let normalizedRegenerationNote: String
    let recentWorkouts: [ProgramRecentWorkout]
    let recoveryScore: Double
    let readinessScore: Double
    let strainScore: Double
}

private struct RouteLaunchMetadata {
    let name: String
    let trailhead: CLLocationCoordinate2D?
    let coordinates: [CLLocationCoordinate2D]
}

struct ProgramStoredCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ProgramBuilderDraftState: Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case selectedModeRawValue
        case selectedPlanDepthRawValue
        case selectedActivityIDs
        case availableMinutes
        case allocationWeights
        case selectedTargetMetricRawValue
        case selectedZone
        case targetValueText
        case routeObjectiveName
        case routeRepeats
        case selectedRouteTemplateID
        case selectedRouteWorkoutID
        case selectedBuilderTabRawValue
        case selectedStageActivityID
        case customMicroStagesByActivityID
        case customCircuitGroupsByActivityID
        case coachRegenerationNotesByActivityID
        case activityMinutes
        case customMicroStages
        case coachRegenerationNote
        case coachAdvice
        case generatedBlueprint
        case updatedAt
    }

    let selectedModeRawValue: String
    let selectedPlanDepthRawValue: String
    let selectedActivityIDs: [String]
    let availableMinutes: Double
    let allocationWeights: [String: Double]
    let activityMinutes: [String: Int]
    let selectedRouteWorkoutID: String?
    let selectedTargetMetricRawValue: String
    let selectedZone: Int
    let targetValueText: String
    let routeObjectiveName: String
    let routeRepeats: Int
    let selectedRouteTemplateID: UUID?
    let selectedBuilderTabRawValue: String?
    let selectedStageActivityID: String?
    let customMicroStagesByActivityID: [String: [ProgramCustomWorkoutMicroStage]]
    let customCircuitGroupsByActivityID: [String: [ProgramWorkoutCircuitGroup]]
    let coachRegenerationNotesByActivityID: [String: String]
    let coachAdvice: String?
    let generatedBlueprint: ProgramGeneratedBlueprint?
    let updatedAt: Date

    init(
        selectedModeRawValue: String,
        selectedPlanDepthRawValue: String,
        selectedActivityIDs: [String],
        availableMinutes: Double,
        allocationWeights: [String : Double],
        activityMinutes: [String: Int],
        selectedRouteWorkoutID: String?,
        selectedTargetMetricRawValue: String,
        selectedZone: Int,
        targetValueText: String,
        routeObjectiveName: String,
        routeRepeats: Int,
        selectedRouteTemplateID: UUID?,
        selectedBuilderTabRawValue: String?,
        selectedStageActivityID: String?,
        customMicroStagesByActivityID: [String: [ProgramCustomWorkoutMicroStage]],
        customCircuitGroupsByActivityID: [String: [ProgramWorkoutCircuitGroup]],
        coachRegenerationNotesByActivityID: [String: String],
        coachAdvice: String?,
        generatedBlueprint: ProgramGeneratedBlueprint?,
        updatedAt: Date
    ) {
        self.selectedModeRawValue = selectedModeRawValue
        self.selectedPlanDepthRawValue = selectedPlanDepthRawValue
        self.selectedActivityIDs = selectedActivityIDs
        self.availableMinutes = availableMinutes
        self.allocationWeights = allocationWeights
        self.activityMinutes = activityMinutes
        self.selectedRouteWorkoutID = selectedRouteWorkoutID
        self.selectedTargetMetricRawValue = selectedTargetMetricRawValue
        self.selectedZone = selectedZone
        self.targetValueText = targetValueText
        self.routeObjectiveName = routeObjectiveName
        self.routeRepeats = routeRepeats
        self.selectedRouteTemplateID = selectedRouteTemplateID
        self.selectedBuilderTabRawValue = selectedBuilderTabRawValue
        self.selectedStageActivityID = selectedStageActivityID
        self.customMicroStagesByActivityID = customMicroStagesByActivityID
        self.customCircuitGroupsByActivityID = customCircuitGroupsByActivityID
        self.coachRegenerationNotesByActivityID = coachRegenerationNotesByActivityID
        self.coachAdvice = coachAdvice
        self.generatedBlueprint = generatedBlueprint
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedModeRawValue = try container.decode(String.self, forKey: .selectedModeRawValue)
        selectedPlanDepthRawValue = try container.decodeIfPresent(String.self, forKey: .selectedPlanDepthRawValue) ?? ProgramPlanDepth.simple.rawValue
        selectedActivityIDs = try container.decode([String].self, forKey: .selectedActivityIDs)
        availableMinutes = try container.decode(Double.self, forKey: .availableMinutes)
        allocationWeights = try container.decode([String: Double].self, forKey: .allocationWeights)
        selectedTargetMetricRawValue = try container.decode(String.self, forKey: .selectedTargetMetricRawValue)
        selectedZone = try container.decode(Int.self, forKey: .selectedZone)
        targetValueText = try container.decode(String.self, forKey: .targetValueText)
        routeObjectiveName = try container.decode(String.self, forKey: .routeObjectiveName)
        routeRepeats = try container.decode(Int.self, forKey: .routeRepeats)
        selectedRouteTemplateID = try container.decodeIfPresent(UUID.self, forKey: .selectedRouteTemplateID)
        selectedRouteWorkoutID = try container.decodeIfPresent(String.self, forKey: .selectedRouteWorkoutID)
        selectedBuilderTabRawValue = try container.decodeIfPresent(String.self, forKey: .selectedBuilderTabRawValue)
        selectedStageActivityID = try container.decodeIfPresent(String.self, forKey: .selectedStageActivityID)
        activityMinutes = try container.decodeIfPresent([String: Int].self, forKey: .activityMinutes) ?? [:]
        if let decodedStages = try container.decodeIfPresent([String: [ProgramCustomWorkoutMicroStage]].self, forKey: .customMicroStagesByActivityID) {
            customMicroStagesByActivityID = decodedStages
        } else {
            let fallbackStages = try container.decodeIfPresent([ProgramCustomWorkoutMicroStage].self, forKey: .customMicroStages) ?? []
            if let firstActivityID = selectedActivityIDs.first, !fallbackStages.isEmpty {
                customMicroStagesByActivityID = [firstActivityID: fallbackStages]
            } else {
                customMicroStagesByActivityID = [:]
            }
        }
        customCircuitGroupsByActivityID = try container.decodeIfPresent([String: [ProgramWorkoutCircuitGroup]].self, forKey: .customCircuitGroupsByActivityID) ?? [:]
        if let decodedNotes = try container.decodeIfPresent([String: String].self, forKey: .coachRegenerationNotesByActivityID) {
            coachRegenerationNotesByActivityID = decodedNotes
        } else {
            let fallbackNote = try container.decodeIfPresent(String.self, forKey: .coachRegenerationNote) ?? ""
            if let firstActivityID = selectedActivityIDs.first, !fallbackNote.isEmpty {
                coachRegenerationNotesByActivityID = [firstActivityID: fallbackNote]
            } else {
                coachRegenerationNotesByActivityID = [:]
            }
        }
        coachAdvice = try container.decodeIfPresent(String.self, forKey: .coachAdvice)
        generatedBlueprint = try container.decodeIfPresent(ProgramGeneratedBlueprint.self, forKey: .generatedBlueprint)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedModeRawValue, forKey: .selectedModeRawValue)
        try container.encode(selectedPlanDepthRawValue, forKey: .selectedPlanDepthRawValue)
        try container.encode(selectedActivityIDs, forKey: .selectedActivityIDs)
        try container.encode(availableMinutes, forKey: .availableMinutes)
        try container.encode(allocationWeights, forKey: .allocationWeights)
        try container.encode(activityMinutes, forKey: .activityMinutes)
        try container.encodeIfPresent(selectedRouteWorkoutID, forKey: .selectedRouteWorkoutID)
        try container.encode(selectedTargetMetricRawValue, forKey: .selectedTargetMetricRawValue)
        try container.encode(selectedZone, forKey: .selectedZone)
        try container.encode(targetValueText, forKey: .targetValueText)
        try container.encode(routeObjectiveName, forKey: .routeObjectiveName)
        try container.encode(routeRepeats, forKey: .routeRepeats)
        try container.encodeIfPresent(selectedRouteTemplateID, forKey: .selectedRouteTemplateID)
        try container.encodeIfPresent(selectedBuilderTabRawValue, forKey: .selectedBuilderTabRawValue)
        try container.encodeIfPresent(selectedStageActivityID, forKey: .selectedStageActivityID)
        try container.encode(customMicroStagesByActivityID, forKey: .customMicroStagesByActivityID)
        try container.encode(customCircuitGroupsByActivityID, forKey: .customCircuitGroupsByActivityID)
        try container.encode(coachRegenerationNotesByActivityID, forKey: .coachRegenerationNotesByActivityID)
        try container.encodeIfPresent(coachAdvice, forKey: .coachAdvice)
        try container.encodeIfPresent(generatedBlueprint, forKey: .generatedBlueprint)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ProgramWorkoutPlanPhase: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let activityID: String
    let activityRawValue: UInt
    let locationRawValue: Int
    let plannedMinutes: Int
    let microStages: [ProgramCustomWorkoutMicroStage]?
    let circuitGroups: [ProgramWorkoutCircuitGroup]?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        activityID: String,
        activityRawValue: UInt,
        locationRawValue: Int,
        plannedMinutes: Int,
        microStages: [ProgramCustomWorkoutMicroStage]? = nil,
        circuitGroups: [ProgramWorkoutCircuitGroup]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.activityID = activityID
        self.activityRawValue = activityRawValue
        self.locationRawValue = locationRawValue
        self.plannedMinutes = plannedMinutes
        self.microStages = microStages
        self.circuitGroups = circuitGroups
    }
}

struct ProgramWorkoutPlanRecord: Identifiable, Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case todayFocus
        case blocks
        case cautionNote
        case selectedActivityIDs
        case availableMinutes
        case modeRawValue
        case selectedPlanDepthRawValue
        case allocationWeights
        case targetMetricRawValue
        case selectedZone
        case targetValueText
        case routeObjectiveName
        case routeRepeats
        case selectedRouteTemplateID
        case primaryActivityID
        case activityRawValue
        case locationRawValue
        case routeName
        case trailhead
        case routeCoordinates
        case phases
        case createdAt
        case updatedAt
        case expiresAt
        case sourceDeviceLabel
    }

    let id: UUID
    let title: String
    let summary: String
    let todayFocus: String
    let blocks: [ProgramGeneratedBlueprint.Block]
    let cautionNote: String?
    let selectedActivityIDs: [String]
    let availableMinutes: Int
    let modeRawValue: String
    let selectedPlanDepthRawValue: String
    let allocationWeights: [String: Double]
    let targetMetricRawValue: String?
    let selectedZone: Int
    let targetValueText: String
    let routeObjectiveName: String
    let routeRepeats: Int
    let selectedRouteTemplateID: UUID?
    let primaryActivityID: String
    let activityRawValue: UInt
    let locationRawValue: Int
    let routeName: String?
    let trailhead: ProgramStoredCoordinate?
    let routeCoordinates: [ProgramStoredCoordinate]
    let phases: [ProgramWorkoutPlanPhase]?
    let createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    let sourceDeviceLabel: String

    init(
        id: UUID,
        title: String,
        summary: String,
        todayFocus: String,
        blocks: [ProgramGeneratedBlueprint.Block],
        cautionNote: String?,
        selectedActivityIDs: [String],
        availableMinutes: Int,
        modeRawValue: String,
        selectedPlanDepthRawValue: String,
        allocationWeights: [String : Double],
        targetMetricRawValue: String?,
        selectedZone: Int,
        targetValueText: String,
        routeObjectiveName: String,
        routeRepeats: Int,
        selectedRouteTemplateID: UUID?,
        primaryActivityID: String,
        activityRawValue: UInt,
        locationRawValue: Int,
        routeName: String?,
        trailhead: ProgramStoredCoordinate?,
        routeCoordinates: [ProgramStoredCoordinate],
        phases: [ProgramWorkoutPlanPhase]?,
        createdAt: Date,
        updatedAt: Date,
        expiresAt: Date?,
        sourceDeviceLabel: String
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.todayFocus = todayFocus
        self.blocks = blocks
        self.cautionNote = cautionNote
        self.selectedActivityIDs = selectedActivityIDs
        self.availableMinutes = availableMinutes
        self.modeRawValue = modeRawValue
        self.selectedPlanDepthRawValue = selectedPlanDepthRawValue
        self.allocationWeights = allocationWeights
        self.targetMetricRawValue = targetMetricRawValue
        self.selectedZone = selectedZone
        self.targetValueText = targetValueText
        self.routeObjectiveName = routeObjectiveName
        self.routeRepeats = routeRepeats
        self.selectedRouteTemplateID = selectedRouteTemplateID
        self.primaryActivityID = primaryActivityID
        self.activityRawValue = activityRawValue
        self.locationRawValue = locationRawValue
        self.routeName = routeName
        self.trailhead = trailhead
        self.routeCoordinates = routeCoordinates
        self.phases = phases
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.sourceDeviceLabel = sourceDeviceLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        todayFocus = try container.decode(String.self, forKey: .todayFocus)
        blocks = try container.decode([ProgramGeneratedBlueprint.Block].self, forKey: .blocks)
        cautionNote = try container.decodeIfPresent(String.self, forKey: .cautionNote)
        selectedActivityIDs = try container.decode([String].self, forKey: .selectedActivityIDs)
        availableMinutes = try container.decode(Int.self, forKey: .availableMinutes)
        modeRawValue = try container.decode(String.self, forKey: .modeRawValue)
        selectedPlanDepthRawValue = try container.decodeIfPresent(String.self, forKey: .selectedPlanDepthRawValue) ?? ProgramPlanDepth.simple.rawValue
        allocationWeights = try container.decode([String: Double].self, forKey: .allocationWeights)
        targetMetricRawValue = try container.decodeIfPresent(String.self, forKey: .targetMetricRawValue)
        selectedZone = try container.decode(Int.self, forKey: .selectedZone)
        targetValueText = try container.decode(String.self, forKey: .targetValueText)
        routeObjectiveName = try container.decode(String.self, forKey: .routeObjectiveName)
        routeRepeats = try container.decode(Int.self, forKey: .routeRepeats)
        selectedRouteTemplateID = try container.decodeIfPresent(UUID.self, forKey: .selectedRouteTemplateID)
        primaryActivityID = try container.decode(String.self, forKey: .primaryActivityID)
        activityRawValue = try container.decode(UInt.self, forKey: .activityRawValue)
        locationRawValue = try container.decode(Int.self, forKey: .locationRawValue)
        routeName = try container.decodeIfPresent(String.self, forKey: .routeName)
        trailhead = try container.decodeIfPresent(ProgramStoredCoordinate.self, forKey: .trailhead)
        routeCoordinates = try container.decode([ProgramStoredCoordinate].self, forKey: .routeCoordinates)
        phases = try container.decodeIfPresent([ProgramWorkoutPlanPhase].self, forKey: .phases)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        sourceDeviceLabel = try container.decode(String.self, forKey: .sourceDeviceLabel)
    }

    var blueprint: ProgramGeneratedBlueprint {
        ProgramGeneratedBlueprint(
            title: title,
            summary: summary,
            todayFocus: todayFocus,
            blocks: blocks,
            cautionNote: cautionNote
        )
    }

    var isExpired: Bool {
        if let expiresAt {
            return expiresAt <= Date()
        }
        return false
    }

    var trailheadCoordinate: CLLocationCoordinate2D? {
        trailhead?.coordinate
    }

    var routeCoordinateValues: [CLLocationCoordinate2D] {
        routeCoordinates.map(\.coordinate)
    }

    var resolvedPhases: [ProgramWorkoutPlanPhase] {
        if let phases, !phases.isEmpty {
            return phases
        }

        return [
            ProgramWorkoutPlanPhase(
                title: ProgramWorkoutType.resolve(id: primaryActivityID)?.title ?? title,
                subtitle: "\(availableMinutes) min planned",
                activityID: primaryActivityID,
                activityRawValue: activityRawValue,
                locationRawValue: locationRawValue,
                plannedMinutes: max(availableMinutes, 1),
                microStages: nil
            )
        ]
    }

    var expirationDescription: String {
        guard let expiresAt else { return "No expiration" }
        return expiresAt.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
final class ProgramWorkoutPlanStore: ObservableObject {
    static let shared = ProgramWorkoutPlanStore()

    private enum Persistence {
        static let repositoryKey = "program_builder_repository_v1"
        static let inboxKey = "program_builder_inbox_v1"
        static let draftKey = "program_builder_draft_v1"
    }

    private static func appSupportNutrivanceDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nutrivance", isDirectory: true)
    }

    private static func persistenceFileURL(forKey key: String) -> URL? {
        appSupportNutrivanceDirectory()?.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private static let ubiquitousKVSMaxSafeBytes = 950_000

    /// Large program payloads must not use UserDefaults on Mac Catalyst (~4 MiB plist limit).
    private static func readLocalPayload(forKey key: String) -> Data? {
        if let url = persistenceFileURL(forKey: key),
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            return data
        }
        return UserDefaults.standard.data(forKey: key)
    }

    private static func writeLocalPayload(_ data: Data?, forKey key: String) {
        guard let dir = appSupportNutrivanceDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let url = persistenceFileURL(forKey: key) {
            if let data, !data.isEmpty {
                try? data.write(to: url, options: [.atomic])
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func pushToUbiquitousIfEligible(_ data: Data, key: String, store: NSUbiquitousKeyValueStore) {
        if data.count <= ubiquitousKVSMaxSafeBytes {
            store.set(data, forKey: key)
        }
    }

    @Published private(set) var repositoryPlans: [ProgramWorkoutPlanRecord] = []
    @Published private(set) var inboxPlan: ProgramWorkoutPlanRecord?
    @Published private(set) var cachedDraft: ProgramBuilderDraftState?

    private var cloudObserver: NSObjectProtocol?

    var activeInboxPlan: ProgramWorkoutPlanRecord? {
        if let inboxPlan, !inboxPlan.isExpired {
            return inboxPlan
        }
        return nil
    }

    private init() {
        reloadFromPersistence()
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromPersistence()
        }
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    func saveRepositoryPlan(_ plan: ProgramWorkoutPlanRecord) {
        var updated = repositoryPlans
        if let existingIndex = updated.firstIndex(where: { $0.id == plan.id }) {
            updated[existingIndex] = plan
        } else {
            updated.insert(plan, at: 0)
        }
        repositoryPlans = updated.sorted { $0.updatedAt > $1.updatedAt }
        persistAll()
    }

    func deleteRepositoryPlan(id: UUID) {
        repositoryPlans.removeAll { $0.id == id }
        persistAll()
    }

    func sendTemporaryPlan(_ plan: ProgramWorkoutPlanRecord) {
        inboxPlan = plan
        persistAll()
    }

    func clearInboxPlan() {
        inboxPlan = nil
        persistAll()
    }

    fileprivate func saveDraft(_ draft: ProgramBuilderDraftState) {
        cachedDraft = draft
        persistAll()
    }

    private func reloadFromPersistence() {
        let cloudStore = NSUbiquitousKeyValueStore.default

        let localRepository = decodeRepository(from: Self.readLocalPayload(forKey: Persistence.repositoryKey))
        let cloudRepository = decodeRepository(from: cloudStore.data(forKey: Persistence.repositoryKey))
        repositoryPlans = mergePlans(localRepository, cloudRepository)

        let localInbox = decodeInbox(from: Self.readLocalPayload(forKey: Persistence.inboxKey))
        let cloudInbox = decodeInbox(from: cloudStore.data(forKey: Persistence.inboxKey))
        inboxPlan = preferredInbox(localInbox, cloudInbox)
        if inboxPlan?.isExpired == true {
            inboxPlan = nil
        }

        let localDraft = decodeDraft(from: Self.readLocalPayload(forKey: Persistence.draftKey))
        let cloudDraft = decodeDraft(from: cloudStore.data(forKey: Persistence.draftKey))
        cachedDraft = preferredDraft(localDraft, cloudDraft)

        persistAll()
    }

    private func persistAll() {
        let cloudStore = NSUbiquitousKeyValueStore.default

        let validRepository = repositoryPlans.filter { !$0.isExpired }
        repositoryPlans = validRepository.sorted { $0.updatedAt > $1.updatedAt }

        if let encodedRepository = try? JSONEncoder().encode(repositoryPlans) {
            Self.writeLocalPayload(encodedRepository, forKey: Persistence.repositoryKey)
            Self.pushToUbiquitousIfEligible(encodedRepository, key: Persistence.repositoryKey, store: cloudStore)
        }

        if let inboxPlan, !inboxPlan.isExpired, let encodedInbox = try? JSONEncoder().encode(inboxPlan) {
            Self.writeLocalPayload(encodedInbox, forKey: Persistence.inboxKey)
            Self.pushToUbiquitousIfEligible(encodedInbox, key: Persistence.inboxKey, store: cloudStore)
        } else {
            Self.writeLocalPayload(nil, forKey: Persistence.inboxKey)
            cloudStore.removeObject(forKey: Persistence.inboxKey)
        }

        if let cachedDraft, let encodedDraft = try? JSONEncoder().encode(cachedDraft) {
            Self.writeLocalPayload(encodedDraft, forKey: Persistence.draftKey)
            Self.pushToUbiquitousIfEligible(encodedDraft, key: Persistence.draftKey, store: cloudStore)
        } else {
            Self.writeLocalPayload(nil, forKey: Persistence.draftKey)
            cloudStore.removeObject(forKey: Persistence.draftKey)
        }
    }

    private func decodeRepository(from data: Data?) -> [ProgramWorkoutPlanRecord] {
        guard let data,
              let decoded = try? JSONDecoder().decode([ProgramWorkoutPlanRecord].self, from: data) else {
            return []
        }
        return decoded.filter { !$0.isExpired }
    }

    private func decodeInbox(from data: Data?) -> ProgramWorkoutPlanRecord? {
        guard let data,
              let decoded = try? JSONDecoder().decode(ProgramWorkoutPlanRecord.self, from: data),
              !decoded.isExpired else {
            return nil
        }
        return decoded
    }

    private func decodeDraft(from data: Data?) -> ProgramBuilderDraftState? {
        guard let data,
              let decoded = try? JSONDecoder().decode(ProgramBuilderDraftState.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func mergePlans(_ lhs: [ProgramWorkoutPlanRecord], _ rhs: [ProgramWorkoutPlanRecord]) -> [ProgramWorkoutPlanRecord] {
        var merged: [UUID: ProgramWorkoutPlanRecord] = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
        for plan in rhs {
            if let existing = merged[plan.id] {
                merged[plan.id] = existing.updatedAt >= plan.updatedAt ? existing : plan
            } else {
                merged[plan.id] = plan
            }
        }
        return merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func preferredInbox(_ lhs: ProgramWorkoutPlanRecord?, _ rhs: ProgramWorkoutPlanRecord?) -> ProgramWorkoutPlanRecord? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left.updatedAt >= right.updatedAt ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return nil
        }
    }

    private func preferredDraft(_ lhs: ProgramBuilderDraftState?, _ rhs: ProgramBuilderDraftState?) -> ProgramBuilderDraftState? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left.updatedAt >= right.updatedAt ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return nil
        }
    }
}

private struct ProgramRecentWorkout: Identifiable {
    let id = UUID()
    let date: Date
    let activity: String
    let durationMinutes: Double
    let calories: Double
    let intensity: String
    let highlight: String?
}

private struct ProgramStageRegenerationResult {
    let stages: [ProgramCustomWorkoutMicroStage]
    let circuitGroups: [ProgramWorkoutCircuitGroup]
    let statusText: String?
}

@MainActor
private final class ProgramBuilderAIPlanner: ObservableObject {
    @Published var coachAdvice = "Preparing your next-session coach..."
    @Published var generatedBlueprint: ProgramGeneratedBlueprint?
    @Published var isGeneratingCoach = false
    @Published var isGeneratingPlan = false
    @Published var isRegeneratingMicroStages = false
    @Published var coachErrorText: String?
    @Published var planErrorText: String?
    @Published var microStageRegenerationErrorText: String?
    @Published var microStageRegenerationActivityID: String?

    func refreshCoachAdvice(for request: ProgramPlannerRequest, engine: HealthStateEngine) async {
        isGeneratingCoach = true
        coachErrorText = nil

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            if model.isAvailable {
                do {
                    let session = LanguageModelSession(model: model, instructions: programBuilderCoachInstructions)
                    let response = try await session.respond(to: coachPrompt(for: request))
                    let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    coachAdvice = cleaned.isEmpty ? fallbackCoachAdvice(for: request, engine: engine) : cleaned
                    isGeneratingCoach = false
                    return
                } catch {
                    coachErrorText = "AI coach fell back to local advice for now."
                }
            }
        }
        #endif

        coachAdvice = fallbackCoachAdvice(for: request, engine: engine)
        isGeneratingCoach = false
    }

    func generateBlueprint(for request: ProgramPlannerRequest, engine: HealthStateEngine) async {
        isGeneratingPlan = true
        planErrorText = nil
        generatedBlueprint = nil

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            if model.isAvailable {
                do {
                    let session = LanguageModelSession(model: model, instructions: programBuilderGenerationInstructions)
                    let response = try await session.respond(
                        to: blueprintPrompt(for: request),
                        generating: ProgramGeneratedBlueprint.self
                    )
                    generatedBlueprint = response.content
                    isGeneratingPlan = false
                    return
                } catch {
                    planErrorText = "Guided generation could not finish, so a local outline was created instead."
                }
            } else {
                planErrorText = "Apple Intelligence is unavailable on this device, so a local outline was created instead."
            }
        }
        #endif

        generatedBlueprint = fallbackBlueprint(for: request, engine: engine)
        isGeneratingPlan = false
    }

    func regenerateMicroStages(
        for activity: ProgramWorkoutType,
        request: ProgramPlannerRequest,
        existingStages: [ProgramCustomWorkoutMicroStage],
        existingCircuitGroups: [ProgramWorkoutCircuitGroup],
        note: String
    ) async -> ProgramStageRegenerationResult {
        let totalMinutes = totalStageMinutes(existingStages)
        let fallbackStages = fallbackRegeneratedMicroStages(
            for: activity,
            request: request,
            existingStages: existingStages,
            note: note,
            totalMinutes: totalMinutes
        )
        let fallbackGroups = inferredCircuitGroups(from: fallbackStages, existing: existingCircuitGroups)

        guard !note.isEmpty else {
            microStageRegenerationErrorText = nil
            return ProgramStageRegenerationResult(stages: fallbackStages, circuitGroups: fallbackGroups, statusText: nil)
        }

        isRegeneratingMicroStages = true
        microStageRegenerationActivityID = activity.id
        microStageRegenerationErrorText = nil
        defer {
            isRegeneratingMicroStages = false
            microStageRegenerationActivityID = nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            if model.isAvailable {
                do {
                    let session = LanguageModelSession(model: model, instructions: programBuilderMicroStageInstructions)
                    let response = try await session.respond(
                        to: microStagePrompt(
                            for: activity,
                            request: request,
                            existingStages: existingStages,
                            note: note,
                            totalMinutes: totalMinutes
                        ),
                        generating: ProgramGeneratedMicroStagePlan.self
                    )
                    let cleaned = sanitizedGeneratedMicroStages(
                        response.content.stages,
                        for: activity,
                        request: request,
                        fallbackStages: fallbackStages,
                        totalMinutes: totalMinutes
                    )
                    if !cleaned.isEmpty {
                        let groups = inferredCircuitGroups(from: cleaned, existing: existingCircuitGroups)
                        return ProgramStageRegenerationResult(
                            stages: cleaned,
                            circuitGroups: groups,
                            statusText: groups.isEmpty ? "Coach rebuilt the stage structure from your note." : "Coach rebuilt the stage structure and grouped the coupled repeats."
                        )
                    }
                } catch {
                    microStageRegenerationErrorText = "Coach fell back to the local stage rebuilder for now."
                }
            }
        }
        #endif

        return ProgramStageRegenerationResult(
            stages: fallbackStages,
            circuitGroups: fallbackGroups,
            statusText: fallbackGroups.isEmpty ? "Coach rebuilt the stage structure from your note." : "Coach rebuilt the stage structure and grouped the coupled repeats."
        )
    }

    private func fallbackCoachAdvice(for request: ProgramPlannerRequest, engine: HealthStateEngine) -> String {
        let activities = request.selectedActivities.map(\.title).joined(separator: ", ")
        let readiness = Int(request.readinessScore.rounded())
        let recovery = Int(request.recoveryScore.rounded())
        let strain = Int(request.strainScore.rounded())
        let depthLead = request.planDepth == .comprehensive
            ? "Build something layered inside the workout if it earns its place, not just because it sounds smart. "
            : "Keep it clean and direct. "

        if request.selectedActivities.isEmpty {
            return "Today looks like a good day to choose the type of session first, then set the constraint that matters most. Start by deciding whether you want skill, controlled aerobic work, or something short and punchy."
        }

        if recovery >= 75 && readiness >= 75 {
            return "\(depthLead)You look fairly ready today. Keep the \(activities) session purposeful and contained inside the \(request.availableMinutes)-minute window you set. If you want quality, anchor it around one clear objective instead of stacking too many demands. Strain is at \(strain), so you have room to do something meaningful without forcing extra pieces that you did not ask for."
        }

        if recovery < 55 || readiness < 55 {
            return "\(depthLead)Today reads more like a control day than a reach day. Keep \(activities) honest, smooth, and sustainable inside the \(request.availableMinutes)-minute window. Focus on rhythm, technique, and leaving yourself better than you started. With recovery at \(recovery) and readiness at \(readiness), the best move today is usually a smarter structure or a longer cooldown, not abandoning quality altogether."
        }

        return "\(depthLead)You are in a workable middle zone today. Let the \(activities) session be specific, but keep the overall ask clean. Use the time you set, stay close to the main intent, and avoid layering extras unless you explicitly want them. Recovery \(recovery), readiness \(readiness), and strain \(strain) suggest a solid day for focused work without needing to overcomplicate it."
    }

    private func fallbackBlueprint(for request: ProgramPlannerRequest, engine: HealthStateEngine) -> ProgramGeneratedBlueprint {
        let title = request.selectedActivities.isEmpty ? "Today Session" : request.selectedActivities.map(\.title).joined(separator: " + ")
        let blocks = request.selectedActivities.map { activity in
            ProgramGeneratedBlueprint.Block(
                title: activity.title,
                minutes: max(5, allocationMinutes(for: activity.title, request: request)),
                focus: request.target != nil
                    ? "Stay centered on \(request.target!.metric.title.lowercased()) and keep the session consistent."
                    : "Keep this block true to the activity you selected without adding extra structure you did not ask for.",
                cue: cueText(for: request, activity: activity)
            )
        }

        return ProgramGeneratedBlueprint(
            title: title,
            summary: "A clean \(request.availableMinutes)-minute outline built from your selected activities and today’s chosen planning route.",
            todayFocus: todayFocusText(for: request),
            blocks: blocks.isEmpty ? [
                .init(title: "Choose an activity", minutes: request.availableMinutes, focus: "Pick the sport first so the planner has something specific to build around.", cue: "Search the catalog or tap a suggestion chip.")
            ] : blocks,
            cautionNote: "The planner stayed inside your explicit picks and did not automatically add cooldown, mobility, or extra sports."
        )
    }

    private func allocationMinutes(for title: String, request: ProgramPlannerRequest) -> Int {
        if let allocation = request.allocations[title] {
            return Int(allocation.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? max(5, request.availableMinutes / max(request.selectedActivities.count, 1))
        }
        return max(5, request.availableMinutes / max(request.selectedActivities.count, 1))
    }

    private func cueText(for request: ProgramPlannerRequest, activity: ProgramWorkoutType) -> String {
        switch request.mode {
        case .guided:
            return "Keep this block aligned with your chosen taste and today’s time budget."
        case .route:
            if let route = request.route, !route.name.isEmpty {
                return "Let \(route.name) shape the effort and finish the route the way you planned it."
            }
            return "Let the chosen route or loop drive the session instead of chasing unrelated metrics."
        }
    }

    private func todayFocusText(for request: ProgramPlannerRequest) -> String {
        switch request.mode {
        case .guided:
            return "Today focus: match the session to what you actually want to do, not what the planner assumes."
        case .route:
            if let route = request.route, !route.name.isEmpty {
                return "Today focus: complete \(route.name) \(route.repeats)x with the route driving the session."
            }
            return "Today focus: route completion."
        }
    }

    private func coachPrompt(for request: ProgramPlannerRequest) -> String {
        let selectedActivities = request.selectedActivities.map(\.title).joined(separator: ", ")
        let recent = request.recentWorkouts.prefix(5).map(describeProgramWorkout).joined(separator: " ")
        let microStageSummary = request.microStagesByActivity
            .sorted { $0.key < $1.key }
            .map { key, stages in
                "\(key): " + stages.map(\.displaySummary).joined(separator: " | ")
            }
            .joined(separator: " || ")
        return """
        Today context:
        - Selected activities: \(selectedActivities.isEmpty ? "none selected yet" : selectedActivities)
        - Available time: \(request.availableMinutes) minutes
        - Planning mode: \(request.mode.title)
        - Plan depth: \(request.planDepth.title)
        - Recovery score: \(Int(request.recoveryScore.rounded())) / 100
        - Readiness score: \(Int(request.readinessScore.rounded())) / 100
        - Strain score: \(Int(request.strainScore.rounded())) / 21
        - Recent workouts: \(recent.isEmpty ? "none loaded" : recent)
        - Target preference: \(request.target?.metric.title ?? "none"), \(request.target?.descriptor ?? "none")
        - Route preference: \(request.route?.name ?? "none"), repeats \(request.route?.repeats ?? 0)
        - Current micro-stage draft: \(microStageSummary.isEmpty ? "none" : microStageSummary)
        - Regeneration note: \(request.normalizedRegenerationNote.isEmpty ? "none" : request.normalizedRegenerationNote)

        Give general advice for the next session, with the emphasis on what the user can realistically do today.
        Never prescribe a specific workout, interval recipe, or named session.
        If plan depth is comprehensive, you may support more structure inside one workout type, but stay performance-forward instead of defaulting to recovery rhetoric.
        Keep it plain text, direct, supportive, and under 170 words.
        """
    }

    private func blueprintPrompt(for request: ProgramPlannerRequest) -> String {
        let selectedActivities = request.selectedActivities.map(\.title).joined(separator: ", ")
        let allocations = request.allocations.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
        let targetLine = request.target.map { "\($0.metric.title): \($0.descriptor.isEmpty ? "general focus" : $0.descriptor)" } ?? "none"
        let routeLine = request.route.map { "\($0.name.isEmpty ? "unnamed route" : $0.name), repeats \($0.repeats), template \($0.templateName ?? "none")" } ?? "none"
        let microStageSummary = request.microStagesByActivity
            .sorted { $0.key < $1.key }
            .map { key, stages in
                "\(key): " + stages.map(\.displaySummary).joined(separator: " | ")
            }
            .joined(separator: " || ")

        return """
        Build a structured workout blueprint from these exact user constraints:
        - Activities selected: \(selectedActivities)
        - Available minutes: \(request.availableMinutes)
        - Planning mode: \(request.mode.title)
        - Plan depth: \(request.planDepth.title)
        - Activity allocations: \(allocations)
        - Target preference: \(targetLine)
        - Route preference: \(routeLine)
        - Existing micro-stage structure: \(microStageSummary.isEmpty ? "none" : microStageSummary)
        - Regeneration note: \(request.normalizedRegenerationNote.isEmpty ? "none" : request.normalizedRegenerationNote)

        Hard constraints:
        - Do not invent cooldown, warmup, mobility, stretching, or extra sports unless the user explicitly selected them.
        - Do not act clever or add a block "because it would be smart."
        - Keep the blueprint faithful to the selected activities and the time budget.
        - If plan depth is comprehensive, it is allowed to describe internal structure inside each selected workout type.
        - Use recovery, readiness, strain, and recent workouts to shape the structure, but do not turn the entire plan into generic conservative recovery language.
        - Make the block titles concise and useful.
        - Keep the focus and cue practical.
        - The summary should reflect today, not a generic training plan.
        """
    }

    private func microStagePrompt(
        for activity: ProgramWorkoutType,
        request: ProgramPlannerRequest,
        existingStages: [ProgramCustomWorkoutMicroStage],
        note: String,
        totalMinutes: Int
    ) -> String {
        let currentStages = existingStages.map(\.displaySummary).joined(separator: " | ")
        let recent = request.recentWorkouts.prefix(4).map(describeProgramWorkout).joined(separator: " ")
        let supportedGoals = Array(Set(ProgramMicroStageRole.allCases.flatMap { activity.supportedMicroStageGoals(for: $0) }))
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")

        return """
        Rebuild the workout stages for this activity using the user's note.

        Activity: \(activity.title)
        Supported goals: \(supportedGoals)
        Planning mode: \(request.mode.title)
        Available minutes for this activity: \(totalMinutes)
        Recovery score: \(Int(request.recoveryScore.rounded())) / 100
        Readiness score: \(Int(request.readinessScore.rounded())) / 100
        Strain score: \(Int(request.strainScore.rounded())) / 21
        User note: \(note)
        Current stages: \(currentStages)
        Target preference: \(request.target?.metric.title ?? "none") \(request.target?.descriptor ?? "")
        Route preference: \(request.route?.name ?? "none"), repeats \(request.route?.repeats ?? 0)
        Recent workouts: \(recent.isEmpty ? "none loaded" : recent)

        Return a materially updated stage structure that responds directly to the user's note.

        Hard constraints:
        - Keep the total session close to \(totalMinutes) minutes.
        - Keep the workout inside the selected activity. Do not invent a second sport.
        - Use only these roles: warmup, goal, steady, work, recovery, cooldown.
        - Use only supported goals.
        - Do not add warmup or cooldown unless the note explicitly asks for them.
        - warmup can only use time or distance.
        - goal can only use time, distance, or energy.
        - steady means maintain a range.
        - work means hold at or above a target.
        - recovery means stay below a target or keep it easy.
        - If two or more stages alternate as a repeat set, give them the same non-empty repeatSetLabel and the same repeat count.
        - A stage should have a clear title, role, goal, planned minutes, repeats, and short coaching notes.
        - If the note asks for more recovery, add space or easier control instead of only renaming stages.
        - If the note asks for more intensity, shift the work stages, targets, or repeat design accordingly.
        - If the note asks for longer warmup or cooldown, actually change the time distribution.
        - Prefer 3 to 7 stages unless the note clearly calls for simpler structure.
        """
    }

    private func fallbackRegeneratedMicroStages(
        for activity: ProgramWorkoutType,
        request: ProgramPlannerRequest,
        existingStages: [ProgramCustomWorkoutMicroStage],
        note: String,
        totalMinutes: Int
    ) -> [ProgramCustomWorkoutMicroStage] {
        var stages: [ProgramCustomWorkoutMicroStage] = existingStages.isEmpty
            ? []
            : existingStages.map { stage in
                var updated = stage
                updated.title = stage.title.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.notes = stage.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.plannedMinutes = max(stage.plannedMinutes, 1)
                updated.repeats = min(max(stage.repeats, 1), 12)
                return updated
            }

        if stages.isEmpty {
            stages = [
                ProgramCustomWorkoutMicroStage(
                    title: activity.title,
                    notes: "",
                    role: .goal,
                    goal: fallbackGoal(for: request, activity: activity),
                    plannedMinutes: max(totalMinutes, 5),
                    repeats: 1,
                    targetValueText: normalizedTargetDescriptor(from: request, fallback: ""),
                    repeatSetLabel: "",
                    targetBehavior: .completionGoal
                )
            ]
        }

        let normalized = note.lowercased()
        guard !normalized.isEmpty else {
            return scaledStages(stages.map { normalizeStage($0, for: activity) }, targetTotalMinutes: totalMinutes)
        }

        if !normalized.contains("warm") {
            stages.removeAll { $0.role == .warmup }
        }
        if !normalized.contains("cool") {
            stages.removeAll { $0.role == .cooldown }
        }
        if stages.isEmpty {
            stages = [
                ProgramCustomWorkoutMicroStage(
                    title: "Main Goal",
                    notes: "",
                    role: .goal,
                    goal: fallbackGoal(for: request, activity: activity),
                    plannedMinutes: max(totalMinutes, 5),
                    repeats: 1,
                    targetValueText: normalizedTargetDescriptor(from: request, fallback: ""),
                    repeatSetLabel: "",
                    targetBehavior: .completionGoal
                )
            ]
        }

        if let coupledStages = coupledCircuitStages(from: normalized, activity: activity, request: request) {
            return scaledStages(coupledStages.map { normalizeStage($0, for: activity) }, targetTotalMinutes: totalMinutes)
        }

        if normalized.contains("simpl") || normalized.contains("cleaner") || normalized.contains("less clutter") {
            stages = collapseStages(stages)
        }

        if normalized.contains("more recovery") || normalized.contains("easier") || normalized.contains("smoother") {
            stages = addRecoverySupport(to: stages)
        }

        if normalized.contains("longer warmup") || normalized.contains("more warmup") {
            stages = shiftMinutes(in: stages, matching: .warmup, delta: 4)
        }

        if normalized.contains("shorter warmup") {
            stages = shiftMinutes(in: stages, matching: .warmup, delta: -3)
        }

        if normalized.contains("longer cooldown") || normalized.contains("extend cooldown") {
            stages = shiftMinutes(in: stages, matching: .cooldown, delta: 5)
        }

        if normalized.contains("shorter cooldown") {
            stages = shiftMinutes(in: stages, matching: .cooldown, delta: -4)
        }

        if normalized.contains("power") {
            stages = applyGoal(.power, label: normalizedTargetDescriptor(from: request, fallback: "220-260 W"), to: stages)
        } else if normalized.contains("pace") {
            stages = applyGoal(.pace, label: normalizedTargetDescriptor(from: request, fallback: "steady pace band"), to: stages)
        } else if normalized.contains("speed") || normalized.contains("mph") || normalized.contains("km/h") || normalized.contains("kph") {
            stages = applyGoal(.speed, label: normalizedTargetDescriptor(from: request, fallback: "18-20 mph"), to: stages)
        } else if normalized.contains("cadence") {
            stages = applyGoal(.cadence, label: normalizedTargetDescriptor(from: request, fallback: "high cadence"), to: stages)
        } else if normalized.contains("zone") || normalized.contains("heart rate") {
            stages = applyGoal(.heartRateZone, label: normalizedTargetDescriptor(from: request, fallback: "Zone 2"), to: stages)
        }

        if normalized.contains("more intensity") || normalized.contains("harder") || normalized.contains("sharper") {
            stages = sharpenWorkStages(stages)
        }

        if normalized.contains("less intensity") || normalized.contains("softer") || normalized.contains("controlled") {
            stages = softenWorkStages(stages)
        }

        if normalized.contains("fewer repeats") {
            stages = adjustRepeats(stages, delta: -1)
        } else if normalized.contains("more repeats") {
            stages = adjustRepeats(stages, delta: 1)
        } else if let requestedRepeats = note.firstPositiveInteger {
            stages = setRepeats(stages, repeats: requestedRepeats)
        }

        return scaledStages(stages.map { normalizeStage($0, for: activity) }, targetTotalMinutes: totalMinutes)
    }

    private func sanitizedGeneratedMicroStages(
        _ generatedStages: [ProgramGeneratedMicroStage],
        for activity: ProgramWorkoutType,
        request: ProgramPlannerRequest,
        fallbackStages: [ProgramCustomWorkoutMicroStage],
        totalMinutes: Int
    ) -> [ProgramCustomWorkoutMicroStage] {
        let supportedGoals = Set(ProgramMicroStageRole.allCases.flatMap { role in
            activity.supportedMicroStageGoals(for: role).map(\.rawValue)
        })
        let cleaned = generatedStages.compactMap { stage -> ProgramCustomWorkoutMicroStage? in
            let role = ProgramMicroStageRole(storageValue: stage.roleRawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .work
            let goalRawValue = stage.goalRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedGoal = ProgramMicroStageGoal(rawValue: goalRawValue)
            let goal: ProgramMicroStageGoal
            if let parsedGoal, supportedGoals.contains(parsedGoal.rawValue) || parsedGoal == .open || parsedGoal == .time {
                goal = parsedGoal
            } else {
                goal = fallbackGoal(for: request, activity: activity)
            }

            let title = stage.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            var targetValueText = stage.targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
            if goal.requiresDescriptorInput && targetValueText.isEmpty {
                targetValueText = defaultTargetText(for: goal, request: request)
            }

            return ProgramCustomWorkoutMicroStage(
                title: title,
                notes: stage.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Coach-adjusted stage." : stage.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role,
                goal: goal,
                plannedMinutes: min(max(stage.plannedMinutes, 1), 180),
                repeats: min(max(stage.repeats, 1), 12),
                targetValueText: targetValueText,
                repeatSetLabel: stage.repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                targetBehavior: role.defaultTargetBehavior
            )
        }

        guard !cleaned.isEmpty else { return fallbackStages }
        let hydrated = hydratedCircuitStages(cleaned)
        return scaledStages(hydrated.map { normalizeStage($0, for: activity) }, targetTotalMinutes: totalMinutes)
    }

    private func totalStageMinutes(_ stages: [ProgramCustomWorkoutMicroStage]) -> Int {
        max(stages.reduce(0) { $0 + max($1.plannedMinutes, 1) * max($1.repeats, 1) }, 1)
    }

    private func scaledStages(_ stages: [ProgramCustomWorkoutMicroStage], targetTotalMinutes: Int) -> [ProgramCustomWorkoutMicroStage] {
        guard !stages.isEmpty else { return stages }
        let safeTarget = max(targetTotalMinutes, 5)
        let currentTotal = totalStageMinutes(stages)
        guard currentTotal != safeTarget else { return stages }

        let scale = Double(safeTarget) / Double(max(currentTotal, 1))
        var updated = stages.map { stage -> ProgramCustomWorkoutMicroStage in
            var stage = stage
            stage.plannedMinutes = min(max(Int((Double(max(stage.plannedMinutes, 1)) * scale).rounded()), 1), 180)
            return stage
        }

        var difference = safeTarget - totalStageMinutes(updated)
        var index = 0
        while difference != 0 && !updated.isEmpty {
            let adjustedIndex = index % updated.count
            if difference > 0 {
                updated[adjustedIndex].plannedMinutes += 1
                difference -= max(updated[adjustedIndex].repeats, 1)
            } else if updated[adjustedIndex].plannedMinutes > 1 {
                updated[adjustedIndex].plannedMinutes -= 1
                difference += max(updated[adjustedIndex].repeats, 1)
            }
            index += 1
            if index > 500 { break }
        }

        return updated
    }

    private func inferredCircuitGroups(
        from stages: [ProgramCustomWorkoutMicroStage],
        existing: [ProgramWorkoutCircuitGroup]
    ) -> [ProgramWorkoutCircuitGroup] {
        let inferred = Dictionary(grouping: hydratedCircuitStages(stages, existingGroups: existing).compactMap { stage -> (UUID, String, Int)? in
            guard let groupID = stage.circuitGroupID else { return nil }
            return (groupID, stage.repeatSetLabel.isEmpty ? "Coupled Circuit" : stage.repeatSetLabel, max(stage.repeats, 1))
        }, by: { $0.0 }).values.compactMap { entries -> ProgramWorkoutCircuitGroup? in
            guard let first = entries.first else { return nil }
            if let existingGroup = existing.first(where: { $0.id == first.0 }) {
                return ProgramWorkoutCircuitGroup(id: existingGroup.id, title: existingGroup.title, repeats: first.2)
            }
            return ProgramWorkoutCircuitGroup(id: first.0, title: first.1, repeats: first.2)
        }
        return inferred.sorted { $0.title < $1.title }
    }

    private func hydratedCircuitStages(
        _ stages: [ProgramCustomWorkoutMicroStage],
        existingGroups: [ProgramWorkoutCircuitGroup] = []
    ) -> [ProgramCustomWorkoutMicroStage] {
        guard !stages.isEmpty else { return stages }

        var updated = stages
        let groupsByID = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.id, $0) })
        let groupsByTitle = Dictionary(uniqueKeysWithValues: existingGroups.map {
            ($0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
        })

        for index in updated.indices {
            if let groupID = updated[index].circuitGroupID,
               let existing = groupsByID[groupID] {
                updated[index].repeatSetLabel = existing.title
                updated[index].repeats = max(updated[index].repeats, existing.repeats)
            }
        }

        let groupedByLabel = Dictionary(grouping: updated.indices.filter {
            updated[$0].circuitGroupID == nil &&
            !updated[$0].repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, by: {
            updated[$0].repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        for (normalizedLabel, indices) in groupedByLabel where indices.count >= 2 {
            guard let firstIndex = indices.first else { continue }
            let rawLabel = updated[firstIndex].repeatSetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = groupsByTitle[normalizedLabel] ?? ProgramWorkoutCircuitGroup(
                title: rawLabel.isEmpty ? "Coupled Circuit" : rawLabel,
                repeats: indices.map { max(updated[$0].repeats, 1) }.max() ?? 1
            )
            for index in indices {
                updated[index].circuitGroupID = group.id
                updated[index].repeatSetLabel = group.title
                updated[index].repeats = max(updated[index].repeats, group.repeats)
            }
        }

        return updated
    }

    private func coupledCircuitStages(
        from normalizedNote: String,
        activity: ProgramWorkoutType,
        request: ProgramPlannerRequest
    ) -> [ProgramCustomWorkoutMicroStage]? {
        guard normalizedNote.contains("coupled") || normalizedNote.contains("paired with") || normalizedNote.contains("alternating with") else {
            return nil
        }

        let repeats = min(max(normalizedNote.firstPositiveInteger ?? 4, 1), 12)
        let group = ProgramWorkoutCircuitGroup(title: "Coupled Circuit", repeats: repeats)
        let steadyGoal: ProgramMicroStageGoal
        if normalizedNote.contains("cadence") {
            steadyGoal = .cadence
        } else if normalizedNote.contains("power") {
            steadyGoal = .power
        } else if normalizedNote.contains("pace") {
            steadyGoal = .pace
        } else if normalizedNote.contains("speed") || normalizedNote.contains("mph") || normalizedNote.contains("kph") || normalizedNote.contains("km/h") {
            steadyGoal = .speed
        } else {
            steadyGoal = preferredSteadyOrWorkGoal(for: activity)
        }

        let workMinutes = durationMinutes(in: normalizedNote, fallback: 5)
        let recoveryMinutes = secondDurationMinutes(in: normalizedNote, fallback: 1)
        let descriptor = descriptorText(in: normalizedNote, for: steadyGoal, fallback: defaultDescriptor(for: steadyGoal))

        return [
            ProgramCustomWorkoutMicroStage(
                title: "Circuit Stage",
                notes: "Maintain the assigned target for each repeat.",
                role: normalizedNote.contains("above") || normalizedNote.contains("over") ? .work : .steady,
                goal: steadyGoal,
                plannedMinutes: workMinutes,
                repeats: repeats,
                targetValueText: descriptor,
                repeatSetLabel: group.title,
                targetBehavior: (normalizedNote.contains("above") || normalizedNote.contains("over")) ? .aboveThreshold : .range,
                circuitGroupID: group.id
            ),
            ProgramCustomWorkoutMicroStage(
                title: "Circuit Recovery",
                notes: "Tone it down and reset before the next repeat.",
                role: .recovery,
                goal: allowedRecoveryGoal(in: normalizedNote, activity: activity),
                plannedMinutes: recoveryMinutes,
                repeats: repeats,
                targetValueText: normalizedNote.contains("zone") ? "Zone 2" : "",
                repeatSetLabel: group.title,
                targetBehavior: .belowThreshold,
                circuitGroupID: group.id
            )
        ]
    }

    private func durationMinutes(in text: String, fallback: Int) -> Int {
        let matches = text.captureGroups(for: #"(\d+)\s*(minute|min)"#)
        if let first = matches.first, let value = Int(first[0]) {
            return value
        }
        return fallback
    }

    private func secondDurationMinutes(in text: String, fallback: Int) -> Int {
        let matches = text.captureGroups(for: #"(\d+)\s*(minute|min)"#)
        if matches.count > 1, let value = Int(matches[1][0]) {
            return value
        }
        return fallback
    }

    private func descriptorText(in text: String, for goal: ProgramMicroStageGoal, fallback: String) -> String {
        switch goal {
        case .heartRateZone:
            if let zone = text.captureGroups(for: #"zone\s*(\d+)"#).first?.first {
                return "Zone \(zone)"
            }
        case .power:
            if let range = text.captureGroups(for: #"(\d+\s*-\s*\d+)\s*w"#).first?.first {
                return "\(range) W"
            }
            if let threshold = text.captureGroups(for: #"(?:above|over|under)\s*(\d+)\s*w"#).first?.first {
                return "\(threshold) W"
            }
        case .cadence:
            if let range = text.captureGroups(for: #"(\d+\s*-\s*\d+)\s*rpm"#).first?.first {
                return "\(range) rpm"
            }
        case .pace:
            if let pace = text.captureGroups(for: #"(\d+:\d+\s*/\s*(?:mi|km))"#).first?.first {
                return pace
            }
        case .speed:
            if let range = text.captureGroups(for: #"(\d+\s*-\s*\d+)\s*(mph|kph|km/h)"#).first {
                return "\(range[0]) \(range[1])"
            }
        default:
            break
        }
        return fallback
    }

    private func allowedRecoveryGoal(in text: String, activity: ProgramWorkoutType) -> ProgramMicroStageGoal {
        if text.contains("power"), activity.supportedMicroStageGoals(for: .recovery).contains(.power) {
            return .power
        }
        if text.contains("cadence"), activity.supportedMicroStageGoals(for: .recovery).contains(.cadence) {
            return .cadence
        }
        if (text.contains("speed") || text.contains("mph") || text.contains("kph") || text.contains("km/h")),
           activity.supportedMicroStageGoals(for: .recovery).contains(.speed) {
            return .speed
        }
        if text.contains("pace"), activity.supportedMicroStageGoals(for: .recovery).contains(.pace) {
            return .pace
        }
        if text.contains("distance"), activity.supportedMicroStageGoals(for: .recovery).contains(.distance) {
            return .distance
        }
        return .time
    }

    private func collapseStages(_ stages: [ProgramCustomWorkoutMicroStage]) -> [ProgramCustomWorkoutMicroStage] {
        guard stages.count > 3 else { return stages }
        let workStages = stages.filter { $0.role == .work || $0.role == .steady }
        var rebuilt: [ProgramCustomWorkoutMicroStage] = []
        if let warmup = stages.first(where: { $0.role == .warmup }) {
            rebuilt.append(warmup)
        }
        if let primaryWork = workStages.first {
            var stage = primaryWork
            stage.title = "Main Set"
            rebuilt.append(stage)
        }
        if let cooldown = stages.last(where: { $0.role == .cooldown }) {
            rebuilt.append(cooldown)
        }
        return rebuilt.isEmpty ? stages : rebuilt
    }

    private func addRecoverySupport(to stages: [ProgramCustomWorkoutMicroStage]) -> [ProgramCustomWorkoutMicroStage] {
        var updated = stages
        if let recoveryIndex = updated.firstIndex(where: { $0.role == .recovery }) {
            updated[recoveryIndex].plannedMinutes += 2
            updated[recoveryIndex].notes = "Bring breathing down before the next push."
        } else if let workIndex = updated.firstIndex(where: { $0.role == .work }) {
            let recovery = ProgramCustomWorkoutMicroStage(
                title: "Reset",
                notes: "Bring breathing down before the next push.",
                role: .recovery,
                goal: .heartRateZone,
                plannedMinutes: 3,
                repeats: updated[workIndex].repeats,
                targetValueText: "Zone 2",
                repeatSetLabel: updated[workIndex].repeatSetLabel,
                targetBehavior: .belowThreshold,
                circuitGroupID: updated[workIndex].circuitGroupID
            )
            updated.insert(recovery, at: min(workIndex + 1, updated.count))
        }
        return updated
    }

    private func shiftMinutes(
        in stages: [ProgramCustomWorkoutMicroStage],
        matching role: ProgramMicroStageRole,
        delta: Int
    ) -> [ProgramCustomWorkoutMicroStage] {
        var updated = stages
        guard let index = updated.firstIndex(where: { $0.role == role }) else { return updated }
        updated[index].plannedMinutes = max(updated[index].plannedMinutes + delta, 1)
        return updated
    }

    private func applyGoal(
        _ goal: ProgramMicroStageGoal,
        label: String,
        to stages: [ProgramCustomWorkoutMicroStage]
    ) -> [ProgramCustomWorkoutMicroStage] {
        stages.map { stage in
            var updated = stage
            if updated.role == .work || updated.role == .steady {
                updated.goal = goal
                updated.targetBehavior = updated.role == .steady ? .range : .aboveThreshold
                if !label.isEmpty {
                    updated.targetValueText = label
                }
            }
            return updated
        }
    }

    private func sharpenWorkStages(_ stages: [ProgramCustomWorkoutMicroStage]) -> [ProgramCustomWorkoutMicroStage] {
        stages.map { stage in
            var updated = stage
            if updated.role == .work {
                updated.plannedMinutes = max(updated.plannedMinutes + 1, 1)
                updated.notes = "Coach pushed this stage to be more decisive and specific."
            }
            return updated
        }
    }

    private func softenWorkStages(_ stages: [ProgramCustomWorkoutMicroStage]) -> [ProgramCustomWorkoutMicroStage] {
        stages.map { stage in
            var updated = stage
            if updated.role == .work {
                updated.plannedMinutes = max(updated.plannedMinutes - 1, 1)
                updated.notes = "Coach softened this stage to keep the session more controlled."
            }
            return updated
        }
    }

    private func adjustRepeats(_ stages: [ProgramCustomWorkoutMicroStage], delta: Int) -> [ProgramCustomWorkoutMicroStage] {
        stages.map { stage in
            var updated = stage
            if updated.role == .work || updated.role == .recovery {
                updated.repeats = min(max(updated.repeats + delta, 1), 12)
            }
            return updated
        }
    }

    private func setRepeats(_ stages: [ProgramCustomWorkoutMicroStage], repeats: Int) -> [ProgramCustomWorkoutMicroStage] {
        stages.map { stage in
            var updated = stage
            if updated.role == .work || updated.role == .recovery {
                updated.repeats = min(max(repeats, 1), 12)
            }
            return updated
        }
    }

    private func defaultTargetText(for goal: ProgramMicroStageGoal, request: ProgramPlannerRequest) -> String {
        switch goal {
        case .heartRateZone:
            return request.target?.metric == .heartRateZone ? request.target?.descriptor ?? "Zone 2" : "Zone 2"
        case .power, .pace, .speed, .cadence, .distance, .energy:
            let descriptor = request.target?.descriptor.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return descriptor.isEmpty ? goal.placeholder : descriptor
        case .open, .time:
            return ""
        }
    }

    private func normalizedTargetDescriptor(from request: ProgramPlannerRequest, fallback: String) -> String {
        let descriptor = request.target?.descriptor.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return descriptor.isEmpty ? fallback : descriptor
    }

    private func allowedGoals(for role: ProgramMicroStageRole, activity: ProgramWorkoutType) -> [ProgramMicroStageGoal] {
        activity.supportedMicroStageGoals(for: role)
    }

    private func preferredSteadyOrWorkGoal(for activity: ProgramWorkoutType) -> ProgramMicroStageGoal {
        allowedGoals(for: .steady, activity: activity).first ?? .time
    }

    private func defaultDescriptor(for goal: ProgramMicroStageGoal) -> String {
        switch goal {
        case .heartRateZone:
            return "Zone 2"
        case .power:
            return "220-260 W"
        case .pace:
            return "7:10-7:30 /mi"
        case .speed:
            return "18-20 mph"
        case .cadence:
            return "100-110 rpm"
        case .distance:
            return "5 km"
        case .energy:
            return "300 kcal"
        case .open, .time:
            return ""
        }
    }

    private func normalizeStage(_ stage: ProgramCustomWorkoutMicroStage, for activity: ProgramWorkoutType?) -> ProgramCustomWorkoutMicroStage {
        guard let activity else { return stage }
        var updated = stage
        let allowed = allowedGoals(for: updated.role, activity: activity)
        if !allowed.contains(updated.goal) {
            updated.goal = allowed.first ?? .time
        }
        updated.targetBehavior = updated.role.defaultTargetBehavior
        if updated.goal.requiresDescriptorInput && updated.targetValueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.targetValueText = defaultDescriptor(for: updated.goal)
        }
        if !updated.goal.requiresDescriptorInput {
            updated.targetValueText = ""
        }
        if updated.circuitGroupID == nil {
            updated.repeatSetLabel = ""
        }
        return updated
    }

    private func fallbackGoal(for request: ProgramPlannerRequest, activity: ProgramWorkoutType) -> ProgramMicroStageGoal {
        let supportedGoals = ProgramMicroStageGoal.allCases.filter { goal in
            ProgramMicroStageRole.allCases.contains { activity.supportedMicroStageGoals(for: $0).contains(goal) }
        }

        if let target = request.target {
            switch target.metric {
            case .pace:
                if supportedGoals.contains(.pace) { return .pace }
                if supportedGoals.contains(.speed) { return .speed }
            case .power:
                if supportedGoals.contains(.power) { return .power }
            case .heartRateZone:
                if supportedGoals.contains(.heartRateZone) { return .heartRateZone }
            case .cadence:
                if supportedGoals.contains(.cadence) { return .cadence }
            case .distance:
                if supportedGoals.contains(.distance) { return .distance }
            }
        }
        if supportedGoals.contains(.time) {
            return .time
        }
        return supportedGoals.first ?? .time
    }
}

private let programBuilderCoachInstructions = """
You are an AI coach for building the next training session.
Focus mainly on what the user can do today.
Never suggest a specific named workout, interval structure, rep scheme, or hidden add-on.
Do not say things like do a tempo run, 6 x 3 minutes, 5 minute cooldown, or 20 minute threshold unless the user explicitly requested those details.
Instead, give general advice on purpose, effort control, session feel, and how ambitious or restrained today should be.
Use direct second-person language.
Stay supportive, grounded, and practical.
Plain text only.

Classification rubric (this app’s coaching semantics):
- Recovery/Readiness score 90–100: Full Send. This is wonderful. Applaud it and speak confidently about quality work.
- Recovery/Readiness score 70–89: Perform. Also wonderful. Encourage momentum and quality.
- Recovery/Readiness score 40–69: Adapt. This is still workable and often fine. Do NOT catastrophize. If it is 60–69, treat it as "still good / workable". If it is 40–50, acknowledge it is a bit rough and suggest a more controlled version of the intent.
- Recovery/Readiness score 0–39: Recover. This is the clearest low-recovery state. Call it out calmly and suggest rebuilding reserve without shaming.

- Strain is a 0–21 load score. Interpret it as training-load context, not overtraining risk by default.
  - Low Day: low strain / low recent load. Not a problem; sometimes it means "not enough intensity lately" depending on goals.
  - Building: moderate strain. Fine; do not worry.
  - Productive: solid strain in a trainable zone. Applaud; this is a good place to be.
  - Spike: unusually high acute load relative to baseline. Mention it as "extra strain" and suggest smart guardrails, but do NOT be alarmist about overtraining.
"""

private let programBuilderGenerationInstructions = """
You generate structured workout blueprints from explicit user constraints.
Respect the selected activities, time budget, planning mode, and route or target details.
Never add cooldown, warmup, stretching, yoga, mobility, or extra sports unless they were explicitly selected.
Do not try to optimize the workout by sneaking in things the user did not ask for.
Each block should have a clear purpose and fit the available minutes.

Use the same Recovery/Readiness and Strain semantics as the app:
- Full Send / Perform: confident, encouraging.
- Adapt: still capable; emphasize controlled intent and sharp execution (especially 40–50), not fear.
- Recover: gentle caution and rebuilding reserve.
- Productive/Building strain: do not frame as overtraining risk.
- Spike: note extra strain but avoid panic language.
"""

private let programBuilderMicroStageInstructions = """
You rebuild workout micro-stages from the user's note and current training context.
Make real structural changes, not cosmetic rewrites.
Keep the session faithful to the selected activity, total time, and requested focus.
When the user asks for more recovery, intensity, warmup, cooldown, or different emphasis, change the stage durations, repeat structure, goals, and labels accordingly.
Use short practical notes.

Coaching tone calibration:
- Do NOT default to overtraining fear. Only mention overreach risk when evidence is strong and repeated.
- If Recovery/Readiness is Full Send or Perform, be upbeat and confident.
- If Recovery/Readiness is Adapt, keep suggestions forward-moving; use control knobs (fewer hard minutes, longer recoveries, tighter execution) rather than "back off" vibes.
- If Recovery/Readiness is Recover, keep the stages doable and supportive of rebuilding.
"""

private func dismissProgramBuilderKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A regenerated set of workout micro-stages.")
struct ProgramGeneratedMicroStagePlan {
    @Generable(description: "One regenerated workout micro-stage.")
    struct Stage {
        var title: String
        var notes: String
        var roleRawValue: String
        var goalRawValue: String
        var plannedMinutes: Int
        var repeats: Int
        var targetValueText: String
        var repeatSetLabel: String
    }

    var stages: [Stage]
}

typealias ProgramGeneratedMicroStage = ProgramGeneratedMicroStagePlan.Stage
#else
struct ProgramGeneratedMicroStagePlan {
    struct Stage {
        var title: String
        var notes: String
        var roleRawValue: String
        var goalRawValue: String
        var plannedMinutes: Int
        var repeats: Int
        var targetValueText: String
        var repeatSetLabel: String
    }

    var stages: [Stage]
}

typealias ProgramGeneratedMicroStage = ProgramGeneratedMicroStagePlan.Stage
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A structured workout blueprint for today.")
struct ProgramGeneratedBlueprint: Identifiable, Codable, Hashable {
    @Generable(description: "A single block inside the generated workout blueprint.")
    struct Block: Identifiable, Codable, Hashable {
        var id: String { "\(title)-\(minutes)" }
        var title: String
        var minutes: Int
        var focus: String
        var cue: String
    }

    var id: String { title }
    var title: String
    var summary: String
    var todayFocus: String
    var blocks: [Block]
    var cautionNote: String?
}
#else
struct ProgramGeneratedBlueprint: Identifiable, Codable, Hashable {
    struct Block: Identifiable, Codable, Hashable {
        var id: String { "\(title)-\(minutes)" }
        var title: String
        var minutes: Int
        var focus: String
        var cue: String
    }

    var id: String { title }
    var title: String
    var summary: String
    var todayFocus: String
    var blocks: [Block]
    var cautionNote: String?
}
#endif

private func insight(from workout: HKWorkout, analytics: WorkoutAnalytics) -> ProgramRecentWorkout {
    let intensity: String
    let duration = workout.duration / 60
    switch duration {
    case ..<30:
        intensity = "short"
    case ..<75:
        intensity = "moderate"
    default:
        intensity = "long"
    }

    return ProgramRecentWorkout(
        date: workout.startDate,
        activity: workout.workoutActivityType.name,
        durationMinutes: duration,
        calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
        intensity: intensity,
        highlight: analytics.heartRates.isEmpty ? nil : "heart rate stayed tracked through the session"
    )
}

private func normalizeCoachRegenerationText(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let collapsed = trimmed
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    let lowered = collapsed.lowercased()
    let normalized = lowered
        .replacingOccurrences(of: "hr", with: "heart rate")
        .replacingOccurrences(of: "mtb", with: "mountain biking")
        .replacingOccurrences(of: "cd", with: "cooldown")
        .replacingOccurrences(of: "wu", with: "warmup")
        .replacingOccurrences(of: "z2", with: "zone 2")
        .replacingOccurrences(of: "z3", with: "zone 3")
        .replacingOccurrences(of: "z4", with: "zone 4")
        .replacingOccurrences(of: "z5", with: "zone 5")

    if normalized.count > 220 {
        return String(normalized.prefix(220))
    }
    return normalized
}

private extension String {
    var firstPositiveInteger: Int? {
        let digits = components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first { !$0.isEmpty }
        guard let digits, let value = Int(digits), value > 0 else { return nil }
        return value
    }

    func captureGroups(for pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, options: [], range: nsRange).map { match in
            guard match.numberOfRanges > 1 else { return [] }
            return (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: self) else { return nil }
                return String(self[range])
            }
        }
    }
}

private func describeProgramWorkout(_ workout: ProgramRecentWorkout) -> String {
    let minutes = Int(workout.durationMinutes.rounded())
    var text = "\(workout.intensity.capitalized) \(workout.activity) session of \(minutes) minutes"
    if let highlight = workout.highlight {
        text += ", which was \(highlight)"
    }
    text += "."
    return text
}
