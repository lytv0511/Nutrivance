import SwiftUI
import WorkoutKit
import HealthKit

struct WatchScheduledWorkoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scheduledWorkouts: [ScheduledWorkoutPlan] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var workoutToDelete: ScheduledWorkoutPlan?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.orange)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadScheduledWorkouts() }
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
            } else if scheduledWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("No Scheduled Workouts")
                        .font(.caption)
                    Text("Workouts scheduled in Apple Workout will appear here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(scheduledWorkouts.enumerated()), id: \.offset) { index, workout in
                            WatchScheduledWorkoutRow(
                                workout: workout,
                                dateFormatter: dateFormatter,
                                onDelete: {
                                    workoutToDelete = workout
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !scheduledWorkouts.isEmpty {
                    Button(action: {
                        Task {
                            await WorkoutScheduler.shared.removeAllWorkouts()
                            await loadScheduledWorkouts()
                        }
                    }) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .task {
            await loadScheduledWorkouts()
        }
        .confirmationDialog(
            "Delete Workout?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let workout = workoutToDelete {
                    Task {
                        await deleteWorkout(workout)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove this workout from Apple Workout?")
        }
    }

    private func loadScheduledWorkouts() async {
        isLoading = true
        errorMessage = nil

        guard WorkoutScheduler.isSupported else {
            errorMessage = "Not supported"
            isLoading = false
            return
        }

        let authStatus = await WorkoutScheduler.shared.requestAuthorization()
        guard authStatus == .authorized else {
            errorMessage = "Permission denied"
            isLoading = false
            return
        }

        scheduledWorkouts = await WorkoutScheduler.shared.scheduledWorkouts
        isLoading = false
    }

    private func deleteWorkout(_ workout: ScheduledWorkoutPlan) async {
        let dateComponents: DateComponents
        if let date = workout.date as? DateComponents {
            dateComponents = date
        } else if let date = workout.date as? Date {
            dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        } else {
            return
        }
        
        await WorkoutScheduler.shared.remove(workout.plan, at: dateComponents)
        await loadScheduledWorkouts()
    }
}

private struct WatchScheduledWorkoutRow: View {
    let workout: ScheduledWorkoutPlan
    let dateFormatter: DateFormatter
    let onDelete: () -> Void

    private var workoutTitle: String {
        if case .custom(let customWorkout) = workout.plan.workout {
            return customWorkout.displayName ?? "Custom Workout"
        }
        return "Scheduled Workout"
    }

    private var workoutDate: Date? {
        if let date = workout.date as? Date {
            return date
        } else if let components = workout.date as? DateComponents {
            return Calendar.current.date(from: components)
        }
        return nil
    }

    private var formattedDate: String {
        guard let date = workoutDate else { return "Unknown" }
        return dateFormatter.string(from: date)
    }

    private var activityType: String {
        if case .custom(let customWorkout) = workout.plan.workout {
            return activityName(for: customWorkout.activity)
        }
        return "Workout"
    }
    
    private func activityName(for activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running:
            return "Run"
        case .walking:
            return "Walk"
        case .cycling:
            return "Cycle"
        case .swimming:
            return "Swim"
        case .hiking:
            return "Hike"
        case .yoga:
            return "Yoga"
        case .functionalStrengthTraining:
            return "Strength"
        case .crossTraining:
            return "Cross"
        case .pilates:
            return "Pilates"
        case .boxing:
            return "Boxing"
        case .dance:
            return "Dance"
        case .elliptical:
            return "Elliptical"
        default:
            return "Workout"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(activityType)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
