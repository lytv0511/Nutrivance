import SwiftUI
import HealthKit

struct StrainRecoveryView: View {
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
                    StrainScoreCard()
                    RecoveryMetricsCard()
                    WorkoutHistoryAnalysis()
                    OvertrainingRiskAssessment()
                }
                .padding()
            }
        }
        .navigationTitle("Strain vs Recovery")
    }
}

struct StrainScoreCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var strainScore: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Daily Strain")
                    .font(.title2.bold())
                
                if isLoading {
                    ProgressView()
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(strainScore))")
                            .font(.system(size: 64, weight: .bold))
                        Text("/10")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .task {
                await fetchStrainData()
            }
            Spacer()
        }
    }
    
    private func fetchStrainData() async {
        healthStore.calculateWorkoutStrain { strain in
            strainScore = strain
            isLoading = false
        }
    }
}

struct RecoveryMetricsCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var hrvValue: Double = 0
    @State private var rhrValue: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery Status")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "HRV",
                        value: String(format: "%.0f ms", hrvValue),
                        icon: "heart.text.square.fill"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Resting HR",
                        value: String(format: "%.0f bpm", rhrValue),
                        icon: "heart.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchRecoveryMetrics()
        }
    }
    
    private func fetchRecoveryMetrics() async {
       hrvValue = await healthStore.fetchHRVAsync()
       rhrValue = await healthStore.fetchRHRAsync()
       isLoading = false
   }
}

struct WorkoutHistoryAnalysis: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var recentWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout History")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                ForEach(recentWorkouts, id: \.uuid) { workout in
                    WorkoutRow(workout: workout)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchWorkoutHistory()
        }
    }
    
    @MainActor
    private func fetchWorkoutHistory() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        await withCheckedContinuation { continuation in
            healthStore.fetchWorkouts(from: startDate, to: endDate) { workouts in
                recentWorkouts = workouts
                isLoading = false
                continuation.resume()
            }
        }
    }
}

struct OvertrainingRiskAssessment: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var riskScore: Double = 0
    @State private var isLoading = true
    
    var riskLevel: String {
        switch riskScore {
        case 0..<3: return "Low"
        case 3..<7: return "Moderate"
        default: return "High"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overtraining Risk")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Risk Level",
                        value: riskLevel,
                        icon: "exclamationmark.triangle.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await calculateRiskScore()
        }
    }
    
    private func calculateRiskScore() async {
        let hrv = await healthStore.fetchHRVAsync()
        riskScore = hrv < 30 ? 8 : hrv < 50 ? 5 : 2
        isLoading = false
    }
}

struct WorkoutRow: View {
    let workout: HKWorkout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(workout.workoutActivityType.name)
                    .font(.headline)
                Text(formatDuration(workout.duration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            let energyType = HKQuantityType(.activeEnergyBurned)
            Text(String(format: "%.0f kcal", workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        return "\(hours)h \(minutes)m"
    }
}

