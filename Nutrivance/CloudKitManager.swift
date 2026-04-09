import CloudKit
import Foundation

/// All CloudKit traffic uses **private database** scope only.
@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    /// Use the same iCloud container on iOS and macOS (see entitlements: `iCloud.None.Nutrivance`).
    private let container = CKContainer.default()
    private let database: CKDatabase

    @Published private(set) var lastHealthSyncError: String?

    init() {
        self.database = container.privateCloudDatabase
    }

    /// Allows `HealthKitCloudSyncProducer` (and tests) to surface upload failures without exposing the `private(set)` publisher.
    func reportHealthSyncError(_ message: String?) {
        lastHealthSyncError = message
    }

    // MARK: - Legacy nutrients (iOS app only)

    #if os(iOS)
    func saveNutrientsToCloud(_ nutrients: [NutrientData], completion: @escaping (Bool) -> Void) {
        let records = nutrients.map { nutrient -> CKRecord in
            let record = CKRecord(recordType: "Nutrient")
            record.setValue(nutrient.name, forKey: "name")
            record.setValue(nutrient.value, forKey: "value")
            record.setValue(nutrient.unit, forKey: "unit")
            return record
        }

        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    completion(true)
                }
            case .failure:
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
        database.add(operation)
    }
    #endif

    // MARK: - Health metrics (producer + consumer)

    /// Upserts by `hkUUID` record name — safe to retry; no duplicate rows.
    func upsertHealthMetricRecords(_ payloads: [HealthMetricRecordPayload]) async throws {
        guard !payloads.isEmpty else { return }
        let records = payloads.map { $0.makeCKRecord() }
        try await modifyRecordsSaving(records)
    }

    private func modifyRecordsSaving(_ records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .allKeys
            op.qualityOfService = .utility
            op.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }
            self.database.add(op)
        }
    }

    /// Delta pull: first page uses `uploadedAfter` (nil = full history); follow-up pages pass `cursor` only.
    func fetchHealthMetricDelta(
        uploadedAfter anchor: Date?,
        cursor: CKQueryOperation.Cursor?,
        limit: Int = 250
    ) async throws -> (payloads: [HealthMetricRecordPayload], nextCursor: CKQueryOperation.Cursor?) {
        try await container.accountStatus()

        let operation: CKQueryOperation
        if let cursor {
            operation = CKQueryOperation(cursor: cursor)
        } else {
            let predicate: NSPredicate
            if let anchor {
                predicate = NSPredicate(
                    format: "%K > %@",
                    HealthMetricCloudSchema.FieldKey.uploadedAt,
                    anchor as NSDate
                )
            } else {
                predicate = NSPredicate(value: true)
            }
            let query = CKQuery(recordType: HealthMetricCloudSchema.recordType, predicate: predicate)
            query.sortDescriptors = [
                NSSortDescriptor(key: HealthMetricCloudSchema.FieldKey.uploadedAt, ascending: true),
            ]
            operation = CKQueryOperation(query: query)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var collected: [HealthMetricRecordPayload] = []
            operation.resultsLimit = limit
            operation.recordMatchedBlock = { _, recordResult in
                switch recordResult {
                case .success(let record):
                    if let payload = HealthMetricRecordPayload(ckRecord: record) {
                        collected.append(payload)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let optCursor):
                    continuation.resume(returning: (collected, optCursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            self.database.add(operation)
        }
    }

    /// Registers a silent push subscription for new/updated health metric rows (macOS consumer).
    func ensureHealthMetricPushSubscription(subscriptionID: String = "HealthMetricRecord.all") async throws {
        let subscription = CKQuerySubscription(
            recordType: HealthMetricCloudSchema.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = false
        subscription.notificationInfo = info

        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    func deleteHealthMetricSubscription(subscriptionID: String = "HealthMetricRecord.all") async throws {
        _ = try await database.modifySubscriptions(saving: [], deleting: [subscriptionID])
    }

    func accountCanUseCloudKit() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    // MARK: - Engine sync blobs (full metrics + workout time series for Mac Catalyst)

    /// Uploads JSON as a **CKAsset** (private DB). Fixed record names → upsert.
    func uploadEngineSyncBlob(recordName: String, data: Data) async throws {
        guard !data.isEmpty else { return }
        _ = try await container.accountStatus()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nutrivance-ck-\(UUID().uuidString).json")
        try data.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }

        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: NutrivanceEngineSyncSchema.recordType, recordID: recordID)
        record[NutrivanceEngineSyncSchema.FieldKey.updatedAt] = Date() as CKRecordValue
        record[NutrivanceEngineSyncSchema.FieldKey.payload] = CKAsset(fileURL: temp)

        try await modifyRecordsSaving([record])
    }

    /// Downloads blob JSON if the record exists.
    func fetchEngineSyncBlob(recordName: String) async -> (updatedAt: Date, data: Data)? {
        do {
            _ = try await container.accountStatus()
        } catch {
            return nil
        }
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let record = try await database.record(for: recordID)
            guard let asset = record[NutrivanceEngineSyncSchema.FieldKey.payload] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let data = try? Data(contentsOf: fileURL),
                  !data.isEmpty,
                  let updatedAt = record[NutrivanceEngineSyncSchema.FieldKey.updatedAt] as? Date else {
                return nil
            }
            return (updatedAt, data)
        } catch let error as CKError where error.code == CKError.Code.unknownItem {
            return nil
        } catch {
            return nil
        }
    }
}

protocol CloudKitRecord {
    static var recordType: String { get }
    var record: CKRecord { get }
    init(record: CKRecord) throws
}
