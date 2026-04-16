import SwiftUI
import WorkoutKit
import HealthKit

#if canImport(WorkoutKit)

struct ScheduledWorkoutsManagerView: View {
    @Binding var isPresented: Bool
    @State private var scheduledWorkouts: [WorkoutKit.ScheduledWorkoutPlan] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var workoutToReschedule: WorkoutKit.ScheduledWorkoutPlan?
    @State private var showRescheduleSheet = false
    @State private var rescheduleDate = Date()
    @State private var showDeleteConfirmation = false
    @State private var workoutToDelete: WorkoutKit.ScheduledWorkoutPlan?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading...")
                    .tint(.orange)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadScheduledWorkouts() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
            } else if scheduledWorkouts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("No Scheduled Workouts")
                        .font(.headline)
                    Text("Workouts you schedule from the Program Builder will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(scheduledWorkouts, id: \.self) { workout in
                        ScheduledWorkoutRow(
                            workout: workout,
                            dateFormatter: dateFormatter,
                            onDelete: {
                                workoutToDelete = workout
                                showDeleteConfirmation = true
                            },
                            onReschedule: {
                                workoutToReschedule = workout
                                rescheduleDate = workoutDate(from: workout)
                                showRescheduleSheet = true
                            }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Scheduled Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !scheduledWorkouts.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await WorkoutScheduler.shared.removeAllWorkouts()
                                await loadScheduledWorkouts()
                            }
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    isPresented = false
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
            Text("This will remove the scheduled workout from Apple Workout.")
        }
        .sheet(isPresented: $showRescheduleSheet) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Reschedule to",
                        selection: $rescheduleDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .navigationTitle("Reschedule Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showRescheduleSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let workout = workoutToReschedule {
                                Task {
                                    await rescheduleWorkout(workout, to: rescheduleDate)
                                }
                            }
                            showRescheduleSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func loadScheduledWorkouts() async {
        isLoading = true
        errorMessage = nil

        guard WorkoutScheduler.isSupported else {
            errorMessage = "Workout scheduling is not supported on this device."
            isLoading = false
            return
        }

        let authStatus = await WorkoutScheduler.shared.requestAuthorization()
        guard authStatus == .authorized else {
            errorMessage = "Permission denied. Please enable in Settings > Nutrivance > Workout."
            isLoading = false
            return
        }

        scheduledWorkouts = await WorkoutScheduler.shared.scheduledWorkouts
        isLoading = false
    }

    private func deleteWorkout(_ workout: WorkoutKit.ScheduledWorkoutPlan) async {
        let dateComponents = workoutDateComponents(from: workout)
        await WorkoutScheduler.shared.remove(workout.plan, at: dateComponents)
        await loadScheduledWorkouts()
    }

    private func rescheduleWorkout(_ workout: WorkoutKit.ScheduledWorkoutPlan, to date: Date) async {
        let newComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let oldComponents = workoutDateComponents(from: workout)
        
        await WorkoutScheduler.shared.remove(workout.plan, at: oldComponents)
        await WorkoutScheduler.shared.schedule(workout.plan, at: newComponents)
        await loadScheduledWorkouts()
    }

    private func workoutDate(from workout: WorkoutKit.ScheduledWorkoutPlan) -> Date {
        if let date = workout.date as? Date {
            return date
        } else if let components = workout.date as? DateComponents {
            return Calendar.current.date(from: components) ?? Date()
        }
        return Date()
    }

    private func workoutDateComponents(from workout: WorkoutKit.ScheduledWorkoutPlan) -> DateComponents {
        if let components = workout.date as? DateComponents {
            return components
        } else if let date = workout.date as? Date {
            return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
        return DateComponents()
    }
}

private struct ScheduledWorkoutRow: View {
    let workout: WorkoutKit.ScheduledWorkoutPlan
    let dateFormatter: DateFormatter
    let onDelete: () -> Void
    let onReschedule: () -> Void

    private var workoutTitle: String {
        switch workout.plan.workout {
        case .custom(let customWorkout):
            return customWorkout.displayName ?? "Custom Workout"
        default:
            return "Scheduled Workout"
        }
    }

    private var activityIconName: String {
        let activity = workoutActivityType
        return activityIcon(for: activity)
    }

    private var workoutActivityType: HKWorkoutActivityType {
        switch workout.plan.workout {
        case .custom(let customWorkout):
            return customWorkout.activity
        case .swimBikeRun:
            return .swimming
        case .pacer:
            return .running
        case .goal(let goal):
            return goal.activity
        @unknown default:
            return .other
        }
    }

    private var activityTypeName: String {
        let activity = workoutActivityType
        return activityName(for: activity)
    }

    private var formattedDate: String {
        let date = workoutDate
        return dateFormatter.string(from: date)
    }

    private var workoutDate: Date {
        if let date = workout.date as? Date {
            return date
        } else if let components = workout.date as? DateComponents {
            return Calendar.current.date(from: components) ?? Date()
        }
        return Date()
    }

    private func activityName(for activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength"
        case .dance: return "Dance"
        case .boxing: return "Boxing"
        case .pilates: return "Pilates"
        case .stairClimbing: return "Stairs"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        default: return "Workout"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activityIconName)
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                Text(workoutTitle)
                    .font(.headline)
                Spacer()
                Text(activityTypeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    onReschedule()
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.clock")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func activityIcon(for activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .hiking: return "figure.hiking"
        case .yoga: return "figure.yoga"
        case .functionalStrengthTraining, .crossTraining: return "figure.strengthtraining.functional"
        case .pilates: return "figure.pilates"
        case .boxing: return "figure.boxing"
        case .dance: return "figure.dance"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rowing"
        case .stairClimbing: return "figure.stairs"
        default: return "figure.run"
        }
    }
}
#endif
