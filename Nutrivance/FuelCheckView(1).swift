import SwiftUI

struct FuelCheckView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        MacronutrientStatusCard()
                            .padding(.horizontal)
                            .padding(.top)
                        HydrationLevelsCard()
                            .padding(.horizontal)
                        //                    HStack(spacing: 20) {
                        NutrientTimingCard()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        PerformanceRecommendations()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        //                    }
                    }
                }
                .background(
                   GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                       .onAppear {
                           withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                               animationPhase = 20
                           }
                       }
               )
                .navigationTitle("Fuel Check")
        }
    }
}

struct MacronutrientStatusCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var carbs: Double = 0
    @State private var protein: Double = 0
    @State private var fats: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macronutrient Balance")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Carbs",
                        value: String(format: "%.0fg", carbs),
                        icon: "leaf.fill"
                    )
                    Divider()
                    MetricItem(
                        title: "Protein",
                        value: String(format: "%.0fg", protein),
                        icon: "figure.strengthtraining.traditional"
                    )
                    Divider()
                    MetricItem(
                        title: "Fats",
                        value: String(format: "%.0fg", fats),
                        icon: "drop.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchMacroData()
        }
    }

    private func fetchMacroData() async {
        let carbsValue = await healthStore.fetchNutrientValueAsync(for: "carbs")
        let proteinValue = await healthStore.fetchNutrientValueAsync(for: "protein")
        let fatsValue = await healthStore.fetchNutrientValueAsync(for: "fats")
        
        carbs = carbsValue
        protein = proteinValue
        fats = fatsValue
        isLoading = false
    }

}

struct HydrationLevelsCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var hydrationLevel: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hydration Status")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Water Intake",
                        value: String(format: "%.0f mL", hydrationLevel * 1000),
                        icon: "drop.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchHydrationData()
        }
    }
    
    private func fetchHydrationData() async {
        await withCheckedContinuation { continuation in
            healthStore.fetchHydration { value in
                hydrationLevel = value
                isLoading = false
                continuation.resume()
            }
        }
    }
}

struct NutrientTimingCard: View {
    @State private var currentTime = Date()
    @State private var lastMealTime: Date? = Calendar.current.date(byAdding: .hour, value: -3, to: Date())
    @State private var isLoading = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // This will set the optimal window to start at 10 AM (2 hours after meal)
    var optimalWindowStart: Date {
        Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    // Window ends at 12 PM
    var optimalWindowEnd: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    var timeUntilWindow: TimeInterval {
        optimalWindowStart.timeIntervalSince(currentTime)
    }
    
    var progressValue: Double {
        let hours = Calendar.current.component(.hour, from: currentTime)
        return Double(hours) / 24.0
    }
    
    var windowColor: Color {
        if timeUntilWindow <= 0 && timeUntilWindow > -3600 { // Within window
            return .green
        } else if abs(timeUntilWindow) <= 7200 { // Within 2 hours
            return .yellow
        }
        return .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrient Timing")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let lastMeal = lastMealTime {
                            TimingRow(title: "Last Meal",
                                    time: lastMeal,
                                    icon: "clock.fill")
                        }
                        
                        TimingRow(title: "Optimal Window",
                                 time: optimalWindowStart,
                                 icon: "target")
                    }
                    
                    Spacer()
                    
                    CircularTimingView(progress: progressValue,
                                     windowStart: optimalWindowStart,
                                     currentTime: currentTime,
                                     color: windowColor)
                        .frame(width: 150, height: 150)
                        .padding()
                        .padding(.trailing)
                }
            }
        }
//        .frame(width: 465, height: 300)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(timer) { time in
            currentTime = time
        }
    }
}

struct CircularTimingView: View {
    let progress: Double
    let windowStart: Date
    let currentTime: Date
    let color: Color
    
    private var windowStartProgress: Double {
        let startHour = Calendar.current.component(.hour, from: windowStart)
        return Double(startHour) / 24.0
    }
    
    private var windowEndProgress: Double {
        let endHour = Calendar.current.component(.hour, from: windowStart.addingTimeInterval(3600 * 2))
        return Double(endHour) / 24.0
    }
    
    private var isInWindow: Bool {
        progress >= windowStartProgress && progress <= windowEndProgress
    }
    
    private var timeUntilWindow: String {
        if isInWindow {
            return "Optimal Time"
        }
        let interval = windowStart.timeIntervalSince(currentTime)
        let hours = Int(abs(interval) / 3600)
        let minutes = Int((abs(interval).truncatingRemainder(dividingBy: 3600)) / 60)
        return interval > 0 ? "\(hours)h \(minutes)m" : "Next window in 22h"
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 10)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            // Window start indicator
            if !isInWindow {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .offset(y: -70)
                    .rotationEffect(.degrees(360 * windowStartProgress))
            }
            
            // Window end indicator
            if !isInWindow {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .offset(y: -70)
                    .rotationEffect(.degrees(360 * windowEndProgress))
            }
            
            // Current time indicator
            Image(systemName: "arrowtriangle.up.fill")
                .foregroundColor(isInWindow ? color : .primary)
                .offset(y: -70)
                .rotationEffect(.degrees(360 * progress))
            
            // Center status
            VStack(spacing: 4) {
                if isInWindow {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                Text(timeUntilWindow)
                    .font(.system(size: 14, weight: .medium))
                Text(currentTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PerformanceRecommendations: View {
    let recommendations: [(String, String, String)] = [
        ("Pre-Workout", "Consume complex carbs 2-3 hours before", "figure.run"),
        ("During Activity", "Stay hydrated, electrolyte balance", "drop.fill"),
        ("Post-Workout", "Protein within 30 minutes", "figure.cooldown"),
        ("Recovery", "Balance macros for optimal recovery", "heart.fill")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Nutrition")
                .font(.title2.bold())
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(recommendations, id: \.0) { rec in
                        RecommendationRow(
                            title: rec.0,
                            description: rec.1,
                            icon: rec.2
                        )
                    }
                }
                Spacer()
            }
        }
//        .frame(width: 465, height: 300)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TimingRow: View {
    let title: String
    let time: Date
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(time, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
