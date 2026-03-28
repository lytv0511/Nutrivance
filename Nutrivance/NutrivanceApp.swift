import Combine
import HealthKit
import SwiftUI
import SwiftData
import UIKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

private func allViewControllers(from root: UIViewController) -> [UIViewController] {
    var controllers: [UIViewController] = [root]
    
    if let presented = root.presentedViewController {
        controllers.append(contentsOf: allViewControllers(from: presented))
    }
    
    for child in root.children {
        controllers.append(contentsOf: allViewControllers(from: child))
    }
    
    return controllers
}

#if canImport(WatchConnectivity)
private struct WatchDashboardPayload: Codable {
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

private struct WatchMetricPointPayload: Codable {
    let date: Date
    let value: Double
}

private struct WatchStressPointPayload: Codable {
    let date: Date
    let stress: Double
    let energy: Double
    let regulation: Double
}

private struct WatchWorkoutPayload: Codable {
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

private struct WatchVitalPayload: Codable {
    let title: String
    let value: Double
    let displayValue: String
    let minimum: Double
    let normalLowerBound: Double
    let normalUpperBound: Double
    let maximum: Double
}

private struct WatchSleepStagePayload: Codable {
    let name: String
    let hours: Double
    let colorName: String
}

private struct WatchCoachCacheEntry: Codable {
    let summaryText: String
    let generatedAt: Date
    let timeFilterRawValue: String
    let suggestionID: String
    let expiresAt: Date?
}

private struct WatchLoadSnapshot {
    let date: Date
    let sessionLoad: Double
    let totalDailyLoad: Double
    let acuteLoad: Double
    let chronicLoad: Double
    let acwr: Double
    let strainScore: Double
}

@MainActor
final class WatchDashboardSyncBridge: NSObject {
    static let shared = WatchDashboardSyncBridge()

    private enum Keys {
        static let dashboardPayload = "dashboardPayload"
        static let request = "request"
        static let dashboardSnapshot = "dashboardSnapshot"
        static let showLiveWorkout = "showLiveWorkout"
        static let accepted = "accepted"
    }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let engine = HealthStateEngine.shared

    private var cancellables: Set<AnyCancellable> = []
    private var pendingSyncTask: Task<Void, Never>?
    private var latestPayloadData: Data?
    private var hasActivatedSession = false

    override init() {
        super.init()
        configureObservers()
    }

    func activateIfNeeded() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        scheduleSnapshotRefresh(reason: "startup", delayNanoseconds: 1_000_000_000)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        scheduleSnapshotRefresh(reason: "scene-active", delayNanoseconds: 600_000_000)
    }

    private func configureObservers() {
        engine.objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh(reason: "engine")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh(reason: "defaults")
            }
            .store(in: &cancellables)
    }

    private func scheduleSnapshotRefresh(
        reason: String,
        delayNanoseconds: UInt64 = 250_000_000
    ) {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            self.publishLatestSnapshot(reason: reason)
        }
    }

    private func publishLatestSnapshot(reason: String) {
        let payload = buildPayload()
        guard let data = try? encoder.encode(payload) else { return }

        latestPayloadData = data
        pushLatestPayloadToWatch()
        print("[WatchSync] Published dashboard snapshot (\(reason)).")
    }

    private func pushLatestPayloadToWatch() {
        guard let session, hasActivatedSession, let latestPayloadData else { return }
        do {
            try session.updateApplicationContext([Keys.dashboardPayload: latestPayloadData])
        } catch {
            print("[WatchSync] Failed to update application context: \(error.localizedDescription)")
        }
    }

    private func buildPayload() -> WatchDashboardPayload {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekDays = watchDateSequence(endingAt: today, days: 7)
        let loadSnapshots = watchDailyLoadSnapshots(
            workouts: engine.workoutAnalytics,
            estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
            endingAt: today,
            days: 7
        )
        let recoveryPairs: [(Date, Double)] = weekDays.compactMap { day in
            watchRecoveryScore(for: day, engine: engine).map { (day, $0) }
        }
        let recoveryLookup: [Date: Double] = Dictionary(uniqueKeysWithValues: recoveryPairs)
        let readinessPairs: [(Date, Double)] = loadSnapshots.compactMap { snapshot in
            guard let recovery = recoveryLookup[snapshot.date],
                  let readiness = watchReadinessScore(
                    for: snapshot.date,
                    recoveryScore: recovery,
                    strainScore: snapshot.strainScore,
                    engine: engine
                  ) else {
                return nil
            }
            return (snapshot.date, readiness)
        }
        let readinessLookup = Dictionary(uniqueKeysWithValues: readinessPairs)

        let midpointSeries = watchFilteredDailyValues(engine.sleepMidpointHours, endingAt: today, days: 7)
        let sleepConsistencyScore = watchSleepConsistencyScore(
            midpointSeries: midpointSeries,
            fallback: engine.sleepConsistency ?? 0
        )
        let latestSleepDay = engine.sleepStages.keys.max() ?? today
        let sleepStagePayloads = watchSleepStagePayloads(from: engine.sleepStages[latestSleepDay] ?? [:])
        let sleepHours = engine.anchoredSleepDuration[today] ?? engine.dailySleepDuration[today] ?? engine.sleepHours ?? 0
        let recommendedSleepHours = min(max(engine.sleepBaseline60Day?.mean ?? engine.sleepBaseline7Day ?? 8.0, 7.0), 9.0)
        let sleepDebtHours = max(0, recommendedSleepHours - sleepHours)

        return WatchDashboardPayload(
            generatedAt: Date(),
            strainWeek: loadSnapshots.map { WatchMetricPointPayload(date: $0.date, value: $0.strainScore) },
            recoveryWeek: weekDays.compactMap { day in
                recoveryLookup[day].map { WatchMetricPointPayload(date: day, value: $0) }
            },
            readinessWeek: weekDays.compactMap { day in
                readinessLookup[day].map { WatchMetricPointPayload(date: day, value: $0) }
            },
            trainingLoadWeek: loadSnapshots.map { WatchMetricPointPayload(date: $0.date, value: $0.totalDailyLoad) },
            hrvWeek: engine.timeSeries(for: "hrv", days: 7).map { WatchMetricPointPayload(date: $0.0, value: $0.1) },
            hrrWeek: watchFilteredDailyValues(engine.dailyHRRAggregates, endingAt: today, days: 7).map {
                WatchMetricPointPayload(date: $0.0, value: $0.1)
            },
            rhrWeek: engine.timeSeries(for: "rhr", days: 7).map { WatchMetricPointPayload(date: $0.0, value: $0.1) },
            stressWeek: watchStressPayloads(
                days: weekDays,
                recoveryLookup: recoveryLookup,
                readinessLookup: readinessLookup,
                hrvSeries: Dictionary(uniqueKeysWithValues: engine.timeSeries(for: "hrv", days: 7))
            ),
            workouts: watchWorkoutPayloads(
                engine: engine,
                loadSnapshots: loadSnapshots
            ),
            vitals: watchVitalPayloads(
                engine: engine,
                today: today,
                sleepHours: sleepHours,
                sleepConsistencyScore: sleepConsistencyScore
            ),
            coachSummaries: watchCoachSummaries(),
            recommendedSleepHours: recommendedSleepHours,
            sleepDebtHours: sleepDebtHours,
            sleepScheduleText: watchSleepScheduleText(
                bedtimeHour: watchAverageBedtimeHour(engine: engine, endingAt: today),
                sleepGoalHours: recommendedSleepHours
            ),
            sleepHours: sleepHours,
            sleepConsistencyScore: sleepConsistencyScore,
            sleepStages: sleepStagePayloads
        )
    }
}

extension WatchDashboardSyncBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.hasActivatedSession = error == nil && activationState == .activated
            self.pushLatestPayloadToWatch()
            self.scheduleSnapshotRefresh(reason: "session-activated")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            session.activate()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void
    ) {
        Task { @MainActor in
            switch message[Keys.request] as? String {
            case Keys.dashboardSnapshot:
                if self.latestPayloadData == nil {
                    self.publishLatestSnapshot(reason: "watch-request")
                }

                replyHandler([
                    Keys.dashboardPayload: self.latestPayloadData ?? Data()
                ])
            case Keys.showLiveWorkout:
                CompanionWorkoutLiveManager.shared.primePresentationFromWatchRequest()
                replyHandler([Keys.accepted: true])
            default:
                replyHandler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        guard (userInfo[Keys.request] as? String) == Keys.showLiveWorkout else { return }

        Task { @MainActor in
            CompanionWorkoutLiveManager.shared.primePresentationFromWatchRequest()
        }
    }
}

@MainActor
private func watchWorkoutPayloads(
    engine: HealthStateEngine,
    loadSnapshots: [WatchLoadSnapshot]
) -> [WatchWorkoutPayload] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    let loadLookup = Dictionary(uniqueKeysWithValues: loadSnapshots.map { ($0.date, $0) })

    return engine.workoutAnalytics
        .filter {
            calendar.isDate($0.workout.startDate, inSameDayAs: today) ||
            calendar.isDate($0.workout.startDate, inSameDayAs: yesterday)
        }
        .sorted { $0.workout.startDate > $1.workout.startDate }
        .map { pair in
            let day = calendar.startOfDay(for: pair.workout.startDate)
            let averageHeartRate = pair.analytics.heartRates.isEmpty
                ? 0
                : Int((pair.analytics.heartRates.map(\.1).reduce(0, +) / Double(pair.analytics.heartRates.count)).rounded())
            let maxHeartRate = Int((pair.analytics.peakHR ?? pair.analytics.heartRates.map(\.1).max() ?? 0).rounded())
            let zoneMinutes = watchZoneMinutes(from: pair.analytics)
            let workoutLoad = HealthStateEngine.proWorkoutLoad(
                for: pair.workout,
                analytics: pair.analytics,
                estimatedMaxHeartRate: engine.estimatedMaxHeartRate
            )
            let strainScore = loadLookup[day]?.strainScore ?? min(21, max(0, workoutLoad / 6))

            return WatchWorkoutPayload(
                id: pair.workout.uuid,
                title: pair.workout.workoutActivityType.name,
                subtitle: watchWorkoutSubtitle(for: pair.workout),
                startDate: pair.workout.startDate,
                durationMinutes: Int((pair.workout.duration / 60).rounded()),
                calories: Int((pair.workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0).rounded()),
                distanceKilometers: pair.workout.totalDistance.map { $0.doubleValue(for: .meter()) / 1000 },
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                strain: strainScore,
                load: workoutLoad,
                zoneMinutes: zoneMinutes,
                note: watchWorkoutNote(for: pair.analytics)
            )
        }
}

@MainActor
private func watchVitalPayloads(
    engine: HealthStateEngine,
    today: Date,
    sleepHours: Double,
    sleepConsistencyScore: Double
) -> [WatchVitalPayload] {
    let sleepHR = engine.dailySleepHeartRate[today] ?? engine.basalSleepingHeartRate[today] ?? engine.restingHeartRate ?? 0
    let respiratory = engine.respiratoryRate[today] ?? 0
    let wristTemperature = engine.wristTemperature[today] ?? 0
    let oxygen = engine.spO2[today] ?? 0

    return [
        WatchVitalPayload(
            title: "Sleep HR",
            value: sleepHR,
            displayValue: String(format: "%.0f bpm", sleepHR),
            minimum: 42,
            normalLowerBound: 48,
            normalUpperBound: 60,
            maximum: 72
        ),
        WatchVitalPayload(
            title: "Respiratory",
            value: respiratory,
            displayValue: String(format: "%.1f br/min", respiratory),
            minimum: 10,
            normalLowerBound: 12,
            normalUpperBound: 18,
            maximum: 22
        ),
        WatchVitalPayload(
            title: "Wrist Temp",
            value: wristTemperature,
            displayValue: String(format: "%+.1f C", wristTemperature),
            minimum: -1.0,
            normalLowerBound: -0.3,
            normalUpperBound: 0.3,
            maximum: 1.0
        ),
        WatchVitalPayload(
            title: "SpO2",
            value: oxygen,
            displayValue: String(format: "%.1f%%", oxygen),
            minimum: 88,
            normalLowerBound: 95,
            normalUpperBound: 100,
            maximum: 100
        ),
        WatchVitalPayload(
            title: "Sleep Hours",
            value: sleepHours,
            displayValue: String(format: "%.1f h", sleepHours),
            minimum: 4,
            normalLowerBound: 7,
            normalUpperBound: 9,
            maximum: 10
        ),
        WatchVitalPayload(
            title: "Consistency",
            value: sleepConsistencyScore,
            displayValue: String(format: "%.0f%%", sleepConsistencyScore),
            minimum: 0,
            normalLowerBound: 75,
            normalUpperBound: 100,
            maximum: 100
        )
    ]
}

private func watchCoachSummaries() -> [String: String] {
    let storageKey = "strain_recovery_ai_summary_cache_v2"
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let cache = try? JSONDecoder().decode([String: WatchCoachCacheEntry].self, from: data) else {
        return [:]
    }

    let now = Date()
    let validEntries = cache.values.filter { entry in
        guard !entry.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let expiresAt = entry.expiresAt {
            return expiresAt > now
        }
        return true
    }

    let preferredEntries = validEntries.filter { $0.suggestionID == "overall" }
    let source = preferredEntries.isEmpty ? validEntries : preferredEntries

    return ["1D", "1W", "1M"].reduce(into: [String: String]()) { result, filter in
        result[filter] = source
            .filter { $0.timeFilterRawValue == filter }
            .sorted { $0.generatedAt > $1.generatedAt }
            .first?
            .summaryText
    }
}

@MainActor
private func watchRecoveryScore(
    for day: Date,
    engine: HealthStateEngine
) -> Double? {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvPairs: [(Date, Double)] = engine.dailyHRV.map { ($0.date, $0.average) }
    let hrvLookup: [Date: Double] = Dictionary(uniqueKeysWithValues: hrvPairs)
    let latestHRV = HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.effectHRV)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: hrvLookup)
    let restingHeartRate = HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate)
    let sleepDurationHours = HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration)
    let timeInBedHours = HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredTimeInBed)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration)
    let bedtimeVarianceMinutes = HealthStateEngine.circularStandardDeviationMinutes(
        from: engine.sleepStartHours,
        around: normalizedDay
    )
    let inputs = HealthStateEngine.proRecoveryInputs(
        latestHRV: latestHRV,
        restingHeartRate: restingHeartRate,
        sleepDurationHours: sleepDurationHours,
        timeInBedHours: timeInBedHours,
        hrvBaseline60Day: engine.hrvBaseline60Day,
        rhrBaseline60Day: engine.rhrBaseline60Day,
        sleepBaseline60Day: engine.sleepBaseline60Day,
        hrvBaseline7Day: engine.hrvBaseline7Day,
        rhrBaseline7Day: engine.rhrBaseline7Day,
        sleepBaseline7Day: engine.sleepBaseline7Day,
        bedtimeVarianceMinutes: bedtimeVarianceMinutes
    )

    guard !inputs.isInconclusive else { return nil }
    guard inputs.hrvZScore != nil || inputs.restingHeartRateZScore != nil || inputs.sleepRatio != nil else {
        return nil
    }

    return HealthStateEngine.proRecoveryScore(from: inputs)
}

@MainActor
private func watchReadinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    engine: HealthStateEngine
) -> Double? {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvPairs: [(Date, Double)] = engine.dailyHRV.map { ($0.date, $0.average) }
    let hrvLookup: [Date: Double] = Dictionary(uniqueKeysWithValues: hrvPairs)
    let hrvValue = hrvLookup[normalizedDay]

    let hrvTrendComponent: Double
    if let hrvValue, let baseline = engine.hrvBaseline7Day, baseline > 0 {
        let deviation = (hrvValue - baseline) / baseline
        hrvTrendComponent = max(0, min(100, (deviation * 200) + 50))
    } else {
        hrvTrendComponent = engine.hrvTrendScore
    }

    let normalizedStrain = HealthStateEngine.normalizedStrainPercent(from: strainScore)
    let readiness = (recoveryScore * 0.70) + (hrvTrendComponent * 0.10) - (normalizedStrain * 0.25) + 25
    return max(0, min(100, readiness))
}

private func watchDailyLoadSnapshots(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    estimatedMaxHeartRate: Double,
    endingAt endDate: Date,
    days: Int
) -> [WatchLoadSnapshot] {
    let calendar = Calendar.current
    let end = calendar.startOfDay(for: endDate)
    let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
    let loadWindowStart = calendar.date(byAdding: .day, value: -27, to: start) ?? start

    var sessionLoadByDay: [Date: Double] = [:]
    var workoutMinutesByDay: [Date: Double] = [:]

    for (workout, analytics) in workouts {
        let day = calendar.startOfDay(for: workout.startDate)
        let load = HealthStateEngine.proWorkoutLoad(
            for: workout,
            analytics: analytics,
            estimatedMaxHeartRate: estimatedMaxHeartRate
        )
        sessionLoadByDay[day, default: 0] += load
        workoutMinutesByDay[day, default: 0] += workout.duration / 60
    }

    let loadDates = watchDateSequence(from: loadWindowStart, to: end)
    let orderedLoads = loadDates.map { day in
        let sessionLoad = sessionLoadByDay[day, default: 0]
        let activeMinutes = workoutMinutesByDay[day, default: 0]
        return sessionLoad + HealthStateEngine.passiveDailyBaseLoad(activeMinutes: activeMinutes)
    }

    return watchDateSequence(from: start, to: end).map { day in
        let stateIndex = loadDates.firstIndex(of: day) ?? max(loadDates.count - 1, 0)
        let state = HealthStateEngine.proTrainingLoadState(loads: orderedLoads, index: stateIndex)

        return WatchLoadSnapshot(
            date: day,
            sessionLoad: sessionLoadByDay[day, default: 0],
            totalDailyLoad: orderedLoads[stateIndex],
            acuteLoad: state.acuteLoad,
            chronicLoad: state.chronicLoad,
            acwr: state.acwr,
            strainScore: HealthStateEngine.proStrainScore(
                acuteLoad: state.acuteLoad,
                chronicLoad: state.chronicLoad
            )
        )
    }
}

private func watchFilteredDailyValues(
    _ values: [Date: Double],
    endingAt endDate: Date,
    days: Int
) -> [(Date, Double)] {
    let calendar = Calendar.current
    let end = calendar.startOfDay(for: endDate)
    let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end

    return values
        .filter { date, _ in
            date >= start && date <= end
        }
        .sorted { $0.0 < $1.0 }
}

private func watchDateSequence(endingAt endDate: Date, days: Int) -> [Date] {
    let calendar = Calendar.current
    let end = calendar.startOfDay(for: endDate)
    let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
    return watchDateSequence(from: start, to: end)
}

private func watchDateSequence(from start: Date, to end: Date) -> [Date] {
    let calendar = Calendar.current
    let safeStart = calendar.startOfDay(for: start)
    let safeEnd = calendar.startOfDay(for: end)
    guard safeStart <= safeEnd else { return [] }

    let dayCount = (calendar.dateComponents([.day], from: safeStart, to: safeEnd).day ?? 0) + 1
    return (0..<dayCount).compactMap {
        calendar.date(byAdding: .day, value: $0, to: safeStart)
    }
}

private func watchSleepConsistencyScore(
    midpointSeries: [(Date, Double)],
    fallback: Double
) -> Double {
    let values = midpointSeries.map(\.1)
    let midpointDeviationHours = watchStandardDeviation(values) ?? fallback
    let best = 0.25
    let worst = 3.0
    let clamped = min(max(midpointDeviationHours, best), worst)
    return ((worst - clamped) / (worst - best)) * 100
}

private func watchStandardDeviation(_ values: [Double]) -> Double? {
    guard values.count > 1 else { return values.first }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
    return sqrt(max(variance, 0))
}

private func watchStressPayloads(
    days: [Date],
    recoveryLookup: [Date: Double],
    readinessLookup: [Date: Double],
    hrvSeries: [Date: Double]
) -> [WatchStressPointPayload] {
    let hrvValues = hrvSeries.values
    let baselineHRV = hrvValues.isEmpty ? 50 : (hrvValues.reduce(0, +) / Double(hrvValues.count))

    return days.map { day in
        let recovery = recoveryLookup[day] ?? 50
        let readiness = readinessLookup[day] ?? 50
        let hrv = hrvSeries[day] ?? baselineHRV
        let deviation = baselineHRV > 0 ? (hrv - baselineHRV) / baselineHRV : 0

        let stress = max(0, min(100, 55 - (deviation * 120) - ((recovery - 50) * 0.35)))
        let energy = max(0, min(100, 45 + (deviation * 90) + ((readiness - 50) * 0.45)))
        let regulation = max(0, min(100, (recovery * 0.55) + (readiness * 0.45) - abs(stress - 50) * 0.2))

        return WatchStressPointPayload(
            date: day,
            stress: stress,
            energy: energy,
            regulation: regulation
        )
    }
}

private func watchSleepStagePayloads(from stages: [String: Double]) -> [WatchSleepStagePayload] {
    let preferredKeys: [(String, String)] = [
        ("core", "blue"),
        ("rem", "purple"),
        ("deep", "indigo")
    ]

    return preferredKeys.compactMap { key, colorName in
        guard let value = stages[key], value > 0 else { return nil }
        return WatchSleepStagePayload(
            name: key.capitalized,
            hours: value,
            colorName: colorName
        )
    }
}

@MainActor
private func watchAverageBedtimeHour(
    engine: HealthStateEngine,
    endingAt endDate: Date
) -> Double? {
    let bedtimeSeries = watchFilteredDailyValues(engine.sleepStartHours, endingAt: endDate, days: 7).map(\.1)
    guard !bedtimeSeries.isEmpty else { return nil }
    return bedtimeSeries.reduce(0, +) / Double(bedtimeSeries.count)
}

private func watchSleepScheduleText(
    bedtimeHour: Double?,
    sleepGoalHours: Double
) -> String {
    guard let bedtimeHour else {
        return "10:30 PM - 7:00 AM"
    }

    let wakeHour = fmod(bedtimeHour + sleepGoalHours, 24)
    return "\(watchClockString(fromDecimalHour: bedtimeHour)) - \(watchClockString(fromDecimalHour: wakeHour))"
}

private func watchClockString(fromDecimalHour hour: Double) -> String {
    let normalized = hour >= 0 ? hour : (24 + hour)
    let wholeHour = Int(normalized) % 24
    let minute = Int(((normalized - Double(Int(normalized))) * 60).rounded()) % 60
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"

    var components = DateComponents()
    components.hour = wholeHour
    components.minute = minute
    let date = Calendar.current.date(from: components) ?? Date()
    return formatter.string(from: date)
}

private func watchZoneMinutes(from analytics: WorkoutAnalytics) -> [Double] {
    var minutes = Array(repeating: 0.0, count: 5)

    for breakdown in analytics.hrZoneBreakdown {
        let zoneIndex = max(0, min(4, breakdown.zone.zoneNumber - 1))
        minutes[zoneIndex] += breakdown.timeInZone / 60
    }

    return minutes
}

private func watchWorkoutSubtitle(for workout: HKWorkout) -> String {
    let timeLabel = workout.startDate.formatted(.dateTime.hour().minute())
    return "\(timeLabel) • \(workout.workoutActivityType.name)"
}

private func watchWorkoutNote(for analytics: WorkoutAnalytics) -> String {
    var fragments: [String] = []

    if let hrr2 = analytics.hrr2 {
        fragments.append("HRR 2m \(Int(hrr2.rounded())) bpm")
    }
    if let vo2 = analytics.vo2Max {
        fragments.append(String(format: "VO2 %.1f", vo2))
    }
    if let peakHR = analytics.peakHR {
        fragments.append("Peak HR \(Int(peakHR.rounded()))")
    }

    if fragments.isEmpty {
        return "Workout analytics synced from your iPhone."
    }

    return fragments.joined(separator: " • ")
}
#endif

private func topViewController(from controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController {
        return topViewController(from: presented)
    }
    
    if let navigationController = controller as? UINavigationController,
       let visibleViewController = navigationController.visibleViewController {
        return topViewController(from: visibleViewController)
    }
    
    if let tabBarController = controller as? UITabBarController,
       let selectedViewController = tabBarController.selectedViewController {
        return topViewController(from: selectedViewController)
    }
    
    for child in controller.children.reversed() {
        return topViewController(from: child)
    }
    
    return controller
}

private func activeNavigationController() -> UINavigationController? {
    let activeScenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
    
    for scene in activeScenes {
        if let keyWindow = scene.windows.first(where: \.isKeyWindow),
           let rootViewController = keyWindow.rootViewController {
            let topController = topViewController(from: rootViewController)
            
            if let navigationController = topController.navigationController {
                return navigationController
            }
            
            if let navigationController = topController as? UINavigationController {
                return navigationController
            }
            
            for controller in allViewControllers(from: rootViewController).reversed() {
                if let navigationController = controller as? UINavigationController {
                    return navigationController
                }
            }
        }
    }
    
    return nil
}

extension Notification.Name {
    static let nutrivanceViewControlToday = Notification.Name("nutrivance.viewControl.today")
    static let nutrivanceViewControlPrevious = Notification.Name("nutrivance.viewControl.previous")
    static let nutrivanceViewControlNext = Notification.Name("nutrivance.viewControl.next")
    static let nutrivanceViewControlFilter1 = Notification.Name("nutrivance.viewControl.filter1")
    static let nutrivanceViewControlFilter2 = Notification.Name("nutrivance.viewControl.filter2")
    static let nutrivanceViewControlFilter3 = Notification.Name("nutrivance.viewControl.filter3")
    static let nutrivanceViewControlFilter4 = Notification.Name("nutrivance.viewControl.filter4")
    static let nutrivanceViewControlRefresh = Notification.Name("nutrivance.viewControl.refresh")
    static let nutrivanceViewControlSaveToJournal = Notification.Name("nutrivance.viewControl.saveToJournal")
}

func toggleSystemSidebar() {
    #if os(iOS)
    let selector = Selector(("toggleSidebar:"))
    let activeScenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
    
    for scene in activeScenes {
        if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
            if let rootViewController = keyWindow.rootViewController {
                for controller in allViewControllers(from: rootViewController) {
                    if let target = controller.targetViewController(forAction: selector, sender: nil) {
                        _ = target.perform(selector, with: nil)
                        return
                    }
                    
                    if controller.responds(to: selector) {
                        _ = controller.perform(selector, with: nil)
                        return
                    }
                }
                
                UIApplication.shared.sendAction(
                    selector,
                    to: nil,
                    from: rootViewController,
                    for: nil
                )
                return
            }
            
            UIApplication.shared.sendAction(
                selector,
                to: nil,
                from: keyWindow,
                for: nil
            )
            return
        }
    }
    
    UIApplication.shared.sendAction(
        selector,
        to: nil,
        from: nil,
        for: nil
    )
    #endif
}

func performBackNavigation(
    presentedDestination: Binding<AppDestination?>,
    dismissAction: (() -> Void)?
) {
    #if os(iOS)
    if let dismissAction {
        dismissAction()
        return
    }
    
    if presentedDestination.wrappedValue != nil {
        presentedDestination.wrappedValue = nil
        return
    }
    
    if let navigationController = activeNavigationController(),
       navigationController.viewControllers.count > 1 {
        navigationController.popViewController(animated: true)
        return
    }
    #endif
}

enum AppFocus: String, CaseIterable {
    case nutrition = "Nutrition"
    case fitness = "Fitness"
    case mentalHealth = "Mental Health"
}

enum RootTabSelection: Hashable {
    case dashboard
    case insights
    case labels
    case log
    case calories
    case carbs
    case protein
    case fats
    case water
    case fiber
    case vitamins
    case minerals
    case phytochemicals
    case antioxidants
    case electrolytes
    case todaysPlan
    case trainingCalendar
    case coach
    case recoveryScore
    case readiness
    case strainRecovery
    case workoutHistory
    case activityRings
    case heartZones
    case personalRecords
    case mindfulnessRealm
    case moodTracker
    case journal
    case sleep
    case stress
    case search
    case home
    case playground
}

enum AppDestination: String, CaseIterable, Hashable, Identifiable {
    case insights
    case labels
    case log
    case calories
    case carbs
    case protein
    case fats
    case water
    case fiber
    case vitamins
    case minerals
    case phytochemicals
    case antioxidants
    case electrolytes
    case todaysPlan
    case trainingCalendar
    case coach
    case recoveryScore
    case readiness
    case strainRecovery
    case workoutHistory
    case activityRings
    case heartZones
    case personalRecords
    case mindfulnessRealm
    case moodTracker
    case journal
    case sleep
    case stress

    var id: String { rawValue }
}

enum SearchScope: String, CaseIterable, Hashable {
    case all
    case nutrition
    case fitness
    case mentalHealth

    var title: String {
        switch self {
        case .all: return "Search"
        case .nutrition: return "Nutrivance"
        case .fitness: return "Movance"
        case .mentalHealth: return "Spirivance"
        }
    }

    var icon: String {
        switch self {
        case .all: return "magnifyingglass"
        case .nutrition: return "leaf.fill"
        case .fitness: return "figure.run"
        case .mentalHealth: return "brain.head.profile"
        }
    }
}

@MainActor
class NavigationState: ObservableObject {
    @Published var selectedView: String = "Dashboard"
    @Published var selectedRootTab: RootTabSelection = .dashboard
    @Published var presentedDestination: AppDestination?
    @Published var pendingWorkoutScrollID: String?
    @Published var dismissAction: (() -> Void)?
    @Published var canGoBack: Bool = false
    @Published var showFocusSwitcher = false
    @Published var appFocus: AppFocus = .fitness {
        didSet {
            if oldValue != appFocus {
                guard !Self.tab(selectedRootTab, belongsTo: appFocus) else { return }

                switch self.appFocus {
                case .nutrition:
                    self.selectedView = "Insights"
                    self.selectedRootTab = Self.defaultRootTab(for: .nutrition)
                    self.presentedDestination = nil
                case .fitness:
                    self.selectedView = "Dashboard"
                    self.selectedRootTab = Self.defaultRootTab(for: .fitness)
                    self.presentedDestination = nil
                case .mentalHealth:
                    self.selectedView = "Mindfulness Realm"
                    self.selectedRootTab = Self.defaultRootTab(for: .mentalHealth)
                    self.presentedDestination = nil
                }
            }
        }
    }
    @Published var tempFocus: AppFocus = .nutrition
    @Published var navigationPath = NavigationPath()
    @Published var isSearchBarFocused = false
    
    func setDismissAction(_ action: @escaping () -> Void) {
        dismissAction = action
        canGoBack = true
    }
    
    func clearDismissAction() {
        dismissAction = nil
        canGoBack = false
    }
    
    func cycleFocus() {
        tempFocus = switch tempFocus {
        case .nutrition: .fitness
        case .fitness: .mentalHealth
        case .mentalHealth: .nutrition
        }
        isSearchBarFocused = false
    }
    
    func cycleBackwardFocus() {
        tempFocus = switch tempFocus {
        case .nutrition: .mentalHealth
        case .fitness: .nutrition
        case .mentalHealth: .fitness
        }
    }
    
    func commitFocusChange() {
        DispatchQueue.main.async {
            self.appFocus = self.tempFocus
            self.showFocusSwitcher = false
        }
    }

    static func defaultRootTab(for focus: AppFocus) -> RootTabSelection {
        if UIDevice.current.userInterfaceIdiom == .phone {
            switch focus {
            case .nutrition: return .search
            case .fitness: return .dashboard
            case .mentalHealth: return .dashboard
            }
        }

        switch focus {
        case .nutrition: return .insights
        case .fitness: return .dashboard
        case .mentalHealth: return .mindfulnessRealm
        }
    }

    static func tab(_ tab: RootTabSelection, belongsTo focus: AppFocus) -> Bool {
        switch focus {
        case .nutrition:
            switch tab {
            case .insights, .labels, .log, .calories, .carbs, .protein, .fats, .water, .fiber, .vitamins, .minerals, .phytochemicals, .antioxidants, .electrolytes, .search:
                return true
            default:
                return false
            }
        case .fitness:
            switch tab {
            case .dashboard, .todaysPlan, .trainingCalendar, .coach, .recoveryScore, .readiness, .strainRecovery, .workoutHistory, .activityRings, .heartZones, .personalRecords:
                return true
            default:
                return false
            }
        case .mentalHealth:
            switch tab {
            case .mindfulnessRealm, .moodTracker, .journal, .sleep, .stress:
                return true
            default:
                return false
            }
        }
    }

    static func destination(for tab: RootTabSelection) -> AppDestination? {
        switch tab {
        case .insights: return .insights
        case .labels: return .labels
        case .log: return .log
        case .calories: return .calories
        case .carbs: return .carbs
        case .protein: return .protein
        case .fats: return .fats
        case .water: return .water
        case .fiber: return .fiber
        case .vitamins: return .vitamins
        case .minerals: return .minerals
        case .phytochemicals: return .phytochemicals
        case .antioxidants: return .antioxidants
        case .electrolytes: return .electrolytes
        case .todaysPlan: return .todaysPlan
        case .trainingCalendar: return .trainingCalendar
        case .coach: return .coach
        case .recoveryScore: return .recoveryScore
        case .readiness: return .readiness
        case .strainRecovery: return .strainRecovery
        case .workoutHistory: return .workoutHistory
        case .activityRings: return .activityRings
        case .heartZones: return .heartZones
        case .personalRecords: return .personalRecords
        case .mindfulnessRealm: return .mindfulnessRealm
        case .moodTracker: return .moodTracker
        case .journal: return .journal
        case .sleep: return .sleep
        case .stress: return .stress
        case .dashboard, .search, .home, .playground: return nil
        }
    }

    func navigate(
        focus: AppFocus,
        view: String,
        tab: RootTabSelection
    ) {
        appFocus = focus
        selectedView = view

        if UIDevice.current.userInterfaceIdiom == .phone {
            switch tab {
            case .dashboard, .search, .playground, .recoveryScore, .readiness, .strainRecovery, .workoutHistory, .stress:
                selectedRootTab = tab
                presentedDestination = nil
            default:
                selectedRootTab = NavigationState.defaultRootTab(for: focus)
                presentedDestination = NavigationState.destination(for: tab)
            }
            return
        }

        selectedRootTab = tab
        presentedDestination = nil
    }

    func navigateToWorkoutHistory(scrollTo workoutID: String? = nil) {
        pendingWorkoutScrollID = workoutID
        navigate(focus: .fitness, view: "Workout History", tab: .workoutHistory)
    }
}

@MainActor
class SearchState: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var selectedScope: SearchScope = .all
    
    func activateSearch(proxy: ScrollViewProxy) {
        proxy.scrollTo("searchField", anchor: .top)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isSearching = true
        }
    }
}

enum DistanceUnitPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case kilometers
    case miles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .kilometers: return "Kilometers"
        case .miles: return "Miles"
        }
    }
}

enum SpeedUnitPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case kilometersPerHour
    case milesPerHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .kilometersPerHour: return "km/h"
        case .milesPerHour: return "mph"
        }
    }
}

enum PaceUnitPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case perKilometer
    case perMile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .perKilometer: return "min/km"
        case .perMile: return "min/mi"
        }
    }
}

enum ElevationUnitPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case meters
    case feet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .meters: return "Meters"
        case .feet: return "Feet"
        }
    }
}

enum TemperatureUnitPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }
}

private struct UnitDisplaySettings: Codable {
    var distance: DistanceUnitPreference
    var speed: SpeedUnitPreference
    var pace: PaceUnitPreference
    var elevation: ElevationUnitPreference
    var temperature: TemperatureUnitPreference
}

@MainActor
final class UnitPreferencesStore: ObservableObject {
    private enum Persistence {
        static let storageKey = "unit_display_settings_v1"
    }

    @Published var distance: DistanceUnitPreference {
        didSet { persist() }
    }
    @Published var speed: SpeedUnitPreference {
        didSet { persist() }
    }
    @Published var pace: PaceUnitPreference {
        didSet { persist() }
    }
    @Published var elevation: ElevationUnitPreference {
        didSet { persist() }
    }
    @Published var temperature: TemperatureUnitPreference {
        didSet { persist() }
    }

    init() {
        let saved = Self.loadPersistedSettings() ?? Self.defaultSettings()
        self.distance = saved.distance
        self.speed = saved.speed
        self.pace = saved.pace
        self.elevation = saved.elevation
        self.temperature = saved.temperature
    }

    private static func loadPersistedSettings() -> UnitDisplaySettings? {
        let cloudStore = NSUbiquitousKeyValueStore.default

        if let cloudData = cloudStore.data(forKey: Persistence.storageKey),
           let decoded = try? JSONDecoder().decode(UnitDisplaySettings.self, from: cloudData) {
            return decoded
        }

        if let localData = UserDefaults.standard.data(forKey: Persistence.storageKey),
           let decoded = try? JSONDecoder().decode(UnitDisplaySettings.self, from: localData) {
            return decoded
        }

        return nil
    }

    private static func defaultSettings(locale: Locale = .current) -> UnitDisplaySettings {
        UnitDisplaySettings(
            distance: .automatic,
            speed: .automatic,
            pace: .automatic,
            elevation: .automatic,
            temperature: .automatic
        )
    }

    private func persist() {
        let settings = UnitDisplaySettings(
            distance: distance,
            speed: speed,
            pace: pace,
            elevation: elevation,
            temperature: temperature
        )
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: Persistence.storageKey)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(encoded, forKey: Persistence.storageKey)
    }

    func resetToAutomatic() {
        distance = .automatic
        speed = .automatic
        pace = .automatic
        elevation = .automatic
        temperature = .automatic
    }

    private var localeUsesImperialDistance: Bool {
        !Locale.current.usesMetricSystem
    }

    private var localeUsesFahrenheit: Bool {
        !Locale.current.usesMetricSystem
    }

    var resolvedDistanceUnit: DistanceUnitPreference {
        switch distance {
        case .automatic:
            return localeUsesImperialDistance ? .miles : .kilometers
        default:
            return distance
        }
    }

    var resolvedSpeedUnit: SpeedUnitPreference {
        switch speed {
        case .automatic:
            return resolvedDistanceUnit == .miles ? .milesPerHour : .kilometersPerHour
        default:
            return speed
        }
    }

    var resolvedPaceUnit: PaceUnitPreference {
        switch pace {
        case .automatic:
            return resolvedDistanceUnit == .miles ? .perMile : .perKilometer
        default:
            return pace
        }
    }

    var resolvedElevationUnit: ElevationUnitPreference {
        switch elevation {
        case .automatic:
            return resolvedDistanceUnit == .miles ? .feet : .meters
        default:
            return elevation
        }
    }

    var resolvedTemperatureUnit: TemperatureUnitPreference {
        switch temperature {
        case .automatic:
            return localeUsesFahrenheit ? .fahrenheit : .celsius
        default:
            return temperature
        }
    }

    func formattedDistance(fromMeters meters: Double, digits: Int = 2) -> (value: String, unit: String) {
        let value: Double
        let unit: String
        switch resolvedDistanceUnit {
        case .miles:
            value = meters / 1609.344
            unit = "mi"
        case .kilometers, .automatic:
            value = meters / 1000
            unit = "km"
        }
        return (String(format: "%.\(digits)f", value), unit)
    }

    func formattedSpeed(fromKilometersPerHour kilometersPerHour: Double, digits: Int = 1) -> (value: String, unit: String) {
        let value: Double
        let unit: String
        switch resolvedSpeedUnit {
        case .milesPerHour:
            value = kilometersPerHour / 1.609344
            unit = "mph"
        case .kilometersPerHour, .automatic:
            value = kilometersPerHour
            unit = "km/h"
        }
        return (String(format: "%.\(digits)f", value), unit)
    }

    func formattedPace(fromMinutesPerKilometer minutesPerKilometer: Double, digits: Int = 1) -> (value: String, unit: String) {
        let value: Double
        let unit: String
        switch resolvedPaceUnit {
        case .perMile:
            value = minutesPerKilometer * 1.609344
            unit = "min/mi"
        case .perKilometer, .automatic:
            value = minutesPerKilometer
            unit = "min/km"
        }
        return (String(format: "%.\(digits)f", value), unit)
    }

    func formattedElevation(fromMeters meters: Double, digits: Int = 0) -> (value: String, unit: String) {
        let value: Double
        let unit: String
        switch resolvedElevationUnit {
        case .feet:
            value = meters * 3.28084
            unit = "ft"
        case .meters, .automatic:
            value = meters
            unit = "m"
        }
        return (String(format: "%.\(digits)f", value), unit)
    }

    func formattedTemperature(fromCelsius celsius: Double, digits: Int = 0) -> (value: String, unit: String) {
        let value: Double
        let unit: String
        switch resolvedTemperatureUnit {
        case .fahrenheit:
            value = (celsius * 9 / 5) + 32
            unit = "°F"
        case .celsius, .automatic:
            value = celsius
            unit = "°C"
        }
        return (String(format: "%.\(digits)f", value), unit)
    }

    var automaticSummaryText: String {
        let distanceText = resolvedDistanceUnit == .miles ? "miles" : "kilometers"
        let speedText = resolvedSpeedUnit == .milesPerHour ? "mph" : "km/h"
        let paceText = resolvedPaceUnit == .perMile ? "min/mi" : "min/km"
        let elevationText = resolvedElevationUnit == .feet ? "feet" : "meters"
        let temperatureText = resolvedTemperatureUnit == .fahrenheit ? "Fahrenheit" : "Celsius"
        return "Automatic currently resolves to \(distanceText), \(speedText), \(paceText), \(elevationText), and \(temperatureText) based on this device."
    }
}

func workoutEffortScoreValue(from workout: HKWorkout) -> Double? {
    let preferredKeys = [
        "HKMetadataKeyWorkoutEffortScore"
    ]

    for key in preferredKeys {
        if let number = workout.metadata?[key] as? NSNumber {
            return number.doubleValue
        }
        if let value = workout.metadata?[key] as? Double {
            return value
        }
    }

    for (key, value) in workout.metadata ?? [:] where key.localizedCaseInsensitiveContains("effort") && key.localizedCaseInsensitiveContains("estimated") == false {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
    }

    return nil
}

func estimatedWorkoutEffortScoreValue(from workout: HKWorkout) -> Double? {
    let preferredKeys = [
        "HKMetadataKeyEstimatedWorkoutEffortScore",
        "HKMetadataKeyEstimatedEffortScore"
    ]

    for key in preferredKeys {
        if let number = workout.metadata?[key] as? NSNumber {
            return number.doubleValue
        }
        if let value = workout.metadata?[key] as? Double {
            return value
        }
    }

    for (key, value) in workout.metadata ?? [:] where key.localizedCaseInsensitiveContains("estimated") && key.localizedCaseInsensitiveContains("effort") {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
    }

    return nil
}

@main
struct NutrivanceApp: App {
    @StateObject private var navigationState = NavigationState()
    @StateObject private var searchState = SearchState()
    @StateObject private var unitPreferences = UnitPreferencesStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init() {
        StrainRecoveryAggressiveCachingController.shared.registerBackgroundTasks()
        WatchDashboardSyncBridge.shared.activateIfNeeded()
        CompanionWorkoutLiveManager.shared.activateIfNeeded()
    }

    private func navigate(
        focus: AppFocus,
        view: String,
        tab: RootTabSelection
    ) {
        navigationState.navigate(focus: focus, view: view, tab: tab)
    }

    private func postViewControl(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
    
    private func hasContextualControls(for tab: RootTabSelection) -> Bool {
        switch tab {
        case .strainRecovery, .stress, .sleep:
            return true
        default:
            return false
        }
    }
    
    private func filterButtonTitles(for tab: RootTabSelection) -> [String] {
        switch tab {
        case .strainRecovery:
            return ["1W", "1M", "1Y"]
        case .stress:
            return ["24H", "1W", "1M"]
        case .sleep:
            return ["Night", "Week", "Month", "Year"]
        default:
            return []
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
                .environmentObject(searchState)
                .environmentObject(unitPreferences)
                .onChange(of: scenePhase) { _, newPhase in
                    HealthStateEngine.shared.handleScenePhaseChange(newPhase)
                    StrainRecoveryAggressiveCachingController.shared.handleScenePhaseChange(newPhase)
                    WatchDashboardSyncBridge.shared.handleScenePhaseChange(newPhase)
                }
        }
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    toggleSystemSidebar()
                }
                .keyboardShortcut("S", modifiers: [.command, .control])
            }
            CommandMenu("Navigation") {
                Button("Back") {
                    performBackNavigation(
                        presentedDestination: $navigationState.presentedDestination,
                        dismissAction: navigationState.dismissAction
                    )
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Insights") {
                    navigate(focus: .nutrition, view: "Insights", tab: .insights)
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])

                Button("Labels") {
                    navigate(focus: .nutrition, view: "Labels", tab: .labels)
                }
                .keyboardShortcut("B", modifiers: [.command, .shift])

                Button("Log") {
                    navigate(focus: .nutrition, view: "Log", tab: .log)
                }
                .keyboardShortcut("G", modifiers: [.command, .shift])

                Button("Calories") {
                    navigate(focus: .nutrition, view: "Calories", tab: .calories)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Carbs") {
                    navigate(focus: .nutrition, view: "Carbs", tab: .carbs)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Protein") {
                    navigate(focus: .nutrition, view: "Protein", tab: .protein)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("Fats") {
                    navigate(focus: .nutrition, view: "Fats", tab: .fats)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button("Water") {
                    navigate(focus: .nutrition, view: "Water", tab: .water)
                }
                .keyboardShortcut("5", modifiers: [.command, .option])

                Button("Fiber") {
                    navigate(focus: .nutrition, view: "Fiber", tab: .fiber)
                }
                .keyboardShortcut("6", modifiers: [.command, .option])

                Button("Vitamins") {
                    navigate(focus: .nutrition, view: "Vitamins", tab: .vitamins)
                }
                .keyboardShortcut("7", modifiers: [.command, .option])

                Button("Minerals") {
                    navigate(focus: .nutrition, view: "Minerals", tab: .minerals)
                }
                .keyboardShortcut("8", modifiers: [.command, .option])

                Button("Phytochemicals") {
                    navigate(focus: .nutrition, view: "Phytochemicals", tab: .phytochemicals)
                }
                .keyboardShortcut("9", modifiers: [.command, .option])

                Button("Antioxidants") {
                    navigate(focus: .nutrition, view: "Antioxidants", tab: .antioxidants)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Button("Electrolytes") {
                    navigate(focus: .nutrition, view: "Electrolytes", tab: .electrolytes)
                }
                .keyboardShortcut("-", modifiers: [.command, .option])

                Button("Dashboard") {
                    navigate(focus: .fitness, view: "Dashboard", tab: .dashboard)
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])

                Button("Today's Plan") {
                    navigate(focus: .fitness, view: "Today's Plan", tab: .todaysPlan)
                }
                .keyboardShortcut("T", modifiers: [.command, .shift])

                Button("Training Calendar") {
                    navigate(focus: .fitness, view: "Training Calendar", tab: .trainingCalendar)
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])

                Button("Coach") {
                    navigate(focus: .fitness, view: "Coach", tab: .coach)
                }
                .keyboardShortcut("C", modifiers: [.command, .shift])

                Button("Recovery Score") {
                    navigate(focus: .fitness, view: "Recovery Score", tab: .recoveryScore)
                }
                .keyboardShortcut("Y", modifiers: [.command, .shift])

                Button("Readiness") {
                    navigate(focus: .fitness, view: "Readiness", tab: .readiness)
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])

                Button("Strain vs Recovery") {
                    navigate(focus: .fitness, view: "Strain vs Recovery", tab: .strainRecovery)
                }
                .keyboardShortcut("V", modifiers: [.command, .shift])

                Button("Workout History") {
                    navigate(focus: .fitness, view: "Workout History", tab: .workoutHistory)
                }
                .keyboardShortcut("W", modifiers: [.command, .option])

                Button("Activity Rings") {
                    navigate(focus: .fitness, view: "Activity Rings", tab: .activityRings)
                }
                .keyboardShortcut("A", modifiers: [.command, .shift])

                Button("Heart Zones") {
                    navigate(focus: .fitness, view: "Heart Zones", tab: .heartZones)
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])

                Button("Personal Records") {
                    navigate(focus: .fitness, view: "Personal Records", tab: .personalRecords)
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])

                Button("Mindfulness Realm") {
                    navigate(focus: .mentalHealth, view: "Mindfulness Realm", tab: .mindfulnessRealm)
                }
                .keyboardShortcut("M", modifiers: [.command, .shift])

                Button("Mood Tracker") {
                    navigate(focus: .mentalHealth, view: "Mood Tracker", tab: .moodTracker)
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])

                Button("Journal") {
                    navigate(focus: .mentalHealth, view: "Journal", tab: .journal)
                }
                .keyboardShortcut("J", modifiers: [.command, .shift])

                Button("Sleep") {
                    navigate(focus: .mentalHealth, view: "Sleep", tab: .sleep)
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])

                Button("Stress") {
                    navigate(focus: .mentalHealth, view: "Stress", tab: .stress)
                }
                .keyboardShortcut("X", modifiers: [.command, .shift])
            }
            CommandMenu("Search") {
                Button("Find") {
                    navigationState.presentedDestination = nil
                    navigationState.selectedRootTab = .search
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        searchState.isSearching = true
                    }
                }
                .keyboardShortcut("F", modifiers: [.command])
            }
            CommandMenu("View Controls") {
                if hasContextualControls(for: navigationState.selectedRootTab) {
                    Button("Today") {
                        postViewControl(.nutrivanceViewControlToday)
                    }
                    .keyboardShortcut("T", modifiers: [.command])
                    
                    Button("Previous") {
                        postViewControl(.nutrivanceViewControlPrevious)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    
                    Button("Next") {
                        postViewControl(.nutrivanceViewControlNext)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    
                    ForEach(Array(filterButtonTitles(for: navigationState.selectedRootTab).enumerated()), id: \.offset) { index, title in
                        Button(title) {
                            switch index {
                            case 0:
                                postViewControl(.nutrivanceViewControlFilter1)
                            case 1:
                                postViewControl(.nutrivanceViewControlFilter2)
                            case 2:
                                postViewControl(.nutrivanceViewControlFilter3)
                            case 3:
                                postViewControl(.nutrivanceViewControlFilter4)
                            default:
                                break
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                    }

                    if navigationState.selectedRootTab == .strainRecovery {
                        Divider()

                        Button("Refresh Coach Summary") {
                            postViewControl(.nutrivanceViewControlRefresh)
                        }
                        .keyboardShortcut("R", modifiers: [.command])

                        Button("Save Coach Summary to Journal") {
                            postViewControl(.nutrivanceViewControlSaveToJournal)
                        }
                        .keyboardShortcut("S", modifiers: [.command])
                    }
                } else {
                    Button("No View Controls Available") {}
                        .disabled(true)
                }
            }
        }
    }
}
