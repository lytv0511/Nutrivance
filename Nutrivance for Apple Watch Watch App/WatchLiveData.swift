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

@MainActor
extension WatchDashboardStore {
    func startLiveServices() {
        connectivityBridge.attach(to: self)
        healthBridge.attach(to: self)
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

    func applyFallbackWorkouts(_ localWorkouts: [WorkoutSession]) {
        guard lastSyncedAt == nil || workouts.isEmpty else { return }
        workouts = localWorkouts
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

    func attach(to store: WatchDashboardStore) {
        self.store = store
    }

    func refresh() {
        Task {
            let authorized = await requestAuthorizationIfNeeded()
            guard authorized else { return }

            async let activeEnergy = fetchTodaySum(for: .activeEnergyBurned, unit: .kilocalorie())
            async let steps = fetchTodaySum(for: .stepCount, unit: .count())
            async let exerciseMinutes = fetchTodaySum(for: .appleExerciseTime, unit: .minute())
            async let distanceMeters = fetchTodaySum(for: .distanceWalkingRunning, unit: .meter())
            async let mindfulnessByDay = fetchMindfulnessMinutesByDay(days: 7)
            async let localWorkouts = fetchFallbackWorkoutsForToday()

            store?.applyLocalStats(
                activeEnergy: await activeEnergy,
                steps: await steps,
                exerciseMinutes: await exerciseMinutes,
                distanceMeters: await distanceMeters
            )
            store?.applyLocalMindfulness(minutesByDay: await mindfulnessByDay)
            store?.applyFallbackWorkouts(await localWorkouts)
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if hasRequestedAuthorization { return true }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!
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

    private func fetchFallbackWorkoutsForToday() async -> [WorkoutSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
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

        return workouts.map { workout in
            WorkoutSession(
                id: workout.uuid,
                title: localizedWorkoutName(workout.workoutActivityType),
                subtitle: "Local HealthKit",
                startDate: workout.startDate,
                durationMinutes: Int((workout.duration / 60).rounded()),
                calories: Int((workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0).rounded()),
                distanceKilometers: workout.totalDistance?.doubleValue(for: .meter()) == nil ? nil : (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000,
                averageHeartRate: 0,
                maxHeartRate: 0,
                strain: 0,
                load: 0,
                zoneMinutes: [0, 0, 0, 0, 0],
                note: "Detailed workout analytics are syncing from your iPhone."
            )
        }
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
