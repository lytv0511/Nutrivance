import Foundation

public struct WorkoutInsight: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let activity: String
    let durationMinutes: Double
    let calories: Double
    let intensity: String
    let highlight: String?
}

public func describeWorkout(_ workout: WorkoutInsight) -> String {
    let minutes = Int(workout.durationMinutes)
    var text = "\(workout.intensity.capitalized) \(workout.activity) session of \(minutes) minutes"
    
    if let highlight = workout.highlight {
        text += ", which was \(highlight)"
    }
    
    text += "."
    
    return text
}
