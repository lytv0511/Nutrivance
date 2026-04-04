import SwiftUI

struct RecoveryScoreView: View {
    @ObservedObject private var engine = HealthStateEngine.shared

    @State private var animationPhase: Double = 0
    @State private var isLoading = false
    @State private var timeFilter: RecoveryFocusTimeFilter = .day

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var selectedWindow: [Date] {
        recoveryDateSequence(from: timeFilter.windowStart(anchor: today), to: today)
    }

    private var recoverySeries: [(Date, Double)] {
        selectedWindow.map { day in
            (day, recoveryScoreForDay(day))
        }
    }

    private var effectHRVSeries: [(Date, Double)] {
        selectedWindow.compactMap { day in
            effectHRV(on: day).map { (day, $0) }
        }
    }

    private var basalRhrSeries: [(Date, Double)] {
        selectedWindow.compactMap { day in
            basalRhr(on: day).map { (day, $0) }
        }
    }

    private var sleepSeries: [(Date, Double)] {
        selectedWindow.compactMap { day in
            sleepDuration(on: day).map { (day, $0) }
        }
    }

    private var respiratorySeries: [(Date, Double)] {
        selectedWindow.compactMap { day in
            engine.respiratoryRate[day].map { (day, $0) }
        }
    }

    private var spO2Series: [(Date, Double)] {
        selectedWindow.compactMap { day in
            engine.spO2[day].map { (day, $0) }
        }
    }

    private var wristTemperatureSeries: [(Date, Double)] {
        selectedWindow.compactMap { day in
            engine.wristTemperature[day].map { (day, $0) }
        }
    }

    private var recoveryValue: Double {
        recoveryScoreForDay(today)
    }

    private var recoveryState: RecoveryFocusState {
        recoveryFocusState(for: recoveryValue)
    }

    private var effectHRVToday: Double? {
        effectHRV(on: today)
    }

    private var basalRhrToday: Double? {
        basalRhr(on: today)
    }

    private var sleepToday: Double? {
        sleepDuration(on: today)
    }

    private var sleepEfficiencyToday: Double? {
        sleepEfficiency(on: today)
    }

    private var respiratoryToday: Double? {
        engine.respiratoryRate[today]
    }

    private var spO2Today: Double? {
        engine.spO2[today]
    }

    private var wristTemperatureToday: Double? {
        engine.wristTemperature[today]
    }

    private var recoveryInputsToday: HealthStateEngine.ProRecoveryInputs {
        recoveryInputs(for: today)
    }

    private var recoverySignals: [RecoverySignalCardModel] {
        [
            RecoverySignalCardModel(
                title: "Effect HRV",
                value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–",
                unit: "ms",
                detail: "Sleep-anchored HRV is the lead signal in your recovery model.",
                tint: .mint
            ),
            RecoverySignalCardModel(
                title: "Basal Sleeping HR",
                value: basalRhrToday.map { String(format: "%.0f", $0) } ?? "–",
                unit: "bpm",
                detail: "The lowest stable overnight heart rate helps estimate cardiovascular cost.",
                tint: .blue
            ),
            RecoverySignalCardModel(
                title: "Sleep Duration",
                value: sleepToday.map { String(format: "%.1f", $0) } ?? "–",
                unit: "h",
                detail: "Recovery still gets sleep-gated. A weak night caps the upside even with decent physiology.",
                tint: .indigo
            ),
            RecoverySignalCardModel(
                title: "Sleep Efficiency",
                value: sleepEfficiencyToday.map { String(format: "%.0f", $0 * 100) } ?? "–",
                unit: "%",
                detail: "Cleaner sleep generally preserves more of your base recovery score.",
                tint: .cyan
            ),
            RecoverySignalCardModel(
                title: "Respiratory Rate",
                value: respiratoryToday.map { String(format: "%.1f", $0) } ?? "–",
                unit: "/min",
                detail: "Breathing rate can help catch systemic stress before it shows up in performance.",
                tint: .teal
            ),
            RecoverySignalCardModel(
                title: "SpO2",
                value: spO2Today.map { String(format: "%.0f", $0) } ?? "–",
                unit: "%",
                detail: "Blood oxygen doesn’t drive the score directly, but it’s useful recovery-side context.",
                tint: .green
            ),
            RecoverySignalCardModel(
                title: "Wrist Temp",
                value: wristTemperatureToday.map { String(format: "%.2f", $0) } ?? "–",
                unit: "°C",
                detail: "Temperature shifts can flag hidden stress, travel, illness, or poor overnight recovery.",
                tint: .orange
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        recoveryHero

                        HStack(spacing: 10) {
                            ForEach(RecoveryFocusTimeFilter.allCases) { filter in
                                Button {
                                    timeFilter = filter
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            (timeFilter == filter ? Color.green.opacity(0.26) : Color.white.opacity(0.08)),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(timeFilter == filter ? 0.18 : 0.08), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())

                        MetricSectionGroup(title: "Recovery Score") {
                            HealthCard(
                                symbol: "heart.text.square.fill",
                                title: "Recovery Score",
                                value: String(format: "%.0f", recoveryValue),
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
                                    Text("Today’s model inputs: HRV z \(recoveryFocusFormatted(recoveryInputsToday.hrvZScore, digits: 2)), RHR penalty z \(recoveryFocusFormatted(recoveryInputsToday.restingHeartRatePenaltyZScore, digits: 2)), sleep ratio \(recoveryFocusFormatted(recoveryInputsToday.sleepRatio, digits: 2)).")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        MetricSectionGroup(title: "Fitness Recovery Signals") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(recoverySignals) { card in
                                    RecoverySignalCard(model: card)
                                }
                            }
                        }

                        MetricSectionGroup(title: "Drivers") {
                            HealthCard(
                                symbol: "waveform.path.ecg",
                                title: "Effect HRV",
                                value: effectHRVToday.map { String(format: "%.0f", $0) } ?? "–",
                                unit: "ms",
                                trend: "\(timeFilter.rawValue) avg: \(String(format: "%.0f", effectHRVSeries.map(\.1).average ?? 0))",
                                color: .mint,
                                chartData: effectHRVSeries,
                                chartLabel: "Effect HRV",
                                chartUnit: "ms"
                            ) {
                                Text("This is the recovery version of HRV: sleep-anchored, momentum-smoothed, and intentionally harder to distort with random daytime samples.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HealthCard(
                                symbol: "heart.fill",
                                title: "Basal Sleeping HR",
                                value: basalRhrToday.map { String(format: "%.0f", $0) } ?? "–",
                                unit: "bpm",
                                trend: "\(timeFilter.rawValue) avg: \(String(format: "%.0f", basalRhrSeries.map(\.1).average ?? 0))",
                                color: .blue,
                                chartData: basalRhrSeries,
                                chartLabel: "Basal HR",
                                chartUnit: "bpm"
                            ) {
                                Text("This is the low-end overnight heart rate signal. When it stays elevated relative to baseline, recovery usually pays a price.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HealthCard(
                                symbol: "bed.double.fill",
                                title: "Sleep Duration",
                                value: sleepToday.map { String(format: "%.1f", $0) } ?? "–",
                                unit: "h",
                                trend: "\(timeFilter.rawValue) avg: \(String(format: "%.1f", sleepSeries.map(\.1).average ?? 0))",
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
                                    Text("This doesn’t directly create the score, but it’s a useful recovery-side hint when you’re accumulating systemic fatigue.")
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
                                    Text("Oxygen saturation is a useful cross-check. Stable values support the read; unexpected drops deserve more caution.")
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
                                    Text("Temperature is especially helpful when recovery feels off but training load alone doesn’t explain it.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }

                if isLoading {
                    ProgressView("Refreshing recovery metrics...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .navigationTitle("Recovery Score")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await refreshCoverage()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.green)
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

                RecoveryHalo(score: recoveryValue, tint: recoveryState.color)
            }

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

    @MainActor
    private func refreshCoverage() async {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -35, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        isLoading = true
        await engine.ensureRecoveryMetricsCoverage(from: start, to: end)
        isLoading = false
    }

    private func recoveryScoreForDay(_ day: Date) -> Double {
        let inputs = recoveryInputs(for: day)
        guard !inputs.isInconclusive else { return engine.recoveryScore }
        return HealthStateEngine.proRecoveryScore(from: inputs)
    }

    private func recoveryInputs(for day: Date) -> HealthStateEngine.ProRecoveryInputs {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        let hrvLookup = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
        return HealthStateEngine.proRecoveryInputs(
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
    }

    private func effectHRV(on day: Date) -> Double? {
        engine.effectHRV[day] ?? Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })[day]
    }

    private func basalRhr(on day: Date) -> Double? {
        engine.basalSleepingHeartRate[day] ?? engine.dailyRestingHeartRate[day]
    }

    private func sleepDuration(on day: Date) -> Double? {
        engine.anchoredSleepDuration[day] ?? engine.dailySleepDuration[day]
    }

    private func sleepEfficiency(on day: Date) -> Double? {
        guard let sleep = sleepDuration(on: day),
              let timeInBed = engine.anchoredTimeInBed[day] ?? sleepDuration(on: day),
              timeInBed > 0 else { return nil }
        return sleep / timeInBed
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.tint.opacity(0.85))
                    .frame(width: 18, height: 18)
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
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.82)) {
                animatedScore = score
            }
        }
    }
}

private func recoveryDateSequence(from start: Date, to end: Date) -> [Date] {
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

private func recoveryFocusFormatted(_ value: Double?, digits: Int) -> String {
    guard let value else { return "–" }
    return String(format: "%.\(digits)f", value)
}

#Preview {
    RecoveryScoreView()
}
