import Foundation

/// Timer sync protocol for keeping watch and phone workouts in sync
/// Both devices run independent timers locally, but sync their elapsed time
/// at critical state changes (start, pause, resume, split, end)
struct WorkoutTimerSync: Codable {
    /// The elapsed time on the source device (watch) at sync point
    let elapsedTime: TimeInterval
    /// The UTC timestamp when this sync was created
    let syncTimestamp: Date
    /// The workout state when sync occurred
    let workoutState: String // "running", "paused", "ended"
    /// Split count at sync point (for split matching)
    let splitCount: Int
    
    /// Calculate the current elapsed time on receiving device
    /// by adding local elapsed time since sync was received
    func getCurrentElapsedTime(localElapsedSinceSyncPoint: TimeInterval) -> TimeInterval {
        return elapsedTime + localElapsedSinceSyncPoint
    }
    
    /// Test if sync happened recently (within 2 seconds)
    func isRecent() -> Bool {
        return Date().timeIntervalSince(syncTimestamp) < 2.0
    }
}

/// Communication keys for timer sync messages
struct WorkoutTimerSyncKeys {
    static let messageKey = "workout_timer_sync"
    static let elapsedTimeKey = "elapsed_time"
    static let syncTimestampKey = "sync_timestamp"
    static let workoutStateKey = "state"
    static let splitCountKey = "split_count"
}

/// Represents different states during pre-workout countdown
enum PreWorkoutCountdownState: Int {
    case waitingForConnection = 0
    case connected = 1
    case counting = 2
    case ready = 3
    case cancelled = 4
    
    var displayText: String {
        switch self {
        case .waitingForConnection:
            return "Waiting for Watch..."
        case .connected:
            return "Watch Connected"
        case .counting:
            return "Starting..."
        case .ready:
            return "Ready"
        case .cancelled:
            return "Cancelled"
        }
    }
}
