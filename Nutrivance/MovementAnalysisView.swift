import SwiftUI
import HealthKit

struct MovementAnalysisView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    Color(red: 0.75, green: 0.0, blue: 0),
                    Color(red: 1.0, green: 0.4, blue: 0),
                    Color(red: 0.95, green: 0.6, blue: 0),
                    Color(red: 0.8, green: 0.2, blue: 0),
                    Color(red: 1.0, green: 0.5, blue: 0),
                    Color(red: 0.9, green: 0.3, blue: 0),
                    Color(red: 0.8, green: 0.1, blue: 0),
                    Color(red: 1.0, green: 0.45, blue: 0),
                    Color(red: 0.85, green: 0.25, blue: 0)
                ]
            )
            .ignoresSafeArea()
            .hueRotation(.degrees(animationPhase))
            
            ScrollView {
                VStack(spacing: 20) {
                    CurrentWorkoutAnalysis()
                    MovementQualityMetrics()
                    FormFeedbackCard()
                    PastWorkoutReview()
                }
                .padding()
            }
        }
        .navigationTitle("Movement Analysis")
    }
}

struct CurrentWorkoutAnalysis: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var currentWorkout: HKWorkout?
    @State private var heartRate: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Session")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else if let workout = currentWorkout {
                HStack {
                    MetricItem(
                        title: "Activity",
                        value: workout.workoutActivityType.name,
                        icon: "figure.run"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Heart Rate",
                        value: String(format: "%.0f bpm", heartRate),
                        icon: "heart.fill"
                    )
                }
            } else {
                Text("No active workout")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchCurrentWorkout()
        }
    }
    
    private func fetchCurrentWorkout() async {
        healthStore.fetchMostRecentWorkout { workout in
            currentWorkout = workout
            isLoading = false
        }
    }
}

struct MovementQualityMetrics: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var workoutEnergy: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement Quality")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Energy",
                        value: String(format: "%.0f kcal", workoutEnergy),
                        icon: "flame.fill"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Duration",
                        value: formatDuration(duration),
                        icon: "clock.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchMovementData()
        }
    }
    
    private func fetchMovementData() async {
        if let workout = await fetchMostRecentWorkout() {
            workoutEnergy = await healthStore.calculateWorkoutEnergy(workout: workout)
            duration = workout.duration
        }
        isLoading = false
    }
    
    private func fetchMostRecentWorkout() async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            healthStore.fetchMostRecentWorkout { workout in
                continuation.resume(returning: workout)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

struct FormFeedbackCard: View {
    var formTips: [(String, String)] = [
        ("Maintain Core Engagement", "Keep your core tight throughout movements"),
        ("Control the Eccentric", "Focus on the lowering phase"),
        ("Full Range of Motion", "Complete each rep through full range"),
        ("Breathing Pattern", "Exhale during exertion")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Form Tips")
                .font(.title2.bold())
            
            ForEach(formTips, id: \.0) { tip in
                FormTipRow(title: tip.0, description: tip.1)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PastWorkoutReview: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var workouts: [HKWorkout] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Workouts")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                ForEach(workouts.prefix(3), id: \.uuid) { workout in
                    WorkoutReviewRow(workout: workout)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchPastWorkouts()
        }
    }
    
    private func fetchPastWorkouts() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        healthStore.fetchWorkouts(from: startDate, to: endDate) { fetchedWorkouts in
            workouts = fetchedWorkouts
            isLoading = false
        }
    }
}

struct FormTipRow: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct WorkoutReviewRow: View {
    let workout: HKWorkout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(workout.workoutActivityType.name)
                    .font(.headline)
                Text(formatDate(workout.startDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(formatDuration(workout.duration))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday().day())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}
