import Foundation

// MARK: - Personalized MET Profile

enum METEstimationMethod: String, Codable, CaseIterable {
    case userProvided = "User Provided"
    case historicalMax = "Historical Max"
    case formulaBased = "Formula Based"
    case agedAdjusted = "Age Adjusted"
    
    var description: String {
        switch self {
        case .userProvided:
            return "You manually entered your max METs"
        case .historicalMax:
            return "Derived from your peak workout METs (90-day history)"
        case .formulaBased:
            return "Estimated from fitness formula"
        case .agedAdjusted:
            return "Age-predicted estimate (Karvonen-based)"
        }
    }
}

struct PersonalizedMETProfile: Codable, Equatable {
    var maxMETs: Double = 15.0                          // Athlete's max MET capacity
    var beneficialMETThresholdPercentage: Double = 0.50 // % of max to count as beneficial (e.g., 50%)
    var estimationMethod: METEstimationMethod = .userProvided
    var historicalMaxMETsObserved: Double?              // Highest MET achieved in tracked workouts
    var calibrationDate: Date?                          // When max METs was last determined
    var historicalMaxHeartRate: Double?                 // Peak HR observed in workouts (for calibration)
    
    // Validation helpers
    var isValid: Bool {
        maxMETs > 0 && maxMETs <= 30 &&
        beneficialMETThresholdPercentage > 0 &&
        beneficialMETThresholdPercentage <= 1.0
    }
    
    mutating func validate() {
        maxMETs = max(1, min(30, maxMETs))
        beneficialMETThresholdPercentage = max(0.1, min(1.0, beneficialMETThresholdPercentage))
    }
}

// MARK: - Daily Personalized MET Snapshot

struct DailyPersonalizedMETSnapshot: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var totalMETs: Double = 0                    // All METs for the day
    var beneficialMETs: Double = 0               // METs above threshold only
    var thresholdMETs: Double = 0                // Daily threshold value (% of max)
    var averageEffortProportion: Double = 0      // Avg % of max during workouts
    var peakEffortProportion: Double = 0         // Peak % of max during day
    var workoutCount: Int = 0
    var zoneDistribution: [PersonalizedMETZone: Double] = [:] // Time (minutes) in each zone
    var recoveryScore: Double? = nil             // Optional link to daily recovery score
    var totalDurationMinutes: Double = 0         // Total active time
    var timestamp: Date = Date()
    
    // Computed properties
    var beneficialMETsPercentage: Double {
        guard totalMETs > 0 else { return 0 }
        return (beneficialMETs / totalMETs) * 100
    }
    
    var totalZoneMinutes: Double {
        zoneDistribution.values.reduce(0, +)
    }
    
    var isHighLoad: Bool {
        beneficialMETs > 0 && totalMETs > 0
    }
    
    // Date normalization
    private static let calendar = Calendar.current
    
    mutating func normalizeDateToToday() {
        let normalized = Self.calendar.startOfDay(for: date)
        date = normalized
    }
}

// MARK: - Per-Workout Personalized MET Data

struct WorkoutPersonalizedMET: Codable, Identifiable {
    var id = UUID()
    var workoutID: UUID? = nil
    var workoutDate: Date
    var workoutType: String? = nil              // e.g., "Cycling", "Running"
    var duration: TimeInterval = 0              // In seconds
    var averageHeartRate: Double = 0
    var peakHeartRate: Double = 0
    var totalMETs: Double = 0                   // Total METs for workout
    var beneficialMETs: Double = 0              // METs above threshold
    var effortProportion: Double = 0            // Current MET / Max MET (0-1)
    var zone: PersonalizedMETZone = .light
    var restingHeartRate: Double = 0            // RHR at time of workout
    var timestamp: Date = Date()
    
    // Computed properties
    var durationMinutes: Double {
        duration / 60.0
    }
    
    var durationHours: Double {
        duration / 3600.0
    }
    
    var effortPercentage: Double {
        effortProportion * 100
    }
}

// MARK: - Personalized MET Zones

enum PersonalizedMETZone: String, CaseIterable, Codable {
    case light = "Light"           // 0-25% of max
    case moderate = "Moderate"     // 25-50% of max
    case vigorous = "Vigorous"     // 50-75% of max
    case hard = "Hard"             // 75-90% of max
    case veryHard = "Very Hard"    // 90-100% of max
    
    var color: String {
        switch self {
        case .light:
            return "green"
        case .moderate:
            return "yellow"
        case .vigorous:
            return "orange"
        case .hard:
            return "red"
        case .veryHard:
            return "purple"
        }
    }
    
    var description: String {
        switch self {
        case .light:
            return "Light Activity — Easy movement, low intensity"
        case .moderate:
            return "Moderate — Conversation possible, steady effort"
        case .vigorous:
            return "Vigorous — Elevated effort, harder to talk"
        case .hard:
            return "Hard — Very challenging, minimal conversation"
        case .veryHard:
            return "Very Hard — Max or near-max effort"
        }
    }
    
    static func fromEffortProportion(_ proportion: Double) -> PersonalizedMETZone {
        switch proportion {
        case 0..<0.25:
            return .light
        case 0.25..<0.50:
            return .moderate
        case 0.50..<0.75:
            return .vigorous
        case 0.75..<0.90:
            return .hard
        default:
            return .veryHard
        }
    }
    
    var rangeBounds: (min: Double, max: Double) {
        switch self {
        case .light:
            return (0, 0.25)
        case .moderate:
            return (0.25, 0.50)
        case .vigorous:
            return (0.50, 0.75)
        case .hard:
            return (0.75, 0.90)
        case .veryHard:
            return (0.90, 1.0)
        }
    }
}

// MARK: - MET Calculation Constants

struct METCalculationConstants {
    // Standard rest metabolic rate
    static let restMetabolicRate: Double = 3.5  // ml/kg/min (used for VO2 conversion, but we focus on effort ratio)
    
    // Passive daily activity baseline
    static let passiveMETsPerHour: Double = 1.2  // METs for light daily activity (walking, ADLs)
    static let passiveWakingHours: Double = 16    // Hours of light daily activity
    
    // Recovery integration multipliers
    static let highLoadRecoveryPenalty: Double = 0.90      // Recovery *= 0.90 if METs > 1.5x max
    static let lowLoadRecoveryBonus: Double = 5.0          // Recovery += 5 if METs < 0.3x max
    
    static let metStressReadinessPenalty: Double = 0.2     // Readiness penalty multiplier per stress index unit
    
    // Adaptive threshold adjustment ranges
    static let lowRecoveryThresholdAdjustment: Double = 0.40   // Lower threshold if recovery < 50%
    static let highRecoveryThresholdAdjustment: Double = 0.60  // Raise threshold if recovery > 75%
    static let normalRecoveryThreshold: Double = 0.50          // Normal threshold (50% of max)
}
