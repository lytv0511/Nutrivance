import Foundation
import SwiftData

/// Local cache of `HealthMetricRecord` rows for offline use and on-device ML (Core ML / MLX).
/// `value` + `startDate` + a type token flatten cleanly into `MLMultiArray` batches via `mlFeatureFloats`.
@Model
final class MacCachedHealthMetric {
    @Attribute(.unique) var hkUUID: String
    var typeIdentifier: String
    var sampleKind: String
    var value: Double
    var unitString: String
    var startDate: Date
    var endDate: Date
    var sourceBundleId: String?
    var deviceName: String?
    var uploadedAt: Date

    init(
        hkUUID: String,
        typeIdentifier: String,
        sampleKind: String,
        value: Double,
        unitString: String,
        startDate: Date,
        endDate: Date,
        sourceBundleId: String?,
        deviceName: String?,
        uploadedAt: Date
    ) {
        self.hkUUID = hkUUID
        self.typeIdentifier = typeIdentifier
        self.sampleKind = sampleKind
        self.value = value
        self.unitString = unitString
        self.startDate = startDate
        self.endDate = endDate
        self.sourceBundleId = sourceBundleId
        self.deviceName = deviceName
        self.uploadedAt = uploadedAt
    }

    convenience init(payload: HealthMetricRecordPayload) {
        self.init(
            hkUUID: payload.hkUUID.uuidString,
            typeIdentifier: payload.typeIdentifier,
            sampleKind: payload.sampleKind.rawValue,
            value: payload.value,
            unitString: payload.unitString,
            startDate: payload.startDate,
            endDate: payload.endDate,
            sourceBundleId: payload.sourceBundleId,
            deviceName: payload.deviceName,
            uploadedAt: payload.uploadedAt
        )
    }

    /// Single-row feature vector: [time, value, typeToken] as `Float` for tensor / `MLMultiArray` pipelines.
    func mlFeatureFloats(typeToken: Double) -> [Float] {
        HealthMetricRecordPayload.mlFeatureRow(startDate: startDate, value: value, typeToken: typeToken)
    }
}
