import Foundation
import HealthKit
import SwiftUI
import Combine

struct SharedWorkoutSummarySnapshot {
    let date: Date
    let sessionLoad: Double
    let totalDailyLoad: Double
    let acuteLoad: Double
    let chronicLoad: Double
    let acwr: Double
    let strainScore: Double
    let workoutCount: Int
    let activeDaysLast28: Int
    let daysSinceLastWorkout: Int?
}

// MARK: - Recovery Computation Context

/// Precomputed lookups + baselines for one snapshot pass.
///
/// The pipeline's per-day helpers (`sharedRecoveryScore`, `sharedReadinessTrendComponent`,
/// `sharedReadinessScore`, and the pro-athlete variants) previously rebuilt
/// `Dictionary(uniqueKeysWithValues: engine.dailyHRV.map ...)` on every call. For a
/// `RecoveryScoreView` refresh that meant ~49 dictionary rebuilds per pass, all on the
/// main actor. `RecoveryComputationContext` captures every map/baseline the helpers need
/// **once** and is passed by value into the per-day overloads, so the math becomes pure
/// O(1) lookup work that can run on any actor.
struct RecoveryComputationContext {
    let hrvByDay: [Date: Double]
    let effectHRV: [Date: Double]
    let basalSleepingHeartRate: [Date: Double]
    let dailyRestingHeartRate: [Date: Double]
    let anchoredSleepDuration: [Date: Double]
    let anchoredTimeInBed: [Date: Double]
    /// Per-day sleep efficiency from sleep analysis (asleep / in-bed), when available.
    let sleepEfficiencyByDay: [Date: Double]
    let dailySleepDuration: [Date: Double]
    let sleepStartHours: [Date: Double]
    let hrvBaseline60Day: HealthStateEngine.RollingBaselineStats?
    let rhrBaseline60Day: HealthStateEngine.RollingBaselineStats?
    let sleepBaseline60Day: HealthStateEngine.RollingBaselineStats?
    let hrvBaseline7Day: Double?
    let rhrBaseline7Day: Double?
    let sleepBaseline7Day: Double?
    /// Fallback HRV trend score when the per-day deviation cannot be computed.
    let hrvTrendFallback: Double
    let respiratoryRateByDay: [Date: Double]
    let spO2ByDay: [Date: Double]
    let wristTemperatureByDay: [Date: Double]

    @MainActor
    static func make(engine: HealthStateEngine) -> RecoveryComputationContext {
        RecoveryComputationContext(
            hrvByDay: engine.cachedHRVByDay,
            effectHRV: engine.effectHRV,
            basalSleepingHeartRate: engine.basalSleepingHeartRate,
            dailyRestingHeartRate: engine.dailyRestingHeartRate,
            anchoredSleepDuration: engine.anchoredSleepDuration,
            anchoredTimeInBed: engine.anchoredTimeInBed,
            sleepEfficiencyByDay: engine.sleepEfficiency,
            dailySleepDuration: engine.dailySleepDuration,
            sleepStartHours: engine.sleepStartHours,
            hrvBaseline60Day: engine.hrvBaseline60Day,
            rhrBaseline60Day: engine.rhrBaseline60Day,
            sleepBaseline60Day: engine.sleepBaseline60Day,
            hrvBaseline7Day: engine.hrvBaseline7Day,
            rhrBaseline7Day: engine.rhrBaseline7Day,
            sleepBaseline7Day: engine.sleepBaseline7Day,
            hrvTrendFallback: engine.hrvTrendScore,
            respiratoryRateByDay: engine.respiratoryRate,
            spO2ByDay: engine.spO2,
            wristTemperatureByDay: engine.wristTemperature
        )
    }
}

/// Same-calendar-day sleep for recovery math. Multi-day smoothing previously blended a 1.4h night with
/// prior full nights, inflating recovery into the 80s.
private func recoverySleepHoursForProInputs(on normalizedDay: Date, context: RecoveryComputationContext) -> Double? {
    if let v = context.anchoredSleepDuration[normalizedDay], v > 0 { return v }
    if let v = context.dailySleepDuration[normalizedDay], v > 0 { return v }
    return HealthStateEngine.smoothedValue(for: normalizedDay, values: context.anchoredSleepDuration)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: context.dailySleepDuration)
}

private func recoveryTimeInBedHoursForProInputs(on normalizedDay: Date, context: RecoveryComputationContext, sleepHours: Double?) -> Double? {
    if let t = context.anchoredTimeInBed[normalizedDay], t > 0 { return t }
    return sleepHours
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: context.anchoredTimeInBed)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: context.anchoredSleepDuration)
        ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: context.dailySleepDuration)
}

func sharedDateSequence(from start: Date, to end: Date) -> [Date] {
    let calendar = Calendar.current
    let normalizedStart = calendar.startOfDay(for: start)
    let normalizedEnd = calendar.startOfDay(for: end)
    guard normalizedStart <= normalizedEnd else { return [] }

    var dates: [Date] = []
    var cursor = normalizedStart
    while cursor <= normalizedEnd {
        dates.append(cursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return dates
}

// MARK: - Context-aware overloads (no per-call dictionary churn)

func sharedRecoveryScoreDetailed(
    for day: Date,
    context: RecoveryComputationContext
) -> RecoveryScoreBreakdown? {
    let inputs = sharedRecoveryInputs(for: day, context: context)
    return RecoveryPhysiologyModel.computeRecoveryBreakdown(day: day, inputs: inputs, context: context)
}

func sharedRecoveryScore(
    for day: Date,
    context: RecoveryComputationContext
) -> Double? {
    sharedRecoveryScoreDetailed(for: day, context: context)?.score
}

func sharedReadinessTrendComponent(
    for day: Date,
    context: RecoveryComputationContext
) -> Double {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvValue = context.hrvByDay[normalizedDay]
    if let hrvValue, let baseline = context.hrvBaseline7Day, baseline > 0 {
        let deviation = (hrvValue - baseline) / baseline
        return max(0, min(100, (deviation * 200) + 50))
    }
    return context.hrvTrendFallback
}

func sharedReadinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    context: RecoveryComputationContext,
    acwr: Double? = nil
) -> Double? {
    let trend = sharedReadinessTrendComponent(for: day, context: context)
    guard let breakdown = sharedRecoveryScoreDetailed(for: day, context: context) else {
        return HealthStateEngine.proReadinessScore(
            recoveryScore: recoveryScore,
            strainScore: strainScore,
            hrvTrendComponent: trend
        )
    }
    let readinessBreakdown = sharedReadinessScoreDetailed(
        for: day,
        recoveryBreakdown: breakdown,
        recoveryScoreForBlend: recoveryScore,
        strainScore: strainScore,
        acwr: acwr,
        context: context
    )
    return readinessBreakdown.score
}

func sharedReadinessScoreDetailed(
    for day: Date,
    recoveryBreakdown: RecoveryScoreBreakdown,
    recoveryScoreForBlend: Double,
    strainScore: Double,
    acwr: Double?,
    context: RecoveryComputationContext
) -> ReadinessScoreBreakdown {
    let input = ReadinessComputationInput(
        recovery: recoveryBreakdown,
        recoveryScoreForBlend: recoveryScoreForBlend,
        strainScore: strainScore,
        hrvTrendComponent: sharedReadinessTrendComponent(for: day, context: context),
        acwr: acwr
    )
    return RecoveryPhysiologyModel.computeReadinessBreakdown(input: input)
}

func sharedRecoveryInputs(
    for day: Date,
    context: RecoveryComputationContext
) -> HealthStateEngine.ProRecoveryInputs {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let sleepHours = recoverySleepHoursForProInputs(on: normalizedDay, context: context)
    let timeInBed = recoveryTimeInBedHoursForProInputs(on: normalizedDay, context: context, sleepHours: sleepHours)
    return HealthStateEngine.proRecoveryInputs(
        latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: context.effectHRV) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: context.hrvByDay),
        restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: context.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: context.dailyRestingHeartRate),
        sleepDurationHours: sleepHours,
        timeInBedHours: timeInBed,
        hrvBaseline60Day: context.hrvBaseline60Day,
        rhrBaseline60Day: context.rhrBaseline60Day,
        sleepBaseline60Day: context.sleepBaseline60Day,
        hrvBaseline7Day: context.hrvBaseline7Day,
        rhrBaseline7Day: context.rhrBaseline7Day,
        sleepBaseline7Day: context.sleepBaseline7Day,
        bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: context.sleepStartHours, around: normalizedDay)
    )
}

// MARK: - Engine-based wrappers (legacy callers)

@MainActor
func sharedRecoveryScore(
    for day: Date,
    engine: HealthStateEngine
) -> Double? {
    sharedRecoveryScore(for: day, context: RecoveryComputationContext.make(engine: engine))
}

@MainActor
func sharedReadinessTrendComponent(
    for day: Date,
    engine: HealthStateEngine
) -> Double {
    sharedReadinessTrendComponent(for: day, context: RecoveryComputationContext.make(engine: engine))
}

@MainActor
func sharedReadinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    engine: HealthStateEngine,
    acwr: Double? = nil
) -> Double? {
    sharedReadinessScore(
        for: day,
        recoveryScore: recoveryScore,
        strainScore: strainScore,
        context: RecoveryComputationContext.make(engine: engine),
        acwr: acwr
    )
}

func sharedDailyLoadSnapshots(
    workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
    estimatedMaxHeartRate: Double,
    displayWindow: (start: Date, end: Date, endExclusive: Date)
) -> [SharedWorkoutSummarySnapshot] {
    let calendar = Calendar.current
    var sessionLoadByDay: [Date: Double] = [:]
    var workoutCountByDay: [Date: Int] = [:]
    var activeMinutesByDay: [Date: Double] = [:]
    let loadWindowStart = calendar.date(byAdding: .day, value: -27, to: displayWindow.start) ?? displayWindow.start

    // Single O(W) pass: bucket session load, count, and active minutes per day.
    for (workout, analytics) in workouts {
        let day = calendar.startOfDay(for: workout.startDate)
        let load = HealthStateEngine.proWorkoutLoad(
            for: workout,
            analytics: analytics,
            estimatedMaxHeartRate: estimatedMaxHeartRate
        )
        sessionLoadByDay[day, default: 0] += load
        workoutCountByDay[day, default: 0] += 1
        activeMinutesByDay[day, default: 0] += workout.duration / 60.0
    }

    let loadDates = sharedDateSequence(from: loadWindowStart, to: displayWindow.end)
    // Build a Date->Int index once instead of `loadDates.firstIndex(of:)` per output day.
    let loadDateIndex: [Date: Int] = Dictionary(uniqueKeysWithValues: loadDates.enumerated().map { ($1, $0) })
    let orderedLoads: [Double] = loadDates.map { day in
        let sessionLoad = sessionLoadByDay[day, default: 0]
        let activeMinutes = activeMinutesByDay[day, default: 0]
        return sessionLoad + HealthStateEngine.passiveDailyBaseLoad(activeMinutes: activeMinutes)
    }

    return sharedDateSequence(from: displayWindow.start, to: displayWindow.end).map { day in
        let activeDaysLast28 = (0..<28).reduce(0) { partial, offset in
            let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
            return partial + ((sessionLoadByDay[sourceDay] ?? 0) > 0 ? 1 : 0)
        }
        let daysSinceLastWorkout = (0..<28).first(where: { offset in
            let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
            return (sessionLoadByDay[sourceDay] ?? 0) > 0
        })
        let stateIndex = loadDateIndex[day] ?? (orderedLoads.indices.last ?? 0)
        let state = HealthStateEngine.proTrainingLoadState(loads: orderedLoads, index: stateIndex)

        return SharedWorkoutSummarySnapshot(
            date: day,
            sessionLoad: sessionLoadByDay[day] ?? 0,
            totalDailyLoad: orderedLoads[stateIndex],
            acuteLoad: state.acuteLoad,
            chronicLoad: state.chronicLoad,
            acwr: state.acwr,
            strainScore: HealthStateEngine.proStrainScore(
                acuteLoad: state.acuteLoad,
                chronicLoad: state.chronicLoad
            ),
            workoutCount: workoutCountByDay[day] ?? 0,
            activeDaysLast28: activeDaysLast28,
            daysSinceLastWorkout: daysSinceLastWorkout
        )
    }
}

// MARK: - Pro-Athlete Aware Score Calculation

func sharedProAthleteRecoveryScore(
    for day: Date,
    context: RecoveryComputationContext,
    profile: ProAthleteProfileValues,
    subjectiveBoost: Double?,
    chronicLoad: Double,
    athleteHistoricalMaxChronicLoad: Double?
) -> (score: Double, hrvWarning: Bool, sleepQualityWarning: Bool, subjectiveBoost: Double?)? {
    guard sharedRecoveryScoreDetailed(for: day, context: context) != nil else { return nil }
    let inputs = sharedRecoveryInputs(for: day, context: context)
    guard !inputs.isInconclusive else { return nil }

    return HealthStateEngine.proAthleteRecoveryScore(
        from: inputs,
        profile: profile,
        chronicLoad: chronicLoad,
        athleteHistoricalMaxChronicLoad: athleteHistoricalMaxChronicLoad,
        subjectiveBoost: subjectiveBoost
    )
}

@MainActor
func sharedProAthleteRecoveryScore(
    for day: Date,
    engine: HealthStateEngine,
    profile: PerformanceProfileSettings,
    chronicLoad: Double,
    athleteHistoricalMaxChronicLoad: Double?
) -> (score: Double, hrvWarning: Bool, sleepQualityWarning: Bool, subjectiveBoost: Double?)? {
    sharedProAthleteRecoveryScore(
        for: day,
        context: RecoveryComputationContext.make(engine: engine),
        profile: ProAthleteProfileValues(from: profile),
        subjectiveBoost: SubjectiveDailyEntryManager.shared.subjectiveRecoveryBoost(),
        chronicLoad: chronicLoad,
        athleteHistoricalMaxChronicLoad: athleteHistoricalMaxChronicLoad
    )
}

func sharedProAthleteReadinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    acwr: Double?,
    acuteLoad: Double?,
    chronicLoad: Double?,
    context: RecoveryComputationContext,
    profile: ProAthleteProfileValues
) -> (score: Double, acwrStatus: String, taperDetected: Bool, asymmetricStrainMultiplier: Double)? {
    return HealthStateEngine.proAthleteReadinessScore(
        recovery: recoveryScore,
        strain: strainScore,
        hrvTrend: sharedReadinessTrendComponent(for: day, context: context),
        acwr: acwr,
        acuteLoad: acuteLoad,
        chronicLoad: chronicLoad,
        profile: profile
    )
}

@MainActor
func sharedProAthleteReadinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    acwr: Double?,
    acuteLoad: Double?,
    chronicLoad: Double?,
    engine: HealthStateEngine,
    profile: PerformanceProfileSettings
) -> (score: Double, acwrStatus: String, taperDetected: Bool, asymmetricStrainMultiplier: Double)? {
    guard profile.isProAthleteMode else { return nil }
    return sharedProAthleteReadinessScore(
        for: day,
        recoveryScore: recoveryScore,
        strainScore: strainScore,
        acwr: acwr,
        acuteLoad: acuteLoad,
        chronicLoad: chronicLoad,
        context: RecoveryComputationContext.make(engine: engine),
        profile: ProAthleteProfileValues(from: profile)
    )
}

// MARK: - Personalized MET Calculations

@MainActor
func sharedPersonalizedMETForWorkout(
    workout: HKWorkout,
    analytics: WorkoutAnalytics,
    profile: PersonalizedMETProfile,
    engine: HealthStateEngine
) -> WorkoutPersonalizedMET? {
    guard profile.isValid else { return nil }
    
    let normalizedDay = Calendar.current.startOfDay(for: workout.startDate)
    let rhr = HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate) ?? 
        HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate) ?? 60
    
    return HealthStateEngine.calculatePersonalizedMETForWorkout(
        workout: workout,
        analytics: analytics,
        profile: profile,
        estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
        rhrAtWorkout: rhr
    )
}

@MainActor
func sharedDailyPersonalizedMETSnapshot(
    for day: Date,
    workouts: [WorkoutPersonalizedMET],
    profile: PersonalizedMETProfile,
    engine: HealthStateEngine,
    useDailyAdaptiveThreshold: Bool,
    recoveryScore: Double?
) -> DailyPersonalizedMETSnapshot {
    return HealthStateEngine.calculateDailyPersonalizedMETSnapshot(
        date: day,
        workouts: workouts,
        profile: profile,
        recoveryScore: recoveryScore,
        useDailyAdaptiveThreshold: useDailyAdaptiveThreshold
    )
}

@MainActor
func sharedDeriveMaxMETsFromHistory(
    engine: HealthStateEngine
) -> Double? {
    return HealthStateEngine.deriveMaxMETsFromHistory(
        workouts: engine.workoutAnalytics,
        estimatedMaxHeartRate: engine.estimatedMaxHeartRate,
        rhrBaseline: engine.rhrBaseline7Day ?? 60
    )
}

// MARK: - Metric view display cache (disk)

/// Shared Application Support folder for instant reload of heavy metric screens.
enum NutrivanceViewMetricDisplayCacheURL {
    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("NutrivanceMetricDisplayCache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(named fileName: String) throws -> URL {
        try directory().appendingPathComponent(fileName, isDirectory: false)
    }
}
