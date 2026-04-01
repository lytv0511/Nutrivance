import ActivityKit
import Foundation

// MARK: - Activity ID Storage

public struct WorkoutActivityStorage {
    private static let userDefaults = UserDefaults(suiteName: "group.com.nutrivance.workouts")
    private static let activeActivityKey = "activeWorkoutActivityId"
    private static let activeAttributesKey = "activeWorkoutAttributes"
    
    public static func getActiveActivityId() -> UUID? {
        guard let idString = userDefaults?.string(forKey: activeActivityKey) else {
            return nil
        }
        return UUID(uuidString: idString)
    }
    
    public static func setActiveActivityId(_ id: UUID?) {
        if let id = id {
            userDefaults?.set(id.uuidString, forKey: activeActivityKey)
        } else {
            userDefaults?.removeObject(forKey: activeActivityKey)
        }
    }
    
    public static func setActiveAttributes(_ attributes: WorkoutLiveActivityAttributes) {
        if let encoded = try? JSONEncoder().encode(attributes) {
            userDefaults?.set(encoded, forKey: activeAttributesKey)
        }
    }
    
    public static func getActiveAttributes() -> WorkoutLiveActivityAttributes? {
        guard let data = userDefaults?.data(forKey: activeAttributesKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkoutLiveActivityAttributes.self, from: data)
    }
    
    public static func clearActiveActivity() {
        userDefaults?.removeObject(forKey: activeActivityKey)
        userDefaults?.removeObject(forKey: activeAttributesKey)
    }
}

// MARK: - Activity Manager Helper

@MainActor
public class WorkoutLiveActivityManager {
    public static let shared = WorkoutLiveActivityManager()
    
    private var currentActivity: Activity<WorkoutLiveActivityAttributes>?
    
    private init() {
        // Recover active activity on manager initialization
        recoverActiveActivity()
    }
    
    /// Attempt to recover reference to an active Live Activity from the system
    private func recoverActiveActivity() {
        if let activeId = WorkoutActivityStorage.getActiveActivityId() {
            for activity in Activity<WorkoutLiveActivityAttributes>.activities {
                if activity.id == activeId {
                    self.currentActivity = activity
                    print("[WorkoutLiveActivityManager] Recovered active activity: \(activeId)")
                    return
                }
            }
            print("[WorkoutLiveActivityManager] Stored activity ID not found in system activities")
        }
    }
    
    public func startActivity(
        workoutType: String,
        activityIcon: String,
        targetMinutes: Int?,
        userInitials: String,
        maxHeartRate: Int?
    ) async throws -> Activity<WorkoutLiveActivityAttributes> {
        await endActivity()
        
        let attributes = WorkoutLiveActivityAttributes(
            workoutType: workoutType,
            activityIcon: activityIcon,
            startTime: Date(),
            targetMinutes: targetMinutes,
            userInitials: userInitials,
            maxHeartRate: maxHeartRate
        )
        
        let initialState = WorkoutActivityState(
            elapsedSeconds: 0,
            currentHeartRate: 0,
            totalCalories: 0,
            totalDistanceKilometers: 0,
            currentPaceMinutesPerKm: nil,
            elevationGainMeters: 0,
            currentHeartRateZone: nil,
            activePhaseTitle: nil
        )
        
        let content = ActivityContent(
            state: initialState,
            staleDate: Date(timeIntervalSinceNow: 30)
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            
            self.currentActivity = activity
            WorkoutActivityStorage.setActiveActivityId(activity.id)
            WorkoutActivityStorage.setActiveAttributes(attributes)
            print("[WorkoutLiveActivityManager] Started live activity: \(activity.id)")
            
            return activity
        } catch {
            print("[WorkoutLiveActivityManager] Failed to request Live Activity: \(error)")
            throw error
        }
    }
    
    public func updateActivity(with state: WorkoutActivityState) async {
        // Try to recover if lost reference
        if currentActivity == nil {
            recoverActiveActivity()
        }
        
        guard let activity = currentActivity else {
            if let activeId = WorkoutActivityStorage.getActiveActivityId() {
                print("[WorkoutLiveActivityManager] Warning: Lost and could not recover activity \(activeId)")
            }
            return
        }
        
        let content = ActivityContent(
            state: state,
            staleDate: Date(timeIntervalSinceNow: 30)
        )
        
        await activity.update(content)
    }
    
    public func endActivity(finalState: WorkoutActivityState? = nil) async {
        // Try to recover if lost reference
        if currentActivity == nil {
            recoverActiveActivity()
        }
        
        guard let activity = currentActivity else { return }
        
        let finalContent = ActivityContent(
            state: finalState ?? WorkoutActivityState(
                elapsedSeconds: 0,
                currentHeartRate: 0,
                totalCalories: 0,
                totalDistanceKilometers: 0,
                currentPaceMinutesPerKm: nil,
                elevationGainMeters: 0,
                currentHeartRateZone: nil,
                activePhaseTitle: nil
            ),
            staleDate: nil
        )
        
        await activity.end(finalContent, dismissalPolicy: .after(minutes: 30))
        
        currentActivity = nil
        WorkoutActivityStorage.clearActiveActivity()
        print("[WorkoutLiveActivityManager] Ended live activity")
    }
    
    public var isActivityActive: Bool {
        if currentActivity != nil {
            return true
        }
        // Check if there's a stored ID we can recover
        if WorkoutActivityStorage.getActiveActivityId() != nil {
            recoverActiveActivity()
            return currentActivity != nil
        }
        return false
    }
}
