import SwiftData
import SwiftUI

struct MacRootContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MacCachedHealthMetric.startDate, order: .reverse) private var metrics: [MacCachedHealthMetric]
    @EnvironmentObject private var sync: MacHealthMetricsDataController

    var body: some View {
        NavigationSplitView {
            List {
                Section("CloudKit bridge") {
                    Toggle("Mock data only (no iCloud)", isOn: $sync.useMockDataOnly)
                    Button("Pull delta from iCloud") {
                        Task { await sync.pullDeltaFromCloudKit() }
                    }
                    .disabled(sync.useMockDataOnly || sync.isPulling)
                    Button("Register push subscription") {
                        Task { await sync.registerPushSubscription() }
                    }
                    .disabled(sync.useMockDataOnly)
                    Button("Inject mock timeline") {
                        do {
                            try MockHealthMetricInjector.injectDemoTimeline(into: sync)
                        } catch {
                            sync.reportPullSummary("Mock inject failed: \(error.localizedDescription)")
                        }
                    }
                }
                Section("Status") {
                    Text(sync.lastPullSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 280)
        } detail: {
            Table(Array(metrics.prefix(500))) {
                TableColumn("Start") { row in
                    Text(row.startDate.formatted(date: .abbreviated, time: .shortened))
                }
                .width(min: 120, ideal: 140)
                TableColumn("Type") { row in
                    Text(row.typeIdentifier)
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 200)
                TableColumn("Value") { row in
                    Text(String(format: "%.1f %@", row.value, row.unitString))
                }
                TableColumn("Kind") { row in
                    Text(row.sampleKind)
                }
                .width(80)
            }
            .navigationTitle("Health metrics cache (macOS)")
        }
    }
}
