//
//  File.swift
//  Nutrivance
//
//  Created by Vincent Leong on 3/11/26.
//

import Foundation
import HealthKit
import Combine

/// Central physiology engine for Nutrivance.
/// All health calculations should live here, not in Views.
final class HealthStateEngine: ObservableObject {

    // MARK: - HealthKit

    private let healthStore = HKHealthStore()

    // MARK: - Raw Metrics (Fetched from HealthKit)

    @Published var latestHRV: Double?          // ms
    @Published var restingHeartRate: Double?   // bpm
    @Published var sleepHours: Double?         // hours
    @Published var activityLoad: Double = 0    // arbitrary training load
    @Published var hrvHistory: [Double] = []   // last 30 HRV values
    @Published var dailyHRV: [DailyHRVPoint] = []
    @Published var sleepHRVAverage: Double?
    // Track last completed sleep session
    @Published var lastSleepStart: Date?
    @Published var lastSleepEnd: Date?

    // MARK: - Baselines

    @Published var hrvBaseline: Double?
    @Published var rhrBaseline: Double?

    // MARK: - Baseline / Load Models

    struct DailyHRVPoint {
        let date: Date
        let average: Double
        let min: Double
        let max: Double
    }

    struct PhysiologicalBaseline {
        let hrvBaseline: Double
        let rhrBaseline: Double
    }

    struct TrainingLoad {
        let acuteLoad: Double
        let chronicLoad: Double
        let acwr: Double
    }

    struct PhysiologySignal {
        enum Direction {
            case higherIsBetter
            case lowerIsBetter
        }

        let value: Double
        let baseline: Double
        let direction: Direction

        var deviation: Double {
            switch direction {
            case .higherIsBetter:
                return (value - baseline) / baseline
            case .lowerIsBetter:
                return (baseline - value) / baseline
            }
        }

        var score: Double {
            let scaled = (deviation * 150) + 50
            return max(0, min(100, scaled))
        }
    }

    struct HealthDomainSignal {
        let value: Double
        let baseline: Double?
        let direction: PhysiologySignal.Direction
        let weight: Double // importance weighting in composite scores
    }

    // Example usage for future expansion:
    // nutrition, mood, subjective readiness, illness, circadian chronotype
    @Published var nutritionScore: Double = 50
    @Published var moodScore: Double = 50
    @Published var subjectiveReadinessScore: Double = 50
    @Published var illnessScore: Double = 50
    @Published var chronotypeScore: Double = 50

    // MARK: - Derived Scores

    @Published var recoveryScore: Double = 0
    @Published var strainScore: Double = 0
    @Published var readinessScore: Double = 0
    @Published var hrvTrendScore: Double = 50
    @Published var circadianHRVScore: Double = 50
    @Published var sleepHRVScore: Double = 50
    @Published var allostaticStressScore: Double = 50
    @Published var autonomicBalanceScore: Double = 50

    // MARK: - Initialization

    init() {
        requestPermissions()
        refreshAllMetrics()
    }

    // MARK: - Permissions

    private func requestPermissions() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let readTypes: Set<HKObjectType> = [hrv, rhr, sleep]

        healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
            if success {
                DispatchQueue.main.async {
                    self.refreshAllMetrics()
                }
            }
        }
    }

    // MARK: - Public Refresh

    func refreshAllMetrics() {
        fetchLatestHRV()
        fetchHRVHistory(days: 30)
        fetchRestingHeartRate()
        fetchSleep()
        fetchBaselines()
        fetchTrainingLoad()
    }

    // MARK: - Fetch HRV

    private func fetchLatestHRV() {

        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: type,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in

            guard let sample = samples?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))

            DispatchQueue.main.async {
                self.latestHRV = value
                self.updateScores()
            }
        }

        healthStore.execute(query)
    }

    // MARK: - HRV History

    private func fetchHRVHistory(days: Int) {

        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in

            guard let quantitySamples = samples as? [HKQuantitySample] else { return }

            let samplesWithDates = quantitySamples.map {
                (
                    date: $0.endDate,
                    value: $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                )
            }

            let values = samplesWithDates.map { $0.value }

            let calendar = Calendar.current

            let grouped = Dictionary(grouping: samplesWithDates) {
                calendar.startOfDay(for: $0.date)
            }

            let dailyPoints: [DailyHRVPoint] = grouped.map { (day, samples) in

                let vals = samples.map { $0.value }

                let avg = vals.reduce(0, +) / Double(vals.count)

                return DailyHRVPoint(
                    date: day,
                    average: avg,
                    min: vals.min() ?? avg,
                    max: vals.max() ?? avg
                )

            }.sorted { $0.date < $1.date }

            DispatchQueue.main.async {
                self.hrvHistory = values
                self.dailyHRV = dailyPoints
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Fetch Resting HR

    private func fetchRestingHeartRate() {

        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: type,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in

            guard let sample = samples?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

            DispatchQueue.main.async {
                self.restingHeartRate = value
                self.updateScores()
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Fetch Sleep

    private func fetchSleep() {

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in

            guard let samples = samples as? [HKCategorySample] else { return }

            // Updated sleep processing: sum all .asleep, ignore fragments <10min, cap total to 9h
            var totalSleep: TimeInterval = 0
            var earliestStart: Date?
            var latestEnd: Date?

            // Find the last completed sleep session (latest one that ended before now)
            var lastSleepStart: Date?
            var lastSleepEnd: Date?
            let now = Date()
            let sleepSessions = samples
                .filter { $0.value == HKCategoryValueSleepAnalysis.asleep.rawValue }
                .filter { $0.endDate <= now }
                .filter { $0.endDate.timeIntervalSince($0.startDate) >= 600 }
                .sorted { $0.endDate > $1.endDate }

            if let last = sleepSessions.first {
                lastSleepStart = last.startDate
                lastSleepEnd = last.endDate
            }

            for sleepSample in samples {
                // Only consider actual sleep (asleep)
                if sleepSample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                    let duration = sleepSample.endDate.timeIntervalSince(sleepSample.startDate)

                    // Ignore fragments <10 minutes
                    if duration < 600 { continue }

                    totalSleep += duration

                    if earliestStart == nil || sleepSample.startDate < earliestStart! {
                        earliestStart = sleepSample.startDate
                    }
                    if latestEnd == nil || sleepSample.endDate > latestEnd! {
                        latestEnd = sleepSample.endDate
                    }
                }
            }

            // Cap total sleep to 9 hours
            let cappedSleepHours = min(totalSleep / 3600, 9.0)

            DispatchQueue.main.async {
                self.sleepHours = cappedSleepHours
                if let start = lastSleepStart, let end = lastSleepEnd {
                    self.lastSleepStart = start
                    self.lastSleepEnd = end
                    self.fetchHRVDuringSleep(start: start, end: end)
                }
                self.updateScores()
            }
        }

        healthStore.execute(query)
    }

    private func fetchHRVDuringSleep(start: Date, end: Date) {

        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        // Use earliest start and latest end across all sleep stages for HRV query
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in

            guard let quantitySamples = samples as? [HKQuantitySample], quantitySamples.count > 0 else { return }

            let values = quantitySamples.map {
                $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            }

            let avg = values.reduce(0, +) / Double(values.count)
            self.sleepHRVAverage = avg

            if !values.isEmpty {
                DispatchQueue.main.async {
                    self.sleepHRVAverage = avg
                    self.sleepHRVScore = self.analyzeSleepWeightedHRV()
                }
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Baseline Fetching

    private func fetchBaselines() {

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -60, to: endDate) else { return }

        fetchAverage(for: .heartRateVariabilitySDNN, start: startDate, end: endDate) { hrvAvg in
            self.fetchAverage(for: .restingHeartRate, start: startDate, end: endDate) { rhrAvg in

                DispatchQueue.main.async {
                    if let hrvAvg { self.hrvBaseline = hrvAvg }
                    if let rhrAvg { self.rhrBaseline = rhrAvg }
                    self.updateScores()
                }
            }
        }
    }

    private func fetchAverage(
        for identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        completion: @escaping (Double?) -> Void
    ) {

        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, result, _ in

            guard let avg = result?.averageQuantity() else {
                completion(nil)
                return
            }

            let unit: HKUnit

            switch identifier {
            case .heartRateVariabilitySDNN:
                unit = HKUnit.secondUnit(with: .milli)

            case .restingHeartRate:
                unit = HKUnit.count().unitDivided(by: HKUnit.minute())

            default:
                unit = HKUnit.count()
            }

            completion(avg.doubleValue(for: unit))
        }

        healthStore.execute(query)
    }

    // MARK: - Training Load

    private func fetchTrainingLoad() {

        let calendar = Calendar.current
        let endDate = Date()

        guard
            let start7 = calendar.date(byAdding: .day, value: -7, to: endDate),
            let start28 = calendar.date(byAdding: .day, value: -28, to: endDate)
        else { return }

        fetchWorkoutLoad(start: start7, end: endDate) { acute in
            self.fetchWorkoutLoad(start: start28, end: endDate) { chronic in

                guard let acute, let chronic, chronic > 0 else { return }

                let acwr = acute / chronic

                DispatchQueue.main.async {
                    self.activityLoad = acute
                    self.strainScore = min(100, acute)
                }
            }
        }
    }

    private func fetchWorkoutLoad(
        start: Date,
        end: Date,
        completion: @escaping (Double?) -> Void
    ) {

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in

            guard let workouts = samples as? [HKWorkout] else {
                completion(nil)
                return
            }

            var totalLoad: Double = 0

            for workout in workouts {

                let durationMinutes = workout.duration / 60.0

                let effortRating: Double

                if let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), durationMinutes > 0 {
                    // kcal per minute as intensity proxy
                    let intensity = energy / durationMinutes

                    // map typical intensity range to 1–10 effort scale
                    effortRating = min(10, max(1, intensity / 8))
                } else {
                    effortRating = 5
                }

                let load = durationMinutes * effortRating

                totalLoad += load
            }

            completion(totalLoad)
        }

        healthStore.execute(query)
    }

    // MARK: - Score Calculations

    private func updateScores() {

        recoveryScore = calculateRecoveryScore()
        strainScore = calculateStrainScore()
        hrvTrendScore = analyzeHRVTrend()
        circadianHRVScore = analyzeCircadianHRV()
        sleepHRVScore = analyzeSleepWeightedHRV()
        allostaticStressScore = calculateAllostaticStress()
        autonomicBalanceScore = calculateAutonomicBalance()

        // Morning readiness model
        let readiness = (recoveryScore * 0.55)
                      + (hrvTrendScore * 0.15)
                      + (circadianHRVScore * 0.10)
                      + (sleepHRVScore * 0.20)
                      - (strainScore * 0.30)

        readinessScore = max(0, min(100, readiness))
    }

    // MARK: - Recovery

    private func calculateRecoveryScore() -> Double {

        var score: Double = 0

        if let hrv = latestHRV {
            score += normalizeHRV(hrv) * 0.4
        }

        if let rhr = restingHeartRate {
            score += normalizeRHR(rhr) * 0.25
        }

        if let sleep = sleepHours {
            score += normalizeSleep(sleep) * 0.25
        }

        let sleepHRV = analyzeSleepWeightedHRV()
        score += sleepHRV * 0.10

        // HRV trend contributes slightly to recovery
        let trend = analyzeHRVTrend()
        score += trend * 0.10

        return max(0, min(100, score))
    }

    // MARK: - Sleep-Weighted HRV

    private func analyzeSleepWeightedHRV() -> Double {
        guard let baseline = hrvBaseline else { return 50 }
        guard let avgHRV = sleepHRVAverage else { return 50 }

        var score = PhysiologySignal(
            value: avgHRV,
            baseline: baseline,
            direction: .higherIsBetter
        ).score

        if let sleep = sleepHours, sleep > 0 {
            let sleepFactor = min(1.0, sleep / 8.0)
            score *= sleepFactor
        }

        return max(0, min(100, score))
    }

    // MARK: - Circadian HRV Analyzer

    private func analyzeCircadianHRV() -> Double {

        guard hrvHistory.count >= 10 else { return 50 }

        // approximate circadian pattern using early vs late samples
        let midpoint = hrvHistory.count / 2

        let firstHalf = hrvHistory.prefix(midpoint)
        let secondHalf = hrvHistory.suffix(midpoint)

        guard firstHalf.count > 0 && secondHalf.count > 0 else { return 50 }

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        guard let baseline = hrvBaseline else { return 50 }

        // healthy circadian rhythm usually shows higher nighttime HRV
        let circadianDelta = (secondAvg - firstAvg) / baseline

        let scaled = (circadianDelta * 200) + 50

        return max(0, min(100, scaled))
    }

    // MARK: - HRV Trend Analyzer

    private func analyzeHRVTrend() -> Double {

        guard hrvHistory.count >= 7 else { return 50 }

        let last7 = hrvHistory.suffix(7)
        let avg7 = last7.reduce(0, +) / Double(last7.count)

        guard let baseline = hrvBaseline else { return 50 }

        // deviation of recent trend from baseline
        let deviation = (avg7 - baseline) / baseline

        // map roughly -25% to +25% trend into 0–100 score
        let scaled = (deviation * 200) + 50

        return max(0, min(100, scaled))
    }

    // MARK: - Autonomic Balance
    private func calculateAutonomicBalance() -> Double {

        guard let hrv = latestHRV, let rhr = restingHeartRate else { return 50 }

        let hrvSignal = PhysiologySignal(value: hrv, baseline: hrvBaseline ?? hrv, direction: .higherIsBetter)
        let rhrSignal = PhysiologySignal(value: rhr, baseline: rhrBaseline ?? rhr, direction: .lowerIsBetter)

        // Combine HRV and RHR for autonomic balance, equal weighting
        let balance = (hrvSignal.score * 0.5) + (rhrSignal.score * 0.5)

        return max(0, min(100, balance))
    }

    // MARK: - Strain

    private func calculateAllostaticStress() -> Double {

        var stress: Double = 0

        if let hrv = latestHRV {
            let hrvSignal = PhysiologySignal(value: hrv, baseline: hrvBaseline ?? hrv, direction: .higherIsBetter)
            stress += (100 - hrvSignal.score) * 0.35
        }

        if let rhr = restingHeartRate {
            let rhrSignal = PhysiologySignal(value: rhr, baseline: rhrBaseline ?? rhr, direction: .lowerIsBetter)
            stress += (100 - rhrSignal.score) * 0.25
        }

        if let sleep = sleepHours {
            let sleepScore = normalizeSleep(sleep)
            stress += (100 - sleepScore) * 0.20
        }

        let strain = calculateStrainScore()
        stress += strain * 0.20

        return max(0, min(100, stress))
    }

    private func calculateStrainScore() -> Double {

        let acute = activityLoad
        let chronic = max(activityLoad / 4, 1) // placeholder if chronic not available
        let acwr = acute / chronic

        // Map ACWR to strain score
        // 0.8-1.3 optimal, 1.3-1.5 high, >1.5 overload
        let strainScore: Double
        switch acwr {
        case ..<0.8:
            strainScore = 30 // low load
        case 0.8..<1.3:
            strainScore = 50 // optimal
        case 1.3..<1.5:
            strainScore = 75 // high load
        default:
            strainScore = 95 // overload
        }

        return min(100, strainScore)
    }

    // MARK: - Normalization Helpers

    private func normalizeHRV(_ hrv: Double) -> Double {
        guard let baseline = hrvBaseline else { return 50 }

        let signal = PhysiologySignal(value: hrv, baseline: baseline, direction: .higherIsBetter)
        return signal.score
    }

    private func normalizeRHR(_ rhr: Double) -> Double {
        guard let baseline = rhrBaseline else { return 50 }

        let signal = PhysiologySignal(value: rhr, baseline: baseline, direction: .lowerIsBetter)
        return signal.score
    }

    private func normalizeSleep(_ hours: Double) -> Double {

        let optimal = 8.0
        let ratio = hours / optimal

        return max(0, min(100, ratio * 100))
    }
}

