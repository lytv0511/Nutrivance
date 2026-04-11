import Combine
import Foundation
import SwiftUI

// MARK: - Platform

/// iOS / iPadOS own canonical tuning state in iCloud and apply pending edits originating from Mac.
/// Mac Catalyst pulls iCloud state, applies merged view immediately for display, and only enqueues pending operations for handheld devices to fold into the authoritative store.
enum NutrivanceTuningPlatformPolicy {
    static var isHandheldAuthoritativeWriter: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }
}

// MARK: - Metric & factor identifiers

enum NutrivanceTuningMetric: String, Codable, CaseIterable, Identifiable {
    case recovery
    case strain
    case readiness

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .recovery: return "Recovery"
        case .strain: return "Strain"
        case .readiness: return "Readiness"
        }
    }

    var icon: String {
        switch self {
        case .recovery: return "heart.text.square.fill"
        case .strain: return "flame.fill"
        case .readiness: return "checkmark.seal.fill"
        }
    }
}

enum NutrivanceTuningFactor: String, Codable, CaseIterable, Identifiable {
    case composite
    case sleep
    case hrv
    case rhr
    case strainLoad
    case readinessBlend

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .composite: return "Overall blend"
        case .sleep: return "Sleep"
        case .hrv: return "HRV"
        case .rhr: return "Resting HR"
        case .strainLoad: return "Training load / zones"
        case .readinessBlend: return "Readiness blend"
        }
    }
}

enum NutrivanceTuningNudgeLevel: Int, Codable, CaseIterable, Identifiable {
    case light = 0
    case medium = 1
    case strong = 2

    var id: Int { rawValue }

    var scalar: Double {
        switch self {
        case .light: return 0.35
        case .medium: return 0.65
        case .strong: return 1.0
        }
    }

    var label: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

// MARK: - Report

struct NutrivanceTuningReport: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var metric: NutrivanceTuningMetric
    var factor: NutrivanceTuningFactor
    var userDirection: Double
    var nudgeLevel: NutrivanceTuningNudgeLevel
    var userNote: String
    var shortAttributionLabel: String
    var effectiveStrength: Double
    var decayRate: Double
    var lastAppliedAt: Date?
    var computedWeight: Double
    var isEnabled: Bool

    static let defaultDecayRate: Double = 0.0035

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case metric
        case factor
        case userDirection
        case nudgeLevel
        case userNote
        case shortAttributionLabel
        case effectiveStrength
        case decayRate
        case lastAppliedAt
        case computedWeight
        case isEnabled
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        metric: NutrivanceTuningMetric,
        factor: NutrivanceTuningFactor,
        userDirection: Double,
        nudgeLevel: NutrivanceTuningNudgeLevel,
        userNote: String,
        shortAttributionLabel: String,
        effectiveStrength: Double = 0.6,
        decayRate: Double = NutrivanceTuningReport.defaultDecayRate,
        lastAppliedAt: Date? = nil,
        computedWeight: Double? = nil,
        isEnabled: Bool = true
    ) {
        let clampedStrength = max(0, min(1, effectiveStrength))
        let clampedDecayRate = max(0, min(1, decayRate))
        self.id = id
        self.createdAt = createdAt
        self.metric = metric
        self.factor = factor
        self.userDirection = max(-1, min(1, userDirection))
        self.nudgeLevel = nudgeLevel
        self.userNote = userNote
        self.shortAttributionLabel = shortAttributionLabel
        self.effectiveStrength = clampedStrength
        self.decayRate = clampedDecayRate
        self.lastAppliedAt = lastAppliedAt
        self.computedWeight = max(0, min(1, computedWeight ?? Self.decayedWeight(
            baseStrength: clampedStrength,
            decayRate: clampedDecayRate,
            anchorDate: Self.decayAnchorDate(createdAt: createdAt, lastAppliedAt: lastAppliedAt),
            asOf: Date()
        )))
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let metric = try container.decode(NutrivanceTuningMetric.self, forKey: .metric)
        let factor = try container.decode(NutrivanceTuningFactor.self, forKey: .factor)
        let userDirection = try container.decodeIfPresent(Double.self, forKey: .userDirection) ?? 1
        let nudgeLevel = try container.decodeIfPresent(NutrivanceTuningNudgeLevel.self, forKey: .nudgeLevel) ?? .medium
        let userNote = try container.decodeIfPresent(String.self, forKey: .userNote) ?? ""
        let shortAttributionLabel = try container.decodeIfPresent(String.self, forKey: .shortAttributionLabel) ?? "Tuning"
        let effectiveStrength = try container.decodeIfPresent(Double.self, forKey: .effectiveStrength) ?? 0.6
        let decayRate = try container.decodeIfPresent(Double.self, forKey: .decayRate) ?? Self.defaultDecayRate
        let lastAppliedAt = try container.decodeIfPresent(Date.self, forKey: .lastAppliedAt)
        let computedWeight = try container.decodeIfPresent(Double.self, forKey: .computedWeight)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        self.init(
            id: id,
            createdAt: createdAt,
            metric: metric,
            factor: factor,
            userDirection: userDirection,
            nudgeLevel: nudgeLevel,
            userNote: userNote,
            shortAttributionLabel: shortAttributionLabel,
            effectiveStrength: effectiveStrength,
            decayRate: decayRate,
            lastAppliedAt: lastAppliedAt,
            computedWeight: computedWeight,
            isEnabled: isEnabled
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(metric, forKey: .metric)
        try container.encode(factor, forKey: .factor)
        try container.encode(userDirection, forKey: .userDirection)
        try container.encode(nudgeLevel, forKey: .nudgeLevel)
        try container.encode(userNote, forKey: .userNote)
        try container.encode(shortAttributionLabel, forKey: .shortAttributionLabel)
        try container.encode(effectiveStrength, forKey: .effectiveStrength)
        try container.encode(decayRate, forKey: .decayRate)
        try container.encodeIfPresent(lastAppliedAt, forKey: .lastAppliedAt)
        try container.encode(resolvedComputedWeight(), forKey: .computedWeight)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    var decayAnchorDate: Date {
        Self.decayAnchorDate(createdAt: createdAt, lastAppliedAt: lastAppliedAt)
    }

    func ageInDays(asOf date: Date = Date()) -> Double {
        max(0, date.timeIntervalSince(decayAnchorDate) / 86_400)
    }

    func resolvedComputedWeight(asOf date: Date = Date()) -> Double {
        Self.decayedWeight(
            baseStrength: effectiveStrength,
            decayRate: decayRate,
            anchorDate: decayAnchorDate,
            asOf: date
        )
    }

    mutating func refreshComputedWeight(asOf date: Date = Date()) {
        computedWeight = resolvedComputedWeight(asOf: date)
    }

    private static func decayAnchorDate(createdAt: Date, lastAppliedAt: Date?) -> Date {
        if let lastAppliedAt, lastAppliedAt > createdAt {
            return lastAppliedAt
        }
        return createdAt
    }

    private static func decayedWeight(
        baseStrength: Double,
        decayRate: Double,
        anchorDate: Date,
        asOf date: Date
    ) -> Double {
        let clampedStrength = max(0, min(1, baseStrength))
        let clampedDecayRate = max(0, min(1, decayRate))
        let ageInDays = max(0, date.timeIntervalSince(anchorDate) / 86_400)
        let decayMultiplier = Foundation.exp(-clampedDecayRate * ageInDays)
        return max(0, min(1, clampedStrength * decayMultiplier))
    }
}

// MARK: - iCloud keys & payloads

private let kAuthoritativeKey = "nutrivance_tuning_authoritative_v1"
private let kPendingIOSKey = "nutrivance_tuning_pending_ios_v1"
private let kLocalMirrorReports = "nutrivance_tuning_reports_local_v1"
private let kLocalMirrorMetrics = "nutrivance_tuning_metric_enabled_v1"
private let kTestingOverlayLocal = "nutrivance_tuning_testing_overlay"

struct NutrivanceTuningAuthoritativeState: Codable, Equatable {
    var reports: [NutrivanceTuningReport]
    var metricGloballyEnabled: [String: Bool]
    var lastModified: Date

    static let empty = NutrivanceTuningAuthoritativeState(
        reports: [],
        metricGloballyEnabled: Dictionary(uniqueKeysWithValues: NutrivanceTuningMetric.allCases.map { ($0.rawValue, true) }),
        lastModified: .distantPast
    )
}

/// Operations queued from Mac for iPhone/iPad to merge into the authoritative store.
enum NutrivanceTuningPendingOperation: Codable, Equatable {
    case upsert(NutrivanceTuningReport)
    case delete(UUID)
    case metricToggle(metricRaw: String, enabled: Bool)
}

// MARK: - Display result

struct NutrivanceTuningDisplayResult: Equatable {
    var base: Double
    var adjusted: Double
    var delta: Double
    var contributingReports: [NutrivanceTuningReport]
}

// MARK: - Engine

enum NutrivanceTuningEngine {
    private static let maxDeltaRecovery: Double = 6
    private static let maxDeltaStrain: Double = 1.5
    private static let maxDeltaReadiness: Double = 6

    static func maximumDelta(for metric: NutrivanceTuningMetric) -> Double {
        switch metric {
        case .recovery: return maxDeltaRecovery
        case .strain: return maxDeltaStrain
        case .readiness: return maxDeltaReadiness
        }
    }

    static func reportSignal(for report: NutrivanceTuningReport, asOf date: Date = Date()) -> Double {
        let sign = report.userDirection >= 0 ? 1.0 : -1.0
        let magnitude = abs(report.userDirection) > 0.01 ? abs(report.userDirection) : 1.0
        return sign * magnitude * report.nudgeLevel.scalar * report.resolvedComputedWeight(asOf: date)
    }

    static func reportDisplayDelta(
        for report: NutrivanceTuningReport,
        metric: NutrivanceTuningMetric,
        asOf date: Date = Date()
    ) -> Double {
        reportSignal(for: report, asOf: date) * (maximumDelta(for: metric) / 3.0)
    }

    static func display(
        base: Double,
        metric: NutrivanceTuningMetric,
        store: NutrivanceTuningStore
    ) -> NutrivanceTuningDisplayResult {
        display(
            base: base,
            metric: metric,
            reports: store.reports,
            isMetricEnabled: store.isMetricGloballyEnabled(metric)
        )
    }

    static func display(
        base: Double,
        metric: NutrivanceTuningMetric,
        reports: [NutrivanceTuningReport],
        isMetricEnabled: Bool = true,
        asOf date: Date = Date()
    ) -> NutrivanceTuningDisplayResult {
        guard isMetricEnabled else {
            return NutrivanceTuningDisplayResult(base: base, adjusted: base, delta: 0, contributingReports: [])
        }
        let active = reports.filter { $0.isEnabled && $0.metric == metric }
        guard !active.isEmpty else {
            return NutrivanceTuningDisplayResult(base: base, adjusted: base, delta: 0, contributingReports: [])
        }

        var sum: Double = 0
        var contributors: [NutrivanceTuningReport] = []

        for report in active.sorted(by: { $0.createdAt < $1.createdAt }) {
            sum += reportSignal(for: report, asOf: date)
            contributors.append(report)
        }

        let maxD = maximumDelta(for: metric)
        let rawDelta = max(-maxD, min(maxD, sum * (maxD / 3.0)))
        let adjusted: Double = {
            switch metric {
            case .recovery, .readiness:
                return max(0, min(100, base + rawDelta))
            case .strain:
                return max(0, min(21, base + rawDelta))
            }
        }()

        return NutrivanceTuningDisplayResult(
            base: base,
            adjusted: adjusted,
            delta: adjusted - base,
            contributingReports: contributors
        )
    }
}

// MARK: - Store

final class NutrivanceTuningStore: ObservableObject {
    static let shared = NutrivanceTuningStore()

    private let cloud = NSUbiquitousKeyValueStore.default
    private var externalChangeCancellable: AnyCancellable?

    @Published private(set) var reports: [NutrivanceTuningReport] = []
    @Published var metricGloballyEnabled: [NutrivanceTuningMetric: Bool] = [
        .recovery: true,
        .strain: true,
        .readiness: true
    ]
    @Published var showTestingOverlay: Bool = false {
        didSet { UserDefaults.standard.set(showTestingOverlay, forKey: kTestingOverlayLocal) }
    }
    @Published var canvasCardPositions: [String: CGPoint] = [:]

    /// Pending ops from Mac (also mirrored on Mac after enqueue) until iOS merges.
    @Published private(set) var pendingIOSOperations: [NutrivanceTuningPendingOperation] = []

    private init() {
        showTestingOverlay = UserDefaults.standard.object(forKey: kTestingOverlayLocal) as? Bool ?? false
        loadLocalFirstThenCloud()
        externalChangeCancellable = NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadFromICloud()
            }
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            processPendingQueueFromMac()
        }
    }

    func isMetricGloballyEnabled(_ metric: NutrivanceTuningMetric) -> Bool {
        metricGloballyEnabled[metric, default: true]
    }

    func setMetricGloballyEnabled(_ metric: NutrivanceTuningMetric, enabled: Bool) {
        metricGloballyEnabled[metric] = enabled
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            persistAuthoritativeToICloud()
        } else {
            pendingIOSOperations.append(.metricToggle(metricRaw: metric.rawValue, enabled: enabled))
            persistPendingToICloud()
            mirrorLocalCache()
        }
    }

    func addReport(_ report: NutrivanceTuningReport) {
        let normalized = refreshedReport(report, touchedAt: report.lastAppliedAt ?? Date())
        reports.append(normalized)
        reinforceAllReportsInPlace()
        let finalReport = reports.first(where: { $0.id == report.id }) ?? normalized
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            persistAuthoritativeToICloud()
        } else {
            pendingIOSOperations.append(.upsert(finalReport))
            persistPendingToICloud()
            mirrorLocalCache()
        }
    }

    func updateReport(_ report: NutrivanceTuningReport) {
        guard let idx = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[idx] = refreshedReport(report, touchedAt: Date())
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            persistAuthoritativeToICloud()
        } else {
            pendingIOSOperations.append(.upsert(reports[idx]))
            persistPendingToICloud()
            mirrorLocalCache()
        }
    }

    func deleteReport(id: UUID) {
        reports.removeAll { $0.id == id }
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            persistAuthoritativeToICloud()
        } else {
            pendingIOSOperations.append(.delete(id))
            persistPendingToICloud()
            mirrorLocalCache()
        }
    }

    func setEffectiveStrength(id: UUID, strength: Double) {
        guard let idx = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[idx].effectiveStrength = max(0, min(1, strength))
        reports[idx].lastAppliedAt = Date()
        reports[idx].refreshComputedWeight()
        let copy = reports[idx]
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            persistAuthoritativeToICloud()
        } else {
            pendingIOSOperations.append(.upsert(copy))
            persistPendingToICloud()
            mirrorLocalCache()
        }
    }

    private func reinforceAllReportsInPlace() {
        for i in reports.indices {
            var r = reports[i]
            let peers = reports.enumerated().filter { $0.offset != i && $0.element.metric == r.metric && $0.element.factor == r.factor }
            var delta = 0.0
            for (_, p) in peers {
                let sameSign = (p.userDirection >= 0) == (r.userDirection >= 0)
                delta += sameSign ? 0.04 : -0.06
            }
            r.effectiveStrength = max(0.15, min(1, r.effectiveStrength + delta))
            r.lastAppliedAt = Date()
            r.refreshComputedWeight()
            reports[i] = r
        }
    }

    // MARK: - iCloud

    private func loadLocalFirstThenCloud() {
        if let data = UserDefaults.standard.data(forKey: kLocalMirrorReports),
           let decoded = try? JSONDecoder().decode([NutrivanceTuningReport].self, from: data) {
            reports = refreshedReports(decoded)
        }
        if let data = UserDefaults.standard.data(forKey: kLocalMirrorMetrics),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            for m in NutrivanceTuningMetric.allCases {
                if let v = decoded[m.rawValue] {
                    metricGloballyEnabled[m] = v
                }
            }
        }
        cloud.synchronize()
        reloadFromICloud()
    }

    private func reloadFromICloud() {
        cloud.synchronize()

        let auth: NutrivanceTuningAuthoritativeState = {
            if let authData = cloud.data(forKey: kAuthoritativeKey),
               let a = try? JSONDecoder().decode(NutrivanceTuningAuthoritativeState.self, from: authData) {
                return a
            }
            return .empty
        }()

        var pending: [NutrivanceTuningPendingOperation] = []
        if let pData = cloud.data(forKey: kPendingIOSKey),
           let p = try? JSONDecoder().decode([NutrivanceTuningPendingOperation].self, from: pData) {
            pending = p
        }
        pendingIOSOperations = pending

        applyMetricDict(auth.metricGloballyEnabled)

        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            reports = refreshedReports(auth.reports)
        } else {
            // Mac: merge iCloud authoritative state with pending queue for immediate display.
            let merged = mergedReportsAndMetrics(authoritative: auth, pending: pending)
            reports = refreshedReports(merged.reports)
            applyMetricDict(merged.metrics)
        }

        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            processPendingQueueFromMac()
        }

        mirrorLocalCache()
        objectWillChange.send()
    }

    private func mergedReportsAndMetrics(authoritative: NutrivanceTuningAuthoritativeState, pending: [NutrivanceTuningPendingOperation]) -> (reports: [NutrivanceTuningReport], metrics: [String: Bool]) {
        var map = Dictionary(uniqueKeysWithValues: refreshedReports(authoritative.reports).map { ($0.id, $0) })
        var metrics = authoritative.metricGloballyEnabled

        for op in pending {
            switch op {
            case .upsert(let r):
                map[r.id] = refreshedReport(r)
            case .delete(let id):
                map[id] = nil
            case .metricToggle(let raw, let enabled):
                metrics[raw] = enabled
            }
        }

        let list = map.values.sorted { $0.createdAt < $1.createdAt }
        return (list, metrics)
    }

    private func applyMetricDict(_ dict: [String: Bool]) {
        for m in NutrivanceTuningMetric.allCases {
            if let v = dict[m.rawValue] {
                metricGloballyEnabled[m] = v
            }
        }
    }

    private func persistAuthoritativeToICloud() {
        reports = refreshedReports(reports)
        var dict: [String: Bool] = [:]
        for m in NutrivanceTuningMetric.allCases {
            dict[m.rawValue] = metricGloballyEnabled[m, default: true]
        }
        let state = NutrivanceTuningAuthoritativeState(
            reports: reports,
            metricGloballyEnabled: dict,
            lastModified: Date()
        )
        if let data = try? JSONEncoder().encode(state) {
            cloud.set(data, forKey: kAuthoritativeKey)
            cloud.synchronize()
        }
        mirrorLocalCache()
    }

    private func persistPendingToICloud() {
        guard let data = try? JSONEncoder().encode(pendingIOSOperations) else { return }
        cloud.set(data, forKey: kPendingIOSKey)
        cloud.synchronize()
    }

    private func mirrorLocalCache() {
        reports = refreshedReports(reports)
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: kLocalMirrorReports)
        }
        let dict = Dictionary(uniqueKeysWithValues: NutrivanceTuningMetric.allCases.map { ($0.rawValue, metricGloballyEnabled[$0, default: true]) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: kLocalMirrorMetrics)
        }
    }

    /// iPhone/iPad: fold Mac pending queue into authoritative data and clear pending.
    func processPendingQueueFromMac() {
        guard NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter else { return }
        cloud.synchronize()
        guard let pendData = cloud.data(forKey: kPendingIOSKey),
              let pending = try? JSONDecoder().decode([NutrivanceTuningPendingOperation].self, from: pendData),
              !pending.isEmpty else { return }

        let auth: NutrivanceTuningAuthoritativeState
        if let authData = cloud.data(forKey: kAuthoritativeKey),
           let a = try? JSONDecoder().decode(NutrivanceTuningAuthoritativeState.self, from: authData) {
            auth = a
        } else {
            auth = .empty
        }

        let merged = mergedReportsAndMetrics(authoritative: auth, pending: pending)
        reports = refreshedReports(merged.reports)
        applyMetricDict(merged.metrics)
        pendingIOSOperations = []

        if let emptyPending = try? JSONEncoder().encode([NutrivanceTuningPendingOperation]()) {
            cloud.set(emptyPending, forKey: kPendingIOSKey)
        }
        persistAuthoritativeToICloud()
        objectWillChange.send()
    }

    /// Call when the app becomes active so each device pulls latest KVS; handheld also merges Mac-queued ops inside `reloadFromICloud()`.
    func syncOnAppForeground() {
        reloadFromICloud()
    }

    private func refreshedReports(_ reports: [NutrivanceTuningReport], asOf date: Date = Date()) -> [NutrivanceTuningReport] {
        reports.map { refreshedReport($0, asOf: date) }
    }

    private func refreshedReport(
        _ report: NutrivanceTuningReport,
        touchedAt: Date? = nil,
        asOf date: Date = Date()
    ) -> NutrivanceTuningReport {
        var refreshed = report
        refreshed.effectiveStrength = max(0, min(1, refreshed.effectiveStrength))
        refreshed.decayRate = max(0, min(1, refreshed.decayRate))
        if let touchedAt {
            refreshed.lastAppliedAt = touchedAt
        }
        refreshed.refreshComputedWeight(asOf: date)
        return refreshed
    }
}

// MARK: - Small UI pieces

struct NutrivanceTuningValueCaption: View {
    let result: NutrivanceTuningDisplayResult
    let unitSuffix: String
    let format: (Double) -> String

    var body: some View {
        if NutrivanceTuningStore.shared.showTestingOverlay, abs(result.delta) > 0.01 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Was \(format(result.base))\(unitSuffix)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let first = result.contributingReports.first {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help(first.shortAttributionLabel)
                }
            }
        }
    }
}
