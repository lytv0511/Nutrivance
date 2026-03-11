//
//  StressView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

// Fetch 10 days of HRV SSDN, compatue baseline HRV (median), convert to RMSSD estimate
// Basic: HRV SDNN → cleaned → RMSSD estimate → baseline → LF/HF proxy → stress/energy/balance

import SwiftUI
import Charts
import HealthKit

struct StressView: View {
    
    struct HRVSession: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let sdnn: Double
        let rmssd: Double
        let combinedHRV: Double
        let lfHfProxy: Double
        let coefficientOfVariation: Double
        let adjustedHRV: Double
        let stress: Double
        let energy: Double
        let nervousBalance: Double
        let baselineEMA: Double
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
    
    @State private var timeFilter: TimeFilter = .dailyMonth
    @State private var selectedDate: Date = Date()
    @State private var selectedSession: HRVSession?
    @State private var aggregatedData: [HRVSession] = []
    @State private var averageValue: Double = 0
    
    var body: some View {
        return NavigationView {
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
                                onFilterChange: updateAggregatedData
                            )
                            
                            // Calendar picker for specific date
                            DatePicker(
                                "Select Date",
                                selection: $selectedDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .onChange(of: selectedDate) { _ in
                                updateAggregatedData()
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                            }
                            .padding(.horizontal)
                            
                            // Chart View
                            if aggregatedData.count > 0 {
                                VStack(spacing: 12) {
                                    if timeFilter == .dailyMonth {
                                        MonthlyChartView(
                                            aggregatedData: aggregatedData,
                                            selectedSession: $selectedSession,
                                            onChartTap: handleChartTap(at:)
                                        )
                                    } else {
                                        HourlyWeeklyChartView(
                                            aggregatedData: aggregatedData,
                                            selectedSession: $selectedSession,
                                            timeFilter: timeFilter,
                                            onChartTap: handleChartTap(at:)
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
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.tertiarySystemBackground)))
                                }
                                .padding(.horizontal)
                            } else {
                                Text("No data available for selected period")
                                    .foregroundColor(.secondary)
                                    .frame(height: 200)
                            }
                            
                            // Current/Selected metrics card (only show if selected)
                            if let selected = selectedSession {
                                HStackMetricsCard(
                                    stressScore: selected.stress,
                                    stressBaseline: 50,
                                    energyScore: selected.energy,
                                    energyBaseline: 50,
                                    nervousBalance: selected.nervousBalance,
                                    nervousBalanceBaseline: 100
                                )
                                .padding(.horizontal)
                                
                                // Show detailed metric cards for selected point
                                LazyVGrid(columns: [GridItem(.flexible())], spacing: 22) {
                                    MetricCard(
                                        title: "RMSSD",
                                        symbol: "waveform.path.ecg",
                                        currentValue: selected.rmssd,
                                        baselineValue: estimateRMSSD(from: selected.baselineEMA),
                                        unit: "",
                                        explanation: "RMSSD (Root Mean Square of Successive Differences) is a measure of short-term heart rate variability. Higher RMSSD typically reflects a healthy, resilient nervous system and better stress recovery. Lower values can indicate fatigue or stress."
                                    )
                                    MetricCard(
                                        title: "SDNN",
                                        symbol: "chart.bar.doc.horizontal",
                                        currentValue: selected.sdnn,
                                        baselineValue: selected.baselineEMA,
                                        unit: "",
                                        explanation: "SDNN (Standard Deviation of NN intervals) measures the overall variability in your heartbeat intervals. Higher SDNN generally means your body is adapting well to daily stressors, while lower values may suggest increased stress or reduced recovery."
                                    )
                                    MetricCard(
                                        title: "Combined HRV",
                                        symbol: "circle.grid.cross",
                                        currentValue: selected.combinedHRV,
                                        baselineValue: combinedHRV(current: selected.baselineEMA, baseline: selected.baselineEMA),
                                        unit: "",
                                        explanation: "Combined HRV is a weighted score using both RMSSD and SDNN, providing a broader view of your heart's adaptability. A higher combined HRV usually reflects good recovery and a balanced nervous system."
                                    )
                                    MetricCard(
                                        title: "LF/HF Proxy",
                                        symbol: "arrow.left.arrow.right",
                                        currentValue: selected.lfHfProxy,
                                        baselineValue: 1.0,
                                        unit: "",
                                        explanation: "The LF/HF Proxy estimates the balance between sympathetic (stress) and parasympathetic (recovery) activity in your body. Values farther from 1 can indicate an imbalance, possibly from stress or overtraining."
                                    )
                                    MetricCard(
                                        title: "Adjusted HRV",
                                        symbol: "shield.lefthalf.fill",
                                        currentValue: selected.adjustedHRV,
                                        baselineValue: combinedHRV(current: selected.baselineEMA, baseline: selected.baselineEMA),
                                        unit: "",
                                        explanation: "Adjusted HRV accounts for how stable your HRV is over time, not just its level. It helps filter out random fluctuations, giving a more reliable picture of your body's stress and recovery state."
                                    )
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding()
                    .onAppear {
                        loadStressMetrics()
                    }
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
                        selectedDate = Date()
                        updateAggregatedData()
                        syncSelectedSessionToDate()
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }) {
                        Text("Today")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        let calendar = Calendar.current
                        let increment: Int
                        let unit: Calendar.Component
                        
                        switch timeFilter {
                        case .hourly24:
                            increment = -1
                            unit = .day
                        case .dailyWeek:
                            increment = -1
                            unit = .weekOfYear
                        case .dailyMonth:
                            increment = -1
                            unit = .month
                        }
                        
                        if let newDate = calendar.date(byAdding: unit, value: increment, to: selectedDate) {
                            selectedDate = newDate
                            updateAggregatedData()
                            syncSelectedSessionToDate()
                        }
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(.body, design: .rounded))
                    }
                    
                    Button(action: {
                        let calendar = Calendar.current
                        let increment: Int
                        let unit: Calendar.Component
                        
                        switch timeFilter {
                        case .hourly24:
                            increment = 1
                            unit = .day
                        case .dailyWeek:
                            increment = 1
                            unit = .weekOfYear
                        case .dailyMonth:
                            increment = 1
                            unit = .month
                        }
                        
                        if let newDate = calendar.date(byAdding: unit, value: increment, to: selectedDate) {
                            // Don't allow going past today
                            if newDate <= Date() {
                                selectedDate = newDate
                                updateAggregatedData()
                                syncSelectedSessionToDate()
                            }
                        }
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(.body, design: .rounded))
                    }
                }
            }
        }
    }
    
    // MARK: - Monthly Chart View
    struct MonthlyChartView: View {
        let aggregatedData: [StressView.HRVSession]
        @Binding var selectedSession: StressView.HRVSession?
        let onChartTap: (CGPoint) -> Void
        
        let chartWidth: CGFloat = 800
        
        var body: some View {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        MonthlyChartContent(
                            aggregatedData: aggregatedData,
                            selectedSession: selectedSession
                        )
                        
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
                            .frame(width: chartWidth)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    onChartTap(location)
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
    }
    
    // MARK: - Monthly Chart Content
    struct MonthlyChartContent: View {
        let aggregatedData: [StressView.HRVSession]
        let selectedSession: StressView.HRVSession?
        
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
            .frame(minWidth: 800)
            .padding()
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 10)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                }
            }
        }
    }
    
    // MARK: - Hourly/Weekly Chart View
    struct HourlyWeeklyChartView: View {
        let aggregatedData: [StressView.HRVSession]
        @Binding var selectedSession: StressView.HRVSession?
        let timeFilter: StressView.TimeFilter
        let onChartTap: (CGPoint) -> Void
        
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
            .contentShape(Rectangle())
            .onTapGesture { location in
                onChartTap(location)
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
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            }
        }
        
        // MARK: - Load HRV Data
        
        func loadStressMetrics() {
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
                
                // Extract SDNN values and dates
                var hrvSessions: [HRVSession] = []
                var sdnnValues: [Double] = []
                var baselineEMA: Double?
                var prevHRVs: [Double] = []
                let alpha = 0.3
                // Process each sample in order
                for sample in samples {
                    let sdnn = sample.quantity.doubleValue(for: .init(from: "ms"))
                    let date = sample.startDate
                    sdnnValues.append(sdnn)
                    
                    // Compute cleaned window for baseline/trend, using last 10 values
                    let window = Array(sdnnValues.suffix(10))
                    let baselineForOutlier = computeBaseline(window)
                    let cleaned = removeOutliers(window, baseline: baselineForOutlier)
                    let baseline = baselineEMA ?? computeBaseline(cleaned)
                    // Update baseline EMA
                    if let prev = baselineEMA {
                        baselineEMA = alpha * sdnn + (1 - alpha) * prev
                    } else {
                        baselineEMA = sdnn
                    }
                    prevHRVs.append(sdnn)
                    if prevHRVs.count > 10 { prevHRVs.removeFirst() }
                    let trendSlope = (prevHRVs.last ?? sdnn) - (prevHRVs.first ?? sdnn)
                    // Combined HRV
                    let combinedCurrentHRV = combinedHRV(current: sdnn, baseline: baseline)
                    let adjustedCurrentHRV = combinedCurrentHRV * (1 - coefficientOfVariation(cleaned))
                    let combinedBaselineHRV = combinedHRV(current: baseline, baseline: baseline)
                    let currentRMSSD = estimateRMSSD(from: sdnn)
                    let baselineRMSSD = estimateRMSSD(from: baseline)
                    let lfHfProxy = pow(baselineRMSSD / max(currentRMSSD, 1e-5), 0.7)
                    let stress = calculateStress(current: adjustedCurrentHRV, baseline: combinedBaselineHRV, lfHfProxy: lfHfProxy)
                    let energy = calculateEnergy(current: adjustedCurrentHRV, baseline: combinedBaselineHRV, values: cleaned)
                    let balance = calculateNervousBalance(current: combinedCurrentHRV, baseline: combinedBaselineHRV)
                    let cv = coefficientOfVariation(cleaned)
                    let session = HRVSession(
                        date: date,
                        sdnn: sdnn,
                        rmssd: currentRMSSD,
                        combinedHRV: combinedCurrentHRV,
                        lfHfProxy: lfHfProxy,
                        coefficientOfVariation: cv,
                        adjustedHRV: adjustedCurrentHRV,
                        stress: stress,
                        energy: energy,
                        nervousBalance: balance,
                        baselineEMA: baselineEMA ?? baseline
                    )
                    hrvSessions.append(session)
                }
                
                // Pick the most significant session for dashboard: latest morning session, or last
                let calendar = Calendar.current
                let morningSessions = hrvSessions.filter { session in
                    let hour = calendar.component(.hour, from: session.date)
                    return hour >= 4 && hour <= 11
                }
                let dashboardSession = morningSessions.last ?? hrvSessions.last
                DispatchQueue.main.async {
                    self.hrvHistory = hrvSessions
                    if let dash = dashboardSession {
                        self.stressScore = dash.stress
                        self.energyScore = dash.energy
                        self.nervousBalance = dash.nervousBalance
                    }
                    self.selectedDate = Date()
                    self.updateAggregatedData()
                    self.loading = false
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
            
            // Calculate average
            averageValue = aggregatedData.map { $0.combinedHRV }.reduce(0, +) / Double(max(aggregatedData.count, 1))
        }
        
        func aggregateByHour() {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
            
            let dayData = hrvHistory.filter { session in
                return session.date >= startOfDay && session.date < endOfDay
            }
            
            var hourlyData: [HRVSession] = []
            
            for hour in 0..<24 {
                let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? Date()
                let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? Date()
                
                let hourSamples = dayData.filter { $0.date >= hourStart && $0.date < hourEnd }
                
                if !hourSamples.isEmpty {
                    let avgSDNN = hourSamples.map { $0.sdnn }.reduce(0, +) / Double(hourSamples.count)
                    let avgRMSSD = hourSamples.map { $0.rmssd }.reduce(0, +) / Double(hourSamples.count)
                    let avgCombined = hourSamples.map { $0.combinedHRV }.reduce(0, +) / Double(hourSamples.count)
                    let avgLFHF = hourSamples.map { $0.lfHfProxy }.reduce(0, +) / Double(hourSamples.count)
                    let avgAdjusted = hourSamples.map { $0.adjustedHRV }.reduce(0, +) / Double(hourSamples.count)
                    let avgStress = hourSamples.map { $0.stress }.reduce(0, +) / Double(hourSamples.count)
                    let avgEnergy = hourSamples.map { $0.energy }.reduce(0, +) / Double(hourSamples.count)
                    let avgBalance = hourSamples.map { $0.nervousBalance }.reduce(0, +) / Double(hourSamples.count)
                    let avgBaseline = hourSamples.map { $0.baselineEMA }.reduce(0, +) / Double(hourSamples.count)
                    let avgCV = hourSamples.map { $0.coefficientOfVariation }.reduce(0, +) / Double(hourSamples.count)
                    
                    let aggregatedSession = HRVSession(
                        date: hourStart,
                        sdnn: avgSDNN,
                        rmssd: avgRMSSD,
                        combinedHRV: avgCombined,
                        lfHfProxy: avgLFHF,
                        coefficientOfVariation: avgCV,
                        adjustedHRV: avgAdjusted,
                        stress: avgStress,
                        energy: avgEnergy,
                        nervousBalance: avgBalance,
                        baselineEMA: avgBaseline
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
                
                if !daySamples.isEmpty {
                    let avgSDNN = daySamples.map { $0.sdnn }.reduce(0, +) / Double(daySamples.count)
                    let avgRMSSD = daySamples.map { $0.rmssd }.reduce(0, +) / Double(daySamples.count)
                    let avgCombined = daySamples.map { $0.combinedHRV }.reduce(0, +) / Double(daySamples.count)
                    let avgLFHF = daySamples.map { $0.lfHfProxy }.reduce(0, +) / Double(daySamples.count)
                    let avgAdjusted = daySamples.map { $0.adjustedHRV }.reduce(0, +) / Double(daySamples.count)
                    let avgStress = daySamples.map { $0.stress }.reduce(0, +) / Double(daySamples.count)
                    let avgEnergy = daySamples.map { $0.energy }.reduce(0, +) / Double(daySamples.count)
                    let avgBalance = daySamples.map { $0.nervousBalance }.reduce(0, +) / Double(daySamples.count)
                    let avgBaseline = daySamples.map { $0.baselineEMA }.reduce(0, +) / Double(daySamples.count)
                    let avgCV = daySamples.map { $0.coefficientOfVariation }.reduce(0, +) / Double(daySamples.count)
                    
                    let aggregatedSession = HRVSession(
                        date: startOfDay,
                        sdnn: avgSDNN,
                        rmssd: avgRMSSD,
                        combinedHRV: avgCombined,
                        lfHfProxy: avgLFHF,
                        coefficientOfVariation: avgCV,
                        adjustedHRV: avgAdjusted,
                        stress: avgStress,
                        energy: avgEnergy,
                        nervousBalance: avgBalance,
                        baselineEMA: avgBaseline
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
                
                if !daySamples.isEmpty {
                    let avgSDNN = daySamples.map { $0.sdnn }.reduce(0, +) / Double(daySamples.count)
                    let avgRMSSD = daySamples.map { $0.rmssd }.reduce(0, +) / Double(daySamples.count)
                    let avgCombined = daySamples.map { $0.combinedHRV }.reduce(0, +) / Double(daySamples.count)
                    let avgLFHF = daySamples.map { $0.lfHfProxy }.reduce(0, +) / Double(daySamples.count)
                    let avgAdjusted = daySamples.map { $0.adjustedHRV }.reduce(0, +) / Double(daySamples.count)
                    let avgStress = daySamples.map { $0.stress }.reduce(0, +) / Double(daySamples.count)
                    let avgEnergy = daySamples.map { $0.energy }.reduce(0, +) / Double(daySamples.count)
                    let avgBalance = daySamples.map { $0.nervousBalance }.reduce(0, +) / Double(daySamples.count)
                    let avgBaseline = daySamples.map { $0.baselineEMA }.reduce(0, +) / Double(daySamples.count)
                    let avgCV = daySamples.map { $0.coefficientOfVariation }.reduce(0, +) / Double(daySamples.count)
                    
                    let aggregatedSession = HRVSession(
                        date: startOfDay,
                        sdnn: avgSDNN,
                        rmssd: avgRMSSD,
                        combinedHRV: avgCombined,
                        lfHfProxy: avgLFHF,
                        coefficientOfVariation: avgCV,
                        adjustedHRV: avgAdjusted,
                        stress: avgStress,
                        energy: avgEnergy,
                        nervousBalance: avgBalance,
                        baselineEMA: avgBaseline
                    )
                    dailyData.append(aggregatedSession)
                }
            }
            
            aggregatedData = dailyData
        }
        
        // MARK: - Chart Interaction
        
        func handleChartTap(at location: CGPoint) {
            // Find the closest data point to the tap location
            guard !aggregatedData.isEmpty else { return }
            
            // For simplicity, cycle through the data or find nearest
            // A more sophisticated approach would use chart coordinates
            if let current = selectedSession {
                if let index = aggregatedData.firstIndex(where: { $0.id == current.id }) {
                    let nextIndex = (index + 1) % aggregatedData.count
                    selectedSession = aggregatedData[nextIndex]
                    // Only update selectedDate for weekly/monthly views, not for 24H
                    if timeFilter != .hourly24 {
                        selectedDate = aggregatedData[nextIndex].date
                    }
                }
            } else {
                selectedSession = aggregatedData.first
                // Only update selectedDate for weekly/monthly views, not for 24H
                if timeFilter != .hourly24 {
                    if let firstSession = aggregatedData.first {
                        selectedDate = firstSession.date
                    }
                }
            }
            
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
        
        // MARK: - Sync Selected Session to Date
        
        func syncSelectedSessionToDate() {
            guard !aggregatedData.isEmpty else { return }
            
            let calendar = Calendar.current
            
            switch timeFilter {
            case .hourly24:
                // For hourly view, select the first data point of the selected day
                selectedSession = aggregatedData.first
                
            case .dailyWeek:
                // For weekly view, find the data point that matches the selected date
                let selectedDayStart = calendar.startOfDay(for: selectedDate)
                if let matchingSession = aggregatedData.first(where: { session in
                    calendar.startOfDay(for: session.date) == selectedDayStart
                }) {
                    selectedSession = matchingSession
                } else {
                    // If no exact match, select the first available
                    selectedSession = aggregatedData.first
                }
                
            case .dailyMonth:
                // For monthly view, find the data point that matches the selected date
                let selectedDayStart = calendar.startOfDay(for: selectedDate)
                if let matchingSession = aggregatedData.first(where: { session in
                    calendar.startOfDay(for: session.date) == selectedDayStart
                }) {
                    selectedSession = matchingSession
                } else {
                    // If no exact match, select the first available
                    selectedSession = aggregatedData.first
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
        
        // MARK: - Baseline Calculation
        
        func computeBaseline(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            
            if sorted.count % 2 == 0 {
                return (sorted[mid - 1] + sorted[mid]) / 2
            } else {
                return sorted[mid]
            }
        }
        
        func estimateRMSSD(from sdnn: Double) -> Double {
            return sdnn * 0.85
        }
        
        func coefficientOfVariation(_ values: [Double]) -> Double {
            
            let mean = values.reduce(0,+) / Double(values.count)
            
            let variance = values.map {
                pow($0 - mean, 2)
            }.reduce(0,+) / Double(values.count)
            
            let sd = sqrt(variance)
            
            return sd / mean
        }
        
        func removeOutliers(_ values: [Double], baseline: Double) -> [Double] {
            
            guard values.count > 4 else { return values }
            
            let mean = values.reduce(0,+) / Double(values.count)
            
            let variance = values.map {
                pow($0 - mean,2)
            }.reduce(0,+) / Double(values.count)
            
            let sd = sqrt(variance)
            
            // Use baseline-adaptive threshold (e.g. 2 * baseline * 0.1)
            let threshold = max(sd * 2, baseline * 0.1)
            
            return values.filter {
                abs($0 - mean) < threshold
            }
        }
        
        func isMeasurementQualityGood(_ values: [Double]) -> Bool {
            
            guard values.count >= 3 else { return false }
            
            let cv = coefficientOfVariation(values)
            
            // Apple Watch HRV is noisy
            if cv > 0.60 { return false }
            
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 0
            
            // artifact detection
            if maxVal - minVal > 120 { return false }
            
            return true
        }
        
        // MARK: - Stress Score
        
        func calculateStress(current: Double, baseline: Double, lfHfProxy: Double) -> Double {
            
            let score = (lfHfProxy - 0.5) * 80
            
            return min(max(score,0),100)
        }
        
        // MARK: - Nervous Balance
        
        func calculateNervousBalance(current: Double, baseline: Double) -> Double {
            
            let ratio = current / baseline
            
            let score = ratio * 100
            
            return min(max(score,0),120)
        }
        
        func calculateEnergy(current: Double, baseline: Double, values: [Double]) -> Double {
            
            let recovery = (current / baseline)
            
            let cv = coefficientOfVariation(values)
            
            let stability = max(0, 1 - cv)
            
            let energy = recovery * 0.7 + stability * 0.3
            
            return min(max(energy * 100,0),100)
        }
        
        func combinedHRV(current: Double, baseline: Double) -> Double {
            let rmssdCurrent = estimateRMSSD(from: current)
            let rmssdBaseline = estimateRMSSD(from: baseline)
            
            // SDNN is current and baseline as is
            // Combine weighted 0.7 RMSSD + 0.3 SDNN (using current and baseline as needed)
            return 0.7 * rmssdCurrent + 0.3 * current
        }
    }
    
    // MARK: - HStack Metrics Card for Stress/Energy/Balance
    struct HStackMetricsCard: View {
        let stressScore: Double
        let stressBaseline: Double
        let energyScore: Double
        let energyBaseline: Double
        let nervousBalance: Double
        let nervousBalanceBaseline: Double
        
        var body: some View {
            HStack(spacing: 0) {
                metricSection(
                    symbol: "flame",
                    title: "Stress",
                    value: Int(stressScore),
                    baseline: Int(stressBaseline)
                )
                Divider()
                    .frame(width: 1)
                    .background(Color.secondary.opacity(0.2))
                    .padding(.vertical, 12)
                metricSection(
                    symbol: "bolt",
                    title: "Energy",
                    value: Int(energyScore),
                    baseline: Int(energyBaseline)
                )
                Divider()
                    .frame(width: 1)
                    .background(Color.secondary.opacity(0.2))
                    .padding(.vertical, 12)
                metricSection(
                    symbol: "heart",
                    title: "Regulation",
                    value: Int(nervousBalance),
                    baseline: Int(nervousBalanceBaseline)
                )
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
        }
        
        @ViewBuilder
        private func metricSection(symbol: String, title: String, value: Int, baseline: Int) -> some View {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(value)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("(\(baseline))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }


// MARK: - Filter Button Group
struct FilterButtonGroup: View {
    @Binding var timeFilter: StressView.TimeFilter
    @Binding var selectedSession: StressView.HRVSession?
    let onFilterChange: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach([StressView.TimeFilter.hourly24, StressView.TimeFilter.dailyWeek, StressView.TimeFilter.dailyMonth], id: \.self) { filter in
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
