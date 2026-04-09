import Foundation
import HealthKit
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
#endif

/// Experimental screen: summarizes the latest workout vs the prior ~6 days using HealthKit-backed analytics,
/// then runs a local MLX instruct model (Hugging Face–hosted weights) for coach-style interpretation.
struct WorkoutTrendProbeView: View {
    @ObservedObject private var engine = HealthStateEngine.shared
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var modelOutput: String = ""
    @State private var errorText: String?
    @State private var dataPayload: String = ""
    @State private var comparison: WorkoutTrendComparisonSnapshot?
    @State private var mlxDownloadProgress: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Latest workout vs last 7 days")
                    .font(.title2.bold())

                Text(
                    "Builds a fact sheet from cached analytics, then runs a small on-device MLX model (downloads once from Hugging Face). Simulator uses numeric fallback—use a physical device for MLX."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                #if canImport(MLXLLM) && canImport(MLX)
                Text(WorkoutTrendMLXModelSelection.userFacingLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                #endif

                if !dataPayload.isEmpty {
                    Group {
                        Text("Data sent to model")
                            .font(.headline)
                        Text(dataPayload)
                            .font(.caption.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await refreshData() }
                    } label: {
                        Label("Refresh data", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)

                    Button {
                        Task { await runAnalysis() }
                    } label: {
                        Label("Run trend pass", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || dataPayload.isEmpty || isGenerating)
                }

                if isLoading {
                    ProgressView("Loading workouts…")
                } else if isGenerating {
                    if let mlxDownloadProgress {
                        ProgressView(value: mlxDownloadProgress) {
                            Text("Downloading model…")
                        } currentValueLabel: {
                            Text("\(Int((mlxDownloadProgress * 100).rounded()))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView("Generating…")
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !modelOutput.isEmpty {
                    Text("Output")
                        .font(.headline)
                    Text(modelOutput)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Experimental tooling—not medical advice. Verify trends against your own judgment and coaching.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle("Trend probe")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshData()
        }
    }

    @MainActor
    private func refreshData() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        await engine.refreshWorkoutAnalytics(days: 21, forceRefresh: false)

        guard let pack = Self.buildSevenDayPack(from: engine.workoutAnalytics) else {
            dataPayload = ""
            comparison = nil
            modelOutput = ""
            errorText = "No workouts in the last 7 days (or analytics not loaded yet)."
            return
        }

        #if !os(visionOS)
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        if let vitalEndEx = cal.date(byAdding: .day, value: 1, to: todayStart),
           let vitalStart = cal.date(byAdding: .day, value: -13, to: todayStart) {
            await engine.ensureRecoveryMetricsCoverage(from: vitalStart, to: vitalEndEx)
        }
        let strainRecoveryBlock = workoutTrendProbeStrainRecoveryContext(for: engine)
        #else
        let strainRecoveryBlock = ""
        #endif

        dataPayload = pack.factsForModel
            + (strainRecoveryBlock.isEmpty ? "" : "\n\n" + strainRecoveryBlock)
        comparison = pack.comparison
        modelOutput = ""
        errorText = nil
    }

    @MainActor
    private func runAnalysis() async {
        guard !dataPayload.isEmpty else { return }
        isGenerating = true
        errorText = nil
        mlxDownloadProgress = nil
        defer {
            isGenerating = false
            mlxDownloadProgress = nil
        }

        if WorkoutTrendMLXCoach.isSimulatorUnsupported {
            modelOutput = Self.heuristicSummary(comparison: comparison)
            errorText = "iOS Simulator does not run MLX Metal inference—showing numeric fallback."
            return
        }

        do {
            let text = try await WorkoutTrendMLXCoach.coachAnalysis(factSheet: dataPayload) { frac in
                Task { @MainActor in
                    mlxDownloadProgress = frac
                }
            }
            modelOutput = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            modelOutput = Self.heuristicSummary(comparison: comparison)
            errorText = "MLX error—showing fallback. (\(error.localizedDescription))"
        }
    }

    // MARK: - Packing

    private struct SevenDayPack {
        let factsForModel: String
        let comparison: WorkoutTrendComparisonSnapshot
    }

    private static func buildSevenDayPack(from analytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)]) -> SevenDayPack? {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let windowStart = cal.date(byAdding: .day, value: -6, to: dayStart),
              let windowEndExclusive = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }

        let windowed = analytics.filter { pair in
            let t = pair.workout.startDate
            return t >= windowStart && t < windowEndExclusive
        }
        .sorted { $0.workout.startDate > $1.workout.startDate }

        guard let latest = windowed.first else { return nil }
        let prior = Array(windowed.dropFirst())

        func minutes(_ w: HKWorkout) -> Double { w.duration / 60.0 }
        func kcal(_ w: HKWorkout) -> Double? {
            w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        }
        func km(_ w: HKWorkout) -> Double? {
            w.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }
        }

        let latestType = latest.workout.workoutActivityType
        let latestTypeName = latestType.name
        let priorSameType = prior.filter { $0.workout.workoutActivityType == latestType }

        let latestLine = formatWorkoutLine(label: "LATEST", pair: latest)
        let priorLines = prior.prefix(12).map { formatWorkoutLine(label: "PRIOR", pair: $0) }.joined(separator: "\n")

        let durPrior = prior.map { minutes($0.workout) }
        let kcalPrior = prior.compactMap { kcal($0.workout) }
        let peakPrior = prior.compactMap { $0.analytics.peakHR }
        let metPrior = prior.compactMap { $0.analytics.metAverage }
        let elevPrior = prior.compactMap { $0.analytics.elevationGain }
        let highZonePrior = prior.compactMap { highZoneMinutes($0.analytics) }

        let medDur = median(durPrior)
        let medKcal = median(kcalPrior)
        let medPeak = median(peakPrior)
        let medMet = median(metPrior)
        let medElev = median(elevPrior)
        let medHighZ = median(highZonePrior)

        let stDur = priorSameType.map { minutes($0.workout) }
        let stKcal = priorSameType.compactMap { kcal($0.workout) }
        let stPeak = priorSameType.compactMap { $0.analytics.peakHR }
        let stMet = priorSameType.compactMap { $0.analytics.metAverage }
        let stElev = priorSameType.compactMap { $0.analytics.elevationGain }
        let stHighZ = priorSameType.compactMap { highZoneMinutes($0.analytics) }

        let medStDur = median(stDur)
        let medStKcal = median(stKcal)
        let medStPeak = median(stPeak)
        let medStMet = median(stMet)
        let medStElev = median(stElev)
        let medStHighZ = median(stHighZ)

        let sameTypePriorLines = priorSameType.prefix(8).map { formatWorkoutLine(label: "PRIOR_SAME_TYPE", pair: $0) }.joined(separator: "\n")
        let sameTypeBlock: String
        if priorSameType.isEmpty {
            sameTypeBlock = """
            PRIMARY (same activity type as latest: \(latestTypeName)): no other sessions of this type in the 7-day window before this latest one. \
            For trend language, compare the latest workout cautiously to ALL-TYPE priors below, and say the same-type sample is empty.
            """
        } else {
            sameTypeBlock = """
            PRIMARY (same activity type as latest: \(latestTypeName)): \(priorSameType.count) prior session(s) of this type in the window (excluding latest). \
            Use these medians and lines as the main benchmark for how the latest \(latestTypeName) session looks versus recent same-type work.

            Same-type PRIOR medians (excluding latest):
            median duration_min: \(medStDur.map { String(format: "%.1f", $0) } ?? "n/a"); \
            median active_energy_kcal: \(medStKcal.map { String(format: "%.0f", $0) } ?? "n/a"); \
            median peak_hr_bpm: \(medStPeak.map { String(format: "%.0f", $0) } ?? "n/a"); \
            median met_avg: \(medStMet.map { String(format: "%.2f", $0) } ?? "n/a"); \
            median elevation_gain_m: \(medStElev.map { String(format: "%.0f", $0) } ?? "n/a"); \
            median minutes Z4_or_higher: \(medStHighZ.map { String(format: "%.1f", $0) } ?? "n/a")

            Same-type prior sessions (up to 8, newest first after latest):
            \(sameTypePriorLines)
            """
        }

        let summary = """
        Window: local days including today (7-day rolling from \(formattedDate(windowStart)) through \(formattedDate(dayStart))).
        Workout count in window: \(windowed.count) (latest + \(prior.count) prior in list).

        \(sameTypeBlock)

        CONTEXT (all activity types combined): prior medians across every prior session in the window, regardless of type—use only as background if same-type data is thin.
        median duration_min: \(medDur.map { String(format: "%.1f", $0) } ?? "n/a"); \
        median active_energy_kcal: \(medKcal.map { String(format: "%.0f", $0) } ?? "n/a"); \
        median peak_hr_bpm: \(medPeak.map { String(format: "%.0f", $0) } ?? "n/a"); \
        median met_avg: \(medMet.map { String(format: "%.2f", $0) } ?? "n/a"); \
        median elevation_gain_m: \(medElev.map { String(format: "%.0f", $0) } ?? "n/a"); \
        median minutes Z4_or_higher: \(medHighZ.map { String(format: "%.1f", $0) } ?? "n/a")

        \(latestLine)

        Recent prior sessions of any type (up to 12, newest first after latest):
        \(priorLines.isEmpty ? "(none)" : priorLines)
        """

        let snapshot = WorkoutTrendComparisonSnapshot(
            workoutCountInWindow: windowed.count,
            latestWorkoutTypeName: latestTypeName,
            sameTypePriorCount: priorSameType.count,
            latestDurationMinutes: minutes(latest.workout),
            latestKilocalories: kcal(latest.workout),
            latestPeakHR: latest.analytics.peakHR,
            priorMedianDurationMinutes: medDur,
            priorMedianKilocalories: medKcal,
            priorMedianPeakHR: medPeak,
            sameTypePriorMedianDurationMinutes: medStDur,
            sameTypePriorMedianKilocalories: medStKcal,
            sameTypePriorMedianPeakHR: medStPeak
        )

        return SevenDayPack(factsForModel: summary, comparison: snapshot)
    }

    private static func formatWorkoutLine(label: String, pair: (workout: HKWorkout, analytics: WorkoutAnalytics)) -> String {
        let w = pair.workout
        let a = pair.analytics
        let type = w.workoutActivityType.name
        let start = formattedDateTime(w.startDate)
        let durMin = w.duration / 60.0
        let kc = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        let distKm = w.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }
        let peak = a.peakHR.map { Int($0.rounded()) }
        let kcalStr = kc.map { String(format: "%.0f kcal", $0) } ?? "kcal n/a"
        let distStr = distKm.map { String(format: "%.2f km", $0) } ?? "dist n/a"
        let peakStr = peak.map { "\($0) bpm peak" } ?? "peak hr n/a"
        let metStr = a.metAverage.map { String(format: "MET_avg %.2f", $0) } ?? "MET n/a"
        let elevStr = a.elevationGain.map { String(format: "elev_gain %.0f m", $0) } ?? "elev n/a"
        let vo2Str = a.vo2Max.map { String(format: "vo2max %.1f", $0) } ?? "vo2 n/a"
        let zoneStr = zoneEffortSummary(a)
        let highZ = highZoneMinutes(a).map { String(format: "Z4+ %.0f min", $0) } ?? "Z4+ n/a"
        return "[\(label)] \(type) @ \(start) | \(String(format: "%.0f", durMin)) min | \(kcalStr) | \(distStr) | \(peakStr) | \(metStr) | \(elevStr) | \(vo2Str) | \(highZ) | \(zoneStr)"
    }

    /// Sum time in zones numbered 4+ (typical threshold / high intensity) when zone breakdown exists.
    private static func highZoneMinutes(_ a: WorkoutAnalytics) -> Double? {
        guard !a.hrZoneBreakdown.isEmpty else { return nil }
        let seconds = a.hrZoneBreakdown
            .filter { $0.zone.zoneNumber >= 4 }
            .map(\.timeInZone)
            .reduce(0, +)
        guard seconds > 0 else { return nil }
        return seconds / 60.0
    }

    private static func zoneEffortSummary(_ a: WorkoutAnalytics) -> String {
        guard !a.hrZoneBreakdown.isEmpty else { return "zones n/a" }
        let parts = a.hrZoneBreakdown.map { entry in
            let m = entry.timeInZone / 60.0
            return "\(entry.zone.name) \(String(format: "%.0f", m))m"
        }
        return parts.joined(separator: ", ")
    }

    private static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private static func formattedDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        if s.count % 2 == 0 {
            return (s[mid - 1] + s[mid]) / 2
        }
        return s[mid]
    }

    private static func heuristicSummary(comparison: WorkoutTrendComparisonSnapshot?) -> String {
        guard let c = comparison else {
            return "Fallback: load workout data first, then run the trend pass again."
        }
        if c.workoutCountInWindow <= 1 {
            return "Fallback numeric read: only one workout showed up in the last seven local days, so there is no earlier session in that window to compare against."
        }

        let useSameType = c.sameTypePriorCount > 0
        let medDur = useSameType ? c.sameTypePriorMedianDurationMinutes : c.priorMedianDurationMinutes
        let medKcal = useSameType ? c.sameTypePriorMedianKilocalories : c.priorMedianKilocalories
        let medPeak = useSameType ? c.sameTypePriorMedianPeakHR : c.priorMedianPeakHR
        let bench = useSameType
            ? "other \(c.latestWorkoutTypeName) sessions from the past seven days"
            : "all workout types combined from the past seven days"

        var parts: [String] = []
        parts.append("Fallback summary (on-device model unavailable). ")
        if useSameType {
            parts.append(String(format: "For your latest %@, comparing against %d earlier same-type session(s) in the window. ", c.latestWorkoutTypeName, c.sameTypePriorCount))
        } else {
            parts.append(String(format: "No earlier %@ in this seven-day window, so the following uses blended medians across other activities. ", c.latestWorkoutTypeName))
        }

        if let med = medDur {
            let delta = c.latestDurationMinutes - med
            if abs(delta) < 2 {
                parts.append(String(format: "Duration is about in line with the median from those %@ (~%.0f min vs ~%.0f min). ", bench, c.latestDurationMinutes, med))
            } else if delta > 0 {
                parts.append(String(format: "Duration ran longer than that median (%.0f vs ~%.0f min). ", c.latestDurationMinutes, med))
            } else {
                parts.append(String(format: "Duration came in shorter than that median (%.0f vs ~%.0f min). ", c.latestDurationMinutes, med))
            }
        }
        if let lk = c.latestKilocalories, let mk = medKcal, mk > 0 {
            let pct = (lk - mk) / mk * 100
            if abs(pct) < 8 {
                parts.append(String(format: "Active energy is close to the median (~%.0f vs ~%.0f kcal). ", lk, mk))
            } else if pct > 0 {
                parts.append(String(format: "Active energy is above the median (%.0f vs ~%.0f kcal). ", lk, mk))
            } else {
                parts.append(String(format: "Active energy is below the median (%.0f vs ~%.0f kcal). ", lk, mk))
            }
        }
        if let lp = c.latestPeakHR, let mp = medPeak {
            if abs(lp - mp) < 5 {
                parts.append(String(format: "Peak heart rate is similar to the median (~%.0f vs ~%.0f bpm). ", lp, mp))
            } else if lp > mp {
                parts.append(String(format: "Peak heart rate is higher than the median (%.0f vs ~%.0f bpm). ", lp, mp))
            } else {
                parts.append(String(format: "Peak heart rate is lower than the median (%.0f vs ~%.0f bpm). ", lp, mp))
            }
        }
        parts.append("Check the fact sheet for the exact lines and medians.")
        return parts.joined()
    }
}

#if canImport(MLXLLM) && canImport(MLX)
// MARK: - Device-aware MLX model (mlx-swift-lm `LLMRegistry` presets)

/// Picks a Hugging Face `mlx-community` instruct checkpoint from RAM + form factor.
/// Qwen* tiers favor numeric / trend narration; Llama / Mistral are strong alternates at each size class.
@MainActor
enum WorkoutTrendMLXModelSelection {

    struct Choice: Sendable {
        let key: String
        let modelLabel: String
        let configuration: ModelConfiguration
    }

    private static let gb: UInt64 = 1024 * 1024 * 1024

    static var current: Choice {
        let ram = ProcessInfo.processInfo.physicalMemory
        let idiom = UIDevice.current.userInterfaceIdiom
        let onMac = ProcessInfo.processInfo.isiOSAppOnMac
        return choose(ram: ram, idiom: idiom, isMacCatalystOrMacApp: onMac)
    }

    static var userFacingLine: String {
        let c = current
        let ramStr = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
        let kind: String = {
            if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac (iOS app)" }
            switch UIDevice.current.userInterfaceIdiom {
            case .phone: return "iPhone"
            case .pad: return "iPad"
            case .mac: return "Mac"
            default: return "Device"
            }
        }()
        return "On-device MLX: \(c.modelLabel) — auto-selected for \(kind) with \(ramStr) RAM (first run downloads weights)."
    }

    private static func choose(ram: UInt64, idiom: UIUserInterfaceIdiom, isMacCatalystOrMacApp: Bool) -> Choice {
        if isMacCatalystOrMacApp || idiom == .mac {
            switch ram {
            case ..<(10 * gb):
                return .init(key: "llama32_3b", modelLabel: "Llama 3.2 3B Instruct (4-bit)", configuration: LLMRegistry.llama3_2_3B_4bit)
            case ..<(16 * gb):
                return .init(key: "qwen3_4b", modelLabel: "Qwen3 4B Instruct (4-bit)", configuration: LLMRegistry.qwen3_4b_4bit)
            case ..<(24 * gb):
                return .init(key: "mistral7b", modelLabel: "Mistral 7B Instruct v0.3 (4-bit)", configuration: LLMRegistry.mistral7B4bit)
            case ..<(64 * gb):
                return .init(key: "qwen3_8b", modelLabel: "Qwen3 8B Instruct (4-bit)", configuration: LLMRegistry.qwen3_8b_4bit)
            case ..<(128 * gb):
                return .init(
                    key: "baichuan14b",
                    modelLabel: "Baichuan-M1 14B Instruct (4-bit)",
                    configuration: LLMRegistry.baichuan_m1_14b_instruct_4bit
                )
            default:
                return .init(
                    key: "qwen3_moe_30b",
                    modelLabel: "Qwen3 MoE ~30B A3B (4-bit)",
                    configuration: LLMRegistry.qwen3MoE_30b_a3b_4bit
                )
            }
        }

        if idiom == .pad {
            switch ram {
            case ..<(10 * gb):
                return .init(key: "llama32_3b", modelLabel: "Llama 3.2 3B Instruct (4-bit)", configuration: LLMRegistry.llama3_2_3B_4bit)
            case ..<(16 * gb):
                return .init(key: "qwen3_4b", modelLabel: "Qwen3 4B Instruct (4-bit)", configuration: LLMRegistry.qwen3_4b_4bit)
            default:
                return .init(key: "qwen3_8b", modelLabel: "Qwen3 8B Instruct (4-bit)", configuration: LLMRegistry.qwen3_8b_4bit)
            }
        }

        if idiom == .phone {
            if ram < 7 * gb {
                return .init(key: "llama32_1b", modelLabel: "Llama 3.2 1B Instruct (4-bit)", configuration: LLMRegistry.llama3_2_1B_4bit)
            }
            return .init(key: "qwen3_17b", modelLabel: "Qwen3 1.7B Instruct (4-bit)", configuration: LLMRegistry.qwen3_1_7b_4bit)
        }

        return .init(key: "llama32_1b", modelLabel: "Llama 3.2 1B Instruct (4-bit)", configuration: LLMRegistry.llama3_2_1B_4bit)
    }
}

/// Loads a Hugging Face MLX instruct model (mlx-swift-lm) and generates coach-style copy from a fact sheet.
@MainActor
enum WorkoutTrendMLXCoach {

    static var isSimulatorUnsupported: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private static var cachedContainer: ModelContainer?
    private static var cachedSelectionKey: String?
    private static var loadTask: Task<ModelContainer, Error>?

    static func resetCachedModel() {
        cachedContainer = nil
        cachedSelectionKey = nil
        loadTask = nil
    }

    private static func memoryCacheLimitBytes(forSelectionKey key: String) -> Int {
        switch key {
        case "llama32_1b":
            return 640 * 1024 * 1024
        case "qwen3_17b", "llama32_3b", "qwen3_4b":
            return 1400 * 1024 * 1024
        case "mistral7b", "qwen3_8b":
            return 2400 * 1024 * 1024
        case "baichuan14b":
            return 4800 * 1024 * 1024
        case "qwen3_moe_30b":
            return 7200 * 1024 * 1024
        default:
            return 768 * 1024 * 1024
        }
    }

    static func ensureModelContainer(
        downloadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ModelContainer {
        let choice = WorkoutTrendMLXModelSelection.current
        if cachedSelectionKey != choice.key {
            cachedContainer = nil
            loadTask = nil
            cachedSelectionKey = nil
        }

        if let cachedContainer { return cachedContainer }
        if let loadTask { return try await loadTask.value }

        Memory.cacheLimit = memoryCacheLimitBytes(forSelectionKey: choice.key)

        let configuration = choice.configuration
        let task = Task {
            try await loadModelContainer(
                configuration: configuration,
                progressHandler: { progress in
                    downloadProgress(progress.fractionCompleted)
                }
            )
        }
        loadTask = task
        do {
            let container = try await task.value
            cachedContainer = container
            cachedSelectionKey = choice.key
            loadTask = nil
            return container
        } catch {
            loadTask = nil
            throw error
        }
    }

    static func coachAnalysis(
        factSheet: String,
        downloadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let container = try await ensureModelContainer(downloadProgress: downloadProgress)
        let session = ChatSession(
            container,
            instructions: systemInstructions,
            generateParameters: GenerateParameters(maxTokens: 480, temperature: 0.35)
        )
        let userBlock = """
        Below is one fact sheet. It includes workout lines plus a STRAIN_RECOVERY_CONTEXT block: \
        training load, strain, ACWR/load status, recovery and readiness by day, and recent HRV, resting HR, MET, and sleep where available. \
        All numbers are from the app’s own calculations over the last seven local days.

        \(factSheet)
        """
        let raw = try await session.respond(to: userBlock)
        return Self.sanitizeCoachParagraph(raw)
    }

    /// Strip common markdown/list patterns so the UI stays plain prose.
    private static func sanitizeCoachParagraph(_ text: String) -> String {
        var s = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "\n\n+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private static let systemInstructions = """
    You are a fitness coach. The user message is a structured fact sheet from the athlete’s app: recent workouts plus strain, \
    recovery, readiness, and training-load context for the last seven local days.

    Speak directly to the athlete as "you". Sound like a coach offering observations and practical training-load guidance—not \
    like someone reading a table aloud. Weave workout details together with strain, recovery, readiness, ACWR/load status, and \
    vitals when those lines are present, and say what that pattern suggests for how hard or easy you might push upcoming training, \
    without sounding robotic.

    Output rules (strict):
    - Reply with exactly one paragraph of plain text: normal sentences only, flowing prose.
    - Do not use bullet points, numbered lists, headings, bold, italics, markdown, or labels like "Thought:" or "Analysis:".
    - Do not describe your reasoning process, steps, or internal thinking—only state conclusions.
    - Anchor on the LATEST workout versus the prior seven days, preferring comparisons to earlier sessions of the SAME activity type \
    when the PRIMARY same-type section has data; if same-type history is thin, say so briefly.
    - Use only numbers and facts that appear in the fact sheet; never invent metrics.
    - No medical diagnosis, treatment, or injury advice. Keep implications tentative (e.g. suggests, seems, might).
    """
}
#else
@MainActor
enum WorkoutTrendMLXCoach {
    static var isSimulatorUnsupported: Bool { true }

    static func resetCachedModel() {}

    static func coachAnalysis(
        factSheet: String,
        downloadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        _ = factSheet
        _ = downloadProgress
        struct MLXNotLinked: Error {}
        throw MLXNotLinked()
    }
}
#endif

struct WorkoutTrendComparisonSnapshot {
    let workoutCountInWindow: Int
    let latestWorkoutTypeName: String
    let sameTypePriorCount: Int
    let latestDurationMinutes: Double
    let latestKilocalories: Double?
    let latestPeakHR: Double?
    let priorMedianDurationMinutes: Double?
    let priorMedianKilocalories: Double?
    let priorMedianPeakHR: Double?
    let sameTypePriorMedianDurationMinutes: Double?
    let sameTypePriorMedianKilocalories: Double?
    let sameTypePriorMedianPeakHR: Double?
}

#if DEBUG
#Preview {
    NavigationStack {
        WorkoutTrendProbeView()
    }
}
#endif
