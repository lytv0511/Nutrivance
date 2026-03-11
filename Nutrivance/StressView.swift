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

    struct HRVSession: Identifiable {
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

    @State private var stressScore: Double = 0
    @State private var energyScore: Double = 0
    @State private var nervousBalance: Double = 0

    @State private var loading = true
    
    @State private var baselineEMA: Double?
    @State private var previousHRVs: [Double] = []
    @State private var hrvHistory: [HRVSession] = []
    @State private var animationPhase: Double = 0

    var body: some View {
        ZStack {
            // Dreamy sleep background
            GradientBackgrounds().spiritGradient(animationPhase: $animationPhase)
                .onAppear {
                    withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                        animationPhase = 20
                    }
                }
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 30) {
                    if loading {
                        ProgressView("Analyzing HRV...")
                    } else {
                        // Chart View for historical metrics
                        if hrvHistory.count > 1 {
                            Chart {
                                ForEach(hrvHistory) { session in
                                    LineMark(
                                        x: .value("Date", session.date),
                                        y: .value("SDNN", session.sdnn)
                                    )
                                    .foregroundStyle(.blue)
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Date", session.date),
                                        y: .value("RMSSD", session.rmssd)
                                    )
                                    .foregroundStyle(.green)
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Date", session.date),
                                        y: .value("Combined HRV", session.combinedHRV)
                                    )
                                    .foregroundStyle(.orange)
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Date", session.date),
                                        y: .value("Baseline EMA", session.baselineEMA)
                                    )
                                    .foregroundStyle(.red)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .frame(height: 200)
                            .padding()
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                                }
                            }
                        } else {
                            Text("Not enough data to display chart")
                                .foregroundColor(.secondary)
                                .frame(height: 200)
                        }
                        
                        // Current metrics card with all three scores
                        HStackMetricsCard(
                            stressScore: stressScore,
                            stressBaseline: hrvHistory.last?.baselineEMA ?? 0,
                            energyScore: energyScore,
                            energyBaseline: hrvHistory.last.map { calculateEnergy(current: $0.combinedHRV, baseline: combinedHRV(current: $0.baselineEMA, baseline: $0.baselineEMA), values: previousHRVs) } ?? 0,
                            nervousBalance: nervousBalance,
                            nervousBalanceBaseline: hrvHistory.last.map { calculateNervousBalance(current: $0.combinedHRV, baseline: combinedHRV(current: $0.baselineEMA, baseline: $0.baselineEMA)) } ?? 0
                        )
                        .padding(.horizontal)
                        
                        // Historical metrics cards: now single column, more padding and symbols, longer explanations
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 22) {
                            ForEach(hrvHistory.reversed()) { session in
                                MetricCard(
                                    title: "RMSSD",
                                    symbol: "waveform.path.ecg",
                                    currentValue: session.rmssd,
                                    baselineValue: estimateRMSSD(from: session.baselineEMA),
                                    unit: "",
                                    explanation: "RMSSD (Root Mean Square of Successive Differences) is a measure of short-term heart rate variability. Higher RMSSD typically reflects a healthy, resilient nervous system and better stress recovery. Lower values can indicate fatigue or stress."
                                )
                                MetricCard(
                                    title: "SDNN",
                                    symbol: "chart.bar.doc.horizontal",
                                    currentValue: session.sdnn,
                                    baselineValue: session.baselineEMA,
                                    unit: "",
                                    explanation: "SDNN (Standard Deviation of NN intervals) measures the overall variability in your heartbeat intervals. Higher SDNN generally means your body is adapting well to daily stressors, while lower values may suggest increased stress or reduced recovery."
                                )
                                MetricCard(
                                    title: "Combined HRV",
                                    symbol: "circle.grid.cross",
                                    currentValue: session.combinedHRV,
                                    baselineValue: combinedHRV(current: session.baselineEMA, baseline: session.baselineEMA),
                                    unit: "",
                                    explanation: "Combined HRV is a weighted score using both RMSSD and SDNN, providing a broader view of your heart’s adaptability. A higher combined HRV usually reflects good recovery and a balanced nervous system."
                                )
                                MetricCard(
                                    title: "LF/HF Proxy",
                                    symbol: "arrow.left.arrow.right",
                                    currentValue: session.lfHfProxy,
                                    baselineValue: 1.0,
                                    unit: "",
                                    explanation: "The LF/HF Proxy estimates the balance between sympathetic (stress) and parasympathetic (recovery) activity in your body. Values farther from 1 can indicate an imbalance, possibly from stress or overtraining."
                                )
                                MetricCard(
                                    title: "Adjusted HRV",
                                    symbol: "shield.lefthalf.fill",
                                    currentValue: session.adjustedHRV,
                                    baselineValue: combinedHRV(current: session.baselineEMA, baseline: session.baselineEMA),
                                    unit: "",
                                    explanation: "Adjusted HRV accounts for how stable your HRV is over time, not just its level. It helps filter out random fluctuations, giving a more reliable picture of your body’s stress and recovery state."
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding()
                .onAppear {
                    loadStressMetrics()
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
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
        }
    }

    // MARK: - Load HRV Data

    func loadStressMetrics() {
        // Fetch last 30 days of HRV SDNN samples from HealthKit
        let healthStore = HKHealthStore()
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            DispatchQueue.main.async { self.loading = false }
            return
        }
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -30, to: now) else {
            DispatchQueue.main.async { self.loading = false }
            return
        }
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
                self.loading = false
            }
        }
        healthStore.execute(query)
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
                    title: "Health",
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
