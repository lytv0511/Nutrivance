//
//  StressHRVTransforms.swift
//  Nutrivance
//
//  Pure math for Stress pipeline (unit-testable; no HealthKit).
//

import Foundation

enum StressRmssdSource: String, Sendable {
    case heartbeatDerived
    case sdnnProxy
}

enum StressHRVTransforms {
    /// Minimum successive NN intervals (ms) so RMSSD has enough successive differences (≥30).
    static let minimumNNIntervalsForRmssd = 31

    /// RMSSD from successive NN (RR) intervals in milliseconds.
    static func rmssd(fromSuccessiveNNMilliseconds rrMs: [Double]) -> Double? {
        guard rrMs.count >= minimumNNIntervalsForRmssd else { return nil }
        var sumSq = 0.0
        var n = 0
        for i in 1..<rrMs.count {
            let d = rrMs[i] - rrMs[i - 1]
            sumSq += d * d
            n += 1
        }
        guard n > 0 else { return nil }
        return sqrt(sumSq / Double(n))
    }

    /// Fallback when no heartbeat-series RMSSD is available (Apple Watch SDNN–only path).
    static func estimateRMSSDFromSDNN(_ sdnn: Double) -> Double {
        sdnn * 0.85
    }

    static func rmssdEffective(sdnn: Double, heartbeatRmssdMs: Double?) -> (rmssd: Double, source: StressRmssdSource) {
        if let hb = heartbeatRmssdMs, hb > 0, hb.isFinite {
            return (hb, .heartbeatDerived)
        }
        return (estimateRMSSDFromSDNN(sdnn), .sdnnProxy)
    }

    static func combinedHRV(sdnn: Double, rmssdEffective: Double) -> Double {
        0.7 * rmssdEffective + 0.3 * sdnn
    }

    static func lfHfProxy(baselineRMSSD: Double, currentRMSSD: Double) -> Double {
        pow(baselineRMSSD / max(currentRMSSD, 1e-5), 0.7)
    }

    /// Stress mapping anchor on LF/HF proxy (headline calibration).
    static let stressProxyAnchor = 0.95
    /// Stress mapping scale on LF/HF proxy (headline calibration).
    static let stressProxyScale = 120.0

    /// Maps LF/HF-style proxy to 0–100 stress; proxy≈1 aligned to low stress (anchor 0.95).
    static func calculateStress(lfHfProxy proxy: Double) -> Double {
        let raw = (proxy - stressProxyAnchor) * stressProxyScale
        return min(max(raw, 0), 100)
    }

    static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 1e-9 else { return 0 }
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance) / mean
    }

    static func calculateEnergy(currentAdjustedCombined: Double, readinessBaselineCombined: Double, windowValues: [Double]) -> Double {
        guard readinessBaselineCombined > 1e-9 else { return 0 }
        let recovery = currentAdjustedCombined / readinessBaselineCombined
        let cv = coefficientOfVariation(windowValues)
        let stability = max(0, 1 - cv)
        let energy = recovery * 0.7 + stability * 0.3
        return min(max(energy * 100, 0), 100)
    }

    /// Combined HRV implied by morning-readiness baseline SDNN (proxy RMSSD leg matches baseline snapshot).
    static func readinessCombinedBaseline(sdnn: Double) -> Double {
        let rm = estimateRMSSDFromSDNN(sdnn)
        return combinedHRV(sdnn: sdnn, rmssdEffective: rm)
    }

    /// Recovery ratio and stability term matching `calculateEnergy` (CV comes from the cleaned SDNN window).
    static func energyBlendComponents(adjustedCombined: Double, readinessBaselineCombined: Double, coefficientOfVariation: Double) -> (recovery: Double, stability: Double) {
        guard readinessBaselineCombined > 1e-9 else { return (0, 0) }
        let recovery = adjustedCombined / readinessBaselineCombined
        let stability = max(0, 1 - coefficientOfVariation)
        return (recovery, stability)
    }

    /// Raw ratio × 100 before headline cap (for explainability).
    static func regulationLinearPercent(currentCombined: Double, readinessBaselineCombined: Double) -> Double {
        guard readinessBaselineCombined > 1e-9 else { return 0 }
        return (currentCombined / readinessBaselineCombined) * 100
    }

    /// Regulation on the same 0–100 scale as Stress and Energy: parity ≈ 100 when combined HRV matches readiness baseline.
    static func calculateRegulationScore(currentCombined: Double, readinessBaselineCombined: Double) -> Double {
        let linear = regulationLinearPercent(currentCombined: currentCombined, readinessBaselineCombined: readinessBaselineCombined)
        return min(max(linear, 0), 100)
    }
}
