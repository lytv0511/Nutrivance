//
//  FeelGoodScoreDetailView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 3/12/26.
//

import Foundation
import SwiftUI

struct FeelGoodScoreDetailView: View {
    @ObservedObject var engine: HealthStateEngine
    @Binding var isPresented: Bool
    @State private var animationPhase: Double = 0
    @State private var expandedCards: Set<String> = []
    @State private var expandedDescriptions: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Feel-Good Score Details")
                            .font(.largeTitle)
                            .bold()
                            .padding(.bottom, 8)
                        
                        Group {
                            componentDetail(name: "HRV (7-day)", value: engine.latestHRV, baseline: engine.hrvBaseline7Day, unit: "ms", direction: .higherIsBetter, weight: 0.25)
                            componentDetail(name: "Resting HR (7-day)", value: engine.restingHeartRate, baseline: engine.rhrBaseline7Day, unit: "bpm", direction: .lowerIsBetter, weight: 0.15)
                            componentDetail(name: "Sleep", value: engine.sleepHours, baseline: engine.sleepBaseline7Day, unit: "h", direction: .higherIsBetter, weight: 0.20)
                            componentDetail(name: "Recovery", value: engine.recoveryScore, baseline: engine.recoveryBaseline7Day, unit: "", direction: .higherIsBetter, weight: 0.20)
                            componentDetail(name: "Strain", value: engine.strainScore, baseline: engine.strainBaseline7Day, unit: "", direction: .lowerIsBetter, weight: 0.10)
                            componentDetail(name: "Circadian", value: engine.circadianHRVScore, baseline: engine.circadianBaseline7Day, unit: "", direction: .higherIsBetter, weight: 0.05)
                            componentDetail(name: "Mood", value: engine.moodScore, baseline: engine.moodBaseline7Day, unit: "", direction: .higherIsBetter, weight: 0.05)
                        }
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private func componentDetail(name: String, value: Double?, baseline: Double?, unit: String, direction: HealthStateEngine.PhysiologySignal.Direction, weight: Double) -> some View {
        if let value, let baseline {
            // Raw deviation: value - baseline
            let deviation = value - baseline
            let deviationPercent = (deviation / baseline) * 100
            
            // Determine if outcome is positive or negative
            let isPositiveOutcome = direction == .higherIsBetter ? (deviation > 0) : (deviation < 0)
            
            // Actual comparison: above or below baseline (based on deviation sign)
            let statusText = deviation > 0 ? "above" : "below"
            let impactText = isPositiveOutcome ? "increases" : "decreases"
            let significanceText = abs(deviationPercent) > 5 ? "significant" : "minor"
            
            let isExpanded = expandedCards.contains(name)
            let descriptionText = expandedDescriptions[name]

            VStack(alignment: .leading, spacing: 14) {

                // Title
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)

                // Value + Unit
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", value))
                        .font(.system(size: 36, weight: .bold))

                    if !unit.isEmpty {
                        Text("(\(unit))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Baseline + Arrow + Percent
                HStack(spacing: 6) {
                    Text("Baseline: \(String(format: "%.1f", baseline))")
                        .foregroundColor(.primary)

                    Image(systemName: deviation > 0 ? "arrow.up" : "arrow.down")
                        .foregroundColor(isPositiveOutcome ? .green : .red)

                    Text("\(String(format: "%+.1f", deviationPercent))%")
                        .foregroundColor(.secondary)
                }

                // Sparkline (simple trend visualization using baseline/value)
                GeometryReader { geo in
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height

                        let startY = h * 0.6
                        let endY = h * (0.6 - CGFloat(deviationPercent/100) * 0.5)

                        path.move(to: CGPoint(x: 0, y: startY))
                        path.addLine(to: CGPoint(x: w, y: endY))
                    }
                    .stroke(isPositiveOutcome ? Color.green : Color.red, lineWidth: 2)
                }
                .frame(height: 28)

                // Baseline range band
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseline Range")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        Capsule()
                            .fill(isPositiveOutcome ? Color.green : Color.red)
                            .frame(width: max(8, min(CGFloat(abs(deviationPercent)) * 2, 120)), height: 6)
                    }
                }

                // Impact bar (model weighting)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Impact on Score")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.blue)
                            .frame(width: CGFloat(weight) * 200, height: 6)
                    }

                    Text("Model Weight: \(Int(weight * 100))% (adaptive)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Expandable explanation
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status: \(significanceText.capitalized) change \(statusText) baseline.")
                            .font(.subheadline)

                        Text("This \(impactText) your Feel‑Good Score based on how this metric compares to your personal baseline.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let desc = descriptionText {
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12))
            )
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            .padding(.vertical, 4)
            .onTapGesture {
                if expandedCards.contains(name) {
                    expandedCards.remove(name)
                    expandedDescriptions.removeValue(forKey: name)
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                } else {
                    addExpandedCardWithDescription(name: name, deviation: deviation, isPositiveOutcome: isPositiveOutcome, significanceText: significanceText)
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }
            }
        } else {
            EmptyView()
        }
    }
    
    private func addExpandedCardWithDescription(name: String, deviation: Double, isPositiveOutcome: Bool, significanceText: String) {
        if let metric = MetricDetail.allMetrics(significanceText: significanceText)[name] {
            expandedCards.insert(name)
            expandedDescriptions[name] = metric.description
        }
    }
}

struct MetricDetail {
    let name: String
    let description: String
    let higherIsBetter: Bool
}

extension MetricDetail {
    static func allMetrics(significanceText: String) -> [String: MetricDetail] {
        return [
            "HRV (7-day)": MetricDetail(
                name: "HRV (7-day)",
                description: "Heart Rate Variability measures your nervous system balance. Higher HRV is generally better, indicating better recovery and stress resilience. This change is considered \(significanceText) and could be influenced by sleep, stress, or recent activity.",
                higherIsBetter: true
            ),
            "Resting HR (7-day)": MetricDetail(
                name: "Resting HR (7-day)",
                description: "Resting Heart Rate shows how efficiently your heart is working at rest. Lower RHR is generally better, indicating good cardiovascular fitness. This change is \(significanceText) and may be affected by recent exercise, stress, or illness.",
                higherIsBetter: false
            ),
            "Sleep": MetricDetail(
                name: "Sleep",
                description: "Sleep duration affects recovery, mood, and energy. Higher sleep is generally better. This change is \(significanceText) and could be caused by changes in bedtime, environment, or stress.",
                higherIsBetter: true
            ),
            "Recovery": MetricDetail(
                name: "Recovery",
                description: "Recovery score indicates how prepared your body is to perform. Higher is better. This change is \(significanceText) and may relate to sleep, nutrition, or recent strain.",
                higherIsBetter: true
            ),
            "Strain": MetricDetail(
                name: "Strain",
                description: "Strain measures how much physical or mental load your body is under. Lower is better to avoid fatigue. This change is \(significanceText) and can be due to workouts, stress, or lifestyle factors.",
                higherIsBetter: false
            ),
            "Circadian": MetricDetail(
                name: "Circadian",
                description: "Circadian HRV Score reflects alignment with your natural daily rhythms. Higher is generally better. This change is \(significanceText) and may be affected by light exposure, sleep timing, or activity.",
                higherIsBetter: true
            ),
            "Mood": MetricDetail(
                name: "Mood",
                description: "Mood score reflects your current emotional state. Higher is better. This change is \(significanceText) and could be influenced by sleep, stress, or social interactions.",
                higherIsBetter: true
            )
        ]
    }
}
