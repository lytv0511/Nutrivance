import SwiftUI

struct ReadinessCheckView: View {
    @ObservedObject private var engine = HealthStateEngine.shared

    @State private var animationPhase: Double = 0
    @State private var isLoading = false

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var readinessValue: Double {
        engine.readinessScore
    }

    private var recoveryValue: Double {
        engine.recoveryScore
    }

    private var strainValue: Double {
        engine.strainScore
    }

    private var readinessClassification: ReadinessNarrative {
        readinessNarrative(for: readinessValue)
    }

    private var readinessSeries: [(Date, Double)] {
        let recoveryByDay = recoverySeriesMap
        let strainByDay = strainSeriesMap
        return readinessWindow.map { day in
            let recovery = recoveryByDay[day] ?? engine.recoveryScore
            let strain = strainByDay[day] ?? engine.strainScore
            return (day, HealthStateEngine.proReadinessScore(
                recoveryScore: recovery,
                strainScore: strain,
                hrvTrendComponent: readinessTrendScore(for: day)
            ))
        }
    }

    private var recoverySeriesMap: [Date: Double] {
        Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, recoveryScoreForDay(day))
        })
    }

    private var strainSeriesMap: [Date: Double] {
        Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, strainScoreForDay(day))
        })
    }

    private var readinessWindow: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return readinessDateSequence(from: start, to: today)
    }

    private var effectHRVToday: Double? {
        engine.effectHRV[today] ?? Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })[today]
    }

    private var basalRhrToday: Double? {
        engine.basalSleepingHeartRate[today] ?? engine.dailyRestingHeartRate[today]
    }

    private var sleepToday: Double? {
        engine.anchoredSleepDuration[today] ?? engine.dailySleepDuration[today]
    }

    private var sleepEfficiencyToday: Double? {
        guard let sleep = sleepToday,
              let timeInBed = engine.anchoredTimeInBed[today] ?? sleepToday,
              timeInBed > 0 else { return nil }
        return sleep / timeInBed
    }

    private var recoveryInputsToday: HealthStateEngine.ProRecoveryInputs {
        let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        return HealthStateEngine.proRecoveryInputs(
            latestHRV: HealthStateEngine.smoothedValue(for: today, values: engine.effectHRV) ?? HealthStateEngine.smoothedValue(for: today, values: hrvLookup),
            restingHeartRate: HealthStateEngine.smoothedValue(for: today, values: engine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: today, values: engine.dailyRestingHeartRate),
            sleepDurationHours: HealthStateEngine.smoothedValue(for: today, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: today, values: engine.dailySleepDuration),
            timeInBedHours: HealthStateEngine.smoothedValue(for: today, values: engine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: today, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: today, values: engine.dailySleepDuration),
            hrvBaseline60Day: engine.hrvBaseline60Day,
            rhrBaseline60Day: engine.rhrBaseline60Day,
            sleepBaseline60Day: engine.sleepBaseline60Day,
            hrvBaseline7Day: engine.hrvBaseline7Day,
            rhrBaseline7Day: engine.rhrBaseline7Day,
            sleepBaseline7Day: engine.sleepBaseline7Day,
            bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: today)
        )
    }

    private var hrvTrendSupport: Double {
        readinessTrendScore(for: today)
    }

    private var readinessDriverCards: [ReadinessFactorCardModel] {
        [
            ReadinessFactorCardModel(
                title: "Recovery Support",
                value: String(format: "%.0f", recoveryValue),
                unit: "/100",
                detail: "The biggest positive input. Better sleep, calmer basal HR, and stronger Effect HRV lift this.",
                tint: .green
            ),
            ReadinessFactorCardModel(
                title: "Strain Drag",
                value: String(format: "%.1f", strainValue),
                unit: "/21",
                detail: "Today's readiness gets pulled down when recent load is already heavy or spiky.",
                tint: .orange
            ),
            ReadinessFactorCardModel(
                title: "HRV Trend",
                value: String(format: "%.0f", hrvTrendSupport),
                unit: "/100",
                detail: "This is the momentum term. It rewards HRV trends that are holding up relative to baseline.",
                tint: .cyan
            ),
            ReadinessFactorCardModel(
                title: "Effect HRV",
                value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–",
                unit: "ms",
                detail: "Sleep-anchored HRV carries more weight than random daytime HRV noise.",
                tint: .mint
            ),
            ReadinessFactorCardModel(
                title: "Basal Sleep HR",
                value: basalRhrToday.map { String(format: "%.0f", $0) } ?? "–",
                unit: "bpm",
                detail: "Lower overnight heart rate relative to baseline usually means less recovery cost.",
                tint: .blue
            ),
            ReadinessFactorCardModel(
                title: "Sleep Efficiency",
                value: sleepEfficiencyToday.map { String(format: "%.0f", $0 * 100) } ?? "–",
                unit: "%",
                detail: "A cleaner night helps preserve the recovery score that readiness starts from.",
                tint: .indigo
            )
        ]
    }

    private var readinessDirectiveTitle: String {
        switch readinessValue {
        case 85...:
            return "Push if the plan asks for it"
        case 70..<85:
            return "Train with intent"
        case 50..<70:
            return "Keep quality, trim excess"
        default:
            return "Bias toward recovery today"
        }
    }

    private var readinessDirectiveDetail: String {
        switch readinessValue {
        case 85...:
            return "Recovery is clearly covering the current load. Hard work is available if it matches your goal."
        case 70..<85:
            return "This is a productive day, but it still rewards structure over chaos. Keep the session specific."
        case 50..<70:
            return "You are still trainable, but this is better framed as controlled execution than a reach day."
        default:
            return "Recovery reserve is light relative to load. Technique, easy volume, or a reset session will likely pay off more."
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().oxygenFlowGradient(animationPhase: $animationPhase)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        readinessHero

                        MetricSectionGroup(title: "Today's Score") {
                            HealthCard(
                                symbol: "bolt.heart.fill",
                                title: "Readiness Score",
                                value: String(format: "%.0f", readinessValue),
                                unit: "/100",
                                trend: "7d avg: \(String(format: "%.0f", readinessSeries.map(\.1).average ?? readinessValue))",
                                color: readinessClassification.color,
                                chartData: readinessSeries,
                                chartLabel: "Readiness",
                                chartUnit: "%",
                                badgeText: readinessClassification.title,
                                badgeColor: readinessClassification.color
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Readiness is today’s training permission slip. It starts from recovery, adds HRV trend support, then subtracts the drag from recent strain.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(readinessDirectiveDetail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ReadinessDirectiveCard(
                                title: readinessDirectiveTitle,
                                detail: readinessDirectiveDetail,
                                tint: readinessClassification.color
                            )
                        }

                        MetricSectionGroup(title: "How It Is Built") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(readinessDriverCards) { card in
                                    ReadinessFactorCard(model: card)
                                }
                            }
                        }

                        MetricSectionGroup(title: "Signal Breakdown") {
                            HealthCard(
                                symbol: "heart.circle.fill",
                                title: "Recovery Reserve",
                                value: String(format: "%.0f", recoveryValue),
                                unit: "/100",
                                trend: "Today’s base before strain drag",
                                color: .green,
                                chartData: readinessWindow.map { ($0, recoverySeriesMap[$0] ?? recoveryValue) },
                                chartLabel: "Recovery",
                                chartUnit: "%"
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Effect HRV z-score: \(readinessFormatted(recoveryInputsToday.hrvZScore, digits: 2))")
                                    Text("RHR penalty z-score: \(readinessFormatted(recoveryInputsToday.restingHeartRatePenaltyZScore, digits: 2))")
                                    Text("Sleep ratio: \(readinessFormatted(recoveryInputsToday.sleepRatio, digits: 2))")
                                    Text("Circadian penalty: \(String(format: "%.1f", recoveryInputsToday.circadianPenalty)) pts")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }

                            HealthCard(
                                symbol: "flame.fill",
                                title: "Strain Drag",
                                value: String(format: "%.1f", strainValue),
                                unit: "/21",
                                trend: "Recent load cost applied to today",
                                color: .orange,
                                chartData: readinessWindow.map { ($0, strainSeriesMap[$0] ?? strainValue) },
                                chartLabel: "Strain",
                                chartUnit: "/21"
                            ) {
                                Text("Strain is the subtractive force in readiness. Even strong recovery can get muted if acute load is already outrunning what your body has absorbed.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HealthCard(
                                symbol: "waveform.path.ecg",
                                title: "HRV Trend Support",
                                value: String(format: "%.0f", hrvTrendSupport),
                                unit: "/100",
                                trend: "Momentum support from HRV trend",
                                color: .cyan,
                                chartData: readinessWindow.map { ($0, readinessTrendScore(for: $0)) },
                                chartLabel: "HRV Trend",
                                chartUnit: "%"
                            ) {
                                Text("This term rewards HRV that is holding up or improving versus baseline. It helps readiness avoid overreacting to one noisy data point.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }

                if isLoading {
                    ProgressView("Refreshing readiness...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .navigationTitle("Readiness Check")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await refreshCoverage()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .task {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
                await refreshCoverage()
            }
        }
    }

    private var readinessHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today’s training permission")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("A simplified, richer read on whether recovery is actually covering the strain you are carrying into today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ReadinessOrb(score: readinessValue, tint: readinessClassification.color)
            }

            HStack(spacing: 12) {
                ReadinessHeroPill(label: "Recovery", value: String(format: "%.0f/100", recoveryValue), tint: .green)
                ReadinessHeroPill(label: "Strain", value: String(format: "%.1f/21", strainValue), tint: .orange)
                ReadinessHeroPill(label: "Meaning", value: readinessClassification.title, tint: readinessClassification.color)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color.cyan.opacity(0.24),
                    Color.blue.opacity(0.16),
                    Color.black.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @MainActor
    private func refreshCoverage() async {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        isLoading = true
        await engine.ensureRecoveryMetricsCoverage(from: start, to: end)
        await engine.ensureWorkoutAnalyticsCoverage(from: start, to: end)
        isLoading = false
    }

    private func recoveryScoreForDay(_ day: Date) -> Double {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        let inputs = HealthStateEngine.proRecoveryInputs(
            latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.effectHRV) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: hrvLookup),
            restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate),
            sleepDurationHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
            timeInBedHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration),
            hrvBaseline60Day: engine.hrvBaseline60Day,
            rhrBaseline60Day: engine.rhrBaseline60Day,
            sleepBaseline60Day: engine.sleepBaseline60Day,
            hrvBaseline7Day: engine.hrvBaseline7Day,
            rhrBaseline7Day: engine.rhrBaseline7Day,
            sleepBaseline7Day: engine.sleepBaseline7Day,
            bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: normalizedDay)
        )
        guard !inputs.isInconclusive else { return engine.recoveryScore }
        return HealthStateEngine.proRecoveryScore(from: inputs)
    }

    private func strainScoreForDay(_ day: Date) -> Double {
        let normalized = Calendar.current.startOfDay(for: day)
        let dayWorkouts = engine.workoutAnalytics.filter {
            Calendar.current.isDate($0.workout.startDate, inSameDayAs: normalized)
        }
        let totalLoad = dayWorkouts.reduce(0.0) { partial, pair in
            partial + HealthStateEngine.proWorkoutLoad(
                for: pair.workout,
                analytics: pair.analytics,
                estimatedMaxHeartRate: engine.estimatedMaxHeartRate
            )
        }

        let recentStart = Calendar.current.date(byAdding: .day, value: -6, to: normalized) ?? normalized
        let loadSeries = readinessDateSequence(from: recentStart, to: normalized).map { loadDay -> Double in
            engine.workoutAnalytics
                .filter { Calendar.current.isDate($0.workout.startDate, inSameDayAs: loadDay) }
                .reduce(0.0) { partial, pair in
                    partial + HealthStateEngine.proWorkoutLoad(
                        for: pair.workout,
                        analytics: pair.analytics,
                        estimatedMaxHeartRate: engine.estimatedMaxHeartRate
                    )
                }
        }

        let acuteLoad = loadSeries.reduce(0, +)
        let chronicLoad = max(loadSeries.average ?? totalLoad, 1)
        let acwr = acuteLoad / chronicLoad
        let logarithmicLoad = 6.2 * log10(max(acuteLoad, 0) + 1)
        let expandedLoad = pow(max(logarithmicLoad, 0), 1.08)
        let adjustment = min(max(8 * (acwr - 1.0), -1.5), 4.5)
        let preSoftCap = expandedLoad + adjustment + 0.5
        let softCapped = 21 * (1 - exp(-preSoftCap / 21))
        return max(0, min(21, softCapped))
    }

    private func readinessTrendScore(for day: Date) -> Double {
        let normalized = Calendar.current.startOfDay(for: day)
        let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        guard let hrvValue = hrvLookup[normalized] ?? engine.effectHRV[normalized] else {
            return engine.hrvTrendScore
        }
        let baseline = engine.hrvBaseline7Day ?? engine.hrvBaseline60Day?.mean ?? hrvValue
        guard baseline > 0 else { return engine.hrvTrendScore }
        let deviation = (hrvValue - baseline) / baseline
        return max(0, min(100, (deviation * 200) + 50))
    }
}

private struct ReadinessNarrative {
    let title: String
    let detail: String
    let color: Color
}

private func readinessNarrative(for score: Double) -> ReadinessNarrative {
    switch score {
    case 90...:
        return ReadinessNarrative(title: "Full Send", detail: "Strong green light for ambitious work.", color: .green)
    case 70..<90:
        return ReadinessNarrative(title: "Perform", detail: "A solid day for quality work.", color: .cyan)
    case 40..<70:
        return ReadinessNarrative(title: "Adapt", detail: "Trainable, but better with control and precision.", color: .orange)
    default:
        return ReadinessNarrative(title: "Recover", detail: "Best used to rebuild rather than force output.", color: .red)
    }
}

private struct ReadinessFactorCardModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let detail: String
    let tint: Color
}

private struct ReadinessFactorCard: View {
    let model: ReadinessFactorCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(model.tint.opacity(0.85))
                    .frame(width: 10, height: 10)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(model.tint)
                Text(model.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(model.tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ReadinessDirectiveCard: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ReadinessHeroPill: View {
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

private struct ReadinessOrb: View {
    let score: Double
    let tint: Color
    @State private var animatedScore: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 12)
            Circle()
                .trim(from: 0, to: animatedScore / 100)
                .stroke(
                    LinearGradient(colors: [tint.opacity(0.4), tint], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("ready")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.82)) {
                animatedScore = score
            }
        }
    }
}

private func readinessDateSequence(from start: Date, to end: Date) -> [Date] {
    let calendar = Calendar.current
    var dates: [Date] = []
    var cursor = calendar.startOfDay(for: start)
    let finish = calendar.startOfDay(for: end)

    while cursor <= finish {
        dates.append(cursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }

    return dates
}

private func readinessFormatted(_ value: Double?, digits: Int) -> String {
    guard let value else { return "–" }
    return String(format: "%.\(digits)f", value)
}
