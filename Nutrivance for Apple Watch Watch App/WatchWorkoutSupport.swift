import Combine
import CoreLocation
import Foundation
import HealthKit
import SwiftUI
import UserNotifications
import WatchKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
import WorkoutKit

private struct WatchPersistedWorkoutSession: Codable {
    let displayStateRawValue: String
    let activeTitle: String?
    let activeSubtitle: String?
    let activeActivityRawValue: UInt?
    let activeLocationRawValue: Int
    let workoutStartDate: Date?
    let accumulatedElapsedTime: TimeInterval
    let pauseStartedAt: Date?
    let phaseQueue: [WatchProgramPhasePayload]
    let currentPhaseIndex: Int
    let currentMicroStageIndex: Int
    let routeName: String?
    let routeTrailhead: WatchPlanCoordinatePayload?
    let routeCoordinates: [WatchPlanCoordinatePayload]
}

struct WatchWorkoutTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let activity: HKWorkoutActivityType
    let location: HKWorkoutSessionLocationType

    static let defaults: [WatchWorkoutTemplate] = [
        .init(id: "run", title: "Outdoor Run", subtitle: "Distance, pace, HR, run metrics", symbol: "figure.run", activity: .running, location: .outdoor),
        .init(id: "walk", title: "Outdoor Walk", subtitle: "Distance, pace, HR", symbol: "figure.walk", activity: .walking, location: .outdoor),
        .init(id: "cycle", title: "Cycling", subtitle: "Power, cadence, speed, HR", symbol: "bicycle", activity: .cycling, location: .outdoor),
        .init(id: "swim", title: "Pool Swim", subtitle: "Distance, strokes, HR", symbol: "figure.pool.swim", activity: .swimming, location: .indoor),
        .init(id: "strength", title: "Strength", subtitle: "Energy, HR, effort", symbol: "dumbbell.fill", activity: .traditionalStrengthTraining, location: .indoor),
        .init(id: "hiit", title: "HIIT", subtitle: "Intervals, HR, energy", symbol: "flame.fill", activity: .highIntensityIntervalTraining, location: .indoor),
        .init(id: "hike", title: "Hike", subtitle: "Elevation, distance, HR", symbol: "figure.hiking", activity: .hiking, location: .outdoor),
        .init(id: "yoga", title: "Yoga", subtitle: "Time, HR, energy", symbol: "figure.mind.and.body", activity: .yoga, location: .indoor)
    ]
}

enum WatchWorkoutGoalMode: String, CaseIterable, Identifiable {
    case open
    case time
    case distance
    case energy

    var id: String { rawValue }
}

enum WatchWorkoutLocationChoice: String, CaseIterable, Identifiable {
    case indoor
    case outdoor

    var id: String { rawValue }

    var hkValue: HKWorkoutSessionLocationType {
        switch self {
        case .indoor:
            return .indoor
        case .outdoor:
            return .outdoor
        }
    }
}

struct WatchCustomWorkoutDraft: Hashable {
    var displayName = "Custom Workout"
    var goalMode: WatchWorkoutGoalMode = .open
    var goalValue: Double = 30
    var stages: [WatchCustomWorkoutStage] = [WatchCustomWorkoutStage()]

    var workoutGoal: WorkoutGoal {
        switch goalMode {
        case .open:
            return .open
        case .time:
            return .time(goalValue, .minutes)
        case .distance:
            return .distance(goalValue, .kilometers)
        case .energy:
            return .energy(goalValue, .kilocalories)
        }
    }

    var workoutPlan: WorkoutPlan? {
        guard let workout = watchCustomWorkout(displayName: displayName, stages: stages) else {
            return nil
        }
        return WorkoutPlan(.custom(workout))
    }
}

struct WatchCustomWorkoutStage: Identifiable, Hashable {
    let id: UUID
    var activity: HKWorkoutActivityType
    var location: WatchWorkoutLocationChoice
    var plannedMinutes: Int
    var goalMode: WatchWorkoutGoalMode
    var goalValue: Double

    init(
        id: UUID = UUID(),
        activity: HKWorkoutActivityType = .running,
        location: WatchWorkoutLocationChoice = .outdoor,
        plannedMinutes: Int = 30,
        goalMode: WatchWorkoutGoalMode = .time,
        goalValue: Double = 30
    ) {
        self.id = id
        self.activity = activity
        self.location = location
        self.plannedMinutes = plannedMinutes
        self.goalMode = goalMode
        self.goalValue = goalValue
    }

    var title: String {
        watchWorkoutDisplayName(activity)
    }
}

extension WatchCustomWorkoutDraft {
    var totalPlannedMinutes: Int {
        stages.reduce(0) { $0 + max($1.plannedMinutes, 1) }
    }

    var customPhases: [WatchProgramPhasePayload] {
        let stageList = stages.isEmpty ? [WatchCustomWorkoutStage()] : stages
        return stageList.enumerated().map { index, stage in
            WatchProgramPhasePayload(
                id: stage.id,
                title: stage.title,
                subtitle: stageList.count > 1
                    ? "\(displayName) • Stage \(index + 1) of \(stageList.count)"
                    : "Custom • \(displayName)",
                activityID: "custom-\(index)-\(stage.activity.rawValue)",
                activityRawValue: stage.activity.rawValue,
                locationRawValue: stage.location.hkValue.rawValue,
                plannedMinutes: max(stage.plannedMinutes, 1),
                objective: objectivePayload(for: stage)
            )
        }
    }

    private func objectivePayload(for stage: WatchCustomWorkoutStage) -> WatchPhaseObjectivePayload {
        switch stage.goalMode {
        case .open, .time:
            return WatchPhaseObjectivePayload(
                kind: .time,
                targetValue: Double(max(stage.plannedMinutes, 1)),
                label: "Time"
            )
        case .distance:
            return WatchPhaseObjectivePayload(
                kind: .distance,
                targetValue: max(stage.goalValue, 0.1),
                label: "Distance"
            )
        case .energy:
            return WatchPhaseObjectivePayload(
                kind: .energy,
                targetValue: max(stage.goalValue, 1),
                label: "Energy"
            )
        }
    }
}

private func watchCustomWorkout(displayName: String, stages: [WatchCustomWorkoutStage]) -> CustomWorkout? {
    let stageList = stages.isEmpty ? [WatchCustomWorkoutStage()] : stages
    guard let firstStage = stageList.first else { return nil }
    let anchorActivity = firstStage.activity
    let anchorLocation = firstStage.location.hkValue

    guard stageList.allSatisfy({ $0.activity == anchorActivity && $0.location.hkValue == anchorLocation }) else {
        return nil
    }

    let blocks = stageList.map { stage in
        IntervalBlock(
            steps: [
                IntervalStep(
                    .work,
                    step: WorkoutStep(
                        goal: watchWorkoutGoal(for: stage),
                        alert: watchWorkoutAlert(for: stage),
                        displayName: stage.title
                    )
                )
            ],
            iterations: 1
        )
    }

    return CustomWorkout(
        activity: anchorActivity,
        location: anchorLocation,
        displayName: displayName,
        warmup: nil,
        blocks: blocks,
        cooldown: nil
    )
}

private func watchWorkoutGoal(for stage: WatchCustomWorkoutStage) -> WorkoutGoal {
    switch stage.goalMode {
    case .open, .time:
        return .time(Double(max(stage.plannedMinutes, 1)), .minutes)
    case .distance:
        return .distance(max(stage.goalValue, 0.1), .kilometers)
    case .energy:
        return .energy(max(stage.goalValue, 1), .kilocalories)
    }
}

private func watchWorkoutAlert(for stage: WatchCustomWorkoutStage) -> (any WorkoutAlert)? {
    nil
}

struct WatchLiveMetric: Identifiable, Hashable {
    let id: String
    let title: String
    let valueText: String
    let symbol: String
    let tint: Color
}

enum WatchWorkoutPageKind: String, CaseIterable, Codable, Hashable, Identifiable {
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

    var title: String {
        switch self {
        case .metricsPrimary:
            return "Main Metrics"
        case .metricsSecondary:
            return "Detail Metrics"
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
}

struct WatchWorkoutSeriesPoint: Codable, Hashable, Identifiable {
    let elapsedTime: TimeInterval
    let value: Double

    var id: TimeInterval { elapsedTime }
}

struct WatchWorkoutSplit: Codable, Hashable, Identifiable {
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

struct WatchPacerTarget: Codable, Hashable {
    let lowerBound: Double
    let upperBound: Double
    let unitLabel: String
}

private struct CompanionWorkoutMetricPayload: Codable {
    let id: String
    let title: String
    let valueText: String
    let symbol: String
    let tintName: String
}

private struct CompanionWorkoutSeriesPointPayload: Codable {
    let elapsedTime: TimeInterval
    let value: Double
}

private struct CompanionWorkoutSplitPayload: Codable {
    let index: Int
    let elapsedTime: TimeInterval
    let splitDuration: TimeInterval
    let splitDistanceMeters: Double
    let averageHeartRate: Double?
    let averageSpeedMetersPerSecond: Double?
    let averagePowerWatts: Double?
    let averageCadence: Double?
}

private struct CompanionWorkoutPacerPayload: Codable {
    let lowerBound: Double
    let upperBound: Double
    let unitLabel: String
}

private struct CompanionWorkoutPhasePayload: Codable {
    let id: UUID
    let title: String
    let subtitle: String
    let activityRawValue: UInt
    let locationRawValue: Int
    let plannedMinutes: Int
    let objectiveStatusText: String
    let isObjectiveComplete: Bool
}

private struct CompanionWorkoutMicroStagePayload: Codable {
    let id: UUID
    let title: String
    let notes: String
    let plannedMinutes: Int
    let repeats: Int
    let objectiveStatusText: String
    let isObjectiveComplete: Bool
}

private struct CompanionWorkoutEffortPromptPayload: Codable {
    let phaseID: UUID
    let title: String
    let subtitle: String
}

private struct CompanionWorkoutSnapshotPayload: Codable {
    let title: String
    let stateText: String
    let activityRawValue: UInt
    let elapsedTime: TimeInterval
    let metrics: [CompanionWorkoutMetricPayload]
    let pageKinds: [String]
    let speedHistory: [CompanionWorkoutSeriesPointPayload]
    let paceHistory: [CompanionWorkoutSeriesPointPayload]
    let powerHistory: [CompanionWorkoutSeriesPointPayload]
    let elevationHistory: [CompanionWorkoutSeriesPointPayload]
    let cadenceHistory: [CompanionWorkoutSeriesPointPayload]
    let heartRateHistory: [CompanionWorkoutSeriesPointPayload]
    let splits: [CompanionWorkoutSplitPayload]
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
    let pacerTarget: CompanionWorkoutPacerPayload?
    let phaseQueue: [CompanionWorkoutPhasePayload]
    let currentPhaseIndex: Int
    let stepQueue: [CompanionWorkoutMicroStagePayload]
    let currentMicroStageIndex: Int
    let effortPrompt: CompanionWorkoutEffortPromptPayload?
}

@MainActor
final class WatchWakeScheduler: ObservableObject {
    @Published private(set) var statusText = "Wake timer off"
    @Published private(set) var authorizationGranted = false

    func scheduleWakeNotification(for wakeTime: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            authorizationGranted = granted == true
        } else {
            authorizationGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }

        guard authorizationGranted else {
            statusText = "Allow notifications to use wake timer"
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: ["watch-wake-timer"])

        let nextWakeDate = Self.nextOccurrence(of: wakeTime)
        let components = Calendar.current.dateComponents([.hour, .minute, .day, .month, .year], from: nextWakeDate)

        let content = UNMutableNotificationContent()
        content.title = "Wake Up"
        content.body = "Your Nutrivance wake timer is ready."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "watch-wake-timer", content: content, trigger: trigger)

        do {
            try await center.add(request)
            statusText = "Next wake: \(nextWakeDate.formatted(date: .omitted, time: .shortened))"
        } catch {
            statusText = "Wake timer unavailable"
        }
    }

    private static func nextOccurrence(of time: Date) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.hour, .minute], from: time)
        components.second = 0

        let todayCandidate = calendar.nextDate(after: now.addingTimeInterval(-1), matching: components, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        return todayCandidate > now ? todayCandidate : (calendar.date(byAdding: .day, value: 1, to: todayCandidate) ?? todayCandidate)
    }
}

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    private enum CompanionControlCommand: String {
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

    private enum CompanionLaunchKeys {
        static let workoutStart = "workoutStart"
        static let openInWorkoutApp = "openInWorkoutApp"
        static let title = "title"
        static let subtitle = "subtitle"
        static let activityRawValue = "activityRawValue"
        static let locationRawValue = "locationRawValue"
        static let routeName = "routeName"
        static let trailheadLatitude = "trailheadLatitude"
        static let trailheadLongitude = "trailheadLongitude"
        static let routeCoordinates = "routeCoordinates"
        static let phasePayloads = "phasePayloads"
        static let accepted = "accepted"
        static let injectedPlacement = "injectedPlacement"
        static let injectedTitle = "injectedTitle"
        static let injectedSubtitle = "injectedSubtitle"
        static let injectedActivityRawValue = "injectedActivityRawValue"
        static let injectedLocationRawValue = "injectedLocationRawValue"
        static let injectedPlannedMinutes = "injectedPlannedMinutes"
    }

    enum SessionDisplayState: String {
        case idle
        case preparing
        case running
        case paused
        case ended
        case failed
    }

    enum PostWorkoutDestination {
        case none
        case effortPrompt
        case nextWorkoutPicker
    }

    private enum EndAction {
        case none
        case promptEffort
        case startAnotherWorkout
        case advancePhase
    }

    struct CompletedPhaseEffort: Identifiable, Hashable {
        let id: UUID
        let phase: WatchProgramPhasePayload
        let completedAt: Date
        var score: Int?
    }

    @Published private(set) var displayState: SessionDisplayState = .idle
    @Published private(set) var metrics: [WatchLiveMetric] = []
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var workoutStartDate: Date?
    @Published private(set) var activeTitle: String?
    @Published private(set) var activeSubtitle: String?
    @Published private(set) var activeActivity: HKWorkoutActivityType?
    @Published private(set) var activeLocation: HKWorkoutSessionLocationType = .unknown
    @Published private(set) var authorizationGranted = false
    @Published private(set) var schedulerAuthorizationState: WorkoutScheduler.AuthorizationState?
    @Published private(set) var scheduledPlans: [ScheduledWorkoutPlan] = []
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var currentZoneIndex: Int?
    @Published private(set) var liveZoneDurations: [TimeInterval] = Array(repeating: 0, count: 5)
    @Published private(set) var splitCount = 0
    @Published private(set) var isMirroringToPhone = false
    @Published private(set) var totalDistanceMeters: Double = 0
    @Published private(set) var currentEnergyKilocalories: Double = 0
    @Published private(set) var currentSpeedMetersPerSecond: Double?
    @Published private(set) var currentPowerWatts: Double?
    @Published private(set) var averagePowerWatts: Double?
    @Published private(set) var currentCadence: Double?
    @Published private(set) var flightsClimbed: Double?
    @Published private(set) var strokeCount: Double?
    @Published private(set) var strideMeters: Double?
    @Published private(set) var groundContactTimeMilliseconds: Double?
    @Published private(set) var verticalOscillationCentimeters: Double?
    @Published private(set) var speedHistory: [WatchWorkoutSeriesPoint] = []
    @Published private(set) var paceHistory: [WatchWorkoutSeriesPoint] = []
    @Published private(set) var powerHistory: [WatchWorkoutSeriesPoint] = []
    @Published private(set) var elevationHistory: [WatchWorkoutSeriesPoint] = []
    @Published private(set) var cadenceHistory: [WatchWorkoutSeriesPoint] = []
    @Published private(set) var heartRateHistory: [WatchWorkoutSeriesPoint] = []
    @Published private(set) var splits: [WatchWorkoutSplit] = []
    @Published private(set) var powerZoneDurations: [TimeInterval] = Array(repeating: 0, count: 5)
    @Published private(set) var currentElevationFeet: Double = 0
    @Published private(set) var elevationGainFeet: Double = 0
    @Published private(set) var pacerTarget: WatchPacerTarget?
    @Published private(set) var routeName: String?
    @Published private(set) var routeTrailhead: CLLocationCoordinate2D?
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var phaseQueue: [WatchProgramPhasePayload] = []
    @Published private(set) var currentPhaseIndex = 0
    @Published private(set) var currentMicroStageIndex = 0
    @Published private(set) var pendingEffortQueue: [CompletedPhaseEffort] = []
    @Published private(set) var activeCompletionPrompt: WatchProgramPhasePayload?

    private enum CompanionLifecycleKeys {
        static let workoutLifecycle = "workoutLifecycle"
        static let reason = "reason"
        static let effortScore = "effortScore"
    }
    @Published private(set) var postWorkoutDestination: PostWorkoutDestination = .none
    @Published private(set) var lastCompletedWorkoutTitle: String?
    @Published private(set) var lastCompletedWorkoutSubtitle: String?
    @Published private(set) var lastEffortScore: Int?
    @Published var customDraft = WatchCustomWorkoutDraft()
    @Published var statusMessage = "Choose a workout to begin."
    private var dismissedCompletionPromptPhaseID: UUID?

    var isSessionActive: Bool {
        displayState == .running || displayState == .paused || displayState == .preparing
    }

    var isOutdoorWorkout: Bool {
        activeLocation == .outdoor
    }

    var currentPhase: WatchProgramPhasePayload? {
        phaseQueue.indices.contains(currentPhaseIndex) ? phaseQueue[currentPhaseIndex] : nil
    }

    var nextPhase: WatchProgramPhasePayload? {
        let nextIndex = currentPhaseIndex + 1
        return phaseQueue.indices.contains(nextIndex) ? phaseQueue[nextIndex] : nil
    }

    var currentMicroStages: [WatchProgramMicroStagePayload] {
        currentPhase?.microStages ?? []
    }

    var currentMicroStage: WatchProgramMicroStagePayload? {
        currentMicroStages.indices.contains(currentMicroStageIndex) ? currentMicroStages[currentMicroStageIndex] : nil
    }

    var nextMicroStage: WatchProgramMicroStagePayload? {
        let nextIndex = currentMicroStageIndex + 1
        return currentMicroStages.indices.contains(nextIndex) ? currentMicroStages[nextIndex] : nil
    }

    var nextAdvanceTitle: String? {
        nextMicroStage?.title ?? nextPhase?.title
    }

    var nextAdvancePlannedMinutes: Int? {
        nextMicroStage?.plannedMinutes ?? nextPhase?.plannedMinutes
    }

    var currentPhaseRemainingTime: TimeInterval? {
        let objective: WatchPhaseObjectivePayload
        if let currentMicroStage {
            objective = currentMicroStage.objective
        } else if let currentPhase {
            objective = currentPhase.objective ?? WatchPhaseObjectivePayload(kind: .time, targetValue: Double(max(currentPhase.plannedMinutes, 1)))
        } else {
            return nil
        }
        guard objective.kind == .time else { return nil }
        return max(objective.targetValue * 60 - currentSegmentElapsedTime(at: Date()), 0)
    }

    var isNextPhaseReady: Bool {
        guard nextMicroStage != nil || nextPhase != nil else { return false }
        return currentSegmentObjectiveStatus().isComplete
    }

    var isCurrentPhaseObjectiveComplete: Bool {
        currentSegmentObjectiveStatus().isComplete
    }

    var currentEffortPromptPhase: CompletedPhaseEffort? {
        pendingEffortQueue.first
    }

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var elapsedTimer: Timer?
    private var estimatedMaxHeartRate: Double = 190
    private var lastZoneSampleDate: Date?
    private var accumulatedElapsedTime: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var pendingEndAction: EndAction = .none
    private var lastPowerSampleDate: Date?
    private var lastHistorySampleElapsedTime: TimeInterval = 0
    private var currentSplitStartElapsedTime: TimeInterval = 0
    private var currentSplitStartDistanceMeters: Double = 0
    private var autoSplitLengthMeters: Double?
    private let workoutTabPreferences = WatchWorkoutTabPreferences()
    private var hasAnnouncedCurrentPhaseReady = false
    private var nextPhaseReminderIdentifier: String?
    private var microStageStartDate: Date?
    private var accumulatedMicroStageElapsedTime: TimeInterval = 0
    private var microStageStartDistanceMeters: Double = 0
    private var microStageStartEnergyKilocalories: Double = 0
    private var microStageStartZoneDurations: [TimeInterval] = []
    private let persistenceKey = "watch.live.workout.session_v2"

    private var sessionState: HKWorkoutSessionState? {
        workoutSession?.state
    }

    var orderedWorkoutPages: [WatchWorkoutPageKind] {
        orderedPages(for: activeActivity ?? .running)
    }

    func orderedPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        workoutTabPreferences.orderedPages(for: activity)
    }

    func isPageEnabled(_ page: WatchWorkoutPageKind, for activity: HKWorkoutActivityType) -> Bool {
        orderedPages(for: activity).contains(page)
    }

    func setPageEnabled(_ isEnabled: Bool, page: WatchWorkoutPageKind, for activity: HKWorkoutActivityType) {
        var pages = orderedPages(for: activity)
        if isEnabled {
            if !pages.contains(page) {
                let defaultPages = WatchWorkoutTabPreferences.defaultPages(for: activity)
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
        workoutTabPreferences.setOrderedPages(pages, for: activity)
        objectWillChange.send()
    }

    func movePage(_ page: WatchWorkoutPageKind, direction: Int, for activity: HKWorkoutActivityType) {
        var pages = orderedPages(for: activity)
        guard let index = pages.firstIndex(of: page) else { return }
        let destination = min(max(index + direction, 0), pages.count - 1)
        guard destination != index else { return }
        pages.move(fromOffsets: IndexSet(integer: index), toOffset: destination > index ? destination + 1 : destination)
        workoutTabPreferences.setOrderedPages(pages, for: activity)
        objectWillChange.send()
    }

    func activate() {
        Task {
            authorizationGranted = await requestAuthorizationIfNeeded()
            estimatedMaxHeartRate = await estimatedMaximumHeartRate()
            restorePersistedSessionIfNeeded()
            await recoverActiveWorkoutSessionIfNeeded()
#if canImport(WatchConnectivity)
            if WCSession.isSupported() {
                let session = WCSession.default
                session.delegate = self
                session.activate()
            }
#endif
            if #available(watchOS 10.0, *) {
                schedulerAuthorizationState = await WorkoutScheduler.shared.requestAuthorization()
                scheduledPlans = await WorkoutScheduler.shared.scheduledWorkouts
            }
        }
    }

    func start(template: WatchWorkoutTemplate) {
        let phase = WatchProgramPhasePayload(
            id: UUID(),
            title: template.title,
            subtitle: template.subtitle,
            activityID: template.id,
            activityRawValue: template.activity.rawValue,
            locationRawValue: template.location.rawValue,
            plannedMinutes: 30,
            objective: WatchPhaseObjectivePayload(kind: .time, targetValue: 30, label: "Time")
        )
        phaseQueue = [phase]
        currentPhaseIndex = 0
        currentMicroStageIndex = 0
        pendingEffortQueue = []
        startWorkout(
            title: phase.title,
            subtitle: phase.subtitle,
            activity: template.activity,
            location: template.location
        )
    }

    func startCustomWorkout() {
        let phases = customDraft.customPhases
        guard let firstPhase = phases.first else {
            statusMessage = "Add at least one custom stage."
            return
        }
        phaseQueue = phases
        currentPhaseIndex = 0
        currentMicroStageIndex = 0
        pendingEffortQueue = []
        startWorkout(
            title: firstPhase.title,
            subtitle: firstPhase.subtitle,
            activity: HKWorkoutActivityType(rawValue: firstPhase.activityRawValue) ?? .running,
            location: HKWorkoutSessionLocationType(rawValue: firstPhase.locationRawValue) ?? .unknown
        )
    }

    func startSyncedPlan(_ plan: WatchProgramPlanPayload) {
        let phases = plan.phases.isEmpty
            ? [
                WatchProgramPhasePayload(
                    id: plan.id,
                    title: plan.title,
                    subtitle: plan.summary,
                    activityID: "primary-\(plan.activityRawValue)",
                    activityRawValue: plan.activityRawValue,
                    locationRawValue: plan.locationRawValue,
                    plannedMinutes: 30,
                    objective: WatchPhaseObjectivePayload(kind: .time, targetValue: 30, label: "Time")
                )
            ]
            : plan.phases
        let firstPhase = phases[0]
        let activity = HKWorkoutActivityType(rawValue: firstPhase.activityRawValue) ?? .running
        let location = HKWorkoutSessionLocationType(rawValue: firstPhase.locationRawValue) ?? .unknown
        phaseQueue = phases
        currentPhaseIndex = 0
        currentMicroStageIndex = 0
        pendingEffortQueue = []
        routeName = plan.routeName
        routeTrailhead = plan.trailhead.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        routeCoordinates = plan.routeCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        startWorkout(
            title: firstPhase.title,
            subtitle: firstPhase.subtitle,
            activity: activity,
            location: location,
            resetRouteGuidance: false
        )
    }

    func scheduleCustomWorkoutForTomorrow() {
        guard #available(watchOS 10.0, *) else { return }

        Task {
            guard let workoutPlan = customDraft.workoutPlan else {
                statusMessage = "WorkoutKit custom workouts need one shared activity and location across stages."
                return
            }
            if schedulerAuthorizationState != .authorized {
                schedulerAuthorizationState = await WorkoutScheduler.shared.requestAuthorization()
            }
            guard schedulerAuthorizationState == .authorized else {
                statusMessage = "Workout scheduling permission is required."
                return
            }

            let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            await WorkoutScheduler.shared.schedule(workoutPlan, at: components)
            scheduledPlans = await WorkoutScheduler.shared.scheduledWorkouts
            statusMessage = "Custom workout scheduled for tomorrow."
        }
    }

    func pause() {
        guard let workoutSession else {
            statusMessage = "No active workout to pause."
            return
        }
        guard sessionState == .running || displayState == .running else {
            statusMessage = "Workout is not currently running."
            return
        }

        statusMessage = "Pausing workout..."
        accumulatedElapsedTime = currentElapsedTime(at: Date())
        accumulatedMicroStageElapsedTime = currentSegmentElapsedTime(at: Date())
        pauseStartedAt = Date()
        elapsedTime = accumulatedElapsedTime
        displayState = .paused
        workoutSession.pause()
        broadcastCompanionSnapshot()
    }

    func resume() {
        guard let workoutSession else {
            statusMessage = "No paused workout to resume."
            return
        }
        guard sessionState == .paused || displayState == .paused else {
            statusMessage = "Workout is already running."
            return
        }

        statusMessage = "Resuming workout..."
        if pauseStartedAt != nil {
            workoutStartDate = Date()
            microStageStartDate = Date()
            pauseStartedAt = nil
        }
        displayState = .running
        workoutSession.resume()
        broadcastCompanionSnapshot()
    }

    func end() {
        guard let workoutSession else { return }
        clearPendingNextPhaseReminder()
        activeCompletionPrompt = nil
        dismissedCompletionPromptPhaseID = nil
        enqueueCurrentPhaseForEffort()
        elapsedTime = currentElapsedTime(at: Date())
        statusMessage = "Ending workout..."
        displayState = .ended
        stopElapsedTimer()
        pendingEndAction = .promptEffort
        lastCompletedWorkoutTitle = activeTitle
        lastCompletedWorkoutSubtitle = activeSubtitle
        postWorkoutDestination = .effortPrompt
        workoutSession.end()
    }

    func advanceToNextPhase() {
        if advanceWithinCurrentPhaseIfNeeded() {
            return
        }
        guard let nextPhase else {
            end()
            return
        }
        guard workoutSession != nil else { return }
        clearPendingNextPhaseReminder()
        activeCompletionPrompt = nil
        dismissedCompletionPromptPhaseID = nil
        enqueueCurrentPhaseForEffort()
        elapsedTime = currentElapsedTime(at: Date())
        statusMessage = "Switching to \(nextPhase.title)..."
        displayState = .ended
        stopElapsedTimer()
        pendingEndAction = .advancePhase
        lastCompletedWorkoutTitle = activeTitle
        lastCompletedWorkoutSubtitle = activeSubtitle
        workoutSession?.end()
    }

    func jumpToQueuedPhase(_ phaseID: UUID) {
        guard let currentPhase else { return }
        guard let targetIndex = phaseQueue.firstIndex(where: { $0.id == phaseID }) else { return }
        guard targetIndex > currentPhaseIndex else { return }

        clearPendingNextPhaseReminder()
        activeCompletionPrompt = nil
        dismissedCompletionPromptPhaseID = nil

        if targetIndex > currentPhaseIndex + 1 {
            phaseQueue.removeSubrange((currentPhaseIndex + 1)..<targetIndex)
        }

        statusMessage = "Skipping from \(currentPhase.title) to \(phaseQueue[currentPhaseIndex + 1].title)..."
        advanceToNextPhase()
    }

    func jumpToMicroStage(_ stageID: UUID) {
        guard let currentPhase else { return }
        guard !currentMicroStages.isEmpty else { return }
        guard let targetIndex = currentMicroStages.firstIndex(where: { $0.id == stageID }) else { return }
        guard targetIndex > currentMicroStageIndex else { return }

        currentMicroStageIndex = targetIndex
        resetMicroStageTracking(at: Date())
        hasAnnouncedCurrentPhaseReady = false
        activeCompletionPrompt = nil
        dismissedCompletionPromptPhaseID = currentPhase.id
        statusMessage = "Moved to \(currentMicroStages[targetIndex].title)."
        broadcastCompanionSnapshot()
    }

    func dismissCompletionPrompt() {
        dismissedCompletionPromptPhaseID = currentPhase?.id
        activeCompletionPrompt = nil
        broadcastCompanionSnapshot()
    }

    func markSplit() {
        guard isSessionActive else {
            statusMessage = "Start a workout before marking a split."
            return
        }

        appendSplitSnapshot(isAutomatic: false)
        statusMessage = "Split \(splitCount) at \(shortWorkoutElapsedString(elapsedTime))"
        broadcastCompanionSnapshot()
    }

    func enableWaterLock() {
        WKInterfaceDevice.current().enableWaterLock()
        statusMessage = "Water lock enabled"
    }

    func showOnPhone() {
        guard isSessionActive else {
            statusMessage = "Start a workout before opening it on iPhone."
            return
        }

        statusMessage = "Connecting to iPhone..."

        Task {
            let mirrored = await ensureCompanionMirroring()
            let revealed = await requestCompanionPresentation()

            if mirrored && revealed {
                statusMessage = "Live workout opened on iPhone."
            } else if mirrored {
                statusMessage = "Mirroring is on. Open Nutrivance on iPhone to view it."
            } else if revealed {
                statusMessage = "Requested iPhone live view."
            } else {
                statusMessage = "Could not reach iPhone. Keep Nutrivance open on your phone."
            }

            broadcastCompanionSnapshot()
        }
    }

    func newWorkout() {
        guard isSessionActive else {
            postWorkoutDestination = .nextWorkoutPicker
            statusMessage = "Choose your next workout."
            return
        }

        elapsedTime = currentElapsedTime(at: Date())
        statusMessage = "Ending workout. Choose your next workout."
        displayState = .ended
        stopElapsedTimer()
        pendingEndAction = .startAnotherWorkout
        lastCompletedWorkoutTitle = activeTitle
        lastCompletedWorkoutSubtitle = activeSubtitle
        postWorkoutDestination = .nextWorkoutPicker
        workoutSession?.end()
    }

    func injectTemplate(_ template: WatchWorkoutTemplate, placement: QueueInsertionPlacement) {
        let phase = WatchProgramPhasePayload(
            id: UUID(),
            title: template.title,
            subtitle: "Injected • \(template.subtitle)",
            activityID: "inject-\(template.id)-\(UUID().uuidString)",
            activityRawValue: template.activity.rawValue,
            locationRawValue: template.location.rawValue,
            plannedMinutes: 30,
            objective: WatchPhaseObjectivePayload(kind: .time, targetValue: 30, label: "Time")
        )
        injectPhases([phase], placement: placement)
    }

    func injectCustomStages(placement: QueueInsertionPlacement) {
        let phases = customDraft.customPhases
        guard !phases.isEmpty else {
            statusMessage = "Add a custom stage before injecting."
            return
        }
        injectPhases(phases, placement: placement)
    }

    func submitEffortScore(_ score: Int) {
        lastEffortScore = score
        if !pendingEffortQueue.isEmpty {
            pendingEffortQueue[0].score = score
            pendingEffortQueue.removeFirst()
        }
        if let nextPrompt = pendingEffortQueue.first {
            postWorkoutDestination = .effortPrompt
            displayState = .ended
            lastCompletedWorkoutTitle = nextPrompt.phase.title
            lastCompletedWorkoutSubtitle = nextPrompt.phase.subtitle
        } else {
            postWorkoutDestination = .none
            displayState = .idle
            lastCompletedWorkoutTitle = nil
            lastCompletedWorkoutSubtitle = nil
        }
        statusMessage = "Effort logged as \(score)/10"
    }

    func dismissPostWorkoutFlow() {
        postWorkoutDestination = .none
        displayState = .idle
        lastCompletedWorkoutTitle = nil
        lastCompletedWorkoutSubtitle = nil
    }

    func prepareForNewWorkoutSelection() {
        postWorkoutDestination = .nextWorkoutPicker
        displayState = .idle
        statusMessage = "Choose your next workout."
    }

    private func startWorkout(
        title: String,
        subtitle: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType,
        resetRouteGuidance: Bool = true
    ) {
        displayState = .preparing
        activeTitle = title
        activeSubtitle = subtitle
        activeActivity = activity
        activeLocation = location
        postWorkoutDestination = .none
        lastCompletedWorkoutTitle = nil
        lastCompletedWorkoutSubtitle = nil
        workoutStartDate = nil
        elapsedTime = 0
        accumulatedElapsedTime = 0
        pauseStartedAt = nil
        pendingEndAction = .none
        lastHistorySampleElapsedTime = 0
        lastPowerSampleDate = nil
        hasAnnouncedCurrentPhaseReady = false
        clearPendingNextPhaseReminder()
        activeCompletionPrompt = nil
        dismissedCompletionPromptPhaseID = nil
        speedHistory = []
        paceHistory = []
        powerHistory = []
        elevationHistory = []
        cadenceHistory = []
        heartRateHistory = []
        splits = []
        powerZoneDurations = Array(repeating: 0, count: 5)
        currentEnergyKilocalories = 0
        currentElevationFeet = 0
        elevationGainFeet = 0
        currentSplitStartElapsedTime = 0
        currentSplitStartDistanceMeters = 0
        autoSplitLengthMeters = defaultSplitLength(for: activity)
        pacerTarget = defaultPacerTarget(for: activity)
        if resetRouteGuidance {
            routeName = nil
            routeTrailhead = nil
            routeCoordinates = []
        }

        Task {
            let ready: Bool
            if authorizationGranted {
                ready = true
            } else {
                ready = await requestAuthorizationIfNeeded()
            }
            authorizationGranted = ready
            guard ready else {
                displayState = .failed
                statusMessage = "Health permissions are required."
                return
            }

            do {
                try beginWorkoutSession(activity: activity, location: location)
            } catch {
                displayState = .failed
                statusMessage = "Could not start workout."
            }
        }
    }

    private func enqueueCurrentPhaseForEffort() {
        guard let currentPhase else { return }
        guard pendingEffortQueue.contains(where: { $0.phase.id == currentPhase.id }) == false else { return }
        pendingEffortQueue.append(
            CompletedPhaseEffort(
                id: UUID(),
                phase: currentPhase,
                completedAt: Date(),
                score: nil
            )
        )
    }

    private func injectPhases(_ phases: [WatchProgramPhasePayload], placement: QueueInsertionPlacement) {
        guard !phases.isEmpty else { return }

        if phaseQueue.isEmpty {
            phaseQueue = phases
            currentPhaseIndex = 0
            statusMessage = "Queue created with \(phases.count) stage\(phases.count == 1 ? "" : "s")."
            broadcastCompanionSnapshot()
            return
        }

        let insertionIndex: Int
        switch placement {
        case .next:
            insertionIndex = min(currentPhaseIndex + 1, phaseQueue.count)
        case .afterPlan:
            insertionIndex = phaseQueue.count
        }

        phaseQueue.insert(contentsOf: phases, at: insertionIndex)
        let head = phases.first?.title ?? "stage"
        statusMessage = placement == .next
            ? "\(head) queued after the current stage."
            : "\(head) queued after the current plan."
        broadcastCompanionSnapshot()
    }

    private func beginWorkoutSession(
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType
    ) throws {
        statusMessage = "Preparing workout..."

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = location

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        workoutSession = session
        workoutBuilder = builder
        metrics = []
        liveZoneDurations = Array(repeating: 0, count: 5)
        currentHeartRate = nil
        averageHeartRate = nil
        currentZoneIndex = nil
        splitCount = 0
        isMirroringToPhone = false
        lastZoneSampleDate = nil
        totalDistanceMeters = 0
        currentSpeedMetersPerSecond = nil
        currentPowerWatts = nil
        averagePowerWatts = nil
        currentCadence = nil
        flightsClimbed = nil
        strokeCount = nil
        strideMeters = nil
        groundContactTimeMilliseconds = nil
        verticalOscillationCentimeters = nil
        currentElevationFeet = 0
        elevationGainFeet = 0

        session.delegate = self
        builder.delegate = self

        let startDate = Date()
        workoutStartDate = startDate
        resetMicroStageTracking(at: startDate)
        session.prepare()
        session.startActivity(with: startDate)

        displayState = .running
        statusMessage = "Workout in progress"
        startElapsedTimer()
        rebuildMetrics()
        broadcastCompanionSnapshot()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await builder.beginCollection(at: startDate)
            } catch {
                self.displayState = .failed
                self.statusMessage = "Could not start workout."
                self.stopElapsedTimer()
                self.clearPersistedSession()
                return
            }

            self.isMirroringToPhone = await self.ensureCompanionMirroring()
            self.broadcastCompanionSnapshot()
            self.persistCurrentSession()
        }
    }

    private func handleCompanionControlCommand(_ rawValue: String) {
        guard let command = CompanionControlCommand(rawValue: rawValue) else { return }

        switch command {
        case .pause:
            pause()
        case .resume:
            resume()
        case .split:
            markSplit()
        case .stop:
            end()
        case .newWorkout:
            newWorkout()
        case .nextPhase:
            advanceToNextPhase()
        }
    }

    private func handleInjectedPhaseRequest(_ payload: [String: Any]) -> Bool {
        guard
            let title = payload[CompanionLaunchKeys.injectedTitle] as? String,
            let subtitle = payload[CompanionLaunchKeys.injectedSubtitle] as? String,
            let activityRawValue = payload[CompanionLaunchKeys.injectedActivityRawValue] as? Int,
            let locationRawValue = payload[CompanionLaunchKeys.injectedLocationRawValue] as? Int,
            let plannedMinutes = payload[CompanionLaunchKeys.injectedPlannedMinutes] as? Int,
            let placementRaw = payload[CompanionLaunchKeys.injectedPlacement] as? String,
            let placement = QueueInsertionPlacement(rawValue: placementRaw)
        else {
            return false
        }

        let phase = WatchProgramPhasePayload(
            id: UUID(),
            title: title,
            subtitle: subtitle,
            activityID: "inject-\(activityRawValue)-\(UUID().uuidString)",
            activityRawValue: UInt(activityRawValue),
            locationRawValue: locationRawValue,
            plannedMinutes: max(plannedMinutes, 1),
            objective: WatchPhaseObjectivePayload(kind: .time, targetValue: Double(max(plannedMinutes, 1)), label: "Time")
        )
        injectPhases([phase], placement: placement)
        return true
    }

    private func handleCompanionLaunchRequest(_ payload: [String: Any]) -> Bool {
        guard
            (payload[CompanionLaunchKeys.workoutStart] as? Bool) == true,
            let title = payload[CompanionLaunchKeys.title] as? String,
            let subtitle = payload[CompanionLaunchKeys.subtitle] as? String,
            let activityRawValue = payload[CompanionLaunchKeys.activityRawValue] as? Int
        else {
            return false
        }

        let activity = HKWorkoutActivityType(rawValue: UInt(activityRawValue)) ?? .running
        let locationRawValue = payload[CompanionLaunchKeys.locationRawValue] as? Int ?? HKWorkoutSessionLocationType.unknown.rawValue
        let location = HKWorkoutSessionLocationType(rawValue: locationRawValue) ?? .unknown
        routeName = payload[CompanionLaunchKeys.routeName] as? String
        if let latitude = payload[CompanionLaunchKeys.trailheadLatitude] as? Double,
           let longitude = payload[CompanionLaunchKeys.trailheadLongitude] as? Double {
            routeTrailhead = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            routeTrailhead = nil
        }
        routeCoordinates = (payload[CompanionLaunchKeys.routeCoordinates] as? [[Double]])?.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        } ?? []

        let phasePayloads = decodePhasePayloads(from: payload[CompanionLaunchKeys.phasePayloads] as? [[String: Any]])
        if (payload[CompanionLaunchKeys.openInWorkoutApp] as? Bool) == true {
            Task { @MainActor in
                await self.openInWorkoutApp(
                    title: title,
                    activity: activity,
                    location: location,
                    phases: phasePayloads
                )
            }
            return true
        }

        if !phasePayloads.isEmpty {
            phaseQueue = phasePayloads
            currentPhaseIndex = 0
            currentMicroStageIndex = 0
            pendingEffortQueue = []
        } else {
            phaseQueue = [
                WatchProgramPhasePayload(
                    id: UUID(),
                    title: title,
                    subtitle: subtitle,
                    activityID: "primary-\(activity.rawValue)",
                    activityRawValue: activity.rawValue,
                    locationRawValue: location.rawValue,
                    plannedMinutes: 30,
                    objective: WatchPhaseObjectivePayload(kind: .time, targetValue: 30, label: "Time")
                )
            ]
            currentPhaseIndex = 0
            currentMicroStageIndex = 0
            pendingEffortQueue = []
        }

        startWorkout(
            title: phaseQueue.first?.title ?? title,
            subtitle: phaseQueue.first?.subtitle ?? subtitle,
            activity: HKWorkoutActivityType(rawValue: phaseQueue.first?.activityRawValue ?? activity.rawValue) ?? activity,
            location: HKWorkoutSessionLocationType(rawValue: phaseQueue.first?.locationRawValue ?? location.rawValue) ?? location,
            resetRouteGuidance: false
        )
        return true
    }

    private func appendHistoryPoint(_ value: Double?, to series: inout [WatchWorkoutSeriesPoint], elapsedTime: TimeInterval) {
        guard let value, value.isFinite else { return }
        if let lastPoint = series.last, abs(lastPoint.elapsedTime - elapsedTime) < 10 {
            series[series.count - 1] = WatchWorkoutSeriesPoint(elapsedTime: elapsedTime, value: value)
        } else {
            series.append(WatchWorkoutSeriesPoint(elapsedTime: elapsedTime, value: value))
        }

        if series.count > 120 {
            series.removeFirst(series.count - 120)
        }
    }

    private func updateDerivedLiveSeries(elapsedTime: TimeInterval) {
        let elapsed = max(elapsedTime, 1)

        if let currentHeartRate {
            appendHistoryPoint(currentHeartRate, to: &heartRateHistory, elapsedTime: elapsed)
        }

        if let currentSpeedMetersPerSecond, currentSpeedMetersPerSecond > 0 {
            appendHistoryPoint(currentSpeedMetersPerSecond * 2.23694, to: &speedHistory, elapsedTime: elapsed)
            appendHistoryPoint(1609.344 / currentSpeedMetersPerSecond, to: &paceHistory, elapsedTime: elapsed)
        }

        if let currentPowerWatts {
            appendHistoryPoint(currentPowerWatts, to: &powerHistory, elapsedTime: elapsed)
        }

        if let currentCadence {
            appendHistoryPoint(currentCadence, to: &cadenceHistory, elapsedTime: elapsed)
        }

        let estimatedElevationFeet = max((flightsClimbed ?? 0) * 10, elevationGainFeet)
        currentElevationFeet = estimatedElevationFeet
        elevationGainFeet = max(elevationGainFeet, estimatedElevationFeet)
        appendHistoryPoint(currentElevationFeet, to: &elevationHistory, elapsedTime: elapsed)
    }

    private func appendSplitSnapshot(isAutomatic: Bool) {
        let splitElapsed = max(elapsedTime - currentSplitStartElapsedTime, 0)
        let splitDistance = max(totalDistanceMeters - currentSplitStartDistanceMeters, 0)
        guard splitElapsed > 0.5 || splitDistance > 1 else { return }

        splitCount += 1
        splits.append(
            WatchWorkoutSplit(
                index: splitCount,
                elapsedTime: elapsedTime,
                splitDuration: splitElapsed,
                splitDistanceMeters: splitDistance,
                averageHeartRate: averageHeartRate,
                averageSpeedMetersPerSecond: splitDistance > 0 ? splitDistance / max(splitElapsed, 1) : currentSpeedMetersPerSecond,
                averagePowerWatts: averagePowerWatts ?? currentPowerWatts,
                averageCadence: currentCadence
            )
        )

        currentSplitStartElapsedTime = elapsedTime
        currentSplitStartDistanceMeters = totalDistanceMeters

        if isAutomatic {
            statusMessage = "Auto split \(splitCount)"
        }
    }

    private func updateAutomaticSplitsIfNeeded() {
        guard let autoSplitLengthMeters, autoSplitLengthMeters > 0 else { return }
        while totalDistanceMeters - currentSplitStartDistanceMeters >= autoSplitLengthMeters {
            appendSplitSnapshot(isAutomatic: true)
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if authorizationGranted { return true }

        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .runningPower,
            .runningSpeed,
            .runningGroundContactTime,
            .runningStrideLength,
            .runningVerticalOscillation,
            .cyclingCadence,
            .cyclingPower,
            .flightsClimbed,
            .swimmingStrokeCount
        ].forEach { identifier in
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }

        let success = await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: readTypes) { success, _ in
                continuation.resume(returning: success)
            }
        }

        authorizationGranted = success
        return success
    }

    private func estimatedMaximumHeartRate() async -> Double {
        do {
            let components = try healthStore.dateOfBirthComponents()
            if let birthDate = components.date,
               let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year {
                return max(150, 211.0 - (0.64 * Double(age)))
            }
        } catch {
        }

        return 190
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.displayState == .running {
                    self.elapsedTime = self.currentElapsedTime(at: Date())
                    self.refreshPhaseSuggestionStatus()
                } else if self.displayState == .paused {
                    self.elapsedTime = self.accumulatedElapsedTime
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func currentElapsedTime(at date: Date) -> TimeInterval {
        if displayState == .paused || pauseStartedAt != nil {
            return accumulatedElapsedTime
        }

        guard let workoutStartDate else { return accumulatedElapsedTime }
        return accumulatedElapsedTime + max(0, date.timeIntervalSince(workoutStartDate))
    }

    private func currentSegmentElapsedTime(at date: Date) -> TimeInterval {
        if displayState == .paused || pauseStartedAt != nil {
            return accumulatedMicroStageElapsedTime
        }

        guard let microStageStartDate else { return accumulatedMicroStageElapsedTime }
        return accumulatedMicroStageElapsedTime + max(0, date.timeIntervalSince(microStageStartDate))
    }

    private func resetMicroStageTracking(at date: Date) {
        accumulatedMicroStageElapsedTime = 0
        microStageStartDate = date
        microStageStartDistanceMeters = totalDistanceMeters
        microStageStartEnergyKilocalories = currentEnergyKilocalories
        microStageStartZoneDurations = liveZoneDurations
    }

    private func currentSegmentObjectiveStatus() -> (summaryText: String, isComplete: Bool) {
        if let currentMicroStage {
            return microStageStatus(for: currentMicroStage, at: currentMicroStageIndex)
        }
        guard let currentPhase else { return ("", false) }
        return objectiveStatus(for: currentPhase, at: currentPhaseIndex)
    }

    private func advanceWithinCurrentPhaseIfNeeded() -> Bool {
        guard let currentPhase else { return false }
        guard nextMicroStage != nil else { return false }
        currentMicroStageIndex += 1
        resetMicroStageTracking(at: Date())
        hasAnnouncedCurrentPhaseReady = false
        activeCompletionPrompt = nil
        dismissedCompletionPromptPhaseID = currentPhase.id
        if let currentMicroStage {
            statusMessage = "Moved to \(currentMicroStage.title)."
        }
        broadcastCompanionSnapshot()
        return true
    }

    private func refreshPhaseSuggestionStatus() {
        guard displayState == .running else { return }
        guard let currentPhase else { return }
        let currentStatus = currentSegmentObjectiveStatus()
        guard currentStatus.isComplete else { return }
        if !hasAnnouncedCurrentPhaseReady {
            hasAnnouncedCurrentPhaseReady = true
            WKInterfaceDevice.current().play(.notification)
            if let nextPhase = nextPhase {
                scheduleNextPhaseReminder(for: nextPhase, currentPhase: currentPhase)
            }
        }
        if dismissedCompletionPromptPhaseID != currentPhase.id {
            activeCompletionPrompt = currentPhase
        }
        if let nextMicroStage {
            statusMessage = "Goal complete. Next stage ready: \(nextMicroStage.title)"
        } else if let nextPhase {
            statusMessage = "Goal complete. Next phase ready: \(nextPhase.title)"
        } else {
            statusMessage = "Goal complete for \(currentMicroStage?.title ?? currentPhase.title)"
        }
        broadcastCompanionSnapshot()
    }

    private func clearPendingNextPhaseReminder() {
        guard let nextPhaseReminderIdentifier else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [nextPhaseReminderIdentifier])
        self.nextPhaseReminderIdentifier = nil
    }

    private func scheduleNextPhaseReminder(
        for nextPhase: WatchProgramPhasePayload,
        currentPhase: WatchProgramPhasePayload
    ) {
        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            let isAuthorized: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                let granted = try? await center.requestAuthorization(options: [.alert, .sound])
                isAuthorized = granted == true
            default:
                isAuthorized = false
            }

            guard isAuthorized else { return }

            let identifier = "workout-next-phase-\(currentPhase.id.uuidString)"
            let content = UNMutableNotificationContent()
            content.title = "Next stage ready"
            content.body = "\(nextPhase.title) is ready to start. Planned \(nextPhase.plannedMinutes) min."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )

            do {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                try await center.add(request)
                await MainActor.run {
                    self.nextPhaseReminderIdentifier = identifier
                }
            } catch {
                await MainActor.run {
                    self.nextPhaseReminderIdentifier = nil
                }
            }
        }
    }

    private func rebuildMetrics() {
        guard let workoutBuilder else {
            metrics = []
            return
        }

        var cards: [WatchLiveMetric] = []
        let sampleElapsedTime = currentElapsedTime(at: Date())

        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let heartStats = workoutBuilder.statistics(for: heartRateType) {
            if let current = heartStats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                currentHeartRate = current
                currentZoneIndex = zoneIndex(for: current)
                cards.append(.init(id: "hr-current", title: "Current HR", valueText: "\(Int(current.rounded())) bpm", symbol: "heart.fill", tint: .red))
            }
            if let average = heartStats.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                averageHeartRate = average
                cards.append(.init(id: "hr-avg", title: "Avg HR", valueText: "\(Int(average.rounded())) bpm", symbol: "waveform.path.ecg", tint: .pink))
            }
        }

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let energy = workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
            currentEnergyKilocalories = energy
            cards.append(.init(id: "energy", title: "Energy", valueText: "\(Int(energy.rounded())) kcal", symbol: "flame.fill", tint: .orange))
        }

        if let distanceType = preferredDistanceType(),
           let distance = workoutBuilder.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) {
            totalDistanceMeters = distance
            let distanceValue = distance >= 1000
                ? String(format: "%.2f km", distance / 1000)
                : "\(Int(distance.rounded())) m"
            cards.append(.init(id: "distance", title: "Distance", valueText: distanceValue, symbol: "location.fill", tint: .green))
        }

        if let speedType = preferredSpeedType(),
           let speedStats = workoutBuilder.statistics(for: speedType) {
            if let current = speedStats.mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())) {
                currentSpeedMetersPerSecond = current
                cards.append(.init(id: "speed-current", title: "Speed", valueText: String(format: "%.1f km/h", current * 3.6), symbol: "speedometer", tint: .cyan))
            }
        }

        if let powerType = preferredPowerType(),
           let powerStats = workoutBuilder.statistics(for: powerType) {
            if let current = powerStats.mostRecentQuantity()?.doubleValue(for: .watt()) {
                currentPowerWatts = current
                cards.append(.init(id: "power-current", title: "Power", valueText: "\(Int(current.rounded())) W", symbol: "bolt.fill", tint: .yellow))
                let powerZone = powerZoneIndex(for: current)
                let now = Date()
                let sampleDate = lastPowerSampleDate ?? now
                let delta = max(0, min(now.timeIntervalSince(sampleDate), 15))
                powerZoneDurations[powerZone] += delta
                lastPowerSampleDate = now
            }
            if let average = powerStats.averageQuantity()?.doubleValue(for: .watt()) {
                averagePowerWatts = average
                cards.append(.init(id: "power-avg", title: "Avg Power", valueText: "\(Int(average.rounded())) W", symbol: "bolt.badge.clock.fill", tint: .yellow))
            }
        }

        if let cadenceType = preferredCadenceType(),
           let cadenceStats = workoutBuilder.statistics(for: cadenceType),
           let cadence = cadenceStats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            currentCadence = cadence
            cards.append(.init(id: "cadence", title: "Cadence", valueText: "\(Int(cadence.rounded())) rpm", symbol: "metronome.fill", tint: .mint))
        }

        if let strideType = HKQuantityType.quantityType(forIdentifier: .runningStrideLength),
           let stride = workoutBuilder.statistics(for: strideType)?.averageQuantity()?.doubleValue(for: .meter()) {
            strideMeters = stride
            cards.append(.init(id: "stride", title: "Stride", valueText: String(format: "%.2f m", stride), symbol: "ruler.fill", tint: .indigo))
        }

        if let gctType = HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime),
           let gct = workoutBuilder.statistics(for: gctType)?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)) {
            groundContactTimeMilliseconds = gct
            cards.append(.init(id: "gct", title: "Ground Contact", valueText: "\(Int(gct.rounded())) ms", symbol: "shoeprints.fill", tint: .brown))
        }

        if let voType = HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation),
           let oscillation = workoutBuilder.statistics(for: voType)?.averageQuantity()?.doubleValue(for: .meterUnit(with: .centi)) {
            verticalOscillationCentimeters = oscillation
            cards.append(.init(id: "vo", title: "Vertical Osc.", valueText: String(format: "%.1f cm", oscillation), symbol: "arrow.up.and.down.text.horizontal", tint: .purple))
        }

        if let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed),
           let flights = workoutBuilder.statistics(for: flightsType)?.sumQuantity()?.doubleValue(for: .count()) {
            flightsClimbed = flights
            cards.append(.init(id: "flights", title: "Flights", valueText: "\(Int(flights.rounded()))", symbol: "stairs", tint: .teal))
        }

        if let strokeType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount),
           let strokes = workoutBuilder.statistics(for: strokeType)?.sumQuantity()?.doubleValue(for: .count()) {
            strokeCount = strokes
            cards.append(.init(id: "strokes", title: "Stroke Count", valueText: "\(Int(strokes.rounded()))", symbol: "figure.pool.swim", tint: .blue))
        }

        metrics = cards
        if sampleElapsedTime - lastHistorySampleElapsedTime >= 8 || lastHistorySampleElapsedTime == 0 {
            updateDerivedLiveSeries(elapsedTime: sampleElapsedTime)
            lastHistorySampleElapsedTime = sampleElapsedTime
        }
        updateAutomaticSplitsIfNeeded()
        broadcastCompanionSnapshot()
    }

    private func broadcastCompanionSnapshot() {
        guard isMirroringToPhone, let workoutSession else { return }
        guard #available(watchOS 10.0, *) else { return }

        let payload = CompanionWorkoutSnapshotPayload(
            title: activeTitle ?? watchWorkoutDisplayName(activeActivity ?? .running),
            stateText: displayState.rawValue.capitalized,
            activityRawValue: activeActivity?.rawValue ?? HKWorkoutActivityType.running.rawValue,
            elapsedTime: elapsedTime,
            metrics: metrics.map {
                CompanionWorkoutMetricPayload(
                    id: $0.id,
                    title: $0.title,
                    valueText: $0.valueText,
                    symbol: $0.symbol,
                    tintName: companionTintName(for: $0.id)
                )
            },
            pageKinds: orderedWorkoutPages.map(\.rawValue),
            speedHistory: speedHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) },
            paceHistory: paceHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) },
            powerHistory: powerHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) },
            elevationHistory: elevationHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) },
            cadenceHistory: cadenceHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) },
            heartRateHistory: heartRateHistory.map { .init(elapsedTime: $0.elapsedTime, value: $0.value) },
            splits: splits.map {
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
            },
            heartRateZoneDurations: liveZoneDurations,
            powerZoneDurations: powerZoneDurations,
            totalDistanceMeters: totalDistanceMeters,
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
            currentPowerWatts: currentPowerWatts,
            averagePowerWatts: averagePowerWatts,
            currentCadence: currentCadence,
            currentElevationFeet: currentElevationFeet,
            elevationGainFeet: elevationGainFeet,
            pacerTarget: pacerTarget.map { .init(lowerBound: $0.lowerBound, upperBound: $0.upperBound, unitLabel: $0.unitLabel) },
            phaseQueue: phaseQueue.enumerated().map { index, phase in
                let status = objectiveStatus(for: phase, at: index)
                return CompanionWorkoutPhasePayload(
                    id: phase.id,
                    title: phase.title,
                    subtitle: phase.subtitle,
                    activityRawValue: phase.activityRawValue,
                    locationRawValue: phase.locationRawValue,
                    plannedMinutes: phase.plannedMinutes,
                    objectiveStatusText: status.summaryText,
                    isObjectiveComplete: status.isComplete
                )
            },
            currentPhaseIndex: currentPhaseIndex,
            stepQueue: currentMicroStages.enumerated().map { index, stage in
                let status = microStageStatus(for: stage, at: index)
                return CompanionWorkoutMicroStagePayload(
                    id: stage.id,
                    title: stage.title,
                    notes: stage.notes,
                    plannedMinutes: stage.plannedMinutes,
                    repeats: stage.repeats,
                    objectiveStatusText: status.summaryText,
                    isObjectiveComplete: status.isComplete
                )
            },
            currentMicroStageIndex: currentMicroStageIndex,
            effortPrompt: currentEffortPromptPhase.map {
                CompanionWorkoutEffortPromptPayload(
                    phaseID: $0.phase.id,
                    title: $0.phase.title,
                    subtitle: $0.phase.subtitle
                )
            }
        )

        Task {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? await workoutSession.sendToRemoteWorkoutSession(data: data)
        }
    }

    func objectiveStatus(for phase: WatchProgramPhasePayload, at index: Int) -> (summaryText: String, isComplete: Bool) {
        if index == currentPhaseIndex, phase.microStages?.isEmpty == false {
            let currentTitle = currentMicroStage?.title ?? phase.title
            let status = currentSegmentObjectiveStatus()
            return ("\(currentTitle) • \(status.summaryText)", status.isComplete)
        }

        let objective = phase.objective ?? WatchPhaseObjectivePayload(
            kind: .time,
            targetValue: Double(max(phase.plannedMinutes, 1))
        )

        if index < currentPhaseIndex {
            return ("Completed", true)
        }

        if index > currentPhaseIndex {
            return (upcomingObjectiveText(for: phase, objective: objective), false)
        }

        switch objective.kind {
        case .time:
            let targetSeconds = max(objective.targetValue, 1) * 60
            let remaining = max(targetSeconds - elapsedTime, 0)
            return ("\(shortWorkoutElapsedString(remaining)) left", remaining <= 0)
        case .distance:
            let currentKilometers = totalDistanceMeters / 1000
            let targetKilometers = max(objective.targetValue, 0.1)
            return (String(format: "%.1f / %.1f km", currentKilometers, targetKilometers), currentKilometers >= targetKilometers)
        case .energy:
            let targetKilocalories = max(objective.targetValue, 1)
            return ("\(Int(currentEnergyKilocalories.rounded())) / \(Int(targetKilocalories.rounded())) kcal", currentEnergyKilocalories >= targetKilocalories)
        case .heartRateZone:
            let zoneNumber = Int(objective.secondaryValue ?? 3)
            let zoneSeconds = liveZoneDurations[max(0, min(zoneNumber - 1, liveZoneDurations.count - 1))] ?? 0
            let currentMinutes = zoneSeconds / 60
            let targetMinutes = max(objective.targetValue, 1)
            return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min in Z\(zoneNumber)", currentMinutes >= targetMinutes)
        case .pacer:
            let currentMinutes = elapsedTime / 60
            let targetMinutes = max(objective.targetValue, 1)
            return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min in range", currentMinutes >= targetMinutes)
        case .routeDistance:
            let currentKilometers = totalDistanceMeters / 1000
            let targetKilometers = max(objective.targetValue, 0.1)
            return (String(format: "%.1f / %.1f km route", currentKilometers, targetKilometers), currentKilometers >= targetKilometers)
        }
    }

    func microStageStatus(for stage: WatchProgramMicroStagePayload, at index: Int) -> (summaryText: String, isComplete: Bool) {
        if index < currentMicroStageIndex {
            return ("Completed", true)
        }

        if index > currentMicroStageIndex {
            return (upcomingMicroStageText(for: stage), false)
        }

        let elapsedTime = currentSegmentElapsedTime(at: Date())
        let distanceDeltaKilometers = max(totalDistanceMeters - microStageStartDistanceMeters, 0) / 1000
        let energyDelta = max(currentEnergyKilocalories - microStageStartEnergyKilocalories, 0)

        switch stage.objective.kind {
        case .time:
            let targetSeconds = max(stage.objective.targetValue, 1) * 60
            let remaining = max(targetSeconds - elapsedTime, 0)
            return ("\(shortWorkoutElapsedString(remaining)) left", remaining <= 0)
        case .distance:
            let targetKilometers = max(stage.objective.targetValue, 0.1)
            return (String(format: "%.1f / %.1f km", distanceDeltaKilometers, targetKilometers), distanceDeltaKilometers >= targetKilometers)
        case .energy:
            let targetKilocalories = max(stage.objective.targetValue, 1)
            return ("\(Int(energyDelta.rounded())) / \(Int(targetKilocalories.rounded())) kcal", energyDelta >= targetKilocalories)
        case .heartRateZone:
            let zoneNumber = Int(stage.objective.secondaryValue ?? 3)
            let priorZoneSeconds = microStageStartZoneDurations[max(0, zoneNumber - 1)] ?? 0
            let currentZoneSeconds = liveZoneDurations[max(0, zoneNumber - 1)] ?? 0
            let currentMinutes = max(currentZoneSeconds - priorZoneSeconds, 0) / 60
            let targetMinutes = max(stage.objective.targetValue, 1)
            return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min in Z\(zoneNumber)", currentMinutes >= targetMinutes)
        case .pacer:
            let targetMinutes = max(stage.objective.targetValue, 1)
            let currentMinutes = elapsedTime / 60
            let label = stage.objective.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let label, !label.isEmpty {
                return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min at \(label)", currentMinutes >= targetMinutes)
            }
            return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min in range", currentMinutes >= targetMinutes)
        case .routeDistance:
            let targetKilometers = max(stage.objective.targetValue, 0.1)
            return (String(format: "%.1f / %.1f km route", distanceDeltaKilometers, targetKilometers), distanceDeltaKilometers >= targetKilometers)
        }
    }

    private func upcomingObjectiveText(for phase: WatchProgramPhasePayload, objective: WatchPhaseObjectivePayload) -> String {
        switch objective.kind {
        case .time:
            return "\(phase.plannedMinutes) min planned"
        case .distance:
            return String(format: "Goal %.1f km", objective.targetValue)
        case .energy:
            return "Goal \(Int(objective.targetValue.rounded())) kcal"
        case .heartRateZone:
            return "Goal \(Int(objective.targetValue.rounded())) min in Z\(Int(objective.secondaryValue ?? 3))"
        case .pacer:
            return "Goal \(Int(objective.targetValue.rounded())) min in range"
        case .routeDistance:
            return String(format: "Goal %.1f km route", objective.targetValue)
        }
    }

    private func upcomingMicroStageText(for stage: WatchProgramMicroStagePayload) -> String {
        switch stage.objective.kind {
        case .time:
            return "\(stage.plannedMinutes) min planned"
        case .distance:
            return String(format: "Goal %.1f km", stage.objective.targetValue)
        case .energy:
            return "Goal \(Int(stage.objective.targetValue.rounded())) kcal"
        case .heartRateZone:
            return "Goal \(Int(stage.objective.targetValue.rounded())) min in Z\(Int(stage.objective.secondaryValue ?? 3))"
        case .pacer:
            return stage.objective.label?.isEmpty == false
                ? "Goal \(Int(stage.objective.targetValue.rounded())) min at \(stage.objective.label!)"
                : "Goal \(Int(stage.objective.targetValue.rounded())) min in range"
        case .routeDistance:
            return String(format: "Goal %.1f km route", stage.objective.targetValue)
        }
    }

    private func ensureCompanionMirroring() async -> Bool {
        guard let workoutSession else { return false }
        guard #available(watchOS 10.0, *) else { return false }
        if isMirroringToPhone { return true }

        do {
            try await workoutSession.startMirroringToCompanionDevice()
            isMirroringToPhone = true
            return true
        } catch {
            isMirroringToPhone = false
            return false
        }
    }

    private func requestCompanionPresentation() async -> Bool {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return false }

        let session = WCSession.default
        guard session.activationState == .activated else {
            session.activate()
            return false
        }

        if session.isReachable {
            return await withCheckedContinuation { continuation in
                session.sendMessage(["request": "showLiveWorkout"]) { reply in
                    let success = (reply["accepted"] as? Bool) ?? false
                    continuation.resume(returning: success)
                } errorHandler: { _ in
                    continuation.resume(returning: false)
                }
            }
        }

        session.transferUserInfo(["request": "showLiveWorkout"])
        return false
#else
        return false
#endif
    }

    private func sendCompanionLifecycleUpdate(state: String, reason: String? = nil) {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
        }

        var payload: [String: Any] = [
            CompanionLifecycleKeys.workoutLifecycle: state
        ]
        if let reason, !reason.isEmpty {
            payload[CompanionLifecycleKeys.reason] = reason
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        session.transferUserInfo(payload)
#endif
    }

    private func persistCurrentSession() {
        guard isSessionActive || workoutSession != nil else { return }
        let payload = WatchPersistedWorkoutSession(
            displayStateRawValue: displayState.rawValue,
            activeTitle: activeTitle,
            activeSubtitle: activeSubtitle,
            activeActivityRawValue: activeActivity?.rawValue,
            activeLocationRawValue: activeLocation.rawValue,
            workoutStartDate: workoutStartDate,
            accumulatedElapsedTime: accumulatedElapsedTime,
            pauseStartedAt: pauseStartedAt,
            phaseQueue: phaseQueue,
            currentPhaseIndex: currentPhaseIndex,
            currentMicroStageIndex: currentMicroStageIndex,
            routeName: routeName,
            routeTrailhead: routeTrailhead.map { WatchPlanCoordinatePayload(latitude: $0.latitude, longitude: $0.longitude) },
            routeCoordinates: routeCoordinates.map { WatchPlanCoordinatePayload(latitude: $0.latitude, longitude: $0.longitude) }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func restorePersistedSessionIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let payload = try? JSONDecoder().decode(WatchPersistedWorkoutSession.self, from: data) else {
            return
        }

        displayState = SessionDisplayState(rawValue: payload.displayStateRawValue) ?? .idle
        activeTitle = payload.activeTitle
        activeSubtitle = payload.activeSubtitle
        if let activeActivityRawValue = payload.activeActivityRawValue {
            activeActivity = HKWorkoutActivityType(rawValue: activeActivityRawValue)
        } else {
            activeActivity = nil
        }
        activeLocation = HKWorkoutSessionLocationType(rawValue: payload.activeLocationRawValue) ?? .unknown
        workoutStartDate = payload.workoutStartDate
        accumulatedElapsedTime = payload.accumulatedElapsedTime
        pauseStartedAt = payload.pauseStartedAt
        phaseQueue = payload.phaseQueue
        currentPhaseIndex = payload.currentPhaseIndex
        currentMicroStageIndex = payload.currentMicroStageIndex
        routeName = payload.routeName
        routeTrailhead = payload.routeTrailhead.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        routeCoordinates = payload.routeCoordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    private func recoverActiveWorkoutSessionIfNeeded() async {
        guard workoutSession == nil else { return }
        let recoveredSession = await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession(completion: { session, _ in
                continuation.resume(returning: session)
            })
        }
        guard let recoveredSession else {
            if !isSessionActive {
                clearPersistedSession()
            }
            return
        }
        attachRecoveredWorkoutSession(recoveredSession)
    }

    private func attachRecoveredWorkoutSession(_ session: HKWorkoutSession) {
        workoutSession = session
        workoutBuilder = session.associatedWorkoutBuilder()
        workoutBuilder?.delegate = self
        session.delegate = self
        activeActivity = session.workoutConfiguration.activityType
        activeLocation = session.workoutConfiguration.locationType
        if activeTitle == nil {
            activeTitle = watchWorkoutDisplayName(activeActivity ?? .running)
        }
        if workoutStartDate == nil {
            workoutStartDate = Date()
        }
        displayState = session.state == .paused ? .paused : .running
        statusMessage = session.state == .paused ? "Recovered paused workout" : "Recovered active workout"
        if session.state == .running {
            startElapsedTimer()
        }
        rebuildMetrics()
        Task { @MainActor in
            self.isMirroringToPhone = await self.ensureCompanionMirroring()
            self.broadcastCompanionSnapshot()
            self.persistCurrentSession()
        }
    }

    private func decodePhasePayloads(from payloads: [[String: Any]]?) -> [WatchProgramPhasePayload] {
        guard let payloads else { return [] }
        return payloads.compactMap { phasePayload in
            guard let title = phasePayload["title"] as? String,
                  let subtitle = phasePayload["subtitle"] as? String,
                  let activityID = phasePayload["activityID"] as? String,
                  let activityRawValue = phasePayload["activityRawValue"] as? Int,
                  let locationRawValue = phasePayload["locationRawValue"] as? Int,
                  let plannedMinutes = phasePayload["plannedMinutes"] as? Int else {
                return nil
            }

            let stagePayloads = (phasePayload["microStages"] as? [[String: Any]] ?? []).compactMap { stagePayload -> WatchProgramMicroStagePayload? in
                guard let title = stagePayload["title"] as? String,
                      let notes = stagePayload["notes"] as? String,
                      let goal = stagePayload["goal"] as? String,
                      let plannedMinutes = stagePayload["plannedMinutes"] as? Int,
                      let repeats = stagePayload["repeats"] as? Int else {
                    return nil
                }
                let targetValueText = stagePayload["targetValueText"] as? String ?? ""
                return WatchProgramMicroStagePayload(
                    id: UUID(uuidString: stagePayload["id"] as? String ?? "") ?? UUID(),
                    title: title,
                    notes: notes,
                    plannedMinutes: plannedMinutes,
                    repeats: repeats,
                    repeatSetLabel: stagePayload["repeatSetLabel"] as? String,
                    targetBehaviorRawValue: stagePayload["targetBehavior"] as? String,
                    circuitGroupID: UUID(uuidString: stagePayload["circuitGroupID"] as? String ?? ""),
                    objective: workoutObjective(
                        goalRawValue: goal,
                        plannedMinutes: plannedMinutes,
                        targetValueText: targetValueText
                    )
                )
            }

            let circuitGroups = (phasePayload["circuitGroups"] as? [[String: Any]] ?? []).compactMap { payload -> WatchProgramCircuitGroupPayload? in
                guard let idString = payload["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let title = payload["title"] as? String,
                      let repeats = payload["repeats"] as? Int else {
                    return nil
                }
                return WatchProgramCircuitGroupPayload(id: id, title: title, repeats: repeats)
            }

            return WatchProgramPhasePayload(
                id: UUID(uuidString: phasePayload["id"] as? String ?? "") ?? UUID(),
                title: title,
                subtitle: subtitle,
                activityID: activityID,
                activityRawValue: UInt(activityRawValue),
                locationRawValue: locationRawValue,
                plannedMinutes: plannedMinutes,
                objective: WatchPhaseObjectivePayload(kind: .time, targetValue: Double(max(plannedMinutes, 1)), label: "Time"),
                microStages: stagePayloads.isEmpty ? nil : stagePayloads,
                circuitGroups: circuitGroups.isEmpty ? nil : circuitGroups
            )
        }
    }

    private func workoutObjective(
        goalRawValue: String,
        plannedMinutes: Int,
        targetValueText: String
    ) -> WatchPhaseObjectivePayload {
        switch goalRawValue {
        case "distance":
            return WatchPhaseObjectivePayload(kind: .distance, targetValue: max(targetValueText.firstNumberValue ?? 1, 0.1), label: targetValueText)
        case "energy":
            return WatchPhaseObjectivePayload(kind: .energy, targetValue: max(targetValueText.firstNumberValue ?? Double(max(plannedMinutes * 8, 40)), 1), label: targetValueText)
        case "heartRateZone":
            return WatchPhaseObjectivePayload(kind: .heartRateZone, targetValue: Double(max(plannedMinutes, 1)), secondaryValue: targetValueText.firstNumberValue ?? 3, label: targetValueText)
        case "power", "pace", "speed", "cadence":
            return WatchPhaseObjectivePayload(kind: .pacer, targetValue: Double(max(plannedMinutes, 1)), label: targetValueText.isEmpty ? goalRawValue : targetValueText)
        default:
            return WatchPhaseObjectivePayload(kind: .time, targetValue: Double(max(plannedMinutes, 1)), label: "Time")
        }
    }

    private func openInWorkoutApp(
        title: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType,
        phases: [WatchProgramPhasePayload]
    ) async {
        guard let workoutPlan = workoutPlanForWorkoutApp(title: title, activity: activity, location: location, phases: phases) else {
            statusMessage = "Workout app handoff needs a single activity workout."
            return
        }

        do {
            try await workoutPlan.openInWorkoutApp()
            statusMessage = "Opened in Apple Workout."
        } catch {
            statusMessage = "Could not open Apple Workout."
        }
    }

    private func workoutPlanForWorkoutApp(
        title: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType,
        phases: [WatchProgramPhasePayload]
    ) -> WorkoutPlan? {
        let resolvedPhases = phases.isEmpty ? currentPhase.map { [$0] } ?? [] : phases
        guard let primaryPhase = resolvedPhases.first else { return nil }

        guard resolvedPhases.allSatisfy({
            HKWorkoutActivityType(rawValue: $0.activityRawValue) == activity &&
            HKWorkoutSessionLocationType(rawValue: $0.locationRawValue) == location
        }) else {
            return nil
        }

        let microStages = resolvedPhases.flatMap { workoutKitMicroStages(from: $0) }
        if microStages.isEmpty {
            let workout = SingleGoalWorkout(
                activity: activity,
                location: location,
                goal: .time(Double(max(primaryPhase.plannedMinutes, 1)), .minutes)
            )
            return WorkoutPlan(.goal(workout))
        }

        return WorkoutPlan(
            .custom(
                customWorkoutForWorkoutApp(
                    title: title,
                    activity: activity,
                    location: location,
                    microStages: microStages
                )
            )
        )
    }

    private func customWorkoutForWorkoutApp(
        title: String,
        activity: HKWorkoutActivityType,
        location: HKWorkoutSessionLocationType,
        microStages: [WatchProgramMicroStagePayload]
    ) -> CustomWorkout {
        let warmup = microStages.first(where: { $0.title.localizedCaseInsensitiveContains("warm") })
        let cooldown = microStages.last(where: { $0.title.localizedCaseInsensitiveContains("cool") })
        let mainStages = microStages.filter { stage in
            stage.id != warmup?.id && stage.id != cooldown?.id
        }

        var blocks: [IntervalBlock] = []
        var index = 0
        while index < mainStages.count {
            let stage = mainStages[index]
            let repeatLabel = stage.repeatSetLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let circuitKey = stage.circuitGroupID?.uuidString ?? repeatLabel
            var groupedStages = [stage]
            if !circuitKey.isEmpty {
                var nextIndex = index + 1
                while nextIndex < mainStages.count,
                      (mainStages[nextIndex].circuitGroupID?.uuidString ?? mainStages[nextIndex].repeatSetLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == circuitKey,
                      mainStages[nextIndex].repeats == stage.repeats {
                    groupedStages.append(mainStages[nextIndex])
                    nextIndex += 1
                }
                index = nextIndex
            } else {
                index += 1
            }

            let steps = groupedStages.map { groupedStage in
                IntervalStep(groupedStage.title.localizedCaseInsensitiveContains("recovery") || groupedStage.title.localizedCaseInsensitiveContains("reset") || groupedStage.title.localizedCaseInsensitiveContains("settle") ? .recovery : .work,
                             step: workoutStep(for: groupedStage))
            }
            blocks.append(IntervalBlock(steps: steps, iterations: max(stage.repeats, 1)))
        }

        return CustomWorkout(
            activity: activity,
            location: location,
            displayName: title,
            warmup: warmup.map(workoutStep(for:)),
            blocks: blocks,
            cooldown: cooldown.map(workoutStep(for:))
        )
    }

    private func workoutKitMicroStages(from phase: WatchProgramPhasePayload) -> [WatchProgramMicroStagePayload] {
        if let microStages = phase.microStages, !microStages.isEmpty {
            return microStages
        }

        let objective = phase.objective ?? WatchPhaseObjectivePayload(
            kind: .time,
            targetValue: Double(max(phase.plannedMinutes, 1)),
            label: "Time"
        )
        return [
            WatchProgramMicroStagePayload(
                id: phase.id,
                title: phase.title,
                notes: phase.subtitle,
                plannedMinutes: max(phase.plannedMinutes, 1),
                repeats: 1,
                repeatSetLabel: nil,
                targetBehaviorRawValue: nil,
                circuitGroupID: nil,
                objective: objective
            )
        ]
    }

    private func workoutStep(for stage: WatchProgramMicroStagePayload) -> WorkoutStep {
        WorkoutStep(goal: workoutGoal(for: stage), alert: workoutAlert(for: stage), displayName: stage.title)
    }

    private func workoutGoal(for stage: WatchProgramMicroStagePayload) -> WorkoutGoal {
        switch stage.objective.kind {
        case .distance, .routeDistance:
            return .distance(max(stage.objective.targetValue, 0.1), .kilometers)
        case .energy:
            return .energy(max(stage.objective.targetValue, 1), .kilocalories)
        case .time, .heartRateZone, .pacer:
            return .time(Double(max(stage.plannedMinutes, 1)), .minutes)
        }
    }

    private func workoutAlert(for stage: WatchProgramMicroStagePayload) -> (any WorkoutAlert)? {
        switch stage.objective.kind {
        case .heartRateZone:
            return .heartRate(zone: Int(stage.objective.secondaryValue ?? 3))
        case .pacer:
            if let range = (stage.objective.label ?? "").numberRange {
                return .power(range.lowerBound...range.upperBound, unit: .watts)
            }
            return nil
        default:
            return nil
        }
    }

    private func zoneIndex(for heartRate: Double) -> Int {
        let ratio = heartRate / max(estimatedMaxHeartRate, 1)
        switch ratio {
        case ..<0.60:
            return 0
        case ..<0.70:
            return 1
        case ..<0.80:
            return 2
        case ..<0.90:
            return 3
        default:
            return 4
        }
    }

    private func preferredDistanceType() -> HKQuantityType? {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming
        ]
        return identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:)).first {
            workoutBuilder?.statistics(for: $0) != nil
        }
    }

    private func preferredSpeedType() -> HKQuantityType? {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .runningSpeed,
            .walkingSpeed
        ]
        return identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:)).first {
            workoutBuilder?.statistics(for: $0) != nil
        }
    }

    private func preferredPowerType() -> HKQuantityType? {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .cyclingPower,
            .runningPower
        ]
        return identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:)).first {
            workoutBuilder?.statistics(for: $0) != nil
        }
    }

    private func preferredCadenceType() -> HKQuantityType? {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .cyclingCadence
        ]
        return identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:)).first {
            workoutBuilder?.statistics(for: $0) != nil
        }
    }

    private func powerZoneIndex(for power: Double) -> Int {
        let referencePower: Double

        switch activeActivity {
        case .some(.cycling):
            referencePower = 240
        case .some(.running):
            referencePower = 280
        default:
            referencePower = 220
        }

        let ratio = power / max(referencePower, 1)
        switch ratio {
        case ..<0.60:
            return 0
        case ..<0.75:
            return 1
        case ..<0.90:
            return 2
        case ..<1.05:
            return 3
        default:
            return 4
        }
    }

    private func defaultSplitLength(for activity: HKWorkoutActivityType) -> Double? {
        switch activity {
        case .running, .walking, .hiking:
            return 1609.344
        case .cycling:
            return 5000
        case .swimming:
            return 100
        default:
            return nil
        }
    }

    private func defaultPacerTarget(for activity: HKWorkoutActivityType) -> WatchPacerTarget? {
        switch activity {
        case .running, .walking, .hiking:
            return WatchPacerTarget(lowerBound: 8 * 60 + 35, upperBound: 9 * 60 + 5, unitLabel: "PACE")
        case .cycling:
            return WatchPacerTarget(lowerBound: 15, upperBound: 19, unitLabel: "MPH")
        case .swimming:
            return WatchPacerTarget(lowerBound: 95, upperBound: 115, unitLabel: "/100M")
        default:
            return nil
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                if fromState == .paused, pauseStartedAt != nil {
                    pauseStartedAt = nil
                    workoutStartDate = date
                } else if workoutStartDate == nil {
                    workoutStartDate = date
                }
                displayState = .running
                statusMessage = "Workout in progress"
                broadcastCompanionSnapshot()
                persistCurrentSession()
            case .paused:
                accumulatedElapsedTime = currentElapsedTime(at: date)
                pauseStartedAt = date
                elapsedTime = accumulatedElapsedTime
                displayState = .paused
                statusMessage = "Workout paused"
                broadcastCompanionSnapshot()
                persistCurrentSession()
            case .ended:
                elapsedTime = currentElapsedTime(at: date)
                displayState = .ended
                statusMessage = "Workout ended"
                broadcastCompanionSnapshot()
                sendCompanionLifecycleUpdate(state: "ended", reason: "Apple Watch workout finished.")
                stopElapsedTimer()
                if let workoutBuilder {
                    try? await workoutBuilder.endCollection(at: date)
                    try? await workoutBuilder.finishWorkout()
                }
                let completedTitle = self.activeTitle
                let completedSubtitle = self.activeSubtitle
                self.workoutSession = nil
                self.workoutBuilder = nil
                self.activeActivity = nil
                self.activeLocation = .unknown
                self.lastZoneSampleDate = nil
                self.currentSpeedMetersPerSecond = nil
                self.isMirroringToPhone = false
                self.workoutStartDate = nil
                self.pauseStartedAt = nil
                self.accumulatedElapsedTime = 0
                self.lastCompletedWorkoutTitle = completedTitle
                self.lastCompletedWorkoutSubtitle = completedSubtitle
                switch self.pendingEndAction {
                case .promptEffort:
                    if let nextPrompt = self.pendingEffortQueue.first {
                        self.lastCompletedWorkoutTitle = nextPrompt.phase.title
                        self.lastCompletedWorkoutSubtitle = nextPrompt.phase.subtitle
                        self.postWorkoutDestination = .effortPrompt
                    } else {
                        self.postWorkoutDestination = .none
                        self.displayState = .idle
                    }
                case .startAnotherWorkout:
                    self.postWorkoutDestination = .nextWorkoutPicker
                case .advancePhase:
                    self.currentPhaseIndex = min(self.currentPhaseIndex + 1, max(self.phaseQueue.count - 1, 0))
                    self.currentMicroStageIndex = 0
                    if let nextPhase = self.currentPhase {
                        self.startWorkout(
                            title: nextPhase.title,
                            subtitle: nextPhase.subtitle,
                            activity: HKWorkoutActivityType(rawValue: nextPhase.activityRawValue) ?? .running,
                            location: HKWorkoutSessionLocationType(rawValue: nextPhase.locationRawValue) ?? .unknown,
                            resetRouteGuidance: false
                        )
                    } else if let nextPrompt = self.pendingEffortQueue.first {
                        self.lastCompletedWorkoutTitle = nextPrompt.phase.title
                        self.lastCompletedWorkoutSubtitle = nextPrompt.phase.subtitle
                        self.postWorkoutDestination = .effortPrompt
                    } else {
                        self.postWorkoutDestination = .none
                        self.displayState = .idle
                    }
                case .none:
                    self.postWorkoutDestination = .none
                    self.displayState = .idle
                }
                self.pendingEndAction = .none
                self.clearPersistedSession()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            displayState = .failed
            statusMessage = "Workout failed"
            broadcastCompanionSnapshot()
            sendCompanionLifecycleUpdate(state: "failed", reason: "Apple Watch workout ended unexpectedly.")
            stopElapsedTimer()
            isMirroringToPhone = false
            pauseStartedAt = nil
            accumulatedElapsedTime = 0
            persistCurrentSession()
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            if let currentHeartRate {
                let now = Date()
                let sampleDate = lastZoneSampleDate ?? now
                let delta = max(0, min(now.timeIntervalSince(sampleDate), 15))
                liveZoneDurations[zoneIndex(for: currentHeartRate)] += delta
                lastZoneSampleDate = now
            }
            rebuildMetrics()
            persistCurrentSession()
        }
    }
}

#if canImport(WatchConnectivity)
extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) { }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void
    ) {
        Task { @MainActor in
            if let command = message["workoutControl"] as? String {
                self.handleCompanionControlCommand(command)
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if let effortScore = message[CompanionLifecycleKeys.effortScore] as? Int {
                self.submitEffortScore(effortScore)
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if self.handleInjectedPhaseRequest(message) {
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if self.handleCompanionLaunchRequest(message) {
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else {
                replyHandler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        Task { @MainActor in
            if let command = userInfo["workoutControl"] as? String {
                self.handleCompanionControlCommand(command)
            } else if let effortScore = userInfo[CompanionLifecycleKeys.effortScore] as? Int {
                self.submitEffortScore(effortScore)
            } else if self.handleInjectedPhaseRequest(userInfo) {
                return
            } else {
                _ = self.handleCompanionLaunchRequest(userInfo)
            }
        }
    }
}
#endif

@MainActor
extension WatchDashboardStore {
    var wakeSuggestionText: String {
        if sleepDebtHours > 2 {
            return "You are carrying meaningful sleep debt. Try protecting tonight's bedtime and trim evening intensity."
        }
        if sleepConsistency < 75 {
            return "Your schedule is drifting. A steadier bedtime should improve recovery faster than pushing for more load."
        }
        return "Sleep is trending well. Keep the same wind-down routine and use the wake timer to protect consistency."
    }
}

@MainActor
private final class WatchWorkoutTabPreferences {
    private let defaults = UserDefaults.standard
    private let storageKey = "watch.workout.tabPreferences"

    func orderedPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        let defaultPages = Self.defaultPages(for: activity)
        guard
            let data = defaults.data(forKey: storageKey),
            let stored = try? JSONDecoder().decode([String: [String]].self, from: data),
            let rawPages = stored[activity.preferenceKey]
        else {
            return defaultPages
        }

        let decoded = rawPages.compactMap(WatchWorkoutPageKind.init(rawValue:))
        let sanitized = decoded.filter(defaultPages.contains)
        let missing = defaultPages.filter { !sanitized.contains($0) }
        return sanitized + missing
    }

    func setOrderedPages(_ pages: [WatchWorkoutPageKind], for activity: HKWorkoutActivityType) {
        var stored: [String: [String]] = [:]
        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        {
            stored = decoded
        }

        stored[activity.preferenceKey] = pages.map(\.rawValue)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func defaultPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        switch activity {
        case .cycling:
            return [.metricsPrimary, .metricsSecondary, .heartRateZones, .splits, .elevationGraph, .powerGraph, .powerZones, .pacer, .map]
        case .running, .walking, .hiking:
            return [.metricsPrimary, .metricsSecondary, .heartRateZones, .segments, .splits, .elevationGraph, .pacer, .map]
        case .swimming:
            return [.metricsPrimary, .heartRateZones, .splits, .segments]
        default:
            return [.metricsPrimary, .metricsSecondary, .heartRateZones, .splits, .map]
        }
    }
}

private func watchWorkoutDisplayName(_ activityType: HKWorkoutActivityType) -> String {
    switch activityType {
    case .running:
        return "Running"
    case .walking:
        return "Walking"
    case .cycling:
        return "Cycling"
    case .swimming:
        return "Swimming"
    case .traditionalStrengthTraining, .functionalStrengthTraining:
        return "Strength"
    case .highIntensityIntervalTraining:
        return "HIIT"
    case .yoga:
        return "Yoga"
    case .hiking:
        return "Hiking"
    default:
        return "Workout"
    }
}

private func companionTintName(for metricID: String) -> String {
    switch metricID {
    case let id where id.contains("hr"):
        return "red"
    case let id where id.contains("energy"):
        return "orange"
    case let id where id.contains("distance"):
        return "green"
    case let id where id.contains("speed"):
        return "cyan"
    case let id where id.contains("power"):
        return "yellow"
    case let id where id.contains("cadence"):
        return "mint"
    case let id where id.contains("stride"):
        return "indigo"
    case let id where id.contains("gct"):
        return "brown"
    case let id where id.contains("vo"):
        return "purple"
    case let id where id.contains("flights"):
        return "teal"
    case let id where id.contains("strokes"):
        return "blue"
    default:
        return "white"
    }
}

private func shortWorkoutElapsedString(_ elapsed: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = elapsed >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: elapsed) ?? "00:00"
}

private extension HKWorkoutActivityType {
    var preferenceKey: String {
        String(rawValue)
    }
}

private extension String {
    var firstNumberValue: Double? {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ")
        var value: Double = 0
        return scanner.scanDouble(&value) ? value : nil
    }

    var numberRange: ClosedRange<Double>? {
        let numbers = components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap { Double($0) }
        guard numbers.count >= 2 else { return nil }
        let lower = min(numbers[0], numbers[1])
        let upper = max(numbers[0], numbers[1])
        return lower...upper
    }
}
