import Combine
import Foundation
import HealthKit
import SwiftUI
import UserNotifications
import WatchKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
import WorkoutKit

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
    var activity: HKWorkoutActivityType = .running
    var location: WatchWorkoutLocationChoice = .outdoor
    var goalMode: WatchWorkoutGoalMode = .open
    var goalValue: Double = 30
    var warmupMinutes: Double = 5
    var workMinutes: Double = 4
    var recoveryMinutes: Double = 2
    var repeats: Int = 4
    var cooldownMinutes: Double = 5

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

    var workoutPlan: WorkoutPlan {
        let warmup = warmupMinutes > 0
            ? WorkoutStep(goal: .time(warmupMinutes, .minutes), displayName: "Warm Up")
            : nil
        let cooldown = cooldownMinutes > 0
            ? WorkoutStep(goal: .time(cooldownMinutes, .minutes), displayName: "Cool Down")
            : nil
        let steps: [IntervalStep] = [
            IntervalStep(.work, step: WorkoutStep(goal: .time(max(workMinutes, 0.5), .minutes), displayName: "Work")),
            IntervalStep(.recovery, step: WorkoutStep(goal: .time(max(recoveryMinutes, 0.5), .minutes), displayName: "Recover"))
        ]
        let customWorkout = CustomWorkout(
            activity: activity,
            location: location.hkValue,
            displayName: displayName,
            warmup: warmup,
            blocks: [IntervalBlock(steps: steps, iterations: max(repeats, 1))],
            cooldown: cooldown
        )
        return WorkoutPlan(.custom(customWorkout))
    }
}

struct WatchLiveMetric: Identifiable, Hashable {
    let id: String
    let title: String
    let valueText: String
    let symbol: String
    let tint: Color
}

private struct CompanionWorkoutMetricPayload: Codable {
    let id: String
    let title: String
    let valueText: String
    let symbol: String
    let tintName: String
}

private struct CompanionWorkoutSnapshotPayload: Codable {
    let title: String
    let stateText: String
    let elapsedTime: TimeInterval
    let metrics: [CompanionWorkoutMetricPayload]
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
    @Published private(set) var currentSpeedMetersPerSecond: Double?
    @Published private(set) var currentPowerWatts: Double?
    @Published private(set) var averagePowerWatts: Double?
    @Published private(set) var currentCadence: Double?
    @Published private(set) var flightsClimbed: Double?
    @Published private(set) var strokeCount: Double?
    @Published private(set) var strideMeters: Double?
    @Published private(set) var groundContactTimeMilliseconds: Double?
    @Published private(set) var verticalOscillationCentimeters: Double?
    @Published private(set) var postWorkoutDestination: PostWorkoutDestination = .none
    @Published private(set) var lastCompletedWorkoutTitle: String?
    @Published private(set) var lastCompletedWorkoutSubtitle: String?
    @Published private(set) var lastEffortScore: Int?
    @Published var customDraft = WatchCustomWorkoutDraft()
    @Published var statusMessage = "Choose a workout to begin."

    var isSessionActive: Bool {
        displayState == .running || displayState == .paused || displayState == .preparing
    }

    var isOutdoorWorkout: Bool {
        activeLocation == .outdoor
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

    private var sessionState: HKWorkoutSessionState? {
        workoutSession?.state
    }

    func activate() {
        Task {
            authorizationGranted = await requestAuthorizationIfNeeded()
            estimatedMaxHeartRate = await estimatedMaximumHeartRate()
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
        startWorkout(
            title: template.title,
            subtitle: template.subtitle,
            activity: template.activity,
            location: template.location
        )
    }

    func startCustomWorkout() {
        startWorkout(
            title: customDraft.displayName,
            subtitle: "Custom • \(watchWorkoutDisplayName(customDraft.activity))",
            activity: customDraft.activity,
            location: customDraft.location.hkValue
        )
    }

    func scheduleCustomWorkoutForTomorrow() {
        guard #available(watchOS 10.0, *) else { return }

        Task {
            if schedulerAuthorizationState != .authorized {
                schedulerAuthorizationState = await WorkoutScheduler.shared.requestAuthorization()
            }
            guard schedulerAuthorizationState == .authorized else {
                statusMessage = "Workout scheduling permission is required."
                return
            }

            let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            await WorkoutScheduler.shared.schedule(customDraft.workoutPlan, at: components)
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
            pauseStartedAt = nil
        }
        displayState = .running
        workoutSession.resume()
        broadcastCompanionSnapshot()
    }

    func end() {
        guard let workoutSession else { return }
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

    func markSplit() {
        guard isSessionActive else {
            statusMessage = "Start a workout before marking a split."
            return
        }

        splitCount += 1
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

    func submitEffortScore(_ score: Int) {
        lastEffortScore = score
        postWorkoutDestination = .none
        displayState = .idle
        lastCompletedWorkoutTitle = nil
        lastCompletedWorkoutSubtitle = nil
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
        location: HKWorkoutSessionLocationType
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

        Task {
            authorizationGranted = await requestAuthorizationIfNeeded()
            guard authorizationGranted else {
                displayState = .failed
                statusMessage = "Health permissions are required."
                return
            }

            do {
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

                session.delegate = self
                builder.delegate = self

                let startDate = Date()
                workoutStartDate = startDate
                session.startActivity(with: startDate)
                try await builder.beginCollection(at: startDate)
                isMirroringToPhone = await ensureCompanionMirroring()

                displayState = .running
                statusMessage = "Workout in progress"
                startElapsedTimer()
                rebuildMetrics()
                broadcastCompanionSnapshot()
            } catch {
                displayState = .failed
                statusMessage = "Could not start workout."
            }
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

    private func rebuildMetrics() {
        guard let workoutBuilder else {
            metrics = []
            return
        }

        var cards: [WatchLiveMetric] = []

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
        broadcastCompanionSnapshot()
    }

    private func broadcastCompanionSnapshot() {
        guard isMirroringToPhone, let workoutSession else { return }
        guard #available(watchOS 10.0, *) else { return }

        let payload = CompanionWorkoutSnapshotPayload(
            title: activeTitle ?? watchWorkoutDisplayName(activeActivity ?? .running),
            stateText: displayState.rawValue.capitalized,
            elapsedTime: elapsedTime,
            metrics: metrics.map {
                CompanionWorkoutMetricPayload(
                    id: $0.id,
                    title: $0.title,
                    valueText: $0.valueText,
                    symbol: $0.symbol,
                    tintName: companionTintName(for: $0.id)
                )
            }
        )

        Task {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? await workoutSession.sendToRemoteWorkoutSession(data: data)
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
            case .paused:
                accumulatedElapsedTime = currentElapsedTime(at: date)
                pauseStartedAt = date
                elapsedTime = accumulatedElapsedTime
                displayState = .paused
                statusMessage = "Workout paused"
                broadcastCompanionSnapshot()
            case .ended:
                elapsedTime = currentElapsedTime(at: date)
                displayState = .ended
                statusMessage = "Workout ended"
                broadcastCompanionSnapshot()
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
                    self.postWorkoutDestination = .effortPrompt
                case .startAnotherWorkout:
                    self.postWorkoutDestination = .nextWorkoutPicker
                case .none:
                    self.postWorkoutDestination = .none
                    self.displayState = .idle
                }
                self.pendingEndAction = .none
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
            stopElapsedTimer()
            isMirroringToPhone = false
            pauseStartedAt = nil
            accumulatedElapsedTime = 0
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
