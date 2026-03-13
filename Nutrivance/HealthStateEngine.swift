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

    // MARK: - Baselines (7-day and 28-day windows)

    @Published var hrvBaseline7Day: Double?      // 7-day average
    @Published var rhrBaseline7Day: Double?      // 7-day average
    @Published var sleepBaseline7Day: Double?    // 7-day average
    @Published var hrvBaseline28Day: Double?     // 28-day average
    @Published var rhrBaseline28Day: Double?     // 28-day average
    
    @Published var recoveryBaseline7Day: Double?      // 7-day recovery score average
    @Published var strainBaseline7Day: Double?        // 7-day strain score average
    @Published var circadianBaseline7Day: Double?     // 7-day circadian score average
    @Published var autonomicBaseline7Day: Double?     // 7-day autonomic balance average
    @Published var moodBaseline7Day: Double?          // 7-day mood score average
    
    // Rolling history for baseline calculations
    private var recoveryScoreHistory: [Double] = []
    private var strainScoreHistory: [Double] = []
    private var circadianScoreHistory: [Double] = []
    private var autonomicScoreHistory: [Double] = []
    private var moodScoreHistory: [Double] = []

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
        let group = DispatchGroup()
        
        // Start all fetch operations without calling updateScores individually
        group.enter()
        DispatchQueue.global().async {
            self.fetchLatestHRV()
            group.leave()
        }
        
        group.enter()
        DispatchQueue.global().async {
            self.fetchHRVHistory(days: 30)
            group.leave()
        }
        
        group.enter()
        DispatchQueue.global().async {
            self.fetchRestingHeartRate()
            group.leave()
        }
        
        group.enter()
        DispatchQueue.global().async {
            self.fetchSleep()
            group.leave()
        }
        
        group.enter()
        DispatchQueue.global().async {
            self.fetchBaselines()
            group.leave()
        }
        
        group.enter()
        DispatchQueue.global().async {
            self.fetchTrainingLoad()
            group.leave()
        }
        
        // After all fetches complete, update scores once on main thread
        group.notify(queue: .main) {
            self.updateScores()
        }
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
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Fetch Sleep

    private func fetchSleep() {

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        // Fetch last 3 days to capture sleep that spans midnight
        let start = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let end = Date()

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in

            guard let samples = samples as? [HKCategorySample] else { return }

            let calendar = Calendar.current
            
            // Categorize all samples by stage type and group by day
            // Stage values: awake=2, unspecifiedAsleep=1, core=3, deep=4, rem=5
            var stagesByDay: [Date: [Int: [HKCategorySample]]] = [:]  // [day: [stageValue: [samples]]]
            
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                
                if stagesByDay[day] == nil {
                    stagesByDay[day] = [:]
                }
                if stagesByDay[day]![sample.value] == nil {
                    stagesByDay[day]![sample.value] = []
                }
                stagesByDay[day]![sample.value]?.append(sample)
            }
            
            // Get the most recent day with sleep
            guard let mostRecentDay = stagesByDay.keys.max() else { return }
            guard let stageSamples = stagesByDay[mostRecentDay] else { return }
            
            // Aggregate sleep: sum unspecified (1), core (3), deep (4), rem (5) — exclude awake (2)
            var totalSleep: Double = 0
            var earliestStart: Date?
            var latestEnd: Date?
            
            let sleepStageValues = [1, 3, 4, 5]  // unspecified, core, deep, rem
            
            for stageValue in sleepStageValues {
                if let stageAmples = stageSamples[stageValue] {
                    for sample in stageAmples {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate)
                        if duration > 0 {  // >= 10 minutes
                            totalSleep += duration
                            
                            if earliestStart == nil || sample.startDate < earliestStart! {
                                earliestStart = sample.startDate
                            }
                            if latestEnd == nil || sample.endDate > latestEnd! {
                                latestEnd = sample.endDate
                            }
                        }
                    }
                }
            }

            // Cap total sleep to 9 hours
            let cappedSleepHours = min(totalSleep / 3600, 9.0)

            DispatchQueue.main.async {
                self.sleepHours = cappedSleepHours
                if let start = earliestStart, let end = latestEnd {
                    self.lastSleepStart = start
                    self.lastSleepEnd = end
                }
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

            if !values.isEmpty {
                let avg = values.reduce(0, +) / Double(values.count)
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

        // Fetch 7-day baselines
        guard let start7Day = calendar.date(byAdding: .day, value: -7, to: endDate) else { return }
        
        // Use a dispatch group to coordinate all baseline fetches
        let group = DispatchGroup()
        var hrvAvg7: Double?
        var rhrAvg7: Double?
        var sleepAvg7: Double?
        var hrvAvg28: Double?
        var rhrAvg28: Double?
        
        // 7-day baselines
        group.enter()
        fetchAverage(for: .heartRateVariabilitySDNN, start: start7Day, end: endDate) { value in
            hrvAvg7 = value
            group.leave()
        }
        
        group.enter()
        fetchAverage(for: .restingHeartRate, start: start7Day, end: endDate) { value in
            rhrAvg7 = value
            group.leave()
        }
        
        group.enter()
        fetchSleepBaseline(days: 7) { value in
            sleepAvg7 = value
            group.leave()
        }
        
        // 28-day baselines
        guard let start28Day = calendar.date(byAdding: .day, value: -28, to: endDate) else { return }
        
        group.enter()
        fetchAverage(for: .heartRateVariabilitySDNN, start: start28Day, end: endDate) { value in
            hrvAvg28 = value
            group.leave()
        }
        
        group.enter()
        fetchAverage(for: .restingHeartRate, start: start28Day, end: endDate) { value in
            rhrAvg28 = value
            group.leave()
        }
        
        // When all fetches complete, update on main thread
        group.notify(queue: .main) {
            if let hrvAvg7 { self.hrvBaseline7Day = hrvAvg7 }
            if let rhrAvg7 { self.rhrBaseline7Day = rhrAvg7 }
            if let sleepAvg7 { self.sleepBaseline7Day = sleepAvg7 }
            if let hrvAvg28 { self.hrvBaseline28Day = hrvAvg28 }
            if let rhrAvg28 { self.rhrBaseline28Day = rhrAvg28 }
        }
    }
    
    private func fetchSleepBaseline(days: Int, completion: @escaping (Double?) -> Void) {
        
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }
        
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        
        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
            
            guard let samples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }
            
            let calendar = Calendar.current
            var dailySleepHours: [Double] = []
            
            // Group samples by calendar day
            var stagesByDay: [Date: [Int: [HKCategorySample]]] = [:]
            
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                if stagesByDay[day] == nil {
                    stagesByDay[day] = [:]
                }
                if stagesByDay[day]![sample.value] == nil {
                    stagesByDay[day]![sample.value] = []
                }
                stagesByDay[day]![sample.value]?.append(sample)
            }
            
            // For each day, sum sleep stages (1, 3, 4, 5) — exclude awake (2)
            let sleepStageValues = [1, 3, 4, 5]
            
            for (_, stageSamples) in stagesByDay.sorted(by: { $0.key < $1.key }) {
                var totalSleep: Double = 0
                
                for stageValue in sleepStageValues {
                    if let stageAmples = stageSamples[stageValue] {
                        for sample in stageAmples {
                            let duration = sample.endDate.timeIntervalSince(sample.startDate)
                            if duration > 0 {
                                totalSleep += duration
                            }
                        }
                    }
                }
                
                let cappedSleep = min(totalSleep / 3600, 9.0)
                if cappedSleep > 0 {
                    dailySleepHours.append(cappedSleep)
                }
            }
            
            // Calculate average of daily values
            if !dailySleepHours.isEmpty {
                let average = dailySleepHours.reduce(0, +) / Double(dailySleepHours.count)
                completion(average)
            } else {
                completion(nil)
            }
        }
        
        healthStore.execute(query)
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


    // Improved: Calculate rolling acute (7d) and chronic (28d) loads with exponential decay, and update strain/ACWR
    private func fetchTrainingLoad() {
        let calendar = Calendar.current
        let endDate = Date()
        guard
            let start28 = calendar.date(byAdding: .day, value: -28, to: endDate)
        else { return }

        // Fetch all workouts in the last 28 days
        let predicate = HKQuery.predicateForSamples(withStart: start28, end: endDate)
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            let workouts = (samples as? [HKWorkout]) ?? []
            // Build a daily load array for the last 28 days
            var dailyLoads = Array(repeating: 0.0, count: 28)
            for workout in workouts {
                let dayIndex = calendar.dateComponents([.day], from: start28, to: calendar.startOfDay(for: workout.endDate)).day ?? 0
                if dayIndex >= 0 && dayIndex < 28 {
                    let durationMinutes = workout.duration / 60.0
                    let effortRating: Double
                    if let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), durationMinutes > 0 {
                        let intensity = energy / durationMinutes
                        effortRating = min(10, max(1, intensity / 8))
                    } else {
                        effortRating = 5
                    }
                    dailyLoads[dayIndex] += durationMinutes * effortRating
                }
            }
            // Calculate EWMA for acute (7d) and chronic (28d) loads
            // EWMA: load_today = lambda * today + (1-lambda) * load_yesterday
            func ewma(_ loads: [Double], lambda: Double) -> Double {
                var avg = 0.0
                for load in loads {
                    avg = lambda * load + (1 - lambda) * avg
                }
                return avg
            }
            // Higher lambda = more weight to recent days
            let acuteLambda = 2.0 / (7.0 + 1.0) // ~0.25
            let chronicLambda = 2.0 / (28.0 + 1.0) // ~0.069
            let acuteLoad = ewma(dailyLoads.suffix(7), lambda: acuteLambda)
            let chronicLoad = ewma(dailyLoads, lambda: chronicLambda)
            DispatchQueue.main.async {
                self.activityLoad = acuteLoad
                // Avoid divide by zero
                let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 0
                // Strain score: optimal 0.8-1.3, high 1.3-1.5, overload >1.5, low <0.8
                let strain: Double
                switch acwr {
                case ..<0.8: strain = 30
                case 0.8..<1.3: strain = 50
                case 1.3..<1.5: strain = 75
                default: strain = 95
                }
                // Decay strain if no recent load
                let daysSinceLast = dailyLoads.lastIndex(where: { $0 > 0 })
                var decayFactor = 1.0
                if let lastDay = daysSinceLast, lastDay < 27 {
                    let daysNoLoad = 27 - lastDay
                    decayFactor = pow(0.85, Double(daysNoLoad)) // 15% decay per day without load
                }
                self.strainScore = min(100, strain * decayFactor)
            }
        }
        healthStore.execute(query)
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

    // MARK: - Feel-Good Score
    @Published var feelGoodScore: Double = 50

    /// Calculate the overall Feel-Good Score based on multiple metrics
    private func calculateFeelGoodScore(subjectiveInput: Double = 0.5) -> Double {
        guard let hrv = latestHRV, let rhr = restingHeartRate, let sleep = sleepHours else {
            return 50
        }

        // Normalize components using 7-day baselines
        let hrvNorm = min(hrv / (hrvBaseline7Day ?? hrv), 1)
        let rhrNorm = max(0, min((80 - rhr) / 20, 1)) // 60-80 bpm optimal
        let sleepNorm = min(sleep / 8.0, 1)
        let recoveryNorm = min(recoveryScore / 100, 1)
        let strainNorm = max(0, min(1 - strainScore / 100, 1))
        let circadianNorm = min(circadianHRVScore / 100, 1)
        let moodNorm = subjectiveInput // 0-1 from user feedback

        // Weighted combination
        let score = 0.25*hrvNorm
                  + 0.15*rhrNorm
                  + 0.2*sleepNorm
                  + 0.2*recoveryNorm
                  + 0.1*strainNorm
                  + 0.05*circadianNorm
                  + 0.05*moodNorm

        return max(0, min(100, score * 100))
    }

    /// Update Feel-Good Score whenever scores refresh
    private func updateFeelGoodScore() {
        feelGoodScore = calculateFeelGoodScore()
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
        
        // Update 7-day rolling averages for score baselines
        updateScoreBaselines()

        // Update Feel-Good Score
        updateFeelGoodScore()
    }
    
    private func updateScoreBaselines() {
        // Add current scores to rolling history (keep only 7 days worth)
        recoveryScoreHistory.append(recoveryScore)
        strainScoreHistory.append(strainScore)
        circadianScoreHistory.append(circadianHRVScore)
        autonomicScoreHistory.append(autonomicBalanceScore)
        moodScoreHistory.append(moodScore)
        
        // Keep only 7 most recent values
        if recoveryScoreHistory.count > 7 { recoveryScoreHistory.removeFirst() }
        if strainScoreHistory.count > 7 { strainScoreHistory.removeFirst() }
        if circadianScoreHistory.count > 7 { circadianScoreHistory.removeFirst() }
        if autonomicScoreHistory.count > 7 { autonomicScoreHistory.removeFirst() }
        if moodScoreHistory.count > 7 { moodScoreHistory.removeFirst() }
        
        // Calculate 7-day averages
        if !recoveryScoreHistory.isEmpty {
            recoveryBaseline7Day = recoveryScoreHistory.reduce(0, +) / Double(recoveryScoreHistory.count)
        }
        if !strainScoreHistory.isEmpty {
            strainBaseline7Day = strainScoreHistory.reduce(0, +) / Double(strainScoreHistory.count)
        }
        if !circadianScoreHistory.isEmpty {
            circadianBaseline7Day = circadianScoreHistory.reduce(0, +) / Double(circadianScoreHistory.count)
        }
        if !autonomicScoreHistory.isEmpty {
            autonomicBaseline7Day = autonomicScoreHistory.reduce(0, +) / Double(autonomicScoreHistory.count)
        }
        if !moodScoreHistory.isEmpty {
            moodBaseline7Day = moodScoreHistory.reduce(0, +) / Double(moodScoreHistory.count)
        }
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
        guard let baseline = hrvBaseline7Day else { return 50 }
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

        guard let baseline = hrvBaseline7Day else { return 50 }

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

        guard let baseline = hrvBaseline7Day else { return 50 }

        // deviation of recent trend from baseline
        let deviation = (avg7 - baseline) / baseline

        // map roughly -25% to +25% trend into 0–100 score
        let scaled = (deviation * 200) + 50

        return max(0, min(100, scaled))
    }

    // MARK: - Autonomic Balance
    private func calculateAutonomicBalance() -> Double {

        guard let hrv = latestHRV, let rhr = restingHeartRate else { return 50 }

        let hrvSignal = PhysiologySignal(value: hrv, baseline: hrvBaseline7Day ?? hrv, direction: .higherIsBetter)
        let rhrSignal = PhysiologySignal(value: rhr, baseline: rhrBaseline7Day ?? rhr, direction: .lowerIsBetter)

        // Combine HRV and RHR for autonomic balance, equal weighting
        let balance = (hrvSignal.score * 0.5) + (rhrSignal.score * 0.5)

        return max(0, min(100, balance))
    }

    // MARK: - Strain

    private func calculateAllostaticStress() -> Double {

        var stress: Double = 0

        if let hrv = latestHRV {
            let hrvSignal = PhysiologySignal(value: hrv, baseline: hrvBaseline28Day ?? hrv, direction: .higherIsBetter)
            stress += (100 - hrvSignal.score) * 0.35
        }

        if let rhr = restingHeartRate {
            let rhrSignal = PhysiologySignal(value: rhr, baseline: rhrBaseline28Day ?? rhr, direction: .lowerIsBetter)
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
        guard let baseline = hrvBaseline7Day else { return 50 }

        let signal = PhysiologySignal(value: hrv, baseline: baseline, direction: .higherIsBetter)
        return signal.score
    }

    private func normalizeRHR(_ rhr: Double) -> Double {
        guard let baseline = rhrBaseline7Day else { return 50 }

        let signal = PhysiologySignal(value: rhr, baseline: baseline, direction: .lowerIsBetter)
        return signal.score
    }

    private func normalizeSleep(_ hours: Double) -> Double {

        let optimal = 8.0
        let ratio = hours / optimal

        return max(0, min(100, ratio * 100))
    }
}
