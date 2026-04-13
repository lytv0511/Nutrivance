import Foundation
import Combine

/// Serialized on iPhone/iPad and read on Mac Catalyst (limited HealthKit) so Training Load matches the handheld app.
struct CatalystTrainingLoadPayload: Codable, Equatable {
    static let iCloudKey = "nutrivance.catalystTrainingLoad.v2"
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    var generatedAt: Date
    /// Daily strain / load series (same window as export).
    var strainSnapshots: [CatalystStrainDayDTO]
    /// Workouts card (acute/chronic / ACWR) daily series.
    var contributionSnapshots: [CatalystContributionDayDTO]
    /// All-sports MET totals by day (sport filter on Mac may not match phone).
    var metByDayStartOfDay: [TimeInterval: Double]
    var vo2ByDayStartOfDay: [TimeInterval: Double]
    /// Training schedule: minutes trained per calendar day.
    var trainingMinutesByDayStartOfDay: [TimeInterval: Double]
    /// Session counts per calendar day (optional for payloads written before this field existed).
    var trainingSessionsByDayStartOfDay: [TimeInterval: Int]? = nil
}

struct CatalystStrainDayDTO: Codable, Equatable {
    var dayStart: TimeInterval
    var sessionLoad: Double
    var totalDailyLoad: Double
    var acuteLoad: Double
    var chronicLoad: Double
    var acwr: Double
    var strainScore: Double
    var workoutCount: Int
    var activeDaysLast28: Int
    var daysSinceLastWorkout: Int?
}

struct CatalystContributionDayDTO: Codable, Equatable {
    var dayStart: TimeInterval
    var sessionLoad: Double
    var totalDailyLoad: Double
    var acuteLoad: Double
    var acuteTotal: Double
    var chronicLoad: Double
    var chronicTotal: Double
    var acwr: Double
    var workoutCount: Int
    var activeDaysLast28: Int
    var daysSinceLastWorkout: Int?
}

@MainActor
final class CatalystTrainingLoadSyncStore: ObservableObject {
    static let shared = CatalystTrainingLoadSyncStore()

    @Published private(set) var payload: CatalystTrainingLoadPayload?

    private let cloud = NSUbiquitousKeyValueStore.default
    private var cancellable: AnyCancellable?
    private let localCacheKey = "nutrivance.catalystTrainingLoad.v2.local"
    private var isLoadingFromCloud = false

    private init() {
        // Load from local cache immediately (no blocking)
        loadFromLocalCache()
        
        // Schedule cloud sync for background (non-blocking)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncCloudInBackground()
        }
        
        // Listen for external changes (e.g., iPhone updates)
        cancellable = NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncCloudInBackground()
            }
    }

    private func loadFromLocalCache() {
        #if targetEnvironment(macCatalyst)
        guard let localData = UserDefaults.standard.data(forKey: localCacheKey),
              let decoded = try? CatalystTrainingLoadPayload.decoder.decode(CatalystTrainingLoadPayload.self, from: localData) else {
            return
        }
        payload = decoded
        #endif
    }

    private func syncCloudInBackground() {
        #if targetEnvironment(macCatalyst)
        guard !isLoadingFromCloud else { return }
        isLoadingFromCloud = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { self?.isLoadingFromCloud = false }
            
            self?.cloud.synchronize()
            
            guard let cloudData = self?.cloud.data(forKey: CatalystTrainingLoadPayload.iCloudKey),
                  let decoded = try? CatalystTrainingLoadPayload.decoder.decode(CatalystTrainingLoadPayload.self, from: cloudData) else {
                return
            }
            
            // Update local cache
            if let encoded = try? CatalystTrainingLoadPayload.encoder.encode(decoded) {
                UserDefaults.standard.set(encoded, forKey: self?.localCacheKey ?? "")
            }
            
            // Update payload on main thread
            DispatchQueue.main.async {
                if self?.payload != decoded {
                    self?.payload = decoded
                }
            }
        }
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    func commitPayload(_ newValue: CatalystTrainingLoadPayload) {
        guard let data = try? CatalystTrainingLoadPayload.encoder.encode(newValue) else { return }
        cloud.set(data, forKey: CatalystTrainingLoadPayload.iCloudKey)
        
        // Sync in background, don't block
        DispatchQueue.global(qos: .background).async {
            self.cloud.synchronize()
        }
    }
    #endif
}
