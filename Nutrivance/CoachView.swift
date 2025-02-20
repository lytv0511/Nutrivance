import SwiftUI
import HealthKit

struct CoachView: View {
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
                    MotivationalMessageCard()
                    AchievementsCard()
                    ProgressTrackingCard()
                    GoalSettingCard()
                }
                .padding()
            }
        }
        .navigationTitle("Coach")
    }
}

struct MotivationalMessageCard: View {
    let messages = [
        "Every rep brings you closer to your goals",
        "Focus on form, results will follow",
        "Quality movement creates lasting strength",
        "Today's practice is tomorrow's progress"
    ]
    
    var dailyMessage: String {
        let day = Calendar.current.component(.day, from: Date())
        return messages[day % messages.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Motivation")
                .font(.title2.bold())
            
            HStack {
                Text(dailyMessage)
                    .font(.headline)
                    .padding(.vertical)
             Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 45))
                    .foregroundStyle(.orange)
                    .padding(.trailing)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AchievementsCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var workoutCount: Int = 0
    @State private var totalMinutes: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Workouts",
                        value: "\(workoutCount)",
                        icon: "figure.strengthtraining.traditional"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Minutes",
                        value: String(format: "%.0f", totalMinutes),
                        icon: "clock.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchAchievements()
        }
    }
    
    private func fetchAchievements() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate)!
        
        healthStore.fetchWorkouts(from: startDate, to: endDate) { workouts in
            workoutCount = workouts.count
            totalMinutes = workouts.reduce(0) { $0 + $1.duration / 60 }
            isLoading = false
        }
    }
}

struct ProgressTrackingCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var recentWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress Tracking")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                ForEach(recentWorkouts, id: \.uuid) { workout in
                    WorkoutProgressRow(workout: workout)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchWorkouts()
        }
    }
    
    @MainActor
    private func fetchWorkouts() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        healthStore.fetchWorkouts(from: startDate, to: endDate) { workouts in
            recentWorkouts = workouts
            isLoading = false
        }
    }
}

struct GoalSettingCard: View {
    @AppStorage("weeklyWorkoutGoal") private var weeklyGoal = 3
    @StateObject private var healthStore = HealthKitManager()
    @State private var currentWeekWorkouts = 0
    @State private var isLoading = true
    
    var progress: Double {
        Double(currentWeekWorkouts) / Double(weeklyGoal)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Goals")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(currentWeekWorkouts)/\(weeklyGoal) workouts")
                        .font(.headline)
                    
                    ProgressView(value: progress)
                        .tint(.orange)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchWeeklyProgress()
        }
    }
    
    private func fetchWeeklyProgress() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        healthStore.fetchWorkouts(from: startDate, to: endDate) { workouts in
            currentWeekWorkouts = workouts.count
            isLoading = false
        }
    }
}

struct WorkoutProgressRow: View {
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
