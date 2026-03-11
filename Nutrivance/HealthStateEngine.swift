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

    // MARK: - Baselines

    @Published var hrvBaseline: Double?
    @Published var rhrBaseline: Double?

    // MARK: - Derived Scores

    @Published var recoveryScore: Double = 0
    @Published var strainScore: Double = 0
    @Published var readinessScore: Double = 0

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
        fetchRestingHeartRate()
        fetchSleep()
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

        let start = Calendar.current.startOfDay(for: Date())

        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in

            var totalSleep: TimeInterval = 0

            samples?.forEach { sample in
                guard let sleepSample = sample as? HKCategorySample else { return }

                if sleepSample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                    totalSleep += sleepSample.endDate.timeIntervalSince(sleepSample.startDate)
                }
            }

            DispatchQueue.main.async {
                self.sleepHours = totalSleep / 3600
                self.updateScores()
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Score Calculations

    private func updateScores() {

        recoveryScore = calculateRecoveryScore()
        strainScore = calculateStrainScore()
        readinessScore = max(0, min(100, recoveryScore - strainScore * 0.5))
    }

    // MARK: - Recovery

    private func calculateRecoveryScore() -> Double {

        var score: Double = 0

        if let hrv = latestHRV {
            score += normalizeHRV(hrv) * 0.4
        }

        if let rhr = restingHeartRate {
            score += normalizeRHR(rhr) * 0.3
        }

        if let sleep = sleepHours {
            score += normalizeSleep(sleep) * 0.3
        }

        return max(0, min(100, score))
    }

    // MARK: - Strain

    private func calculateStrainScore() -> Double {
        return min(100, activityLoad)
    }

    // MARK: - Normalization Helpers

    private func normalizeHRV(_ hrv: Double) -> Double {
        guard let baseline = hrvBaseline else { return 50 }

        let ratio = hrv / baseline

        return max(0, min(100, ratio * 50))
    }

    private func normalizeRHR(_ rhr: Double) -> Double {
        guard let baseline = rhrBaseline else { return 50 }

        let ratio = baseline / rhr

        return max(0, min(100, ratio * 50))
    }

    private func normalizeSleep(_ hours: Double) -> Double {

        let optimal = 8.0
        let ratio = hours / optimal

        return max(0, min(100, ratio * 100))
    }
}
