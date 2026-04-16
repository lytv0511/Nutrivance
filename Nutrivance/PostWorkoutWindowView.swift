import SwiftUI
import HealthKit

private let cardBg = Color.gray.opacity(0.1)

struct PostWorkoutWindowView: View {
    @State private var selectedAnalysis: WorkoutBlockAnalysisResult?
    @State private var isShowingWorkoutPicker = false
    @State private var isLoading = false
    @StateObject private var analyzer = WorkoutBlockAnalyzer.shared
    @StateObject private var healthKitManager = HealthKitManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let analysis = selectedAnalysis {
                        analysisView(analysis)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Blocks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingWorkoutPicker = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $isShowingWorkoutPicker) {
                WorkoutPickerSheet { workout in
                    Task {
                        await analyzeWorkout(workout)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Workout Analysis")
                .font(.title2.weight(.semibold))

            Text("Analyze your workout blocks to see how well you completed each stage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isShowingWorkoutPicker = true
            } label: {
                Label("Select Workout", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func analysisView(_ analysis: WorkoutBlockAnalysisResult) -> some View {
        VStack(spacing: 20) {
            summaryCard(analysis)
            blocksList(analysis)
        }
    }

    @ViewBuilder
    private func summaryCard(_ analysis: WorkoutBlockAnalysisResult) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workoutTypeDisplayName(analysis.workoutType))
                        .font(.headline)
                    Text(analysis.workoutDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(analysis.overallCompletionPercentage))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(completionColor(for: analysis.overallCompletionPercentage))
            }

            HStack(spacing: 20) {
                statItem(value: "\(analysis.completedBlocks)", label: "Completed", color: .green)
                statItem(value: "\(analysis.partialBlocks)", label: "Partial", color: .orange)
                statItem(value: "\(analysis.skippedBlocks)", label: "Skipped", color: .red)
            }

            HStack {
                Text("Planned: \(analysis.formattedPlannedDuration)")
                Spacer()
                Text("Actual: \(analysis.formattedActualDuration)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func blocksList(_ analysis: WorkoutBlockAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Block Details")
                .font(.headline)

            ForEach(analysis.blockResults) { block in
                blockRow(block)
            }
        }
    }

    @ViewBuilder
    private func blockRow(_ block: WorkoutBlockResult) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor(for: block.status))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(block.title)
                        .font(.subheadline.weight(.medium))
                    if !block.repeatLabel.isEmpty {
                        Text(block.repeatLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(block.roleTitle) • \(block.goalTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(block.completionPercentage))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor(for: block.status))

                Text(formatDuration(block.actualDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusColor(for status: WorkoutBlockStatus) -> Color {
        switch status {
        case .completed: return .green
        case .partial: return .orange
        case .skipped: return .red
        case .notStarted: return .gray
        }
    }

    private func completionColor(for percentage: Double) -> Color {
        if percentage >= 90 { return .green }
        if percentage >= 60 { return .orange }
        return .red
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func workoutTypeDisplayName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stairs"
        case .crossCountrySkiing: return "Cross Country"
        case .downhillSkiing: return "Skiing"
        case .snowboarding: return "Snowboarding"
        case .paddleSports: return "Paddling"
        case .sailing: return "Sailing"
        case .surfingSports: return "Surfing"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .dance: return "Dance"
        case .pilates: return "Pilates"
        case .coreTraining: return "Core"
        case .crossTraining: return "Cross Training"
        case .mixedCardio: return "Cardio"
        case .other: return "Workout"
        default: return "Workout"
        }
    }

    private func analyzeWorkout(_ workout: HKWorkout) async {
        let blocks = createSampleBlocks()
        let segments = extractSegments(from: workout)

        if let result = await analyzer.analyzeWorkoutWithSegments(
            workout: workout,
            plannedBlocks: blocks,
            segments: segments
        ) {
            selectedAnalysis = result
        }
    }

    private func createSampleBlocks() -> [PlannedWorkoutBlock] {
        [
            PlannedWorkoutBlock(
                title: "Warmup",
                roleRawValue: "warmup",
                goalRawValue: "time",
                plannedDurationSeconds: 300,
                repeats: 1,
                plannedValue: 5,
                unit: "min"
            ),
            PlannedWorkoutBlock(
                title: "Work Interval",
                roleRawValue: "work",
                goalRawValue: "pace",
                plannedDurationSeconds: 180,
                repeats: 4,
                plannedValue: 0,
                unit: "/km"
            ),
            PlannedWorkoutBlock(
                title: "Recovery",
                roleRawValue: "recovery",
                goalRawValue: "time",
                plannedDurationSeconds: 60,
                repeats: 4,
                plannedValue: 1,
                unit: "min"
            ),
            PlannedWorkoutBlock(
                title: "Cooldown",
                roleRawValue: "cooldown",
                goalRawValue: "time",
                plannedDurationSeconds: 300,
                repeats: 1,
                plannedValue: 5,
                unit: "min"
            )
        ]
    }

    private func extractSegments(from workout: HKWorkout) -> [(start: Date, end: Date, type: HKWorkoutActivityType)] {
        guard !workout.workoutActivities.isEmpty else {
            let endDate = workout.endDate ?? workout.startDate.addingTimeInterval(workout.duration)
            return [(workout.startDate, endDate, workout.workoutActivityType)]
        }

        return workout.workoutActivities.map { activity in
            let activityEnd = activity.endDate ?? activity.startDate.addingTimeInterval(activity.duration)
            return (activity.startDate, activityEnd, workout.workoutActivityType)
        }
    }
}

struct WorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [HKWorkout] = []
    @State private var isLoading = true
    @StateObject private var healthKitManager = HealthKitManager()

    let onSelect: (HKWorkout) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading workouts...")
                } else if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.run",
                        description: Text("Complete a workout with structured intervals to analyze.")
                    )
                } else {
                    List(workouts, id: \.uuid) { workout in
                        Button {
                            onSelect(workout)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(workoutTypeDisplayName(workout.workoutActivityType))
                                        .font(.headline)
                                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatDuration(workout.duration))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Select Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadWorkouts()
            }
        }
    }

    private func loadWorkouts() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            healthKitManager.fetchWorkouts(from: sevenDaysAgo, to: Date()) { [self] (fetchedWorkouts: [HKWorkout]) in
                workouts = fetchedWorkouts.filter { !$0.workoutActivities.isEmpty }
                isLoading = false
                continuation.resume()
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return "\(minutes) min"
    }

    private func workoutTypeDisplayName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stairs"
        case .crossCountrySkiing: return "Cross Country"
        case .downhillSkiing: return "Skiing"
        case .snowboarding: return "Snowboarding"
        case .paddleSports: return "Paddling"
        case .sailing: return "Sailing"
        case .surfingSports: return "Surfing"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .dance: return "Dance"
        case .pilates: return "Pilates"
        case .coreTraining: return "Core"
        case .crossTraining: return "Cross Training"
        case .mixedCardio: return "Cardio"
        case .other: return "Workout"
        default: return "Workout"
        }
    }
}

#Preview {
    PostWorkoutWindowView()
}
