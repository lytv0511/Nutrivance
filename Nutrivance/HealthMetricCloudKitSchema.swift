import CloudKit
import Foundation

// MARK: - CloudKit schema (Private DB)

/// Mirrors `HKQuantitySample` / basic `HKCategorySample` fields for cross-device sync.
/// Deploy `HealthMetricRecord` in CloudKit Dashboard with indexed `startDate` + `hkUUID` for efficient queries.
enum HealthMetricCloudSchema {
    static let recordType = "HealthMetricRecord"

    enum FieldKey {
        static let hkUUID = "hkUUID"
        static let typeIdentifier = "typeIdentifier"
        static let sampleKind = "sampleKind"
        static let value = "value"
        static let unitString = "unitString"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let sourceBundleId = "sourceBundleId"
        static let deviceName = "deviceName"
        /// When this row was written to CloudKit (client clock); useful for delta ordering.
        static let uploadedAt = "uploadedAt"
    }

    enum SampleKind: String {
        case quantity
        case category
    }
}

/// Transport model (HealthKit-free) for macOS / ML pipelines — maps 1:1 to `CKRecord` fields.
struct HealthMetricRecordPayload: Sendable, Equatable {
    var hkUUID: UUID
    var typeIdentifier: String
    var sampleKind: HealthMetricCloudSchema.SampleKind
    var value: Double
    var unitString: String
    var startDate: Date
    var endDate: Date
    var sourceBundleId: String?
    var deviceName: String?
    var uploadedAt: Date

    /// Row-oriented layout friendly to `MLMultiArray` / MLX tensors (time, value, type hash optional).
    static func mlFeatureRow(startDate: Date, value: Double, typeToken: Double) -> [Float] {
        [Float(startDate.timeIntervalSince1970), Float(value), Float(typeToken)]
    }
}

extension HealthMetricRecordPayload {
    /// Stable `CKRecord.ID`: one CloudKit row per HealthKit object UUID (idempotent upserts).
    func cloudKitRecordID(zoneID: CKRecordZone.ID = .default) -> CKRecord.ID {
        CKRecord.ID(recordName: hkUUID.uuidString, zoneID: zoneID)
    }

    func makeCKRecord(zoneID: CKRecordZone.ID = .default) -> CKRecord {
        let id = cloudKitRecordID(zoneID: zoneID)
        let record = CKRecord(recordType: HealthMetricCloudSchema.recordType, recordID: id)
        record[HealthMetricCloudSchema.FieldKey.hkUUID] = hkUUID.uuidString as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.typeIdentifier] = typeIdentifier as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.sampleKind] = sampleKind.rawValue as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.value] = value as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.unitString] = unitString as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.startDate] = startDate as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.endDate] = endDate as CKRecordValue
        record[HealthMetricCloudSchema.FieldKey.uploadedAt] = uploadedAt as CKRecordValue
        if let sourceBundleId { record[HealthMetricCloudSchema.FieldKey.sourceBundleId] = sourceBundleId as CKRecordValue }
        if let deviceName { record[HealthMetricCloudSchema.FieldKey.deviceName] = deviceName as CKRecordValue }
        return record
    }

    init?(ckRecord: CKRecord) {
        guard ckRecord.recordType == HealthMetricCloudSchema.recordType,
              let uuidStr = ckRecord[HealthMetricCloudSchema.FieldKey.hkUUID] as? String,
              let uuid = UUID(uuidString: uuidStr),
              let typeId = ckRecord[HealthMetricCloudSchema.FieldKey.typeIdentifier] as? String,
              let kindStr = ckRecord[HealthMetricCloudSchema.FieldKey.sampleKind] as? String,
              let kind = HealthMetricCloudSchema.SampleKind(rawValue: kindStr),
              let val = ckRecord[HealthMetricCloudSchema.FieldKey.value] as? Double,
              let unit = ckRecord[HealthMetricCloudSchema.FieldKey.unitString] as? String,
              let start = ckRecord[HealthMetricCloudSchema.FieldKey.startDate] as? Date,
              let end = ckRecord[HealthMetricCloudSchema.FieldKey.endDate] as? Date else { return nil }

        hkUUID = uuid
        typeIdentifier = typeId
        sampleKind = kind
        value = val
        unitString = unit
        startDate = start
        endDate = end
        sourceBundleId = ckRecord[HealthMetricCloudSchema.FieldKey.sourceBundleId] as? String
        deviceName = ckRecord[HealthMetricCloudSchema.FieldKey.deviceName] as? String
        uploadedAt = (ckRecord[HealthMetricCloudSchema.FieldKey.uploadedAt] as? Date) ?? Date.distantPast
    }
}

// MARK: - Full engine blobs (CKAsset) for cross-device graphs

/// Full-resolution HRV SDNN samples (ms) for Stress / charts on Mac Catalyst (not the KVS-trimmed snapshot).
struct EngineHRVSamplesBlob: Codable, Sendable {
    var updatedAt: Date
    var samples: [EngineHRVSamplePoint]
}

struct EngineHRVSamplePoint: Codable, Sendable, Hashable {
    var date: Date
    var value: Double
}

/// Per-segment sleep analysis intervals from HealthKit (category `sleepAnalysis` value = `HKCategoryValueSleepAnalysis` raw).
struct EngineSleepTimelineBlob: Codable, Sendable {
    var updatedAt: Date
    var segments: [EngineSleepTimelineSegment]
}

struct EngineSleepTimelineSegment: Codable, Sendable, Hashable {
    var start: Date
    var end: Date
    /// Same integer values used by `SleepStage` in `SleepView` / HealthKit (e.g. awake=2, core=3, …).
    var stageValue: Int
}

// MARK: - Sleep UI handoff (iOS → Mac Catalyst)

/// Per-stage summary for collapsed Sleep Stages header (block counts + HR/RR ranges).
struct EngineSleepStageAggregateHandoff: Codable, Sendable {
    var stageValue: Int
    var blockCount: Int
    var hrMin: Int?
    var hrMax: Int?
    var hrAvg: Double?
    var rrMin: Int?
    var rrMax: Int?
    var rrAvg: Double?
}

/// One consolidated segment with optional vitals (matches `SleepStageData` after merge).
struct EngineSleepSegmentVitalsHandoff: Codable, Sendable {
    var start: Date
    var end: Date
    var stageValue: Int
    var averageHeartRate: Int?
    var averageRespiratoryRate: Int?
}

struct EngineHeartRateDipHandoff: Codable, Sendable {
    var daytimeAvgBpm: Double?
    var nocturnalAvgBpm: Double?
    var dipPercent: Double?
    var bandRaw: String
    var daytimeSampleCount: Int
    var nocturnalSampleCount: Int
}

struct EngineBedtimeNightHandoff: Codable, Sendable {
    var nightStart: Date
    var firstAsleepTime: Date
    var minutesFromNightAnchor: Double
    var deviationMinutes: Double
}

struct EngineOvernightVitalHandoff: Codable, Sendable {
    var id: String
    var title: String
    var systemImage: String
    var normalityPosition: Double
    var isOutlier: Bool
    var valueLabel: String
}

/// One wake-day row: segments + vitals + dip + overnight strip for that night.
struct EngineSleepNightUIPackage: Codable, Sendable {
    /// `startOfDay` for the calendar day that labels this sleep row (nightStart + ~12h).
    var wakeDayStart: Date
    var stageAggregates: [EngineSleepStageAggregateHandoff]
    var segments: [EngineSleepSegmentVitalsHandoff]
    var heartRateDip: EngineHeartRateDipHandoff?
    var overnightVitals: [EngineOvernightVitalHandoff]
}

/// Full sleep screen handoff built on iPhone/iPad after HealthKit load.
struct EngineSleepUIMetricsBlob: Codable, Sendable {
    var updatedAt: Date
    var nights: [EngineSleepNightUIPackage]
    var bedtimeNights: [EngineBedtimeNightHandoff]
}

/// Large JSON payloads that exceed iCloud KVS limits or need full time series (not `cloudTrimmedSnapshot`).
/// In CloudKit Dashboard, create **EngineSyncBlob** with `updatedAt` (Date/Time) and `payload` (Asset).
enum NutrivanceEngineSyncSchema {
    static let recordType = "EngineSyncBlob"

    enum FieldKey {
        static let updatedAt = "updatedAt"
        static let payload = "payload"
    }

    enum RecordName {
        /// Full `HealthStateEngine.MetricsSnapshot` JSON (daily HRV, RHR, sleep series, vitals, scores, …).
        static let metricsSnapshot = "NUTRIVANCE_ENGINE_METRICS_SNAPSHOT_V1"
        /// `PersistedWorkoutAnalyticsEntry` array JSON (strain / workout charts, HRR series, HR timelines).
        static let workoutAnalytics = "NUTRIVANCE_ENGINE_WORKOUT_ANALYTICS_V1"
        /// All HRV SDNN samples (trimmed on device before upload) for Catalyst Stress charts.
        static let hrvSamplesDetailed = "NUTRIVANCE_ENGINE_HRV_SAMPLES_DETAILED_V1"
        /// Sleep stage intervals for Catalyst Sleep timeline charts (not daily aggregates only).
        static let sleepTimelineDetailed = "NUTRIVANCE_ENGINE_SLEEP_TIMELINE_V1"
        /// Consolidated sleep rows, per-stage HR/RR, HR dip, bedtime series, overnight vitals (Mac parity).
        static let sleepUIMetricsDetailed = "NUTRIVANCE_ENGINE_SLEEP_UI_METRICS_V1"
    }
}
