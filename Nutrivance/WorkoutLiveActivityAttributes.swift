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
    var elapsedReferenceDate: Date
    var isPaused: Bool
    var currentHeartRate: Int
    var heartRateDisplay: String?
    var totalCalories: Double
    var caloriesDisplay: String?
    var totalDistanceKilometers: Double
    var distanceDisplay: String?
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
        if let distanceDisplay, !distanceDisplay.isEmpty {
            return distanceDisplay
        }
        String(format: "%.1f km", totalDistanceKilometers)
    }
    
    var formattedPace: String? {
        guard let pace = currentPaceMinutesPerKm, pace > 0 else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace.truncatingRemainder(dividingBy: 1)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedCalories: String {
        if let caloriesDisplay, !caloriesDisplay.isEmpty {
            return caloriesDisplay
        }
        return "\(Int(totalCalories.rounded())) CAL"
    }

    var formattedHeartRate: String {
        if let heartRateDisplay, !heartRateDisplay.isEmpty {
            return heartRateDisplay
        }
        return "\(currentHeartRate)"
    }
}
