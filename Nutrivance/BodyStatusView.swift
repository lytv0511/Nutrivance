//
//  BodyStatusView.swift
//  Nutrivance
//
//  Body Status — a composite 0–100 score for pro athletes from sleep, HRV, load,
//  circadian time awake, sympathetic load, and related signals. It can trend down
//  through the day from activity and time awake even when overnight HRV looks strong.
//

import SwiftUI
import Charts
import HealthKit

// MARK: - Model

struct BodyStatusModel {
    /// Current composite status level, 0–100.
    let level: Double
    /// Post-sleep starting level for today, 0–100.
    let morningLevel: Double

    // -- Drain components --
    let activityDrain: Double     // 0–50 (training load)
    let circadianDrain: Double    // 0–20 (time since wake)
    let stressDrain: Double       // 0–15 (HRV suppression vs morning)
    let rhrPenalty: Double        // 0–12 (elevated RHR vs 7-day baseline)

    // -- Recharge / mitigation components --
    let mindfulnessBonus: Double  // 0–8  (mindfulness minutes today)
    let hrvTrendBonus: Double     // 0–8  (positive HRV trend supports the score)

    // -- Source signals for display --
    let sleepHours: Double?
    let sleepEfficiency: Double?
    let morningHRV: Double?
    let currentHRV: Double?
    let hoursAwake: Double
    let todayWorkoutCount: Int
    let todayTotalLoad: Double
    let rhrBaseline: Double?
    let currentRHR: Double?

    // -- Charts --
    let sevenDayStatus: [(Date, Double)]
    let intradayCurve: [(Date, Double)]

    static let empty = BodyStatusModel(
        level: 0, morningLevel: 0,
        activityDrain: 0, circadianDrain: 0, stressDrain: 0, rhrPenalty: 0,
        mindfulnessBonus: 0, hrvTrendBonus: 0,
        sleepHours: nil, sleepEfficiency: nil, morningHRV: nil, currentHRV: nil,
        hoursAwake: 0, todayWorkoutCount: 0, todayTotalLoad: 0,
        rhrBaseline: nil, currentRHR: nil,
        sevenDayStatus: [], intradayCurve: []
    )
}

// MARK: - Engine

/// Computes the Body Status model from HealthStateEngine on the main actor.
@MainActor
func computeBodyStatus(engine: HealthStateEngine) -> BodyStatusModel {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let now = Date()

    // ── Sleep recharge ──────────────────────────────────────────────
    let sleepH: Double = engine.anchoredSleepDuration[today] ?? engine.readinessSleepDuration ?? 0
    let rawEff: Double = engine.sleepEfficiency[today] ?? engine.readinessSleepEfficiency ?? 0.85
    let eff = max(0.0, min(1.0, rawEff))
    // Sleep quality: proportion of goal (8 h) scaled by efficiency
    let sleepQuality = min(1.0, sleepH / 8.0) * (eff * 0.70 + 0.30)
    // Base charge from sleep, floors at 5 so zero-sleep still shows a value
    let baseCharge = sleepQuality * 90 + 5

    // HRV quality multiplier: if morning HRV is above baseline, the morning level starts higher
    let morningHRV: Double? = engine.readinessEffectHRV ?? engine.readinessHRV
    let hrvBaseline = engine.hrvBaseline7Day ?? engine.hrvBaseline60Day?.mean ?? 50.0
    let hrvFactor = morningHRV.map { min(1.25, max(0.60, $0 / max(hrvBaseline, 1.0))) } ?? 1.0
    let morningCharge = min(100.0, baseCharge * hrvFactor)

    // ── Activity drain ───────────────────────────────────────────────
    let todayWorkouts = engine.workoutAnalytics.filter {
        cal.isDate($0.workout.startDate, inSameDayAs: now)
    }
    let todayLoad = todayWorkouts.reduce(0.0) {
        $0 + HealthStateEngine.proWorkoutLoad(
            for: $1.workout,
            analytics: $1.analytics,
            estimatedMaxHeartRate: engine.estimatedMaxHeartRate
        )
    }
    let activityDrain = min(50.0, todayLoad * 0.70)

    // ── Circadian drain ──────────────────────────────────────────────
    // Natural energy depletion since waking (independent of HRV)
    let wakeTime: Date = engine.lastSleepEnd
        ?? cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
    let hoursAwake = max(0.0, now.timeIntervalSince(wakeTime) / 3600.0)
    let circadianDrain = min(20.0, hoursAwake * 1.10)

    // ── Stress / HRV-suppression drain ───────────────────────────────
    // If current HRV is lower than morning HRV, sympathetic load pulls the score down
    let currentHRV: Double? = engine.effectHRV[today] ?? engine.nightlyAnchoredHRV[today]
    let stressDrain: Double = {
        guard let m = morningHRV, m > 0, let c = currentHRV, c > 0 else { return 0 }
        return max(0, (m - c) / m * 15.0)
    }()

    // ── RHR elevation penalty ────────────────────────────────────────
    let currentRHR: Double? = engine.basalSleepingHeartRate[today]
        ?? engine.dailyRestingHeartRate[today]
        ?? engine.restingHeartRate
    let rhrBaseline: Double? = engine.rhrBaseline7Day ?? engine.rhrBaseline60Day?.mean
    let rhrPenalty: Double = {
        guard let rhr = currentRHR, let base = rhrBaseline, base > 0 else { return 0 }
        let elevation = max(0.0, rhr - base) / base
        return min(12.0, elevation * 35.0)
    }()

    // ── Mindfulness bonus ────────────────────────────────────────────
    let mindMin = engine.mindfulnessMinutesByDay[today] ?? 0.0
    let mindBonus = min(8.0, mindMin / 10.0)

    // ── HRV trend bonus ──────────────────────────────────────────────
    // Positive trend = nervous system is adapting well = score holds longer
    let trendBonus = max(0.0, min(8.0, (engine.hrvTrendScore - 50.0) / 50.0 * 8.0))

    let level = max(5.0, min(100.0,
        morningCharge - activityDrain - circadianDrain - stressDrain - rhrPenalty
        + mindBonus + trendBonus
    ))

    // ── 7-day history ────────────────────────────────────────────────
    let sevenDay = buildBodyStatusHistory(engine: engine, today: today, cal: cal)

    // ── Intraday synthetic curve ──────────────────────────────────────
    let intraDay = buildBodyStatusIntradayCurve(
        morningLevel: morningCharge,
        currentLevel: level,
        wakeTime: wakeTime,
        hoursAwake: hoursAwake,
        activityDrain: activityDrain,
        circadianDrain: circadianDrain,
        stressDrain: stressDrain,
        rhrPenalty: rhrPenalty,
        mindBonus: mindBonus,
        trendBonus: trendBonus,
        todayWorkouts: todayWorkouts.map { ($0.workout.startDate, $0.workout.duration) },
        now: now
    )

    return BodyStatusModel(
        level: level,
        morningLevel: morningCharge,
        activityDrain: activityDrain,
        circadianDrain: circadianDrain,
        stressDrain: stressDrain,
        rhrPenalty: rhrPenalty,
        mindfulnessBonus: mindBonus,
        hrvTrendBonus: trendBonus,
        sleepHours: sleepH > 0 ? sleepH : nil,
        sleepEfficiency: sleepH > 0 ? eff : nil,
        morningHRV: morningHRV,
        currentHRV: currentHRV,
        hoursAwake: hoursAwake,
        todayWorkoutCount: todayWorkouts.count,
        todayTotalLoad: todayLoad,
        rhrBaseline: rhrBaseline,
        currentRHR: currentRHR,
        sevenDayStatus: sevenDay,
        intradayCurve: intraDay
    )
}

@MainActor
private func buildBodyStatusHistory(
    engine: HealthStateEngine,
    today: Date,
    cal: Calendar
) -> [(Date, Double)] {
    (0..<7).compactMap { offset -> (Date, Double)? in
        guard let day = cal.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
        let dSleep = engine.anchoredSleepDuration[day] ?? engine.dailySleepDuration[day] ?? 0
        let dEff = engine.sleepEfficiency[day] ?? 0.85
        let dSleepQ = min(1.0, dSleep / 8.0) * (dEff * 0.70 + 0.30)
        let dBase = dSleepQ * 90 + 5
        let dHRV = engine.effectHRV[day] ?? engine.cachedHRVByDay[day]
        let baseline = engine.hrvBaseline7Day ?? engine.hrvBaseline60Day?.mean ?? 50.0
        let dFactor = dHRV.map { min(1.25, max(0.60, $0 / max(baseline, 1.0))) } ?? 1.0
        let dMorning = min(100.0, dBase * dFactor)
        let dWorkouts = engine.workoutAnalytics.filter { cal.isDate($0.workout.startDate, inSameDayAs: day) }
        let dLoad = dWorkouts.reduce(0.0) {
            $0 + HealthStateEngine.proWorkoutLoad(
                for: $1.workout, analytics: $1.analytics,
                estimatedMaxHeartRate: engine.estimatedMaxHeartRate
            )
        }
        let dActivityDrain = min(50.0, dLoad * 0.70)
        let dRHR = engine.basalSleepingHeartRate[day] ?? engine.dailyRestingHeartRate[day]
        let rhrBase = engine.rhrBaseline7Day ?? engine.rhrBaseline60Day?.mean
        let dRhrPenalty: Double = {
            guard let rhr = dRHR, let base = rhrBase, base > 0 else { return 0 }
            return min(12.0, max(0.0, rhr - base) / base * 35.0)
        }()
        let dMind = engine.mindfulnessMinutesByDay[day] ?? 0
        let dMindBonus = min(8.0, dMind / 10.0)
        let dTrend = max(0.0, min(8.0, (engine.hrvTrendScore - 50.0) / 50.0 * 8.0))
        // For past days assume full day elapsed (use 16h circadian drain typical workday)
        let dLevel = max(5.0, min(100.0,
            dMorning - dActivityDrain - 14.0 - dRhrPenalty + dMindBonus + dTrend
        ))
        return (day, dLevel)
    }
}

private func buildBodyStatusIntradayCurve(
    morningLevel: Double,
    currentLevel: Double,
    wakeTime: Date,
    hoursAwake: Double,
    activityDrain: Double,
    circadianDrain: Double,
    stressDrain: Double,
    rhrPenalty: Double,
    mindBonus: Double,
    trendBonus: Double,
    todayWorkouts: [(Date, TimeInterval)],
    now: Date
) -> [(Date, Double)] {
    guard hoursAwake > 0 else { return [(wakeTime, morningLevel), (now, morningLevel)] }

    var points: [(Date, Double)] = []
    // Start at wake time with morning baseline
    points.append((wakeTime, morningLevel))

    // Sort workouts by start time
    let sorted = todayWorkouts.sorted { $0.0 < $1.0 }
    var runningDrain = 0.0

    for (start, duration) in sorted {
        guard start > wakeTime, start < now else { continue }
        // Level just before workout
        let elapsed = start.timeIntervalSince(wakeTime) / 3600.0
        let preWorkoutCircadian = min(20.0, elapsed * 1.10)
        let preWorkoutLevel = max(5, morningLevel - runningDrain - preWorkoutCircadian - stressDrain - rhrPenalty + mindBonus + trendBonus)
        points.append((start, preWorkoutLevel))
        // Sharp drop during workout (spread over workout duration)
        let workoutEndTime = min(start.addingTimeInterval(duration), now)
        let workoutDrain = min(30.0, activityDrain * 0.60)
        let postWorkoutLevel = max(5, preWorkoutLevel - workoutDrain)
        points.append((workoutEndTime, postWorkoutLevel))
        runningDrain += workoutDrain
    }

    // End at current time = current level
    points.append((now, max(5, currentLevel)))

    // De-dupe and sort by time
    return points.sorted { $0.0 < $1.0 }.reduce(into: [(Date, Double)]()) { acc, pt in
        if acc.last?.0 != pt.0 { acc.append(pt) }
    }
}

// MARK: - Level color

private func bodyStatusLevelColor(for level: Double) -> Color {
    switch level {
    case 70...:  return .green
    case 45..<70: return .yellow
    case 25..<45: return .orange
    default:     return .red
    }
}

// MARK: - Main View

struct BodyStatusView: View {

    @ObservedObject private var engine = HealthStateEngine.shared
    @State private var model: BodyStatusModel = .empty
    @State private var loading = true
    @State private var animatedLevel: Double = 0
    @State private var animationPhase: Double = 0
    @Environment(\.dismiss) private var dismiss

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "E"; return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().oxygenFlowGradient(animationPhase: $animationPhase)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if loading {
                            ProgressView("Computing body status…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else {
                            heroSection
                            chargeBreakdownSection
                            drainBreakdownSection
                            intradayChartSection
                            sevenDayChartSection
                            calcDetailSection
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
            }
            .task { await load() }
            .navigationTitle("Body Status")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 16)
                    .frame(width: 168, height: 168)
                Circle()
                    .trim(from: 0, to: animatedLevel / 100)
                    .stroke(
                        LinearGradient(
                            colors: [bodyStatusLevelColor(for: model.level).opacity(0.5),
                                     bodyStatusLevelColor(for: model.level)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 168, height: 168)
                    .animation(.spring(response: 1.2, dampingFraction: 0.8), value: animatedLevel)

                VStack(spacing: 4) {
                    Text("\(Int(model.level.rounded()))")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(bodyStatusLevelColor(for: model.level))
                    Text("Body Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(bodyStatusHeadline(model.level))
                .font(.title3.bold())
                .foregroundStyle(bodyStatusLevelColor(for: model.level))

            Text(bodyStatusNarrative(model.level))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 16) {
                BodyStatusHeroPill(label: "Wake baseline", value: String(format: "%.0f%%", model.morningLevel), tint: .green)
                if model.todayWorkoutCount > 0 {
                    BodyStatusHeroPill(label: "Workouts", value: "\(model.todayWorkoutCount) session\(model.todayWorkoutCount > 1 ? "s" : "")", tint: .orange)
                }
                BodyStatusHeroPill(label: "Awake", value: String(format: "%.0fh", model.hoursAwake), tint: .cyan)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            LinearGradient(
                colors: [bodyStatusLevelColor(for: model.level).opacity(0.18),
                         Color.black.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(bodyStatusLevelColor(for: model.level).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Charge Breakdown

    private var chargeBreakdownSection: some View {
        BodyStatusSectionCard(title: "What Charged You", icon: "bolt.fill", tint: .green) {
            VStack(spacing: 0) {
                BodyStatusFactorRow(
                    icon: "moon.zzz.fill", tint: .indigo,
                    label: "Sleep Recharge",
                    detail: model.sleepHours.map {
                        String(format: "%.1f h sleep", $0) +
                        (model.sleepEfficiency.map { String(format: ", %.0f%% efficiency", $0 * 100) } ?? "")
                    } ?? "No sleep data",
                    value: String(format: "+%.0f%%", model.morningLevel),
                    positive: true
                )
                Divider().opacity(0.3).padding(.leading, 40)
                BodyStatusFactorRow(
                    icon: "waveform.path.ecg", tint: .cyan,
                    label: "HRV Quality Modifier",
                    detail: model.morningHRV.map { String(format: "Morning HRV: %.0f ms", $0) } ?? "HRV not detected",
                    value: model.morningHRV != nil ? (model.morningHRV! >= (engine.hrvBaseline7Day ?? 50) ? "Above baseline" : "Below baseline") : "—",
                    positive: model.morningHRV.map { $0 >= (engine.hrvBaseline7Day ?? 50) } ?? true
                )
                if model.mindfulnessBonus > 0 {
                    Divider().opacity(0.3).padding(.leading, 40)
                    BodyStatusFactorRow(
                        icon: "figure.mind.and.body", tint: .mint,
                        label: "Mindfulness Sessions",
                        detail: "Parasympathetic recovery boost",
                        value: String(format: "+%.1f%%", model.mindfulnessBonus),
                        positive: true
                    )
                }
                if model.hrvTrendBonus > 0.5 {
                    Divider().opacity(0.3).padding(.leading, 40)
                    BodyStatusFactorRow(
                        icon: "arrow.up.right.circle.fill", tint: .green,
                        label: "HRV Trend Support",
                        detail: "Your score holds longer when HRV is trending up",
                        value: String(format: "+%.1f%%", model.hrvTrendBonus),
                        positive: true
                    )
                }
            }
        }
    }

    // MARK: Drain Breakdown

    private var drainBreakdownSection: some View {
        BodyStatusSectionCard(title: "What Drained You", icon: "bolt.slash.fill", tint: .orange) {
            VStack(spacing: 0) {
                BodyStatusFactorRow(
                    icon: "sun.horizon.fill", tint: .yellow,
                    label: "Circadian Drain",
                    detail: String(format: "%.0f h awake — natural hourly depletion", model.hoursAwake),
                    value: String(format: "−%.0f%%", model.circadianDrain),
                    positive: false
                )
                if model.activityDrain > 0 {
                    Divider().opacity(0.3).padding(.leading, 40)
                    BodyStatusFactorRow(
                        icon: "figure.run.circle.fill", tint: .orange,
                        label: "Training Load",
                        detail: model.todayWorkoutCount > 0
                            ? String(format: "%d workout%@ • TRIMP: %.0f", model.todayWorkoutCount, model.todayWorkoutCount > 1 ? "s" : "", model.todayTotalLoad)
                            : "No workouts logged",
                        value: String(format: "−%.0f%%", model.activityDrain),
                        positive: false
                    )
                }
                if model.stressDrain > 0.5 {
                    Divider().opacity(0.3).padding(.leading, 40)
                    BodyStatusFactorRow(
                        icon: "brain.head.profile", tint: .pink,
                        label: "Sympathetic Load",
                        detail: model.currentHRV.map {
                            String(format: "HRV dropped to %.0f ms from %.0f ms morning reading",
                                   $0, model.morningHRV ?? 0)
                        } ?? "Elevated stress signals detected",
                        value: String(format: "−%.1f%%", model.stressDrain),
                        positive: false
                    )
                }
                if model.rhrPenalty > 0.5 {
                    Divider().opacity(0.3).padding(.leading, 40)
                    BodyStatusFactorRow(
                        icon: "heart.circle", tint: .red,
                        label: "Elevated Resting HR",
                        detail: [
                            model.currentRHR.map { String(format: "Current: %.0f bpm", $0) },
                            model.rhrBaseline.map { String(format: "7-day avg: %.0f bpm", $0) }
                        ].compactMap { $0 }.joined(separator: " · "),
                        value: String(format: "−%.0f%%", model.rhrPenalty),
                        positive: false
                    )
                }
            }
        }
    }

    // MARK: Intraday Chart

    @ViewBuilder
    private var intradayChartSection: some View {
        if model.intradayCurve.count >= 2 {
            BodyStatusSectionCard(title: "Today's Status Curve", icon: "waveform", tint: .cyan) {
                Chart(model.intradayCurve, id: \.0) { pt in
                    AreaMark(
                        x: .value("Time", pt.0),
                        y: .value("Status", pt.1)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [bodyStatusLevelColor(for: model.level).opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", pt.0),
                        y: .value("Status", pt.1)
                    )
                    .foregroundStyle(bodyStatusLevelColor(for: model.level))
                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { val in
                        AxisValueLabel(format: .dateTime.hour())
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { val in
                        AxisValueLabel { Text("\(val.as(Int.self) ?? 0)%").font(.caption2) }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [4]))
                    }
                }
                .frame(height: 140)
                .padding(.top, 8)
                Text("Status tends to fall during activity and rise after sleep. This curve reflects workout timing, time awake, and current stress load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 7-Day Chart

    @ViewBuilder
    private var sevenDayChartSection: some View {
        if !model.sevenDayStatus.isEmpty {
            BodyStatusSectionCard(title: "7-Day Status", icon: "calendar", tint: .purple) {
                Chart(model.sevenDayStatus, id: \.0) { pt in
                    BarMark(
                        x: .value("Day", Self.dayFmt.string(from: pt.0)),
                        y: .value("Status", pt.1)
                    )
                    .foregroundStyle(bodyStatusLevelColor(for: pt.1).gradient)
                    .cornerRadius(6)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { val in
                        AxisValueLabel { Text("\(val.as(Int.self) ?? 0)%").font(.caption2) }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [4]))
                    }
                }
                .frame(height: 140)
                .padding(.top, 8)
            }
        }
    }

    // MARK: Calculation Detail

    private var calcDetailSection: some View {
        BodyStatusSectionCard(title: "How It Is Calculated", icon: "function", tint: .secondary) {
            VStack(alignment: .leading, spacing: 12) {
                CalcRow(label: "Sleep Recharge", formula: "sleepRatio × efficiency × 90 + 5", value: String(format: "%.0f pts", model.morningLevel))
                CalcRow(label: "HRV Modifier", formula: "clamp(morningHRV / baseline, 0.6–1.25)", value: model.morningHRV.map { String(format: "×%.2f", min(1.25, max(0.60, $0 / max(engine.hrvBaseline7Day ?? 50, 1)))) } ?? "×1.00 (no data)")
                CalcRow(label: "Activity Drain", formula: "min(50, TRIMP × 0.7)", value: String(format: "−%.0f pts", model.activityDrain))
                CalcRow(label: "Circadian Drain", formula: "min(20, hoursAwake × 1.1)", value: String(format: "−%.0f pts (%.1fh awake)", model.circadianDrain, model.hoursAwake))
                CalcRow(label: "Sympathetic Load", formula: "(morningHRV − currentHRV) / morningHRV × 15", value: String(format: "−%.1f pts", model.stressDrain))
                CalcRow(label: "RHR Penalty", formula: "(rhr − baseline) / baseline × 35", value: String(format: "−%.1f pts", model.rhrPenalty))
                CalcRow(label: "Mindfulness Bonus", formula: "min(8, minutes / 10)", value: String(format: "+%.1f pts", model.mindfulnessBonus))
                CalcRow(label: "HRV Trend Bonus", formula: "(trendScore − 50) / 50 × 8", value: String(format: "+%.1f pts", model.hrvTrendBonus))
                Divider()
                HStack {
                    Text("Body Status").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.0f / 100", model.level))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(bodyStatusLevelColor(for: model.level))
                }
                Text("Unlike a single HRV snapshot, this score folds in real-time load and time awake. HRV can look strong overnight while the composite level still reflects training stress carried into the day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Helpers

    private func bodyStatusHeadline(_ level: Double) -> String {
        switch level {
        case 75...: return "Peak Reserve"
        case 55..<75: return "Solid Reserve"
        case 35..<55: return "Moderate Drawdown"
        case 15..<35: return "Low Reserve"
        default: return "Critically Low"
        }
    }

    private func bodyStatusNarrative(_ level: Double) -> String {
        switch level {
        case 75...:
            return "Autonomic balance is strong. Hard training sessions are well supported today."
        case 55..<75:
            return "Good energy available. Structured quality work is appropriate; watch late-day accumulation."
        case 35..<55:
            return "Reserve is partially drawn down. Prioritize execution over effort; avoid loading spikes."
        case 15..<35:
            return "Low reserve. Technical or easy sessions only. Recovery takes priority over output today."
        default:
            return "Reserve is very low. Rest is the highest-ROI activity right now."
        }
    }

    @MainActor
    private func load() async {
        model = computeBodyStatus(engine: engine)
        loading = false
        withAnimation(.spring(response: 1.2, dampingFraction: 0.82)) {
            animatedLevel = model.level
        }
    }
}

// MARK: - Compact Snippet View (for embedding)

struct BodyStatusSnippetView: View {
    let model: BodyStatusModel
    let hrvTrendSupport: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                // Header row
                HStack(alignment: .center, spacing: 12) {
                    // Mini gauge
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: model.level / 100)
                            .stroke(
                                bodyStatusLevelColor(for: model.level),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(model.level.rounded()))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(bodyStatusLevelColor(for: model.level))
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Body Status")
                            .font(.subheadline.weight(.semibold))
                        Text(bodyStatusSnippetSubtitle(model.level))
                            .font(.caption)
                            .foregroundStyle(bodyStatusLevelColor(for: model.level))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Factor pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if model.sleepHours != nil {
                            BodyStatusFactorPill(icon: "moon.zzz.fill", label: String(format: "Wake %.0f%%", model.morningLevel), tint: .indigo)
                        }
                        if model.activityDrain > 2 {
                            BodyStatusFactorPill(icon: "figure.run.circle.fill", label: String(format: "−%.0f%% training", model.activityDrain), tint: .orange)
                        }
                        BodyStatusFactorPill(icon: "sun.horizon.fill", label: String(format: "−%.0f%% awake", model.circadianDrain), tint: .yellow)
                        if model.stressDrain > 1 {
                            BodyStatusFactorPill(icon: "brain.head.profile", label: String(format: "−%.0f%% stress", model.stressDrain), tint: .pink)
                        }
                    }
                }

                // HRV Trend row
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Text("HRV Trend Support")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f / 100", hrvTrendSupport))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(hrvTrendSupport >= 60 ? "▲ Momentum" : hrvTrendSupport >= 40 ? "→ Stable" : "▼ Lagging")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hrvTrendSupport >= 60 ? .green : hrvTrendSupport >= 40 ? .secondary : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background((hrvTrendSupport >= 60 ? Color.green : hrvTrendSupport >= 40 ? Color.secondary : Color.orange).opacity(0.15), in: Capsule())
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(bodyStatusLevelColor(for: model.level).opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func bodyStatusSnippetSubtitle(_ level: Double) -> String {
        switch level {
        case 75...: return "Peak reserve · Tap for details"
        case 55..<75: return "Solid reserve · Tap for details"
        case 35..<55: return "Moderate drawdown · Tap for details"
        default: return "Low reserve · Tap for details"
        }
    }
}

// MARK: - Supporting Views

private struct BodyStatusSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.title3.weight(.bold))
            }
            content()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct BodyStatusFactorRow: View {
    let icon: String
    let tint: Color
    let label: String
    let detail: String
    let value: String
    let positive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.subheadline)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(positive ? .green : .orange)
        }
        .padding(.vertical, 10)
    }
}

private struct BodyStatusHeroPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BodyStatusFactorPill: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct CalcRow: View {
    let label: String
    let formula: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text(formula)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}
