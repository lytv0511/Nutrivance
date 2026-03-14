import SwiftUI
import HealthKit

struct WorkoutHistoryView: View {
    @State private var isLoading = false
    @State private var resultMessage: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            Button(action: runAnalyticsForAllWorkouts) {
                HStack {
                    if isLoading {
                        ProgressView()
                    }
                    Text("Run Workout Analytics (Print to Console)")
                }
            }
            .disabled(isLoading)
            if let msg = resultMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ComingSoonView(
                feature: "WorkoutHistory",
                description: "Experience the future of fitness tracking with WorkoutHistory"
            )
        }
        .padding()
    }

    func runAnalyticsForAllWorkouts() {
        isLoading = true
        resultMessage = nil
        Task {
            // Get last 30 days
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
            let manager = HealthKitManager()
            let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
                manager.fetchWorkouts(from: start, to: end) { result in
                    continuation.resume(returning: result)
                }
            }
            if workouts.isEmpty {
                await MainActor.run {
                    isLoading = false
                    resultMessage = "No workouts found in last 30 days."
                }
                return
            }
            for workout in workouts {
                _ = await manager.computeWorkoutAnalytics(for: workout)
            }
            await MainActor.run {
                isLoading = false
                resultMessage = "Analytics complete. Check Xcode console for output."
            }
        }
    }
}
