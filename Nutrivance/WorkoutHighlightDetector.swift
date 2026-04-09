import HealthKit

class WorkoutHighlightDetector {

    static func detectHighlights(workouts: [HKWorkout]) -> [WorkoutInsight] {
        guard !workouts.isEmpty else { return [] }

        let longestDuration = workouts.map { $0.duration }.max() ?? 0

        return workouts.map { workout in
            let durationMinutes = workout.duration / 60

            let calories = workout.totalEnergyBurned?
                .doubleValue(for: .kilocalorie()) ?? 0

            let activity = workout.workoutActivityType.name

            let intensity = intensityLabel(duration: durationMinutes, calories: calories)

            var highlight: String?

            if workout.duration == longestDuration {
                highlight = "your longest \(activity) session in the past month"
            }

            return WorkoutInsight(
                date: workout.startDate,
                activity: activity,
                durationMinutes: durationMinutes,
                calories: calories,
                intensity: intensity,
                highlight: highlight
            )
        }
    }

    static func intensityLabel(duration: Double, calories: Double) -> String {
        let score = calories / max(duration, 1)

        switch score {
        case 0..<3:
            return "light"
        case 3..<6:
            return "moderate"
        case 6..<9:
            return "intense"
        default:
            return "very intense"
        }
    }
}
