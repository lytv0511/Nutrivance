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

@MainActor
func sharedRecoveryScore(
    for day: Date,
    engine: HealthStateEngine
) -> Double? {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
    let inputs = HealthStateEngine.proRecoveryInputs(
        latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.effectHRV) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: hrvLookup),
        restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate),
        sleepDurationHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
        timeInBedHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
        hrvBaseline60Day: engine.hrvBaseline60Day,
        rhrBaseline60Day: engine.rhrBaseline60Day,
        sleepBaseline60Day: engine.sleepBaseline60Day,
        hrvBaseline7Day: engine.hrvBaseline7Day,
        rhrBaseline7Day: engine.rhrBaseline7Day,
        sleepBaseline7Day: engine.sleepBaseline7Day,
        bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: normalizedDay)
    )

    guard !inputs.isInconclusive else { return nil }
    guard inputs.hrvZScore != nil || inputs.restingHeartRateZScore != nil || inputs.sleepRatio != nil else {
        return nil
    }
    return HealthStateEngine.proRecoveryScore(from: inputs)
}

@MainActor
func sharedReadinessTrendComponent(
    for day: Date,
    engine: HealthStateEngine
) -> Double {
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
    let hrvValue = hrvLookup[normalizedDay]
    if let hrvValue, let baseline = engine.hrvBaseline7Day, baseline > 0 {
        let deviation = (hrvValue - baseline) / baseline
        return max(0, min(100, (deviation * 200) + 50))
    }
    return engine.hrvTrendScore
}

@MainActor
func sharedReadinessScore(
    for day: Date,
    recoveryScore: Double,
    strainScore: Double,
    engine: HealthStateEngine
) -> Double? {
    HealthStateEngine.proReadinessScore(
        recoveryScore: recoveryScore,
        strainScore: strainScore,
        hrvTrendComponent: sharedReadinessTrendComponent(for: day, engine: engine)
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
    let loadWindowStart = calendar.date(byAdding: .day, value: -27, to: displayWindow.start) ?? displayWindow.start

    for (workout, analytics) in workouts {
        let day = calendar.startOfDay(for: workout.startDate)
        let load = HealthStateEngine.proWorkoutLoad(
            for: workout,
            analytics: analytics,
            estimatedMaxHeartRate: estimatedMaxHeartRate
        )
        sessionLoadByDay[day, default: 0] += load
        workoutCountByDay[day, default: 0] += 1
    }

    let loadDates = sharedDateSequence(from: loadWindowStart, to: displayWindow.end)
    let orderedLoads = loadDates.map { day in
        let sessionLoad = sessionLoadByDay[day, default: 0]
        let activeMinutes = workouts
            .filter { calendar.isDate($0.workout.startDate, inSameDayAs: day) }
            .reduce(0.0) { $0 + ($1.workout.duration / 60.0) }
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
        let stateIndex = loadDates.firstIndex(of: day) ?? (orderedLoads.indices.last ?? 0)
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

@MainActor
func sharedProAthleteRecoveryScore(
    for day: Date,
    engine: HealthStateEngine,
    profile: PerformanceProfileSettings,
    chronicLoad: Double,
    athleteHistoricalMaxChronicLoad: Double?
) -> (score: Double, hrvWarning: Bool, sleepQualityWarning: Bool, subjectiveBoost: Double?)? {
    guard let baseScore = sharedRecoveryScore(for: day, engine: engine) else { return nil }
    
    let normalizedDay = Calendar.current.startOfDay(for: day)
    let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
    let inputs = HealthStateEngine.proRecoveryInputs(
        latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.effectHRV) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: hrvLookup),
        restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate),
        sleepDurationHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
        timeInBedHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
        hrvBaseline60Day: engine.hrvBaseline60Day,
        rhrBaseline60Day: engine.rhrBaseline60Day,
        sleepBaseline60Day: engine.sleepBaseline60Day,
        hrvBaseline7Day: engine.hrvBaseline7Day,
        rhrBaseline7Day: engine.rhrBaseline7Day,
        sleepBaseline7Day: engine.sleepBaseline7Day,
        bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: normalizedDay)
    )
    
    guard !inputs.isInconclusive else { return nil }
    
    let subjectiveBoost = SubjectiveDailyEntryManager.shared.subjectiveRecoveryBoost()
    
    return HealthStateEngine.proAthleteRecoveryScore(
        from: inputs,
        profile: ProAthleteProfileValues(from: profile),
        chronicLoad: chronicLoad,
        athleteHistoricalMaxChronicLoad: athleteHistoricalMaxChronicLoad,
        subjectiveBoost: subjectiveBoost
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
    
    return HealthStateEngine.proAthleteReadinessScore(
        recovery: recoveryScore,
        strain: strainScore,
        hrvTrend: sharedReadinessTrendComponent(for: day, engine: engine),
        acwr: acwr,
        acuteLoad: acuteLoad,
        chronicLoad: chronicLoad,
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
