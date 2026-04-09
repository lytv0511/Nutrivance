#if os(iOS)
import CloudKit
import Foundation
import HealthKit

/// iOS **producer**: reads authorized HealthKit samples and upserts `HealthMetricRecord` into the user's **private** CloudKit database.
/// Stable `CKRecord.ID` = HK object UUID → idempotent sync; watermark advances on successful upload (delta forward sync).
final class HealthKitCloudSyncProducer: @unchecked Sendable {
    static let shared = HealthKitCloudSyncProducer()

    private let syncQueue = DispatchQueue(label: "com.nutrivance.healthkit.cloud.producer", qos: .utility)
    private var observerQueries: [HKObserverQuery] = []
    private let watermarkKeyPrefix = "HealthCloudSyncSampleStartWatermark"
    private let initialBackfillDays = 14

    private let observedQuantityTypes: [HKQuantityTypeIdentifier] = [
        .heartRate,
        .restingHeartRate,
        .heartRateVariabilitySDNN,
        .stepCount,
        .appleExerciseTime,
        .activeEnergyBurned,
        .distanceWalkingRunning,
        .oxygenSaturation,
        .respiratoryRate,
    ]

    /// Call after HealthKit authorization succeeds (e.g. from `HealthKitManager.requestAuthorization`).
    func startIfPossible(healthStore: HKHealthStore) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        syncQueue.async { [weak self] in
            self?.installObservers(healthStore: healthStore)
        }
    }

    private func installObservers(healthStore: HKHealthStore) {
        observerQueries.removeAll()

        for id in observedQuantityTypes {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            guard authorizedToRead(healthStore: healthStore, type: type) else { continue }

            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }

            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if error == nil {
                    self?.syncQueue.async {
                        self?.syncQuantityBatches(identifier: id, healthStore: healthStore)
                    }
                }
                completionHandler()
            }
            healthStore.execute(query)
            observerQueries.append(query)
        }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
           authorizedToRead(healthStore: healthStore, type: sleepType) {
            healthStore.enableBackgroundDelivery(for: sleepType, frequency: .hourly) { _, _ in }
            let q = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, done, err in
                if err == nil {
                    self?.syncQueue.async {
                        self?.syncSleepBatches(healthStore: healthStore)
                    }
                }
                done()
            }
            healthStore.execute(q)
            observerQueries.append(q)
        }

        syncQueue.async { [weak self] in
            guard let self else { return }
            for id in self.observedQuantityTypes {
                self.syncQuantityBatches(identifier: id, healthStore: healthStore)
            }
            self.syncSleepBatches(healthStore: healthStore)
        }
    }

    private func authorizedToRead(healthStore: HKHealthStore, type: HKObjectType) -> Bool {
        healthStore.authorizationStatus(for: type) == .sharingAuthorized
    }

    private func watermarkKey(for metricKey: String) -> String {
        "\(watermarkKeyPrefix).\(metricKey)"
    }

    private func watermarkStart(for metricKey: String) -> Date {
        let key = watermarkKey(for: metricKey)
        if let d = UserDefaults.standard.object(forKey: key) as? Date {
            return d
        }
        return Calendar.current.date(byAdding: .day, value: -initialBackfillDays, to: Date()) ?? .distantPast
    }

    private func advanceWatermark(metricKey: String, samples: [HKSample]) {
        guard let maxStart = samples.map(\.startDate).max() else { return }
        let key = watermarkKey(for: metricKey)
        let current = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        if maxStart > current {
            UserDefaults.standard.set(maxStart, forKey: key)
        }
    }

    private func syncQuantityBatches(identifier: HKQuantityTypeIdentifier, healthStore: HKHealthStore) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
        guard authorizedToRead(healthStore: healthStore, type: type) else { return }

        let hk = HealthKitManager()
        let unit = hk.unit(for: identifier)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let metricKey = identifier.rawValue

        var workingStart = watermarkStart(for: metricKey)
        let batchLimit = 400

        while true {
            let predicate = HKQuery.predicateForSamples(withStart: workingStart, end: nil, options: .strictStartDate)
            let group = DispatchGroup()
            group.enter()
            var batchSamples: [HKQuantitySample] = []
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: batchLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                batchSamples = (results as? [HKQuantitySample]) ?? []
                group.leave()
            }
            healthStore.execute(query)
            group.wait()

            if batchSamples.isEmpty { break }

            let now = Date()
            let payloads: [HealthMetricRecordPayload] = batchSamples.map { s in
                HealthMetricRecordPayload(
                    hkUUID: s.uuid,
                    typeIdentifier: identifier.rawValue,
                    sampleKind: .quantity,
                    value: s.quantity.doubleValue(for: unit),
                    unitString: unit.unitString,
                    startDate: s.startDate,
                    endDate: s.endDate,
                    sourceBundleId: s.sourceRevision.source.bundleIdentifier,
                    deviceName: s.device?.name,
                    uploadedAt: now
                )
            }

            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                defer { sem.signal() }
                do {
                    try await CloudKitManager.shared.upsertHealthMetricRecords(payloads)
                    self.advanceWatermark(metricKey: metricKey, samples: batchSamples)
                } catch {
                    CloudKitManager.shared.reportHealthSyncError(error.localizedDescription)
                }
            }
            sem.wait()

            if batchSamples.count < batchLimit { break }
            if let last = batchSamples.last {
                workingStart = last.startDate.addingTimeInterval(0.001)
            } else {
                break
            }
        }
    }

    private func syncSleepBatches(healthStore: HKHealthStore) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        guard authorizedToRead(healthStore: healthStore, type: sleepType) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let metricKey = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        var workingStart = watermarkStart(for: metricKey)
        let batchLimit = 400

        while true {
            let predicate = HKQuery.predicateForSamples(withStart: workingStart, end: nil, options: .strictStartDate)
            let group = DispatchGroup()
            group.enter()
            var batchSamples: [HKCategorySample] = []
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: batchLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                batchSamples = (results as? [HKCategorySample]) ?? []
                group.leave()
            }
            healthStore.execute(query)
            group.wait()

            if batchSamples.isEmpty { break }

            let now = Date()
            let payloads: [HealthMetricRecordPayload] = batchSamples.map { s in
                HealthMetricRecordPayload(
                    hkUUID: s.uuid,
                    typeIdentifier: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                    sampleKind: .category,
                    value: Double(s.value),
                    unitString: "hk_category",
                    startDate: s.startDate,
                    endDate: s.endDate,
                    sourceBundleId: s.sourceRevision.source.bundleIdentifier,
                    deviceName: s.device?.name,
                    uploadedAt: now
                )
            }

            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                defer { sem.signal() }
                do {
                    try await CloudKitManager.shared.upsertHealthMetricRecords(payloads)
                    self.advanceWatermark(metricKey: metricKey, samples: batchSamples)
                } catch {
                    CloudKitManager.shared.reportHealthSyncError(error.localizedDescription)
                }
            }
            sem.wait()

            if batchSamples.count < batchLimit { break }
            if let last = batchSamples.last {
                workingStart = last.startDate.addingTimeInterval(0.001)
            } else {
                break
            }
        }
    }
}
#endif
