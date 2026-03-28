import SwiftUI
import HealthKit
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ProgramBuilderView: View {
    @StateObject private var engine = HealthStateEngine.shared
    @StateObject private var planner = ProgramBuilderAIPlanner()
    @StateObject private var liveWorkoutManager = CompanionWorkoutLiveManager.shared

    @State private var searchText = ""
    @State private var selectedMode: ProgramBuilderMode = .guided
    @State private var selectedActivityIDs: [String] = ["running"]
    @State private var customActivities: [ProgramWorkoutType] = []
    @State private var customActivityName = ""
    @State private var availableMinutes: Double = 60
    @State private var allocationWeights: [String: Double] = ["running": 1]
    @State private var selectedTargetMetric: ProgramTargetMetric = .pace
    @State private var selectedZone = 3
    @State private var targetValueText = ""
    @State private var routeObjectiveName = ""
    @State private var routeRepeats = 1
    @State private var selectedRouteTemplateID: UUID?
    @State private var plannedRouteLaunchMetadata: RouteLaunchMetadata?

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

    private var wideLayout: Bool {
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

    private var routeTemplates: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        engine.workoutAnalytics
            .filter { pair in
                let activity = pair.workout.workoutActivityType
                return [.running, .walking, .hiking, .cycling].contains(activity)
            }
            .sorted { $0.workout.startDate > $1.workout.startDate }
            .prefix(8)
            .map { $0 }
    }

    private var selectedRouteTemplate: (workout: HKWorkout, analytics: WorkoutAnalytics)? {
        routeTemplates.first { $0.workout.uuid == selectedRouteTemplateID }
    }

    private var coachContextID: String {
        [
            selectedMode.rawValue,
            selectedActivityIDs.joined(separator: ","),
            String(Int(availableMinutes.rounded())),
            targetValueText,
            String(selectedZone),
            routeObjectiveName,
            String(routeRepeats)
        ].joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if wideLayout || proxy.size.width > 920 {
                    HStack(alignment: .top, spacing: 24) {
                        leftColumn
                            .frame(width: min(430, proxy.size.width * 0.36))
                        rightColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 20) {
                        leftColumn
                        rightColumn
                    }
                    .padding(16)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(programBuilderBackground.ignoresSafeArea())
        }
        .navigationTitle("Program Builder")
        .navigationBarTitleDisplayMode(.large)
        .task(id: coachContextID) {
            await planner.refreshCoachAdvice(
                for: buildPlannerRequest(),
                engine: engine
            )
        }
        .onChange(of: selectedActivityIDs) { _, newValue in
            rebalanceWeights(for: newValue)
            syncTargetMetric()
        }
        .onChange(of: selectedMode) { _, _ in
            plannedRouteLaunchMetadata = nil
        }
        .onChange(of: selectedRouteTemplateID) { _, _ in
            plannedRouteLaunchMetadata = nil
        }
        .onChange(of: routeObjectiveName) { _, _ in
            plannedRouteLaunchMetadata = nil
        }
        .onChange(of: routeRepeats) { _, _ in
            plannedRouteLaunchMetadata = nil
        }
        .onAppear {
            rebalanceWeights(for: selectedActivityIDs)
            syncTargetMetric()
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
                }
            }

            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Search Every Activity")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    TextField("Search running, ski touring, yoga, triathlon...", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        TextField("Add your own activity", text: $customActivityName)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button("Add") {
                            addCustomActivity()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
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
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected For Today")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Use one sport, blend several, chase a target, or plan around a route.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Text("\(Int(availableMinutes.rounded())) min")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.orange)
                    }

                    Slider(value: $availableMinutes, in: 15...240, step: 5)
                        .tint(.orange)

                    if selectedActivities.isEmpty {
                        ProgramEmptyState(
                            title: "Choose at least one activity",
                            subtitle: "Search the full catalog or pick from the suggestions on the left."
                        )
                    } else {
                        AdaptiveChipGrid(selectedActivities) { activity in
                                ProgramSelectedActivityChip(
                                    activity: activity,
                                    allocationText: allocationText(for: activity.id)
                                ) {
                                    removeActivity(activity.id)
                                }
                        }
                    }
                }
            }

            ProgramSectionCard {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Planning Mode", selection: $selectedMode) {
                        ForEach(ProgramBuilderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedMode {
                    case .guided:
                        guidedPlanningView
                    case .target:
                        targetPlanningView
                    case .route:
                        routePlanningView
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
                            Text("Guided Generation")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Build a session outline that matches exactly what you selected. No surprise add-ons.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Button {
                            Task {
                                await planner.generateBlueprint(for: buildPlannerRequest(), engine: engine)
                                plannedRouteLaunchMetadata = await routeLaunchMetadata()
                            }
                        } label: {
                            if planner.isGeneratingPlan {
                                ProgressView()
                                    .tint(.black)
                                    .frame(width: 30, height: 30)
                            } else {
                                Text("Generate")
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(selectedActivities.isEmpty || planner.isGeneratingPlan)
                    }

                    if let errorText = planner.planErrorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.orange.opacity(0.9))
                    }

                    if let blueprint = planner.generatedBlueprint {
                        ProgramGeneratedBlueprintView(blueprint: blueprint)
                    } else {
                        ProgramEmptyState(
                            title: "No workout generated yet",
                            subtitle: "Pick your sports, choose a planning route, then generate a clean outline from those constraints."
                        )
                    }
                }
            }
        }
    }

    private var workoutLaunchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start This Workout")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Run it here on iPhone or hand it straight to Apple Watch. Outdoor starts use device GPS, and connected HealthKit-compatible sensors can flow into the live view.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if liveWorkoutManager.isWorkoutActive {
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

                HStack(spacing: 12) {
                    ProgramLaunchButton(
                        title: "Start on iPhone",
                        subtitle: activity.routeFriendly ? "GPS + phone-connected feeds" : "Local live workout",
                        symbol: "iphone",
                        tint: .cyan
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
                        tint: .orange
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
                                routeName: routeLaunch.name.isEmpty ? nil : routeLaunch.name,
                                trailheadCoordinate: routeLaunch.trailhead,
                                routeCoordinates: routeLaunch.coordinates
                            )
                        }
                    }
                }

                if let launchStatusMessage = liveWorkoutManager.launchStatusMessage, !launchStatusMessage.isEmpty {
                    Text(launchStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                ProgramEmptyState(
                    title: "Pick the primary activity first",
                    subtitle: "The first selected activity becomes the live workout type for iPhone or Apple Watch."
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(activity.title, systemImage: activity.symbol)
                                Spacer()
                                Text(allocationText(for: activity.id))
                                    .foregroundStyle(activity.tint)
                            }
                            .font(.subheadline.weight(.semibold))

                            Slider(
                                value: Binding(
                                    get: { allocationWeights[activity.id, default: 1] },
                                    set: { allocationWeights[activity.id] = max(0.15, $0) }
                                ),
                                in: 0.15...3,
                                step: 0.05
                            )
                            .tint(activity.tint)
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

            if let primary = selectedActivities.first {
                HStack(spacing: 12) {
                    Label(primary.title, systemImage: primary.symbol)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(primary.category.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(primary.tint)
                }

                Picker("Target", selection: $selectedTargetMetric) {
                    ForEach(primary.supportedTargets) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTargetMetric == .heartRateZone {
                    Stepper("Zone \(selectedZone)", value: $selectedZone, in: 1...5)
                        .foregroundStyle(.white)
                } else {
                    TextField(
                        selectedTargetMetric.placeholder,
                        text: $targetValueText
                    )
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Text(selectedTargetMetric.guidance)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                ProgramEmptyState(
                    title: "Pick a sport first",
                    subtitle: "Choose the primary sport, then set the target you care about today."
                )
            }
        }
    }

    private var routePlanningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Route-Led Session Design")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Use a course, trail, or familiar loop as the anchor. The watch can show the route while the phone handles the planning step.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            TextField("Name the route, trail, climb, or course", text: $routeObjectiveName)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Stepper("Repeats: \(routeRepeats)", value: $routeRepeats, in: 1...10)
                .foregroundStyle(.white)

            if routeTemplates.isEmpty {
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

    private func toggleActivity(_ id: String) {
        if selectedActivityIDs.contains(id) {
            removeActivity(id)
        } else {
            selectedActivityIDs.append(id)
            allocationWeights[id] = allocationWeights[id] ?? 1
        }
    }

    private func removeActivity(_ id: String) {
        selectedActivityIDs.removeAll { $0 == id }
        allocationWeights.removeValue(forKey: id)
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
        allocationWeights[item.id] = 1
        customActivityName = ""
    }

    private func rebalanceWeights(for ids: [String]) {
        let active = Set(ids)
        allocationWeights = allocationWeights.filter { active.contains($0.key) }
        for id in ids where allocationWeights[id] == nil {
            allocationWeights[id] = 1
        }
    }

    private func syncTargetMetric() {
        guard let primary = selectedActivities.first else { return }
        if !primary.supportedTargets.contains(selectedTargetMetric) {
            selectedTargetMetric = primary.supportedTargets.first ?? .heartRateZone
        }
    }

    private func allocationText(for id: String) -> String {
        let totalWeight = selectedActivityIDs.reduce(0.0) { $0 + allocationWeights[$1, default: 1] }
        guard totalWeight > 0 else { return "\(Int(availableMinutes.rounded())) min" }
        let weight = allocationWeights[id, default: 1]
        let minutes = max(5, Int((availableMinutes * (weight / totalWeight)).rounded()))
        return "\(minutes) min"
    }

    private func buildPlannerRequest() -> ProgramPlannerRequest {
        let target = selectedMode == .target
            ? ProgramPlannerRequest.TargetPreference(
                metric: selectedTargetMetric,
                descriptor: selectedTargetMetric == .heartRateZone ? "Zone \(selectedZone)" : targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            : nil

        let route = selectedMode == .route
            ? ProgramPlannerRequest.RoutePreference(
                name: routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines),
                repeats: routeRepeats,
                templateName: selectedRouteTemplate?.workout.workoutActivityType.name
            )
            : nil

        return ProgramPlannerRequest(
            selectedActivities: selectedActivities,
            availableMinutes: Int(availableMinutes.rounded()),
            mode: selectedMode,
            allocations: selectedActivities.reduce(into: [:]) { partial, activity in
                partial[activity.title] = allocationText(for: activity.id)
            },
            target: target,
            route: route,
            recentWorkouts: engine.workoutAnalytics.prefix(8).map { insight(from: $0.workout, analytics: $0.analytics) },
            recoveryScore: engine.recoveryScore,
            readinessScore: engine.readinessScore,
            strainScore: engine.strainScore
        )
    }

    private func launchSubtitle(for activity: ProgramWorkoutType) -> String {
        switch selectedMode {
        case .guided:
            return "\(Int(availableMinutes.rounded())) min • \(activity.title)"
        case .target:
            let detail = selectedTargetMetric == .heartRateZone
                ? "Zone \(selectedZone)"
                : targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(Int(availableMinutes.rounded())) min • \(activity.title)"
                : "\(Int(availableMinutes.rounded())) min • \(selectedTargetMetric.title): \(detail)"
        case .route:
            let routeName = routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
            if routeName.isEmpty {
                return "\(Int(availableMinutes.rounded())) min • Route session"
            }
            return "\(routeName) • \(routeRepeats)x"
        }
    }

    private func routeLaunchMetadata() async -> RouteLaunchMetadata? {
        guard selectedMode == .route else { return nil }

        let name = routeObjectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workout = selectedRouteTemplate?.workout else {
            return name.isEmpty ? nil : RouteLaunchMetadata(name: name, trailhead: nil, coordinates: [])
        }

        let coordinates = await fetchRouteCoordinates(for: workout, maximumPoints: 120)
        let trailhead = coordinates.first
        let resolvedName = name.isEmpty ? workout.workoutActivityType.name.capitalized : name
        return RouteLaunchMetadata(name: resolvedName, trailhead: trailhead, coordinates: coordinates)
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

private struct ProgramBuilderCoachSection: View {
    @ObservedObject var planner: ProgramBuilderAIPlanner
    let request: ProgramPlannerRequest
    let refreshAction: () -> Void

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
                            .tint(.black)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            HStack(spacing: 10) {
                ProgramStatBadge(title: "Recovery", value: "\(Int(request.recoveryScore.rounded()))", tint: .green)
                ProgramStatBadge(title: "Readiness", value: "\(Int(request.readinessScore.rounded()))", tint: .cyan)
                ProgramStatBadge(title: "Strain", value: "\(Int(request.strainScore.rounded()))", tint: .orange)
            }

            Text(planner.coachAdvice)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            if let coachError = planner.coachErrorText {
                Text(coachError)
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.9))
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
                .foregroundStyle(activity.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                Text(allocationText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(activity.tint)
            }
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: Capsule())
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ProgramLaunchButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
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

private let programBuilderBackground = LinearGradient(
    colors: [
        Color(red: 0.07, green: 0.06, blue: 0.05),
        Color(red: 0.20, green: 0.09, blue: 0.04),
        Color(red: 0.06, green: 0.12, blue: 0.10)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private enum ProgramBuilderMode: String, CaseIterable, Identifiable {
    case guided
    case target
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guided:
            return "Guided"
        case .target:
            return "Target"
        case .route:
            return "Route"
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
        .init(id: "cooldown", title: "Cooldown", subtitle: "Explicit low-intensity finish", symbol: "wind.down.circle", category: .recovery, tint: .blue, keywords: ["cooldown", "cool down"], supportedTargets: [.heartRateZone], routeFriendly: false, aliasMatches: ["cooldown"]),
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
    let allocations: [String: String]
    let target: TargetPreference?
    let route: RoutePreference?
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

private struct ProgramRecentWorkout: Identifiable {
    let id = UUID()
    let date: Date
    let activity: String
    let durationMinutes: Double
    let calories: Double
    let intensity: String
    let highlight: String?
}

@MainActor
private final class ProgramBuilderAIPlanner: ObservableObject {
    @Published var coachAdvice = "Preparing your next-session coach..."
    @Published var generatedBlueprint: ProgramGeneratedBlueprint?
    @Published var isGeneratingCoach = false
    @Published var isGeneratingPlan = false
    @Published var coachErrorText: String?
    @Published var planErrorText: String?

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

    private func fallbackCoachAdvice(for request: ProgramPlannerRequest, engine: HealthStateEngine) -> String {
        let activities = request.selectedActivities.map(\.title).joined(separator: ", ")
        let readiness = Int(request.readinessScore.rounded())
        let recovery = Int(request.recoveryScore.rounded())
        let strain = Int(request.strainScore.rounded())

        if request.selectedActivities.isEmpty {
            return "Today looks like a good day to choose the type of session first, then set the constraint that matters most. Start by deciding whether you want skill, controlled aerobic work, or something short and punchy."
        }

        if recovery >= 75 && readiness >= 75 {
            return "You look fairly ready today. Keep the \(activities) session purposeful and contained inside the \(request.availableMinutes)-minute window you set. If you want quality, anchor it around one clear objective instead of stacking too many demands. Strain is at \(strain), so you have room to do something meaningful without forcing extra pieces that you did not ask for."
        }

        if recovery < 55 || readiness < 55 {
            return "Today reads more like a control day than a reach day. Keep \(activities) honest, smooth, and sustainable inside the \(request.availableMinutes)-minute window. Focus on rhythm, technique, and leaving yourself better than you started. With recovery at \(recovery) and readiness at \(readiness), the best move today is usually restraint rather than chasing extra load."
        }

        return "You are in a workable middle zone today. Let the \(activities) session be specific, but keep the overall ask clean. Use the time you set, stay close to the main intent, and avoid layering extras unless you explicitly want them. Recovery \(recovery), readiness \(readiness), and strain \(strain) suggest a solid day for focused work without needing to overcomplicate it."
    }

    private func fallbackBlueprint(for request: ProgramPlannerRequest, engine: HealthStateEngine) -> ProgramGeneratedBlueprint {
        let title = request.selectedActivities.isEmpty ? "Today Session" : request.selectedActivities.map(\.title).joined(separator: " + ")
        let blocks = request.selectedActivities.map { activity in
            ProgramGeneratedBlueprint.Block(
                title: activity.title,
                minutes: max(5, allocationMinutes(for: activity.title, request: request)),
                focus: request.mode == .target && request.target != nil
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
        case .target:
            if let target = request.target {
                let descriptor = target.descriptor.isEmpty ? target.metric.title : target.descriptor
                return "Hold the work around \(descriptor) and avoid drifting away from the target."
            }
            return "Use one target and stay disciplined around it."
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
        case .target:
            if let target = request.target {
                return "Today focus: stay centered on \(target.metric.title.lowercased())\(target.descriptor.isEmpty ? "" : " at \(target.descriptor)")."
            }
            return "Today focus: target-led control."
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
        return """
        Today context:
        - Selected activities: \(selectedActivities.isEmpty ? "none selected yet" : selectedActivities)
        - Available time: \(request.availableMinutes) minutes
        - Planning mode: \(request.mode.title)
        - Recovery score: \(Int(request.recoveryScore.rounded())) / 100
        - Readiness score: \(Int(request.readinessScore.rounded())) / 100
        - Strain score: \(Int(request.strainScore.rounded())) / 21
        - Recent workouts: \(recent.isEmpty ? "none loaded" : recent)
        - Target preference: \(request.target?.metric.title ?? "none"), \(request.target?.descriptor ?? "none")
        - Route preference: \(request.route?.name ?? "none"), repeats \(request.route?.repeats ?? 0)

        Give general advice for the next session, with the emphasis on what the user can realistically do today.
        Never prescribe a specific workout, interval recipe, or named session.
        Keep it plain text, direct, supportive, and under 170 words.
        """
    }

    private func blueprintPrompt(for request: ProgramPlannerRequest) -> String {
        let selectedActivities = request.selectedActivities.map(\.title).joined(separator: ", ")
        let allocations = request.allocations.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
        let targetLine = request.target.map { "\($0.metric.title): \($0.descriptor.isEmpty ? "general focus" : $0.descriptor)" } ?? "none"
        let routeLine = request.route.map { "\($0.name.isEmpty ? "unnamed route" : $0.name), repeats \($0.repeats), template \($0.templateName ?? "none")" } ?? "none"

        return """
        Build a structured workout blueprint from these exact user constraints:
        - Activities selected: \(selectedActivities)
        - Available minutes: \(request.availableMinutes)
        - Planning mode: \(request.mode.title)
        - Activity allocations: \(allocations)
        - Target preference: \(targetLine)
        - Route preference: \(routeLine)

        Hard constraints:
        - Do not invent cooldown, warmup, mobility, stretching, or extra sports unless the user explicitly selected them.
        - Do not act clever or add a block "because it would be smart."
        - Keep the blueprint faithful to the selected activities and the time budget.
        - Make the block titles concise and useful.
        - Keep the focus and cue practical.
        - The summary should reflect today, not a generic training plan.
        """
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
"""

private let programBuilderGenerationInstructions = """
You generate structured workout blueprints from explicit user constraints.
Respect the selected activities, time budget, planning mode, and route or target details.
Never add cooldown, warmup, stretching, yoga, mobility, or extra sports unless they were explicitly selected.
Do not try to optimize the workout by sneaking in things the user did not ask for.
Each block should have a clear purpose and fit the available minutes.
"""

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A structured workout blueprint for today.")
private struct ProgramGeneratedBlueprint: Identifiable {
    @Generable(description: "A single block inside the generated workout blueprint.")
    struct Block: Identifiable {
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
private struct ProgramGeneratedBlueprint: Identifiable {
    struct Block: Identifiable {
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

private func describeProgramWorkout(_ workout: ProgramRecentWorkout) -> String {
    let minutes = Int(workout.durationMinutes.rounded())
    var text = "\(workout.intensity.capitalized) \(workout.activity) session of \(minutes) minutes"
    if let highlight = workout.highlight {
        text += ", which was \(highlight)"
    }
    text += "."
    return text
}
