import Foundation

enum PlatformContext {
    #if targetEnvironment(macCatalyst)
    static let isMacCatalyst = true
    #else
    static let isMacCatalyst = false
    #endif
}

struct CloudCacheHelper {
    private let cloudKey: String
    private let localKey: String
    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    
    init(cloudKey: String, localKey: String) {
        self.cloudKey = cloudKey
        self.localKey = localKey
    }
    
    func loadLocalFirst<T: Decodable>(_ type: T.Type) -> T? {
        if let localData = defaults.data(forKey: localKey),
           let decoded = try? JSONDecoder().decode(type, from: localData) {
            return decoded
        }
        return nil
    }
    
    func loadCloudAsync<T: Decodable>(_ type: T.Type) async -> T? {
        await withCheckedContinuation { continuation in
            // Try local first (no waiting)
            if let localData = self.defaults.data(forKey: self.localKey),
               let decoded = try? JSONDecoder().decode(type, from: localData) {
                continuation.resume(returning: decoded)
                
                // Sync cloud in background for next load
                DispatchQueue.global(qos: .background).async {
                    self.cloud.synchronize()
                }
                return
            }
            
            // Only block on cloud if local cache miss
            DispatchQueue.global(qos: .userInitiated).async {
                self.cloud.synchronize()
                if let cloudData = self.cloud.data(forKey: self.cloudKey),
                   let decoded = try? JSONDecoder().decode(type, from: cloudData) {
                    continuation.resume(returning: decoded)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func updateLocalCache<T: Encodable>(_ value: T) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        defaults.set(encoded, forKey: localKey)
    }
    
    func saveToCloud<T: Encodable>(_ value: T) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        defaults.set(encoded, forKey: localKey)
        cloud.set(encoded, forKey: cloudKey)
    }
}

extension UserDefaults {
    private static let catalystLaunchDataCacheKey = "nutrivance.catalyst.launchCache.v1"
    
    static func cacheLaunchDataIfMacCatalyst() {
        guard PlatformContext.isMacCatalyst else { return }
        
        // Defer to background to avoid blocking main thread on launch
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35) {
            let cloud = NSUbiquitousKeyValueStore.default
            cloud.synchronize()
            
            var allKeys: [String: Data] = [:]
            
            let keys = [
                "nutrivance.metrics.snapshot.v3",
                "nutrivance.catalystTrainingLoad.v2",
                "stage_quest_records_v1",
                "nutrivance.browserWorkspace.v1"
            ]
            
            for key in keys {
                if let data = cloud.data(forKey: key) {
                    allKeys[key] = data
                }
            }
            
            if !allKeys.isEmpty,
               let encoded = try? JSONEncoder().encode(allKeys) {
                UserDefaults.standard.set(encoded, forKey: catalystLaunchDataCacheKey)
            }
        }
    }
    
    static func preloadLaunchCacheForMacCatalyst() -> [String: Data] {
        guard PlatformContext.isMacCatalyst else { return [:] }
        
        if let cached = UserDefaults.standard.data(forKey: catalystLaunchDataCacheKey),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: cached) {
            return decoded
        }
        
        return [:]
    }
}

#if targetEnvironment(macCatalyst)

// MARK: - Mac Catalyst health sync (single orchestration path)

/// Mac Catalyst cannot read HealthKit; it consumes **one pipeline** driven by iPhone/iPad:
/// 1. **NSUbiquitousKeyValueStore** — small metric snapshots + training-load payload keys.
/// 2. **CloudKit `EngineSyncBlob`** — large handoffs (workout analytics bundle, detailed HRV/sleep series, metrics snapshot asset).
///
/// Previously, timers and notifications were spread across `HealthStateEngine`, `CatalystTrainingLoadSyncStore`,
/// and ad‑hoc `Task.sleep` chains. All Catalyst scheduling for this pipeline goes through this coordinator.
@MainActor
final class MacCatalystHealthSyncCoordinator {
    static let shared = MacCatalystHealthSyncCoordinator()

    private var deferredLaunchMergeTask: Task<Void, Never>?
    private var ubiquitousRemoteMergeTask: Task<Void, Never>?
    private var foregroundResumeTask: Task<Void, Never>?

    private init() {}

    func cancelAllPending() {
        deferredLaunchMergeTask?.cancel()
        deferredLaunchMergeTask = nil
        ubiquitousRemoteMergeTask?.cancel()
        ubiquitousRemoteMergeTask = nil
        foregroundResumeTask?.cancel()
        foregroundResumeTask = nil
    }

    /// Call from `deinit` or other nonisolated contexts; hops to the main actor.
    nonisolated static func cancelPendingTasksSchedulingOnMainActor() {
        Task { @MainActor in
            MacCatalystHealthSyncCoordinator.shared.cancelAllPending()
        }
    }

    /// Post–first-frame merge: KVS + disk hydrate already ran; pull CloudKit blobs after a short deferral so launch stays responsive.
    func scheduleDeferredLaunchMerge(engine: HealthStateEngine) {
        deferredLaunchMergeTask?.cancel()
        deferredLaunchMergeTask = Task { [weak engine] in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard let engine, !Task.isCancelled else { return }
            await engine.macCatalystRunAggregatedCloudMerge(userInitiatedRefresh: false)
            engine.macCatalystAfterRemoteMergeBookkeeping()
        }
    }

    /// Coalesced handler for `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.
    func handleUbiquitousRemoteChange(engine: HealthStateEngine) {
        ubiquitousRemoteMergeTask?.cancel()
        ubiquitousRemoteMergeTask = Task { [weak engine] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let engine, !Task.isCancelled, engine.macCatalystIsAppActive else { return }
            // Training-load series travel via KVS — refresh before CloudKit so strain charts react quickly.
            CatalystTrainingLoadSyncStore.shared.pullLatestFromICloudForCoordinator()
            await engine.macCatalystRunAggregatedCloudMerge(userInitiatedRefresh: false)
            engine.macCatalystAfterRemoteMergeBookkeeping()
        }
    }

    /// User brought the Mac window forward — treat as an explicit refresh (bypasses automatic CloudKit spacing).
    func handleSceneBecameActive(engine: HealthStateEngine) {
        foregroundResumeTask?.cancel()
        foregroundResumeTask = Task { [weak engine] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let engine, !Task.isCancelled, engine.macCatalystIsAppActive else { return }
            CatalystTrainingLoadSyncStore.shared.pullLatestFromICloudForCoordinator()
            engine.refreshStartupMetrics(force: true)
            engine.macCatalystScheduleStartupWorkoutCoverageSync()
        }
    }
}

#endif