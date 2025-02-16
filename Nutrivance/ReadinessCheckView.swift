import SwiftUI

struct ReadinessCheckView: View {
    @State private var animationPhase: Double = 0
    @State private var hrvValue: Double = 0
    @State private var rhrValue: Double = 0
    @StateObject private var healthStore = HealthKitManager()
    
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
                    ReadinessScoreCard()
                    SleepMetricsCard()
                    HRVTrendsCard()
                    RecoveryRecommendationsCard(hrvValue: hrvValue, rhrValue: rhrValue)
                }
                .padding()
            }
        }
        .navigationTitle("Readiness Check")
        .task {
            await fetchHealthData()
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Readiness Score")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    Text("\(Int(readinessScore))")
                        .font(.system(size: 64, weight: .bold))
                    Text("/100")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ReadinessGauge(score: readinessScore)
                        .padding()
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
            recs.append(("Rest Day", "Low HRV indicates high stress", "bed.double.fill"))
        } else if hrvValue < 50 {
            recs.append(("Light Activity", "Moderate HRV suggests careful training", "figure.walk"))
        }
        
        if rhrValue > 65 {
            recs.append(("Recovery Focus", "Elevated RHR detected", "heart.fill"))
        }
        
        recs.append(("Hydration", "Maintain fluid balance", "drop.fill"))
        
        return recs
    }
    
    var body: some View {
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
                .frame(width: 32)
            
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
    
    var color: Color {
        switch score {
        case 0..<40: return .red
        case 40..<70: return .orange
        case 70..<85: return .yellow
        default: return .green
        }
    }
    
    var body: some View {
        Gauge(value: score, in: 0...100) {
            Image(systemName: "bolt.heart.fill")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(color)
        .scaleEffect(1.5)
    }
}
