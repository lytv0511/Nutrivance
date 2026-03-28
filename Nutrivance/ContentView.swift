import SwiftUI
import HealthKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

private enum WorkoutMetricsVariant {
    case primary
    case secondary
}

@MainActor
class AppState: ObservableObject {
    @Published var healthKitManager = HealthKitManager()
    @Published var selectedNutrient: String?
    @Published var navigationPath = NavigationPath()
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var engine = HealthStateEngine.shared
    @StateObject private var companionWorkoutManager = CompanionWorkoutLiveManager.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("startup_curtain_dismissed") private var hasDismissedStartupCurtain = false
    @State private var showStartupCurtain = true

    private var startupStatusText: String {
        let hasCoreHealthBootstrap =
            engine.hasHydratedCachedMetrics ||
            !engine.dailyHRV.isEmpty ||
            !engine.dailyRestingHeartRate.isEmpty ||
            !engine.sleepStages.isEmpty

        if !engine.hasHydratedCachedMetrics && !engine.hasInitializedWorkoutAnalytics {
            return "Loading cached health data..."
        }
        if engine.isSyncingStartupWorkoutCoverage {
            return "Fetching workouts..."
        }
        if engine.isRefreshingCachedMetrics {
            return "Updating metrics..."
        }
        if !engine.hasInitializedWorkoutAnalytics {
            return "Preparing workout history..."
        }
        if !hasCoreHealthBootstrap {
            return "Updating recovery metrics..."
        }
        return "Finalizing startup..."
    }
    
    var body: some View {
        ZStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
    //                if horizontalSizeClass == .regular {
    //                    ContentView_iPad_alt()
    //                        .environmentObject(appState)
//                    ContentView_iPad_alt()
                    ContentView_iPad_alt()
    //                } else {
    //                    ContentView_iPad()
    //                        .environmentObject(appState)
    //                }
                } else if UIDevice.current.userInterfaceIdiom == .phone {
                    ContentView_iPhone_alt()
//                    ContentView_iPad_alt()
                }
            }

            if showStartupCurtain && !hasDismissedStartupCurtain {
                StartupCurtainView(statusText: startupStatusText)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }

            if companionWorkoutManager.isVisible {
                CompanionWorkoutLiveOverlay(manager: companionWorkoutManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(8)
                    .transition(.opacity)
            } else if companionWorkoutManager.canReopenLiveView {
                CompanionWorkoutReentryButton(manager: companionWorkoutManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 20)
                    .zIndex(7)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            guard !hasDismissedStartupCurtain else {
                showStartupCurtain = false
                return
            }

            let minimumCurtainDuration: UInt64 = engine.hasHydratedCachedMetrics ? 700_000_000 : 2_200_000_000
            let maximumCurtainDuration: UInt64 = 12_000_000_000
            let pollInterval: UInt64 = 200_000_000

            let startedAt = Date()
            try? await Task.sleep(nanoseconds: minimumCurtainDuration)

            while Date().timeIntervalSince(startedAt) < Double(maximumCurtainDuration) / 1_000_000_000 {
                let hasWorkoutBootstrap = engine.hasInitializedWorkoutAnalytics
                let hasCoreHealthBootstrap =
                    engine.hasHydratedCachedMetrics ||
                    !engine.dailyHRV.isEmpty ||
                    !engine.dailyRestingHeartRate.isEmpty ||
                    !engine.sleepStages.isEmpty

                if engine.requiresInitialFullSync {
                    if hasWorkoutBootstrap && !engine.isSyncingStartupWorkoutCoverage {
                        break
                    }
                } else if (hasWorkoutBootstrap || hasCoreHealthBootstrap) && !engine.isSyncingStartupWorkoutCoverage {
                    break
                }

                try? await Task.sleep(nanoseconds: pollInterval)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                hasDismissedStartupCurtain = true
                showStartupCurtain = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, hasDismissedStartupCurtain else { return }
            showStartupCurtain = false
            companionWorkoutManager.activateIfNeeded()
        }
        .onAppear {
            companionWorkoutManager.activateIfNeeded()
        }
    }
}

private struct StartupCurtainView: View {
    let statusText: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.94), Color.orange.opacity(0.24), Color.black.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 104, height: 104)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.orange)
                }
                Text("Preparing Nutrivance")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundColor(.white)
                Text(statusText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, 32)
                ProgressView()
                    .tint(.orange)
                    .scaleEffect(1.15)
                    .padding(.top, 4)
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

enum CompanionWorkoutPageKind: String, CaseIterable, Identifiable {
    case metricsPrimary
    case metricsSecondary
    case heartRateZones
    case segments
    case splits
    case elevationGraph
    case powerGraph
    case powerZones
    case pacer
    case map

    var id: String { rawValue }
}

struct CompanionWorkoutSeriesPoint: Identifiable, Hashable {
    let elapsedTime: TimeInterval
    let value: Double

    var id: TimeInterval { elapsedTime }
}

struct CompanionWorkoutSplit: Identifiable, Hashable {
    let index: Int
    let elapsedTime: TimeInterval
    let splitDuration: TimeInterval
    let splitDistanceMeters: Double
    let averageHeartRate: Double?
    let averageSpeedMetersPerSecond: Double?
    let averagePowerWatts: Double?
    let averageCadence: Double?

    var id: Int { index }
}

struct CompanionWorkoutPacerTarget: Hashable {
    let lowerBound: Double
    let upperBound: Double
    let unitLabel: String
}

@MainActor
final class CompanionWorkoutLiveManager: NSObject, ObservableObject {
    static let shared = CompanionWorkoutLiveManager()

    enum WorkoutControlCommand: String {
        case pause
        case resume
        case split
        case stop
        case newWorkout
    }

    private struct MirroredMetricPayload: Codable {
        let id: String
        let title: String
        let valueText: String
        let symbol: String
        let tintName: String
    }

    private struct MirroredWorkoutSnapshotPayload: Codable {
        let title: String
        let stateText: String
        let activityRawValue: UInt
        let elapsedTime: TimeInterval
        let metrics: [MirroredMetricPayload]
        let pageKinds: [String]
        let speedHistory: [MirroredSeriesPointPayload]
        let paceHistory: [MirroredSeriesPointPayload]
        let powerHistory: [MirroredSeriesPointPayload]
        let elevationHistory: [MirroredSeriesPointPayload]
        let cadenceHistory: [MirroredSeriesPointPayload]
        let heartRateHistory: [MirroredSeriesPointPayload]
        let splits: [MirroredSplitPayload]
        let heartRateZoneDurations: [TimeInterval]
        let powerZoneDurations: [TimeInterval]
        let totalDistanceMeters: Double
        let currentHeartRate: Double?
        let averageHeartRate: Double?
        let currentSpeedMetersPerSecond: Double?
        let currentPowerWatts: Double?
        let averagePowerWatts: Double?
        let currentCadence: Double?
        let currentElevationFeet: Double
        let elevationGainFeet: Double
        let pacerTarget: MirroredPacerPayload?
    }

    private struct MirroredSeriesPointPayload: Codable {
        let elapsedTime: TimeInterval
        let value: Double
    }

    private struct MirroredSplitPayload: Codable {
        let index: Int
        let elapsedTime: TimeInterval
        let splitDuration: TimeInterval
        let splitDistanceMeters: Double
        let averageHeartRate: Double?
        let averageSpeedMetersPerSecond: Double?
        let averagePowerWatts: Double?
        let averageCadence: Double?
    }

    private struct MirroredPacerPayload: Codable {
        let lowerBound: Double
        let upperBound: Double
        let unitLabel: String
    }

    struct LiveMetric: Identifiable, Hashable {
        let id: String
        let title: String
        let value: String
        let symbol: String
        let tint: Color
    }

    @Published private(set) var isVisible = false
    @Published private(set) var title = "Watch Workout"
    @Published private(set) var stateText = "Preparing"
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var metrics: [LiveMetric] = []
    @Published private(set) var activityType: HKWorkoutActivityType = .running
    @Published private(set) var pageKinds: [CompanionWorkoutPageKind] = [.metricsPrimary, .heartRateZones, .map]
    @Published private(set) var speedHistory: [CompanionWorkoutSeriesPoint] = []
    @Published private(set) var paceHistory: [CompanionWorkoutSeriesPoint] = []
    @Published private(set) var powerHistory: [CompanionWorkoutSeriesPoint] = []
    @Published private(set) var elevationHistory: [CompanionWorkoutSeriesPoint] = []
    @Published private(set) var cadenceHistory: [CompanionWorkoutSeriesPoint] = []
    @Published private(set) var heartRateHistory: [CompanionWorkoutSeriesPoint] = []
    @Published private(set) var splits: [CompanionWorkoutSplit] = []
    @Published private(set) var heartRateZoneDurations: [TimeInterval] = Array(repeating: 0, count: 5)
    @Published private(set) var powerZoneDurations: [TimeInterval] = Array(repeating: 0, count: 5)
    @Published private(set) var totalDistanceMeters: Double = 0
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var currentSpeedMetersPerSecond: Double?
    @Published private(set) var currentPowerWatts: Double?
    @Published private(set) var averagePowerWatts: Double?
    @Published private(set) var currentCadence: Double?
    @Published private(set) var currentElevationFeet: Double = 0
    @Published private(set) var elevationGainFeet: Double = 0
    @Published private(set) var pacerTarget: CompanionWorkoutPacerTarget?
    @Published private(set) var isWorkoutActive = false

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var hasActivated = false

    var canReopenLiveView: Bool {
        isWorkoutActive && !isVisible
    }

    func activateIfNeeded() {
        guard hasActivated == false else { return }
        hasActivated = true
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attachMirroredSession(session)
            }
        }
    }

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        mirroredSession = session
        session.delegate = self
        activityType = session.workoutConfiguration.activityType
        title = session.workoutConfiguration.activityType.name
        stateText = "Live on Apple Watch"
        startedAt = Date()
        startElapsedTimer()
        isWorkoutActive = true
        isVisible = true

        if #available(iOS 26.0, *) {
            let builder = session.associatedWorkoutBuilder()
            self.builder = builder
            builder.delegate = self
            rebuildMetrics()
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func rebuildMetrics() {
        guard let builder else { return }
        var updated: [LiveMetric] = []

        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let heartStats = builder.statistics(for: heartRateType),
           let current = heartStats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            updated.append(.init(id: "hr", title: "Heart Rate", value: "\(Int(current.rounded())) bpm", symbol: "heart.fill", tint: .red))
        }

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let energy = builder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
            updated.append(.init(id: "energy", title: "Energy", value: "\(Int(energy.rounded())) kcal", symbol: "flame.fill", tint: .orange))
        }

        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        if let distanceType = distanceTypes.compactMap(HKQuantityType.quantityType(forIdentifier:)).first(where: { builder.statistics(for: $0) != nil }),
           let distance = builder.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) {
            let label = distance >= 1000 ? String(format: "%.2f km", distance / 1000) : "\(Int(distance.rounded())) m"
            updated.append(.init(id: "distance", title: "Distance", value: label, symbol: "location.fill", tint: .green))
        }

        if let powerType = [HKQuantityTypeIdentifier.cyclingPower, .runningPower]
            .compactMap(HKQuantityType.quantityType(forIdentifier:))
            .first(where: { builder.statistics(for: $0) != nil }),
           let power = builder.statistics(for: powerType)?.mostRecentQuantity()?.doubleValue(for: .watt()) {
            updated.append(.init(id: "power", title: "Power", value: "\(Int(power.rounded())) W", symbol: "bolt.fill", tint: .yellow))
        }

        if let speedType = [HKQuantityTypeIdentifier.runningSpeed, .walkingSpeed]
            .compactMap(HKQuantityType.quantityType(forIdentifier:))
            .first(where: { builder.statistics(for: $0) != nil }),
           let speed = builder.statistics(for: speedType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())) {
            updated.append(.init(id: "speed", title: "Speed", value: String(format: "%.1f km/h", speed * 3.6), symbol: "speedometer", tint: .cyan))
        }

        if let cadenceType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence),
           let cadence = builder.statistics(for: cadenceType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            updated.append(.init(id: "cadence", title: "Cadence", value: "\(Int(cadence.rounded())) rpm", symbol: "metronome.fill", tint: .mint))
        }

        metrics = updated
    }

    private func applyRemoteSnapshot(_ payload: MirroredWorkoutSnapshotPayload) {
        title = payload.title
        stateText = payload.stateText
        activityType = HKWorkoutActivityType(rawValue: payload.activityRawValue) ?? .running
        elapsedTime = payload.elapsedTime
        startedAt = Date().addingTimeInterval(-payload.elapsedTime)
        metrics = payload.metrics.map {
            LiveMetric(
                id: $0.id,
                title: $0.title,
                value: $0.valueText,
                symbol: $0.symbol,
                tint: companionTintColor(named: $0.tintName)
            )
        }
        pageKinds = payload.pageKinds.compactMap(CompanionWorkoutPageKind.init(rawValue:))
        speedHistory = payload.speedHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) }
        paceHistory = payload.paceHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) }
        powerHistory = payload.powerHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) }
        elevationHistory = payload.elevationHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) }
        cadenceHistory = payload.cadenceHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) }
        heartRateHistory = payload.heartRateHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) }
        splits = payload.splits.map {
            .init(
                index: $0.index,
                elapsedTime: $0.elapsedTime,
                splitDuration: $0.splitDuration,
                splitDistanceMeters: $0.splitDistanceMeters,
                averageHeartRate: $0.averageHeartRate,
                averageSpeedMetersPerSecond: $0.averageSpeedMetersPerSecond,
                averagePowerWatts: $0.averagePowerWatts,
                averageCadence: $0.averageCadence
            )
        }
        heartRateZoneDurations = payload.heartRateZoneDurations
        powerZoneDurations = payload.powerZoneDurations
        totalDistanceMeters = payload.totalDistanceMeters
        currentHeartRate = payload.currentHeartRate
        averageHeartRate = payload.averageHeartRate
        currentSpeedMetersPerSecond = payload.currentSpeedMetersPerSecond
        currentPowerWatts = payload.currentPowerWatts
        averagePowerWatts = payload.averagePowerWatts
        currentCadence = payload.currentCadence
        currentElevationFeet = payload.currentElevationFeet
        elevationGainFeet = payload.elevationGainFeet
        pacerTarget = payload.pacerTarget.map {
            CompanionWorkoutPacerTarget(lowerBound: $0.lowerBound, upperBound: $0.upperBound, unitLabel: $0.unitLabel)
        }
        isWorkoutActive = payload.stateText != "Ended"
        isVisible = true
    }

    func primePresentationFromWatchRequest() {
        activateIfNeeded()
        isWorkoutActive = true
        if !isVisible {
            title = "Watch Workout"
            stateText = mirroredSession == nil ? "Connecting..." : stateText
            isVisible = true
        }
    }

    func dismissLiveView() {
        guard isWorkoutActive else { return }
        isVisible = false
    }

    func reopenLiveView() {
        guard isWorkoutActive else { return }
        isVisible = true
    }

    func sendControl(_ command: WorkoutControlCommand) {
#if canImport(WatchConnectivity)
        activateIfNeeded()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        guard session.activationState == .activated else {
            session.activate()
            return
        }

        let payload: [String: Any] = ["workoutControl": command.rawValue]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
#endif
    }

    fileprivate func finishSession() {
        stopElapsedTimer()
        isWorkoutActive = false
        stateText = "Ended"
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            self.isVisible = false
            self.metrics = []
            self.pageKinds = [.metricsPrimary, .heartRateZones, .map]
            self.speedHistory = []
            self.paceHistory = []
            self.powerHistory = []
            self.elevationHistory = []
            self.cadenceHistory = []
            self.heartRateHistory = []
            self.splits = []
            self.heartRateZoneDurations = Array(repeating: 0, count: 5)
            self.powerZoneDurations = Array(repeating: 0, count: 5)
            self.totalDistanceMeters = 0
            self.currentHeartRate = nil
            self.averageHeartRate = nil
            self.currentSpeedMetersPerSecond = nil
            self.currentPowerWatts = nil
            self.averagePowerWatts = nil
            self.currentCadence = nil
            self.currentElevationFeet = 0
            self.elevationGainFeet = 0
            self.pacerTarget = nil
            self.builder = nil
            self.mirroredSession = nil
            self.startedAt = nil
            self.elapsedTime = 0
            self.isWorkoutActive = false
        }
    }
}

extension CompanionWorkoutLiveManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                stateText = "Running"
                if startedAt == nil {
                    startedAt = date
                }
            case .paused:
                stateText = "Paused"
            case .ended:
                finishSession()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            stateText = "Unavailable"
            finishSession()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for packet in data {
                guard let payload = try? JSONDecoder().decode(MirroredWorkoutSnapshotPayload.self, from: packet) else {
                    continue
                }
                applyRemoteSnapshot(payload)
            }
        }
    }
}

extension CompanionWorkoutLiveManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            rebuildMetrics()
        }
    }
}

private struct CompanionWorkoutLiveOverlay: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    @State private var selectedPage: CompanionWorkoutPageKind = .metricsPrimary
    @State private var controlsExpanded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.title)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text(manager.stateText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        manager.dismissLiveView()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Text(companionElapsedString(manager.elapsedTime))
                        .font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit())
                }

                TabView(selection: $selectedPage) {
                    ForEach(manager.pageKinds) { page in
                        CompanionWorkoutPageView(manager: manager, page: page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, controlsExpanded ? 208 : 112)

            CompanionWorkoutControlsDrawer(
                manager: manager,
                isExpanded: $controlsExpanded
            )
        }
        .onAppear {
            selectedPage = manager.pageKinds.first ?? .metricsPrimary
        }
        .onChange(of: manager.pageKinds) { _, newValue in
            guard let first = newValue.first else { return }
            if !newValue.contains(selectedPage) {
                selectedPage = first
            }
        }
    }
}

private struct CompanionWorkoutControlsDrawer: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    @Binding var isExpanded: Bool

    private var primaryControlLabel: String {
        manager.stateText == "Paused" ? "Resume" : "Pause"
    }

    private var primaryControlSymbol: String {
        manager.stateText == "Paused" ? "play.fill" : "pause.fill"
    }

    private var primaryControlCommand: CompanionWorkoutLiveManager.WorkoutControlCommand {
        manager.stateText == "Paused" ? .resume : .pause
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                } label: {
                    VStack(spacing: 8) {
                        Capsule()
                            .fill(Color.white.opacity(0.34))
                            .frame(width: 48, height: 6)
                        Text(isExpanded ? "Hide Controls" : "Workout Controls")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        CompanionWorkoutControlButton(symbol: primaryControlSymbol, title: primaryControlLabel, tint: .yellow) {
                            manager.sendControl(primaryControlCommand)
                        }
                        CompanionWorkoutControlButton(symbol: "flag.checkered", title: "Split", tint: .blue) {
                            manager.sendControl(.split)
                        }
                        CompanionWorkoutControlButton(symbol: "plus.circle.fill", title: "New", tint: .orange) {
                            manager.sendControl(.newWorkout)
                        }
                        CompanionWorkoutControlButton(symbol: "stop.fill", title: "Stop", tint: .red) {
                            manager.sendControl(.stop)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct CompanionWorkoutControlButton: View {
    let symbol: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CompanionWorkoutReentryButton: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager

    var body: some View {
        Button {
            manager.reopenLiveView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Open Live Workout")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(companionElapsedString(manager.elapsedTime))
                    .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.86), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CompanionWorkoutPageView: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    let page: CompanionWorkoutPageKind

    var body: some View {
        switch page {
        case .metricsPrimary:
            CompanionWorkoutMetricsPage(manager: manager, variant: .primary)
        case .metricsSecondary:
            CompanionWorkoutMetricsPage(manager: manager, variant: .secondary)
        case .heartRateZones:
            CompanionWorkoutZonesPage(manager: manager, power: false)
        case .segments:
            CompanionWorkoutGraphPage(
                manager: manager,
                title: manager.activityType == .cycling ? "POWER" : "SEGMENTS",
                accent: manager.activityType == .cycling ? .yellow : .cyan,
                points: manager.activityType == .cycling ? manager.powerHistory : manager.paceHistory,
                leadingValue: manager.activityType == .cycling
                    ? (manager.currentPowerWatts.map { "\(Int($0.rounded()))W" } ?? "--")
                    : companionPaceValue(speed: manager.currentSpeedMetersPerSecond),
                leadingLabel: manager.activityType == .cycling ? "CURRENT POWER" : "CURRENT PACE",
                trailingValue: manager.splits.last.map { companionElapsedString($0.splitDuration) } ?? companionElapsedString(manager.elapsedTime),
                trailingLabel: manager.splits.isEmpty ? "ELAPSED" : "LAST SEGMENT"
            )
        case .splits:
            CompanionWorkoutSplitsPage(manager: manager)
        case .elevationGraph:
            CompanionWorkoutGraphPage(
                manager: manager,
                title: "ELEVATION",
                accent: .green,
                points: manager.elevationHistory,
                leadingValue: "\(Int(manager.elevationGainFeet.rounded()))FT",
                leadingLabel: "ELEV GAIN",
                trailingValue: manager.currentSpeedMetersPerSecond.map { companionSpeedValue(metersPerSecond: $0) } ?? "--",
                trailingLabel: "CURRENT SPEED"
            )
        case .powerGraph:
            CompanionWorkoutGraphPage(
                manager: manager,
                title: "POWER",
                accent: .yellow,
                points: manager.powerHistory,
                leadingValue: manager.currentCadence.map { "\(Int($0.rounded()))RPM" } ?? "--",
                leadingLabel: "CADENCE",
                trailingValue: manager.averagePowerWatts.map { "\(Int($0.rounded()))W" } ?? "--",
                trailingLabel: "30 SEC AVG POWER"
            )
        case .powerZones:
            CompanionWorkoutZonesPage(manager: manager, power: true)
        case .pacer:
            CompanionWorkoutPacerPage(manager: manager)
        case .map:
            CompanionWorkoutMetricsPage(manager: manager, variant: .primary)
        }
    }
}

private struct CompanionWorkoutMetricsPage: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    let variant: WorkoutMetricsVariant

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(companionMetricLines(for: manager, variant: variant)) { line in
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(line.value)
                        .font(.system(size: 50, weight: .black, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.55)
                    Text(line.label)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CompanionWorkoutZonesPage: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    let power: Bool

    private var zoneDurations: [TimeInterval] {
        power ? manager.powerZoneDurations : manager.heartRateZoneDurations
    }

    private var currentZone: Int {
        if power {
            return manager.currentPowerWatts.map(companionPowerZoneIndex) ?? 0
        }
        return manager.currentHeartRate.map(companionHeartRateZoneIndex) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((power ? companionPowerZoneColor(index) : companionHeartZoneColor(index)).opacity(index == currentZone ? 1 : 0.35))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companionElapsedString(zoneDurations.indices.contains(currentZone) ? zoneDurations[currentZone] : 0))
                        .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                    Text(power ? "TIME IN POWER ZONE" : "TIME IN ZONE")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(power ? (manager.averagePowerWatts.map { "\(Int($0.rounded()))W" } ?? "--") : (manager.averageHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--"))
                        .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                    Text(power ? "AVERAGE POWER" : "AVERAGE HR")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct CompanionWorkoutGraphPage: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    let title: String
    let accent: Color
    let points: [CompanionWorkoutSeriesPoint]
    let leadingValue: String
    let leadingLabel: String
    let trailingValue: String
    let trailingLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(accent)

            CompanionWorkoutSparkline(points: points, accent: accent)
                .frame(height: 120)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(leadingValue)
                        .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                    Text(leadingLabel)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(trailingValue)
                        .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                    Text(trailingLabel)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct CompanionWorkoutSplitsPage: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager

    private var latestSplitElapsed: TimeInterval {
        manager.splits.last?.elapsedTime ?? 0
    }

    private var currentSplitDuration: TimeInterval {
        max(manager.elapsedTime - latestSplitElapsed, 0)
    }

    private var distanceBeforeCurrentSplit: Double {
        manager.splits.reduce(0) { $0 + $1.splitDistanceMeters }
    }

    private var currentSplitDistance: Double {
        max(manager.totalDistanceMeters - distanceBeforeCurrentSplit, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(companionElapsedString(manager.elapsedTime))
                .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.yellow)

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companionElapsedString(currentSplitDuration))
                        .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    Text("CURRENT SPLIT")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(companionSplitSpeedValue(manager: manager, splitDistanceMeters: currentSplitDistance, splitDuration: currentSplitDuration))
                        .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    Text("SPLIT SPEED / PACE")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companionDistanceValue(distanceMeters: currentSplitDistance, activityType: manager.activityType))
                        .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    Text("SPLIT DIST")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.currentHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--")
                        .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    Text("HR")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct CompanionWorkoutPacerPage: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(companionElapsedString(manager.elapsedTime))
                .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.yellow)

            if let target = manager.pacerTarget {
                CompanionWorkoutPacerBar(
                    progress: companionPacerProgress(manager: manager, target: target),
                    inTarget: companionPacerInRange(manager: manager, target: target)
                )
                .frame(height: 34)

                Text(companionAveragePacerValue(manager: manager, target: target))
                    .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.mint)
                Text("AVERAGE \(target.unitLabel)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.mint.opacity(0.85))

                Text(companionCurrentPacerValue(manager: manager, target: target))
                    .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("CURRENT \(target.unitLabel)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(companionDistanceValue(distanceMeters: manager.totalDistanceMeters, activityType: manager.activityType))
                .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())

            Spacer()
        }
    }
}

private struct CompanionWorkoutSparkline: View {
    let points: [CompanionWorkoutSeriesPoint]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = max(values.max() ?? 1, minValue + 1)

            ZStack(alignment: .bottomTrailing) {
                Path { path in
                    guard let first = points.first else { return }
                    for (index, point) in points.enumerated() {
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                        let ratio = (point.value - minValue) / max(maxValue - minValue, 0.001)
                        let y = proxy.size.height - proxy.size.height * CGFloat(min(max(ratio, 0), 1))
                        if point.elapsedTime == first.elapsedTime {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                VStack(alignment: .trailing, spacing: 0) {
                    Text(companionAxisLabel(maxValue))
                    Spacer()
                    Text(companionAxisLabel(minValue))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompanionWorkoutPacerBar: View {
    let progress: Double
    let inTarget: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let markerX = width * CGFloat(min(max(progress, 0), 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.65))
                    .frame(height: 26)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.72))
                    .frame(width: width * 0.48, height: 26)
                    .offset(x: width * 0.26)
                Capsule()
                    .fill(inTarget ? Color.green : Color.mint)
                    .frame(width: 64, height: 34)
                    .offset(x: max(0, min(width - 64, markerX - 32)))
            }
        }
    }
}

private func companionElapsedString(_ elapsed: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = elapsed >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: elapsed) ?? "00:00"
}

private func companionTintColor(named name: String) -> Color {
    switch name {
    case "red":
        return .red
    case "orange":
        return .orange
    case "green":
        return .green
    case "cyan":
        return .cyan
    case "yellow":
        return .yellow
    case "mint":
        return .mint
    case "indigo":
        return .indigo
    case "brown":
        return .brown
    case "purple":
        return .purple
    case "teal":
        return .teal
    case "blue":
        return .blue
    default:
        return .white
    }
}

private struct CompanionMetricLine: Identifiable {
    let id: String
    let value: String
    let label: String
}

@MainActor
private func companionMetricLines(for manager: CompanionWorkoutLiveManager, variant: WorkoutMetricsVariant) -> [CompanionMetricLine] {
    let distanceMiles = manager.totalDistanceMeters / 1609.344
    let avgSpeed = manager.totalDistanceMeters / max(manager.elapsedTime, 1)
    switch variant {
    case .primary:
        switch manager.activityType {
        case .cycling:
            return [
                .init(id: "speed", value: companionSpeedValue(metersPerSecond: avgSpeed), label: "AVERAGE SPEED"),
                .init(id: "elev", value: "\(Int(manager.elevationGainFeet.rounded()))FT", label: "ELEVATION GAINED"),
                .init(id: "distance", value: companionDistanceValue(distanceMeters: manager.totalDistanceMeters, activityType: manager.activityType), label: "")
            ]
        default:
            return [
                .init(id: "time", value: companionElapsedString(manager.elapsedTime), label: ""),
                .init(id: "pace", value: companionPaceValue(speed: manager.currentSpeedMetersPerSecond == nil ? nil : avgSpeed), label: "AVERAGE PACE"),
                .init(id: "distance", value: companionDistanceValue(distanceMeters: manager.totalDistanceMeters, activityType: manager.activityType), label: "")
            ]
        }
    case .secondary:
        switch manager.activityType {
        case .cycling:
            return [
                .init(id: "power", value: manager.currentPowerWatts.map { "\(Int($0.rounded()))W" } ?? "--", label: "POWER"),
                .init(id: "cadence", value: manager.currentCadence.map { "\(Int($0.rounded()))RPM" } ?? "--", label: "CADENCE"),
                .init(id: "speed", value: companionSpeedValue(metersPerSecond: manager.currentSpeedMetersPerSecond), label: "CURRENT SPEED")
            ]
        default:
            return [
                .init(id: "cadence", value: manager.currentCadence.map { "\(Int($0.rounded()))" } ?? "--", label: "CADENCE"),
                .init(id: "pace", value: companionPaceValue(speed: manager.currentSpeedMetersPerSecond), label: "CURRENT PACE"),
                .init(id: "hr", value: manager.currentHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--", label: "HEART RATE")
            ]
        }
    }
}

@MainActor
private func companionSpeedValue(metersPerSecond: Double?) -> String {
    guard let metersPerSecond, metersPerSecond > 0 else { return "--" }
    return String(format: "%.1fMPH", metersPerSecond * 2.23694)
}

@MainActor
private func companionPaceValue(speed: Double?) -> String {
    guard let speed, speed > 0 else { return "--" }
    let secondsPerMile = 1609.344 / speed
    let minutes = Int(secondsPerMile) / 60
    let seconds = Int(secondsPerMile) % 60
    return String(format: "%d'%02d''", minutes, seconds)
}

@MainActor
private func companionDistanceValue(distanceMeters: Double, activityType: HKWorkoutActivityType) -> String {
    if activityType == .swimming {
        return "\(Int(distanceMeters.rounded()))M"
    }
    return String(format: "%.2fMI", distanceMeters / 1609.344)
}

@MainActor
private func companionAxisLabel(_ value: Double) -> String {
    value >= 10 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
}

@MainActor
private func companionSplitSpeedValue(manager: CompanionWorkoutLiveManager, splitDistanceMeters: Double, splitDuration: TimeInterval) -> String {
    switch manager.activityType {
    case .cycling:
        return companionSpeedValue(metersPerSecond: splitDistanceMeters / max(splitDuration, 1))
    case .swimming:
        return companionSwimPace(distanceMeters: splitDistanceMeters, duration: splitDuration)
    default:
        let pace = splitDistanceMeters > 0 ? splitDuration / (splitDistanceMeters / 1609.344) : 0
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return pace > 0 ? String(format: "%d'%02d''", minutes, seconds) : "--"
    }
}

@MainActor
private func companionSwimPace(distanceMeters: Double, duration: TimeInterval) -> String {
    guard distanceMeters > 0, duration > 0 else { return "--" }
    let seconds = duration / (distanceMeters / 100)
    let minutes = Int(seconds) / 60
    let remainder = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, remainder)
}

@MainActor
private func companionPacerProgress(manager: CompanionWorkoutLiveManager, target: CompanionWorkoutPacerTarget) -> Double {
    let currentValue: Double
    switch target.unitLabel {
    case "PACE":
        currentValue = {
            guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else { return 0 }
            return 1609.344 / speed
        }()
    case "/100M":
        currentValue = {
            guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else { return 0 }
            return 100 / speed
        }()
    default:
        currentValue = (manager.currentSpeedMetersPerSecond ?? 0) * 2.23694
    }
    let span = max(target.upperBound - target.lowerBound, 0.001)
    return (currentValue - (target.lowerBound - span)) / (span * 3)
}

@MainActor
private func companionPacerInRange(manager: CompanionWorkoutLiveManager, target: CompanionWorkoutPacerTarget) -> Bool {
    let currentValue: Double
    switch target.unitLabel {
    case "PACE":
        guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else { return false }
        currentValue = 1609.344 / speed
    case "/100M":
        guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else { return false }
        currentValue = 100 / speed
    default:
        currentValue = (manager.currentSpeedMetersPerSecond ?? 0) * 2.23694
    }
    return currentValue >= target.lowerBound && currentValue <= target.upperBound
}

@MainActor
private func companionAveragePacerValue(manager: CompanionWorkoutLiveManager, target: CompanionWorkoutPacerTarget) -> String {
    switch target.unitLabel {
    case "PACE":
        let miles = manager.totalDistanceMeters / 1609.344
        return miles > 0 ? companionPaceFromSeconds(manager.elapsedTime / miles) : "--"
    case "/100M":
        return companionSwimPace(distanceMeters: manager.totalDistanceMeters, duration: manager.elapsedTime)
    default:
        let avgSpeed = manager.totalDistanceMeters / max(manager.elapsedTime, 1)
        return companionSpeedValue(metersPerSecond: avgSpeed)
    }
}

@MainActor
private func companionCurrentPacerValue(manager: CompanionWorkoutLiveManager, target: CompanionWorkoutPacerTarget) -> String {
    switch target.unitLabel {
    case "PACE":
        return companionPaceValue(speed: manager.currentSpeedMetersPerSecond)
    case "/100M":
        return companionSwimPace(distanceMeters: 100, duration: manager.currentSpeedMetersPerSecond.map { 100 / max($0, 0.001) } ?? 0)
    default:
        return companionSpeedValue(metersPerSecond: manager.currentSpeedMetersPerSecond)
    }
}

@MainActor
private func companionPaceFromSeconds(_ secondsPerMile: Double) -> String {
    guard secondsPerMile > 0 else { return "--" }
    let minutes = Int(secondsPerMile) / 60
    let seconds = Int(secondsPerMile) % 60
    return String(format: "%d'%02d''", minutes, seconds)
}

@MainActor
private func companionHeartZoneColor(_ index: Int) -> Color {
    switch index {
    case 0: return Color(red: 0.13, green: 0.31, blue: 0.55)
    case 1: return Color(red: 0.12, green: 0.43, blue: 0.39)
    case 2: return Color(red: 0.39, green: 0.54, blue: 0.05)
    case 3: return Color(red: 0.63, green: 0.35, blue: 0.05)
    default: return Color(red: 0.49, green: 0.03, blue: 0.24)
    }
}

@MainActor
private func companionPowerZoneColor(_ index: Int) -> Color {
    companionHeartZoneColor(index)
}

@MainActor
private func companionHeartRateZoneIndex(_ heartRate: Double) -> Int {
    let ratio = heartRate / 190
    switch ratio {
    case ..<0.60: return 0
    case ..<0.70: return 1
    case ..<0.80: return 2
    case ..<0.90: return 3
    default: return 4
    }
}

@MainActor
private func companionPowerZoneIndex(_ power: Double) -> Int {
    let ratio = power / 240
    switch ratio {
    case ..<0.60: return 0
    case ..<0.75: return 1
    case ..<0.90: return 2
    case ..<1.05: return 3
    default: return 4
    }
}
