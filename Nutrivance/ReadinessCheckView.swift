import SwiftUI
import UIKit

struct ReadinessCheckView: View {
    @EnvironmentObject private var navigationState: NavigationState
    @ObservedObject private var tuningStore = NutrivanceTuningStore.shared
    @ObservedObject private var performanceProfile = PerformanceProfileSettings.shared
    @State private var animationPhase: Double = 0
    @State private var snapshot = ReadinessSnapshot.empty
    @State private var proAthleteReadinessData: (score: Double, acwrStatus: String, taperDetected: Bool, asymmetricStrainMultiplier: Double)?
    /// Caches the per-day load snapshots produced by `buildSnapshot()` so the
    /// pro-athlete pass does not recompute `sharedDailyLoadSnapshots` for the same window.
    @State private var cachedReadinessLoadSnapshots: [SharedWorkoutSummarySnapshot] = []
    @State private var bodyStatusModel: BodyStatusModel = .empty
    @State private var morningReadiness: MorningReadinessSnapshot? = nil
    @State private var showBodyStatus = false

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

    private var readinessTuning: NutrivanceTuningDisplayResult {
        NutrivanceTuningEngine.display(base: readinessValue, metric: .readiness, store: tuningStore)
    }

    private var recoveryTuning: NutrivanceTuningDisplayResult {
        NutrivanceTuningEngine.display(base: recoveryValue, metric: .recovery, store: tuningStore)
    }

    private var strainTuning: NutrivanceTuningDisplayResult {
        NutrivanceTuningEngine.display(base: strainValue, metric: .strain, store: tuningStore)
    }

    private var displayedReadinessValue: Double { readinessTuning.adjusted }
    private var displayedRecoveryValue: Double { recoveryTuning.adjusted }
    private var displayedStrainValue: Double { strainTuning.adjusted }

    private var readinessClassification: ReadinessNarrative {
        readinessNarrative(for: displayedReadinessValue)
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

    private var recoveryBreakdownToday: RecoveryScoreBreakdown? {
        snapshot.recoveryBreakdownToday
    }

    private var readinessBreakdownToday: ReadinessScoreBreakdown? {
        snapshot.readinessBreakdownToday
    }

    private var hrvTrendSupport: Double {
        snapshot.hrvTrendSupport
    }

    private var readinessDriverCards: [ReadinessFactorCardModel] {
        snapshot.readinessDriverCards
    }

    private var readinessDirectiveTitle: String {
        switch displayedReadinessValue {
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
        switch displayedReadinessValue {
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
                                value: String(format: "%.0f", displayedReadinessValue),
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

                        // MARK: - Body Status Snippet
                        MetricSectionGroup(title: "Body Status") {
                            BodyStatusSnippetView(
                                model: bodyStatusModel,
                                hrvTrendSupport: hrvTrendSupport
                            ) {
                                showBodyStatus = true
                            }
                        }

                        // MARK: - Readiness This Morning
                        if let morning = morningReadiness {
                            MetricSectionGroup(title: "Readiness This Morning") {
                                MorningReadinessCard(data: morning)
                            }
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
                                value: String(format: "%.0f", displayedRecoveryValue),
                                unit: "/100",
                                trend: "Today’s base before strain drag",
                                color: .green,
                                chartData: readinessWindow.map { ($0, recoverySeriesMap[$0] ?? recoveryValue) },
                                chartLabel: "Recovery",
                                chartUnit: "%"
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let b = recoveryBreakdownToday {
                                        Text(String(format: "Core recovery %.0f + overnight context %.1f pts (cap −6) + agreement %.0f.", b.coreScore, b.secondaryDelta, b.agreementBonus))
                                        Text(String(format: "Model confidence %.0f%% (HRV + sleep coverage).", b.confidence01 * 100))
                                    }
                                    Text("Effect HRV z-score: \(readinessFormatted(recoveryInputsToday.hrvZScore, digits: 2))")
                                    Text("RHR penalty z-score: \(readinessFormatted(recoveryInputsToday.restingHeartRatePenaltyZScore, digits: 2))")
                                    Text("Sleep ratio: \(readinessFormatted(recoveryInputsToday.sleepRatio, digits: 2))")
                                    Text("Circadian penalty: \(String(format: "%.1f", recoveryInputsToday.circadianPenalty)) pts")
                                    if let r = readinessBreakdownToday {
                                        Text(String(format: "Readiness blends recovery at %.0f%% weight; zone: %@.", r.recoveryConfidence01 * 100, r.trainingZone))
                                            .padding(.top, 4)
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }

                            HealthCard(
                                symbol: "flame.fill",
                                title: "Strain Drag",
                                value: String(format: "%.1f", displayedStrainValue),
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
                                Text("Same 0–100 term as the HRV Trend card above: from daily HRV vs your 7-day average (about 50 is neutral). Very low values usually mean last night was far under that average, not a missing sensor by itself.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // MARK: - Pro-Athlete Analysis
                        if performanceProfile.isProAthleteMode, let proData = proAthleteReadinessData {
                            MetricSectionGroup(title: "Pro-Athlete Analysis") {
                                VStack(spacing: 12) {
                                    // ACWR Status Card
                                    if let acwr = snapshot.readinessWindow.count > 0 ? proData.acwrStatus : nil {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Acute-to-Chronic Load Ratio")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                    Text("Training load progression")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                HStack(spacing: 8) {
                                                    Text(acwr)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(acwr == "Optimal" ? .green : acwr == "Danger" ? .red : .orange)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .fill(Color(.systemGray6))
                                                        )
                                                }
                                            }
                                            
                                            if acwr == "Optimal" {
                                                Text("Sweet spot for injury prevention (0.8–1.3 range). Recovery + 5 points.")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            } else if acwr == "Danger" {
                                                Text("High load progression (>1.5 ratio). Readiness significantly reduced.")
                                                    .font(.caption2)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Taper Detection Card
                                    if proData.taperDetected {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "pause.circle.fill")
                                                    .foregroundColor(.yellow)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Fresh but Flat")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                    Text("Taper detected: readiness capped at 88")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                            }
                                            Text("You're in a planned rest phase. Stay disciplined—avoid the urge to push hard despite feeling charged.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Asymmetric Strain Impact Card
                                    if proData.asymmetricStrainMultiplier < 1.0 {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "chart.bar.xaxis")
                                                    .foregroundColor(.orange)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Asymmetric Strain Impact")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                    Text("High strain creates exponential cost")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Text(String(format: "× %.2f", proData.asymmetricStrainMultiplier))
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.orange)
                                            }
                                            Text("Readiness multiplier applied: each unit of strain above threshold creates increasingly severe penalty.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
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
            .sheet(isPresented: $showBodyStatus) {
                BodyStatusView()
            }
            .onAppear {
                let day = today
                if let cached = ReadinessDisplayDiskCache.loadIfMatches(anchorDay: day) {
                    snapshot = cached
                } else {
                    snapshot = .empty
                }
                applyAuxiliaryReadinessChrome()
            }
            .task(id: refreshTaskID) {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
                await recomputeReadinessFromEngineIfNeeded()
                applyAuxiliaryReadinessChrome()
            }
        }
    }

    private func scheduleForceRefresh() {
        Task {
            await refreshCoverageOnUserDemand(forceNetwork: true)
            applyAuxiliaryReadinessChrome()
        }
    }

    /// Rebuild charts after merging the latest sleep window (same path as toolbar refresh, lighter than skipping when disk cache exists).
    @MainActor
    private func recomputeReadinessFromEngineIfNeeded() async {
        await refreshCoverageOnUserDemand(forceNetwork: false)
        applyAuxiliaryReadinessChrome()
    }

    /// Pro-athlete / body / morning widgets from the engine (cheap vs full `buildSnapshot()` fan-out).
    @MainActor
    private func applyAuxiliaryReadinessChrome() {
        updateProAthleteData()
        bodyStatusModel = computeBodyStatus(engine: healthEngine)
        morningReadiness = buildMorningReadiness(engine: healthEngine)
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

                ReadinessOrb(score: displayedReadinessValue, tint: readinessClassification.color)
            }

            NutrivanceTuningValueCaption(
                result: readinessTuning,
                unitSuffix: "/100",
                format: { String(format: "%.0f", $0) }
            )

            HStack(spacing: 12) {
                ReadinessHeroPill(label: "Recovery", value: String(format: "%.0f/100", displayedRecoveryValue), tint: .green)
                ReadinessHeroPill(label: "Strain", value: String(format: "%.1f/21", displayedStrainValue), tint: .orange)
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
    private func refreshCoverageOnUserDemand(forceNetwork: Bool) async {
        await healthEngine.refreshRecentSleepForRecoveryScores()
        #if targetEnvironment(macCatalyst)
        healthEngine.recomputePublishedScoresNow()
        snapshot = buildSnapshot()
        ReadinessDisplayDiskCache.save(snapshot, anchorDay: today)
        DispatchQueue.global(qos: .utility).async {
            NSUbiquitousKeyValueStore.default.synchronize()
        }
        return
        #endif

        let calendar = Calendar.current
        let recoveryStart = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let workoutStart = calendar.date(byAdding: .day, value: -10, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        if forceNetwork {
            await healthEngine.refreshSyncedHealthDataFromICloud()
        }

        if healthEngine.needsRecoveryMetricsCoverage(from: recoveryStart, to: end) {
            await healthEngine.ensureRecoveryMetricsCoverage(from: recoveryStart, to: end)
        }
        if healthEngine.needsWorkoutAnalyticsCoverage(from: workoutStart, to: end) {
            await healthEngine.ensureWorkoutAnalyticsCoverage(from: workoutStart, to: end)
        }

        healthEngine.recomputePublishedScoresNow()
        snapshot = buildSnapshot()
        ReadinessDisplayDiskCache.save(snapshot, anchorDay: today)
    }

    /// Builds the readiness snapshot. The heavy fan-out — ~21 per-day pipeline calls
    /// that previously each rebuilt a HRV dictionary — now reuses a single
    /// `RecoveryComputationContext`, and the per-day load snapshots are cached for
    /// `updateProAthleteData` to read back without recomputing.
    @MainActor
    private func buildSnapshot() -> ReadinessSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let readinessWindow = sharedDateSequence(from: start, to: today)
        let context = RecoveryComputationContext.make(engine: healthEngine)
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
        cachedReadinessLoadSnapshots = loadSnapshots
        let strainLookup = Dictionary(uniqueKeysWithValues: loadSnapshots.map { ($0.date, $0.strainScore) })
        let acwrLookup = Dictionary(uniqueKeysWithValues: loadSnapshots.map { ($0.date, $0.acwr) })

        let recoveryFallback = healthEngine.recoveryScore
        let strainFallback = healthEngine.strainScore
        let readinessFallback = healthEngine.readinessScore

        let recoveryDetailByDay = Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, sharedRecoveryScoreDetailed(for: day, context: context))
        })
        let recoverySeriesMap = Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, recoveryDetailByDay[day].flatMap { $0 }?.score ?? recoveryFallback)
        })
        let strainSeriesMap = Dictionary(uniqueKeysWithValues: readinessWindow.map { day in
            (day, strainLookup[day] ?? strainFallback)
        })
        let hrvTrendSeries = readinessWindow.map { day in
            (day, sharedReadinessTrendComponent(for: day, context: context))
        }
        let readinessSeries = readinessWindow.map { day in
            let rb = recoveryDetailByDay[day].flatMap { $0 }
            let rec = rb?.score ?? recoveryFallback
            let readinessVal: Double = {
                guard let breakdown = rb else {
                    return sharedReadinessScore(
                        for: day,
                        recoveryScore: rec,
                        strainScore: strainSeriesMap[day] ?? strainFallback,
                        context: context,
                        acwr: acwrLookup[day]
                    ) ?? readinessFallback
                }
                return sharedReadinessScoreDetailed(
                    for: day,
                    recoveryBreakdown: breakdown,
                    recoveryScoreForBlend: rec,
                    strainScore: strainSeriesMap[day] ?? strainFallback,
                    acwr: acwrLookup[day],
                    context: context
                ).score
            }()
            return (day, readinessVal)
        }

        let effectHRVToday = ReadinessCheckView.effectHRV(on: today, context: context)
        let basalRhrToday = ReadinessCheckView.basalRhr(on: today, context: context)
        let sleepToday = ReadinessCheckView.sleepDuration(on: today, context: context)
        let sleepEfficiencyToday = ReadinessCheckView.sleepEfficiency(on: today, context: context, sleepDuration: sleepToday)
        let recoveryInputsToday = sharedRecoveryInputs(for: today, context: context)
        let recoveryBreakdownToday = recoveryDetailByDay[today].flatMap { $0 }
        let hrvTrendSupport = hrvTrendSeries.last?.1 ?? healthEngine.hrvTrendScore
        let readinessValue = readinessSeries.last?.1 ?? readinessFallback
        let recoveryValue = recoverySeriesMap[today] ?? recoveryFallback
        let strainValue = strainSeriesMap[today] ?? strainFallback
        let readinessBreakdownToday: ReadinessScoreBreakdown? = {
            guard let rb = recoveryBreakdownToday else { return nil }
            return sharedReadinessScoreDetailed(
                for: today,
                recoveryBreakdown: rb,
                recoveryScoreForBlend: recoveryValue,
                strainScore: strainValue,
                acwr: acwrLookup[today],
                context: context
            )
        }()

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
            recoveryBreakdownToday: recoveryBreakdownToday,
            readinessBreakdownToday: readinessBreakdownToday,
            hrvTrendSupport: hrvTrendSupport,
            readinessDriverCards: makeReadinessDriverCards(
                recoveryValue: recoveryValue,
                strainValue: strainValue,
                hrvTrendSupport: hrvTrendSupport,
                effectHRVToday: effectHRVToday,
                basalRhrToday: basalRhrToday,
                sleepEfficiencyToday: sleepEfficiencyToday,
                recoveryInputsToday: recoveryInputsToday,
                recoveryBreakdown: recoveryBreakdownToday,
                readinessBreakdown: readinessBreakdownToday
            )
        )
    }

    // Per-day helpers used by both `buildSnapshot` and the (in-progress) detached path.
    nonisolated static func effectHRV(on day: Date, context: RecoveryComputationContext) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return context.effectHRV[normalizedDay] ?? context.hrvByDay[normalizedDay]
    }

    nonisolated static func basalRhr(on day: Date, context: RecoveryComputationContext) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return context.basalSleepingHeartRate[normalizedDay] ?? context.dailyRestingHeartRate[normalizedDay]
    }

    nonisolated static func sleepDuration(on day: Date, context: RecoveryComputationContext) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        return context.anchoredSleepDuration[normalizedDay] ?? context.dailySleepDuration[normalizedDay]
    }

    nonisolated static func sleepEfficiency(on day: Date, context: RecoveryComputationContext, sleepDuration: Double?) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        if let direct = context.sleepEfficiencyByDay[normalizedDay], direct > 0, direct <= 1.0 {
            return direct
        }
        guard let sleepDuration, sleepDuration > 0 else { return nil }
        guard let timeInBed = context.anchoredTimeInBed[normalizedDay], timeInBed > 0 else { return nil }
        // If time-in-bed equals sleep duration (missing real in-bed data), ratio is meaningless — avoid showing 100%.
        guard timeInBed > sleepDuration + (1.0 / 60.0) else { return nil }
        return min(1.0, max(0.0, sleepDuration / timeInBed))
    }
    
    @MainActor
    private func updateProAthleteData() {
        guard performanceProfile.isProAthleteMode else {
            proAthleteReadinessData = nil
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        // Reuse the load snapshots already produced by `buildSnapshot()` instead of
        // recomputing `sharedDailyLoadSnapshots` for the same 7-day window.
        let loadSnapshots: [SharedWorkoutSummarySnapshot] = {
            if !cachedReadinessLoadSnapshots.isEmpty { return cachedReadinessLoadSnapshots }
            let readinessDisplayWindow = (
                start: Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today,
                end: today,
                endExclusive: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            )
            let computed = sharedDailyLoadSnapshots(
                workouts: healthEngine.workoutAnalytics,
                estimatedMaxHeartRate: healthEngine.estimatedMaxHeartRate,
                displayWindow: readinessDisplayWindow
            )
            cachedReadinessLoadSnapshots = computed
            return computed
        }()
        let todayLoad = loadSnapshots.first(where: { $0.date == today })

        proAthleteReadinessData = sharedProAthleteReadinessScore(
            for: today,
            recoveryScore: snapshot.recoveryValue,
            strainScore: snapshot.strainValue,
            acwr: todayLoad?.acwr,
            acuteLoad: todayLoad?.acuteLoad,
            chronicLoad: todayLoad?.chronicLoad,
            engine: healthEngine,
            profile: performanceProfile
        )
    }

    private func makeReadinessDriverCards(
        recoveryValue: Double,
        strainValue: Double,
        hrvTrendSupport: Double,
        effectHRVToday: Double?,
        basalRhrToday: Double?,
        sleepEfficiencyToday: Double?,
        recoveryInputsToday: HealthStateEngine.ProRecoveryInputs,
        recoveryBreakdown: RecoveryScoreBreakdown?,
        readinessBreakdown: ReadinessScoreBreakdown?
    ) -> [ReadinessFactorCardModel] {
        buildReadinessDriverCards(
            recoveryValue: recoveryValue,
            strainValue: strainValue,
            hrvTrendSupport: hrvTrendSupport,
            effectHRVToday: effectHRVToday,
            basalRhrToday: basalRhrToday,
            sleepEfficiencyToday: sleepEfficiencyToday,
            recoveryInputsToday: recoveryInputsToday,
            recoveryBreakdown: recoveryBreakdown,
            readinessBreakdown: readinessBreakdown
        )
    }

    // The per-day helpers (`recoveryInputs`, `effectHRV`, `basalRhr`, `sleepDuration`,
    // `sleepEfficiency`) are now `nonisolated static` versions defined alongside
    // `buildSnapshot()` so they operate on a `RecoveryComputationContext`.

    // MARK: - Morning Readiness

    /// Computes a readiness score anchored to the last sleep session's biometrics —
    /// captured before any training or daily stress could affect the numbers.
    /// Returns nil when no HRV was detected during that sleep window.
    @MainActor
    private func buildMorningReadiness(engine: HealthStateEngine) -> MorningReadinessSnapshot? {
        // Require HRV detected during sleep — otherwise the score is unreliable
        // Prefer raw sleep-anchored HRV for "this morning" — Effect HRV is smoothed across days and can drift from last night.
        guard let morningHRV = engine.readinessHRV ?? engine.readinessEffectHRV else { return nil }

        let inputs = HealthStateEngine.proRecoveryInputs(
            latestHRV: morningHRV,
            restingHeartRate: engine.readinessBasalHeartRate ?? engine.restingHeartRate,
            sleepDurationHours: engine.readinessSleepDuration,
            timeInBedHours: engine.readinessTimeInBed ?? engine.readinessSleepDuration,
            hrvBaseline60Day: engine.hrvBaseline60Day,
            rhrBaseline60Day: engine.rhrBaseline60Day,
            sleepBaseline60Day: engine.sleepBaseline60Day,
            hrvBaseline7Day: engine.hrvBaseline7Day,
            rhrBaseline7Day: engine.rhrBaseline7Day,
            sleepBaseline7Day: engine.sleepBaseline7Day
        )

        guard !inputs.isInconclusive else { return nil }

        let morningRecovery = HealthStateEngine.proRecoveryScore(from: inputs)
        // At wake time there is no accumulated strain drag yet
        let morningReadinessScore = HealthStateEngine.proReadinessScore(
            recoveryScore: morningRecovery,
            strainScore: 0,
            hrvTrendComponent: engine.hrvTrendScore
        )

        let capturedDesc: String = {
            guard let wakeTime = engine.lastSleepEnd else { return "Last sleep session" }
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return "Captured at \(fmt.string(from: wakeTime))"
        }()

        return MorningReadinessSnapshot(
            readinessScore: morningReadinessScore,
            recoveryScore: morningRecovery,
            effectHRV: morningHRV,
            sleepHours: engine.readinessSleepDuration,
            sleepEfficiency: engine.readinessSleepEfficiency,
            basalHR: engine.readinessBasalHeartRate,
            hrvZScore: inputs.hrvZScore,
            sleepRatio: inputs.sleepRatio,
            capturedDescription: capturedDesc
        )
    }
}

// MARK: - Readiness “How it is built” cards (shared live + disk restore)

/// Pills must not reuse the z-score badge thresholds for unrelated scales (e.g. 0–100 confidence).
fileprivate func readinessRecoveryDataQualityPill(confidence01: Double) -> (String, Color) {
    let pct = confidence01 * 100
    if pct >= 80 { return (String(format: "Data %.0f%%", pct), .mint) }
    if pct >= 60 { return (String(format: "Data %.0f%%", pct), .yellow) }
    return (String(format: "Data %.0f%%", pct), .orange)
}

fileprivate func readinessHrvTrendVersus7dPill(_ support0to100: Double) -> (String, Color) {
    switch support0to100 {
    case ..<20: return ("vs 7d: very low", .red)
    case ..<38: return ("vs 7d: low", .orange)
    case ..<48: return ("vs 7d: soft", .orange)
    case ..<55: return ("vs 7d: neutral", .mint)
    case ..<68: return ("vs 7d: good", .green)
    default: return ("vs 7d: strong", .green)
    }
}

fileprivate func readinessEffectHrvZPill(_ z: Double?) -> (String, Color) {
    guard let z else { return ("HRV z n/a", .secondary) }
    if abs(z) < 0.12 { return ("Near baseline", .mint) }
    let label = String(format: "%+.1f SD", z)
    if z >= 0.35 { return (label, .green) }
    if z <= -0.35 { return (label, .orange) }
    return (label, .mint)
}

fileprivate func readinessBasalPenaltyPill(_ penaltyZ: Double?) -> (String, Color) {
    guard let penaltyZ else { return ("RHR n/a", .secondary) }
    if penaltyZ < 0.08 { return ("HR cost: low", .green) }
    if penaltyZ < 0.55 { return (String(format: "+%.1f SD cost", penaltyZ), .orange) }
    return (String(format: "+%.1f SD cost", penaltyZ), .red)
}

fileprivate func readinessSleepEfficiencyPill(_ fraction: Double?) -> (String, Color) {
    guard let fraction else { return ("No ratio yet", .secondary) }
    let pct = fraction * 100
    if pct >= 90 { return (String(format: "%.0f%% solid", pct), .mint) }
    if pct >= 80 { return (String(format: "%.0f%% ok", pct), .green) }
    if pct >= 70 { return (String(format: "%.0f%% thin", pct), .orange) }
    return (String(format: "%.0f%% low", pct), .red)
}

fileprivate func buildReadinessDriverCards(
    recoveryValue: Double,
    strainValue: Double,
    hrvTrendSupport: Double,
    effectHRVToday: Double?,
    basalRhrToday: Double?,
    sleepEfficiencyToday: Double?,
    recoveryInputsToday: HealthStateEngine.ProRecoveryInputs,
    recoveryBreakdown: RecoveryScoreBreakdown?,
    readinessBreakdown: ReadinessScoreBreakdown?
) -> [ReadinessFactorCardModel] {
    let confPct: String = {
        guard let r = readinessBreakdown else { return "–" }
        return String(format: "%.0f%%", r.confidence01 * 100)
    }()
    let zone = readinessBreakdown?.trainingZone ?? "–"
    let limiter: String = {
        guard let r = readinessBreakdown else { return "–" }
        switch r.limitingFactor {
        case .recovery: return "Recovery"
        case .strain: return "Strain"
        case .context: return "Context"
        case .balanced: return "Balanced"
        }
    }()

    let sleepEfficiencyDisplayed = sleepEfficiencyToday ?? recoveryInputsToday.sleepEfficiency
    let hrvTrendDetail: String = {
        let base = "0–100 support from HRV vs your 7-day average (~50 is neutral). This is separate from Effect HRV z-scores on the recovery card."
        if hrvTrendSupport < 22 {
            return base + " A very low score usually means last night’s HRV is far under that average, or baseline coverage is thin—not a “broken” meter."
        }
        return base
    }()

    return [
        ReadinessFactorCardModel(
            title: "Recovery Support",
            value: String(format: "%.0f", recoveryValue),
            unit: "/100",
            detail: recoveryBreakdown.map {
                String(format: "Core %.0f + secondaries %.1f + agreement %.0f. Data confidence %.0f%%.", $0.coreScore, $0.secondaryDelta, $0.agreementBonus, $0.confidence01 * 100)
            } ?? "The biggest positive input. Better sleep, calmer basal HR, and stronger Effect HRV lift this.",
            tint: .green,
            accessoryPill: recoveryBreakdown.map { readinessRecoveryDataQualityPill(confidence01: $0.confidence01) },
            contribution: nil,
            contributionDirection: .higherIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Strain Drag",
            value: String(format: "%.1f", strainValue),
            unit: "/21",
            detail: "Today's readiness gets pulled down when recent load is already heavy or spiky.",
            tint: .orange,
            accessoryPill: nil,
            contribution: nil,
            contributionDirection: .lowerIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Readiness confidence",
            value: confPct,
            unit: "confidence",
            detail: "Blends recovery-signal coverage with load (ACWR) stability so low-quality days do not over-trust the headline score.",
            tint: .yellow,
            accessoryPill: nil,
            contribution: nil,
            contributionDirection: .higherIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Training zone",
            value: zone,
            unit: "",
            detail: "Derived from the final readiness score and recent strain arc.",
            tint: .teal,
            accessoryPill: nil,
            contribution: nil,
            contributionDirection: .higherIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Limiting factor",
            value: limiter,
            unit: "",
            detail: "Whether recovery reserve, load drag, or mixed signals is driving the score today.",
            tint: .purple,
            accessoryPill: nil,
            contribution: nil,
            contributionDirection: .consistency
        ),
        ReadinessFactorCardModel(
            title: "HRV Trend",
            value: String(format: "%.0f", hrvTrendSupport),
            unit: "/100",
            detail: hrvTrendDetail,
            tint: .cyan,
            accessoryPill: readinessHrvTrendVersus7dPill(hrvTrendSupport),
            contribution: nil,
            contributionDirection: .higherIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Effect HRV",
            value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–",
            unit: "ms",
            detail: "Sleep-anchored HRV carries more weight than random daytime HRV noise. The pill is your HRV z-score vs baseline (standard deviations), not the 0–100 trend chip.",
            tint: .mint,
            accessoryPill: readinessEffectHrvZPill(recoveryInputsToday.hrvZScore),
            contribution: nil,
            contributionDirection: .higherIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Basal Sleep HR",
            value: basalRhrToday.map { String(format: "%.0f", $0) } ?? "–",
            unit: "bpm",
            detail: "Overnight HR cost in the recovery model. The pill summarizes resting HR penalty z (above baseline), not bpm.",
            tint: .blue,
            accessoryPill: readinessBasalPenaltyPill(recoveryInputsToday.restingHeartRatePenaltyZScore),
            contribution: nil,
            contributionDirection: .lowerIsBetter
        ),
        ReadinessFactorCardModel(
            title: "Sleep Efficiency",
            value: sleepEfficiencyDisplayed.map { String(format: "%.0f", $0 * 100) } ?? "—",
            unit: "%",
            detail: sleepEfficiencyDisplayed == nil
                ? "No reliable asleep / in-bed ratio yet. We also try the value baked into recovery inputs when HealthKit timing lines up."
                : "A cleaner night helps preserve the recovery score that readiness starts from.",
            tint: .indigo,
            accessoryPill: readinessSleepEfficiencyPill(sleepEfficiencyDisplayed),
            contribution: nil,
            contributionDirection: .higherIsBetter
        )
    ]
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
    let recoveryBreakdownToday: RecoveryScoreBreakdown?
    let readinessBreakdownToday: ReadinessScoreBreakdown?
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
        recoveryBreakdownToday: nil,
        readinessBreakdownToday: nil,
        hrvTrendSupport: 0,
        readinessDriverCards: []
    )
}

// MARK: - Readiness display disk cache

private struct ReadinessDV: Codable {
    var d: TimeInterval
    var y: Double
}

private struct ReadinessMapDisk: Codable {
    var pairs: [ReadinessDV]
}

private struct PersistedProRecoveryInputs: Codable {
    var hrvZScore: Double?
    var restingHeartRateZScore: Double?
    var restingHeartRatePenaltyZScore: Double?
    var sleepRatio: Double?
    var sleepScalar: Double?
    var sleepGoalHours: Double
    var sleepDurationHours: Double?
    var timeInBedHours: Double?
    var sleepEfficiency: Double?
    var composite: Double
    var baseRecoveryScore: Double
    var finalRecoveryScore: Double
    var sleepDebtPenalty: Double
    var circadianPenalty: Double
    var efficiencyCap: Double?
    var bedtimeVarianceMinutes: Double?
    var isInconclusive: Bool

    init(_ i: HealthStateEngine.ProRecoveryInputs) {
        hrvZScore = i.hrvZScore
        restingHeartRateZScore = i.restingHeartRateZScore
        restingHeartRatePenaltyZScore = i.restingHeartRatePenaltyZScore
        sleepRatio = i.sleepRatio
        sleepScalar = i.sleepScalar
        sleepGoalHours = i.sleepGoalHours
        sleepDurationHours = i.sleepDurationHours
        timeInBedHours = i.timeInBedHours
        sleepEfficiency = i.sleepEfficiency
        composite = i.composite
        baseRecoveryScore = i.baseRecoveryScore
        finalRecoveryScore = i.finalRecoveryScore
        sleepDebtPenalty = i.sleepDebtPenalty
        circadianPenalty = i.circadianPenalty
        efficiencyCap = i.efficiencyCap
        bedtimeVarianceMinutes = i.bedtimeVarianceMinutes
        isInconclusive = i.isInconclusive
    }

    var asInputs: HealthStateEngine.ProRecoveryInputs {
        HealthStateEngine.ProRecoveryInputs(
            hrvZScore: hrvZScore,
            restingHeartRateZScore: restingHeartRateZScore,
            restingHeartRatePenaltyZScore: restingHeartRatePenaltyZScore,
            sleepRatio: sleepRatio,
            sleepScalar: sleepScalar,
            sleepGoalHours: sleepGoalHours,
            sleepDurationHours: sleepDurationHours,
            timeInBedHours: timeInBedHours,
            sleepEfficiency: sleepEfficiency,
            composite: composite,
            baseRecoveryScore: baseRecoveryScore,
            finalRecoveryScore: finalRecoveryScore,
            sleepDebtPenalty: sleepDebtPenalty,
            circadianPenalty: circadianPenalty,
            efficiencyCap: efficiencyCap,
            bedtimeVarianceMinutes: bedtimeVarianceMinutes,
            isInconclusive: isInconclusive
        )
    }
}

private struct ReadinessFactorDiskCard: Codable {
    var title: String
    var value: String
    var unit: String
    var detail: String
    var tr: Double
    var tg: Double
    var tb: Double
    var ta: Double
    var contribution: Double?
    var direction: String

    init(_ m: ReadinessFactorCardModel) {
        title = m.title
        value = m.value
        unit = m.unit
        detail = m.detail
        let c = UIColor(m.tint)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        tr = Double(r)
        tg = Double(g)
        tb = Double(b)
        ta = Double(a)
        contribution = m.contribution
        switch m.contributionDirection {
        case .higherIsBetter: direction = "higher"
        case .lowerIsBetter: direction = "lower"
        case .consistency: direction = "consistency"
        }
    }

    var asModel: ReadinessFactorCardModel {
        let dir: ReadinessFactorCardModel.ContributionDirection
        switch direction {
        case "lower": dir = .lowerIsBetter
        case "consistency": dir = .consistency
        default: dir = .higherIsBetter
        }
        return ReadinessFactorCardModel(
            title: title,
            value: value,
            unit: unit,
            detail: detail,
            tint: Color(red: tr, green: tg, blue: tb, opacity: ta),
            accessoryPill: nil,
            contribution: contribution,
            contributionDirection: dir
        )
    }
}

private struct ReadinessSnapshotDiskEnvelope: Codable {
    var v: Int
    var anchor: TimeInterval
    var savedAt: TimeInterval
    var readinessValue: Double
    var recoveryValue: Double
    var strainValue: Double
    var readinessWindow: [TimeInterval]
    var readinessSeries: [ReadinessDV]
    var recoverySeries: ReadinessMapDisk
    var strainSeries: ReadinessMapDisk
    var hrvTrendSeries: [ReadinessDV]
    var effectHRVToday: Double?
    var basalRhrToday: Double?
    var sleepToday: Double?
    var sleepEfficiencyToday: Double?
    var recoveryInputs: PersistedProRecoveryInputs
    var hrvTrendSupport: Double
    var driverCards: [ReadinessFactorDiskCard]
    var recoveryBreakdown: RecoveryScoreBreakdown?
    var readinessBreakdown: ReadinessScoreBreakdown?

    init(snapshot: ReadinessSnapshot, anchorDay: Date) {
        v = 2
        anchor = anchorDay.timeIntervalSince1970
        savedAt = Date().timeIntervalSince1970
        readinessValue = snapshot.readinessValue
        recoveryValue = snapshot.recoveryValue
        strainValue = snapshot.strainValue
        readinessWindow = snapshot.readinessWindow.map(\.timeIntervalSince1970)
        readinessSeries = snapshot.readinessSeries.map { ReadinessDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        recoverySeries = ReadinessMapDisk(pairs: snapshot.recoverySeriesMap.keys.sorted().map { d in
            ReadinessDV(d: d.timeIntervalSince1970, y: snapshot.recoverySeriesMap[d] ?? 0)
        })
        strainSeries = ReadinessMapDisk(pairs: snapshot.strainSeriesMap.keys.sorted().map { d in
            ReadinessDV(d: d.timeIntervalSince1970, y: snapshot.strainSeriesMap[d] ?? 0)
        })
        hrvTrendSeries = snapshot.hrvTrendSeries.map { ReadinessDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        effectHRVToday = snapshot.effectHRVToday
        basalRhrToday = snapshot.basalRhrToday
        sleepToday = snapshot.sleepToday
        sleepEfficiencyToday = snapshot.sleepEfficiencyToday
        recoveryInputs = PersistedProRecoveryInputs(snapshot.recoveryInputsToday)
        hrvTrendSupport = snapshot.hrvTrendSupport
        driverCards = snapshot.readinessDriverCards.map(ReadinessFactorDiskCard.init)
        recoveryBreakdown = snapshot.recoveryBreakdownToday
        readinessBreakdown = snapshot.readinessBreakdownToday
    }

    func asSnapshot() -> ReadinessSnapshot {
        let cal = Calendar.current
        let recoveryMap = Dictionary(uniqueKeysWithValues: recoverySeries.pairs.map { pair in
            (cal.startOfDay(for: Date(timeIntervalSince1970: pair.d)), pair.y)
        })
        let strainMap = Dictionary(uniqueKeysWithValues: strainSeries.pairs.map { pair in
            (cal.startOfDay(for: Date(timeIntervalSince1970: pair.d)), pair.y)
        })
        return ReadinessSnapshot(
            readinessValue: readinessValue,
            recoveryValue: recoveryValue,
            strainValue: strainValue,
            readinessWindow: readinessWindow.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0)) },
            readinessSeries: readinessSeries.map { (cal.startOfDay(for: Date(timeIntervalSince1970: $0.d)), $0.y) },
            recoverySeriesMap: recoveryMap,
            strainSeriesMap: strainMap,
            hrvTrendSeries: hrvTrendSeries.map { (cal.startOfDay(for: Date(timeIntervalSince1970: $0.d)), $0.y) },
            effectHRVToday: effectHRVToday,
            basalRhrToday: basalRhrToday,
            sleepToday: sleepToday,
            sleepEfficiencyToday: sleepEfficiencyToday,
            recoveryInputsToday: recoveryInputs.asInputs,
            recoveryBreakdownToday: recoveryBreakdown,
            readinessBreakdownToday: readinessBreakdown,
            hrvTrendSupport: hrvTrendSupport,
            readinessDriverCards: buildReadinessDriverCards(
                recoveryValue: recoveryValue,
                strainValue: strainValue,
                hrvTrendSupport: hrvTrendSupport,
                effectHRVToday: effectHRVToday,
                basalRhrToday: basalRhrToday,
                sleepEfficiencyToday: sleepEfficiencyToday,
                recoveryInputsToday: recoveryInputs.asInputs,
                recoveryBreakdown: recoveryBreakdown,
                readinessBreakdown: readinessBreakdown
            )
        )
    }
}

private enum ReadinessDisplayDiskCache {
    private static let fileName = "readiness-display-v2.json"
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    static func loadIfMatches(anchorDay: Date) -> ReadinessSnapshot? {
        let day = Calendar.current.startOfDay(for: anchorDay)
        guard let url = try? NutrivanceViewMetricDisplayCacheURL.fileURL(named: fileName),
              let data = try? Data(contentsOf: url),
              let env = try? decoder.decode(ReadinessSnapshotDiskEnvelope.self, from: data) else {
            return nil
        }
        let cachedAnchor = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: env.anchor))
        guard cachedAnchor == day else { return nil }
        return env.asSnapshot()
    }

    static func save(_ snapshot: ReadinessSnapshot, anchorDay: Date) {
        let day = Calendar.current.startOfDay(for: anchorDay)
        let env = ReadinessSnapshotDiskEnvelope(snapshot: snapshot, anchorDay: day)
        guard let url = try? NutrivanceViewMetricDisplayCacheURL.fileURL(named: fileName),
              let data = try? encoder.encode(env) else { return }
        try? data.write(to: url, options: [.atomic])
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
    /// When set, shown as the top-right pill instead of `contribution` thresholds.
    let accessoryPill: (text: String, color: Color)?
    let contribution: Double?
    let contributionDirection: ContributionDirection
    
    enum ContributionDirection {
        case higherIsBetter
        case lowerIsBetter
        case consistency
    }
    
    var displayPill: (text: String, color: Color)? {
        accessoryPill ?? contributionBadge
    }
    
    var contributionBadge: (text: String, color: Color)? {
        guard let contribution else { return nil }
        switch contributionDirection {
        case .higherIsBetter:
            if contribution > 5 {
                return ("+\(Int(contribution))", .green)
            } else if contribution > 0 {
                return ("+\(Int(contribution))", .mint)
            } else if contribution > -5 {
                return ("\(Int(contribution))", .orange)
            } else {
                return ("\(Int(contribution))", .red)
            }
        case .lowerIsBetter:
            if contribution > 5 {
                return ("+\(Int(contribution))", .green)
            } else if contribution > 0 {
                return ("+\(Int(contribution))", .mint)
            } else if contribution > -5 {
                return ("\(Int(contribution))", .orange)
            } else {
                return ("\(Int(contribution))", .red)
            }
        case .consistency:
            if contribution > 3 {
                return ("Consistent", .green)
            } else if contribution > 0 {
                return ("Stable", .mint)
            } else if contribution > -3 {
                return ("Variable", .orange)
            } else {
                return ("Inconsistent", .red)
            }
        }
    }
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
                if let badge = model.displayPill {
                    Text(badge.text)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badge.color.opacity(0.15), in: Capsule())
                }
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
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
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
        .onChange(of: score) { oldValue, newValue in
            withAnimation(.spring(response: 1.1, dampingFraction: 0.82)) {
                animatedScore = newValue
            }
        }
        .onAppear {
            animatedScore = score
        }
    }
}

private func readinessFormatted(_ value: Double?, digits: Int) -> String {
    guard let value else { return "–" }
    return String(format: "%.\(digits)f", value)
}

// MARK: - Morning Readiness Data Model

private struct MorningReadinessSnapshot {
    let readinessScore: Double
    let recoveryScore: Double
    let effectHRV: Double
    let sleepHours: Double?
    let sleepEfficiency: Double?
    let basalHR: Double?
    let hrvZScore: Double?
    let sleepRatio: Double?
    let capturedDescription: String

    var classification: (title: String, color: Color) {
        switch readinessScore {
        case 85...: return ("Full Send", .green)
        case 70..<85: return ("Perform", .cyan)
        case 50..<70: return ("Adapt", .orange)
        default: return ("Recover", .red)
        }
    }
}

// MARK: - Morning Readiness Card

private struct MorningReadinessCard: View {
    let data: MorningReadinessSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: data.readinessScore / 100)
                        .stroke(
                            data.classification.color,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(data.readinessScore.rounded()))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(data.classification.color)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Morning Readiness")
                            .font(.subheadline.weight(.semibold))
                        Text(data.classification.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(data.classification.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(data.classification.color.opacity(0.14), in: Capsule())
                    }
                    Text(data.capturedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Snapshot of your physiology at wake-up — before today's training or daily stress could affect your scores. Use this to assess true daily readiness rather than a post-workout dip.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Signal grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MorningReadinessTile(
                    icon: "waveform.path.ecg", tint: .cyan,
                    label: "Effect HRV",
                    value: String(format: "%.0f ms", data.effectHRV),
                    sub: data.hrvZScore.map { String(format: "z=%.2f", $0) } ?? nil
                )
                MorningReadinessTile(
                    icon: "heart.fill", tint: .green,
                    label: "Recovery",
                    value: String(format: "%.0f / 100", data.recoveryScore),
                    sub: "Pre-activity baseline"
                )
                if let sleep = data.sleepHours {
                    MorningReadinessTile(
                        icon: "moon.zzz.fill", tint: .indigo,
                        label: "Sleep",
                        value: String(format: "%.1f h", sleep),
                        sub: data.sleepEfficiency.map { String(format: "%.0f%% efficient", $0 * 100) } ?? nil
                    )
                }
                if let rhr = data.basalHR {
                    MorningReadinessTile(
                        icon: "bed.double.fill", tint: .blue,
                        label: "Basal HR",
                        value: String(format: "%.0f bpm", rhr),
                        sub: "During sleep"
                    )
                }
            }

            // Interpretation note
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Strain is excluded from morning readiness — this score reflects your body's state before any load was applied today.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(data.classification.color.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct MorningReadinessTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    let sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
