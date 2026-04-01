//
//  WorkoutLiveActivityAttributes.swift
//  Nutrivance
//
//  Attributes for Workout Live Activity - used by main app
//

import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = WorkoutActivityState
    
    let workoutType: String
    let activityIcon: String
    let startTime: Date
    let targetMinutes: Int?
    let userInitials: String
    let maxHeartRate: Int?
}

struct WorkoutActivityState: Codable, Hashable {
    var elapsedSeconds: Int
    var currentHeartRate: Int
    var totalCalories: Double
    var totalDistanceKilometers: Double
    var currentPaceMinutesPerKm: Double?
    var elevationGainMeters: Int
    var currentHeartRateZone: Int?
    var activePhaseTitle: String?
    
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
}
