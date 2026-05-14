import Foundation

// MARK: - Layer 2 helpers (rolling baselines, Sendable)

private let kMinBaselineSamples = 5
private let kMinStdFloor: Double = 1e-4

/// Prior-window stats for a single scalar stream (excludes `anchorDay` from the window).
struct PerSignalBaselineSnapshot: Sendable, Codable, Hashable {
    let mean: Double
    let standardDeviation: Double
    let sampleCount: Int

    var isUsableForSecondary: Bool {
        sampleCount >= kMinBaselineSamples && standardDeviation >= kMinStdFloor
    }
}

// MARK: - Coverage & breakdown (Layer 4)

enum RecoverySignalCoverageState: String, Codable, Hashable {
    case used
    case imputed
    case missing
}

enum RecoveryPipelineSignalKind: String, Codable, Hashable, CaseIterable {
    case hrv
    case rhr
    case sleepDuration
    case sleepEfficiency
    case circadian
    case respiratory
    case spO2
    case wristTemperature
}

struct RecoverySignalCoverageEntry: Codable, Hashable {
    let signal: RecoveryPipelineSignalKind
    let state: RecoverySignalCoverageState
}

/// Sealed recovery output for UI, persistence, and downstream readiness (Layer 4).
struct RecoveryScoreBreakdown: Sendable, Codable, Hashable {
    var score: Double
    var coreScore: Double
    var secondaryDelta: Double
    var agreementBonus: Double
    var confidence01: Double
    var coverage: [RecoverySignalCoverageEntry]
    var componentContributions: [RecoveryPipelineSignalKind: Double]

    static func coverageDict(_ entries: [RecoverySignalCoverageEntry]) -> [RecoveryPipelineSignalKind: RecoverySignalCoverageState] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.signal, $0.state) })
    }
}

// MARK: - Readiness (Layers 6–7)

enum ReadinessLimitingFactor: String, Codable, Hashable {
    case recovery
    case strain
    case context
    case balanced
}

struct ReadinessScoreBreakdown: Sendable, Codable, Hashable {
    var score: Double
    var trainingZone: String
    var limitingFactor: ReadinessLimitingFactor
    var confidence01: Double
    var recoveryConfidence01: Double
    var loadConfidence01: Double
}

struct ReadinessComputationInput: Sendable {
    let recovery: RecoveryScoreBreakdown
    let recoveryScoreForBlend: Double
    let strainScore: Double
    let hrvTrendComponent: Double
    let acwr: Double?
}

// MARK: - Layer 3 model

enum RecoveryPhysiologyModel {
    static let minimumBaselineSamples = kMinBaselineSamples
    static let minimumStandardDeviation = kMinStdFloor
    static let secondaryAdjustmentCap: Double = 6
    static let agreementBonusPoints: Double = 2
    static let agreementCoreThreshold: Double = 72
    static let agreementNeutralZEpsilon: Double = 0.55

    static func priorWindowBaseline(
        values: [Date: Double],
        anchorDay: Date,
        lookbackDays: Int = 7
    ) -> PerSignalBaselineSnapshot? {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: anchorDay)
        var samples: [Double] = []
        for offset in 1...lookbackDays {
            guard let day = cal.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let key = cal.startOfDay(for: day)
            if let v = values[key], v.isFinite, v > 0 {
                samples.append(v)
            }
        }
        guard samples.count >= 2 else { return nil }
        let n = samples.count
        let mean = samples.reduce(0, +) / Double(n)
        let variance = samples.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, n - 1))
        let sd = sqrt(max(variance, minimumStandardDeviation))
        return PerSignalBaselineSnapshot(mean: mean, standardDeviation: sd, sampleCount: n)
    }

    static func zScore(value: Double, baseline: PerSignalBaselineSnapshot) -> Double {
        (value - baseline.mean) / max(baseline.standardDeviation, minimumStandardDeviation)
    }

    static func computeRecoveryBreakdown(
        day: Date,
        inputs: HealthStateEngine.ProRecoveryInputs,
        context: RecoveryComputationContext
    ) -> RecoveryScoreBreakdown? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        guard !inputs.isInconclusive else { return nil }
        guard inputs.hrvZScore != nil || inputs.restingHeartRateZScore != nil || inputs.sleepRatio != nil else {
            return nil
        }

        let core = HealthStateEngine.proRecoveryScore(from: inputs)
        let confidence = recoveryConfidence01(inputs: inputs)

        var coverage: [RecoverySignalCoverageEntry] = []
        func appendCoverage(_ signal: RecoveryPipelineSignalKind, _ state: RecoverySignalCoverageState) {
            coverage.append(RecoverySignalCoverageEntry(signal: signal, state: state))
        }

        if inputs.hrvZScore != nil {
            appendCoverage(.hrv, .used)
        } else {
            appendCoverage(.hrv, .missing)
        }
        if inputs.restingHeartRateZScore != nil || inputs.restingHeartRatePenaltyZScore != nil {
            appendCoverage(.rhr, .used)
        } else {
            appendCoverage(.rhr, .missing)
        }
        if let s = inputs.sleepDurationHours, s > 0 {
            appendCoverage(.sleepDuration, .used)
        } else {
            appendCoverage(.sleepDuration, .missing)
        }
        if let e = inputs.sleepEfficiency {
            appendCoverage(.sleepEfficiency, e > 0 ? .used : .missing)
        } else {
            appendCoverage(.sleepEfficiency, .missing)
        }
        if (inputs.bedtimeVarianceMinutes ?? 0) > 0 {
            appendCoverage(.circadian, .used)
        } else {
            appendCoverage(.circadian, .imputed)
        }

        let rrBase = priorWindowBaseline(values: context.respiratoryRateByDay, anchorDay: normalizedDay)
        let spo2Base = priorWindowBaseline(values: context.spO2ByDay, anchorDay: normalizedDay)
        let tempBase = priorWindowBaseline(values: context.wristTemperatureByDay, anchorDay: normalizedDay)

        var rawSecondary: [RecoveryPipelineSignalKind: Double] = [:]

        if let today = context.respiratoryRateByDay[normalizedDay], today > 0, let base = rrBase, base.isUsableForSecondary {
            let z = zScore(value: today, baseline: base)
            let penalty = -min(3.0, max(0, z) * 1.8)
            rawSecondary[.respiratory] = penalty
            appendCoverage(.respiratory, .used)
        } else {
            appendCoverage(.respiratory, context.respiratoryRateByDay[normalizedDay] != nil ? .imputed : .missing)
        }

        if let today = context.spO2ByDay[normalizedDay], today > 0, let base = spo2Base, base.isUsableForSecondary {
            let zLow = (base.mean - today) / max(base.standardDeviation, minimumStandardDeviation)
            let penalty = -min(3.0, max(0, zLow) * 2.2)
            rawSecondary[.spO2] = penalty
            appendCoverage(.spO2, .used)
        } else {
            appendCoverage(.spO2, context.spO2ByDay[normalizedDay] != nil ? .imputed : .missing)
        }

        if let today = context.wristTemperatureByDay[normalizedDay], today.isFinite, let base = tempBase, base.isUsableForSecondary {
            let z = abs(zScore(value: today, baseline: base))
            let penalty = -min(3.0, z * 1.4)
            rawSecondary[.wristTemperature] = penalty
            appendCoverage(.wristTemperature, .used)
        } else {
            appendCoverage(.wristTemperature, context.wristTemperatureByDay[normalizedDay] != nil ? .imputed : .missing)
        }

        var secondarySum = rawSecondary.values.reduce(0, +)
        if secondarySum < -secondaryAdjustmentCap {
            let scale = secondaryAdjustmentCap / abs(secondarySum)
            secondarySum = -secondaryAdjustmentCap
            for k in rawSecondary.keys {
                rawSecondary[k] = (rawSecondary[k] ?? 0) * scale
            }
        }

        let cov = RecoveryScoreBreakdown.coverageDict(coverage)
        let secondaryNeutral = secondarySignalsNeutral(raw: rawSecondary, coverage: cov)
        var agreement: Double = 0
        if core >= agreementCoreThreshold,
           confidence >= 0.75,
           secondaryNeutral {
            agreement = agreementBonusPoints
        }

        let final = max(0, min(100, core + secondarySum + agreement))

        var components: [RecoveryPipelineSignalKind: Double] = [:]
        if let h = inputs.hrvZScore { components[.hrv] = h }
        if let p = inputs.restingHeartRatePenaltyZScore { components[.rhr] = -p }
        if let r = inputs.sleepRatio { components[.sleepDuration] = r * 50 }
        if let e = inputs.sleepEfficiency { components[.sleepEfficiency] = e * 40 }
        if let v = inputs.bedtimeVarianceMinutes { components[.circadian] = -min(10, max(0, v - 90) * 0.1) }
        for (k, v) in rawSecondary {
            components[k] = v * 10
        }
        components[.hrv, default: 0] += (final - core) * 0.25

        return RecoveryScoreBreakdown(
            score: final,
            coreScore: core,
            secondaryDelta: secondarySum,
            agreementBonus: agreement,
            confidence01: confidence,
            coverage: coverage,
            componentContributions: components
        )
    }

    private static func secondarySignalsNeutral(
        raw: [RecoveryPipelineSignalKind: Double],
        coverage: [RecoveryPipelineSignalKind: RecoverySignalCoverageState]
    ) -> Bool {
        for kind in [RecoveryPipelineSignalKind.respiratory, .spO2, .wristTemperature] {
            guard coverage[kind] == .used else { continue }
            guard let v = raw[kind] else { return false }
            if abs(v) > agreementNeutralZEpsilon * 2 { return false }
        }
        return true
    }

    static func recoveryConfidence01(inputs: HealthStateEngine.ProRecoveryInputs) -> Double {
        var c = 1.0
        if inputs.hrvZScore == nil { c *= 0.72 }
        if inputs.sleepDurationHours == nil || (inputs.sleepDurationHours ?? 0) < 0.25 { c *= 0.65 }
        if inputs.sleepRatio != nil, (inputs.sleepRatio ?? 1) < 0.35 { c *= 0.88 }
        return max(0.35, min(1.0, c))
    }

    static func computeReadinessBreakdown(input: ReadinessComputationInput) -> ReadinessScoreBreakdown {
        let rec = input.recovery
        let blendedRecovery = input.recoveryScoreForBlend * rec.confidence01 + 50.0 * (1.0 - rec.confidence01)
        let score = HealthStateEngine.proReadinessScore(
            recoveryScore: blendedRecovery,
            strainScore: input.strainScore,
            hrvTrendComponent: input.hrvTrendComponent
        )

        let loadConf = loadConfidence01(acwr: input.acwr)
        let combinedConf = max(0.25, min(1.0, rec.confidence01 * 0.65 + loadConf * 0.35))

        let strainNorm = HealthStateEngine.normalizedStrainPercent(from: input.strainScore)
        let recoveryDist = abs(blendedRecovery - 70)
        let strainDist = abs(strainNorm - 35)

        let limiting: ReadinessLimitingFactor
        if recoveryDist > strainDist + 12 {
            limiting = .recovery
        } else if strainDist > recoveryDist + 12 {
            limiting = .strain
        } else {
            limiting = .balanced
        }

        let zone = trainingZoneLabel(for: score, strain: input.strainScore)

        return ReadinessScoreBreakdown(
            score: score,
            trainingZone: zone,
            limitingFactor: limiting,
            confidence01: combinedConf,
            recoveryConfidence01: rec.confidence01,
            loadConfidence01: loadConf
        )
    }

    private static func loadConfidence01(acwr: Double?) -> Double {
        guard let a = acwr, a > 0 else { return 0.85 }
        if a >= 0.8 && a <= 1.3 { return 1.0 }
        if a < 0.8 { return 0.9 }
        if a <= 1.5 { return 0.82 }
        return 0.72
    }

    private static func trainingZoneLabel(for readiness: Double, strain: Double) -> String {
        if readiness >= 82 { return "Full go" }
        if readiness >= 68 { return "Progressive" }
        if readiness >= 52 { return "Controlled" }
        if strain > 16 { return "Ease back" }
        return "Recovery bias"
    }
}
