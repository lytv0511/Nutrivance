import Foundation
import HealthKit
import WatchConnectivity
import SwiftUI

struct WatchDashboardPayload: Codable {
    let generatedAt: Date
    let strainWeek: [WatchMetricPointPayload]
    let recoveryWeek: [WatchMetricPointPayload]
    let readinessWeek: [WatchMetricPointPayload]
    let trainingLoadWeek: [WatchMetricPointPayload]
    let hrvWeek: [WatchMetricPointPayload]
    let hrrWeek: [WatchMetricPointPayload]
    let rhrWeek: [WatchMetricPointPayload]
    let stressWeek: [WatchStressPointPayload]
    let workouts: [WatchWorkoutPayload]
    let vitals: [WatchVitalPayload]
    let coachSummaries: [String: String]
    let recommendedSleepHours: Double
    let sleepDebtHours: Double
    let sleepScheduleText: String
    let sleepHours: Double
    let sleepConsistencyScore: Double
    let sleepStages: [WatchSleepStagePayload]
    let incomingPlan: WatchProgramPlanPayload?
    let savedPlans: [WatchProgramPlanPayload]
}

struct WatchMetricPointPayload: Codable {
    let date: Date
    let value: Double
}

struct WatchStressPointPayload: Codable {
    let date: Date
    let stress: Double
    let energy: Double
    let regulation: Double
}

struct WatchWorkoutPayload: Codable {
    let id: UUID
    let title: String
    let subtitle: String
    let startDate: Date
    let durationMinutes: Int
    let calories: Int
    let distanceKilometers: Double?
    let averageHeartRate: Int
    let maxHeartRate: Int
    let strain: Double
    let load: Double
    let zoneMinutes: [Double]
    let note: String
}

struct WatchVitalPayload: Codable {
    let title: String
    let value: Double
    let displayValue: String
    let minimum: Double
    let normalLowerBound: Double
    let normalUpperBound: Double
    let maximum: Double
}

struct WatchSleepStagePayload: Codable {
    let name: String
    let hours: Double
    let colorName: String
}

struct WatchPlanCoordinatePayload: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

struct WatchProgramPlanPayload: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let summary: String
    let todayFocus: String
    let activityRawValue: UInt
    let locationRawValue: Int
    let routeName: String?
    let trailhead: WatchPlanCoordinatePayload?
    let routeCoordinates: [WatchPlanCoordinatePayload]
    let phases: [WatchProgramPhasePayload]
    let sourceDeviceLabel: String
    let createdAt: Date
    let expiresAt: Date?
}

struct WatchPhaseObjectivePayload: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case time
        case distance
        case energy
        case heartRateZone
        case pacer
        case routeDistance
    }

    let kind: Kind
    let targetValue: Double
    let secondaryValue: Double?
    let label: String?

    init(
        kind: Kind,
        targetValue: Double,
        secondaryValue: Double? = nil,
        label: String? = nil
    ) {
        self.kind = kind
        self.targetValue = targetValue
        self.secondaryValue = secondaryValue
        self.label = label
    }
}

struct WatchProgramMicroStagePayload: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let notes: String
    let plannedMinutes: Int
    let repeats: Int
    let repeatSetLabel: String?
    let objective: WatchPhaseObjectivePayload
}

struct WatchProgramPhasePayload: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let activityID: String
    let activityRawValue: UInt
    let locationRawValue: Int
    let plannedMinutes: Int
    let objective: WatchPhaseObjectivePayload?
    let microStages: [WatchProgramMicroStagePayload]?

    init(
        id: UUID,
        title: String,
        subtitle: String,
        activityID: String,
        activityRawValue: UInt,
        locationRawValue: Int,
        plannedMinutes: Int,
        objective: WatchPhaseObjectivePayload?,
        microStages: [WatchProgramMicroStagePayload]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.activityID = activityID
        self.activityRawValue = activityRawValue
        self.locationRawValue = locationRawValue
        self.plannedMinutes = plannedMinutes
        self.objective = objective
        self.microStages = microStages
    }
}

private struct WatchLocalSleepSnapshot {
    let recommendedSleepHours: Double
    let sleepDebtHours: Double
    let sleepScheduleText: String
    let sleepHours: Double
    let sleepConsistencyScore: Double
    let sleepStages: [(name: String, hours: Double, color: Color)]
}

@MainActor
extension WatchDashboardStore {
    func startLiveServices() {
        guard !hasStartedLiveServices else { return }
        hasStartedLiveServices = true
        connectivityBridge.attach(to: self)
        healthBridge.attach(to: self)
        connectivityBridge.requestImmediateRefresh()

        Task { @MainActor in
            await Task.yield()
            workoutManager.activate()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.healthBridge.refresh()
        }
    }

    func refreshLiveData() {
        connectivityBridge.requestImmediateRefresh()
        healthBridge.refresh()
    }

    func applySyncedPayload(_ payload: WatchDashboardPayload) {
        strainWeek = payload.strainWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        recoveryWeek = payload.recoveryWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        readinessWeek = payload.readinessWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        trainingLoadWeek = payload.trainingLoadWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        hrvWeek = payload.hrvWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        hrrWeek = payload.hrrWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        rhrWeek = payload.rhrWeek.map { MetricPoint(date: $0.date, value: $0.value) }
        stressWeek = payload.stressWeek.map {
            StressPoint(
                date: $0.date,
                stress: $0.stress,
                energy: $0.energy,
                regulation: $0.regulation
            )
        }
        workouts = payload.workouts.map {
            WorkoutSession(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                startDate: $0.startDate,
                durationMinutes: $0.durationMinutes,
                calories: $0.calories,
                distanceKilometers: $0.distanceKilometers,
                averageHeartRate: $0.averageHeartRate,
                maxHeartRate: $0.maxHeartRate,
                strain: $0.strain,
                load: $0.load,
                zoneMinutes: $0.zoneMinutes,
                note: $0.note
            )
        }
        vitals = payload.vitals.map {
            VitalGauge(
                title: $0.title,
                value: $0.value,
                displayValue: $0.displayValue,
                minimum: $0.minimum,
                normalRange: $0.normalLowerBound...$0.normalUpperBound,
                maximum: $0.maximum
            )
        }
        for window in CoachWindow.allCases {
            if let summary = payload.coachSummaries[window.rawValue], !summary.isEmpty {
                coachSummaries[window] = summary
            }
        }

        recommendedSleepHours = payload.recommendedSleepHours
        sleepDebtHours = payload.sleepDebtHours
        sleepScheduleText = payload.sleepScheduleText
        sleepHours = payload.sleepHours
        sleepConsistency = payload.sleepConsistencyScore
        sleepStages = payload.sleepStages.map {
            ($0.name, $0.hours, sleepStageColor(named: $0.colorName))
        }
        incomingPlan = payload.incomingPlan
        savedPlans = payload.savedPlans
        markSynced(at: payload.generatedAt)
    }

    func applyLocalMindfulness(minutesByDay: [Date: Double]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let points = (0..<7).compactMap { offset -> MetricPoint? in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else {
                return nil
            }
            let minutes = minutesByDay[date] ?? 0
            let score = min(100, minutes * 5)
            return MetricPoint(date: date, value: score)
        }
        mindfulnessWeek = points
    }

    func applyLocalStats(
        activeEnergy: Double,
        steps: Double,
        exerciseMinutes: Double,
        distanceMeters: Double
    ) {
        stats = [
            ("Calories", "\(Int(activeEnergy.rounded())) kcal", "flame.fill", .orange),
            ("Steps", NumberFormatter.localizedString(from: NSNumber(value: Int(steps.rounded())), number: .decimal), "figure.walk", .green),
            ("Active", "\(Int(exerciseMinutes.rounded())) min", "bolt.heart.fill", .cyan),
            ("Move", String(format: "%.1f km", distanceMeters / 1000), "location.fill", .yellow)
        ]
    }

    fileprivate func applyLocalSleepSnapshot(_ snapshot: WatchLocalSleepSnapshot) {
        recommendedSleepHours = snapshot.recommendedSleepHours
        sleepDebtHours = snapshot.sleepDebtHours
        sleepScheduleText = snapshot.sleepScheduleText
        sleepHours = snapshot.sleepHours
        sleepConsistency = snapshot.sleepConsistencyScore
        sleepStages = snapshot.sleepStages
    }

    func mergeLocalWorkouts(_ localWorkouts: [WorkoutSession]) {
        guard !localWorkouts.isEmpty else { return }

        var mergedByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        for workout in localWorkouts {
            if let synced = mergedByID[workout.id] {
                mergedByID[workout.id] = WorkoutSession(
                    id: synced.id,
                    title: synced.title,
                    subtitle: synced.subtitle == "Local HealthKit" ? workout.subtitle : synced.subtitle,
                    startDate: synced.startDate,
                    durationMinutes: synced.durationMinutes,
                    calories: max(synced.calories, workout.calories),
                    distanceKilometers: synced.distanceKilometers ?? workout.distanceKilometers,
                    averageHeartRate: synced.averageHeartRate > 0 ? synced.averageHeartRate : workout.averageHeartRate,
                    maxHeartRate: synced.maxHeartRate > 0 ? synced.maxHeartRate : workout.maxHeartRate,
                    strain: synced.strain > 0 ? synced.strain : workout.strain,
                    load: synced.load > 0 ? synced.load : workout.load,
                    zoneMinutes: synced.zoneMinutes.contains(where: { $0 > 0 }) ? synced.zoneMinutes : workout.zoneMinutes,
                    note: synced.note.contains("syncing") ? workout.note : synced.note
                )
            } else {
                mergedByID[workout.id] = workout
            }
        }

        workouts = mergedByID.values.sorted { $0.startDate > $1.startDate }
    }
}

@MainActor
final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    private enum Keys {
        static let request = "request"
        static let requestDashboardSnapshot = "dashboardSnapshot"
        static let dashboardPayload = "dashboardPayload"
    }

    private weak var store: WatchDashboardStore?
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var lastImmediateRefreshAt = Date.distantPast

    func attach(to store: WatchDashboardStore) {
        self.store = store

        guard let session else { return }
        session.delegate = self
        session.activate()

        if !session.receivedApplicationContext.isEmpty {
            applyApplicationContext(session.receivedApplicationContext)
        }
    }

    func requestImmediateRefresh() {
        guard let session else { return }

        let now = Date()
        guard now.timeIntervalSince(lastImmediateRefreshAt) > 1.5 else { return }
        lastImmediateRefreshAt = now

        if !session.receivedApplicationContext.isEmpty {
            applyApplicationContext(session.receivedApplicationContext)
        }

        guard session.activationState == .activated, session.isReachable else { return }

        session.sendMessage([Keys.request: Keys.requestDashboardSnapshot]) { [weak self] reply in
            Task { @MainActor in
                self?.applyApplicationContext(reply)
            }
        } errorHandler: { _ in
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil else { return }
        Task { @MainActor in
            self.requestImmediateRefresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                self.requestImmediateRefresh()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }

    private func applyApplicationContext(_ context: [String: Any]) {
        guard let data = context[Keys.dashboardPayload] as? Data else { return }
        guard let payload = try? JSONDecoder().decode(WatchDashboardPayload.self, from: data) else { return }
        store?.applySyncedPayload(payload)
    }
}

@MainActor
final class WatchHealthBridge {
    private let healthStore = HKHealthStore()
    private weak var store: WatchDashboardStore?
    private var hasRequestedAuthorization = false
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAt = Date.distantPast

    func attach(to store: WatchDashboardStore) {
        self.store = store
    }

    func refresh() {
        guard refreshTask == nil else { return }

        let now = Date()
        guard now.timeIntervalSince(lastRefreshAt) > 15 else { return }
        lastRefreshAt = now

        refreshTask = Task {
            defer { refreshTask = nil }
            let authorized = await requestAuthorizationIfNeeded()
            guard authorized else { return }

            async let activeEnergy = fetchTodaySum(for: .activeEnergyBurned, unit: .kilocalorie())
            async let steps = fetchTodaySum(for: .stepCount, unit: .count())
            async let exerciseMinutes = fetchTodaySum(for: .appleExerciseTime, unit: .minute())
            async let distanceMeters = fetchTodaySum(for: .distanceWalkingRunning, unit: .meter())
            async let mindfulnessByDay = fetchMindfulnessMinutesByDay(days: 7)
            async let localWorkouts = fetchRecentWorkouts(days: 2)
            async let localSleepSnapshot = fetchSleepSnapshot(days: 14)

            store?.applyLocalStats(
                activeEnergy: await activeEnergy,
                steps: await steps,
                exerciseMinutes: await exerciseMinutes,
                distanceMeters: await distanceMeters
            )
            store?.applyLocalMindfulness(minutesByDay: await mindfulnessByDay)
            store?.mergeLocalWorkouts(await localWorkouts)
            if let localSleepSnapshot = await localSleepSnapshot {
                store?.applyLocalSleepSnapshot(localSleepSnapshot)
            }
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if hasRequestedAuthorization { return true }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        let success = await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, _ in
                continuation.resume(returning: success)
            }
        }

        hasRequestedAuthorization = success
        return success
    }

    private func fetchTodaySum(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )

        let options: HKStatisticsOptions = switch identifier {
        case .activeEnergyBurned, .stepCount, .appleExerciseTime, .distanceWalkingRunning:
            .cumulativeSum
        default:
            .discreteAverage
        }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, _ in
                let value = switch options {
                case .cumulativeSum:
                    statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                default:
                    statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0
                }
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchMindfulnessMinutesByDay(days: Int) async -> [Date: Double] {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return [:]
        }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: endDate)) else {
            return [:]
        }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let grouped = (samples as? [HKCategorySample] ?? []).reduce(into: [Date: Double]()) { partialResult, sample in
                    let day = calendar.startOfDay(for: sample.startDate)
                    partialResult[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
                }
                continuation.resume(returning: grouped)
            }
            healthStore.execute(query)
        }
    }

    private func fetchRecentWorkouts(days: Int) async -> [WorkoutSession] {
        let calendar = Calendar.current
        let endDate = Date()
        let today = calendar.startOfDay(for: endDate)
        let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: today) ?? today
        let estimatedMaxHeartRate = await fetchEstimatedMaxHeartRate()

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }

        var sessions: [WorkoutSession] = []
        sessions.reserveCapacity(workouts.count)

        for workout in workouts {
            let heartRates = await fetchHeartRateSamples(for: workout)
            let averageHeartRate = heartRates.isEmpty
                ? 0
                : Int((heartRates.map(\.1).reduce(0, +) / Double(heartRates.count)).rounded())
            let maxHeartRate = Int((heartRates.map(\.1).max() ?? 0).rounded())
            let zoneMinutes = deriveZoneMinutes(from: heartRates, workout: workout, maxHeartRate: estimatedMaxHeartRate)
            let load = deriveWorkoutLoad(
                workout: workout,
                zoneMinutes: zoneMinutes,
                averageHeartRate: Double(averageHeartRate),
                estimatedMaxHeartRate: estimatedMaxHeartRate
            )

            sessions.append(
                WorkoutSession(
                    id: workout.uuid,
                    title: localizedWorkoutName(workout.workoutActivityType),
                    subtitle: localWorkoutSubtitle(for: workout),
                    startDate: workout.startDate,
                    durationMinutes: Int((workout.duration / 60).rounded()),
                    calories: Int((workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0).rounded()),
                    distanceKilometers: workout.totalDistance.map { $0.doubleValue(for: .meter()) / 1000 },
                    averageHeartRate: averageHeartRate,
                    maxHeartRate: maxHeartRate,
                    strain: min(21, max(0, load / 6)),
                    load: load,
                    zoneMinutes: zoneMinutes,
                    note: localWorkoutNote(
                        for: workout,
                        averageHeartRate: averageHeartRate,
                        maxHeartRate: maxHeartRate,
                        zoneMinutes: zoneMinutes
                    )
                )
            )
        }

        return sessions.sorted { $0.startDate > $1.startDate }
    }

    private func fetchEstimatedMaxHeartRate() async -> Double {
        do {
            let components = try healthStore.dateOfBirthComponents()
            if let birthDate = components.date {
                let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
                if let age {
                    return max(150, 211.0 - (0.64 * Double(age)))
                }
            }
        } catch {
        }

        return 190
    }

    private func fetchHeartRateSamples(for workout: HKWorkout) async -> [(Date, Double)] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    ($0.startDate, $0.quantity.doubleValue(for: HKUnit(from: "count/min")))
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func deriveZoneMinutes(
        from heartRates: [(Date, Double)],
        workout: HKWorkout,
        maxHeartRate: Double
    ) -> [Double] {
        guard !heartRates.isEmpty else { return [0, 0, 0, 0, 0] }

        var minutes = Array(repeating: 0.0, count: 5)
        let sortedHeartRates = heartRates.sorted { $0.0 < $1.0 }

        for index in sortedHeartRates.indices {
            let sample = sortedHeartRates[index]
            let nextDate = index < sortedHeartRates.count - 1
                ? sortedHeartRates[index + 1].0
                : min(workout.endDate, sample.0.addingTimeInterval(5))
            let seconds = max(0, min(nextDate.timeIntervalSince(sample.0), 30))
            let zoneNumber = derivedZoneNumber(for: sample.1, maxHeartRate: maxHeartRate)
            minutes[max(0, min(4, zoneNumber - 1))] += seconds / 60.0
        }

        return minutes
    }

    private func deriveWorkoutLoad(
        workout: HKWorkout,
        zoneMinutes: [Double],
        averageHeartRate: Double,
        estimatedMaxHeartRate: Double
    ) -> Double {
        let zoneWeightedLoad = zoneMinutes.enumerated().reduce(0.0) { partial, entry in
            partial + (entry.element * zoneWeight(for: entry.offset + 1))
        }

        if zoneWeightedLoad > 0 {
            return zoneWeightedLoad
        }

        let durationMinutes = workout.duration / 60.0
        guard durationMinutes > 0 else { return 0 }

        if averageHeartRate > 0 {
            let zoneNumber = derivedZoneNumber(for: averageHeartRate, maxHeartRate: estimatedMaxHeartRate)
            return durationMinutes * zoneWeight(for: zoneNumber)
        }

        if let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
            let intensity = energy / durationMinutes
            return durationMinutes * min(10, max(1, intensity / 8))
        }

        return durationMinutes
    }

    private func derivedZoneNumber(for heartRate: Double, maxHeartRate: Double) -> Int {
        let safeMax = max(maxHeartRate, 1)
        let percentMax = heartRate / safeMax

        switch percentMax {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    private func zoneWeight(for zoneNumber: Int) -> Double {
        switch zoneNumber {
        case 1: return 1.0
        case 2: return 2.0
        case 3: return 3.5
        case 4: return 5.0
        default: return 6.0
        }
    }

    private func localWorkoutSubtitle(for workout: HKWorkout) -> String {
        let timeLabel = workout.startDate.formatted(.dateTime.hour().minute())
        return "\(timeLabel) • Local HealthKit"
    }

    private func localWorkoutNote(
        for workout: HKWorkout,
        averageHeartRate: Int,
        maxHeartRate: Int,
        zoneMinutes: [Double]
    ) -> String {
        let topZoneIndex = zoneMinutes.enumerated().max(by: { $0.element < $1.element })?.offset
        let topZoneText = topZoneIndex.map { "mostly Zone \($0 + 1)" } ?? "steady effort"

        if averageHeartRate > 0 && maxHeartRate > 0 {
            return "\(localizedWorkoutName(workout.workoutActivityType)) averaged \(averageHeartRate) bpm, peaked at \(maxHeartRate) bpm, and stayed \(topZoneText.lowercased())."
        }

        return "\(localizedWorkoutName(workout.workoutActivityType)) synced from local HealthKit with duration, energy, and distance."
    }

    private func fetchSleepSnapshot(days: Int) async -> WatchLocalSleepSnapshot? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let calendar = Calendar.current
        let endDate = Date()
        let latestAnchor = calendar.startOfDay(for: endDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: latestAnchor) else {
            return nil
        }

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }

        let asleepSamples = samples.filter { isAsleepCategory($0.value) }
        guard !asleepSamples.isEmpty else { return nil }

        let groupedByDay = Dictionary(grouping: asleepSamples) { sample in
            calendar.startOfDay(for: sample.endDate)
        }

        var sleepHoursByDay: [Date: Double] = [:]
        var sleepStagesByDay: [Date: [String: Double]] = [:]
        var bedtimeHourByDay: [Date: Double] = [:]

        for (day, daySamples) in groupedByDay {
            var stages: [String: Double] = [:]
            for sample in daySamples {
                let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                stages[sleepStageName(for: sample.value), default: 0] += hours
            }

            sleepHoursByDay[day] = stages.values.reduce(0, +)
            sleepStagesByDay[day] = stages

            if let firstStart = daySamples.map(\.startDate).min() {
                let components = calendar.dateComponents([.hour, .minute], from: firstStart)
                bedtimeHourByDay[day] = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
            }
        }

        guard let latestDay = sleepHoursByDay.keys.max(),
              let latestSleepHours = sleepHoursByDay[latestDay] else {
            return nil
        }

        let recommendedSleepHours = min(
            9.0,
            max(
                7.0,
                sleepHoursByDay.values.isEmpty
                    ? 8.0
                    : sleepHoursByDay.values.reduce(0, +) / Double(sleepHoursByDay.count)
            )
        )
        let sleepDebtHours = max(0, recommendedSleepHours - latestSleepHours)
        let averageBedtimeHour = bedtimeHourByDay.values.isEmpty
            ? 22.5
            : bedtimeHourByDay.values.reduce(0, +) / Double(bedtimeHourByDay.count)
        let stageOrder = ["Core", "REM", "Deep", "Asleep"]
        let latestStages = stageOrder.compactMap { name -> (String, Double, Color)? in
            guard let hours = sleepStagesByDay[latestDay]?[name], hours > 0.01 else { return nil }
            return (name, hours, sleepStageColor(named: name))
        }

        return WatchLocalSleepSnapshot(
            recommendedSleepHours: recommendedSleepHours,
            sleepDebtHours: sleepDebtHours,
            sleepScheduleText: sleepScheduleText(
                bedtimeHour: averageBedtimeHour,
                sleepGoalHours: recommendedSleepHours
            ),
            sleepHours: latestSleepHours,
            sleepConsistencyScore: sleepConsistencyScore(from: bedtimeHourByDay),
            sleepStages: latestStages.isEmpty ? [("Asleep", latestSleepHours, .cyan)] : latestStages
        )
    }

    private func isAsleepCategory(_ value: Int) -> Bool {
        if #available(watchOS 9.0, *) {
            return value == HKCategoryValueSleepAnalysis.asleep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        }

        return value == HKCategoryValueSleepAnalysis.asleep.rawValue
    }

    private func sleepStageName(for value: Int) -> String {
        if #available(watchOS 9.0, *) {
            switch value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                return "Core"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return "REM"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return "Deep"
            default:
                return "Asleep"
            }
        }

        return "Asleep"
    }

    private func sleepConsistencyScore(from bedtimeHourByDay: [Date: Double]) -> Double {
        let values = bedtimeHourByDay.values
        guard values.count > 1 else { return 100 }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        let stdMinutes = sqrt(variance) * 60
        return max(45, min(100, 100 - stdMinutes * 0.9))
    }

    private func sleepScheduleText(bedtimeHour: Double, sleepGoalHours: Double) -> String {
        let bedtime = date(forHourValue: bedtimeHour)
        let wakeDate = bedtime.addingTimeInterval(sleepGoalHours * 3600)
        return "\(bedtime.formatted(date: .omitted, time: .shortened)) - \(wakeDate.formatted(date: .omitted, time: .shortened))"
    }

    private func date(forHourValue hourValue: Double) -> Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        let normalized = hourValue.truncatingRemainder(dividingBy: 24)
        let hour = Int(normalized)
        let minute = Int((((normalized - floor(normalized)) * 60)).rounded()) % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }
}

private func sleepStageColor(named name: String) -> Color {
    switch name.lowercased() {
    case "core":
        return .blue
    case "rem":
        return .purple
    case "deep":
        return .indigo
    default:
        return .cyan
    }
}

private func localizedWorkoutName(_ activityType: HKWorkoutActivityType) -> String {
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
