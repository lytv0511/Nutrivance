import XCTest
@testable import Nutrivance

final class RecoveryPhysiologyModelTests: XCTestCase {
    private func emptyRecoveryContext(
        respiratoryRateByDay: [Date: Double] = [:],
        spO2ByDay: [Date: Double] = [:],
        wristTemperatureByDay: [Date: Double] = [:]
    ) -> RecoveryComputationContext {
        RecoveryComputationContext(
            hrvByDay: [:],
            effectHRV: [:],
            basalSleepingHeartRate: [:],
            dailyRestingHeartRate: [:],
            anchoredSleepDuration: [:],
            anchoredTimeInBed: [:],
            sleepEfficiencyByDay: [:],
            dailySleepDuration: [:],
            sleepStartHours: [:],
            hrvBaseline60Day: nil,
            rhrBaseline60Day: nil,
            sleepBaseline60Day: nil,
            hrvBaseline7Day: 50,
            rhrBaseline7Day: 52,
            sleepBaseline7Day: 8,
            hrvTrendFallback: 50,
            respiratoryRateByDay: respiratoryRateByDay,
            spO2ByDay: spO2ByDay,
            wristTemperatureByDay: wristTemperatureByDay
        )
    }

    func testRecoveryConfidenceDropsWithoutHRV() {
        let withHRV = HealthStateEngine.proRecoveryInputs(
            latestHRV: 80,
            restingHeartRate: 50,
            sleepDurationHours: 8,
            timeInBedHours: 9,
            hrvBaseline60Day: nil,
            rhrBaseline60Day: nil,
            sleepBaseline60Day: nil,
            hrvBaseline7Day: 50,
            rhrBaseline7Day: 52,
            sleepBaseline7Day: 8,
            bedtimeVarianceMinutes: 45
        )
        let withoutHRV = HealthStateEngine.proRecoveryInputs(
            latestHRV: nil,
            restingHeartRate: 50,
            sleepDurationHours: 8,
            timeInBedHours: 9,
            hrvBaseline60Day: nil,
            rhrBaseline60Day: nil,
            sleepBaseline60Day: nil,
            hrvBaseline7Day: 50,
            rhrBaseline7Day: 52,
            sleepBaseline7Day: 8,
            bedtimeVarianceMinutes: 45
        )
        XCTAssertGreaterThan(
            RecoveryPhysiologyModel.recoveryConfidence01(inputs: withHRV),
            RecoveryPhysiologyModel.recoveryConfidence01(inputs: withoutHRV)
        )
    }

    func testSecondaryAdjustmentsCapAtSixPoints() {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date())
        var rr: [Date: Double] = [:]
        var spo2: [Date: Double] = [:]
        var temp: [Date: Double] = [:]
        for offset in 1...7 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let d = cal.startOfDay(for: day)
            rr[d] = 14
            spo2[d] = 98
            temp[d] = 36.5
        }
        rr[anchor] = 30
        spo2[anchor] = 90
        temp[anchor] = 38.8

        let ctx = emptyRecoveryContext(respiratoryRateByDay: rr, spO2ByDay: spo2, wristTemperatureByDay: temp)
        let inputs = HealthStateEngine.proRecoveryInputs(
            latestHRV: 95,
            restingHeartRate: 48,
            sleepDurationHours: 8,
            timeInBedHours: 9,
            hrvBaseline60Day: nil,
            rhrBaseline60Day: nil,
            sleepBaseline60Day: nil,
            hrvBaseline7Day: 50,
            rhrBaseline7Day: 52,
            sleepBaseline7Day: 8,
            bedtimeVarianceMinutes: 60
        )
        guard let b = RecoveryPhysiologyModel.computeRecoveryBreakdown(day: anchor, inputs: inputs, context: ctx) else {
            return XCTFail("Expected recovery breakdown")
        }
        XCTAssertEqual(b.secondaryDelta, -RecoveryPhysiologyModel.secondaryAdjustmentCap, accuracy: 0.001)
    }

    func testReadinessConfidenceReflectsACWRBand() {
        let recovery = RecoveryScoreBreakdown(
            score: 78,
            coreScore: 78,
            secondaryDelta: 0,
            agreementBonus: 0,
            confidence01: 0.9,
            coverage: [],
            componentContributions: [:]
        )
        let optimal = ReadinessComputationInput(
            recovery: recovery,
            recoveryScoreForBlend: recovery.score,
            strainScore: 10,
            hrvTrendComponent: 55,
            acwr: 1.05
        )
        let highRatio = ReadinessComputationInput(
            recovery: recovery,
            recoveryScoreForBlend: recovery.score,
            strainScore: 10,
            hrvTrendComponent: 55,
            acwr: 1.9
        )
        let bOpt = RecoveryPhysiologyModel.computeReadinessBreakdown(input: optimal)
        let bHigh = RecoveryPhysiologyModel.computeReadinessBreakdown(input: highRatio)
        XCTAssertGreaterThan(bOpt.confidence01, bHigh.confidence01)
        XCTAssertGreaterThan(bOpt.loadConfidence01, bHigh.loadConfidence01)
    }
}
