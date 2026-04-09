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
    var isEnabled: Bool

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
        isEnabled: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.metric = metric
        self.factor = factor
        self.userDirection = max(-1, min(1, userDirection))
        self.nudgeLevel = nudgeLevel
        self.userNote = userNote
        self.shortAttributionLabel = shortAttributionLabel
        self.effectiveStrength = max(0, min(1, effectiveStrength))
        self.isEnabled = isEnabled
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

    static func display(
        base: Double,
        metric: NutrivanceTuningMetric,
        store: NutrivanceTuningStore
    ) -> NutrivanceTuningDisplayResult {
        guard store.isMetricGloballyEnabled(metric) else {
            return NutrivanceTuningDisplayResult(base: base, adjusted: base, delta: 0, contributingReports: [])
        }
        let active = store.reports.filter { $0.isEnabled && $0.metric == metric }
        guard !active.isEmpty else {
            return NutrivanceTuningDisplayResult(base: base, adjusted: base, delta: 0, contributingReports: [])
        }

        var sum: Double = 0
        var contributors: [NutrivanceTuningReport] = []

        for report in active.sorted(by: { $0.createdAt < $1.createdAt }) {
            let sign = report.userDirection >= 0 ? 1.0 : -1.0
            let mag = abs(report.userDirection) > 0.01 ? abs(report.userDirection) : 1.0
            let perReport = sign * mag * report.nudgeLevel.scalar * report.effectiveStrength
            sum += perReport
            contributors.append(report)
        }

        let maxD: Double = {
            switch metric {
            case .recovery: return maxDeltaRecovery
            case .strain: return maxDeltaStrain
            case .readiness: return maxDeltaReadiness
            }
        }()

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
        reports.append(report)
        reinforceAllReportsInPlace()
        let finalReport = reports.first(where: { $0.id == report.id }) ?? report
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
        reports[idx] = report
        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            persistAuthoritativeToICloud()
        } else {
            pendingIOSOperations.append(.upsert(report))
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
            reports[i] = r
        }
    }

    // MARK: - iCloud

    private func loadLocalFirstThenCloud() {
        if let data = UserDefaults.standard.data(forKey: kLocalMirrorReports),
           let decoded = try? JSONDecoder().decode([NutrivanceTuningReport].self, from: data) {
            reports = decoded
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
            reports = auth.reports
        } else {
            // Mac: merge iCloud authoritative state with pending queue for immediate display.
            let merged = mergedReportsAndMetrics(authoritative: auth, pending: pending)
            reports = merged.reports
            applyMetricDict(merged.metrics)
        }

        if NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter {
            processPendingQueueFromMac()
        }

        mirrorLocalCache()
        objectWillChange.send()
    }

    private func mergedReportsAndMetrics(authoritative: NutrivanceTuningAuthoritativeState, pending: [NutrivanceTuningPendingOperation]) -> (reports: [NutrivanceTuningReport], metrics: [String: Bool]) {
        var map = Dictionary(uniqueKeysWithValues: authoritative.reports.map { ($0.id, $0) })
        var metrics = authoritative.metricGloballyEnabled

        for op in pending {
            switch op {
            case .upsert(let r):
                map[r.id] = r
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
        reports = merged.reports
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
