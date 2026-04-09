import CloudKit
import Foundation
import SwiftData
import SwiftUI

/// macOS **consumer**: pulls deltas from the private CloudKit database, persists into SwiftData, optional push subscription.
@MainActor
final class MacHealthMetricsDataController: ObservableObject {
    static let shared = MacHealthMetricsDataController()

    private let uploadedAnchorKey = "MacHealthMetricsLastUploadedAtAnchor"

    @Published private(set) var lastPullSummary: String = ""
    @Published private(set) var isPulling = false
    @Published var useMockDataOnly = false

    let modelContainer: ModelContainer

    private init() {
        let boot = Self.makeModelContainer()
        modelContainer = boot.container
        if !boot.userMessage.isEmpty {
            lastPullSummary = boot.userMessage
        }
    }

    var mainContext: ModelContext {
        modelContainer.mainContext
    }

    func reportPullSummary(_ text: String) {
        lastPullSummary = text
    }

    /// Highest `uploadedAt` we've successfully imported (delta cursor).
    private var uploadedAnchor: Date? {
        get { UserDefaults.standard.object(forKey: uploadedAnchorKey) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: uploadedAnchorKey)
            }
        }
    }

    private static var persistentStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("NutrivanceMac", isDirectory: true)
        return folder.appendingPathComponent("HealthMetrics.store")
    }

    private static func ensureStoreParentExists(url: URL) {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    /// Avoids `loadIssueModelContainer` from implicit CloudKit wiring and sandbox path issues; recovers from a bad on-disk store.
    private static func makeModelContainer() -> (container: ModelContainer, userMessage: String) {
        let schema = Schema([MacCachedHealthMetric.self])

        func diskConfiguration() -> ModelConfiguration {
            let url = persistentStoreURL
            ensureStoreParentExists(url: url)
            return ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        }

        func openDisk() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: diskConfiguration())
        }

        do {
            return (try openDisk(), "")
        } catch {
            let url = persistentStoreURL
            let dir = url.deletingLastPathComponent()
            let base = url.lastPathComponent
            // Remove incompatible / corrupted store and typical SQLite journal sidecars.
            let related = [
                url,
                dir.appendingPathComponent(base + "-wal"),
                dir.appendingPathComponent(base + "-shm"),
            ]
            for f in related {
                try? FileManager.default.removeItem(at: f)
            }
            ensureStoreParentExists(url: url)
            do {
                return (try openDisk(), "Previous local cache was reset (store could not be opened).")
            } catch {
                let mem = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                do {
                    let c = try ModelContainer(for: schema, configurations: mem)
                    let msg = "Using in-memory cache only (on-disk SwiftData store failed: \(error.localizedDescription))."
                    return (c, msg)
                } catch {
                    fatalError("SwiftData could not start: \(error)")
                }
            }
        }
    }

    func ingestPayloads(_ payloads: [HealthMetricRecordPayload], context: ModelContext) throws {
        for p in payloads {
            let id = p.hkUUID.uuidString
            let fd = FetchDescriptor<MacCachedHealthMetric>(predicate: #Predicate { $0.hkUUID == id })
            if let existing = try context.fetch(fd).first {
                existing.typeIdentifier = p.typeIdentifier
                existing.sampleKind = p.sampleKind.rawValue
                existing.value = p.value
                existing.unitString = p.unitString
                existing.startDate = p.startDate
                existing.endDate = p.endDate
                existing.sourceBundleId = p.sourceBundleId
                existing.deviceName = p.deviceName
                existing.uploadedAt = p.uploadedAt
            } else {
                context.insert(MacCachedHealthMetric(payload: p))
            }
        }
        try context.save()
        if let maxUp = payloads.map(\.uploadedAt).max() {
            uploadedAnchor = max(uploadedAnchor ?? .distantPast, maxUp)
        }
    }

    /// Paginated delta sync using `CKQueryOperation` cursor + `uploadedAt` anchor.
    func pullDeltaFromCloudKit() async {
        guard !useMockDataOnly else { return }
        let ok = await CloudKitManager.shared.accountCanUseCloudKit()
        guard ok else {
            lastPullSummary = "iCloud / CloudKit not available for this Apple ID."
            return
        }

        isPulling = true
        defer { isPulling = false }

        var cursor: CKQueryOperation.Cursor?
        var total = 0
        let anchor = uploadedAnchor

        do {
            repeat {
                let (payloads, next) = try await CloudKitManager.shared.fetchHealthMetricDelta(
                    uploadedAfter: cursor == nil ? anchor : nil,
                    cursor: cursor,
                    limit: 250
                )
                if !payloads.isEmpty {
                    try ingestPayloads(payloads, context: mainContext)
                    total += payloads.count
                }
                cursor = next
            } while cursor != nil

            lastPullSummary = "Imported \(total) metric row(s) (delta)."
        } catch {
            lastPullSummary = "CloudKit pull failed: \(error.localizedDescription)"
        }
    }

    func registerPushSubscription() async {
        guard !useMockDataOnly else { return }
        do {
            try await CloudKitManager.shared.ensureHealthMetricPushSubscription()
            lastPullSummary = "Subscribed to silent CloudKit pushes."
        } catch {
            lastPullSummary = "Subscription error: \(error.localizedDescription)"
        }
    }
}
