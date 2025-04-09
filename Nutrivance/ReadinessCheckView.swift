import SwiftUI

struct ReadinessCheckView: View {
    @State private var animationPhase: Double = 0
    @State private var hrvValue: Double = 0
    @State private var rhrValue: Double = 0
    @StateObject private var healthStore = HealthKitManager()
    
    var body: some View {
        NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        ReadinessScoreCard()
                            .frame(maxWidth: .infinity)
                            .padding()
                        RecoveryRecommendationsCard(hrvValue: hrvValue, rhrValue: rhrValue)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        SleepMetricsCard()
                            .padding(.horizontal)
                        HRVTrendsCard()
                            .padding(.horizontal)
                    }
                }
                .navigationTitle("Readiness Check")
                .background(
                   GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                       .onAppear {
                           withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                               animationPhase = 20
                           }
                       }
               )
                .task {
                    await fetchHealthData()
                }
            }
    }
    
    private func fetchHealthData() async {
        hrvValue = await healthStore.fetchHRVAsync()
        rhrValue = await healthStore.fetchRHRAsync()
    }
}

struct ReadinessScoreCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var readinessScore: Double = 0
    @State private var hrvValue: Double = 0
    @State private var rhrValue: Double = 0
    @State private var sleepHours: Double = 0
    @State private var isLoading = true
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Readiness Score")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    if horizontalSizeClass == .regular {
                        Text("\(Int(readinessScore))")
                            .font(.system(size: 72, weight: .bold))
                            .padding(.leading, 16)
                        Text("/100")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ReadinessGauge(score: readinessScore)
                            .padding(.trailing, 32)
                            .frame(width: 240, height: 240)
                    } else {
                        VStack(spacing: 16) {
                            HStack {
                                Spacer()
                                Text("\(Int(readinessScore))")
                                    .font(.system(size: 72, weight: .bold))
                                Text("/100")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            ReadinessGauge(score: readinessScore)
                                .frame(width: 200, height: 200)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchHealthData()
        }
    }
    
    private func fetchHealthData() async {
        hrvValue = await healthStore.fetchHRVAsync()
        rhrValue = await healthStore.fetchRHRAsync()
        calculateReadinessScore()
        isLoading = false
    }
    
    private func calculateReadinessScore() {
        let hrvScore = normalizeHRV(hrvValue)
        let rhrScore = normalizeRHR(rhrValue)
        readinessScore = (hrvScore + rhrScore) / 2
    }
    
    private func normalizeHRV(_ hrv: Double) -> Double {
        min(max((hrv - 20) * 2, 0), 100)
    }
    
    private func normalizeRHR(_ rhr: Double) -> Double {
        min(max(100 - (rhr - 40), 0), 100)
    }
}

struct SleepMetricsCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var sleepData: [String: Any] = [:]
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Quality")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Duration",
                        value: formatDuration(sleepData["duration"] as? Double ?? 0),
                        icon: "moon.zzz.fill"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Deep Sleep",
                        value: formatDuration(sleepData["deepSleep"] as? Double ?? 0),
                        icon: "waveform.path"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Efficiency",
                        value: "\(Int((sleepData["efficiency"] as? Double ?? 0) * 100))%",
                        icon: "chart.bar.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchSleepData()
        }
    }
    
    private func fetchSleepData() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate)!
        sleepData = await healthStore.fetchMentalHealthDataAsync(from: startDate, to: endDate)
        isLoading = false
    }
    
    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }
}

struct HRVTrendsCard: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var hrvValue: Double = 0
    @State private var rhrValue: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery Metrics")
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

struct RecoveryRecommendationsCard: View {
    let hrvValue: Double
    let rhrValue: Double
    
    var recommendations: [(String, String, String)] {
        var recs: [(String, String, String)] = []
        
        if hrvValue < 30 {
            recs.append(("Rest & Recharge", "Take this as an opportunity to focus on recovery and self-care", "bed.double.fill"))
        } else if hrvValue < 50 {
            recs.append(("Light Activity", "Moderate HRV suggests careful training", "figure.walk"))
        } else {
            recs.append(("Ready for Action", "Your stress resilience is strong - great time for a challenge!", "figure.run"))
        }
        
        if rhrValue > 65 {
            recs.append(("Recovery Focus", "Let's prioritize rest to optimize performance", "heart.fill"))
        } else {
            recs.append(("Peak Condition", "Your heart rate is in an optimal range - you're primed for activity", "heart.text.square.fill"))
        }
        
        recs.append(("Hydration", "Maintain fluid balance", "drop.fill"))
        
        return recs
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery Recommendations")
                    .font(.title2.bold())
                
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
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MetricItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecommendationRow: View {
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReadinessGauge: View {
    let score: Double
    @State private var animatedScore: Double = 0
    
    var color: Color {
        switch score {
        case 0..<40: return .red
        case 40..<70: return .orange
        case 70..<85: return .yellow
        default: return .green
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: animatedScore/100)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 45))
                .foregroundColor(color)
        }
        .onAppear {
            withAnimation(.spring(response: 1.5, dampingFraction: 0.8, blendDuration: 0.8)) {
                animatedScore = score
            }
        }
    }
}
