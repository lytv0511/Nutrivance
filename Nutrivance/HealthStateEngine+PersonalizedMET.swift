import Foundation
import HealthKit

extension HealthStateEngine {
    
    // MARK: - Max METs Derivation from History
    
    /// Derives max METs from 90-day workout history.
    /// Scans workouts for highest heart rate effort and extrapolates max METs.
    nonisolated static func deriveMaxMETsFromHistory(
        workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)],
        estimatedMaxHeartRate: Double,
        rhrBaseline: Double
    ) -> Double? {
        guard !workouts.isEmpty else { return nil }
        
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recentWorkouts = workouts.filter { $0.workout.startDate >= ninetyDaysAgo }
        
        guard !recentWorkouts.isEmpty else { return nil }
        
        // Find peak HR achieved during any workout
        let peakHRObserved = recentWorkouts.compactMap { $0.analytics.heartRateData?.max { $0.hr < $1.hr }?.hr }.max() ?? estimatedMaxHeartRate * 0.85
        
        // Calculate MET at peak effort
        let hrReserve = estimatedMaxHeartRate - rhrBaseline
        guard hrReserve > 0 else { return nil }
        
        let effortRatio = (peakHRObserved - rhrBaseline) / hrReserve
        let peakMETObserved = 1.0 + (effortRatio * 20)  // Assume max capacity around 20 METs as baseline
        
        // Apply 1.1x multiplier to extrapolate beyond observed peak
        let derivedMaxMETs = peakMETObserved * 1.1
        
        return min(25, max(8, derivedMaxMETs))  // Clamp to reasonable athlete range
    }
    
    // MARK: - Per-Workout MET Calculation
    
    /// Calculates personalized METs for a single workout based on HR effort.
    ///
    /// Formula:
    ///   HR Reserve = Max HR - RHR
    ///   Effort Ratio = (Avg HR - RHR) / HR Reserve
    ///   Current MET = 1 + (Effort Ratio × Max METs)
    ///   Total METs = Current MET × Duration(hours)
    nonisolated static func calculatePersonalizedMETForWorkout(
        workout: HKWorkout,
        analytics: WorkoutAnalytics,
        profile: PersonalizedMETProfile,
        estimatedMaxHeartRate: Double,
        rhrAtWorkout: Double
    ) -> WorkoutPersonalizedMET? {
        guard let heartRateData = analytics.heartRateData, !heartRateData.isEmpty else {
            return nil
        }
        
        let profile = profile
        guard profile.maxMETs > 0 else { return nil }
        
        // Calculate HR Reserve
        let hrReserve = estimatedMaxHeartRate - rhrAtWorkout
        guard hrReserve > 0 else { return nil }
        
        // Get workout metrics
        let avgHeartRate = heartRateData.map { $0.hr }.average ?? 0
        let peakHeartRate = (heartRateData.max { $0.hr < $1.hr }?.hr) ?? avgHeartRate
        let durationHours = workout.duration / 3600.0
        
        // Calculate effort ratio and current MET
        let effortRatio = max(0, (avgHeartRate - rhrAtWorkout) / hrReserve)
        let currentMET = 1.0 + (effortRatio * profile.maxMETs)
        let effortProportion = currentMET / profile.maxMETs
        
        // Calculate total and beneficial METs
        let totalMETs = currentMET * durationHours
        let thresholdMET = profile.maxMETs * profile.beneficialMETThresholdPercentage
        let beneficialMETs = max(0, (currentMET - thresholdMET) * durationHours)
        
        // Classify zone
        let zone = PersonalizedMETZone.fromEffortProportion(effortProportion)
        
        return WorkoutPersonalizedMET(
            workoutID: UUID(),
            workoutDate: workout.startDate,
            workoutType: workout.workoutActivityType.name,
            duration: workout.duration,
            averageHeartRate: avgHeartRate,
            peakHeartRate: peakHeartRate,
            totalMETs: totalMETs,
            beneficialMETs: beneficialMETs,
            effortProportion: effortProportion,
            zone: zone,
            restingHeartRate: rhrAtWorkout,
            timestamp: Date()
        )
    }
    
    // MARK: - Daily Aggregation
    
    /// Aggregates METs across all workouts for a given day and calculates daily snapshot.
    nonisolated static func calculateDailyPersonalizedMETSnapshot(
        date: Date,
        workouts: [WorkoutPersonalizedMET],
        profile: PersonalizedMETProfile,
        recoveryScore: Double?,
        useDailyAdaptiveThreshold: Bool
    ) -> DailyPersonalizedMETSnapshot {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        
        // Sum workout METs
        let totalMETs = workouts.reduce(0) { $0 + $1.totalMETs }
        let beneficialMETs = workouts.reduce(0) { $0 + $1.beneficialMETs }
        
        // Add passive daily activity (light walking, ADLs)
        let passiveMETs = METCalculationConstants.passiveMETsPerHour * METCalculationConstants.passiveWakingHours
        let totalWithPassive = totalMETs + passiveMETs
        
        // Calculate adaptive threshold
        let (thresholdMETs, _) = calculateAdaptiveThreshold(
            baseThreshold: profile.maxMETs * profile.beneficialMETThresholdPercentage,
            recoveryScore: recoveryScore,
            useDailyAdaptive: useDailyAdaptiveThreshold
        )
        
        // Zone distribution (in minutes)
        var zoneDistribution: [PersonalizedMETZone: Double] = [:]
        for zone in PersonalizedMETZone.allCases {
            let workoutsInZone = workouts.filter { $0.zone == zone }
            let minutesInZone = workoutsInZone.reduce(0) { $0 + $1.durationMinutes }
            if minutesInZone > 0 {
                zoneDistribution[zone] = minutesInZone
            }
        }
        
        // Calculate averages
        let totalActiveMinutes = workouts.reduce(0) { $0 + $1.durationMinutes }
        let avgEffortProportion = totalActiveMinutes > 0
            ? workouts.reduce(0) { $0 + ($1.effortProportion * $1.durationMinutes) } / totalActiveMinutes
            : 0
        let peakEffortProportion = workouts.map { $0.effortProportion }.max() ?? 0
        
        return DailyPersonalizedMETSnapshot(
            id: UUID(),
            date: normalizedDate,
            totalMETs: totalWithPassive,
            beneficialMETs: beneficialMETs,
            thresholdMETs: thresholdMETs,
            averageEffortProportion: avgEffortProportion,
            peakEffortProportion: peakEffortProportion,
            workoutCount: workouts.count,
            zoneDistribution: zoneDistribution,
            recoveryScore: recoveryScore,
            totalDurationMinutes: totalActiveMinutes,
            timestamp: Date()
        )
    }
    
    // MARK: - Adaptive Threshold Calculation
    
    /// Calculates daily adaptive beneficial MET threshold based on recovery score.
    /// If recovery is low, threshold is lowered to make more METs count as "beneficial".
    /// If recovery is high, threshold is raised to require more effort for benefit credit.
    nonisolated static func calculateAdaptiveThreshold(
        baseThreshold: Double,
        recoveryScore: Double?,
        useDailyAdaptive: Bool
    ) -> (thresholdMET: Double, adjustmentFactor: Double) {
        guard useDailyAdaptive, let recovery = recoveryScore else {
            return (baseThreshold, 1.0)
        }
        
        // Normalize recovery to 0-1 scale
        let normalizedRecovery = recovery / 100.0
        
        if normalizedRecovery < 0.50 {
            // Low recovery: lower threshold to 40% of max
            let adjustedThreshold = baseThreshold * (METCalculationConstants.lowRecoveryThresholdAdjustment / METCalculationConstants.normalRecoveryThreshold)
            return (adjustedThreshold, METCalculationConstants.lowRecoveryThresholdAdjustment / METCalculationConstants.normalRecoveryThreshold)
        } else if normalizedRecovery > 0.75 {
            // High recovery: raise threshold to 60% of max
            let adjustedThreshold = baseThreshold * (METCalculationConstants.highRecoveryThresholdAdjustment / METCalculationConstants.normalRecoveryThreshold)
            return (adjustedThreshold, METCalculationConstants.highRecoveryThresholdAdjustment / METCalculationConstants.normalRecoveryThreshold)
        }
        
        return (baseThreshold, 1.0)
    }
    
    // MARK: - Recovery/Readiness Integration
    
    /// Adjusts recovery score based on yesterday's beneficial MET load.
    nonisolated static func adjustRecoveryForMETLoad(
        baseRecovery: Double,
        yesterdayBeneficialMETs: Double,
        maxMETs: Double
    ) -> Double {
        let metStressIndex = yesterdayBeneficialMETs / (maxMETs * 2.0)
        
        if yesterdayBeneficialMETs > (maxMETs * 1.5) {
            // High load: penalize recovery
            return baseRecovery * METCalculationConstants.highLoadRecoveryPenalty
        } else if yesterdayBeneficialMETs < (maxMETs * 0.3) {
            // Low load / recovery day: bonus
            return baseRecovery + METCalculationConstants.lowLoadRecoveryBonus
        }
        
        return baseRecovery
    }
    
    /// Adjusts readiness score based on MET stress index.
    nonisolated static func adjustReadinessForMETLoad(
        baseReadiness: Double,
        beneficialMETsToday: Double,
        maxMETs: Double
    ) -> Double {
        let metStressIndex = beneficialMETsToday / (maxMETs * 2.0)
        
        if metStressIndex > 1.0 {
            let penalty = (metStressIndex - 1.0) * METCalculationConstants.metStressReadinessPenalty
            return baseReadiness * (1.0 - penalty)
        }
        
        return baseReadiness
    }
}

// MARK: - Helper Extensions

extension Array where Element == Double {
    fileprivate var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .crossTraining: return "Cross Training"
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .cricket: return "Cricket"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .kickboxing: return "Kickboxing"
        case .kiteSurfing: return "Kite Surfing"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind & Body"
        case .mixedMetabolicCardioTraining: return "Mixed Cardio"
        case .paddleSports: return "Paddle Sports"
        case .pilates: return "Pilates"
        case .racquetball: return "Racquetball"
        case .rockClimbing: return "Rock Climbing"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .skatingSports: return "Skating"
        case .skiing: return "Skiing"
        case .snowboarding: return "Snowboarding"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing"
        case .tabletennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track & Field"
        case .traditionalStrengthTraining: return "Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }
}
