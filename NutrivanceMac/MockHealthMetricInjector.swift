import Foundation
import SwiftData

/// Seeds SwiftData with synthetic `HealthMetricRecord`-shaped data so macOS UI and ML hooks work without an iPhone sync.
enum MockHealthMetricInjector {
    /// ~48 hours of fake heart-rate–like samples (HealthKit-style type id string).
    @MainActor
    static func injectDemoTimeline(into controller: MacHealthMetricsDataController) throws {
        let ctx = controller.mainContext
        let typeId = "HKQuantityTypeIdentifierHeartRate"
        let now = Date()
        var payloads: [HealthMetricRecordPayload] = []
        for i in 0..<48 {
            guard let t = Calendar.current.date(byAdding: .hour, value: -i, to: now) else { continue }
            let base = 120.0 + sin(Double(i) / 5.0) * 15.0
            payloads.append(
                HealthMetricRecordPayload(
                    hkUUID: UUID(),
                    typeIdentifier: typeId,
                    sampleKind: .quantity,
                    value: base,
                    unitString: "count/min",
                    startDate: t,
                    endDate: t.addingTimeInterval(60),
                    sourceBundleId: "com.apple.mock",
                    deviceName: "MockSensor",
                    uploadedAt: now
                )
            )
        }
        try controller.ingestPayloads(payloads, context: ctx)
    }

    /// Flattened `[Float]` matrix (rows: time, value, typeToken) for MLX / Core ML experiments.
    @MainActor
    static func demoMLFeatureArray(from controller: MacHealthMetricsDataController) throws -> [Float] {
        let ctx = controller.mainContext
        let fd = FetchDescriptor<MacCachedHealthMetric>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let rows = try ctx.fetch(fd)
        let token: Double = 1.0
        return rows.flatMap { $0.mlFeatureFloats(typeToken: token) }
    }
}
