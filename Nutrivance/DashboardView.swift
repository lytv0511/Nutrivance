import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject var engine = HealthStateEngine()
    @State private var selectedChartRange: ChartRange = .month
    @State private var showDetailModal: Bool = false
    @State private var selectedMetric: MetricType = .recovery
    @State private var animationPhase: Double = 0

    enum ChartRange: String, CaseIterable {
        case day24h = "24h"
        case week = "7d"
        case month = "30d"
    }
    enum MetricType: String {
        case recovery, readiness, strain, allostatic, autonomic
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Cards
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            summaryCard(
                                icon: "arrow.triangle.2.circlepath.heart.fill",
                                title: "Recovery",
                                value: engine.recoveryScore,
                                baseline: engine.hrvBaseline,
                                description: "Overall recovery based on HRV, RHR, and sleep",
                                color: .green,
                                metric: .recovery
                            )
                            summaryCard(
                                icon: "bolt.heart.fill",
                                title: "Readiness",
                                value: engine.readinessScore,
                                baseline: nil,
                                description: "Physiological readiness today",
                                color: .blue,
                                metric: .readiness
                            )
                            summaryCard(
                                icon: "flame.fill",
                                title: "Strain",
                                value: engine.strainScore,
                                baseline: nil,
                                description: "Training stress from recent activity",
                                color: .orange,
                                metric: .strain
                            )
                            summaryCard(
                                icon: "waveform.path.ecg",
                                title: "Allostatic Stress",
                                value: engine.allostaticStressScore,
                                baseline: nil,
                                description: "Allostatic stress load",
                                color: .red,
                                metric: .allostatic
                            )
                            summaryCard(
                                icon: "arrow.left.and.right.heart",
                                title: "Autonomic Balance",
                                value: engine.autonomicBalanceScore,
                                baseline: nil,
                                description: "Autonomic balance (HRV vs RHR)",
                                color: .purple,
                                metric: .autonomic
                            )
                        }
                        .padding(.horizontal)
                    }
                    .sheet(isPresented: $showDetailModal) {
                        MetricDetailModal(
                            engine: engine,
                            metric: selectedMetric
                        )
                    }

                    // Chart Filters
                    HStack(spacing: 10) {
                        ForEach(ChartRange.allCases, id: \.self) { range in
                            Button(action: {
                                selectedChartRange = range
                            }) {
                                Text(range.rawValue)
                                    .font(.caption)
                                    .padding(6)
                                    .background(selectedChartRange == range ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // HRV Trend Chart
                    VStack(alignment: .leading) {
                        Text("HRV Trend")
                            .font(.headline)
                            .padding(.horizontal)
                        Chart {
                            ForEach(chartData(for: engine.dailyHRV), id: \.date) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("HRV", point.average)
                                )
                                .foregroundStyle(.green)
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal)
                    }

                    // Sleep-Weighted HRV
                    VStack(alignment: .leading) {
                        Text("Sleep-Weighted HRV")
                            .font(.headline)
                            .padding(.horizontal)
                        HStack {
                            Text("\(Int(engine.sleepHRVScore))")
                                .font(.largeTitle)
                                .bold()
                            Text("(Sleep HRV)")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // ACWR Chart
                    VStack(alignment: .leading) {
                        Text("Training Load (ACWR)")
                            .font(.headline)
                            .padding(.horizontal)
                        HStack {
                            Text("Load: \(Int(engine.activityLoad))")
                            Spacer()
                            let acute = engine.activityLoad
                            let chronic = max(engine.activityLoad / 4, 1)
                            let acwr = acute / chronic
                            Text("ACWR: \(String(format: "%.2f", acwr))")
                        }
                        .padding(.horizontal)
                    }

                    // Navigation Links
                    VStack(spacing: 10) {
                        NavigationLink("Recovery Details", destination: RecoveryScoreView())
                        NavigationLink("Readiness Details", destination: ReadinessCheckView())
                        NavigationLink("Strain & Recovery", destination: StrainRecoveryView())
                        NavigationLink("Fuel Check", destination: FuelCheckView())
                    }
                    .padding(.vertical)
                }
                .padding(.top)
            }
            .background(
                GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // Summary Card Factory
    private func summaryCard(icon: String, title: String, value: Double, baseline: Double?, description: String, color: Color, metric: MetricType) -> some View {
        Button {
            HapticFeedback.selection()
            selectedMetric = metric
            showDetailModal = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.headline)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(value))")
                        .font(.system(size: 28, weight: .bold))
                    if let base = baseline {
                        Text("(\(Int(base)))")
                            .foregroundColor(.secondary)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Chart Data Filter
    private func chartData(for dailyHRV: [HealthStateEngine.DailyHRVPoint]) -> [HealthStateEngine.DailyHRVPoint] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedChartRange {
        case .day24h:
            return dailyHRV.filter { calendar.isDate($0.date, inSameDayAs: now) }
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return [] }
            return dailyHRV.filter { $0.date >= start && $0.date <= now }
        case .month:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return [] }
            return dailyHRV.filter { $0.date >= start && $0.date <= now }
        }
    }
}

// Haptic Helper
struct HapticFeedback {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

// Metric Detail Modal
struct MetricDetailModal: View {
    @ObservedObject var engine: HealthStateEngine
    let metric: DashboardView.MetricType
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(detailTitle)
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)

            Text(detailDescription)
                .font(.body)
                .foregroundColor(.secondary)

            Divider()

            Group {
                switch metric {
                case .recovery:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recovery Score: \(Int(engine.recoveryScore))")
                        Text("HRV: \(Int(engine.latestHRV ?? 0)) ms")
                        Text("Resting HR: \(Int(engine.restingHeartRate ?? 0)) bpm")
                        Text("Sleep: \(String(format: "%.1f", engine.sleepHours ?? 0)) h")
                        Text("Sleep-Weighted HRV: \(Int(engine.sleepHRVScore))")
                    }
                case .readiness:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Readiness Score: \(Int(engine.readinessScore))")
                        Text("HRV Trend: \(Int(engine.hrvTrendScore))")
                        Text("Circadian HRV: \(Int(engine.circadianHRVScore))")
                        Text("Sleep HRV: \(Int(engine.sleepHRVScore))")
                        Text("Strain: \(Int(engine.strainScore))")
                    }
                case .strain:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Strain Score: \(Int(engine.strainScore))")
                        Text("Training Load: \(Int(engine.activityLoad))")
                        let acute = engine.activityLoad
                        let chronic = max(engine.activityLoad / 4, 1)
                        let acwr = acute / chronic
                        Text("ACWR: \(String(format: "%.2f", acwr))")
                    }
                case .allostatic:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allostatic Stress: \(Int(engine.allostaticStressScore))")
                        Text("HRV: \(Int(engine.latestHRV ?? 0)) ms")
                        Text("Resting HR: \(Int(engine.restingHeartRate ?? 0)) bpm")
                        Text("Sleep: \(String(format: "%.1f", engine.sleepHours ?? 0)) h")
                        Text("Strain: \(Int(engine.strainScore))")
                    }
                case .autonomic:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Autonomic Balance: \(Int(engine.autonomicBalanceScore))")
                        Text("HRV: \(Int(engine.latestHRV ?? 0)) ms")
                        Text("Resting HR: \(Int(engine.restingHeartRate ?? 0)) bpm")
                    }
                }
            }
            .font(.title3)
            Spacer()
        }
        .padding()
        .onAppear {
            HapticFeedback.selection()
        }
    }

    var detailTitle: String {
        switch metric {
        case .recovery: return "Recovery"
        case .readiness: return "Readiness"
        case .strain: return "Strain"
        case .allostatic: return "Allostatic Stress"
        case .autonomic: return "Autonomic Balance"
        }
    }
    var detailDescription: String {
        switch metric {
        case .recovery:
            return "Recovery is a composite of HRV, resting heart rate, and sleep. Higher scores suggest you are well-recovered and ready for activity."
        case .readiness:
            return "Readiness reflects your physiological state today, including trends and circadian patterns. Use it to guide your training and recovery."
        case .strain:
            return "Strain measures training and lifestyle stress over the past week. Higher strain can reduce recovery if not balanced."
        case .allostatic:
            return "Allostatic stress represents the cumulative burden of stressors on your body, including physical and psychological load."
        case .autonomic:
            return "Autonomic balance compares your HRV and resting heart rate to assess nervous system balance."
        }
    }
}
