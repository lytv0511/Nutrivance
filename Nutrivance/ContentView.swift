import SwiftUI
import CoreLocation
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

private enum CompanionWorkoutSource {
    case appleWatch
    case thisDevice
}

private struct CompanionPersistedWorkoutStep: Codable {
    let id: UUID
    let title: String
    let notes: String
    let plannedMinutes: Int
    let repeats: Int
    let objectiveStatusText: String
    let isObjectiveComplete: Bool
}

private struct CompanionPersistedWorkoutPhase: Codable {
    let id: UUID
    let title: String
    let subtitle: String
    let activityRawValue: UInt
    let locationRawValue: Int
    let plannedMinutes: Int
    let objectiveStatusText: String
    let isObjectiveComplete: Bool
}

private struct CompanionPersistedWorkoutSession: Codable {
    private enum CodingKeys: String, CodingKey {
        case sourceRawValue
        case title
        case stateText
        case elapsedTime
        case pausedElapsedTime
        case isPaused
        case startedAt
        case activityRawValue
        case localWorkoutTitle
        case localWorkoutSubtitle
        case phaseQueue
        case currentPhaseIndex
        case stepQueue
        case currentMicroStageIndex
    }

    let sourceRawValue: String
    let title: String
    let stateText: String
    let elapsedTime: TimeInterval
    let pausedElapsedTime: TimeInterval?
    let isPaused: Bool?
    let startedAt: Date?
    let activityRawValue: UInt
    let localWorkoutTitle: String
    let localWorkoutSubtitle: String
    let phaseQueue: [CompanionPersistedWorkoutPhase]
    let currentPhaseIndex: Int
    let stepQueue: [CompanionPersistedWorkoutStep]
    let currentMicroStageIndex: Int

    init(
        sourceRawValue: String,
        title: String,
        stateText: String,
        elapsedTime: TimeInterval,
        pausedElapsedTime: TimeInterval? = nil,
        isPaused: Bool? = nil,
        startedAt: Date?,
        activityRawValue: UInt,
        localWorkoutTitle: String,
        localWorkoutSubtitle: String,
        phaseQueue: [CompanionPersistedWorkoutPhase],
        currentPhaseIndex: Int,
        stepQueue: [CompanionPersistedWorkoutStep],
        currentMicroStageIndex: Int
    ) {
        self.sourceRawValue = sourceRawValue
        self.title = title
        self.stateText = stateText
        self.elapsedTime = elapsedTime
        self.pausedElapsedTime = pausedElapsedTime
        self.isPaused = isPaused
        self.startedAt = startedAt
        self.activityRawValue = activityRawValue
        self.localWorkoutTitle = localWorkoutTitle
        self.localWorkoutSubtitle = localWorkoutSubtitle
        self.phaseQueue = phaseQueue
        self.currentPhaseIndex = currentPhaseIndex
        self.stepQueue = stepQueue
        self.currentMicroStageIndex = currentMicroStageIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceRawValue = try container.decode(String.self, forKey: .sourceRawValue)
        title = try container.decode(String.self, forKey: .title)
        stateText = try container.decode(String.self, forKey: .stateText)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        pausedElapsedTime = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedElapsedTime)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        activityRawValue = try container.decode(UInt.self, forKey: .activityRawValue)
        localWorkoutTitle = try container.decode(String.self, forKey: .localWorkoutTitle)
        localWorkoutSubtitle = try container.decode(String.self, forKey: .localWorkoutSubtitle)
        phaseQueue = try container.decode([CompanionPersistedWorkoutPhase].self, forKey: .phaseQueue)
        currentPhaseIndex = try container.decode(Int.self, forKey: .currentPhaseIndex)
        stepQueue = try container.decode([CompanionPersistedWorkoutStep].self, forKey: .stepQueue)
        currentMicroStageIndex = try container.decode(Int.self, forKey: .currentMicroStageIndex)
    }
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
        case nextPhase
    }

    enum QueueInsertionPlacement: String {
        case next
        case afterPlan
    }

    struct InjectableWorkout: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let activity: HKWorkoutActivityType
        let location: HKWorkoutSessionLocationType
        let plannedMinutes: Int
    }

    private enum SessionStateText {
        static let watchConnecting = "Connecting to Apple Watch..."
        static let watchLive = "Live on Apple Watch"
        static let phoneRunning = "Running on iPhone"
        static let phonePaused = "Paused on iPhone"
        static let ended = "Ended"
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
        let phaseQueue: [MirroredPhasePayload]
        let currentPhaseIndex: Int
        let stepQueue: [MirroredStepPayload]
        let currentMicroStageIndex: Int
        let effortPrompt: MirroredEffortPromptPayload?
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

    private struct MirroredPhasePayload: Codable {
        let id: UUID
        let title: String
        let subtitle: String
        let activityRawValue: UInt
        let locationRawValue: Int
        let plannedMinutes: Int
        let objectiveStatusText: String
        let isObjectiveComplete: Bool
    }

    private struct MirroredStepPayload: Codable {
        let id: UUID
        let title: String
        let notes: String
        let plannedMinutes: Int
        let repeats: Int
        let objectiveStatusText: String
        let isObjectiveComplete: Bool
    }

    private struct MirroredEffortPromptPayload: Codable {
        let phaseID: UUID
        let title: String
        let subtitle: String
    }

    struct WorkoutPhase: Identifiable, Hashable {
        let id: UUID
        let title: String
        let subtitle: String
        let activityRawValue: UInt
        let locationRawValue: Int
        let plannedMinutes: Int
        let objectiveStatusText: String
        let isObjectiveComplete: Bool
    }

    struct WorkoutStep: Identifiable, Hashable {
        let id: UUID
        let title: String
        let notes: String
        let plannedMinutes: Int
        let repeats: Int
        let objectiveStatusText: String
        let isObjectiveComplete: Bool
    }

    struct EffortPromptPhase: Identifiable, Hashable {
        let phaseID: UUID
        let title: String
        let subtitle: String

        var id: UUID { phaseID }
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
    @Published private(set) var phaseQueue: [WorkoutPhase] = []
    @Published private(set) var currentPhaseIndex = 0
    @Published private(set) var stepQueue: [WorkoutStep] = []
    @Published private(set) var currentMicroStageIndex = 0
    @Published private(set) var pendingEffortPrompt: EffortPromptPhase?
    private var source: CompanionWorkoutSource = .appleWatch
    @Published private(set) var launchStatusMessage: String?
    private var shouldAutoPresentLiveView = true

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var mirroredSession: HKWorkoutSession?
    private var localSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var pausedElapsedTime: TimeInterval = 0
    private var elapsedTimer: Timer?
    private var lastSnapshotElapsedTime: TimeInterval = 0
    private var hasActivated = false
    private var persistedSource: CompanionWorkoutSource = .appleWatch
    private var authorizationRequestInFlight = false
    private var locationAuthorizationContinuation: CheckedContinuation<Bool, Never>?
    private var lastLocation: CLLocation?
    private var localWorkoutTitle = "Workout"
    private var localWorkoutSubtitle = ""
    private var pendingLocalEndAction: WorkoutControlCommand?
    private let persistenceKey = "companion_live_workout_session_v2"

    private enum CompanionLifecycleKeys {
        static let workoutLifecycle = "workoutLifecycle"
        static let state = "state"
        static let reason = "reason"
        static let effortScore = "effortScore"
        static let injectedPlacement = "injectedPlacement"
        static let injectedTitle = "injectedTitle"
        static let injectedSubtitle = "injectedSubtitle"
        static let injectedActivityRawValue = "injectedActivityRawValue"
        static let injectedLocationRawValue = "injectedLocationRawValue"
        static let injectedPlannedMinutes = "injectedPlannedMinutes"
    }

    static let injectableWorkouts: [InjectableWorkout] = [
        .init(id: "run", title: "Outdoor Run", subtitle: "Injected • Run", symbol: "figure.run", activity: .running, location: .outdoor, plannedMinutes: 30),
        .init(id: "walk", title: "Outdoor Walk", subtitle: "Injected • Walk", symbol: "figure.walk", activity: .walking, location: .outdoor, plannedMinutes: 30),
        .init(id: "cycle", title: "Cycling", subtitle: "Injected • Cycling", symbol: "bicycle", activity: .cycling, location: .outdoor, plannedMinutes: 30),
        .init(id: "yoga", title: "Yoga", subtitle: "Injected • Yoga", symbol: "figure.mind.and.body", activity: .yoga, location: .indoor, plannedMinutes: 20),
        .init(id: "strength", title: "Strength", subtitle: "Injected • Strength", symbol: "dumbbell.fill", activity: .traditionalStrengthTraining, location: .indoor, plannedMinutes: 30),
        .init(id: "hike", title: "Hike", subtitle: "Injected • Hike", symbol: "figure.hiking", activity: .hiking, location: .outdoor, plannedMinutes: 45)
    ]

    var canReopenLiveView: Bool {
        isWorkoutActive && !isVisible
    }

    var isPaused: Bool {
        stateText.localizedCaseInsensitiveContains("paused")
    }

    var currentPhaseRemainingTime: TimeInterval? {
        if stepQueue.indices.contains(currentMicroStageIndex) {
            return max(TimeInterval(stepQueue[currentMicroStageIndex].plannedMinutes * 60) - elapsedTime, 0)
        }
        guard phaseQueue.indices.contains(currentPhaseIndex) else { return nil }
        return max(TimeInterval(phaseQueue[currentPhaseIndex].plannedMinutes * 60) - elapsedTime, 0)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func activateIfNeeded() {
        guard hasActivated == false else { return }
        hasActivated = true
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attachMirroredSession(session)
            }
        }
        restorePersistedSessionIfNeeded()
        if #available(iOS 26.0, *) {
            Task { @MainActor [weak self] in
                await self?.recoverActiveWorkoutSessionIfNeeded()
            }
        }
#if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if session.activationState != .activated {
                session.activate()
            }
        }
#endif
    }

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        resetForNewSession()
        mirroredSession = session
        localSession = nil
        session.delegate = self
        activityType = session.workoutConfiguration.activityType
        title = session.workoutConfiguration.activityType.name
        stateText = SessionStateText.watchLive
        source = .appleWatch
        launchStatusMessage = nil
        startedAt = Date()
        startElapsedTimer()
        isWorkoutActive = true
        shouldAutoPresentLiveView = true
        isVisible = true
        print("[Companion] Attached mirrored session from watch, activity: \(activityType.name)")

        if #available(iOS 26.0, *) {
            let builder = session.associatedWorkoutBuilder()
            self.builder = builder
            builder.delegate = self
            print("[Companion] Associated workout builder attached")
            rebuildMetrics()
        }
        persistCurrentSession()
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPaused {
                    self.elapsedTime = self.pausedElapsedTime
                } else if let startedAt = self.startedAt {
                    self.elapsedTime = self.pausedElapsedTime + Date().timeIntervalSince(startedAt)
                }
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
            currentHeartRate = current
            averageHeartRate = heartStats.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            updated.append(.init(id: "hr", title: "Heart Rate", value: "\(Int(current.rounded())) bpm", symbol: "heart.fill", tint: .red))
        }

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let energy = builder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
            updated.append(.init(id: "energy", title: "Energy", value: "\(Int(energy.rounded())) kcal", symbol: "flame.fill", tint: .orange))
        }

        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        if let distanceType = distanceTypes.compactMap(HKQuantityType.quantityType(forIdentifier:)).first(where: { builder.statistics(for: $0) != nil }),
           let distance = builder.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) {
            totalDistanceMeters = max(totalDistanceMeters, distance)
            let label = distance >= 1000 ? String(format: "%.2f km", distance / 1000) : "\(Int(distance.rounded())) m"
            updated.append(.init(id: "distance", title: "Distance", value: label, symbol: "location.fill", tint: .green))
        } else if totalDistanceMeters > 0 {
            let label = totalDistanceMeters >= 1000
                ? String(format: "%.2f km", totalDistanceMeters / 1000)
                : "\(Int(totalDistanceMeters.rounded())) m"
            updated.append(.init(id: "distance", title: "Distance", value: label, symbol: "location.fill", tint: .green))
        }

        if let powerType = [HKQuantityTypeIdentifier.cyclingPower, .runningPower]
            .compactMap(HKQuantityType.quantityType(forIdentifier:))
            .first(where: { builder.statistics(for: $0) != nil }),
           let power = builder.statistics(for: powerType)?.mostRecentQuantity()?.doubleValue(for: .watt()) {
            currentPowerWatts = power
            averagePowerWatts = builder.statistics(for: powerType)?.averageQuantity()?.doubleValue(for: .watt())
            updated.append(.init(id: "power", title: "Power", value: "\(Int(power.rounded())) W", symbol: "bolt.fill", tint: .yellow))
        }

        if let speedType = [HKQuantityTypeIdentifier.runningSpeed, .walkingSpeed]
            .compactMap(HKQuantityType.quantityType(forIdentifier:))
            .first(where: { builder.statistics(for: $0) != nil }),
           let speed = builder.statistics(for: speedType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())) {
            currentSpeedMetersPerSecond = speed
            updated.append(.init(id: "speed", title: "Speed", value: String(format: "%.1f km/h", speed * 3.6), symbol: "speedometer", tint: .cyan))
        } else if let speed = currentSpeedMetersPerSecond, speed > 0 {
            updated.append(.init(id: "speed", title: "Speed", value: String(format: "%.1f km/h", speed * 3.6), symbol: "speedometer", tint: .cyan))
        }

        if let cadenceType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence),
           let cadence = builder.statistics(for: cadenceType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            currentCadence = cadence
            updated.append(.init(id: "cadence", title: "Cadence", value: "\(Int(cadence.rounded())) rpm", symbol: "metronome.fill", tint: .mint))
        } else if let cadence = currentCadence {
            updated.append(.init(id: "cadence", title: "Cadence", value: "\(Int(cadence.rounded())) rpm", symbol: "metronome.fill", tint: .mint))
        }

        if source == .thisDevice && currentElevationFeet != 0 {
            updated.append(.init(id: "elevation", title: "Elevation", value: "\(Int(currentElevationFeet.rounded())) ft", symbol: "mountain.2.fill", tint: .green))
        }

        metrics = updated
    }

    private func applyRemoteSnapshot(_ payload: MirroredWorkoutSnapshotPayload) {
        let normalizedState = payload.stateText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["ended", "failed", "idle"].contains(normalizedState) {
            launchStatusMessage = normalizedState == "failed"
                ? "Apple Watch workout became unavailable."
                : "Apple Watch workout finished."
            finishSession()
            return
        }

        title = payload.title
        stateText = payload.stateText
        source = .appleWatch
        launchStatusMessage = nil
        activityType = HKWorkoutActivityType(rawValue: payload.activityRawValue) ?? .running
        
        // Sync elapsed time and state with watch
        lastSnapshotElapsedTime = payload.elapsedTime
        elapsedTime = payload.elapsedTime
        pausedElapsedTime = payload.elapsedTime
        
        if normalizedState == "paused" {
            startedAt = nil
            stopElapsedTimer()
        } else {
            startedAt = Date()
            startElapsedTimer()
        }
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
        phaseQueue = payload.phaseQueue.map {
            WorkoutPhase(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                activityRawValue: $0.activityRawValue,
                locationRawValue: $0.locationRawValue,
                plannedMinutes: $0.plannedMinutes,
                objectiveStatusText: $0.objectiveStatusText,
                isObjectiveComplete: $0.isObjectiveComplete
            )
        }
        currentPhaseIndex = payload.currentPhaseIndex
        stepQueue = payload.stepQueue.map {
            WorkoutStep(
                id: $0.id,
                title: $0.title,
                notes: $0.notes,
                plannedMinutes: $0.plannedMinutes,
                repeats: $0.repeats,
                objectiveStatusText: $0.objectiveStatusText,
                isObjectiveComplete: $0.isObjectiveComplete
            )
        }
        currentMicroStageIndex = payload.currentMicroStageIndex
        pendingEffortPrompt = payload.effortPrompt.map {
            EffortPromptPhase(phaseID: $0.phaseID, title: $0.title, subtitle: $0.subtitle)
        }
        isWorkoutActive = true
        if shouldAutoPresentLiveView {
            isVisible = true
        }
        persistCurrentSession()
    }

    private func handleWatchLifecycleState(_ state: String, reason: String?) {
        let normalizedState = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["ended", "failed", "idle"].contains(normalizedState) else { return }
        guard source == .appleWatch || mirroredSession != nil || isWorkoutActive else { return }

        switch normalizedState {
        case "failed":
            launchStatusMessage = reason?.isEmpty == false ? reason : "Apple Watch workout became unavailable."
        case "idle":
            launchStatusMessage = reason?.isEmpty == false ? reason : "Apple Watch workout cleared."
        default:
            launchStatusMessage = reason?.isEmpty == false ? reason : "Apple Watch workout finished."
        }
        finishSession()
    }

    func primePresentationFromWatchRequest() {
        activateIfNeeded()
        isWorkoutActive = true
        if !isVisible {
            title = "Watch Workout"
            stateText = mirroredSession == nil ? SessionStateText.watchConnecting : stateText
            source = .appleWatch
            shouldAutoPresentLiveView = true
            isVisible = true
        }
    }

    func startWorkoutOnThisDevice(
        title: String,
        subtitle: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType
    ) {
        Task {
            launchStatusMessage = nil
            guard await requestWorkoutAuthorization() else {
                launchStatusMessage = "Health permissions are required to start on iPhone."
                return
            }

            if location == .outdoor {
                guard await requestLocationAuthorizationIfNeeded() else {
                    launchStatusMessage = "Location permission is required for outdoor workout tracking."
                    return
                }
            }

            do {
                try beginLocalWorkout(title: title, subtitle: subtitle, activity: activity, location: location)
                launchStatusMessage = location == .outdoor
                    ? "Started on iPhone. GPS and connected HealthKit-compatible sensors will appear here."
                    : "Started on iPhone."
            } catch {
                launchStatusMessage = "Could not start the workout on iPhone."
            }
        }
    }

    func startWorkoutOnWatch(
        title: String,
        subtitle: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType,
        phases: [ProgramWorkoutPlanPhase] = [],
        routeName: String? = nil,
        trailheadCoordinate: CLLocationCoordinate2D? = nil,
        routeCoordinates: [CLLocationCoordinate2D] = []
    ) {
#if canImport(WatchConnectivity)
        activateIfNeeded()
        guard WCSession.isSupported() else {
            launchStatusMessage = "Apple Watch is unavailable on this device."
            return
        }

        let session = WCSession.default
        launchStatusMessage = "Starting on Apple Watch..."

        if session.activationState != .activated {
            session.activate()
        }

        // Build minimal payload first (for quick startup)
        var minimalPayload: [String: Any] = [
            "workoutStart": true,
            "title": title,
            "subtitle": subtitle,
            "activityRawValue": Int(activity.rawValue),
            "locationRawValue": location.rawValue
        ]
        
        // Build full payload (for queued delivery)
        var fullPayload: [String: Any] = minimalPayload
        
        // Add phase payloads if present
        if !phases.isEmpty {
            let phasePayloads = phases.map { phase in
                [
                    "id": phase.id.uuidString,
                    "title": phase.title,
                    "subtitle": phase.subtitle,
                    "activityID": phase.activityID,
                    "activityRawValue": Int(phase.activityRawValue),
                    "locationRawValue": phase.locationRawValue,
                    "plannedMinutes": phase.plannedMinutes,
                    "microStages": (phase.microStages ?? []).map { stage in
                        [
                            "id": stage.id.uuidString,
                            "title": stage.title,
                            "notes": stage.notes,
                            "role": stage.role.rawValue,
                            "goal": stage.goal.rawValue,
                            "targetBehavior": stage.targetBehavior.rawValue,
                            "plannedMinutes": stage.plannedMinutes,
                            "repeats": stage.repeats,
                            "targetValueText": stage.targetValueText,
                            "repeatSetLabel": stage.repeatSetLabel,
                            "circuitGroupID": stage.circuitGroupID?.uuidString as Any
                        ]
                    },
                    "circuitGroups": (phase.circuitGroups ?? []).map { group in
                        [
                            "id": group.id.uuidString,
                            "title": group.title,
                            "repeats": group.repeats
                        ]
                    }
                ]
            }
            fullPayload["phasePayloads"] = phasePayloads
        }
        
        if let routeName, !routeName.isEmpty {
            fullPayload["routeName"] = routeName
        }
        if let trailheadCoordinate {
            fullPayload["trailheadLatitude"] = trailheadCoordinate.latitude
            fullPayload["trailheadLongitude"] = trailheadCoordinate.longitude
        }
        if !routeCoordinates.isEmpty {
            fullPayload["routeCoordinates"] = routeCoordinates.map { [$0.latitude, $0.longitude] }
        }

        if session.isReachable {
            // Try sending full payload via direct message
            session.sendMessage(fullPayload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    if (reply["accepted"] as? Bool) == true {
                        self?.primePresentationFromWatchRequest()
                        self?.launchStatusMessage = "Apple Watch workout started."
                    } else {
                        self?.launchStatusMessage = "Apple Watch did not confirm the workout start."
                    }
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    // Fallback: send minimal payload via direct message for quick feedback
                    WCSession.default.sendMessage(minimalPayload, replyHandler: { reply in
                        Task { @MainActor in
                            if (reply["accepted"] as? Bool) == true {
                                self?.primePresentationFromWatchRequest()
                                self?.launchStatusMessage = "Apple Watch workout started."
                            } else {
                                // Queue full payload for later delivery
                                WCSession.default.transferUserInfo(fullPayload)
                                self?.launchStatusMessage = "Queuing workout details to send when reachable..."
                            }
                        }
                    }, errorHandler: { _ in
                        // Send both minimal and full payloads for background delivery
                        WCSession.default.transferUserInfo(minimalPayload)
                        WCSession.default.transferUserInfo(fullPayload)
                        self?.launchStatusMessage = "Queuing workout to send when reachable..."
                    })
                }
            })
        } else {
            // Watch not reachable: queue payloads
            session.transferUserInfo(minimalPayload)
            if !phases.isEmpty {
                session.transferUserInfo(fullPayload)
            }
            launchStatusMessage = "Queuing workout to send when reachable..."
        }
#else
        launchStatusMessage = "Watch connectivity is unavailable."
#endif
    }

    func dismissLiveView() {
        guard isWorkoutActive else { return }
        shouldAutoPresentLiveView = false
        isVisible = false
    }

    func reopenLiveView() {
        guard isWorkoutActive else { return }
        shouldAutoPresentLiveView = true
        isVisible = true
    }

    func sendControl(_ command: WorkoutControlCommand) {
        if source == .thisDevice {
            handleLocalControl(command)
            return
        }

#if canImport(WatchConnectivity)
        activateIfNeeded()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = ["workoutControl": command.rawValue]
        applyOptimisticWatchControlState(command)

        if session.activationState != .activated {
            print("[iPhone Companion] Control: Session not activated, activating...")
            session.activate()
        }

        print("[iPhone Companion] Sending control '\(command.rawValue)' to watch. Reachable: \(session.isReachable)")

        if session.isReachable {
            session.sendMessage(payload) { [weak self] reply in
                Task { @MainActor in
                    print("[iPhone Companion] Control message delivered, reply: \(reply)")
                    self?.launchStatusMessage = nil
                }
            } errorHandler: { [weak self] error in
                Task { @MainActor in
                    print("[iPhone Companion] Control message error: \(error.localizedDescription)")
                    self?.launchStatusMessage = "Watch control was queued and will sync when reachable."
                }
            }
        } else {
            print("[iPhone Companion] Watch not reachable for control, using background transfer")
            session.transferUserInfo(payload)
        }
#endif
    }

    func sendWorkoutToAppleWorkoutAppOnWatch(
        title: String,
        subtitle: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType,
        phases: [ProgramWorkoutPlanPhase]
    ) {
#if canImport(WatchConnectivity)
        activateIfNeeded()
        guard WCSession.isSupported() else {
            launchStatusMessage = "Apple Watch is unavailable on this device."
            return
        }

        let session = WCSession.default
        let phasePayloads: [[String: Any]] = phases.map { phase in
            [
                "id": phase.id.uuidString,
                "title": phase.title,
                "subtitle": phase.subtitle,
                "activityID": phase.activityID,
                "activityRawValue": Int(phase.activityRawValue),
                "locationRawValue": phase.locationRawValue,
                "plannedMinutes": phase.plannedMinutes,
                "microStages": (phase.microStages ?? []).map { stage in
                    [
                        "id": stage.id.uuidString,
                        "title": stage.title,
                        "notes": stage.notes,
                        "role": stage.role.rawValue,
                        "goal": stage.goal.rawValue,
                        "targetBehavior": stage.targetBehavior.rawValue,
                        "plannedMinutes": stage.plannedMinutes,
                        "repeats": stage.repeats,
                        "targetValueText": stage.targetValueText,
                        "repeatSetLabel": stage.repeatSetLabel,
                        "circuitGroupID": stage.circuitGroupID?.uuidString as Any
                    ]
                },
                "circuitGroups": (phase.circuitGroups ?? []).map { group in
                    [
                        "id": group.id.uuidString,
                        "title": group.title,
                        "repeats": group.repeats
                    ]
                }
            ]
        }
        let payload: [String: Any] = [
            "workoutStart": true,
            "openInWorkoutApp": true,
            "title": title,
            "subtitle": subtitle,
            "activityRawValue": Int(activity.rawValue),
            "locationRawValue": location.rawValue,
            "phasePayloads": phasePayloads
        ]

        launchStatusMessage = "Sending to Apple Workout on watch..."
        if session.activationState != .activated {
            session.activate()
        }

        if session.isReachable {
            session.sendMessage(payload) { [weak self] reply in
                Task { @MainActor in
                    self?.launchStatusMessage = (reply["accepted"] as? Bool) == true
                        ? "Apple Workout is opening on Apple Watch."
                        : "Apple Watch did not confirm the Workout app handoff."
                }
            } errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.launchStatusMessage = "Watch is not reachable. Open Nutrivance on Apple Watch to use Workout app handoff."
                }
            }
        } else {
            session.transferUserInfo(payload)
            launchStatusMessage = "Handoff queued for Apple Watch."
        }
#endif
    }

    func submitEffortScoreOnPhone(_ score: Int) {
#if canImport(WatchConnectivity)
        activateIfNeeded()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = [CompanionLifecycleKeys.effortScore: score]
        if session.activationState != .activated {
            session.activate()
        }
        pendingEffortPrompt = nil
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
#endif
    }

    func injectWorkout(_ workout: InjectableWorkout, placement: QueueInsertionPlacement) {
#if canImport(WatchConnectivity)
        activateIfNeeded()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = [
            CompanionLifecycleKeys.injectedPlacement: placement.rawValue,
            CompanionLifecycleKeys.injectedTitle: workout.title,
            CompanionLifecycleKeys.injectedSubtitle: workout.subtitle,
            CompanionLifecycleKeys.injectedActivityRawValue: Int(workout.activity.rawValue),
            CompanionLifecycleKeys.injectedLocationRawValue: workout.location.rawValue,
            CompanionLifecycleKeys.injectedPlannedMinutes: workout.plannedMinutes
        ]
        if session.activationState != .activated {
            session.activate()
        }
        launchStatusMessage = placement == .next
            ? "Queued \(workout.title) after the current stage."
            : "Queued \(workout.title) after the plan."
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
#endif
    }

    private func handleLocalControl(_ command: WorkoutControlCommand) {
        switch command {
        case .pause:
            guard let localSession else { return }
            stateText = SessionStateText.phonePaused
            pausedElapsedTime = elapsedTime
            startedAt = nil
            localSession.pause()
            stopElapsedTimer()
            persistCurrentSession()
        case .resume:
            guard let localSession else { return }
            startedAt = Date()
            stateText = SessionStateText.phoneRunning
            localSession.resume()
            startElapsedTimer()
            persistCurrentSession()
        case .split:
            appendSplit()
        case .stop:
            pendingLocalEndAction = .stop
            endLocalWorkout()
        case .newWorkout:
            pendingLocalEndAction = .newWorkout
            endLocalWorkout()
        case .nextPhase:
            launchStatusMessage = "Next phase switching is currently handled from the staged watch workflow."
        }
    }

    private func applyOptimisticWatchControlState(_ command: WorkoutControlCommand) {
        switch command {
        case .pause:
            stateText = "Paused"
        case .resume:
            stateText = "Running"
        case .split:
            launchStatusMessage = "Split sent to Apple Watch."
        case .stop:
            stateText = SessionStateText.ended
            launchStatusMessage = nil
            finishSession(immediate: true)
        case .newWorkout:
            launchStatusMessage = "Requested next workout on Apple Watch."
        case .nextPhase:
            launchStatusMessage = "Requested next phase on Apple Watch."
        }
    }

    private func requestWorkoutAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if authorizationRequestInFlight { return false }
        authorizationRequestInFlight = true
        defer { authorizationRequestInFlight = false }

        let readTypes: Set<HKObjectType> = Set([
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKQuantityType.quantityType(forIdentifier: .distanceCycling),
            HKQuantityType.quantityType(forIdentifier: .distanceSwimming),
            HKQuantityType.quantityType(forIdentifier: .runningSpeed),
            HKQuantityType.quantityType(forIdentifier: .walkingSpeed),
            HKQuantityType.quantityType(forIdentifier: .runningPower),
            HKQuantityType.quantityType(forIdentifier: .cyclingPower),
            HKQuantityType.quantityType(forIdentifier: .cyclingCadence),
            HKQuantityType.quantityType(forIdentifier: .flightsClimbed)
        ].compactMap { $0 })

        let shareTypes: Set<HKSampleType> = Set([
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ])

        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    private func requestLocationAuthorizationIfNeeded() async -> Bool {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .restricted, .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                locationAuthorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    private func beginLocalWorkout(
        title: String,
        subtitle: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType
    ) throws {
        resetForNewSession()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = location

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        localWorkoutTitle = title
        localWorkoutSubtitle = subtitle
        localSession = session
        mirroredSession = nil
        self.builder = builder
        self.title = title
        self.activityType = activity
        self.source = .thisDevice
        self.stateText = SessionStateText.phoneRunning
        self.pageKinds = localPageKinds(for: activity, location: location)
        self.isWorkoutActive = true
        self.shouldAutoPresentLiveView = true
        self.isVisible = true
        self.pendingLocalEndAction = nil

        session.delegate = self
        builder.delegate = self

        let startDate = Date()
        startedAt = startDate
        session.prepare()
        session.startActivity(with: startDate)
        startElapsedTimer()

        if location == .outdoor {
            lastLocation = nil
            locationManager.startUpdatingLocation()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await builder.beginCollection(at: startDate)
                self.rebuildMetrics()
                self.persistCurrentSession()
            } catch {
                self.launchStatusMessage = "Could not begin live workout collection."
                self.finishSession()
            }
        }
    }

    private func localPageKinds(for activity: HKWorkoutActivityType, location: HKWorkoutSessionLocationType) -> [CompanionWorkoutPageKind] {
        var pages: [CompanionWorkoutPageKind] = [.metricsPrimary, .heartRateZones, .segments, .splits]
        if activity == .cycling {
            pages.append(.powerGraph)
        }
        if location == .outdoor {
            pages.append(.map)
            pages.append(.elevationGraph)
        }
        return pages
    }

    private func appendSplit() {
        let splitElapsed = max(elapsedTime - (splits.last?.elapsedTime ?? 0), 0)
        let previousDistance = splits.reduce(0) { $0 + $1.splitDistanceMeters }
        let splitDistance = max(totalDistanceMeters - previousDistance, 0)
        let nextIndex = splits.count + 1

        splits.append(
            CompanionWorkoutSplit(
                index: nextIndex,
                elapsedTime: elapsedTime,
                splitDuration: splitElapsed,
                splitDistanceMeters: splitDistance,
                averageHeartRate: averageHeartRate,
                averageSpeedMetersPerSecond: currentSpeedMetersPerSecond,
                averagePowerWatts: averagePowerWatts ?? currentPowerWatts,
                averageCadence: currentCadence
            )
        )
    }

    private func appendHistoryPoint(_ value: Double?, to series: inout [CompanionWorkoutSeriesPoint], elapsedTime: TimeInterval) {
        guard let value, value.isFinite else { return }
        if let lastPoint = series.last, abs(lastPoint.elapsedTime - elapsedTime) < 10 {
            series[series.count - 1] = .init(elapsedTime: elapsedTime, value: value)
        } else {
            series.append(.init(elapsedTime: elapsedTime, value: value))
        }

        if series.count > 120 {
            series.removeFirst(series.count - 120)
        }
    }

    private func updateDerivedSeries() {
        let elapsed = max(elapsedTime, 1)
        appendHistoryPoint(currentHeartRate, to: &heartRateHistory, elapsedTime: elapsed)
        if let currentSpeedMetersPerSecond, currentSpeedMetersPerSecond > 0 {
            appendHistoryPoint(currentSpeedMetersPerSecond * 2.23694, to: &speedHistory, elapsedTime: elapsed)
            appendHistoryPoint(1609.344 / currentSpeedMetersPerSecond, to: &paceHistory, elapsedTime: elapsed)
        }
        appendHistoryPoint(currentPowerWatts, to: &powerHistory, elapsedTime: elapsed)
        appendHistoryPoint(currentCadence, to: &cadenceHistory, elapsedTime: elapsed)
        appendHistoryPoint(currentElevationFeet, to: &elevationHistory, elapsedTime: elapsed)
    }

    private func endLocalWorkout() {
        guard let localSession else { return }
        stateText = SessionStateText.ended
        stopElapsedTimer()
        locationManager.stopUpdatingLocation()
        localSession.end()
    }

    private func finalizeLocalWorkoutSave() async {
        guard let builder else { return }
        let endDate = Date()
        do {
            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()
        } catch {
            launchStatusMessage = "Workout ended, but HealthKit could not save the final sample."
        }
    }

    private func resetForNewSession() {
        stopElapsedTimer()
        metrics = []
        pageKinds = [.metricsPrimary, .heartRateZones, .map]
        speedHistory = []
        paceHistory = []
        powerHistory = []
        elevationHistory = []
        cadenceHistory = []
        heartRateHistory = []
        splits = []
        heartRateZoneDurations = Array(repeating: 0, count: 5)
        powerZoneDurations = Array(repeating: 0, count: 5)
        totalDistanceMeters = 0
        currentHeartRate = nil
        averageHeartRate = nil
        currentSpeedMetersPerSecond = nil
        currentPowerWatts = nil
        averagePowerWatts = nil
        currentCadence = nil
        currentElevationFeet = 0
        elevationGainFeet = 0
        pacerTarget = nil
        phaseQueue = []
        currentPhaseIndex = 0
        stepQueue = []
        currentMicroStageIndex = 0
        pendingEffortPrompt = nil
        builder = nil
        lastLocation = nil
        locationManager.stopUpdatingLocation()
        elapsedTime = 0
        startedAt = nil
        pendingLocalEndAction = nil
        shouldAutoPresentLiveView = true
    }

    fileprivate func finishSession(immediate: Bool = false) {
        stopElapsedTimer()
        isWorkoutActive = false
        stateText = SessionStateText.ended
        clearPersistedSession()
        let cleanupDelay = immediate ? 0.0 : 6.0
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak self] in
            guard let self else { return }
            self.isVisible = false
            self.resetForNewSession()
            self.mirroredSession = nil
            self.localSession = nil
            self.startedAt = nil
            self.source = .appleWatch
        }
    }

    private func persistCurrentSession() {
        guard isWorkoutActive else { return }
        persistedSource = source
        let payload = CompanionPersistedWorkoutSession(
            sourceRawValue: source == .thisDevice ? "thisDevice" : "appleWatch",
            title: title,
            stateText: stateText,
            elapsedTime: elapsedTime,
            pausedElapsedTime: pausedElapsedTime,
            isPaused: isPaused,
            startedAt: startedAt,
            activityRawValue: activityType.rawValue,
            localWorkoutTitle: localWorkoutTitle,
            localWorkoutSubtitle: localWorkoutSubtitle,
            phaseQueue: phaseQueue.map {
                CompanionPersistedWorkoutPhase(
                    id: $0.id,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    activityRawValue: $0.activityRawValue,
                    locationRawValue: $0.locationRawValue,
                    plannedMinutes: $0.plannedMinutes,
                    objectiveStatusText: $0.objectiveStatusText,
                    isObjectiveComplete: $0.isObjectiveComplete
                )
            },
            currentPhaseIndex: currentPhaseIndex,
            stepQueue: stepQueue.map {
                CompanionPersistedWorkoutStep(
                    id: $0.id,
                    title: $0.title,
                    notes: $0.notes,
                    plannedMinutes: $0.plannedMinutes,
                    repeats: $0.repeats,
                    objectiveStatusText: $0.objectiveStatusText,
                    isObjectiveComplete: $0.isObjectiveComplete
                )
            },
            currentMicroStageIndex: currentMicroStageIndex
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    private func restorePersistedSessionIfNeeded() {
        guard !isWorkoutActive,
              let data = UserDefaults.standard.data(forKey: persistenceKey),
              let payload = try? JSONDecoder().decode(CompanionPersistedWorkoutSession.self, from: data) else {
            return
        }

        title = payload.title
        stateText = payload.stateText
        elapsedTime = payload.elapsedTime
        pausedElapsedTime = payload.pausedElapsedTime ?? payload.elapsedTime
        if payload.isPaused == true {
            startedAt = nil
        } else {
            startedAt = payload.startedAt ?? Date().addingTimeInterval(-payload.elapsedTime)
        }
        activityType = HKWorkoutActivityType(rawValue: payload.activityRawValue) ?? .running
        localWorkoutTitle = payload.localWorkoutTitle
        localWorkoutSubtitle = payload.localWorkoutSubtitle
        source = payload.sourceRawValue == "thisDevice" ? .thisDevice : .appleWatch
        persistedSource = source
        phaseQueue = payload.phaseQueue.map {
            WorkoutPhase(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                activityRawValue: $0.activityRawValue,
                locationRawValue: $0.locationRawValue,
                plannedMinutes: $0.plannedMinutes,
                objectiveStatusText: $0.objectiveStatusText,
                isObjectiveComplete: $0.isObjectiveComplete
            )
        }
        currentPhaseIndex = payload.currentPhaseIndex
        stepQueue = payload.stepQueue.map {
            WorkoutStep(
                id: $0.id,
                title: $0.title,
                notes: $0.notes,
                plannedMinutes: $0.plannedMinutes,
                repeats: $0.repeats,
                objectiveStatusText: $0.objectiveStatusText,
                isObjectiveComplete: $0.isObjectiveComplete
            )
        }
        currentMicroStageIndex = payload.currentMicroStageIndex
        isWorkoutActive = true
        shouldAutoPresentLiveView = false
    }

    @available(iOS 26.0, *)
    private func recoverActiveWorkoutSessionIfNeeded() async {
        guard localSession == nil, mirroredSession == nil else { return }
        let recoveredSession = await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession(completion: { session, _ in
                continuation.resume(returning: session)
            })
        }
        guard let recoveredSession else {
            if !isWorkoutActive {
                clearPersistedSession()
            }
            return
        }

        if source == .thisDevice {
            attachRecoveredLocalSession(recoveredSession)
        } else {
            attachMirroredSession(recoveredSession)
        }
    }

    @available(iOS 26.0, *)
    private func attachRecoveredLocalSession(_ session: HKWorkoutSession) {
        let restoredTitle = localWorkoutTitle.isEmpty ? title : localWorkoutTitle
        let restoredSubtitle = localWorkoutSubtitle
        resetForNewSession()
        localWorkoutTitle = restoredTitle
        localWorkoutSubtitle = restoredSubtitle
        localSession = session
        mirroredSession = nil
        builder = session.associatedWorkoutBuilder()
        builder?.delegate = self
        session.delegate = self
        title = restoredTitle
        activityType = session.workoutConfiguration.activityType
        source = .thisDevice
        isWorkoutActive = true
        stateText = session.state == .paused ? SessionStateText.phonePaused : SessionStateText.phoneRunning
        if let persistedData = UserDefaults.standard.data(forKey: persistenceKey),
           let payload = try? JSONDecoder().decode(CompanionPersistedWorkoutSession.self, from: persistedData),
           let restoredStart = payload.startedAt {
            startedAt = restoredStart
            elapsedTime = Date().timeIntervalSince(restoredStart)
        } else {
            startedAt = Date()
        }
        pageKinds = localPageKinds(for: activityType, location: session.workoutConfiguration.locationType)
        shouldAutoPresentLiveView = false
        isVisible = false
        if session.state == .running {
            startElapsedTimer()
        }
        rebuildMetrics()
        persistCurrentSession()
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
                stateText = source == .thisDevice ? SessionStateText.phoneRunning : "Running"
                if startedAt == nil {
                    startedAt = date
                }
                if source == .thisDevice {
                    startElapsedTimer()
                }
                persistCurrentSession()
            case .paused:
                stateText = source == .thisDevice ? SessionStateText.phonePaused : "Paused"
                pausedElapsedTime = elapsedTime
                startedAt = nil
                stopElapsedTimer()
                persistCurrentSession()
            case .ended:
                if source == .thisDevice {
                    Task { @MainActor in
                        await finalizeLocalWorkoutSave()
                        if pendingLocalEndAction == .newWorkout {
                            launchStatusMessage = "Workout finished. Choose the next one from Program Builder."
                        }
                        finishSession()
                    }
                } else {
                    finishSession()
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            print("[Companion] Workout session failed: \(error.localizedDescription)")
            stateText = "Unavailable"
            finishSession()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            print("[Companion] Received \(data.count) packet(s) from remote workout session")
            var successCount = 0
            var failureCount = 0
            
            for packet in data {
                do {
                    let payload = try JSONDecoder().decode(MirroredWorkoutSnapshotPayload.self, from: packet)
                    applyRemoteSnapshot(payload)
                    successCount += 1
                } catch {
                    failureCount += 1
                    print("[Companion] Failed to decode remote snapshot: \(error)")
                }
            }
            
            if failureCount > 0 {
                print("[Companion] Processed \(successCount) successful, \(failureCount) failed packets")
            }
        }
    }
}

extension CompanionWorkoutLiveManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            rebuildMetrics()
            updateDerivedSeries()
            persistCurrentSession()
        }
    }
}

extension CompanionWorkoutLiveManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorized = manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
        Task { @MainActor in
            locationAuthorizationContinuation?.resume(returning: authorized)
            locationAuthorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard source == .thisDevice, isWorkoutActive else { return }
            for location in locations where location.horizontalAccuracy >= 0 {
                if let lastLocation {
                    let distance = max(location.distance(from: lastLocation), 0)
                    if distance > 0 {
                        totalDistanceMeters += distance
                        if location.altitude > lastLocation.altitude {
                            elevationGainFeet += (location.altitude - lastLocation.altitude) * 3.28084
                        }
                    }
                }

                if location.speed >= 0 {
                    currentSpeedMetersPerSecond = location.speed
                }
                currentElevationFeet = location.altitude * 3.28084
                self.lastLocation = location
            }
            updateDerivedSeries()
            rebuildMetrics()
        }
    }
}

#if canImport(WatchConnectivity)
extension CompanionWorkoutLiveManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("[Companion] WCSession activation completed: state=\(activationState.rawValue), error=\(error?.localizedDescription ?? "none")")
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void
    ) {
        Task { @MainActor in
            guard let state = message[CompanionLifecycleKeys.workoutLifecycle] as? String else {
                replyHandler([:])
                return
            }
            let reason = message[CompanionLifecycleKeys.reason] as? String
            self.handleWatchLifecycleState(state, reason: reason)
            replyHandler(["accepted": true])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        Task { @MainActor in
            guard let state = userInfo[CompanionLifecycleKeys.workoutLifecycle] as? String else { return }
            let reason = userInfo[CompanionLifecycleKeys.reason] as? String
            self.handleWatchLifecycleState(state, reason: reason)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[Companion] WCSession became inactive.")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[Companion] WCSession deactivated. Reactivating...")
        session.activate()
    }
    #endif
}
#endif

private struct CompanionWorkoutLiveOverlay: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    @State private var selectedPage: CompanionWorkoutPageKind = .metricsPrimary
    @State private var controlsExpanded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.title)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text(manager.stateText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(companionElapsedString(manager.elapsedTime))
                        .font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit())
                        .lineLimit(1)
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
                }

                TabView(selection: $selectedPage) {
                    ForEach(manager.pageKinds) { page in
                        CompanionWorkoutPageView(manager: manager, page: page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let prompt = manager.pendingEffortPrompt {
                    CompanionWorkoutEffortCard(manager: manager, prompt: prompt)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
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
    @State private var showsInjector = false
    @State private var insertionPlacement: CompanionWorkoutLiveManager.QueueInsertionPlacement = .next

    private var primaryControlLabel: String {
        manager.isPaused ? "Resume" : "Pause"
    }

    private var primaryControlSymbol: String {
        manager.isPaused ? "play.fill" : "pause.fill"
    }

    private var primaryControlCommand: CompanionWorkoutLiveManager.WorkoutControlCommand {
        manager.isPaused ? .resume : .pause
    }

    private var nextPhase: CompanionWorkoutLiveManager.WorkoutPhase? {
        let nextIndex = manager.currentPhaseIndex + 1
        return manager.phaseQueue.indices.contains(nextIndex) ? manager.phaseQueue[nextIndex] : nil
    }

    private var nextStep: CompanionWorkoutLiveManager.WorkoutStep? {
        let nextIndex = manager.currentMicroStageIndex + 1
        return manager.stepQueue.indices.contains(nextIndex) ? manager.stepQueue[nextIndex] : nil
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
                        CompanionWorkoutControlButton(symbol: "plus.circle.fill", title: showsInjector ? "Hide Add" : "Add", tint: .orange) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                showsInjector.toggle()
                            }
                        }
                        CompanionWorkoutControlButton(symbol: "stop.fill", title: "Stop", tint: .red) {
                            manager.sendControl(.stop)
                        }
                        if let nextStep {
                            CompanionWorkoutControlButton(
                                symbol: "forward.end.fill",
                                title: "Next: \(nextStep.title) \(nextStep.plannedMinutes)m",
                                tint: .green
                            ) {
                                manager.sendControl(.nextPhase)
                            }
                        } else if let nextPhase {
                            CompanionWorkoutControlButton(
                                symbol: "forward.end.fill",
                                title: "Next: \(nextPhase.title) \(nextPhase.plannedMinutes)m",
                                tint: .green
                            ) {
                                manager.sendControl(.nextPhase)
                            }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    if showsInjector {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                injectorChip(title: "Inject Next", isSelected: insertionPlacement == .next) {
                                    insertionPlacement = .next
                                }
                                injectorChip(title: "After Plan", isSelected: insertionPlacement == .afterPlan) {
                                    insertionPlacement = .afterPlan
                                }
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(CompanionWorkoutLiveManager.injectableWorkouts) { workout in
                                    CompanionWorkoutControlButton(symbol: workout.symbol, title: workout.title, tint: .orange) {
                                        manager.injectWorkout(workout, placement: insertionPlacement)
                                        showsInjector = false
                                    }
                                }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if !manager.stepQueue.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Current Workout Steps", systemImage: "list.bullet.indent")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(min(manager.currentMicroStageIndex + 1, max(manager.stepQueue.count, 1)))/\(manager.stepQueue.count)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            ForEach(Array(manager.stepQueue.enumerated()), id: \.element.id) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: microStageSymbol(for: index))
                                        .foregroundStyle(microStageTint(for: index))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.title)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                        Text(step.objectiveStatusText)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.65))
                                        if !step.notes.isEmpty {
                                            Text(step.notes)
                                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.52))
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }

                    if manager.phaseQueue.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Workout Queue", systemImage: "list.bullet.rectangle")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(manager.currentPhaseIndex + 1)/\(manager.phaseQueue.count)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            ForEach(Array(manager.phaseQueue.enumerated()), id: \.element.id) { index, phase in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: queueSymbol(for: index))
                                        .foregroundStyle(queueTint(for: index))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(phase.title)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                        Text(queueDetail(for: phase, at: index))
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.65))
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
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

    private func injectorChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((isSelected ? Color.green : Color.white.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func queueSymbol(for index: Int) -> String {
        if index < manager.currentPhaseIndex {
            return "checkmark.circle.fill"
        }
        if index == manager.currentPhaseIndex {
            return "play.circle.fill"
        }
        if index == manager.currentPhaseIndex + 1 {
            return "forward.circle.fill"
        }
        return "circle"
    }

    private func microStageSymbol(for index: Int) -> String {
        if index < manager.currentMicroStageIndex {
            return "checkmark.circle.fill"
        }
        if index == manager.currentMicroStageIndex {
            return "play.circle.fill"
        }
        if index == manager.currentMicroStageIndex + 1 {
            return "forward.circle.fill"
        }
        return "circle"
    }

    private func microStageTint(for index: Int) -> Color {
        if index < manager.currentMicroStageIndex {
            return .green
        }
        if index == manager.currentMicroStageIndex {
            return .orange
        }
        if index == manager.currentMicroStageIndex + 1 {
            return .cyan
        }
        return .white.opacity(0.36)
    }

    private func queueTint(for index: Int) -> Color {
        if index < manager.currentPhaseIndex {
            return .green
        }
        if index == manager.currentPhaseIndex {
            return .orange
        }
        if index == manager.currentPhaseIndex + 1 {
            return .mint
        }
        return Color.white.opacity(0.45)
    }

    private func queueDetail(for phase: CompanionWorkoutLiveManager.WorkoutPhase, at index: Int) -> String {
        if index < manager.currentPhaseIndex {
            return "Completed"
        }
        if index == manager.currentPhaseIndex {
            return "Current • \(phase.objectiveStatusText)"
        }
        if index == manager.currentPhaseIndex + 1 {
            return "Next • \(phase.objectiveStatusText)"
        }
        return phase.objectiveStatusText
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
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
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

private struct CompanionWorkoutEffortCard: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager
    let prompt: CompanionWorkoutLiveManager.EffortPromptPhase
    @State private var score = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log Effort")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(prompt.title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(prompt.subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text("\(Int(score.rounded()))/10")
                    .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.green)
            }

            Slider(value: $score, in: 1...10, step: 1)
                .tint(.green)

            Button {
                manager.submitEffortScoreOnPhone(Int(score.rounded()))
            } label: {
                Text("Save on iPhone")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: line.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(line.tint)
                            .frame(width: 24, height: 24)
                            .background(line.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        if !line.label.isEmpty {
                            Text(line.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Text(line.value)
                        .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
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
            HStack(spacing: 8) {
                Image(systemName: companionMetricSymbol(for: title))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
            }

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
    let totalCentiseconds = Int((elapsed * 100).rounded())
    let centiseconds = totalCentiseconds % 100
    let totalSeconds = totalCentiseconds / 100
    let seconds = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    let minutes = totalMinutes % 60
    let hours = totalMinutes / 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }
    if minutes > 0 {
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
    return String(format: "%02d.%02d", seconds, centiseconds)
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
    let symbol: String
    let tint: Color
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
                .init(id: "speed", value: companionSpeedValue(metersPerSecond: avgSpeed), label: "AVERAGE SPEED", symbol: "speedometer", tint: .cyan),
                .init(id: "elev", value: "\(Int(manager.elevationGainFeet.rounded()))FT", label: "ELEVATION GAINED", symbol: "mountain.2.fill", tint: .green),
                .init(id: "distance", value: companionDistanceValue(distanceMeters: manager.totalDistanceMeters, activityType: manager.activityType), label: "DISTANCE", symbol: "point.topleft.down.curvedto.point.bottomright.up.fill", tint: .orange)
            ]
        default:
            return [
                .init(id: "time", value: companionElapsedString(manager.elapsedTime), label: "TIME", symbol: "timer", tint: .yellow),
                .init(id: "pace", value: companionPaceValue(speed: manager.currentSpeedMetersPerSecond == nil ? nil : avgSpeed), label: "AVERAGE PACE", symbol: "figure.run", tint: .mint),
                .init(id: "distance", value: companionDistanceValue(distanceMeters: manager.totalDistanceMeters, activityType: manager.activityType), label: "DISTANCE", symbol: "point.topleft.down.curvedto.point.bottomright.up.fill", tint: .orange)
            ]
        }
    case .secondary:
        switch manager.activityType {
        case .cycling:
            return [
                .init(id: "power", value: manager.currentPowerWatts.map { "\(Int($0.rounded()))W" } ?? "--", label: "POWER", symbol: "bolt.fill", tint: .green),
                .init(id: "cadence", value: manager.currentCadence.map { "\(Int($0.rounded()))RPM" } ?? "--", label: "CADENCE", symbol: "metronome.fill", tint: .mint),
                .init(id: "speed", value: companionSpeedValue(metersPerSecond: manager.currentSpeedMetersPerSecond), label: "CURRENT SPEED", symbol: "speedometer", tint: .cyan)
            ]
        default:
            return [
                .init(id: "cadence", value: manager.currentCadence.map { "\(Int($0.rounded()))" } ?? "--", label: "CADENCE", symbol: "metronome.fill", tint: .mint),
                .init(id: "pace", value: companionPaceValue(speed: manager.currentSpeedMetersPerSecond), label: "CURRENT PACE", symbol: "figure.run", tint: .cyan),
                .init(id: "hr", value: manager.currentHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--", label: "HEART RATE", symbol: "heart.fill", tint: .red)
            ]
        }
    }
}

@MainActor
private func companionMetricSymbol(for title: String) -> String {
    switch title {
    case "POWER":
        return "bolt.fill"
    case "ELEVATION":
        return "mountain.2.fill"
    case "SEGMENTS":
        return "figure.run"
    default:
        return "chart.xyaxis.line"
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
