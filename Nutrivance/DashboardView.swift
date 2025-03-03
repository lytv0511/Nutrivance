import SwiftUI
import Charts
import HealthKit

struct DashboardMetrics {
    var activeEnergy: String = "0"
    var restingEnergy: String = "0"
    var steps: String = "0"
    var distance: String = "0"
    var standMinutes: String = "0"
    var physicalEffort: String = "0"
    var standHours: String = "0"
    var flights: String = "0"
    var exercise: String = "0"
    var workouts: [HKWorkout] = []
}

class DashboardViewModel: ObservableObject {
    @Published var metrics = DashboardMetrics()
    let healthStore: HealthKitManager
    
    init(healthStore: HealthKitManager) {
        self.healthStore = healthStore
    }
    
    func loadHealthData() async {
        let types: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .basalEnergyBurned,
            .stepCount,
            .distanceWalkingRunning,
            .appleExerciseTime,
            .flightsClimbed
        ]
        
        for type in types {
            if let quantity = try? await healthStore.fetchTodayQuantity(for: type) {
                await MainActor.run {
                    switch type {
                    case .activeEnergyBurned:
                        metrics.activeEnergy = String(format: "%.0f", quantity)
                    case .basalEnergyBurned:
                        metrics.restingEnergy = String(format: "%.0f", quantity)
                    case .stepCount:
                        metrics.steps = String(format: "%.0f", quantity)
                    case .distanceWalkingRunning:
                        metrics.distance = String(format: "%.1f", quantity/1000)
                    case .appleExerciseTime:
                        metrics.exercise = String(format: "%.0f", quantity)
                    case .flightsClimbed:
                        metrics.flights = String(format: "%.0f", quantity)
                    default:
                        break
                    }
                }
            }
        }
        
        let standHours = await withCheckedContinuation { continuation in
            healthStore.fetchStandTime { hours in
                continuation.resume(returning: hours)
            }
        }
        
        await MainActor.run {
            metrics.standHours = String(format: "%.0f", standHours)
        }
    }

}

struct DashboardView: View {
    @State private var animationPhase: Double = 0
    @StateObject private var healthStore = HealthKitManager()
    @StateObject private var viewModel: DashboardViewModel
    
    init() {
        let healthStore = HealthKitManager()
        _viewModel = StateObject(wrappedValue: DashboardViewModel(healthStore: healthStore))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Rest of your view code remains the same, but use viewModel.metrics instead of metrics
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today's Overview")
                                .font(.title2)
                                .bold()
                            Text(Date(), style: .date)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        CircularProgressView(progress: 0.75)
                            .frame(width: 60, height: 60)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 15) {
                            MetricCard(title: "Active Energy", value: viewModel.metrics.activeEnergy, unit: "kcal", icon: "flame.fill")
                            MetricCard(title: "Steps", value: viewModel.metrics.steps, unit: "steps", icon: "figure.walk")
                            MetricCard(title: "Distance", value: viewModel.metrics.distance, unit: "km", icon: "figure.run")
                            MetricCard(title: "Exercise", value: viewModel.metrics.exercise, unit: "min", icon: "timer")
                            MetricCard(title: "Stand", value: viewModel.metrics.standHours, unit: "hr", icon: "figure.stand")
                            MetricCard(title: "Flights", value: viewModel.metrics.flights, unit: "floors", icon: "stairs")
                        }
                    }
                    .task {
                        await viewModel.loadHealthData()
                    }
                    
                    // Rest of your existing view components
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today's Training")
                            .font(.title3)
                            .bold()
                        
                        ForEach(["Upper Body Strength", "HIIT Cardio", "Core Stability"], id: \.self) { workout in
                            DashboardWorkoutRow(name: workout, duration: "45 min", completed: false)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    
                    RecoveryStatusView()
                    WeeklyProgressChart(viewModel: viewModel)
                }
                .padding()
            }
            .background(
                GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
            )
            .navigationTitle("Dashboard")
        }
        .onAppear {
           healthStore.startObservingHealthData {
               Task { @MainActor in
                   await viewModel.loadHealthData()
               }
           }
       }
    }
}

struct DashboardWorkoutRow: View {
    let name: String
    let duration: String
    let completed: Bool
    
    var body: some View {
        HStack {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? .green : .secondary)
            Text(name)
            Spacer()
            Text(duration)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct RecoveryStatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery Status")
                .font(.title3)
                .bold()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("85%")
                        .font(.title)
                        .bold()
                    Text("Ready for Peak Performance")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                Spacer()
                CircularProgressView(progress: 0.85)
                    .frame(width: 60, height: 60)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}

struct WeeklyProgressChart: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    struct ActivityData: Identifiable, Equatable {
        let id = UUID()
        let day: String
        let moveScore: Double
        let exerciseScore: Double
        let standScore: Double
        
        static func == (lhs: ActivityData, rhs: ActivityData) -> Bool {
            lhs.day == rhs.day &&
            lhs.moveScore == rhs.moveScore &&
            lhs.exerciseScore == rhs.exerciseScore &&
            lhs.standScore == rhs.standScore
        }
    }

    private func fetchWeeklyActivityData() async -> [ActivityData] {
        var activityData: [ActivityData] = []
        let calendar = Calendar.current
        
        let goals = try? await viewModel.healthStore.fetchActivityGoals()
        let activeEnergyGoal = goals?.activeEnergy ?? 600
        let exerciseGoal = goals?.exerciseTime ?? 30
        let standGoal = goals?.standHours ?? 12
        
        for daysAgo in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let activeEnergy = try? await viewModel.healthStore.fetchQuantity(for: .activeEnergyBurned, start: startOfDay, end: endOfDay)
            let exerciseMinutes = try? await viewModel.healthStore.fetchQuantity(for: .appleExerciseTime, start: startOfDay, end: endOfDay)
            let standHours = try? await viewModel.healthStore.fetchQuantity(for: .appleStandTime, start: startOfDay, end: endOfDay)
            
            let energyScore = min((activeEnergy ?? 0) / activeEnergyGoal, 1.0) * 40
            let exerciseScore = min((exerciseMinutes ?? 0) / exerciseGoal, 1.0) * 40
            let standScore = min((standHours ?? 0) / standGoal, 1.0) * 20
            
            let weekday = calendar.component(.weekday, from: date)
            activityData.append(ActivityData(
                day: calendar.shortWeekdaySymbols[weekday - 1],
                moveScore: energyScore,
                exerciseScore: exerciseScore,
                standScore: standScore
            ))
        }
        
        return activityData
    }

    
    @State private var weeklyData: [ActivityData] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Progress")
                .font(.title3)
                .bold()
            
            Chart(weeklyData) { item in
                Plot {
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Move", item.moveScore)
                    )
                    .foregroundStyle(item.moveScore/40 >= 0.8 ?
                        Gradient(colors: [Color(red: 255/255, green: 46/255, blue: 84/255), .orange, .yellow]) :
                        Gradient(colors: [Color(red: 255/255, green: 46/255, blue: 84/255)]))
                    
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Exercise", item.exerciseScore)
                    )
                    .foregroundStyle(item.exerciseScore/40 >= 0.8 ?
                        Gradient(colors: [Color(red: 76/255, green: 217/255, blue: 100/255), .mint, .yellow]) :
                        Gradient(colors: [Color(red: 76/255, green: 217/255, blue: 100/255)]))
                    
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Stand", item.standScore)
                    )
                    .foregroundStyle(item.standScore/20 >= 0.8 ?
                        Gradient(colors: [Color(red: 0/255, green: 122/255, blue: 255/255), .cyan, .white]) :
                        Gradient(colors: [Color(red: 0/255, green: 122/255, blue: 255/255)]))
                }
            }

            .animation(.easeInOut(duration: 0.3), value: weeklyData)
            .frame(height: 200)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .task {
            weeklyData = await fetchWeeklyActivityData()
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                LinearGradient(
                    colors: [.blue, .green],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }
}
