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
    let currentRepeatIteration: Int
    let accumulatedQualifiedObjectiveTime: TimeInterval
    let routeName: String?
    let routeTrailhead: WatchPlanCoordinatePayload?
    let routeCoordinates: [WatchPlanCoordinatePayload]

    private enum CodingKeys: String, CodingKey {
        case displayStateRawValue
        case activeTitle
        case activeSubtitle
        case activeActivityRawValue
        case activeLocationRawValue
        case workoutStartDate
        case accumulatedElapsedTime
        case pauseStartedAt
        case phaseQueue
        case currentPhaseIndex
        case currentMicroStageIndex
        case currentRepeatIteration
        case accumulatedQualifiedObjectiveTime
        case routeName
        case routeTrailhead
        case routeCoordinates
    }

    init(
        displayStateRawValue: String,
        activeTitle: String?,
        activeSubtitle: String?,
        activeActivityRawValue: UInt?,
        activeLocationRawValue: Int,
        workoutStartDate: Date?,
        accumulatedElapsedTime: TimeInterval,
        pauseStartedAt: Date?,
        phaseQueue: [WatchProgramPhasePayload],
        currentPhaseIndex: Int,
        currentMicroStageIndex: Int,
        currentRepeatIteration: Int,
        accumulatedQualifiedObjectiveTime: TimeInterval,
        routeName: String?,
        routeTrailhead: WatchPlanCoordinatePayload?,
        routeCoordinates: [WatchPlanCoordinatePayload]
    ) {
        self.displayStateRawValue = displayStateRawValue
        self.activeTitle = activeTitle
        self.activeSubtitle = activeSubtitle
        self.activeActivityRawValue = activeActivityRawValue
        self.activeLocationRawValue = activeLocationRawValue
        self.workoutStartDate = workoutStartDate
        self.accumulatedElapsedTime = accumulatedElapsedTime
        self.pauseStartedAt = pauseStartedAt
        self.phaseQueue = phaseQueue
        self.currentPhaseIndex = currentPhaseIndex
        self.currentMicroStageIndex = currentMicroStageIndex
        self.currentRepeatIteration = currentRepeatIteration
        self.accumulatedQualifiedObjectiveTime = accumulatedQualifiedObjectiveTime
        self.routeName = routeName
        self.routeTrailhead = routeTrailhead
        self.routeCoordinates = routeCoordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayStateRawValue = try container.decode(String.self, forKey: .displayStateRawValue)
        activeTitle = try container.decodeIfPresent(String.self, forKey: .activeTitle)
        activeSubtitle = try container.decodeIfPresent(String.self, forKey: .activeSubtitle)
        activeActivityRawValue = try container.decodeIfPresent(UInt.self, forKey: .activeActivityRawValue)
        activeLocationRawValue = try container.decode(Int.self, forKey: .activeLocationRawValue)
        workoutStartDate = try container.decodeIfPresent(Date.self, forKey: .workoutStartDate)
        accumulatedElapsedTime = try container.decode(TimeInterval.self, forKey: .accumulatedElapsedTime)
        pauseStartedAt = try container.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        phaseQueue = try container.decode([WatchProgramPhasePayload].self, forKey: .phaseQueue)
        currentPhaseIndex = try container.decode(Int.self, forKey: .currentPhaseIndex)
        currentMicroStageIndex = try container.decode(Int.self, forKey: .currentMicroStageIndex)
        currentRepeatIteration = try container.decodeIfPresent(Int.self, forKey: .currentRepeatIteration) ?? 0
        accumulatedQualifiedObjectiveTime = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedQualifiedObjectiveTime) ?? 0
        routeName = try container.decodeIfPresent(String.self, forKey: .routeName)
        routeTrailhead = try container.decodeIfPresent(WatchPlanCoordinatePayload.self, forKey: .routeTrailhead)
        routeCoordinates = try container.decodeIfPresent([WatchPlanCoordinatePayload].self, forKey: .routeCoordinates) ?? []
    }
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

    var metricPageIndex: Int? {
        switch self {
        case .metricsPrimary:
            return 0
        case .metricsSecondary:
            return 1
        case .metricsTertiary:
            return 2
        case .metricsQuaternary:
            return 3
        default:
            return nil
        }
    }

    var isAutomaticMetricPage: Bool {
        metricPageIndex != nil
    }

    static var metricPageCases: [WatchWorkoutPageKind] {
        [.metricsPrimary, .metricsSecondary, .metricsTertiary, .metricsQuaternary]
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
    @Published private(set) var currentRepeatIteration = 0
    @Published private(set) var pendingEffortQueue: [CompletedPhaseEffort] = []
    @Published private(set) var activeCompletionPrompt: WatchProgramPhasePayload?

    private enum CompanionLifecycleKeys {
        static let workoutLifecycle = "workoutLifecycle"
        static let reason = "reason"
        static let effortScore = "effortScore"
        static let request = "request"
        static let liveWorkoutSnapshot = "liveWorkoutSnapshot"
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

    private var currentRepeatGroupProgress: RepeatGroupProgress? {
        guard currentMicroStages.indices.contains(currentMicroStageIndex) else { return nil }
        return repeatGroupProgress(for: currentMicroStageIndex)
    }

    private var hasMoreStepsInCurrentPhase: Bool {
        guard let progress = currentRepeatGroupProgress else { return false }
        if currentMicroStageIndex < progress.endIndex { return true }
        if currentRepeatIteration + 1 < progress.iterations { return true }
        return currentMicroStages.indices.contains(progress.endIndex + 1)
    }

    var nextAdvanceTitle: String? {
        if let currentMicroStage, let progress = currentRepeatGroupProgress, currentRepeatIteration + 1 < progress.iterations {
            return currentMicroStage.title
        }
        return nextMicroStage?.title ?? nextPhase?.title
    }

    var nextAdvancePlannedMinutes: Int? {
        if let currentMicroStage, let progress = currentRepeatGroupProgress, currentRepeatIteration + 1 < progress.iterations {
            return currentMicroStage.plannedMinutes
        }
        return nextMicroStage?.plannedMinutes ?? nextPhase?.plannedMinutes
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
        guard [.time, .power, .cadence, .speed, .pace].contains(objective.kind) else { return nil }
        return max(objective.targetValue * 60 - currentObjectiveProgressTime(at: Date()), 0)
    }

    var compactCurrentStageTitle: String? {
        currentMicroStage?.title ?? currentPhase?.title
    }

    var compactCurrentStageTargetText: String? {
        if let currentMicroStage {
            return compactTargetText(for: currentMicroStage)
        }
        guard let currentPhase else { return nil }
        return compactTargetText(for: currentPhase)
    }

    var compactCurrentStageProgressText: String? {
        if let currentMicroStage {
            return compactProgressText(for: currentMicroStage, at: currentMicroStageIndex)
        }
        guard let currentPhase else { return nil }
        return compactProgressText(for: currentPhase, at: currentPhaseIndex)
    }

    var isCompactCurrentStageTargetSatisfied: Bool {
        if let currentMicroStage {
            switch currentMicroStage.objective.kind {
            case .power, .cadence, .speed, .pace:
                return metricObjectiveSatisfied(for: currentMicroStage)
            default:
                return microStageStatus(for: currentMicroStage, at: currentMicroStageIndex).isComplete
            }
        }
        guard let currentPhase else { return false }
        return objectiveStatus(for: currentPhase, at: currentPhaseIndex).isComplete
    }

    var isNextPhaseReady: Bool {
        guard hasMoreStepsInCurrentPhase || nextPhase != nil else { return false }
        return currentSegmentObjectiveStatus().isComplete
    }

    var isCurrentPhaseObjectiveComplete: Bool {
        currentSegmentObjectiveStatus().isComplete
    }

    var currentEffortPromptPhase: CompletedPhaseEffort? {
        pendingEffortQueue.first
    }

    private struct RepeatGroupProgress {
        let startIndex: Int
        let endIndex: Int
        let iterations: Int
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
    private var persistenceTicks: Int = 0
    private var lastPowerSampleDate: Date?
    private var lastHistorySampleElapsedTime: TimeInterval = 0
    private var currentSplitStartElapsedTime: TimeInterval = 0
    private var currentSplitStartDistanceMeters: Double = 0
    private var autoSplitLengthMeters: Double?
    private let workoutTabPreferences = WatchWorkoutTabPreferences()
    private let workoutMetricPreferences = WatchWorkoutMetricPreferences()
    private var hasAnnouncedCurrentPhaseReady = false
    private var nextPhaseReminderIdentifier: String?
    private var microStageStartDate: Date?
    private var accumulatedMicroStageElapsedTime: TimeInterval = 0
    private var accumulatedQualifiedObjectiveTime: TimeInterval = 0
    private var microStageStartDistanceMeters: Double = 0
    private var microStageStartEnergyKilocalories: Double = 0
    private var microStageStartZoneDurations: [TimeInterval] = []
    private var objectiveQualificationSampleDate: Date?
    private let persistenceKey = "watch.live.workout.session_v2"

    private var sessionState: HKWorkoutSessionState? {
        workoutSession?.state
    }

    /// True when the session carries a structured plan (program phases and/or micro-stages) worth tracking separately from raw metrics.
    var shouldShowPlanTrackingTab: Bool {
        guard isSessionActive else { return false }
        if phaseQueue.count > 1 { return true }
        if let first = phaseQueue.first, let stages = first.microStages, !stages.isEmpty { return true }
        return false
    }

    var orderedWorkoutPages: [WatchWorkoutPageKind] {
        let activity = activeActivity ?? .running
        let basePages = orderedPages(for: activity)
        let automaticMetricPages = automaticMetricPages(for: activity)
        var pages: [WatchWorkoutPageKind] = []

        for page in basePages {
            if page == .metricsPrimary {
                pages.append(contentsOf: automaticMetricPages)
            } else if !page.isAutomaticMetricPage {
                pages.append(page)
            }
        }

        guard shouldShowPlanTrackingTab else { return pages }
        let tab = WatchWorkoutPageKind.planTracking
        guard !pages.contains(tab) else { return pages }
        if let mainIdx = pages.firstIndex(of: .metricsPrimary) {
            pages.insert(tab, at: min(mainIdx + 1, pages.count))
        } else {
            pages.insert(tab, at: 0)
        }
        return pages
    }

    /// Progress line for a micro-stage row in the plan UI (handles past / future / current phase).
    func planTrackingRowStatus(
        phaseIndex: Int,
        stageIndex: Int,
        stage: WatchProgramMicroStagePayload
    ) -> (summaryText: String, isComplete: Bool) {
        if phaseIndex < currentPhaseIndex {
            return ("Completed", true)
        }
        if phaseIndex > currentPhaseIndex {
            return (upcomingMicroStageText(for: stage), false)
        }
        return microStageStatus(for: stage, at: stageIndex)
    }

    func orderedPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        workoutTabPreferences.orderedPages(for: activity)
    }

    func availableEditablePages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        WatchWorkoutTabPreferences
            .defaultPages(for: activity)
            .filter { !$0.isAutomaticMetricPage && $0 != .planTracking }
    }

    func isPageEnabled(_ page: WatchWorkoutPageKind, for activity: HKWorkoutActivityType) -> Bool {
        if page.isAutomaticMetricPage && page != .metricsPrimary { return false }
        if page == .planTracking { return false }
        return orderedPages(for: activity).contains(page)
    }

    func setPageEnabled(_ isEnabled: Bool, page: WatchWorkoutPageKind, for activity: HKWorkoutActivityType) {
        guard !page.isAutomaticMetricPage || page == .metricsPrimary else { return }
        guard page != .planTracking else { return }
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
        guard !page.isAutomaticMetricPage || page == .metricsPrimary else { return }
        guard page != .planTracking else { return }
        var pages = orderedPages(for: activity)
        guard let index = pages.firstIndex(of: page) else { return }
        let destination = min(max(index + direction, 0), pages.count - 1)
        guard destination != index else { return }
        pages.move(fromOffsets: IndexSet(integer: index), toOffset: destination > index ? destination + 1 : destination)
        workoutTabPreferences.setOrderedPages(pages, for: activity)
        objectWillChange.send()
    }

    func resetPagesToDefault(for activity: HKWorkoutActivityType) {
        let defaultPages = WatchWorkoutTabPreferences.defaultPages(for: activity)
        let editablePages = availableEditablePages(for: activity)

        for page in editablePages {
            setPageEnabled(defaultPages.contains(page), page: page, for: activity)
        }

        objectWillChange.send()
    }

    func availableMetricIDs(for activity: HKWorkoutActivityType) -> [String] {
        workoutMetricPreferences.availableMetricIDs(for: activity)
    }

    func orderedMetricIDs(for activity: HKWorkoutActivityType) -> [String] {
        workoutMetricPreferences.orderedMetricIDs(for: activity)
    }

    func metricIDs(for page: WatchWorkoutPageKind, activity: HKWorkoutActivityType) -> [String] {
        guard let pageIndex = page.metricPageIndex else { return [] }
        let orderedIDs = orderedMetricIDs(for: activity)
        let startIndex = pageIndex * 3
        guard startIndex < orderedIDs.count else { return [] }
        let endIndex = min(startIndex + 3, orderedIDs.count)
        return Array(orderedIDs[startIndex..<endIndex])
    }

    func isMetricEnabled(_ metricID: String, for activity: HKWorkoutActivityType) -> Bool {
        orderedMetricIDs(for: activity).contains(metricID)
    }

    func setMetricEnabled(_ isEnabled: Bool, metricID: String, for activity: HKWorkoutActivityType) {
        workoutMetricPreferences.setMetricEnabled(isEnabled, metricID: metricID, for: activity)
        objectWillChange.send()
    }

    func moveMetric(_ metricID: String, direction: Int, for activity: HKWorkoutActivityType) {
        workoutMetricPreferences.moveMetric(metricID, direction: direction, for: activity)
        objectWillChange.send()
    }

    private func automaticMetricPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        let metricCount = max(orderedMetricIDs(for: activity).count, 1)
        let pagesNeeded = max(1, Int(ceil(Double(metricCount) / 3.0)))
        return Array(WatchWorkoutPageKind.metricPageCases.prefix(pagesNeeded))
    }

    func activate() {
        Task {
            authorizationGranted = await requestAuthorizationIfNeeded()
            estimatedMaxHeartRate = await estimatedMaximumHeartRate()
            restorePersistedSessionIfNeeded()
            await recoverActiveWorkoutSessionIfNeeded()
            normalizePostWorkoutDestinationAfterStartup()
#if canImport(WatchConnectivity)
            if WCSession.isSupported() {
                let session = WCSession.default
                session.delegate = self
                session.activate()
            }
#endif
            refreshRecoveredWorkoutContext()
            if #available(watchOS 10.0, *) {
                schedulerAuthorizationState = await WorkoutScheduler.shared.requestAuthorization()
                scheduledPlans = await WorkoutScheduler.shared.scheduledWorkouts
            }
        }
    }

    func refreshRecoveredWorkoutContext() {
        guard isSessionActive || workoutSession != nil else { return }
        if displayState == .running {
            startElapsedTimer()
        } else if displayState == .paused {
            stopElapsedTimer()
        }
        Task { @MainActor in
            self.isMirroringToPhone = await self.ensureCompanionMirroring()
            self.broadcastCompanionSnapshot()
            self.persistCurrentSession()
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
        currentRepeatIteration = 0
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
        currentRepeatIteration = 0
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
        currentRepeatIteration = 0
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
        if let currentMicroStage, objectiveCountsOnlyQualifiedTime(currentMicroStage.objective.kind) {
            accumulatedQualifiedObjectiveTime = objectiveProgressTime(for: currentMicroStage, at: Date())
        }
        objectiveQualificationSampleDate = nil
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
            objectiveQualificationSampleDate = Date()
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
        currentRepeatIteration = 0
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
            self.isMirroringToPhone = await self.ensureCompanionMirroring()
            _ = await self.requestCompanionPresentation()
            self.broadcastCompanionSnapshot()
            self.persistCurrentSession()

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
            print("[Watch] handleCompanionLaunchRequest: workoutStart validation failed. Keys: \(Array(payload.keys))")
            return false
        }

        print("[Watch] Processing companion launch request: title=\(title), phases=\(payload[CompanionLaunchKeys.phasePayloads] is [Any] ? "present" : "none")")

        let activity = HKWorkoutActivityType(rawValue: UInt(activityRawValue)) ?? .running
        let locationRawValue = payload[CompanionLaunchKeys.locationRawValue] as? Int ?? HKWorkoutSessionLocationType.unknown.rawValue
        let location = HKWorkoutSessionLocationType(rawValue: locationRawValue) ?? .unknown
        routeName = payload[CompanionLaunchKeys.routeName] as? String
        if let latitude = payload[CompanionLaunchKeys.trailheadLatitude] as? Double,
           let longitude = payload[CompanionLaunchKeys.trailheadLongitude] as? Double {
            routeTrailhead = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            print("[Watch] Trailhead set: \(latitude), \(longitude)")
        } else {
            routeTrailhead = nil
        }
        routeCoordinates = (payload[CompanionLaunchKeys.routeCoordinates] as? [[Double]])?.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        } ?? []
        print("[Watch] Route coordinates: \(routeCoordinates.count) points")

        let phasePayloads = decodePhasePayloads(from: payload[CompanionLaunchKeys.phasePayloads] as? [[String: Any]])
        print("[Watch] Decoded \(phasePayloads.count) phases from payload")
        
        if (payload[CompanionLaunchKeys.openInWorkoutApp] as? Bool) == true {
            print("[Watch] Opening in Workout app...")
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
            currentRepeatIteration = 0
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
            currentRepeatIteration = 0
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
        persistenceTicks = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.displayState == .running {
                    self.elapsedTime = self.currentElapsedTime(at: Date())
                    self.refreshPhaseSuggestionStatus()
                } else if self.displayState == .paused {
                    self.elapsedTime = self.accumulatedElapsedTime
                }
                
                // Persist session every 5 seconds (500 ticks at 0.01 interval)
                self.persistenceTicks += 1
                if self.persistenceTicks >= 500 {
                    self.persistenceTicks = 0
                    self.persistCurrentSession()
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
        accumulatedQualifiedObjectiveTime = 0
        microStageStartDate = date
        microStageStartDistanceMeters = totalDistanceMeters
        microStageStartEnergyKilocalories = currentEnergyKilocalories
        microStageStartZoneDurations = liveZoneDurations
        objectiveQualificationSampleDate = date
    }

    private func normalizedRepeatGroupKey(for stage: WatchProgramMicroStagePayload) -> String {
        if let circuitGroupID = stage.circuitGroupID {
            return circuitGroupID.uuidString
        }
        return stage.repeatSetLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func repeatGroupProgress(for stageIndex: Int) -> RepeatGroupProgress {
        guard currentMicroStages.indices.contains(stageIndex) else {
            return RepeatGroupProgress(startIndex: stageIndex, endIndex: stageIndex, iterations: 1)
        }

        let stage = currentMicroStages[stageIndex]
        let groupKey = normalizedRepeatGroupKey(for: stage)
        if !groupKey.isEmpty {
            var startIndex = stageIndex
            while startIndex > 0,
                  normalizedRepeatGroupKey(for: currentMicroStages[startIndex - 1]) == groupKey,
                  currentMicroStages[startIndex - 1].repeats == stage.repeats {
                startIndex -= 1
            }

            var endIndex = stageIndex
            while currentMicroStages.indices.contains(endIndex + 1),
                  normalizedRepeatGroupKey(for: currentMicroStages[endIndex + 1]) == groupKey,
                  currentMicroStages[endIndex + 1].repeats == stage.repeats {
                endIndex += 1
            }

            return RepeatGroupProgress(
                startIndex: startIndex,
                endIndex: endIndex,
                iterations: max(stage.repeats, 1)
            )
        }

        return RepeatGroupProgress(
            startIndex: stageIndex,
            endIndex: stageIndex,
            iterations: max(stage.repeats, 1)
        )
    }

    private func objectiveCountsOnlyQualifiedTime(_ kind: WatchPhaseObjectivePayload.Kind) -> Bool {
        [.power, .cadence, .speed, .pace].contains(kind)
    }

    private func currentObjectiveProgressTime(at date: Date) -> TimeInterval {
        guard let currentMicroStage else {
            return currentSegmentElapsedTime(at: date)
        }
        return objectiveProgressTime(for: currentMicroStage, at: date)
    }

    private func objectiveProgressTime(for stage: WatchProgramMicroStagePayload, at date: Date) -> TimeInterval {
        guard objectiveCountsOnlyQualifiedTime(stage.objective.kind) else {
            return currentSegmentElapsedTime(at: date)
        }

        var qualifiedTime = accumulatedQualifiedObjectiveTime
        if displayState == .running,
           let sampleDate = objectiveQualificationSampleDate,
           metricObjectiveSatisfied(for: stage) {
            qualifiedTime += max(0, min(date.timeIntervalSince(sampleDate), 15))
        }
        return qualifiedTime
    }

    private func updateQualifiedObjectiveProgress(at date: Date) {
        guard let currentMicroStage, objectiveCountsOnlyQualifiedTime(currentMicroStage.objective.kind) else {
            objectiveQualificationSampleDate = date
            accumulatedQualifiedObjectiveTime = 0
            return
        }

        defer { objectiveQualificationSampleDate = date }

        guard let sampleDate = objectiveQualificationSampleDate else { return }
        guard metricObjectiveSatisfied(for: currentMicroStage) else { return }
        accumulatedQualifiedObjectiveTime += max(0, min(date.timeIntervalSince(sampleDate), 15))
    }

    private func metricObjectiveSatisfied(for stage: WatchProgramMicroStagePayload) -> Bool {
        let behavior = stage.targetBehaviorRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = stage.targetValueText ?? stage.objective.label ?? ""

        switch stage.objective.kind {
        case .power:
            guard let currentPowerWatts else { return false }
            return numericMetricSatisfied(value: currentPowerWatts, label: label, behavior: behavior)
        case .cadence:
            guard let currentCadence else { return false }
            return numericMetricSatisfied(value: currentCadence, label: label, behavior: behavior)
        case .speed:
            guard
                let currentSpeedMetersPerSecond,
                let target = label.speedTarget
            else { return false }
            let currentValue = Measurement(value: currentSpeedMetersPerSecond, unit: UnitSpeed.metersPerSecond)
                .converted(to: target.unit)
                .value
            return speedMetricSatisfied(value: currentValue, target: target, behavior: behavior)
        case .pace:
            guard
                let currentSpeedMetersPerSecond,
                let target = label.paceAsSpeedTarget
            else { return false }
            return speedMetricSatisfied(value: currentSpeedMetersPerSecond, target: target, behavior: behavior)
        default:
            return false
        }
    }

    private func numericMetricSatisfied(value: Double, label: String, behavior: String?) -> Bool {
        if behavior == "belowthreshold" {
            if let upperBound = label.numberRange?.upperBound {
                return value <= upperBound
            }
            if let threshold = label.firstNumberValue {
                return value <= threshold
            }
            return false
        }

        if let range = label.numberRange {
            return range.contains(value)
        }

        if let threshold = label.firstNumberValue {
            return value >= threshold
        }

        return false
    }

    private func speedMetricSatisfied(
        value: Double,
        target: WatchParsedSpeedTarget,
        behavior: String?
    ) -> Bool {
        if behavior == "belowthreshold" {
            return target.recoveryRange.contains(value)
        }
        if let range = target.range {
            return range.contains(value)
        }
        return value >= target.threshold
    }

    private func repeatIterationPrefix(for stageIndex: Int) -> String {
        let progress = repeatGroupProgress(for: stageIndex)
        guard progress.iterations > 1 else { return "" }
        return "Round \(min(currentRepeatIteration + 1, progress.iterations))/\(progress.iterations) • "
    }

    /// Clamps 1-based zone labels (from plan / NLP) to `liveZoneDurations` indices. Returns 0 if zone data is not ready.
    private func safeHeartRateZoneIndex(zoneNumber: Int) -> Int {
        guard !liveZoneDurations.isEmpty else { return 0 }
        return max(0, min(zoneNumber - 1, liveZoneDurations.count - 1))
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
        guard !currentMicroStages.isEmpty else { return false }

        let progress = repeatGroupProgress(for: currentMicroStageIndex)
        if currentMicroStageIndex < progress.endIndex {
            currentMicroStageIndex += 1
        } else if currentRepeatIteration + 1 < progress.iterations {
            currentRepeatIteration += 1
            currentMicroStageIndex = progress.startIndex
        } else {
            let nextIndex = progress.endIndex + 1
            guard currentMicroStages.indices.contains(nextIndex) else { return false }
            currentRepeatIteration = 0
            currentMicroStageIndex = nextIndex
        }

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
        if let currentMicroStage,
           let progress = currentRepeatGroupProgress,
           currentRepeatIteration + 1 < progress.iterations {
            statusMessage = "Goal complete. Next round ready: \(currentMicroStage.title)"
        } else if let nextMicroStage {
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

        updateQualifiedObjectiveProgress(at: Date())
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
            guard let data = try? JSONEncoder().encode(payload) else {
                print("[Watch] Failed to encode snapshot payload")
                return
            }
            do {
                try await workoutSession.sendToRemoteWorkoutSession(data: data)
                print("[Watch] Snapshot sent successfully (size: \(data.count) bytes)")
            } catch {
                print("[Watch] Failed to send snapshot to iPhone: \(error.localizedDescription)")
                // Fall back to WCSession for critical updates if available
                #if canImport(WatchConnectivity)
                if WCSession.isSupported() {
                    let session = WCSession.default
                    if session.activationState == .activated && session.isReachable {
                        let fallbackPayload: [String: Any] = [
                            "snapshotUpdate": true,
                            "elapsedTime": elapsedTime,
                            "stateText": displayState.rawValue
                        ]
                        session.sendMessage(fallbackPayload, replyHandler: { response in
                            print("[Watch] WCSession fallback sent: \(response)")
                        }, errorHandler: { error in
                            print("[Watch] WCSession fallback failed: \(error.localizedDescription)")
                        })
                    }
                }
                #endif
            }
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
            let zIdx = safeHeartRateZoneIndex(zoneNumber: zoneNumber)
            let displayZone = zIdx + 1
            let zoneSeconds = liveZoneDurations.isEmpty ? 0 : liveZoneDurations[zIdx]
            let currentMinutes = zoneSeconds / 60
            let targetMinutes = max(objective.targetValue, 1)
            return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min in Z\(displayZone)", currentMinutes >= targetMinutes)
        case .power, .cadence, .speed, .pace:
            let currentMinutes = currentObjectiveProgressTime(at: Date()) / 60
            let targetMinutes = max(objective.targetValue, 1)
            return ("\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min at \(objectiveDisplayLabel(for: objective))", currentMinutes >= targetMinutes)
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
            return ("\(repeatIterationPrefix(for: index))\(shortWorkoutElapsedString(remaining)) left", remaining <= 0)
        case .distance:
            let targetKilometers = max(stage.objective.targetValue, 0.1)
            return ("\(repeatIterationPrefix(for: index))" + String(format: "%.1f / %.1f km", distanceDeltaKilometers, targetKilometers), distanceDeltaKilometers >= targetKilometers)
        case .energy:
            let targetKilocalories = max(stage.objective.targetValue, 1)
            return ("\(repeatIterationPrefix(for: index))\(Int(energyDelta.rounded())) / \(Int(targetKilocalories.rounded())) kcal", energyDelta >= targetKilocalories)
        case .heartRateZone:
            let zoneNumber = Int(stage.objective.secondaryValue ?? 3)
            let zIdx = safeHeartRateZoneIndex(zoneNumber: zoneNumber)
            let displayZone = zIdx + 1
            let priorZoneSeconds = microStageStartZoneDurations.indices.contains(zIdx) ? microStageStartZoneDurations[zIdx] : 0
            let currentZoneSeconds = liveZoneDurations.isEmpty ? 0 : liveZoneDurations[zIdx]
            let currentMinutes = max(currentZoneSeconds - priorZoneSeconds, 0) / 60
            let targetMinutes = max(stage.objective.targetValue, 1)
            return ("\(repeatIterationPrefix(for: index))\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min in Z\(displayZone)", currentMinutes >= targetMinutes)
        case .power, .cadence, .speed, .pace:
            let targetMinutes = max(stage.objective.targetValue, 1)
            let currentMinutes = objectiveProgressTime(for: stage, at: Date()) / 60
            return ("\(repeatIterationPrefix(for: index))\(Int(currentMinutes.rounded())) / \(Int(targetMinutes.rounded())) min at \(objectiveDisplayLabel(for: stage.objective))", currentMinutes >= targetMinutes)
        case .routeDistance:
            let targetKilometers = max(stage.objective.targetValue, 0.1)
            return ("\(repeatIterationPrefix(for: index))" + String(format: "%.1f / %.1f km route", distanceDeltaKilometers, targetKilometers), distanceDeltaKilometers >= targetKilometers)
        }
    }

    private func compactTargetText(for stage: WatchProgramMicroStagePayload) -> String {
        switch stage.objective.kind {
        case .time:
            return "\(max(stage.plannedMinutes, 1)) min"
        case .distance:
            return String(format: "%.1f km", max(stage.objective.targetValue, 0.1))
        case .energy:
            return "\(Int(max(stage.objective.targetValue, 1).rounded())) kcal"
        case .heartRateZone:
            return "Zone \(Int(stage.objective.secondaryValue ?? 3))"
        case .power, .cadence, .speed, .pace:
            return objectiveDisplayLabel(for: stage.objective)
        case .routeDistance:
            return String(format: "%.1f km route", max(stage.objective.targetValue, 0.1))
        }
    }

    private func compactTargetText(for phase: WatchProgramPhasePayload) -> String {
        let objective = phase.objective ?? WatchPhaseObjectivePayload(
            kind: .time,
            targetValue: Double(max(phase.plannedMinutes, 1))
        )

        switch objective.kind {
        case .time:
            return "\(max(phase.plannedMinutes, 1)) min"
        case .distance:
            return String(format: "%.1f km", max(objective.targetValue, 0.1))
        case .energy:
            return "\(Int(max(objective.targetValue, 1).rounded())) kcal"
        case .heartRateZone:
            return "Zone \(Int(objective.secondaryValue ?? 3))"
        case .power, .cadence, .speed, .pace:
            return objectiveDisplayLabel(for: objective)
        case .routeDistance:
            return String(format: "%.1f km route", max(objective.targetValue, 0.1))
        }
    }

    private func compactProgressText(for stage: WatchProgramMicroStagePayload, at index: Int) -> String {
        let roundSuffix = compactRoundSuffix(for: index)

        switch stage.objective.kind {
        case .time:
            let targetSeconds = max(stage.objective.targetValue, 1) * 60
            let remaining = max(targetSeconds - currentSegmentElapsedTime(at: Date()), 0)
            return "\(shortWorkoutElapsedString(remaining)) left\(roundSuffix)"
        case .distance:
            let currentKilometers = max(totalDistanceMeters - microStageStartDistanceMeters, 0) / 1000
            return String(format: "%.1f/%.1f km%@", currentKilometers, max(stage.objective.targetValue, 0.1), roundSuffix)
        case .energy:
            let currentEnergy = max(currentEnergyKilocalories - microStageStartEnergyKilocalories, 0)
            return "\(Int(currentEnergy.rounded()))/\(Int(max(stage.objective.targetValue, 1).rounded())) kcal\(roundSuffix)"
        case .heartRateZone:
            let zoneNumber = Int(stage.objective.secondaryValue ?? 3)
            let zIdx = safeHeartRateZoneIndex(zoneNumber: zoneNumber)
            let priorZoneSeconds = microStageStartZoneDurations.indices.contains(zIdx) ? microStageStartZoneDurations[zIdx] : 0
            let currentZoneSeconds = liveZoneDurations.isEmpty ? 0 : liveZoneDurations[zIdx]
            let currentMinutes = max(currentZoneSeconds - priorZoneSeconds, 0) / 60
            return "\(Int(currentMinutes.rounded()))/\(Int(max(stage.objective.targetValue, 1).rounded())) min\(roundSuffix)"
        case .power, .cadence, .speed, .pace:
            let currentMinutes = objectiveProgressTime(for: stage, at: Date()) / 60
            return "\(Int(currentMinutes.rounded()))/\(Int(max(stage.objective.targetValue, 1).rounded())) min\(roundSuffix)"
        case .routeDistance:
            let currentKilometers = max(totalDistanceMeters - microStageStartDistanceMeters, 0) / 1000
            return String(format: "%.1f/%.1f km%@", currentKilometers, max(stage.objective.targetValue, 0.1), roundSuffix)
        }
    }

    private func compactProgressText(for phase: WatchProgramPhasePayload, at index: Int) -> String {
        let objective = phase.objective ?? WatchPhaseObjectivePayload(
            kind: .time,
            targetValue: Double(max(phase.plannedMinutes, 1))
        )

        switch objective.kind {
        case .time:
            let targetSeconds = max(objective.targetValue, 1) * 60
            let remaining = max(targetSeconds - elapsedTime, 0)
            return "\(shortWorkoutElapsedString(remaining)) left"
        case .distance:
            return String(format: "%.1f/%.1f km", totalDistanceMeters / 1000, max(objective.targetValue, 0.1))
        case .energy:
            return "\(Int(currentEnergyKilocalories.rounded()))/\(Int(max(objective.targetValue, 1).rounded())) kcal"
        case .heartRateZone:
            let zoneNumber = Int(objective.secondaryValue ?? 3)
            let zIdx = safeHeartRateZoneIndex(zoneNumber: zoneNumber)
            let currentZoneSeconds = liveZoneDurations.isEmpty ? 0 : liveZoneDurations[zIdx]
            let currentMinutes = currentZoneSeconds / 60
            return "\(Int(currentMinutes.rounded()))/\(Int(max(objective.targetValue, 1).rounded())) min"
        case .power, .cadence, .speed, .pace:
            let currentMinutes = currentObjectiveProgressTime(at: Date()) / 60
            return "\(Int(currentMinutes.rounded()))/\(Int(max(objective.targetValue, 1).rounded())) min"
        case .routeDistance:
            return String(format: "%.1f/%.1f km route", totalDistanceMeters / 1000, max(objective.targetValue, 0.1))
        }
    }

    private func compactRoundSuffix(for stageIndex: Int) -> String {
        let progress = repeatGroupProgress(for: stageIndex)
        guard progress.iterations > 1 else { return "" }
        return "; Round \(min(currentRepeatIteration + 1, progress.iterations))/\(progress.iterations)"
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
        case .power, .cadence, .speed, .pace:
            return "Goal \(Int(objective.targetValue.rounded())) min at \(objectiveDisplayLabel(for: objective))"
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
        case .power, .cadence, .speed, .pace:
            return "Goal \(Int(stage.objective.targetValue.rounded())) min at \(objectiveDisplayLabel(for: stage.objective))"
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
            session.sendMessage(payload, replyHandler: { response in
                print("[WatchSync] Companion lifecycle message sent and acknowledged: \(response)")
            }, errorHandler: { error in
                print("[WatchSync] Failed to send companion lifecycle message: \(error.localizedDescription)")
                // Fall back to background transfer
                session.transferUserInfo(payload)
            })
        } else {
            print("[WatchSync] iPhone not reachable, using background transfer for lifecycle update")
            session.transferUserInfo(payload)
        }
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
            currentRepeatIteration: currentRepeatIteration,
            accumulatedQualifiedObjectiveTime: accumulatedQualifiedObjectiveTime,
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
        currentRepeatIteration = payload.currentRepeatIteration
        accumulatedQualifiedObjectiveTime = payload.accumulatedQualifiedObjectiveTime
        objectiveQualificationSampleDate = Date()
        routeName = payload.routeName
        routeTrailhead = payload.routeTrailhead.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        routeCoordinates = payload.routeCoordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    private func normalizePostWorkoutDestinationAfterStartup() {
        guard !isSessionActive else { return }

        if !pendingEffortQueue.isEmpty {
            postWorkoutDestination = .effortPrompt
            if displayState == .running || displayState == .paused || displayState == .preparing {
                displayState = .ended
            }
            return
        }

        postWorkoutDestination = .none
        if displayState == .ended || displayState == .failed {
            displayState = .idle
        }
        lastCompletedWorkoutTitle = nil
        lastCompletedWorkoutSubtitle = nil
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

    /// WatchConnectivity / plist bridging may deliver integers as `NSNumber`; accept those so micro-stages are not dropped.
    private static func decodeWCInt(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let v = Int(s) { return v }
        return nil
    }

    private func decodePhasePayloads(from payloads: [[String: Any]]?) -> [WatchProgramPhasePayload] {
        guard let payloads else { return [] }
        return payloads.compactMap { phasePayload in
            guard let title = phasePayload["title"] as? String,
                  let subtitle = phasePayload["subtitle"] as? String,
                  let activityID = phasePayload["activityID"] as? String,
                  let activityRawValue = Self.decodeWCInt(phasePayload["activityRawValue"]),
                  let locationRawValue = Self.decodeWCInt(phasePayload["locationRawValue"]),
                  let plannedMinutes = Self.decodeWCInt(phasePayload["plannedMinutes"]) else {
                return nil
            }

            let stagePayloads = (phasePayload["microStages"] as? [[String: Any]] ?? []).compactMap { stagePayload -> WatchProgramMicroStagePayload? in
                guard let title = stagePayload["title"] as? String,
                      let goal = stagePayload["goal"] as? String,
                      let plannedMinutes = Self.decodeWCInt(stagePayload["plannedMinutes"]) else {
                    return nil
                }
                let repeats = max(Self.decodeWCInt(stagePayload["repeats"]) ?? 1, 1)
                let notes = stagePayload["notes"] as? String ?? ""
                let targetValueText = stagePayload["targetValueText"] as? String ?? ""
                let roleRawValue = stagePayload["role"] as? String
                let goalRawValue = stagePayload["goal"] as? String
                return WatchProgramMicroStagePayload(
                    id: UUID(uuidString: stagePayload["id"] as? String ?? "") ?? UUID(),
                    title: title,
                    notes: notes,
                    roleRawValue: roleRawValue,
                    goalRawValue: goalRawValue,
                    plannedMinutes: plannedMinutes,
                    repeats: repeats,
                    repeatSetLabel: stagePayload["repeatSetLabel"] as? String,
                    targetValueText: targetValueText.isEmpty ? nil : targetValueText,
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
        case "power":
            return WatchPhaseObjectivePayload(kind: .power, targetValue: Double(max(plannedMinutes, 1)), label: targetValueText.isEmpty ? "Power" : targetValueText)
        case "cadence":
            return WatchPhaseObjectivePayload(kind: .cadence, targetValue: Double(max(plannedMinutes, 1)), label: targetValueText.isEmpty ? "Cadence" : targetValueText)
        case "speed":
            return WatchPhaseObjectivePayload(kind: .speed, targetValue: Double(max(plannedMinutes, 1)), label: targetValueText.isEmpty ? "Speed" : targetValueText)
        case "pace":
            return WatchPhaseObjectivePayload(kind: .pace, targetValue: Double(max(plannedMinutes, 1)), label: targetValueText.isEmpty ? "Pace" : targetValueText)
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
        let warmup = microStages.first(where: { isWarmupStage($0) })
        let cooldown = microStages.last(where: { isCooldownStage($0) })
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
                IntervalStep(intervalStepPurpose(for: groupedStage),
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
                roleRawValue: nil,
                goalRawValue: fallbackGoalRawValue(for: objective.kind),
                plannedMinutes: max(phase.plannedMinutes, 1),
                repeats: 1,
                repeatSetLabel: nil,
                targetValueText: objective.label,
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
        case .time, .heartRateZone, .power, .cadence, .speed, .pace:
            return .time(Double(max(stage.plannedMinutes, 1)), .minutes)
        }
    }

    private func workoutAlert(for stage: WatchProgramMicroStagePayload) -> (any WorkoutAlert)? {
        switch stage.objective.kind {
        case .heartRateZone:
            return .heartRate(zone: Int(stage.objective.secondaryValue ?? 3))
        case .power:
            return powerAlert(for: stage)
        case .cadence:
            return cadenceAlert(for: stage)
        case .speed:
            return speedAlert(for: stage)
        case .pace:
            return paceAlert(for: stage)
        case .time, .distance, .energy, .routeDistance:
            return nil
        }
    }

    private func intervalStepPurpose(for stage: WatchProgramMicroStagePayload) -> IntervalStep.Purpose {
        switch stage.roleRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "recovery":
            return .recovery
        default:
            return .work
        }
    }

    private func isWarmupStage(_ stage: WatchProgramMicroStagePayload) -> Bool {
        if stage.roleRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "warmup" {
            return true
        }
        return stage.title.localizedCaseInsensitiveContains("warm")
    }

    private func isCooldownStage(_ stage: WatchProgramMicroStagePayload) -> Bool {
        if stage.roleRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cooldown" {
            return true
        }
        return stage.title.localizedCaseInsensitiveContains("cool")
    }

    private func fallbackGoalRawValue(for kind: WatchPhaseObjectivePayload.Kind) -> String? {
        switch kind {
        case .distance, .routeDistance:
            return "distance"
        case .energy:
            return "energy"
        case .heartRateZone:
            return "heartRateZone"
        case .power:
            return "power"
        case .cadence:
            return "cadence"
        case .speed:
            return "speed"
        case .pace:
            return "pace"
        case .time:
            return "time"
        }
    }

    private func powerAlert(for stage: WatchProgramMicroStagePayload) -> (any WorkoutAlert)? {
        let behavior = stage.targetBehaviorRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = stage.targetValueText ?? stage.objective.label ?? ""
        if behavior == "belowthreshold", let target = label.firstNumberValue {
            return .power(0...target, unit: .watts)
        }
        if let range = label.numberRange {
            return .power(range.lowerBound...range.upperBound, unit: .watts)
        }
        if let target = label.firstNumberValue {
            return .power(target, unit: .watts)
        }
        return nil
    }

    private func cadenceAlert(for stage: WatchProgramMicroStagePayload) -> (any WorkoutAlert)? {
        let behavior = stage.targetBehaviorRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = stage.targetValueText ?? stage.objective.label ?? ""
        if behavior == "belowthreshold", let target = label.firstNumberValue {
            return .cadence(0...target)
        }
        if let range = label.numberRange {
            return .cadence(range.lowerBound...range.upperBound)
        }
        if let target = label.firstNumberValue {
            return .cadence(target)
        }
        return nil
    }

    private func speedAlert(for stage: WatchProgramMicroStagePayload) -> (any WorkoutAlert)? {
        let behavior = stage.targetBehaviorRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = stage.targetValueText ?? stage.objective.label ?? ""
        guard let target = label.speedTarget else { return nil }
        if behavior == "belowthreshold" {
            return .speed(target.recoveryRange.lowerBound...target.recoveryRange.upperBound, unit: target.unit)
        }
        if let range = target.range {
            return .speed(range.lowerBound...range.upperBound, unit: target.unit)
        }
        return .speed(target.threshold, unit: target.unit)
    }

    private func paceAlert(for stage: WatchProgramMicroStagePayload) -> (any WorkoutAlert)? {
        let behavior = stage.targetBehaviorRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = stage.targetValueText ?? stage.objective.label ?? ""
        guard let target = label.paceAsSpeedTarget else { return nil }
        if behavior == "belowthreshold" {
            return .speed(target.recoveryRange.lowerBound...target.recoveryRange.upperBound, unit: target.unit)
        }
        if let range = target.range {
            return .speed(range.lowerBound...range.upperBound, unit: target.unit)
        }
        return .speed(target.threshold, unit: target.unit)
    }

    private func objectiveDisplayLabel(for objective: WatchPhaseObjectivePayload) -> String {
        let label = objective.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        switch objective.kind {
        case .power:
            return "power target"
        case .cadence:
            return "cadence target"
        case .speed:
            return "speed target"
        case .pace:
            return "pace target"
        default:
            return "target"
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
                    self.currentRepeatIteration = 0
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
    ) {
        Task { @MainActor in
            if let error = error {
                print("[Watch] WCSession activation failed: \(error.localizedDescription)")
                self.statusMessage = "iPhone connection failed: \(error.localizedDescription)"
                return
            }
            
            let stateString: String
            switch activationState {
            case .activated:
                stateString = "ACTIVATED"
            case .inactive:
                stateString = "INACTIVE"
            case .notActivated:
                stateString = "NOT_ACTIVATED"
            @unknown default:
                stateString = "UNKNOWN(\(activationState.rawValue))"
            }
            
            print("[Watch] WCSession activation completed: state=\(stateString), isReachable=\(session.isReachable)")
            
            switch activationState {
            case .activated:
                if session.isReachable {
                    self.statusMessage = "Connected to iPhone"
                    print("[Watch] iPhone is reachable, ready to receive commands")
                    if self.isSessionActive || self.workoutSession != nil {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.isMirroringToPhone = await self.ensureCompanionMirroring()
                            _ = await self.requestCompanionPresentation()
                            self.broadcastCompanionSnapshot()
                            self.persistCurrentSession()
                        }
                    }
                } else {
                    self.statusMessage = "iPhone not in range"
                    print("[Watch] iPhone not immediately reachable, will receive via background transfer")
                }
            case .inactive:
                self.statusMessage = "iPhone connection inactive"
                print("[Watch] Connection is inactive, attempting to reactivate...")
                // Attempt to reactivate
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if WCSession.isSupported() {
                        print("[Watch] Reactivating session...")
                        WCSession.default.activate()
                    }
                }
            case .notActivated:
                self.statusMessage = "WatchConnectivity unavailable"
                print("[Watch] WatchConnectivity not supported on this device")
            @unknown default:
                self.statusMessage = "Unknown iPhone connection state"
                print("[Watch] Unknown activation state: \(activationState.rawValue)")
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            guard session.isReachable, self.isSessionActive || self.workoutSession != nil else { return }
            self.statusMessage = "Connected to iPhone"
            self.isMirroringToPhone = await self.ensureCompanionMirroring()
            _ = await self.requestCompanionPresentation()
            self.broadcastCompanionSnapshot()
            self.persistCurrentSession()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void
    ) {
        Task { @MainActor in
            print("[Watch] Received message from iPhone: keys=\(message.keys.joined(separator: ","))")
            
            if let command = message["workoutControl"] as? String {
                print("[Watch] Processing workoutControl: \(command)")
                self.handleCompanionControlCommand(command)
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if message["request"] as? String == "showLiveWorkout" {
                print("[Watch] Received iPhone request to show live workout")
                if self.isSessionActive {
                    // Workout is already active; ensure this view gets foregrounded when possible
                    self.statusMessage = "iPhone requested live workout display"
                } else {
                    self.statusMessage = "iPhone requested workout view"
                }
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if message[CompanionLifecycleKeys.request] as? String == CompanionLifecycleKeys.liveWorkoutSnapshot {
                print("[Watch] Re-sending active workout snapshot to iPhone")
                self.refreshRecoveredWorkoutContext()
                replyHandler([CompanionLaunchKeys.accepted: self.isSessionActive || self.workoutSession != nil])
            } else if let effortScore = message[CompanionLifecycleKeys.effortScore] as? Int {
                print("[Watch] Processing effortScore: \(effortScore)")
                self.submitEffortScore(effortScore)
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if self.handleInjectedPhaseRequest(message) {
                print("[Watch] Handled as injected phase request")
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else if self.handleCompanionLaunchRequest(message) {
                print("[Watch] Handled as companion launch request")
                replyHandler([CompanionLaunchKeys.accepted: true])
            } else {
                print("[Watch] Message not recognized, keys: \(Array(message.keys))")
                replyHandler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        Task { @MainActor in
            print("[Watch] Received userInfo from iPhone: keys=\(userInfo.keys.joined(separator: ","))")
            
            if let command = userInfo["workoutControl"] as? String {
                print("[Watch] Processing userInfo workoutControl: \(command)")
                self.handleCompanionControlCommand(command)
            } else if userInfo["request"] as? String == "showLiveWorkout" {
                print("[Watch] Received iPhone userInfo request to show live workout")
                if self.isSessionActive {
                    self.statusMessage = "iPhone requested live workout display"
                } else {
                    self.statusMessage = "iPhone requested workout view"
                }
            } else if userInfo[CompanionLifecycleKeys.request] as? String == CompanionLifecycleKeys.liveWorkoutSnapshot {
                print("[Watch] Re-sending active workout snapshot from userInfo request")
                self.refreshRecoveredWorkoutContext()
            } else if let effortScore = userInfo[CompanionLifecycleKeys.effortScore] as? Int {
                print("[Watch] Processing userInfo effortScore: \(effortScore)")
                self.submitEffortScore(effortScore)
            } else if self.handleInjectedPhaseRequest(userInfo) {
                print("[Watch] Handled userInfo as injected phase request")
                return
            } else {
                print("[Watch] Trying companion launch request from userInfo")
                if self.handleCompanionLaunchRequest(userInfo) {
                    print("[Watch] Successfully handled as companion launch request")
                } else {
                    print("[Watch] UserInfo not recognized, keys: \(Array(userInfo.keys))")
                }
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

    func orderedPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
        let defaultPages = Self.defaultPages(for: activity)
        guard
            let data = storedData(),
            let stored = try? JSONDecoder().decode([String: [String]].self, from: data),
            let rawPages = stored[activity.preferenceKey]
        else {
            return defaultPages
        }

        let decoded = rawPages.compactMap(WatchWorkoutPageKind.init(rawValue:))
        let allowed = Set(defaultPages + [.planTracking])
        return decoded.filter { allowed.contains($0) }
    }

    func setOrderedPages(_ pages: [WatchWorkoutPageKind], for activity: HKWorkoutActivityType) {
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

    static func defaultPages(for activity: HKWorkoutActivityType) -> [WatchWorkoutPageKind] {
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

@MainActor
private final class WatchWorkoutMetricPreferences {
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
    }

    func moveMetric(_ metricID: String, direction: Int, for activity: HKWorkoutActivityType) {
        var metricIDs = orderedMetricIDs(for: activity)
        guard let index = metricIDs.firstIndex(of: metricID) else { return }
        let destination = min(max(index + direction, 0), metricIDs.count - 1)
        guard destination != index else { return }
        metricIDs.move(fromOffsets: IndexSet(integer: index), toOffset: destination > index ? destination + 1 : destination)
        persist(metricIDs, for: activity)
    }

    private func persist(_ metricIDs: [String], for activity: HKWorkoutActivityType) {
        var stored: [String: [String]] = [:]
        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        {
            stored = decoded
        }

        stored[activity.preferenceKey] = metricIDs
        if let data = try? JSONEncoder().encode(stored) {
            persistData(data)
        }
    }

    private static func defaultMetricIDs(for activity: HKWorkoutActivityType) -> [String] {
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

func watchWorkoutDisplayName(_ activityType: HKWorkoutActivityType) -> String {
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

private struct WatchParsedSpeedTarget {
    let unit: UnitSpeed
    let threshold: Double
    let range: ClosedRange<Double>?

    var recoveryRange: ClosedRange<Double> {
        0...max(range?.upperBound ?? threshold, threshold)
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

    var speedTarget: WatchParsedSpeedTarget? {
        let normalized = lowercased()
        let unit: UnitSpeed
        if normalized.contains("mph") {
            unit = .milesPerHour
        } else if normalized.contains("km/h") || normalized.contains("kph") {
            unit = .kilometersPerHour
        } else if normalized.contains("m/s") {
            unit = .metersPerSecond
        } else {
            return nil
        }

        if let range = numberRange {
            return WatchParsedSpeedTarget(unit: unit, threshold: range.upperBound, range: range)
        }
        if let value = firstNumberValue {
            return WatchParsedSpeedTarget(unit: unit, threshold: value, range: nil)
        }
        return nil
    }

    var paceAsSpeedTarget: WatchParsedSpeedTarget? {
        let normalized = lowercased()
        let metersPerSegment: Double
        if normalized.contains("/mi") {
            metersPerSegment = 1609.344
        } else if normalized.contains("/km") {
            metersPerSegment = 1000
        } else {
            return nil
        }

        let pattern = #"\b(\d+):(\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        let speeds = regex.matches(in: self, range: nsRange).compactMap { match -> Double? in
            guard
                let minutesRange = Range(match.range(at: 1), in: self),
                let secondsRange = Range(match.range(at: 2), in: self),
                let minutes = Double(self[minutesRange]),
                let seconds = Double(self[secondsRange])
            else {
                return nil
            }
            let totalSeconds = (minutes * 60) + seconds
            guard totalSeconds > 0 else { return nil }
            return metersPerSegment / totalSeconds
        }

        guard let first = speeds.first else { return nil }
        if speeds.count >= 2 {
            let lower = speeds.min() ?? first
            let upper = speeds.max() ?? first
            return WatchParsedSpeedTarget(unit: .metersPerSecond, threshold: upper, range: lower...upper)
        }
        return WatchParsedSpeedTarget(unit: .metersPerSecond, threshold: first, range: nil)
    }
}
