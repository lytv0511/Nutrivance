
import SwiftUI
import Charts

// MARK: - BlurView for Liquid Glass Effect
import UIKit

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct DashboardView: View {
    @StateObject var engine = HealthStateEngine()
    @State private var selectedChartRange: ChartRange = .month
    @State private var selectedMetric: MetricType = .recovery
    @State private var animationPhase: Double = 0
    
    enum DetailViewType {
        case none
        case feelGood
        case metric(MetricType)
    }
    
    @State private var activeDetailView: DetailViewType = .none

    enum ChartRange: String, CaseIterable {
        case day24h = "24h"
        case week = "7d"
        case month = "30d"
    }
    enum MetricType: String {
        case recovery, readiness, strain, allostatic, autonomic
    }

    // Customization State
    @State private var showCustomizationSheet: Bool = false
    @State private var showArrangementSheet: Bool = false
    @State private var groupSummaryCards: Bool = false
    @State private var dashboardItemOrder: [String] = ["SummaryCards", "HRVTrend"]
    @State private var summaryCardsOrder: [String] = ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dashboardItemsSection()
                    feelGoodScoreSection()
                    acwrSection()
                    navigationLinksSection()
                }
                .padding(.top)
            }
            .background(
                GradientBackgrounds()
                    .burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showArrangementSheet = true
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()}) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showArrangementSheet) {
                DashboardArrangementSheet(
                    isPresented: $showArrangementSheet,
                    dashboardItemOrder: $dashboardItemOrder,
                    summaryCardsOrder: $summaryCardsOrder
                )
            }
        }
    }

    // MARK: - Dashboard Sections as ViewBuilder functions

    @ViewBuilder
    private func dashboardItemsSection() -> some View {
        ForEach(dashboardItemOrder, id: \.self) { item in
            Group {
                // Show the collapsible button before Summary Cards
                if item == "SummaryCards" {
                    HStack {
                        Button(action: { withAnimation { groupSummaryCards.toggle() }
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()}) {
                            HStack(spacing: 6) {
                                Image(systemName: groupSummaryCards ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Summary Cards")
                                    .font(.headline)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                switch item {
                case "SummaryCards":
                    if groupSummaryCards {
                        summaryCardsTabView()
                    } else {
                        summaryCardsInline()
                    }
                case "HRVTrend":
                    hrvTrendSection()
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func summaryCardsTabView() -> some View {
        TabView {
            ForEach(summaryCardsOrder, id: \.self) { title in
                summaryCard(
                    icon: iconFor(title),
                    title: title,
                    value: valueFor(title),
                    baseline: baselineFor(title),
                    description: descriptionFor(title),
                    color: colorFor(title),
                    metric: metricFor(title)
                )
                .padding(.bottom)
                .padding(.horizontal)
            }
        }
        .frame(height: 200)
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func summaryCardsInline() -> some View {
        VStack(spacing: 12) {
            ForEach(summaryCardsOrder, id: \.self) { title in
                summaryCard(
                    icon: iconFor(title),
                    title: title,
                    value: valueFor(title),
                    baseline: baselineFor(title),
                    description: descriptionFor(title),
                    color: colorFor(title),
                    metric: metricFor(title)
                )
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func hrvTrendSection() -> some View {
        VStack(spacing: 8) {
            // Chart Filters - pill-shaped buttons
            HStack(spacing: 12) {
                ForEach(ChartRange.allCases, id: \.self) { range in
                    Button(action: { selectedChartRange = range
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()}) {
                        Text(range.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(selectedChartRange == range ? .white : .accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .background(
                        Capsule()
                            .fill(selectedChartRange == range ? Color.accentColor : Color.gray.opacity(0.2))
                    )
                }
                Spacer(minLength: 0)
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
        }
    }

    @ViewBuilder
    private func sleepWeightedSection() -> some View {
        let hrv = engine.latestHRV ?? 0
        let sleep = engine.sleepHours ?? 0
        let sleepWeight = min(max(sleep / 8.0, 0), 1) // normalize sleep to 0-1 (assuming 8h optimal)
        let sleepWeightedHRV = hrv * sleepWeight

        VStack(alignment: .leading) {
            Text("Sleep-Weighted HRV")
                .font(.headline)
                .padding(.horizontal)
            HStack {
                Text(String(format: "%.0f", sleepWeightedHRV))
                    .font(.largeTitle)
                    .bold()
                Text("(Sleep HRV)")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func acwrSection() -> some View {
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
    }

    @ViewBuilder
    private func navigationLinksSection() -> some View {
        VStack(spacing: 10) {
            NavigationLink("Recovery Details", destination: RecoveryScoreView())
            NavigationLink("Readiness Details", destination: ReadinessCheckView())
            NavigationLink("Strain & Recovery", destination: StrainRecoveryView())
            NavigationLink("Fuel Check", destination: FuelCheckView())
        }
        .padding(.vertical)
    }
    
    @ViewBuilder
    private func feelGoodScoreSection() -> some View {
        Button {
            activeDetailView = .feelGood
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } label: {
            let score = engine.feelGoodScore

            VStack(alignment: .leading, spacing: 6) {
                Text("Feel-Good Score")
                    .font(.headline)
                    .padding(.horizontal)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", score))
                        .font(.system(size: 36, weight: .bold))
                    Text("/100")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .padding(.horizontal)
                Text("Your overall physiological readiness and recovery, based on multiple metrics.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding(.horizontal)
        }
        .navigationDestination(isPresented: Binding(
            get: { 
                if case .feelGood = activeDetailView { return true } else { return false }
            },
            set: { if !$0 { activeDetailView = .none } }
        )) {
            FeelGoodScoreDetailView(engine: engine, isPresented: Binding(
                get: { if case .feelGood = activeDetailView { return true } else { return false } },
                set: { if !$0 { activeDetailView = .none } }
            ))
        }
    }

    // customizationSheet() removed

    // Helper functions to map title to properties
    func iconFor(_ title: String) -> String {
        switch title {
        case "Recovery": return "heart.circle.fill"
        case "Readiness": return "bolt.heart.fill"
        case "Strain": return "flame.fill"
        case "Allostatic": return "waveform.path.ecg"
        case "Autonomic": return "heart.circle"
        default: return "questionmark"
        }
    }

    func valueFor(_ title: String) -> Double {
        switch title {
        case "Recovery": return engine.recoveryScore
        case "Readiness": return engine.readinessScore
        case "Strain": return engine.strainScore
        case "Allostatic": return engine.allostaticStressScore
        case "Autonomic": return engine.autonomicBalanceScore
        default: return 0
        }
    }

    func baselineFor(_ title: String) -> Double? {
        switch title {
        case "Recovery": return engine.hrvBaseline7Day
        default: return nil
        }
    }

    func descriptionFor(_ title: String) -> String {
        switch title {
        case "Recovery":
            return "Shows how ready your body is based on HRV, resting heart rate, and sleep. Higher numbers mean better recovery."
        case "Readiness":
            return "Indicates how prepared your body is today. Higher numbers mean you can perform well; lower numbers suggest taking it easier."
        case "Strain":
            return "Measures the stress your body has experienced from activity and lifestyle. Higher numbers mean more stress/load."
        case "Allostatic":
            return "Represents cumulative stress on your body over time. Higher numbers mean your body has been under repeated stress and may need recovery."
        case "Autonomic":
            return "Shows how well your body's nervous system is balanced. Higher numbers mean calm and balance; lower numbers may indicate stress."
        default:
            return ""
        }
    }

    func colorFor(_ title: String) -> Color {
        switch title {
        case "Recovery": return .green
        case "Readiness": return .blue
        case "Strain": return .orange
        case "Allostatic": return .red
        case "Autonomic": return .purple
        default: return .gray
        }
    }

    func metricFor(_ title: String) -> MetricType {
        switch title {
        case "Recovery": return .recovery
        case "Readiness": return .readiness
        case "Strain": return .strain
        case "Allostatic": return .allostatic
        case "Autonomic": return .autonomic
        default: return .recovery
        }
    }

    // Summary Card Factory
    private func summaryCard(icon: String, title: String, value: Double, baseline: Double?, description: String, color: Color, metric: MetricType) -> some View {
        Button {
            HapticFeedback.selection()
            activeDetailView = .metric(metric)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.headline)
                    Spacer()
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
        .sheet(isPresented: Binding(
            get: { 
                if case .metric(let m) = activeDetailView, m == metric { return true } else { return false }
            },
            set: { if !$0 { activeDetailView = .none } }
        )) {
            MetricDetailModal(
                engine: engine,
                metric: metric
            )
        }
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

// MARK: - Dashboard Arrangement Sheet
struct DashboardArrangementSheet: View {
    @Binding var isPresented: Bool
    @Binding var dashboardItemOrder: [String]
    @Binding var summaryCardsOrder: [String]
    
    @State private var isEditingMode: Bool = false
    @State private var localDashboardOrder: [String] = []
    @State private var localSummaryCardsOrder: [String] = []
    
    let mainItems = [
        ("A", "Summary Cards", ["Recovery", "Readiness", "Strain", "Allostatic", "Autonomic"]),
        ("B", "HRV Trend", [])
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<localDashboardOrder.count, id: \.self) { mainIndex in
                        let mainItemName = localDashboardOrder[mainIndex]
                        let letter = mainItemName == "SummaryCards" ? "A" : "B"
                        let displayName = mainItemName == "SummaryCards" ? "Summary Cards" : "HRV Trend"
                        
                        if mainItemName == "SummaryCards" {
                            DisclosureGroup(letter + ". " + displayName) {
                                ForEach(0..<localSummaryCardsOrder.count, id: \.self) { itemIndex in
                                    HStack {
                                        Text("\(itemIndex + 1). \(localSummaryCardsOrder[itemIndex])")
                                        Spacer()
                                        if isEditingMode {
                                            HStack(spacing: 4) {
                                                Button(action: {
                                                    if itemIndex > 0 {
                                                        localSummaryCardsOrder.swapAt(itemIndex, itemIndex - 1)
                                                    }
                                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                                    impact.impactOccurred()
                                                }) {
                                                    Image(systemName: "chevron.up")
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                }
                                                Button(action: {
                                                    if itemIndex < localSummaryCardsOrder.count - 1 {
                                                        localSummaryCardsOrder.swapAt(itemIndex, itemIndex + 1)
                                                    }
                                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                                    impact.impactOccurred()
                                                }) {
                                                    Image(systemName: "chevron.down")
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            Text(letter + ". " + displayName)
                        }
                    }
                    
                    if isEditingMode {
                        HStack {
                            Spacer()
                            Button(action: {
                                if localDashboardOrder.count == 2 {
                                    localDashboardOrder.swapAt(0, 1)
                                }
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text("Swap A & B")
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Dashboard Layout")
                }
            }
            .navigationTitle("Arrange Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditingMode ? "Done" : "Edit") {
                        if isEditingMode {
                            dashboardItemOrder = localDashboardOrder
                            summaryCardsOrder = localSummaryCardsOrder
                            isPresented = false
                        }
                        isEditingMode.toggle()
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
                    .foregroundColor(.blue)
                }
            }
            .onAppear {
                localDashboardOrder = dashboardItemOrder
                localSummaryCardsOrder = summaryCardsOrder
            }
        }
    }
}
