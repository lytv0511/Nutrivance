import SwiftUI
import UIKit

struct RecoveryScoreView: View {
    @ObservedObject private var tuningStore = NutrivanceTuningStore.shared
    @ObservedObject private var performanceProfile = PerformanceProfileSettings.shared
    @State private var animationPhase: Double = 0
    @State private var timeFilter: RecoveryFocusTimeFilter = .day
    @State private var snapshotsByFilter: [RecoveryFocusTimeFilter: RecoverySnapshot] = [:]
    @State private var proAthleteRecoveryData: (score: Double, hrvWarning: Bool, sleepQualityWarning: Bool, subjectiveBoost: Double?)?

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var refreshTaskID: String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: today)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private var healthEngine: HealthStateEngine { HealthStateEngine.shared }

    private var selectedWindow: [Date] {
        snapshot.selectedWindow
    }

    private var recoverySeries: [(Date, Double)] {
        snapshot.recoverySeries
    }

    private var effectHRVSeries: [(Date, Double)] {
        snapshot.effectHRVSeries
    }

    private var basalRhrSeries: [(Date, Double)] {
        snapshot.basalRhrSeries
    }

    private var sleepSeries: [(Date, Double)] {
        snapshot.sleepSeries
    }

    private var respiratorySeries: [(Date, Double)] {
        snapshot.respiratorySeries
    }

    private var spO2Series: [(Date, Double)] {
        snapshot.spO2Series
    }

    private var wristTemperatureSeries: [(Date, Double)] {
        snapshot.wristTemperatureSeries
    }

    private var recoveryValue: Double {
        snapshot.recoveryValue
    }

    private var recoveryTuning: NutrivanceTuningDisplayResult {
        NutrivanceTuningEngine.display(base: recoveryValue, metric: .recovery, store: tuningStore)
    }

    /// Display value after optional Nutrivance Labs nudges.
    private var displayedRecoveryValue: Double {
        recoveryTuning.adjusted
    }

    private var recoveryState: RecoveryFocusState {
        recoveryFocusState(for: displayedRecoveryValue)
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

    private var respiratoryToday: Double? {
        snapshot.respiratoryToday
    }

    private var spO2Today: Double? {
        snapshot.spO2Today
    }

    private var wristTemperatureToday: Double? {
        snapshot.wristTemperatureToday
    }

    private var recoveryInputsToday: HealthStateEngine.ProRecoveryInputs {
        snapshot.recoveryInputsToday
    }

    private var recoveryBreakdownToday: RecoveryScoreBreakdown? {
        snapshot.recoveryBreakdownToday
    }

    private var recoverySignals: [RecoverySignalCardModel] {
        snapshot.recoverySignals
    }

    private var snapshot: RecoverySnapshot {
        snapshotsByFilter[timeFilter] ?? RecoverySnapshot.empty(for: timeFilter, anchor: today)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                    .ignoresSafeArea()

                ScrollView {
                    Group {
                        LazyVStack(alignment: .leading, spacing: 28) {
                        recoveryHero

                        recoveryTimeFilterBar

                        MetricSectionGroup(title: "Recovery Score") {
                            HealthCard(
                                symbol: "heart.text.square.fill",
                                title: "Recovery Score",
                                value: String(format: "%.0f", displayedRecoveryValue),
                                unit: "/100",
                                trend: "\(timeFilter.rawValue) avg: \(String(format: "%.0f", recoverySeries.map(\.1).average ?? recoveryValue))",
                                color: recoveryState.color,
                                chartData: recoverySeries,
                                chartLabel: "Recovery",
                                chartUnit: "%",
                                badgeText: recoveryState.title,
                                badgeColor: recoveryState.color
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recovery is the fitness-side answer to one question: how much reserve did your body rebuild, independent of how hard you trained?")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(recoveryState.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    ForEach(Array(recoveryScoreFooterLines(
                                        breakdown: recoveryBreakdownToday,
                                        inputs: recoveryInputsToday
                                    ).enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        MetricSectionGroup(title: "Fitness Recovery Signals") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(recoverySignals) { card in
                                    RecoverySignalCard(model: card)
                                }
                            }
                            .catalystDirectionalFocusGroup()
                        }

                        MetricSectionGroup(title: "How It Is Built") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Layer 2 bundles one snapshot of your HealthKit-aligned maps (HRV, resting HR, sleep, circadian timing, respiratory rate, SpO2, wrist temperature) plus rolling baselines used for comparisons.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Layer 3 scores a core recovery from autonomic + sleep signals, then applies small adjustments from secondary vitals versus your personal prior-week baseline. The sum of those secondary adjustments is capped, and an optional agreement bonus applies only when the core score is strong and confidence is high.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Layer 4 seals the headline score with explicit coverage per signal and a confidence value that downstream readiness uses so missing sleep or HRV does not silently pretend to be a full-quality day.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        recoveryDriversSection

                        MetricSectionGroup(title: "Context") {
                            if !respiratorySeries.isEmpty {
                                HealthCard(
                                    symbol: "lungs.fill",
                                    title: "Respiratory Rate",
                                    value: respiratoryToday.map { String(format: "%.1f", $0) } ?? "–",
                                    unit: "/min",
                                    trend: "\(timeFilter.rawValue) avg: \(String(format: "%.1f", respiratorySeries.map(\.1).average ?? 0))",
                                    color: .teal,
                                    chartData: respiratorySeries,
                                    chartLabel: "Respiratory Rate",
                                    chartUnit: "/min"
                                ) {
                                    Text("When enough prior-day samples exist, respiratory rate is compared to your rolling baseline. Large elevations contribute a small capped adjustment alongside SpO2 and wrist temperature.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !spO2Series.isEmpty {
                                HealthCard(
                                    symbol: "drop.fill",
                                    title: "SpO2",
                                    value: spO2Today.map { String(format: "%.0f", $0) } ?? "–",
                                    unit: "%",
                                    trend: "\(timeFilter.rawValue) avg: \(String(format: "%.0f", spO2Series.map(\.1).average ?? 0))",
                                    color: .green,
                                    chartData: spO2Series,
                                    chartLabel: "SpO2",
                                    chartUnit: "%"
                                ) {
                                    Text("SpO2 is compared to your personal baseline; unusually low readings versus that baseline add a small negative adjustment, with total secondary influence capped across all three vitals.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !wristTemperatureSeries.isEmpty {
                                HealthCard(
                                    symbol: "thermometer.medium",
                                    title: "Wrist Temperature",
                                    value: wristTemperatureToday.map { String(format: "%.2f", $0) } ?? "–",
                                    unit: "°C",
                                    trend: "\(timeFilter.rawValue) avg: \(String(format: "%.2f", wristTemperatureSeries.map(\.1).average ?? 0))",
                                    color: .orange,
                                    chartData: wristTemperatureSeries,
                                    chartLabel: "Wrist Temp",
                                    chartUnit: "°C"
                                ) {
                                    Text("Wrist temperature is compared to your personal baseline; unusually large deviations add a small negative adjustment, gated on enough baseline samples so single-day noise does not dominate.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    // MARK: - Pro-Athlete Insights
                    if performanceProfile.isProAthleteMode, let proData = proAthleteRecoveryData {
                        MetricSectionGroup(title: "Pro-Athlete Insights") {
                            VStack(alignment: .leading, spacing: 12) {
                                // Show badges for active conditions
                                if proData.hrvWarning {
                                    HStack(spacing: 8) {
                                        ProAthleteInfoBadge(badgeType: .hrvBellCurve)
                                        Spacer()
                                    }
                                }
                                
                                if proData.sleepQualityWarning {
                                    HStack(spacing: 8) {
                                        ProAthleteInfoBadge(badgeType: .sleepQualityLow)
                                        Spacer()
                                    }
                                }
                                
                                if performanceProfile.enableStrainSensitiveHRV && healthEngine.chronicTrainingLoad > 0 {
                                    HStack(spacing: 8) {
                                        ProAthleteInfoBadge(badgeType: .strainSensitiveHRV)
                                        Spacer()
                                    }
                                }
                                
                                if let subjectiveBoost = proData.subjectiveBoost, subjectiveBoost != 0 {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(subjectiveBoost > 0 ? .green : .orange)
                                            Text("Subjective Data Applied")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(String(format: "%+.0f pts", subjectiveBoost))
                                                .font(.caption)
                                                .foregroundColor(subjectiveBoost > 0 ? .green : .orange)
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                    }
                                }
                                
                                // Subjective Data Entry (if enabled)
                                if performanceProfile.enableSubjectiveDataCollection {
                                    Divider().padding(.vertical, 8)
                                    SubjectiveDailyEntryCompact()
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
            .navigationTitle("Recovery Score")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        scheduleForceRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.green)
                    }
                    .catalystDesktopFocusable()
                }
            }
            .onReceiveViewControl(.nutrivanceViewControlRecoveryScoreRefresh) {
                scheduleForceRefresh()
            }
            .onReceiveViewControl(.nutrivanceViewControlRecoveryScoreFilter1D) {
                timeFilter = .day
            }
            .onReceiveViewControl(.nutrivanceViewControlRecoveryScoreFilter1W) {
                timeFilter = .week
            }
            .onReceiveViewControl(.nutrivanceViewControlRecoveryScoreFilter1M) {
                timeFilter = .month
            }
            .onAppear {
                if let cached = RecoveryDisplayDiskCache.loadIfMatches(anchorDay: today) {
                    snapshotsByFilter = cached
                } else {
                    snapshotsByFilter = [:]
                }
                updateProAthleteData()
            }
            .task(id: refreshTaskID) {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
                await recomputeRecoveryFromEngineIfNeeded()
                updateProAthleteData()
            }
        }
    }

    private func scheduleForceRefresh() {
        Task {
            await refreshCoverageOnUserDemand(forceNetwork: true)
        }
    }

    /// Build from in-memory engine only when there is no display cache for today (no HK / CloudKit pulls).
    @MainActor
    private func recomputeRecoveryFromEngineIfNeeded() async {
        guard snapshotsByFilter.isEmpty else { return }
        snapshotsByFilter = await buildSnapshots()
        RecoveryDisplayDiskCache.save(snapshotsByFilter, anchorDay: today)
    }

    private var recoveryHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fitness-side recovery")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("A calm read on how well your body rebuilt reserve, independent of how much strain you chose to carry.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RecoveryHalo(score: displayedRecoveryValue, tint: recoveryState.color)
            }

            NutrivanceTuningValueCaption(
                result: recoveryTuning,
                unitSuffix: "/100",
                format: { String(format: "%.0f", $0) }
            )

            HStack(spacing: 12) {
                RecoveryHeroPill(label: "State", value: recoveryState.title, tint: recoveryState.color)
                RecoveryHeroPill(label: "Sleep", value: sleepToday.map { String(format: "%.1fh", $0) } ?? "–", tint: .indigo)
                RecoveryHeroPill(label: "Effect HRV", value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–", tint: .mint)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color.green.opacity(0.22),
                    Color.teal.opacity(0.14),
                    Color.black.opacity(0.16)
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

    private var recoveryTimeFilterBar: some View {
        HStack(spacing: 10) {
            ForEach(RecoveryFocusTimeFilter.allCases) { filter in
                RecoveryTimeFilterSegmentButton(
                    filter: filter,
                    isSelected: timeFilter == filter
                ) {
                    timeFilter = filter
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recoveryDriversSection: some View {
        MetricSectionGroup(title: "Drivers") {
            recoveryDriverEffectHRVCard
            recoveryDriverBasalHRPhCard
            recoveryDriverSleepDurationCard
        }
    }

    private var recoveryDriverEffectHRVCard: some View {
        let trend = "\(timeFilter.rawValue) avg: \(String(format: "%.0f", effectHRVSeries.map(\.1).average ?? 0))"
        return HealthCard(
            symbol: "waveform.path.ecg",
            title: "Effect HRV",
            value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–",
            unit: "ms",
            trend: trend,
            color: .mint,
            chartData: effectHRVSeries,
            chartLabel: "Effect HRV",
            chartUnit: "ms"
        ) {
            Text("This is the recovery version of HRV: sleep-anchored, momentum-smoothed, and intentionally harder to distort with random daytime samples.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var recoveryDriverBasalHRPhCard: some View {
        let trend = "\(timeFilter.rawValue) avg: \(String(format: "%.0f", basalRhrSeries.map(\.1).average ?? 0))"
        return HealthCard(
            symbol: "heart.fill",
            title: "Basal Sleeping HR",
            value: basalRhrToday.map { String(format: "%.0f", $0) } ?? "–",
            unit: "bpm",
            trend: trend,
            color: .blue,
            chartData: basalRhrSeries,
            chartLabel: "Basal HR",
            chartUnit: "bpm"
        ) {
            Text("This is the low-end overnight heart rate signal. When it stays elevated relative to baseline, recovery usually pays a price.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var recoveryDriverSleepDurationCard: some View {
        let trend = "\(timeFilter.rawValue) avg: \(String(format: "%.1f", sleepSeries.map(\.1).average ?? 0))"
        return HealthCard(
            symbol: "bed.double.fill",
            title: "Sleep Duration",
            value: sleepToday.map { String(format: "%.1f", $0) } ?? "–",
            unit: "h",
            trend: trend,
            color: .indigo,
            chartData: sleepSeries,
            chartLabel: "Sleep",
            chartUnit: "h"
        ) {
            Text("Recovery uses sleep as a gate, not just a side note. A short or inefficient night reduces how much of your physiology advantage survives the final score.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func refreshCoverageOnUserDemand(forceNetwork: Bool) async {
        #if targetEnvironment(macCatalyst)
        healthEngine.recomputePublishedScoresNow()
        snapshotsByFilter = await buildSnapshots()
        RecoveryDisplayDiskCache.save(snapshotsByFilter, anchorDay: today)
        DispatchQueue.global(qos: .utility).async {
            NSUbiquitousKeyValueStore.default.synchronize()
        }
        updateProAthleteData()
        return
        #endif

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -35, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        if forceNetwork {
            await healthEngine.refreshSyncedHealthDataFromICloud()
        }
        if healthEngine.needsRecoveryMetricsCoverage(from: start, to: end) {
            await healthEngine.ensureRecoveryMetricsCoverage(from: start, to: end)
        }

        healthEngine.recomputePublishedScoresNow()
        snapshotsByFilter = await buildSnapshots()
        RecoveryDisplayDiskCache.save(snapshotsByFilter, anchorDay: today)
        updateProAthleteData()
    }

    /// Builds the per-filter snapshot grid for the recovery view.
    ///
    /// Heavy work (49 per-day score calls per refresh) used to run on the main actor
    /// **and** rebuilt `Dictionary(uniqueKeysWithValues: dailyHRV.map ...)` for every
    /// call. Now we capture the engine's published state into a `RecoveryComputationContext`
    /// (one allocation) plus a few extra maps, then run the snapshot loop on a detached
    /// `Task.detached(priority: .userInitiated)` so SwiftUI stays responsive.
    @MainActor
    private func buildSnapshots() async -> [RecoveryFocusTimeFilter: RecoverySnapshot] {
        let context = RecoveryComputationContext.make(engine: healthEngine)
        let recoveryFallback = healthEngine.recoveryScore
        let anchorDay = today

        return await Task.detached(priority: .userInitiated) {
            RecoveryScoreView.computeSnapshots(
                anchorDay: anchorDay,
                context: context,
                recoveryFallback: recoveryFallback
            )
        }.value
    }

    /// Pure (Sendable-friendly) snapshot builder. Lives as a `nonisolated static`
    /// helper so the detached `Task` in `buildSnapshots()` can call it without touching
    /// `@MainActor` state. `fileprivate` is required because the result uses `RecoverySnapshot`
    /// and `RecoveryFocusTimeFilter`, which are `private` types at file scope.
    nonisolated fileprivate static func computeSnapshots(
        anchorDay: Date,
        context: RecoveryComputationContext,
        recoveryFallback: Double
    ) -> [RecoveryFocusTimeFilter: RecoverySnapshot] {
        var snapshots: [RecoveryFocusTimeFilter: RecoverySnapshot] = [:]

        for filter in RecoveryFocusTimeFilter.allCases {
            let selectedWindow = sharedDateSequence(from: filter.windowStart(anchor: anchorDay), to: anchorDay)
            let recoveryDetailByDay = Dictionary(uniqueKeysWithValues: selectedWindow.map { day in
                (day, sharedRecoveryScoreDetailed(for: day, context: context))
            })
            let recoverySeries = selectedWindow.map { day in
                (day, recoveryDetailByDay[day].flatMap { $0 }?.score ?? recoveryFallback)
            }
            let effectHRVSeries = selectedWindow.compactMap { day in
                effectHRV(on: day, context: context).map { (day, $0) }
            }
            let basalRhrSeries = selectedWindow.compactMap { day in
                basalRhr(on: day, context: context).map { (day, $0) }
            }
            let sleepSeries = selectedWindow.compactMap { day in
                sleepDuration(on: day, context: context).map { (day, $0) }
            }
            let respiratorySeries = selectedWindow.compactMap { day in
                context.respiratoryRateByDay[day].map { (day, $0) }
            }
            let spO2Series = selectedWindow.compactMap { day in
                context.spO2ByDay[day].map { (day, $0) }
            }
            let wristTemperatureSeries = selectedWindow.compactMap { day in
                context.wristTemperatureByDay[day].map { (day, $0) }
            }

            let effectHRVToday = effectHRV(on: anchorDay, context: context)
            let basalRhrToday = basalRhr(on: anchorDay, context: context)
            let sleepToday = sleepDuration(on: anchorDay, context: context)
            let sleepEfficiencyToday = sleepEfficiency(on: anchorDay, context: context, sleepDuration: sleepToday)
            let respiratoryToday = context.respiratoryRateByDay[anchorDay]
            let spO2Today = context.spO2ByDay[anchorDay]
            let wristTemperatureToday = context.wristTemperatureByDay[anchorDay]
            let recoveryInputsToday = sharedRecoveryInputs(for: anchorDay, context: context)
            let recoveryBreakdownToday = recoveryDetailByDay[anchorDay].flatMap { $0 }
            let recoveryValue = recoverySeries.last?.1 ?? recoveryFallback

            snapshots[filter] = RecoverySnapshot(
                selectedWindow: selectedWindow,
                recoverySeries: recoverySeries,
                effectHRVSeries: effectHRVSeries,
                basalRhrSeries: basalRhrSeries,
                sleepSeries: sleepSeries,
                respiratorySeries: respiratorySeries,
                spO2Series: spO2Series,
                wristTemperatureSeries: wristTemperatureSeries,
                recoveryValue: recoveryValue,
                effectHRVToday: effectHRVToday,
                basalRhrToday: basalRhrToday,
                sleepToday: sleepToday,
                sleepEfficiencyToday: sleepEfficiencyToday,
                respiratoryToday: respiratoryToday,
                spO2Today: spO2Today,
                wristTemperatureToday: wristTemperatureToday,
                recoveryInputsToday: recoveryInputsToday,
                recoveryBreakdownToday: recoveryBreakdownToday,
                recoverySignals: makeRecoverySignals(
                    effectHRVToday: effectHRVToday,
                    basalRhrToday: basalRhrToday,
                    sleepToday: sleepToday,
                    sleepEfficiencyToday: sleepEfficiencyToday,
                    respiratoryToday: respiratoryToday,
                    spO2Today: spO2Today,
                    wristTemperatureToday: wristTemperatureToday,
                    recoveryInputsToday: recoveryInputsToday,
                    recoveryBreakdown: recoveryBreakdownToday
                )
            )
        }

        return snapshots
    }

    nonisolated static func effectHRV(on day: Date, context: RecoveryComputationContext) -> Double? {
        context.effectHRV[day] ?? context.hrvByDay[day]
    }

    nonisolated static func basalRhr(on day: Date, context: RecoveryComputationContext) -> Double? {
        context.basalSleepingHeartRate[day] ?? context.dailyRestingHeartRate[day]
    }

    nonisolated static func sleepDuration(on day: Date, context: RecoveryComputationContext) -> Double? {
        context.anchoredSleepDuration[day] ?? context.dailySleepDuration[day]
    }

    nonisolated static func sleepEfficiency(on day: Date, context: RecoveryComputationContext, sleepDuration: Double?) -> Double? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        if let direct = context.sleepEfficiencyByDay[normalizedDay], direct > 0, direct <= 1.0 {
            return direct
        }
        guard let sleepDuration, sleepDuration > 0 else { return nil }
        guard let timeInBed = context.anchoredTimeInBed[normalizedDay], timeInBed > 0 else { return nil }
        guard timeInBed > sleepDuration + (1.0 / 60.0) else { return nil }
        return min(1.0, max(0.0, sleepDuration / timeInBed))
    }
    
    @MainActor
    private func updateProAthleteData() {
        guard performanceProfile.isProAthleteMode else { 
            proAthleteRecoveryData = nil
            return 
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        proAthleteRecoveryData = sharedProAthleteRecoveryScore(
            for: today,
            engine: healthEngine,
            profile: performanceProfile,
            chronicLoad: healthEngine.chronicTrainingLoad,
            athleteHistoricalMaxChronicLoad: nil
        )
    }

    nonisolated fileprivate static func makeRecoverySignals(
        effectHRVToday: Double?,
        basalRhrToday: Double?,
        sleepToday: Double?,
        sleepEfficiencyToday: Double?,
        respiratoryToday: Double?,
        spO2Today: Double?,
        wristTemperatureToday: Double?,
        recoveryInputsToday: HealthStateEngine.ProRecoveryInputs,
        recoveryBreakdown: RecoveryScoreBreakdown?
    ) -> [RecoverySignalCardModel] {
        func comp(_ k: RecoveryPipelineSignalKind) -> Double? {
            recoveryBreakdown?.componentContributions[k]
        }
        let rhrSupport = comp(.rhr)
            ?? recoveryInputsToday.restingHeartRatePenaltyZScore.map { -$0 }
        let sleepDurContrib = comp(.sleepDuration)
            ?? recoveryInputsToday.sleepRatio.map { $0 * 50 }
        let sleepEffContrib = comp(.sleepEfficiency)
            ?? recoveryInputsToday.sleepEfficiency.map { $0 * 40 }

        return [
            RecoverySignalCardModel(
                title: "Effect HRV",
                value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–",
                unit: "ms",
                detail: "HRV versus your baseline is the lead input in the core autonomic block of the recovery score.",
                tint: .mint,
                contribution: comp(.hrv) ?? recoveryInputsToday.hrvZScore,
                contributionDirection: .higherIsBetter
            ),
            RecoverySignalCardModel(
                title: "Basal Sleeping HR",
                value: basalRhrToday.map { String(format: "%.0f", $0) } ?? "–",
                unit: "bpm",
                detail: "Overnight resting HR feeds the core score; the model treats upward pressure versus baseline as a drag on recovery.",
                tint: .blue,
                contribution: rhrSupport,
                contributionDirection: .higherIsBetter
            ),
            RecoverySignalCardModel(
                title: "Sleep Duration",
                value: sleepToday.map { String(format: "%.1f", $0) } ?? "–",
                unit: "h",
                detail: "Anchored sleep duration gates the upside: short nights cap the core score even when HRV looks strong.",
                tint: .indigo,
                contribution: sleepDurContrib,
                contributionDirection: .higherIsBetter
            ),
            RecoverySignalCardModel(
                title: "Sleep Efficiency",
                value: sleepEfficiencyToday.map { String(format: "%.0f", $0 * 100) } ?? "–",
                unit: "%",
                detail: "Time asleep versus time in bed refines the sleep contribution inside the same core block.",
                tint: .cyan,
                contribution: sleepEffContrib,
                contributionDirection: .higherIsBetter
            ),
            RecoverySignalCardModel(
                title: "Respiratory Rate",
                value: respiratoryToday.map { String(format: "%.1f", $0) } ?? "–",
                unit: "/min",
                detail: "Compared with your prior-week baseline, elevations can apply a small capped adjustment after the core score is computed.",
                tint: .teal,
                contribution: comp(.respiratory),
                contributionDirection: .higherIsBetter
            ),
            RecoverySignalCardModel(
                title: "SpO2",
                value: spO2Today.map { String(format: "%.0f", $0) } ?? "–",
                unit: "%",
                detail: "Readings below your personal baseline can subtract a few points, pooled with other secondary vitals under a hard cap.",
                tint: .green,
                contribution: comp(.spO2),
                contributionDirection: .higherIsBetter
            ),
            RecoverySignalCardModel(
                title: "Wrist Temp",
                value: wristTemperatureToday.map { String(format: "%.2f", $0) } ?? "–",
                unit: "°C",
                detail: "Large deviations from your rolling baseline add a small negative adjustment when baseline quality gates pass.",
                tint: .orange,
                contribution: comp(.wristTemperature),
                contributionDirection: .higherIsBetter
            )
        ]
    }

    // The per-day helpers (`recoveryInputs`, `effectHRV`, `basalRhr`, `sleepDuration`,
    // `sleepEfficiency`) are now `nonisolated static` versions that operate on a
    // `RecoveryComputationContext`. See `computeSnapshots(...)` above.
}

private struct RecoveryTimeFilterSegmentButton: View {
    let filter: RecoveryFocusTimeFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(filter.rawValue)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected ? Color.green.opacity(0.26) : Color.white.opacity(0.08),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .catalystDesktopFocusable()
    }
}

private struct RecoverySnapshot {
    let selectedWindow: [Date]
    let recoverySeries: [(Date, Double)]
    let effectHRVSeries: [(Date, Double)]
    let basalRhrSeries: [(Date, Double)]
    let sleepSeries: [(Date, Double)]
    let respiratorySeries: [(Date, Double)]
    let spO2Series: [(Date, Double)]
    let wristTemperatureSeries: [(Date, Double)]
    let recoveryValue: Double
    let effectHRVToday: Double?
    let basalRhrToday: Double?
    let sleepToday: Double?
    let sleepEfficiencyToday: Double?
    let respiratoryToday: Double?
    let spO2Today: Double?
    let wristTemperatureToday: Double?
    let recoveryInputsToday: HealthStateEngine.ProRecoveryInputs
    let recoveryBreakdownToday: RecoveryScoreBreakdown?
    let recoverySignals: [RecoverySignalCardModel]

    static func empty(for filter: RecoveryFocusTimeFilter, anchor: Date) -> RecoverySnapshot {
        RecoverySnapshot(
            selectedWindow: sharedDateSequence(from: filter.windowStart(anchor: anchor), to: anchor),
            recoverySeries: [],
            effectHRVSeries: [],
            basalRhrSeries: [],
            sleepSeries: [],
            respiratorySeries: [],
            spO2Series: [],
            wristTemperatureSeries: [],
            recoveryValue: 0,
            effectHRVToday: nil,
            basalRhrToday: nil,
            sleepToday: nil,
            sleepEfficiencyToday: nil,
            respiratoryToday: nil,
            spO2Today: nil,
            wristTemperatureToday: nil,
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
            recoverySignals: []
        )
    }
}

private enum RecoveryFocusTimeFilter: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"

    var id: String { rawValue }

    func windowStart(anchor: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        case .week:
            return calendar.date(byAdding: .day, value: -13, to: anchor) ?? anchor
        case .month:
            return calendar.date(byAdding: .day, value: -27, to: anchor) ?? anchor
        }
    }
}

private struct RecoveryFocusState {
    let title: String
    let detail: String
    let color: Color
}

private func recoveryFocusState(for score: Double) -> RecoveryFocusState {
    switch score {
    case 90...:
        return RecoveryFocusState(title: "Full Send", detail: "Recovery reserve is high and supportive of ambitious work.", color: .green)
    case 70..<90:
        return RecoveryFocusState(title: "Perform", detail: "You rebuilt enough reserve for quality training without extra caution.", color: .mint)
    case 40..<70:
        return RecoveryFocusState(title: "Adapt", detail: "Recovery is workable, but there is less margin than ideal.", color: .orange)
    default:
        return RecoveryFocusState(title: "Recover", detail: "Reserve looks limited, so the better move is to restore rather than press.", color: .red)
    }
}

private struct RecoverySignalCardModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let detail: String
    let tint: Color
    let contribution: Double?
    let contributionDirection: ContributionDirection
    
    enum ContributionDirection {
        case higherIsBetter
        case lowerIsBetter
        case consistency
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

private struct RecoverySignalCard: View {
    let model: RecoverySignalCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let badge = model.contributionBadge {
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

private struct RecoveryHeroPill: View {
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

private struct RecoveryHalo: View {
    let score: Double
    let tint: Color
    @State private var animatedScore: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 112, height: 112)
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 12)
                .frame(width: 112, height: 112)
            Circle()
                .trim(from: 0, to: animatedScore / 100)
                .stroke(
                    LinearGradient(colors: [tint.opacity(0.35), tint], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 112, height: 112)
            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("recover")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: score) { oldValue, newValue in
            withAnimation(.spring(response: 1.0, dampingFraction: 0.82)) {
                animatedScore = newValue
            }
        }
        .onAppear {
            animatedScore = score
        }
    }
}

private func recoveryScoreFooterLines(
    breakdown: RecoveryScoreBreakdown?,
    inputs: HealthStateEngine.ProRecoveryInputs
) -> [String] {
    if let b = breakdown {
        var lines: [String] = [
            "Core score (autonomic + sleep backbone): \(String(format: "%.0f", b.coreScore))/100.",
            "Secondary vitals vs your prior-week baseline: \(String(format: "%.1f", b.secondaryDelta)) pts total (cap ±\(Int(RecoveryPhysiologyModel.secondaryAdjustmentCap))). Agreement bonus: \(String(format: "%.0f", b.agreementBonus)). Final: \(String(format: "%.0f", b.score))/100.",
            "Confidence for downstream readiness blending: \(String(format: "%.0f", b.confidence01 * 100))%."
        ]
        let missing = b.coverage.filter { $0.state == .missing }.map(\.signal.rawValue)
        if !missing.isEmpty {
            lines.append("Missing today: \(missing.joined(separator: ", ")).")
        }
        return lines
    }
    return [
        "Detailed breakdown unavailable. Raw inputs — HRV z \(recoveryFocusFormatted(inputs.hrvZScore, digits: 2)), RHR penalty z \(recoveryFocusFormatted(inputs.restingHeartRatePenaltyZScore, digits: 2)), sleep ratio \(recoveryFocusFormatted(inputs.sleepRatio, digits: 2))."
    ]
}

private func recoveryFocusFormatted(_ value: Double?, digits: Int) -> String {
    guard let value else { return "–" }
    return String(format: "%.\(digits)f", value)
}

// MARK: - Recovery display disk cache

private struct RecoveryScoreDV: Codable {
    var d: TimeInterval
    var y: Double
}

private struct RecoveryPersistedProRecoveryInputs: Codable {
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

private struct RecoverySignalDiskCard: Codable {
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

    init(_ m: RecoverySignalCardModel) {
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

    var asModel: RecoverySignalCardModel {
        let dir: RecoverySignalCardModel.ContributionDirection
        switch direction {
        case "lower": dir = .lowerIsBetter
        case "consistency": dir = .consistency
        default: dir = .higherIsBetter
        }
        return RecoverySignalCardModel(
            title: title,
            value: value,
            unit: unit,
            detail: detail,
            tint: Color(red: tr, green: tg, blue: tb, opacity: ta),
            contribution: contribution,
            contributionDirection: dir
        )
    }
}

private struct RecoverySnapshotDisk: Codable {
    var selectedWindow: [TimeInterval]
    var recoverySeries: [RecoveryScoreDV]
    var effectHRVSeries: [RecoveryScoreDV]
    var basalRhrSeries: [RecoveryScoreDV]
    var sleepSeries: [RecoveryScoreDV]
    var respiratorySeries: [RecoveryScoreDV]
    var spO2Series: [RecoveryScoreDV]
    var wristTemperatureSeries: [RecoveryScoreDV]
    var recoveryValue: Double
    var effectHRVToday: Double?
    var basalRhrToday: Double?
    var sleepToday: Double?
    var sleepEfficiencyToday: Double?
    var respiratoryToday: Double?
    var spO2Today: Double?
    var wristTemperatureToday: Double?
    var recoveryInputs: RecoveryPersistedProRecoveryInputs
    var recoverySignals: [RecoverySignalDiskCard]
    var recoveryBreakdown: RecoveryScoreBreakdown?

    init(snapshot: RecoverySnapshot) {
        selectedWindow = snapshot.selectedWindow.map(\.timeIntervalSince1970)
        recoverySeries = snapshot.recoverySeries.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        effectHRVSeries = snapshot.effectHRVSeries.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        basalRhrSeries = snapshot.basalRhrSeries.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        sleepSeries = snapshot.sleepSeries.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        respiratorySeries = snapshot.respiratorySeries.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        spO2Series = snapshot.spO2Series.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        wristTemperatureSeries = snapshot.wristTemperatureSeries.map { RecoveryScoreDV(d: $0.0.timeIntervalSince1970, y: $0.1) }
        recoveryValue = snapshot.recoveryValue
        effectHRVToday = snapshot.effectHRVToday
        basalRhrToday = snapshot.basalRhrToday
        sleepToday = snapshot.sleepToday
        sleepEfficiencyToday = snapshot.sleepEfficiencyToday
        respiratoryToday = snapshot.respiratoryToday
        spO2Today = snapshot.spO2Today
        wristTemperatureToday = snapshot.wristTemperatureToday
        recoveryInputs = RecoveryPersistedProRecoveryInputs(snapshot.recoveryInputsToday)
        recoverySignals = snapshot.recoverySignals.map(RecoverySignalDiskCard.init)
        recoveryBreakdown = snapshot.recoveryBreakdownToday
    }

    func asSnapshot() -> RecoverySnapshot {
        let cal = Calendar.current
        func mapPairs(_ rows: [RecoveryScoreDV]) -> [(Date, Double)] {
            rows.map { (cal.startOfDay(for: Date(timeIntervalSince1970: $0.d)), $0.y) }
        }
        return RecoverySnapshot(
            selectedWindow: selectedWindow.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0)) },
            recoverySeries: mapPairs(recoverySeries),
            effectHRVSeries: mapPairs(effectHRVSeries),
            basalRhrSeries: mapPairs(basalRhrSeries),
            sleepSeries: mapPairs(sleepSeries),
            respiratorySeries: mapPairs(respiratorySeries),
            spO2Series: mapPairs(spO2Series),
            wristTemperatureSeries: mapPairs(wristTemperatureSeries),
            recoveryValue: recoveryValue,
            effectHRVToday: effectHRVToday,
            basalRhrToday: basalRhrToday,
            sleepToday: sleepToday,
            sleepEfficiencyToday: sleepEfficiencyToday,
            respiratoryToday: respiratoryToday,
            spO2Today: spO2Today,
            wristTemperatureToday: wristTemperatureToday,
            recoveryInputsToday: recoveryInputs.asInputs,
            recoveryBreakdownToday: recoveryBreakdown,
            recoverySignals: recoverySignals.map(\.asModel)
        )
    }
}

private struct RecoveryStoreDiskEnvelope: Codable {
    var v: Int
    var anchor: TimeInterval
    var savedAt: TimeInterval
    var snapshots: [String: RecoverySnapshotDisk]

    init(snapshotsByFilter: [RecoveryFocusTimeFilter: RecoverySnapshot], anchorDay: Date) {
        v = 2
        anchor = anchorDay.timeIntervalSince1970
        savedAt = Date().timeIntervalSince1970
        let day = Calendar.current.startOfDay(for: anchorDay)
        var out: [String: RecoverySnapshotDisk] = [:]
        for filter in RecoveryFocusTimeFilter.allCases {
            let snap = snapshotsByFilter[filter] ?? RecoverySnapshot.empty(for: filter, anchor: day)
            out[filter.rawValue] = RecoverySnapshotDisk(snapshot: snap)
        }
        snapshots = out
    }

    func asSnapshotsByFilter(anchorDay: Date) -> [RecoveryFocusTimeFilter: RecoverySnapshot] {
        let day = Calendar.current.startOfDay(for: anchorDay)
        var out: [RecoveryFocusTimeFilter: RecoverySnapshot] = [:]
        for filter in RecoveryFocusTimeFilter.allCases {
            if let disk = snapshots[filter.rawValue] {
                out[filter] = disk.asSnapshot()
            } else {
                out[filter] = RecoverySnapshot.empty(for: filter, anchor: day)
            }
        }
        return out
    }
}

private enum RecoveryDisplayDiskCache {
    private static let fileName = "recovery-display-v1.json"
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    static func loadIfMatches(anchorDay: Date) -> [RecoveryFocusTimeFilter: RecoverySnapshot]? {
        let day = Calendar.current.startOfDay(for: anchorDay)
        guard let url = try? NutrivanceViewMetricDisplayCacheURL.fileURL(named: fileName),
              let data = try? Data(contentsOf: url),
              let env = try? decoder.decode(RecoveryStoreDiskEnvelope.self, from: data) else {
            return nil
        }
        let cachedAnchor = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: env.anchor))
        guard cachedAnchor == day else { return nil }
        return env.asSnapshotsByFilter(anchorDay: day)
    }

    static func save(_ snapshotsByFilter: [RecoveryFocusTimeFilter: RecoverySnapshot], anchorDay: Date) {
        let day = Calendar.current.startOfDay(for: anchorDay)
        let env = RecoveryStoreDiskEnvelope(snapshotsByFilter: snapshotsByFilter, anchorDay: day)
        guard let url = try? NutrivanceViewMetricDisplayCacheURL.fileURL(named: fileName),
              let data = try? encoder.encode(env) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

#Preview {
    RecoveryScoreView()
}
