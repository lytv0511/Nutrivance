//
//  StressView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

// SDNN samples → optional heartbeat-derived RMSSD → cleaned windows → dual baseline (intraday EMA + morning EMA)
// → LF/HF proxy → Stress / Energy / Regulation (dashboard uses morning-readiness baseline).

import SwiftUI
import Charts
import HealthKit

struct StressView: View {
    
    struct HRVSession: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let sdnn: Double
        let rmssd: Double
        let rmssdSource: StressRmssdSource
        let combinedHRV: Double
        let lfHfProxy: Double
        let coefficientOfVariation: Double
        let adjustedHRV: Double
        /// Chart series — intraday EMA baseline (historical continuity).
        let stress: Double
        let energy: Double
        let nervousBalance: Double
        let baselineEMA: Double
        /// Morning-readiness baseline SDNN (cold-start falls back to intraday snapshot).
        let readinessBaselineSdnn: Double
        /// Combined HRV baseline for headline scores — not below intraday snapshot so afternoon samples aren’t pegged vs depressed morning-only memory.
        let dashboardCombinedBaseline: Double
        /// LF/HF proxy for headline Stress (baseline RMSSD leg matches dashboard baseline SDNN).
        let dashboardLfHfProxy: Double
        let dashboardStress: Double
        let dashboardEnergy: Double
        let dashboardRegulation: Double
    }
    
    enum TimeFilter: Hashable {
        case hourly24
        case dailyWeek
        case dailyMonth
    }
    
    @State private var stressScore: Double = 0
    @State private var energyScore: Double = 0
    @State private var nervousBalance: Double = 0
    
    @State private var loading = true
    
    @State private var baselineEMA: Double?
    @State private var previousHRVs: [Double] = []
    @State private var hrvHistory: [HRVSession] = []
    
    @State private var timeFilter: TimeFilter = .hourly24
    @State private var selectedDate: Date = Date()
    @State private var selectedSession: HRVSession?
    @State private var aggregatedData: [HRVSession] = []
    @State private var averageValue: Double = 0
    
    private func selectTimeFilter(_ filter: TimeFilter) {
        timeFilter = filter
        selectedSession = nil
        updateAggregatedData()
        syncSelectedSessionToDate()
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    private func stepSelectedDate(by value: Int) {
        let calendar = Calendar.current
        let unit: Calendar.Component
        
        switch timeFilter {
        case .hourly24:
            unit = .day
        case .dailyWeek:
            unit = .weekOfYear
        case .dailyMonth:
            unit = .month
        }
        
        guard let newDate = calendar.date(byAdding: unit, value: value, to: selectedDate) else {
            return
        }
        
        if value > 0, newDate > Date() {
            return
        }
        
        selectedDate = newDate
        updateAggregatedData()
        syncSelectedSessionToDate()
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    private func jumpToToday() {
        selectedDate = Date()
        updateAggregatedData()
        syncSelectedSessionToDate()
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    /// Keeps week/month charts aligned to calendar days when a day has no HRV samples (`sdnn` is 0 for placeholders).
    private func stressPlaceholderSession(startOfDay: Date) -> HRVSession {
        HRVSession(
            date: startOfDay,
            sdnn: 0,
            rmssd: 0,
            rmssdSource: .sdnnProxy,
            combinedHRV: 0,
            lfHfProxy: 1.0,
            coefficientOfVariation: 0,
            adjustedHRV: 0,
            stress: 50,
            energy: 50,
            nervousBalance: 100,
            baselineEMA: 50,
            readinessBaselineSdnn: 50,
            dashboardCombinedBaseline: StressHRVTransforms.readinessCombinedBaseline(sdnn: 50),
            dashboardLfHfProxy: 1.0,
            dashboardStress: 50,
            dashboardEnergy: 50,
            dashboardRegulation: 100
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dreamy sleep background - isolated to prevent view hierarchy updates
                AnimatedBackgroundView()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 30) {
                        if loading {
                            ProgressView("Analyzing HRV...")
                        } else {
                            // Time filter buttons - pill shaped, equally sized, glass effect
                            FilterButtonGroup(
                                timeFilter: $timeFilter,
                                selectedSession: $selectedSession,
                                onFilterChange: {
                                    updateAggregatedData()
                                    syncSelectedSessionToDate()
                                }
                            )

                            #if targetEnvironment(macCatalyst)
                            if MacCatalystHealthDataPolicy.isActive {
                                Text(MacCatalystHealthDataPolicy.stressHistoryNotice)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                            #endif
                            
                            // Calendar picker for specific date
                            DatePicker(
                                "Select Date",
                                selection: $selectedDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .onChange(of: selectedDate) { _ in
                                updateAggregatedData()
                                syncSelectedSessionToDate()
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                            }
                            .padding(.horizontal)
                            .buttonStyle(.glass)
                            .catalystDesktopFocusable()
                            
                            // Chart View
                            if aggregatedData.count > 0 {
                                VStack(spacing: 12) {
                                    if timeFilter == .dailyMonth {
                                        MonthlyChartView(
                                            aggregatedData: aggregatedData,
                                            selectedSession: $selectedSession,
                                            selectedDate: $selectedDate
                                        )
                                    } else {
                                        HourlyWeeklyChartView(
                                            aggregatedData: aggregatedData,
                                            selectedSession: $selectedSession,
                                            selectedDate: $selectedDate,
                                            timeFilter: timeFilter
                                        )
                                    }
                                    
                                    // Average value display
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text(averageLabel())
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(String(format: "%.1f", averageValue))
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(.ultraThinMaterial)
                                    )
                                }
                                .padding(.horizontal)
                            } else {
                                Text("No data available for selected period")
                                    .foregroundColor(.secondary)
                                    .frame(height: 200)
                            }
                            
                            // Current/Selected metrics card (only show if selected)
                            if let selected = selectedSession {
                                StressHeadlineMetricsCard(session: selected)
                                    .padding(.horizontal)

                                StressScoresExplanation(session: selected)
                                    .padding(.horizontal)

                                
                                // Show detailed metric cards for selected point
                                LazyVGrid(columns: [GridItem(.flexible())], spacing: 22) {
                                    MetricCard(
                                        title: "RMSSD",
                                        symbol: "waveform.path.ecg",
                                        currentValue: selected.rmssd,
                                        baselineValue: StressHRVTransforms.estimateRMSSDFromSDNN(selected.readinessBaselineSdnn),
                                        unit: "",
                                        explanation: "RMSSD (Root Mean Square of Successive Differences) reflects beat‑to‑beat vagal modulation when computed from heartbeat series data; otherwise a pragmatic fallback scales Apple Watch SDNN. Higher RMSSD generally aligns with stronger parasympathetic tone versus your morning‑readiness baseline."
                                    )
                                    MetricCard(
                                        title: "SDNN",
                                        symbol: "chart.bar.doc.horizontal",
                                        currentValue: selected.sdnn,
                                        baselineValue: selected.readinessBaselineSdnn,
                                        unit: "",
                                        explanation: "SDNN captures overall beat‑to‑beat variability in milliseconds. Your headline Stress/Energy/Regulation row compares readings against a morning‑anchored baseline SDNN when enough waking samples exist; otherwise it blends intraday context."
                                    )
                                    MetricCard(
                                        title: "Combined HRV",
                                        symbol: "circle.grid.cross",
                                        currentValue: selected.combinedHRV,
                                        baselineValue: StressHRVTransforms.combinedHRV(
                                            sdnn: selected.readinessBaselineSdnn,
                                            rmssdEffective: StressHRVTransforms.estimateRMSSDFromSDNN(selected.readinessBaselineSdnn)
                                        ),
                                        unit: "",
                                        explanation: "Combined HRV weights beat‑to‑beat variation (~70%) with SDNN (~30%). Charts favor continuity against your rolling intraday baseline; the headline cards emphasize interpretation versus morning‑readiness context."
                                    )
                                    StressLfHfProxiesCard(session: selected)
                                    MetricCard(
                                        title: "Adjusted HRV",
                                        symbol: "shield.lefthalf.fill",
                                        currentValue: selected.adjustedHRV,
                                        baselineValue: StressHRVTransforms.combinedHRV(
                                            sdnn: selected.readinessBaselineSdnn,
                                            rmssdEffective: StressHRVTransforms.estimateRMSSDFromSDNN(selected.readinessBaselineSdnn)
                                        ),
                                        unit: "",
                                        explanation: "Adjusted HRV scales combined HRV down when recent SDNN samples are noisy (high coefficient of variation). It stabilizes intraday charts while headline scores pair the same adjustment with morning‑readiness baselines."
                                    )
                                }
                                .padding()
                            }
                        }
                    }
                    .padding()
                    .onAppear {
                        loadStressMetrics()
                    }
                    #if targetEnvironment(macCatalyst)
                    .refreshable {
                        await HealthStateEngine.shared.refreshSyncedHealthDataFromICloud()
                        await MainActor.run {
                            applyCatalystStressFromEngineSnapshot()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                        loadStressMetrics()
                    }
                    #endif
                    .onChange(of: aggregatedData) { _ in
                        // Sync the selected session whenever aggregated data changes
                        syncSelectedSessionToDate()
                    }
                }
            }
            .navigationTitle("Stress View")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: {
                        jumpToToday()
                    }) {
                        Text("Today")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .catalystToolbarButtonSize()
                    .catalystDesktopFocusable()
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        stepSelectedDate(by: -1)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(.body, design: .rounded))
                    }
                    .catalystIconButtonSize()
                    .catalystDesktopFocusable()
                    
                    Button(action: {
                        stepSelectedDate(by: 1)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(.body, design: .rounded))
                    }
                    .catalystIconButtonSize()
                    .catalystDesktopFocusable()
                    
                    Button(action: {
                        stepSelectedDate(by: 1)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(.body, design: .rounded))
                    }
                    .catalystIconButtonSize()
                    .catalystDesktopFocusable()
                }
            }
            .onReceiveViewControl(.nutrivanceViewControlToday) {
                jumpToToday()
            }
            .onReceiveViewControl(.nutrivanceViewControlPrevious) {
                stepSelectedDate(by: -1)
            }
            .onReceiveViewControl(.nutrivanceViewControlNext) {
                stepSelectedDate(by: 1)
            }
            .onReceiveViewControl(.nutrivanceViewControlFilter1) {
                selectTimeFilter(.hourly24)
            }
            .onReceiveViewControl(.nutrivanceViewControlFilter2) {
                selectTimeFilter(.dailyWeek)
            }
            .onReceiveViewControl(.nutrivanceViewControlFilter3) {
                selectTimeFilter(.dailyMonth)
            }
        }
    }
    
    // MARK: - Monthly Chart View
    struct MonthlyChartView: View {
        let aggregatedData: [StressView.HRVSession]
        @Binding var selectedSession: StressView.HRVSession?
        @Binding var selectedDate: Date

        private func updateSelection(
            from location: CGPoint,
            proxy: ChartProxy,
            geometry: GeometryProxy
        ) {
            let plotFrame = geometry[proxy.plotAreaFrame]
            guard let xPosition = ChartInteractionSmoothing.clampedXPosition(
                for: location,
                plotFrame: plotFrame
            ) else { return }

            let date = proxy.value(atX: xPosition) as Date?
                ?? ChartInteractionSmoothing.fallbackBoundaryDate(
                    for: xPosition,
                    plotFrame: plotFrame,
                    data: aggregatedData.map { ($0.date, $0.combinedHRV) }
                )
            guard let date else { return }

            guard let closest = aggregatedData.min(by: {
                abs($0.date.timeIntervalSince1970 - date.timeIntervalSince1970) <
                abs($1.date.timeIntervalSince1970 - date.timeIntervalSince1970)
            }) else { return }

            if selectedSession?.id != closest.id {
                selectedSession = closest
                selectedDate = closest.date
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        var body: some View {
            GeometryReader { geometry in
                let chartWidth = max(CGFloat(aggregatedData.count) * 40, geometry.size.width)
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .leading) {
                            MonthlyChartContent(
                                aggregatedData: aggregatedData,
                                selectedSession: selectedSession,
                                onSelectionDrag: { location, proxy, geo in
                                    updateSelection(from: location, proxy: proxy, geometry: geo)
                                }
                            )
                            .frame(width: chartWidth)
                            
                            // Invisible scroll anchors positioned at each data point
                            if !aggregatedData.isEmpty {
                                let itemWidth = chartWidth / CGFloat(aggregatedData.count)
                                HStack(spacing: 0) {
                                    ForEach(Array(aggregatedData.enumerated()), id: \.element.id) { index, session in
                                        Color.clear
                                            .frame(width: itemWidth, height: 0)
                                            .id(session.id)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: selectedSession?.id) { _ in
                        if let selectedId = selectedSession?.id {
                            withAnimation {
                                scrollProxy.scrollTo(selectedId, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)
            .padding()
        }
    }
    
    // MARK: - Monthly Chart Content
    struct MonthlyChartContent: View {
        let aggregatedData: [StressView.HRVSession]
        let selectedSession: StressView.HRVSession?
        let onSelectionDrag: (CGPoint, ChartProxy, GeometryProxy) -> Void
        
        var body: some View {
            Chart {
                ForEach(aggregatedData) { session in
                    LineMark(
                        x: .value("Date", session.date),
                        y: .value("HRV", session.combinedHRV)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("Date", session.date),
                        y: .value("HRV", session.combinedHRV)
                    )
                    .foregroundStyle(.blue)
                    .opacity(selectedSession?.id == session.id ? 1 : 0.3)
                }
                
                if let selected = selectedSession {
                    RuleMark(x: .value("Selected", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                }
            }
            .frame(height: 250)
            .padding()
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 10)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    onSelectionDrag(value.location, proxy, geo)
                                }
                        )
                }
            }
        }
    }
    
    // MARK: - Hourly/Weekly Chart View
    struct HourlyWeeklyChartView: View {
        let aggregatedData: [StressView.HRVSession]
        @Binding var selectedSession: StressView.HRVSession?
        @Binding var selectedDate: Date
        let timeFilter: StressView.TimeFilter

        private func updateSelection(
            from location: CGPoint,
            proxy: ChartProxy,
            geometry: GeometryProxy
        ) {
            let plotFrame = geometry[proxy.plotAreaFrame]
            guard let xPosition = ChartInteractionSmoothing.clampedXPosition(
                for: location,
                plotFrame: plotFrame
            ) else { return }

            let date = proxy.value(atX: xPosition) as Date?
                ?? ChartInteractionSmoothing.fallbackBoundaryDate(
                    for: xPosition,
                    plotFrame: plotFrame,
                    data: aggregatedData.map { ($0.date, $0.combinedHRV) }
                )
            guard let date else { return }

            guard let closest = aggregatedData.min(by: {
                abs($0.date.timeIntervalSince1970 - date.timeIntervalSince1970) <
                abs($1.date.timeIntervalSince1970 - date.timeIntervalSince1970)
            }) else { return }

            if selectedSession?.id != closest.id {
                selectedSession = closest
                if timeFilter != .hourly24 {
                    selectedDate = closest.date
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        
        var body: some View {
            Chart {
                ForEach(aggregatedData) { session in
                    LineMark(
                        x: .value("Time", session.date),
                        y: .value("HRV", session.combinedHRV)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("Time", session.date),
                        y: .value("HRV", session.combinedHRV)
                    )
                    .foregroundStyle(.blue)
                    .opacity(selectedSession?.id == session.id ? 1 : 0.3)
                }
                
                if let selected = selectedSession {
                    RuleMark(x: .value("Selected", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                }
            }
            .frame(height: 250)
            .padding()
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisTick()
                    if timeFilter == .hourly24 {
                        AxisValueLabel(format: .dateTime.hour(), centered: true)
                    } else {
                        AxisValueLabel(format: .dateTime.month().day(), centered: true)
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(from: value.location, proxy: proxy, geometry: geo)
                                }
                        )
                }
            }
        }
    }
    
    // MARK: - Metric Card View
        struct MetricCard: View {
            let title: String
            let symbol: String
            let currentValue: Double
            let baselineValue: Double
            let unit: String
            let explanation: String
            
            var body: some View {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: symbol)
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)
                            .frame(width: 36, height: 36)
                        Text(title)
                            .bold()
                            .font(.title3)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%@", currentValue, unit))
                                .bold()
                                .font(.title2)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Baseline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%@", baselineValue, unit))
                                .bold()
                                .font(.title2)
                        }
                    }
                    Text(explanation)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            }
        }
        
        // MARK: - Load HRV Data

        #if targetEnvironment(macCatalyst)
        /// Call `await HealthStateEngine.shared.refreshSyncedHealthDataFromICloud()` first when you need the latest KVS snapshot.
        private func applyCatalystStressFromEngineSnapshot() {
            let engine = HealthStateEngine.shared
            let tuples: [(Date, Double)]
            if !engine.hrvSampleHistory.isEmpty {
                tuples = engine.hrvSampleHistory.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            } else if !engine.dailyHRV.isEmpty {
                tuples = engine.dailyHRV.map { ($0.date, $0.average) }.sorted { $0.0 < $1.0 }
            } else {
                hrvHistory = []
                aggregatedData = []
                loading = false
                return
            }

            let points = tuples.map { StressSessionPipeline.SdnnPoint(sampleUUID: nil, date: $0.0, sdnn: $0.1) }
            /// Mac Catalyst receives SDNN-only handoffs (`EngineHRVSamplePoint`); native heartbeat RMSSD is unavailable until blobs carry beat-derived RMSSD.
            let hrvSessions = StressSessionPipeline.buildSessions(points: points, heartbeatRmssdByUUID: [:], calendar: Calendar.current)

            let calendar = Calendar.current
            let morningSessions = hrvSessions.filter { session in
                let hour = calendar.component(.hour, from: session.date)
                return hour >= 4 && hour <= 11
            }
            let dashboardSession = morningSessions.last ?? hrvSessions.last
            hrvHistory = hrvSessions
            if let dash = dashboardSession {
                stressScore = dash.dashboardStress
                energyScore = dash.dashboardEnergy
                nervousBalance = dash.dashboardRegulation
            }
            updateAggregatedData()
            syncSelectedSessionToDate()
            loading = false
        }
        #endif
        
        func loadStressMetrics() {
            #if targetEnvironment(macCatalyst)
            Task { @MainActor in
                await HealthStateEngine.shared.refreshSyncedHealthDataFromICloud()
                applyCatalystStressFromEngineSnapshot()
            }
            return
            #endif
            // Fetch all-time HRV SDNN samples from HealthKit
            let healthStore = HKHealthStore()
            guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
                DispatchQueue.main.async { self.loading = false }
                return
            }
            let calendar = Calendar.current
            let now = Date()
            
            // Create start date from year 2015 to capture all historical HRV data
            var startOfAllTimeComponents = DateComponents()
            startOfAllTimeComponents.year = 2015
            startOfAllTimeComponents.month = 1
            startOfAllTimeComponents.day = 1
            let startDate = calendar.date(from: startOfAllTimeComponents) ?? calendar.date(byAdding: .year, value: -10, to: now) ?? now
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { query, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    DispatchQueue.main.async { self.loading = false }
                    return
                }
                
                let msUnit = HKUnit.secondUnit(with: .milli)
                let points: [StressSessionPipeline.SdnnPoint] = samples.map {
                    StressSessionPipeline.SdnnPoint(
                        sampleUUID: $0.uuid,
                        date: $0.startDate,
                        sdnn: $0.quantity.doubleValue(for: msUnit)
                    )
                }
                StressHeartbeatRmssd.prefetchRmssdByHRVSamples(hrvSamples: samples, healthStore: healthStore) { hbMap in
                    let hrvSessions = StressSessionPipeline.buildSessions(
                        points: points,
                        heartbeatRmssdByUUID: hbMap,
                        calendar: calendar
                    )
                    let morningSessions = hrvSessions.filter { session in
                        let hour = calendar.component(.hour, from: session.date)
                        return hour >= 4 && hour <= 11
                    }
                    let dashboardSession = morningSessions.last ?? hrvSessions.last
                    DispatchQueue.main.async {
                        self.hrvHistory = hrvSessions
                        if let dash = dashboardSession {
                            self.stressScore = dash.dashboardStress
                            self.energyScore = dash.dashboardEnergy
                            self.nervousBalance = dash.dashboardRegulation
                        }
                        self.updateAggregatedData()
                        self.syncSelectedSessionToDate()
                        self.loading = false
                    }
                }
            }
            healthStore.execute(query)
        }
        
        // MARK: - Data Aggregation
        
        func updateAggregatedData() {
            switch timeFilter {
            case .hourly24:
                aggregateByHour()
            case .dailyWeek:
                aggregateByWeek()
            case .dailyMonth:
                aggregateByMonth()
            }
            
            // Ignore placeholder days (no samples) so sparse weeks/months don't skew the average toward 0.
            let measurable = aggregatedData.filter { $0.sdnn > 0.001 }
            averageValue = measurable.isEmpty ? 0 : measurable.map { $0.combinedHRV }.reduce(0, +) / Double(measurable.count)
        }
        
        func aggregateByHour() {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
            
            let dayData = hrvHistory.filter { session in
                return session.date >= startOfDay && session.date < endOfDay
            }

            #if targetEnvironment(macCatalyst)
            // Watch HRV is sparse (~few samples/day). Hourly buckets drop most hours and look “empty”; show every synced sample for the selected day.
            aggregatedData = dayData.sorted { $0.date < $1.date }
            return
            #endif
            
            var hourlyData: [HRVSession] = []
            
            for hour in 0..<24 {
                let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? Date()
                let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? Date()
                
                let hourSamples = dayData.filter { $0.date >= hourStart && $0.date < hourEnd }
                
                if !hourSamples.isEmpty {
                    let n = Double(hourSamples.count)
                    let avgSDNN = hourSamples.map { $0.sdnn }.reduce(0, +) / n
                    let avgRMSSD = hourSamples.map { $0.rmssd }.reduce(0, +) / n
                    let avgCombined = hourSamples.map { $0.combinedHRV }.reduce(0, +) / n
                    let avgLFHF = hourSamples.map { $0.lfHfProxy }.reduce(0, +) / n
                    let avgAdjusted = hourSamples.map { $0.adjustedHRV }.reduce(0, +) / n
                    let avgStress = hourSamples.map { $0.stress }.reduce(0, +) / n
                    let avgEnergy = hourSamples.map { $0.energy }.reduce(0, +) / n
                    let avgBalance = hourSamples.map { $0.nervousBalance }.reduce(0, +) / n
                    let avgBaseline = hourSamples.map { $0.baselineEMA }.reduce(0, +) / n
                    let avgCV = hourSamples.map { $0.coefficientOfVariation }.reduce(0, +) / n
                    let avgReadiness = hourSamples.map { $0.readinessBaselineSdnn }.reduce(0, +) / n
                    let avgDashboardCombined = hourSamples.map { $0.dashboardCombinedBaseline }.reduce(0, +) / n
                    let avgDashStress = hourSamples.map { $0.dashboardStress }.reduce(0, +) / n
                    let avgDashEnergy = hourSamples.map { $0.dashboardEnergy }.reduce(0, +) / n
                    let avgDashReg = hourSamples.map { $0.dashboardRegulation }.reduce(0, +) / n
                    let avgDashLf = hourSamples.map { $0.dashboardLfHfProxy }.reduce(0, +) / n
                    let hbCount = hourSamples.filter { $0.rmssdSource == .heartbeatDerived }.count
                    let aggRmssdSource: StressRmssdSource = Double(hbCount) >= Double(hourSamples.count) * 0.5 ? .heartbeatDerived : .sdnnProxy

                    let aggregatedSession = HRVSession(
                        date: hourStart,
                        sdnn: avgSDNN,
                        rmssd: avgRMSSD,
                        rmssdSource: aggRmssdSource,
                        combinedHRV: avgCombined,
                        lfHfProxy: avgLFHF,
                        coefficientOfVariation: avgCV,
                        adjustedHRV: avgAdjusted,
                        stress: avgStress,
                        energy: avgEnergy,
                        nervousBalance: avgBalance,
                        baselineEMA: avgBaseline,
                        readinessBaselineSdnn: avgReadiness,
                        dashboardCombinedBaseline: avgDashboardCombined,
                        dashboardLfHfProxy: avgDashLf,
                        dashboardStress: avgDashStress,
                        dashboardEnergy: avgDashEnergy,
                        dashboardRegulation: avgDashReg
                    )
                    hourlyData.append(aggregatedSession)
                }
            }
            
            aggregatedData = hourlyData
        }
        
        func aggregateByWeek() {
            let calendar = Calendar.current
            
            // Find the Sunday of the week containing selectedDate
            let weekday = calendar.component(.weekday, from: selectedDate)
            let daysToSubtract = weekday - 1 // Sunday is 1 in Gregorian calendar
            let startOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: selectedDate) ?? selectedDate
            let startOfWeekMidnight = calendar.startOfDay(for: startOfWeek)
            
            // End of week is the following Saturday at 23:59:59
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeekMidnight) ?? startOfWeekMidnight
            let endOfWeekEnd = calendar.date(byAdding: .day, value: 1, to: endOfWeek) ?? endOfWeek
            
            let weekData = hrvHistory.filter { session in
                return session.date >= startOfWeekMidnight && session.date < endOfWeekEnd
            }
            
            var dailyData: [HRVSession] = []
            
            for dayOffset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeekMidnight) ?? Date()
                let startOfDay = calendar.startOfDay(for: day)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
                
                let daySamples = weekData.filter { $0.date >= startOfDay && $0.date < endOfDay }
                
                if daySamples.isEmpty {
                    dailyData.append(stressPlaceholderSession(startOfDay: startOfDay))
                } else {
                    let n = Double(daySamples.count)
                    let avgSDNN = daySamples.map { $0.sdnn }.reduce(0, +) / n
                    let avgRMSSD = daySamples.map { $0.rmssd }.reduce(0, +) / n
                    let avgCombined = daySamples.map { $0.combinedHRV }.reduce(0, +) / n
                    let avgLFHF = daySamples.map { $0.lfHfProxy }.reduce(0, +) / n
                    let avgAdjusted = daySamples.map { $0.adjustedHRV }.reduce(0, +) / n
                    let avgStress = daySamples.map { $0.stress }.reduce(0, +) / n
                    let avgEnergy = daySamples.map { $0.energy }.reduce(0, +) / n
                    let avgBalance = daySamples.map { $0.nervousBalance }.reduce(0, +) / n
                    let avgBaseline = daySamples.map { $0.baselineEMA }.reduce(0, +) / n
                    let avgCV = daySamples.map { $0.coefficientOfVariation }.reduce(0, +) / n
                    let avgReadiness = daySamples.map { $0.readinessBaselineSdnn }.reduce(0, +) / n
                    let avgDashboardCombined = daySamples.map { $0.dashboardCombinedBaseline }.reduce(0, +) / n
                    let avgDashStress = daySamples.map { $0.dashboardStress }.reduce(0, +) / n
                    let avgDashEnergy = daySamples.map { $0.dashboardEnergy }.reduce(0, +) / n
                    let avgDashReg = daySamples.map { $0.dashboardRegulation }.reduce(0, +) / n
                    let avgDashLf = daySamples.map { $0.dashboardLfHfProxy }.reduce(0, +) / n
                    let hbCount = daySamples.filter { $0.rmssdSource == .heartbeatDerived }.count
                    let aggRmssdSource: StressRmssdSource = Double(hbCount) >= Double(daySamples.count) * 0.5 ? .heartbeatDerived : .sdnnProxy

                    let aggregatedSession = HRVSession(
                        date: startOfDay,
                        sdnn: avgSDNN,
                        rmssd: avgRMSSD,
                        rmssdSource: aggRmssdSource,
                        combinedHRV: avgCombined,
                        lfHfProxy: avgLFHF,
                        coefficientOfVariation: avgCV,
                        adjustedHRV: avgAdjusted,
                        stress: avgStress,
                        energy: avgEnergy,
                        nervousBalance: avgBalance,
                        baselineEMA: avgBaseline,
                        readinessBaselineSdnn: avgReadiness,
                        dashboardCombinedBaseline: avgDashboardCombined,
                        dashboardLfHfProxy: avgDashLf,
                        dashboardStress: avgDashStress,
                        dashboardEnergy: avgDashEnergy,
                        dashboardRegulation: avgDashReg
                    )
                    dailyData.append(aggregatedSession)
                }
            }
            
            aggregatedData = dailyData
        }
        
        func aggregateByMonth() {
            let calendar = Calendar.current
            
            // Get the year and month components from selectedDate
            let year = calendar.component(.year, from: selectedDate)
            let month = calendar.component(.month, from: selectedDate)
            
            // Create start of month (first day at midnight)
            var startOfMonthComponents = DateComponents()
            startOfMonthComponents.year = year
            startOfMonthComponents.month = month
            startOfMonthComponents.day = 1
            let startOfMonth = calendar.date(from: startOfMonthComponents) ?? selectedDate
            
            // Create end of month (last day at 23:59:59)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfMonth
            let endOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? nextMonth
            let endOfMonthEnd = calendar.date(byAdding: .day, value: 1, to: endOfMonth) ?? endOfMonth
            
            let monthData = hrvHistory.filter { session in
                return session.date >= startOfMonth && session.date < endOfMonthEnd
            }
            
            // Get the number of days in the month
            let daysInMonth = calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 30
            
            var dailyData: [HRVSession] = []
            
            for dayOffset in 0..<daysInMonth {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfMonth) ?? Date()
                let startOfDay = calendar.startOfDay(for: day)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
                
                let daySamples = monthData.filter { $0.date >= startOfDay && $0.date < endOfDay }
                
                if daySamples.isEmpty {
                    dailyData.append(stressPlaceholderSession(startOfDay: startOfDay))
                } else {
                    let n = Double(daySamples.count)
                    let avgSDNN = daySamples.map { $0.sdnn }.reduce(0, +) / n
                    let avgRMSSD = daySamples.map { $0.rmssd }.reduce(0, +) / n
                    let avgCombined = daySamples.map { $0.combinedHRV }.reduce(0, +) / n
                    let avgLFHF = daySamples.map { $0.lfHfProxy }.reduce(0, +) / n
                    let avgAdjusted = daySamples.map { $0.adjustedHRV }.reduce(0, +) / n
                    let avgStress = daySamples.map { $0.stress }.reduce(0, +) / n
                    let avgEnergy = daySamples.map { $0.energy }.reduce(0, +) / n
                    let avgBalance = daySamples.map { $0.nervousBalance }.reduce(0, +) / n
                    let avgBaseline = daySamples.map { $0.baselineEMA }.reduce(0, +) / n
                    let avgCV = daySamples.map { $0.coefficientOfVariation }.reduce(0, +) / n
                    let avgReadiness = daySamples.map { $0.readinessBaselineSdnn }.reduce(0, +) / n
                    let avgDashboardCombined = daySamples.map { $0.dashboardCombinedBaseline }.reduce(0, +) / n
                    let avgDashStress = daySamples.map { $0.dashboardStress }.reduce(0, +) / n
                    let avgDashEnergy = daySamples.map { $0.dashboardEnergy }.reduce(0, +) / n
                    let avgDashReg = daySamples.map { $0.dashboardRegulation }.reduce(0, +) / n
                    let avgDashLf = daySamples.map { $0.dashboardLfHfProxy }.reduce(0, +) / n
                    let hbCount = daySamples.filter { $0.rmssdSource == .heartbeatDerived }.count
                    let aggRmssdSource: StressRmssdSource = Double(hbCount) >= Double(daySamples.count) * 0.5 ? .heartbeatDerived : .sdnnProxy

                    let aggregatedSession = HRVSession(
                        date: startOfDay,
                        sdnn: avgSDNN,
                        rmssd: avgRMSSD,
                        rmssdSource: aggRmssdSource,
                        combinedHRV: avgCombined,
                        lfHfProxy: avgLFHF,
                        coefficientOfVariation: avgCV,
                        adjustedHRV: avgAdjusted,
                        stress: avgStress,
                        energy: avgEnergy,
                        nervousBalance: avgBalance,
                        baselineEMA: avgBaseline,
                        readinessBaselineSdnn: avgReadiness,
                        dashboardCombinedBaseline: avgDashboardCombined,
                        dashboardLfHfProxy: avgDashLf,
                        dashboardStress: avgDashStress,
                        dashboardEnergy: avgDashEnergy,
                        dashboardRegulation: avgDashReg
                    )
                    dailyData.append(aggregatedSession)
                }
            }
            
            aggregatedData = dailyData
        }
        
        // MARK: - Sync Selected Session to Date
        
        func syncSelectedSessionToDate() {
            guard !aggregatedData.isEmpty else { return }
            
            let calendar = Calendar.current
            
            switch timeFilter {
            case .hourly24:
                // Keep the user's selected calendar day; only move the highlighted sample (never overwrite selectedDate).
                selectedSession = aggregatedData.last
                
            case .dailyWeek:
                let selectedDayStart = calendar.startOfDay(for: selectedDate)
                if let matchingSession = aggregatedData.first(where: { session in
                    calendar.startOfDay(for: session.date) == selectedDayStart
                }) {
                    selectedSession = matchingSession
                } else {
                    selectedSession = nil
                }
                
            case .dailyMonth:
                let selectedDayStart = calendar.startOfDay(for: selectedDate)
                if let matchingSession = aggregatedData.first(where: { session in
                    calendar.startOfDay(for: session.date) == selectedDayStart
                }) {
                    selectedSession = matchingSession
                } else {
                    selectedSession = nil
                }
            }
        }
        
        // MARK: - UI Helpers
        
        func filterLabel(_ filter: TimeFilter) -> String {
            switch filter {
            case .hourly24:
                return "24H"
            case .dailyWeek:
                return "1W"
            case .dailyMonth:
                return "1M"
            }
        }
        
        func averageLabel() -> String {
            switch timeFilter {
            case .hourly24:
                return "Day Average"
            case .dailyWeek:
                return "Week Average"
            case .dailyMonth:
                return "Month Average"
            }
        }
        
    // MARK: - Stress headline + explainability
        
        struct StressHeadlineMetricsCard: View {
            let session: StressView.HRVSession
            
            /// Combined HRV baseline used for headline Stress/Energy/Regulation (matches pipeline blending).
            private var headlineBaseline: Double {
                session.dashboardCombinedBaseline
            }
            
            private var measurable: Bool {
                session.sdnn > 0.001
            }
            
            var body: some View {
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                    headlineColumn(
                        symbol: "flame",
                        title: "Stress",
                        subtitle: nil,
                        value: session.dashboardStress,
                        footnote: measurable
                            ? String(format: "proxy %.2f", session.dashboardLfHfProxy)
                            : "—"
                    )
                    Divider()
                        .frame(width: 1)
                        .background(Color.secondary.opacity(0.2))
                        .padding(.vertical, 12)
                    headlineColumn(
                        symbol: "bolt.fill",
                        title: "Energy",
                        subtitle: "Autonomic battery",
                        value: session.dashboardEnergy,
                        footnote: measurable ? relativeToMorningBaseline : "—"
                    )
                    Divider()
                        .frame(width: 1)
                        .background(Color.secondary.opacity(0.2))
                        .padding(.vertical, 12)
                    headlineColumn(
                        symbol: "heart.circle.fill",
                        title: "Regulation",
                        subtitle: nil,
                        value: session.dashboardRegulation,
                        footnote: measurable ? "vs baseline ≈ 100" : "—"
                    )
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)

                    Text("Each headline score is on a 0–100 scale.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            
            private var relativeToMorningBaseline: String {
                guard headlineBaseline > 1e-9 else { return "—" }
                let ratio = session.adjustedHRV / headlineBaseline
                return String(format: "adj. HRV %.0f%% of baseline", min(max(ratio * 100, 0), 999))
            }
            
            @ViewBuilder
            private func headlineColumn(symbol: String, title: String, subtitle: String?, value: Double, footnote: String) -> some View {
                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    Text("\(Int(min(max(value.rounded(), 0), 100))))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        
        struct StressScoresExplanation: View {
            let session: StressView.HRVSession
            
            private var headlineBaseline: Double {
                session.dashboardCombinedBaseline
            }
            
            private var recoveryStability: (recovery: Double, stability: Double) {
                StressHRVTransforms.energyBlendComponents(
                    adjustedCombined: session.adjustedHRV,
                    readinessBaselineCombined: headlineBaseline,
                    coefficientOfVariation: session.coefficientOfVariation
                )
            }
            
            private var regulationLinear: Double {
                StressHRVTransforms.regulationLinearPercent(
                    currentCombined: session.combinedHRV,
                    readinessBaselineCombined: headlineBaseline
                )
            }
            
            private var rmssdNote: String {
                switch session.rmssdSource {
                case .heartbeatDerived:
                    return "Heartbeat‑derived RMSSD."
                case .sdnnProxy:
                    return "RMSSD estimated from SDNN (Apple Watch path)."
                }
            }
            
            var body: some View {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(
                            "Stress uses the headline LF/HF proxy versus baseline RMSSD (baseline SDNN is the larger of morning‑window memory and the intraday snapshot so afternoons aren’t compared to an artificially low morning-only SDNN). The score clamps to 0–100 using anchor \(String(format: "%.2f", StressHRVTransforms.stressProxyAnchor)) and scale \(String(format: "%.0f", StressHRVTransforms.stressProxyScale)). Proxy \(String(format: "%.2f", session.dashboardLfHfProxy)) → Stress \(Int(session.dashboardStress))."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        
                        Text(
                            "Energy (autonomic battery) blends recovery = adjusted combined HRV ÷ headline baseline combined HRV (baseline \(String(format: "%.1f", headlineBaseline)) → ratio \(String(format: "%.2f", recoveryStability.recovery))) with stability = 1 − coefficient of variation (\(String(format: "%.2f", recoveryStability.stability))) at 70% / 30%, then ×100 → \(Int(session.dashboardEnergy)). \(rmssdNote)"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        
                        Text(
                            "Regulation is combined HRV ÷ headline baseline combined × 100 (here \(String(format: "%.1f", regulationLinear))), capped 0–100 → \(Int(session.dashboardRegulation)); parity with the headline baseline reads near 100."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        
                        Text(
                            "LF/HF proxy on charts (\(String(format: "%.2f", session.lfHfProxy))) uses the rolling intraday baseline; headline proxy (\(String(format: "%.2f", session.dashboardLfHfProxy))) uses the morning baseline—the Stress number follows the headline value."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Why these scores?", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
            }
        }
        
        struct StressLfHfProxiesCard: View {
            let session: StressView.HRVSession
            
            var body: some View {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                        Text("LF/HF Proxy")
                            .bold()
                            .font(.title3)
                    }
                    
                    proxyRow(label: "Headline (morning baseline)", value: session.dashboardLfHfProxy, caption: "Drives headline Stress")
                    Divider().opacity(0.35)
                    proxyRow(label: "Chart (intraday baseline)", value: session.lfHfProxy, caption: "Historical continuity on graphs")
                    
                    Text("Both compare baseline RMSSD (morning‑aware, never below the intraday snapshot SDNN) to your effective RMSSD at this sample. Near 1.0 is low sympathetic skew versus that baseline; higher values mean relatively tighter HRV vs baseline.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            }
            
            private func proxyRow(label: String, value: Double, caption: String) -> some View {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f · ref 1.00", value))
                        .bold()
                        .font(.title2)
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
}


// MARK: - Stress session pipeline (shared iOS / Catalyst)

enum StressSessionPipeline {
    struct SdnnPoint {
        let sampleUUID: UUID?
        let date: Date
        let sdnn: Double
    }

    static func buildSessions(
        points: [SdnnPoint],
        heartbeatRmssdByUUID: [UUID: Double],
        calendar: Calendar = .current
    ) -> [StressView.HRVSession] {
        var hrvSessions: [StressView.HRVSession] = []
        var sdnnValues: [Double] = []
        var baselineEMA: Double?
        var morningBaselineEMA: Double?
        var prevHRVs: [Double] = []
        let alpha = 0.3

        for point in points {
            let sdnn = point.sdnn
            let date = point.date
            sdnnValues.append(sdnn)

            let window = Array(sdnnValues.suffix(10))
            let baselineForOutlier = computeBaseline(window)
            let cleaned = removeOutliers(window, baseline: baselineForOutlier)
            let baselineSnapshot = baselineEMA ?? computeBaseline(cleaned)

            if let prev = baselineEMA {
                baselineEMA = alpha * sdnn + (1 - alpha) * prev
            } else {
                baselineEMA = sdnn
            }

            prevHRVs.append(sdnn)
            if prevHRVs.count > 10 { prevHRVs.removeFirst() }

            let hour = calendar.component(.hour, from: date)
            if hour >= 4 && hour <= 11 {
                if let prev = morningBaselineEMA {
                    morningBaselineEMA = alpha * sdnn + (1 - alpha) * prev
                } else {
                    morningBaselineEMA = sdnn
                }
            }

            let readinessBaselineSdnn = morningBaselineEMA ?? baselineSnapshot

            let hbRmssdMs: Double?
            if let id = point.sampleUUID {
                hbRmssdMs = heartbeatRmssdByUUID[id]
            } else {
                hbRmssdMs = nil
            }
            let rmEff = StressHRVTransforms.rmssdEffective(sdnn: sdnn, heartbeatRmssdMs: hbRmssdMs)

            let combinedCurrent = StressHRVTransforms.combinedHRV(sdnn: sdnn, rmssdEffective: rmEff.rmssd)
            let cv = StressHRVTransforms.coefficientOfVariation(cleaned)
            let adjustedCurrent = combinedCurrent * (1 - cv)

            let intradayBaselineRMSSD = StressHRVTransforms.estimateRMSSDFromSDNN(baselineSnapshot)
            let combinedBaselineIntraday = StressHRVTransforms.combinedHRV(sdnn: baselineSnapshot, rmssdEffective: intradayBaselineRMSSD)

            let lfIntraday = StressHRVTransforms.lfHfProxy(baselineRMSSD: intradayBaselineRMSSD, currentRMSSD: rmEff.rmssd)
            let stress = StressHRVTransforms.calculateStress(lfHfProxy: lfIntraday)
            let energy = StressHRVTransforms.calculateEnergy(
                currentAdjustedCombined: adjustedCurrent,
                readinessBaselineCombined: combinedBaselineIntraday,
                windowValues: cleaned
            )
            let nervousBalance = StressHRVTransforms.calculateRegulationScore(
                currentCombined: combinedCurrent,
                readinessBaselineCombined: combinedBaselineIntraday
            )

            let dashboardSdnnBaseline = max(readinessBaselineSdnn, baselineSnapshot)
            let dashboardBaselineRMSSD = StressHRVTransforms.estimateRMSSDFromSDNN(dashboardSdnnBaseline)
            let combinedDashboardBaseline = StressHRVTransforms.combinedHRV(sdnn: dashboardSdnnBaseline, rmssdEffective: dashboardBaselineRMSSD)

            let lfReadiness = StressHRVTransforms.lfHfProxy(baselineRMSSD: dashboardBaselineRMSSD, currentRMSSD: rmEff.rmssd)
            let dashStress = StressHRVTransforms.calculateStress(lfHfProxy: lfReadiness)
            let dashEnergy = StressHRVTransforms.calculateEnergy(
                currentAdjustedCombined: adjustedCurrent,
                readinessBaselineCombined: combinedDashboardBaseline,
                windowValues: cleaned
            )
            let dashRegulation = StressHRVTransforms.calculateRegulationScore(
                currentCombined: combinedCurrent,
                readinessBaselineCombined: combinedDashboardBaseline
            )

            let session = StressView.HRVSession(
                date: date,
                sdnn: sdnn,
                rmssd: rmEff.rmssd,
                rmssdSource: rmEff.source,
                combinedHRV: combinedCurrent,
                lfHfProxy: lfIntraday,
                coefficientOfVariation: cv,
                adjustedHRV: adjustedCurrent,
                stress: stress,
                energy: energy,
                nervousBalance: nervousBalance,
                baselineEMA: baselineEMA ?? baselineSnapshot,
                readinessBaselineSdnn: readinessBaselineSdnn,
                dashboardCombinedBaseline: combinedDashboardBaseline,
                dashboardLfHfProxy: lfReadiness,
                dashboardStress: dashStress,
                dashboardEnergy: dashEnergy,
                dashboardRegulation: dashRegulation
            )
            hrvSessions.append(session)
        }

        return hrvSessions
    }

    private static func computeBaseline(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

    private static func removeOutliers(_ values: [Double], baseline: Double) -> [Double] {
        guard values.count > 4 else { return values }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        let sd = sqrt(variance)
        let threshold = max(sd * 2, baseline * 0.1)
        return values.filter { abs($0 - mean) < threshold }
    }
}

// MARK: - Filter Button Group
struct FilterButtonGroup: View {
    @Binding var timeFilter: StressView.TimeFilter
    @Binding var selectedSession: StressView.HRVSession?
    let onFilterChange: () -> Void
    
    private let filters: [StressView.TimeFilter] = [
        .hourly24,
        .dailyWeek,
        .dailyMonth
    ]
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(filters.enumerated()), id: \.element) { index, filter in
                FilterButton(
                    filter: filter,
                    isSelected: timeFilter == filter,
                    filterLabel: labelForFilter(filter),
                    action: {
                        timeFilter = filter
                        selectedSession = nil
                        onFilterChange()
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    }
                )
            }
        }
        .padding(.horizontal)
        .frame(height: 50)
    }
    
    private func labelForFilter(_ filter: StressView.TimeFilter) -> String {
        switch filter {
        case .hourly24:
            return "24H"
        case .dailyWeek:
            return "1W"
        case .dailyMonth:
            return "1M"
        }
    }
}

// MARK: - Filter Button
struct FilterButton: View {
    let filter: StressView.TimeFilter
    let isSelected: Bool
    let filterLabel: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(filterLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(FilterButtonBackground(isSelected: isSelected))
        .buttonStyle(.glass)
        .catalystDesktopFocusable()
    }
}

// MARK: - Filter Button Background
struct FilterButtonBackground: View {
    let isSelected: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 25)
            .fill(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.1))
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.white.opacity(0.05))
                    .blur(radius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Animated Background View (completely isolated - has its own animation state)
struct AnimatedBackgroundView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        GradientBackgrounds().spiritGradient(animationPhase: .constant(animationPhase))
            .onAppear {
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
            }
    }
}
