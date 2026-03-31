import ActivityKit
import Foundation

// MARK: - Workout Live Activity Attributes

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    /// Static content that doesn't change during the activity
    public typealias ContentState = WorkoutActivityState
    
    // Static: Workout context
    let workoutType: String
    let activityIcon: String  // SF Symbol name
    let startTime: Date
    let targetMinutes: Int?
    let userInitials: String
    
    // Static: Zone thresholds for color coding
    let maxHeartRate: Int?
    
    // MARK: - Preview Context
    
    func preview(state: WorkoutActivityState, kind: ActivityPreviewViewKind?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activityIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(workoutType)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DURATION")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(state.formattedElapsedTime)
                        .font(.caption.bold().monospacedDigit())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("HR")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(state.currentHeartRate)")
                        .font(.caption.bold())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("KCAL")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(Int(state.totalCalories))")
                        .font(.caption.bold())
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.7))
    }
}

// MARK: - Workout Activity State

struct WorkoutActivityState: Codable, Hashable {
    // Real-time metrics
    var elapsedSeconds: Int
    var currentHeartRate: Int
    var totalCalories: Double
    var totalDistanceKilometers: Double
    var currentPaceMinutesPerKm: Double?
    var elevationGainMeters: Int
    
    // Zone data for visualization
    var currentHeartRateZone: Int?  // 1-5
    var activePhaseTitle: String?
    
    // Format helpers
    var formattedElapsedTime: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedDistance: String {
        String(format: "%.1f km", totalDistanceKilometers)
    }
    
    var formattedPace: String? {
        guard let pace = currentPaceMinutesPerKm, pace > 0 else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace.truncatingRemainder(dividingBy: 1)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case elapsedSeconds
        case currentHeartRate
        case totalCalories
        case totalDistanceKilometers
        case currentPaceMinutesPerKm
        case elevationGainMeters
        case currentHeartRateZone
        case activePhaseTitle
    }
}

// MARK: - Activity ID Storage

public struct WorkoutActivityStorage {
    private static let userDefaults = UserDefaults(suiteName: "group.com.nutrivance.workouts")
    private static let activeActivityKey = "activeWorkoutActivityId"
    private static let activeAttributesKey = "activeWorkoutAttributes"
    
    /// Retrieve stored activity ID
    public static func getActiveActivityId() -> UUID? {
        guard let idString = userDefaults?.string(forKey: activeActivityKey) else {
            return nil
        }
        return UUID(uuidString: idString)
    }
    
    /// Store activity ID
    public static func setActiveActivityId(_ id: UUID?) {
        if let id = id {
            userDefaults?.set(id.uuidString, forKey: activeActivityKey)
        } else {
            userDefaults?.removeObject(forKey: activeActivityKey)
        }
    }
    
    /// Store serialized attributes for recovery
    public static func setActiveAttributes(_ attributes: WorkoutLiveActivityAttributes) {
        if let encoded = try? JSONEncoder().encode(attributes) {
            userDefaults?.set(encoded, forKey: activeAttributesKey)
        }
    }
    
    /// Retrieve stored attributes
    public static func getActiveAttributes() -> WorkoutLiveActivityAttributes? {
        guard let data = userDefaults?.data(forKey: activeAttributesKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkoutLiveActivityAttributes.self, from: data)
    }
    
    /// Clear stored activity data
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
    
    private init() {}
    
    /// Request a new Live Activity for an active workout
    public func startActivity(
        workoutType: String,
        activityIcon: String,
        targetMinutes: Int?,
        userInitials: String,
        maxHeartRate: Int?
    ) async throws -> Activity<WorkoutLiveActivityAttributes> {
        // End any existing activity
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
            
            return activity
        } catch {
            print("Failed to request Live Activity: \(error)")
            throw error
        }
    }
    
    /// Update the current Live Activity with new metrics
    public func updateActivity(with state: WorkoutActivityState) async {
        guard let activity = currentActivity else {
            // Try to recover from storage
            if let id = WorkoutActivityStorage.getActiveActivityId() {
                // In production, you'd retrieve the activity by ID
                // This is a limitation of ActivityKit - activities aren't directly retrievable by ID
                print("Warning: Lost reference to active activity")
            }
            return
        }
        
        let content = ActivityContent(
            state: state,
            staleDate: Date(timeIntervalSinceNow: 30)
        )
        
        await activity.update(content)
    }
    
    /// End the current Live Activity and show a summary
    public func endActivity(
        finalState: WorkoutActivityState? = nil
    ) async {
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
    }
    
    /// Get current activity (mainly for reference)
    public var isActivityActive: Bool {
        currentActivity != nil
    }
}
