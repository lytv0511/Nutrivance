//
//  WorkoutMetricsSnapshot.swift
//  Nutrivance for Apple Watch Watch App
//
//  Watch-side metrics snapshot for iPhone synchronization
//

import Foundation
import HealthKit

/// Keys for workout metrics messages sent from watch to iPhone
struct WorkoutMetricsSnapshotKeys {
    static let messageKey = "workoutMetricsSnapshot"
    
    static let elapsedTimeKey = "elapsedTime"
    static let stateKey = "state"
    static let heartRateKey = "heartRate"
    static let totalCaloriesKey = "totalCalories"
    static let totalDistanceKey = "totalDistance"
    static let currentSpeedKey = "currentSpeed"
    static let currentPaceKey = "currentPace"
    static let elevationGainKey = "elevationGain"
    static let activePhaseKey = "activePhase"
    static let splitCountKey = "splitCount"
    static let timestampKey = "timestamp"
}

/// Snapshot of workout metrics from the watch to send to iPhone
struct WorkoutMetricsSnapshot: Codable {
    let elapsedTime: TimeInterval
    let state: String  // "running", "paused", etc.
    let heartRate: Int?
    let totalCalories: Double
    let totalDistance: Double  // in meters
    let currentSpeed: Double?  // in m/s
    let currentPace: Double?   // in minutes per km
    let elevationGain: Double  // in meters
    let activePhase: String?
    let splitCount: Int
    let timestamp: Date  // when this snapshot was created
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            WorkoutMetricsSnapshotKeys.messageKey: true,
            WorkoutMetricsSnapshotKeys.elapsedTimeKey: elapsedTime,
            WorkoutMetricsSnapshotKeys.stateKey: state,
            WorkoutMetricsSnapshotKeys.totalCaloriesKey: totalCalories,
            WorkoutMetricsSnapshotKeys.totalDistanceKey: totalDistance,
            WorkoutMetricsSnapshotKeys.elevationGainKey: elevationGain,
            WorkoutMetricsSnapshotKeys.splitCountKey: splitCount,
            WorkoutMetricsSnapshotKeys.timestampKey: timestamp.timeIntervalSince1970
        ]
        
        if let hr = heartRate {
            dict[WorkoutMetricsSnapshotKeys.heartRateKey] = hr
        }
        if let speed = currentSpeed {
            dict[WorkoutMetricsSnapshotKeys.currentSpeedKey] = speed
        }
        if let pace = currentPace {
            dict[WorkoutMetricsSnapshotKeys.currentPaceKey] = pace
        }
        if let phase = activePhase {
            dict[WorkoutMetricsSnapshotKeys.activePhaseKey] = phase
        }
        
        return dict
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> WorkoutMetricsSnapshot? {
        guard let elapsedTime = dict[WorkoutMetricsSnapshotKeys.elapsedTimeKey] as? TimeInterval,
              let state = dict[WorkoutMetricsSnapshotKeys.stateKey] as? String,
              let totalCalories = dict[WorkoutMetricsSnapshotKeys.totalCaloriesKey] as? Double,
              let totalDistance = dict[WorkoutMetricsSnapshotKeys.totalDistanceKey] as? Double,
              let elevationGain = dict[WorkoutMetricsSnapshotKeys.elevationGainKey] as? Double,
              let splitCount = dict[WorkoutMetricsSnapshotKeys.splitCountKey] as? Int,
              let timestampInterval = dict[WorkoutMetricsSnapshotKeys.timestampKey] as? TimeInterval else {
            return nil
        }
        
        let heartRate = dict[WorkoutMetricsSnapshotKeys.heartRateKey] as? Int
        let currentSpeed = dict[WorkoutMetricsSnapshotKeys.currentSpeedKey] as? Double
        let currentPace = dict[WorkoutMetricsSnapshotKeys.currentPaceKey] as? Double
        let activePhase = dict[WorkoutMetricsSnapshotKeys.activePhaseKey] as? String
        
        return WorkoutMetricsSnapshot(
            elapsedTime: elapsedTime,
            state: state,
            heartRate: heartRate,
            totalCalories: totalCalories,
            totalDistance: totalDistance,
            currentSpeed: currentSpeed,
            currentPace: currentPace,
            elevationGain: elevationGain,
            activePhase: activePhase,
            splitCount: splitCount,
            timestamp: Date(timeIntervalSince1970: timestampInterval)
        )
    }
}
