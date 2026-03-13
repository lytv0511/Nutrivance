import Foundation

struct StrainModelContext: Codable {
    let strainScore: Int
    let acuteLoad: Double
    let chronicLoad: Double
    
    let hrvStatus: String
    let rhrStatus: String
    let sleepStatus: String
    
    let vo2Trend: String
    
    let workouts: [WorkoutInsight]
}
