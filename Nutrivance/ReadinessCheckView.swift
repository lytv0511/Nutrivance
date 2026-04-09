import SwiftUI

struct ReadinessCheckView: View {
    @EnvironmentObject private var navigationState: NavigationState
    @State private var animationPhase: Double = 0
    @State private var isLoading = false
    @State private var snapshot = ReadinessSnapshot.empty
    /// Same calendar day: rebuild from engine only when returning to this screen (no redundant coverage / CloudKit).
    @State private var lastCompletedCoverageTaskID: String?

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Stable per calendar day so a new day triggers a fresh `.task` cycle.
    private var refreshTaskID: String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: today)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private var healthEngine: HealthStateEngine { HealthStateEngine.shared }

    private var readinessValue: Double {
        snapshot.readinessValue
    }

    private var recoveryValue: Double {
        snapshot.recoveryValue
    }

    private var strainValue: Double {
        snapshot.strainValue
    }

    private var readinessClassification: ReadinessNarrative {
        readinessNarrative(for: readinessValue)
    }

    private var readinessSeries: [(Date, Double)] {
        snapshot.readinessSeries
    }

    private var recoverySeriesMap: [Date: Double] {
        snapshot.recoverySeriesMap
    }

    private var strainSeriesMap: [Date: Double] {
        snapshot.strainSeriesMap
    }

    private var readinessWindow: [Date] {
        snapshot.readinessWindow
    }

    private var effectHRVToday: Double? {
        snapshot.effectHRVToday
    }

    private var basalRhrToday: Double? {
        snapshot.basalRhrToday
    }

    private var sleepToday: Double? {
        snapshot.sleepToday
    }

    private var sleepEfficiencyToday: Double? {
        snapshot.sleepEfficiencyToday
    }

    private var recoveryInputsToday: HealthStateEngine.ProRecoveryInputs {
        snapshot.recoveryInputsToday
    }

    private var hrvTrendSupport: Double {
        snapshot.hrvTrendSupport
    }

    private var readinessDriverCards: [ReadinessFactorCardModel] {
        snapshot.readinessDriverCards
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
                            .catalystDirectionalFocusGroup()
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
                                chartData: snapshot.hrvTrendSeries,
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
                        scheduleForceRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.cyan)
                    }
                    .catalystDesktopFocusable()
                }
            }
            .onReceiveViewControl(.nutrivanceViewControlReadinessRefresh) {
                guard navigationState.isGloballyActiveRootTab(.readiness) else { return }
                scheduleForceRefresh()
            }
            .task(id: refreshTaskID) {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
                if lastCompletedCoverageTaskID == refreshTaskID {
                    snapshot = buildSnapshot()
                    return
                }
                await refreshCoverage(forceNetwork: false)
                lastCompletedCoverageTaskID = refreshTaskID
            }
        }
    }

    private func scheduleForceRefresh() {
        Task {
            await refreshCoverage(forceNetwork: true)
            lastCompletedCoverageTaskID = refreshTaskID
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
    private func refreshCoverage(forceNetwork: Bool) async {
        snapshot = buildSnapshot()
        
        #if targetEnvironment(macCatalyst)
        let buildSnapshotCopy = buildSnapshot
        DispatchQueue.global(qos: .userInitiated).async {
            NSUbiquitousKeyValueStore.default.synchronize()
            DispatchQueue.main.async {
                let newSnapshot = buildSnapshotCopy()
                self.snapshot = newSnapshot
            }
        }
        return
        #endif

        let calendar = Calendar.current
        let recoveryStart = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let workoutStart = calendar.date(byAdding: .day, value: -10, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        if forceNetwork {
            isLoading = true
            await healthEngine.refreshSyncedHealthDataFromICloud()
            snapshot = buildSnapshot()
            isLoading = false
            return
        }

        let needRecovery = healthEngine.needsRecoveryMetricsCoverage(from: recoveryStart, to: end)
        let needWorkouts = healthEngine.needsWorkoutAnalyticsCoverage(from: workoutStart, to: end)
        guard needRecovery || needWorkouts else { return }

        isLoading = true
        if needRecovery {
            await healthEngine.ensureRecoveryMetricsCoverage(from: recoveryStart, to: end)
        }
        if needWorkouts {
            await healthEngine.ensureWorkoutAnalyticsCoverage(from: workoutStart, to: end)
        }
        snapshot = buildSnapshot()
        isLoading = false
    }

    @MainActor
    private func buildSnapshot() -> ReadinessSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let readinessWindow = sharedDateSequence(from: start, to: today)
        let hrvLookup = Dictionary(uniqueKeysWithValues: healthEngine.dailyHRV.map { ($0.date, $0.average) })
        let readinessDisplayWindow = (
            start: start,
            end: today,
            endExclusive: calendar.date(byAdding: .day, value: 1, to: today) ?? today
        )
        let loadSnapshots = sharedDailyLoadSnapshots(
            workouts: healthEngine.workoutAnalytics,
            estimatedMaxHeartRate: healthEngine.estimatedMaxHeartRate,
            displayWindow: readinessDisplayWindow
        )
        let strainLookup = Dictionary(uniqueKeysWithValues: loadSnapshots.map { ($0.date, $0.strainScore) })

        let recoverySeriesMap = Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, sharedRecoveryScore(for: day, engine: healthEngine) ?? healthEngine.recoveryScore)
        })
        let strainSeriesMap = Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, strainLookup[day] ?? healthEngine.strainScore)
        })
        let hrvTrendSeries = readinessWindow.map { day in
            (day, sharedReadinessTrendComponent(for: day, engine: healthEngine))
        }
        let readinessSeries = readinessWindow.map { day in
            (
                day,
                sharedReadinessScore(
                    for: day,
                    recoveryScore: recoverySeriesMap[day] ?? healthEngine.recoveryScore,
                    strainScore: strainSeriesMap[day] ?? healthEngine.strainScore,
                    engine: healthEngine
                ) ?? healthEngine.readinessScore
            )
        }

        let effectHRVToday = effectHRV(on: today, hrvLookup: hrvLookup)
        let basalRhrToday = basalRhr(on: today)
        let sleepToday = sleepDuration(on: today)
        let sleepEfficiencyToday = sleepEfficiency(on: today, sleepDuration: sleepToday)
        let recoveryInputsToday = recoveryInputs(for: today, hrvLookup: hrvLookup)
        let hrvTrendSupport = hrvTrendSeries.last?.1 ?? healthEngine.hrvTrendScore
        let readinessValue = readinessSeries.last?.1 ?? healthEngine.readinessScore
        let recoveryValue = recoverySeriesMap[today] ?? healthEngine.recoveryScore
        let strainValue = strainSeriesMap[today] ?? healthEngine.strainScore

        return ReadinessSnapshot(
            readinessValue: readinessValue,
            recoveryValue: recoveryValue,
            strainValue: strainValue,
            readinessWindow: readinessWindow,
            readinessSeries: readinessSeries,
            recoverySeriesMap: recoverySeriesMap,
            strainSeriesMap: strainSeriesMap,
            hrvTrendSeries: hrvTrendSeries,
            effectHRVToday: effectHRVToday,
            basalRhrToday: basalRhrToday,
            sleepToday: sleepToday,
            sleepEfficiencyToday: sleepEfficiencyToday,
            recoveryInputsToday: recoveryInputsToday,
            hrvTrendSupport: hrvTrendSupport,
            readinessDriverCards: makeReadinessDriverCards(
                recoveryValue: recoveryValue,
                strainValue: strainValue,
                hrvTrendSupport: hrvTrendSupport,
                effectHRVToday: effectHRVToday,
                basalRhrToday: basalRhrToday,
                sleepEfficiencyToday: sleepEfficiencyToday
            )
        )
    }

    private func makeReadinessDriverCards(
        recoveryValue: Double,
        strainValue: Double,
        hrvTrendSupport: Double,
        effectHRVToday: Double?,
        basalRhrToday: Double?,
        sleepEfficiencyToday: Double?
    ) -> [ReadinessFactorCardModel] {
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

    private func recoveryInputs(for day: Date, hrvLookup: [Date: Double]) -> HealthStateEngine.ProRecoveryInputs {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return HealthStateEngine.proRecoveryInputs(
            latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.effectHRV) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: hrvLookup),
            restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.basalSleepingHeartRate) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.dailyRestingHeartRate),
            sleepDurationHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.dailySleepDuration),
            timeInBedHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.anchoredTimeInBed) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.anchoredSleepDuration) ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: healthEngine.dailySleepDuration),
            hrvBaseline60Day: healthEngine.hrvBaseline60Day,
            rhrBaseline60Day: healthEngine.rhrBaseline60Day,
            sleepBaseline60Day: healthEngine.sleepBaseline60Day,
            hrvBaseline7Day: healthEngine.hrvBaseline7Day,
            rhrBaseline7Day: healthEngine.rhrBaseline7Day,
            sleepBaseline7Day: healthEngine.sleepBaseline7Day,
            bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: healthEngine.sleepStartHours, around: normalizedDay)
        )
    }

    private func effectHRV(on day: Date, hrvLookup: [Date: Double]) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return healthEngine.effectHRV[normalizedDay] ?? hrvLookup[normalizedDay]
    }

    private func basalRhr(on day: Date) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return healthEngine.basalSleepingHeartRate[normalizedDay] ?? healthEngine.dailyRestingHeartRate[normalizedDay]
    }

    private func sleepDuration(on day: Date) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return healthEngine.anchoredSleepDuration[normalizedDay] ?? healthEngine.dailySleepDuration[normalizedDay]
    }

    private func sleepEfficiency(on day: Date, sleepDuration: Double?) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        guard let sleepDuration else { return nil }
        let timeInBed = healthEngine.anchoredTimeInBed[normalizedDay] ?? sleepDuration
        guard timeInBed > 0 else { return nil }
        return sleepDuration / timeInBed
    }

}

private struct ReadinessSnapshot {
    let readinessValue: Double
    let recoveryValue: Double
    let strainValue: Double
    let readinessWindow: [Date]
    let readinessSeries: [(Date, Double)]
    let recoverySeriesMap: [Date: Double]
    let strainSeriesMap: [Date: Double]
    let hrvTrendSeries: [(Date, Double)]
    let effectHRVToday: Double?
    let basalRhrToday: Double?
    let sleepToday: Double?
    let sleepEfficiencyToday: Double?
    let recoveryInputsToday: HealthStateEngine.ProRecoveryInputs
    let hrvTrendSupport: Double
    let readinessDriverCards: [ReadinessFactorCardModel]

    static let empty = ReadinessSnapshot(
        readinessValue: 0,
        recoveryValue: 0,
        strainValue: 0,
        readinessWindow: [],
        readinessSeries: [],
        recoverySeriesMap: [:],
        strainSeriesMap: [:],
        hrvTrendSeries: [],
        effectHRVToday: nil,
        basalRhrToday: nil,
        sleepToday: nil,
        sleepEfficiencyToday: nil,
        recoveryInputsToday: HealthStateEngine.ProRecoveryInputs(
            hrvZScore: nil,
            restingHeartRateZScore: nil,
            restingHeartRatePenaltyZScore: nil,
            sleepRatio: nil,
            sleepScalar: nil,
            sleepGoalHours: 8,
            sleepDurationHours: nil,
            timeInBedHours: nil,
            sleepEfficiency: nil,
            composite: 0,
            baseRecoveryScore: 0,
            finalRecoveryScore: 0,
            sleepDebtPenalty: 0,
            circadianPenalty: 0,
            efficiencyCap: nil,
            bedtimeVarianceMinutes: nil,
            isInconclusive: true
        ),
        hrvTrendSupport: 0,
        readinessDriverCards: []
    )
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
        .catalystDesktopFocusable()
        .accessibilityLabel("\(model.title), \(model.value) \(model.unit)")
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
        .catalystDesktopFocusable()
        .accessibilityLabel("\(title). \(detail)")
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

private func readinessFormatted(_ value: Double?, digits: Int) -> String {
    guard let value else { return "–" }
    return String(format: "%.\(digits)f", value)
}
