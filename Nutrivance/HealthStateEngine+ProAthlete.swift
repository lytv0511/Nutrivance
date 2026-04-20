import Foundation
import HealthKit

// MARK: - Pro-Athlete Profile Values

struct ProAthleteProfileValues: Sendable {
    let isProAthleteMode: Bool
    let enableStrainSensitiveHRV: Bool
    let chronicLoadPercentile: Double
    let enableHRVBellCurve: Bool
    let hrvZScoreCap: Double
    let enableSleepQualityCoeff: Bool
    let enableSubjectiveDataCollection: Bool
    let enableACWRLogic: Bool
    let acwrOptimalMin: Double
    let acwrOptimalMax: Double
    let acwrDangerThreshold: Double
    let enableAsymmetricStrainPenalty: Bool
    let enableTaperLogic: Bool

    init(from profile: PerformanceProfileSettings) {
        self.isProAthleteMode = profile.isProAthleteMode
        self.enableStrainSensitiveHRV = profile.enableStrainSensitiveHRV
        self.chronicLoadPercentile = profile.chronicLoadPercentile
        self.enableHRVBellCurve = profile.enableHRVBellCurve
        self.hrvZScoreCap = profile.hrvZScoreCap
        self.enableSleepQualityCoeff = profile.enableSleepQualityCoeff
        self.enableSubjectiveDataCollection = profile.enableSubjectiveDataCollection
        self.enableACWRLogic = profile.enableACWRLogic
        self.acwrOptimalMin = profile.acwrOptimalMin
        self.acwrOptimalMax = profile.acwrOptimalMax
        self.acwrDangerThreshold = profile.acwrDangerThreshold
        self.enableAsymmetricStrainPenalty = profile.enableAsymmetricStrainPenalty
        self.enableTaperLogic = profile.enableTaperLogic
    }

    static var defaultValues: ProAthleteProfileValues {
        ProAthleteProfileValues(
            isProAthleteMode: false,
            enableStrainSensitiveHRV: true,
            chronicLoadPercentile: 0.8,
            enableHRVBellCurve: true,
            hrvZScoreCap: 2.5,
            enableSleepQualityCoeff: true,
            enableSubjectiveDataCollection: false,
            enableACWRLogic: true,
            acwrOptimalMin: 0.8,
            acwrOptimalMax: 1.3,
            acwrDangerThreshold: 1.5,
            enableAsymmetricStrainPenalty: true,
            enableTaperLogic: true
        )
    }
}

// MARK: - Pro-Athlete Recovery & Readiness Calculations

extension HealthStateEngine {
    
    // MARK: - Pro-Athlete Recovery Score
    
    /// Enhanced recovery score with pro-athlete optimizations:
    /// - Dynamic HRV weighting based on chronic load
    /// - Sleep quality coefficient (deep/REM ratio + efficiency)
    /// - HRV bell-curve cap (detects parasympathetic hyperactivity)
    /// - Subjective data integration (optional)
    nonisolated static func proAthleteRecoveryScore(
        from inputs: ProRecoveryInputs,
        profile: ProAthleteProfileValues,
        chronicLoad: Double,
        athleteHistoricalMaxChronicLoad: Double?,
        subjectiveBoost: Double? = nil
    ) -> (score: Double, hrvWarning: Bool, sleepQualityWarning: Bool, subjectiveBoost: Double?) {
        guard profile.isProAthleteMode else {
            // Standard mode: just return base recovery
            return (score: proRecoveryScore(from: inputs), hrvWarning: false, sleepQualityWarning: false, subjectiveBoost: nil)
        }
        
        var finalScore = inputs.baseRecoveryScore
        var hrvWarning = false
        var sleepQualityWarning = false
        
        // ========================================
        // 1. Dynamic HRV Weighting (Strain-Sensitive)
        // ========================================
        var adjustedComposite = inputs.composite
        if profile.enableStrainSensitiveHRV {
            let percentile80 = (athleteHistoricalMaxChronicLoad ?? 1.0) * profile.chronicLoadPercentile
            if chronicLoad >= percentile80 {
                // At high chronic load: boost HRV weight (30% → 50%), reduce RHR (25% → 10%)
                let hrvZ = inputs.hrvZScore ?? 0
                let rhrPenaltyZ = inputs.restingHeartRatePenaltyZScore ?? 0
                adjustedComposite = (hrvZ * 0.50) - (rhrPenaltyZ * 0.10)
            }
        }
        
        let baseRecovery = normalizedCompositeScore(from: adjustedComposite)
        
        // ========================================
        // 2. HRV Bell-Curve Cap (Overtraining Detection)
        // ========================================
        if profile.enableHRVBellCurve,
           let hrvZ = inputs.hrvZScore,
           hrvZ > profile.hrvZScoreCap {
            // Abnormally high HRV (Z > cap) signals potential deep fatigue
            // Cap at lower value and flag warning
            hrvWarning = true
            finalScore = min(baseRecovery, 85.0)  // Prevent 100 score
        } else {
            finalScore = baseRecovery
        }
        
        // ========================================
        // 3. Sleep Quality Coefficient (Deep/REM Awareness)
        // ========================================
        var sleepQualityCoeff = 1.0
        if profile.enableSleepQualityCoeff {
            // Ideally: deepSleepRatio + remSleepRatio from HealthKit breakdown
            // Fallback: use efficiency as proxy
            if let efficiency = inputs.sleepEfficiency {
                // Penalty escalation: < 0.70 = 0.85x, < 0.85 = 0.92x, >= 0.85 = 1.0x
                if efficiency < 0.70 {
                    sleepQualityCoeff = 0.85
                    sleepQualityWarning = true
                } else if efficiency < 0.85 {
                    sleepQualityCoeff = 0.92
                }
            }
        }
        
        let afterSleepQuality = max(0, finalScore * sleepQualityCoeff)
        
        // ========================================
        // 4. Apply Sleep Scalar and Penalties
        // ========================================
        let afterPenalties = max(0, afterSleepQuality - (inputs.sleepDebtPenalty + inputs.circadianPenalty))
        let gatedRecovery = max(0, min(100, afterPenalties * (inputs.sleepScalar ?? 1.0)))
        let efficiencyCap = ((inputs.sleepEfficiency ?? 1.0) < 0.85) ? 70.0 : nil
        var result = min(gatedRecovery, efficiencyCap ?? gatedRecovery)
        
        // ========================================
        // 5. Subjective Data Integration (Optional)
        // ========================================
        var subjectiveBoost: Double? = nil
        if profile.enableSubjectiveDataCollection, let externalBoost = subjectiveBoost {
            subjectiveBoost = externalBoost
            result = max(0, min(100, result + externalBoost))
        }
        
        return (score: result, hrvWarning: hrvWarning, sleepQualityWarning: sleepQualityWarning, subjectiveBoost: subjectiveBoost)
    }
    
    // MARK: - Pro-Athlete Readiness Score
    
    /// Enhanced readiness score with pro-athlete optimizations:
    /// - ACWR-based logic (sweet spot bonus, danger zone penalty)
    /// - Asymmetric strain penalty (multiplicative, not additive)
    /// - Taper detection ("Fresh but Flat" advisory)
    nonisolated static func proAthleteReadinessScore(
        recovery: Double,
        strain: Double,
        hrvTrend: Double,
        acwr: Double?,
        acuteLoad: Double?,
        chronicLoad: Double?,
        profile: ProAthleteProfileValues
    ) -> (score: Double, acwrStatus: String, taperDetected: Bool, asymmetricStrainMultiplier: Double) {
        guard profile.isProAthleteMode else {
            // Standard mode
            let standard = proReadinessScore(recoveryScore: recovery, strainScore: strain, hrvTrendComponent: hrvTrend)
            return (score: standard, acwrStatus: "Standard", taperDetected: false, asymmetricStrainMultiplier: 1.0)
        }
        
        var readiness = recovery * 0.70 + hrvTrend * 0.10
        var acwrStatus = "Neutral"
        var taperDetected = false
        var strainMultiplier = 1.0
        
        // ========================================
        // 1. ACWR-Based Readiness Logic
        // ========================================
        if profile.enableACWRLogic, let acwr = acwr {
            if acwr >= profile.acwrOptimalMin && acwr <= profile.acwrOptimalMax {
                // Optimal range: +5 bonus
                readiness += 5.0
                acwrStatus = "Optimal"
            } else if acwr > profile.acwrDangerThreshold {
                // Danger zone (high acute load relative to chronic): heavy exponential penalty
                let excess = acwr - profile.acwrDangerThreshold
                let acwrPenalty = min(40.0, excess * 30.0)  // Up to 40 point penalty
                readiness -= acwrPenalty
                acwrStatus = "Danger"
            } else if acwr < profile.acwrOptimalMin {
                // Detraining: neutral (no penalty, but flag as potential taper)
                acwrStatus = "Detraining"
            }
        }
        
        // ========================================
        // 2. Asymmetric Strain Penalty (Multiplicative)
        // ========================================
        if profile.enableAsymmetricStrainPenalty {
            let normalizedStrain = normalizedStrainPercent(from: strain)
            // At high strain (17/21 → 81%), apply multiplicative penalty
            // Formula: readiness *= (1 - (normalizedStrain / 100) * 0.35)
            // This ensures strain interacts exponentially with readiness
            strainMultiplier = max(0.4, 1.0 - (normalizedStrain / 100.0) * 0.35)
            readiness *= strainMultiplier
        } else {
            // Standard linear penalty
            let normalizedStrain = normalizedStrainPercent(from: strain)
            readiness -= (normalizedStrain * 0.25)
        }
        
        // ========================================
        // 3. Taper Detection ("Fresh but Flat")
        // ========================================
        if profile.enableTaperLogic,
           let acuteLoad = acuteLoad,
           let chronicLoad = chronicLoad {
            let acuteDropFactor = acuteLoad / max(chronicLoad, 1.0)
            if acuteDropFactor < 0.6 && recovery > 80.0 {
                // Fresh but Flat: acute load dropped 40%+ below chronic, recovery is high
                // Cap readiness at 88 to prevent over-ambition during taper
                taperDetected = true
                readiness = min(88.0, readiness)
                if acwrStatus == "Neutral" {
                    acwrStatus = "Fresh but Flat"
                }
            }
        }
        
        // Add baseline offset
        readiness += 25.0
        
        let finalReadiness = max(0, min(100, readiness))
        
        return (score: finalReadiness, acwrStatus: acwrStatus, taperDetected: taperDetected, asymmetricStrainMultiplier: strainMultiplier)
    }
    
    // MARK: - Pro-Athlete Strain Score
    
    /// Enhanced strain score with optional exponential zone weighting
    nonisolated static func proAthleteStrainScore(
        acuteLoad: Double,
        chronicLoad: Double,
        zoneWeightingExponential: Bool = false
    ) -> Double {
        let debug = debugStrainSnapshot(label: "ProAthlete", acuteLoad: acuteLoad, chronicLoad: chronicLoad)
        return debug.finalStrainScore
        // Note: Zone weighting is applied at workout load calculation time,
        // not in strain score formula itself. See proWorkoutLoad() extension.
    }
    
    // MARK: - Exponential Zone Weighting Helper
    
    /// Apply exponential zone weights instead of linear
    /// Zone 1: 1.0x, Zone 2: 2.0x, Zone 3: 3.5x, Zone 4: 6.0x, Zone 5: 9.0x (vs standard 6.0x)
    nonisolated static func proZoneWeight(
        for zoneNumber: Int,
        exponential: Bool = false
    ) -> Double {
        if exponential {
            switch zoneNumber {
            case 1: return 1.0
            case 2: return 2.0
            case 3: return 3.5
            case 4: return 6.0
            default: return 9.0  // Zone 5: boosted from 6.0 to 9.0
            }
        } else {
            return proZoneWeight(for: zoneNumber)  // Standard weighting
        }
    }
}

// MARK: - Pro-Athlete Output Structures

struct ProAthleteRecoveryResult {
    let baseScore: Double
    let adjustedScore: Double
    let hrvWarning: Bool
    let sleepQualityWarning: Bool
    let subjectiveBoost: Double?
    let dynamicHRVActive: Bool
}

struct ProAthleteReadinessResult {
    let baseScore: Double
    let adjustedScore: Double
    let acwrStatus: String
    let taperDetected: Bool
    let asymmetricStrainMultiplier: Double
}
