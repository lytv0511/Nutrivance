import Foundation
import HealthKit
#if canImport(UIKit)
import UIKit
#endif

enum WorkoutBlockStatus: String, Codable {
    case completed
    case partial
    case skipped
    case notStarted
}

struct WorkoutBlockResult: Identifiable, Codable {
    let id: UUID
    let blockIndex: Int
    let title: String
    let roleRawValue: String
    let goalRawValue: String
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let plannedValue: Double
    let actualValue: Double
    let unit: String
    let status: WorkoutBlockStatus
    let completionPercentage: Double
    let repeatLabel: String

    var summary: String {
        switch status {
        case .completed:
            return "Completed \(Int(completionPercentage))%"
        case .partial:
            return "Partial \(Int(completionPercentage))%"
        case .skipped:
            return "Skipped"
        case .notStarted:
            return "Not started"
        }
    }

    var roleTitle: String {
        switch roleRawValue {
        case "warmup": return "Warmup"
        case "goal": return "Goal"
        case "steady": return "Steady"
        case "work": return "Work"
        case "recovery": return "Recovery"
        case "cooldown": return "Cooldown"
        case "foundation": return "Foundation"
        default: return "Stage"
        }
    }

    var goalTitle: String {
        switch goalRawValue {
        case "distance": return "Distance"
        case "energy": return "Energy"
        case "heartRateZone": return "HR Zone"
        case "power": return "Power"
        case "pace": return "Pace"
        case "speed": return "Speed"
        case "cadence": return "Cadence"
        case "time": return "Time"
        default: return "Open"
        }
    }
}

struct WorkoutBlockAnalysisResult: Identifiable, Codable {
    let id: UUID
    let workoutID: UUID
    let workoutDate: Date
    let workoutTypeRawValue: UInt
    let totalPlannedDuration: TimeInterval
    let totalActualDuration: TimeInterval
    let blockResults: [WorkoutBlockResult]
    let overallCompletionPercentage: Double

    var workoutType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: workoutTypeRawValue) ?? .other
    }

    var completedBlocks: Int {
        blockResults.filter { $0.status == .completed }.count
    }

    var partialBlocks: Int {
        blockResults.filter { $0.status == .partial }.count
    }

    var skippedBlocks: Int {
        blockResults.filter { $0.status == .skipped }.count
    }

    var formattedPlannedDuration: String {
        let minutes = Int(totalPlannedDuration / 60)
        return "\(minutes) min"
    }

    var formattedActualDuration: String {
        let minutes = Int(totalActualDuration / 60)
        return "\(minutes) min"
    }
}

@MainActor
final class WorkoutBlockAnalyzer: ObservableObject {
    static let shared = WorkoutBlockAnalyzer()

    @Published private(set) var currentAnalysis: WorkoutBlockAnalysisResult?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var errorMessage: String?

    private let skipThreshold: TimeInterval = 2.0

    private init() {}

    func analyzeWorkout(
        _ workout: HKWorkout,
        plannedBlocks: [PlannedWorkoutBlock]
    ) async -> WorkoutBlockAnalysisResult? {
        isAnalyzing = true
        errorMessage = nil

        defer { isAnalyzing = false }

        guard !plannedBlocks.isEmpty else {
            errorMessage = "No planned blocks provided"
            return nil
        }

        let activities = workout.workoutActivities
        var blockResults: [WorkoutBlockResult] = []

        let flattenedBlocks = flattenBlocksWithRepeats(plannedBlocks)

        for (index, block) in flattenedBlocks.enumerated() {
            let result: WorkoutBlockResult

            if index < activities.count {
                let activity = activities[index]
                result = analyzeBlock(
                    block: block,
                    activity: activity,
                    index: index
                )
            } else {
                result = WorkoutBlockResult(
                    id: UUID(),
                    blockIndex: index,
                    title: block.title,
                    roleRawValue: block.roleRawValue,
                    goalRawValue: block.goalRawValue,
                    plannedDuration: block.plannedDurationSeconds,
                    actualDuration: 0,
                    plannedValue: block.plannedValue,
                    actualValue: 0,
                    unit: block.unit,
                    status: .notStarted,
                    completionPercentage: 0,
                    repeatLabel: block.repeatLabel
                )
            }

            blockResults.append(result)
        }

        let totalPlanned = flattenedBlocks.reduce(0) { $0 + $1.plannedDurationSeconds }
        let totalActual = blockResults.reduce(0) { $0 + $1.actualDuration }
        let overallPercentage = totalPlanned > 0 ? (totalActual / totalPlanned) * 100 : 0

        let analysis = WorkoutBlockAnalysisResult(
            id: UUID(),
            workoutID: workout.uuid,
            workoutDate: workout.startDate,
            workoutTypeRawValue: workout.workoutActivityType.rawValue,
            totalPlannedDuration: totalPlanned,
            totalActualDuration: totalActual,
            blockResults: blockResults,
            overallCompletionPercentage: min(100, max(0, overallPercentage))
        )

        currentAnalysis = analysis
        return analysis
    }

    func analyzeWorkoutWithSegments(
        workout: HKWorkout,
        plannedBlocks: [PlannedWorkoutBlock],
        segments: [(start: Date, end: Date, type: HKWorkoutActivityType)]
    ) async -> WorkoutBlockAnalysisResult? {
        isAnalyzing = true
        errorMessage = nil

        defer { isAnalyzing = false }

        guard !plannedBlocks.isEmpty else {
            errorMessage = "No planned blocks provided"
            return nil
        }

        var blockResults: [WorkoutBlockResult] = []
        let flattenedBlocks = flattenBlocksWithRepeats(plannedBlocks)

        for (index, block) in flattenedBlocks.enumerated() {
            let result: WorkoutBlockResult

            if index < segments.count {
                let segment = segments[index]
                let actualDuration = segment.end.timeIntervalSince(segment.start)
                result = analyzeBlockWithDuration(
                    block: block,
                    actualDuration: actualDuration,
                    index: index
                )
            } else {
                result = WorkoutBlockResult(
                    id: UUID(),
                    blockIndex: index,
                    title: block.title,
                    roleRawValue: block.roleRawValue,
                    goalRawValue: block.goalRawValue,
                    plannedDuration: block.plannedDurationSeconds,
                    actualDuration: 0,
                    plannedValue: block.plannedValue,
                    actualValue: 0,
                    unit: block.unit,
                    status: .notStarted,
                    completionPercentage: 0,
                    repeatLabel: block.repeatLabel
                )
            }

            blockResults.append(result)
        }

        let totalPlanned = flattenedBlocks.reduce(0) { $0 + $1.plannedDurationSeconds }
        let totalActual = blockResults.reduce(0) { $0 + $1.actualDuration }
        let overallPercentage = totalPlanned > 0 ? (totalActual / totalPlanned) * 100 : 0

        let analysis = WorkoutBlockAnalysisResult(
            id: UUID(),
            workoutID: workout.uuid,
            workoutDate: workout.startDate,
            workoutTypeRawValue: workout.workoutActivityType.rawValue,
            totalPlannedDuration: totalPlanned,
            totalActualDuration: totalActual,
            blockResults: blockResults,
            overallCompletionPercentage: min(100, max(0, overallPercentage))
        )

        currentAnalysis = analysis
        return analysis
    }

    private func flattenBlocksWithRepeats(_ blocks: [PlannedWorkoutBlock]) -> [PlannedWorkoutBlock] {
        var flattened: [PlannedWorkoutBlock] = []

        for block in blocks {
            if block.repeats > 1 {
                for i in 0..<block.repeats {
                    let repeatedBlock = PlannedWorkoutBlock(
                        id: UUID(),
                        title: block.title,
                        roleRawValue: block.roleRawValue,
                        goalRawValue: block.goalRawValue,
                        plannedDurationSeconds: block.plannedDurationSeconds,
                        repeats: 1,
                        plannedValue: block.plannedValue,
                        unit: block.unit,
                        repeatLabel: "\(i + 1)/\(block.repeats)"
                    )
                    flattened.append(repeatedBlock)
                }
            } else {
                flattened.append(block)
            }
        }

        return flattened
    }

    private func analyzeBlock(
        block: PlannedWorkoutBlock,
        activity: HKWorkoutActivity,
        index: Int
    ) -> WorkoutBlockResult {
        return analyzeBlockWithDuration(
            block: block,
            actualDuration: activity.duration,
            index: index
        )
    }

    private func analyzeBlockWithDuration(
        block: PlannedWorkoutBlock,
        actualDuration: TimeInterval,
        index: Int
    ) -> WorkoutBlockResult {
        let plannedDuration = block.plannedDurationSeconds

        let status: WorkoutBlockStatus
        let completionPercentage: Double

        if actualDuration < skipThreshold {
            status = .skipped
            completionPercentage = 0
        } else {
            let durationRatio = actualDuration / plannedDuration
            completionPercentage = min(100, durationRatio * 100)

            if completionPercentage >= 95 {
                status = .completed
            } else if completionPercentage >= 20 {
                status = .partial
            } else {
                status = .skipped
            }
        }

        return WorkoutBlockResult(
            id: UUID(),
            blockIndex: index,
            title: block.title,
            roleRawValue: block.roleRawValue,
            goalRawValue: block.goalRawValue,
            plannedDuration: plannedDuration,
            actualDuration: actualDuration,
            plannedValue: block.plannedValue,
            actualValue: 0,
            unit: block.unit,
            status: status,
            completionPercentage: completionPercentage,
            repeatLabel: block.repeatLabel
        )
    }
}

struct PlannedWorkoutBlock: Identifiable, Codable {
    let id: UUID
    let title: String
    let roleRawValue: String
    let goalRawValue: String
    let plannedDurationSeconds: TimeInterval
    let repeats: Int
    let plannedValue: Double
    let unit: String
    let repeatLabel: String

    init(
        id: UUID = UUID(),
        title: String,
        roleRawValue: String,
        goalRawValue: String,
        plannedDurationSeconds: TimeInterval,
        repeats: Int = 1,
        plannedValue: Double = 0,
        unit: String = "",
        repeatLabel: String = ""
    ) {
        self.id = id
        self.title = title
        self.roleRawValue = roleRawValue
        self.goalRawValue = goalRawValue
        self.plannedDurationSeconds = plannedDurationSeconds
        self.repeats = repeats
        self.plannedValue = plannedValue
        self.unit = unit
        self.repeatLabel = repeatLabel
    }

    var roleTitle: String {
        switch roleRawValue {
        case "warmup": return "Warmup"
        case "goal": return "Goal"
        case "steady": return "Steady"
        case "work": return "Work"
        case "recovery": return "Recovery"
        case "cooldown": return "Cooldown"
        case "foundation": return "Foundation"
        default: return "Stage"
        }
    }

    var goalTitle: String {
        switch goalRawValue {
        case "distance": return "Distance"
        case "energy": return "Energy"
        case "heartRateZone": return "HR Zone"
        case "power": return "Power"
        case "pace": return "Pace"
        case "speed": return "Speed"
        case "cadence": return "Cadence"
        case "time": return "Time"
        default: return "Open"
        }
    }

}
