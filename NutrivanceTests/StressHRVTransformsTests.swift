//
//  StressHRVTransformsTests.swift
//  NutrivanceTests
//

import XCTest
@testable import Nutrivance

final class StressHRVTransformsTests: XCTestCase {

    func testRmssdFromSyntheticIntervals() {
        // Mild beat-to-beat variation around ~850 ms NN intervals
        var rr: [Double] = []
        rr.reserveCapacity(40)
        for i in 0..<40 {
            rr.append(830 + Double((i % 5) * 4))
        }
        let v = StressHRVTransforms.rmssd(fromSuccessiveNNMilliseconds: rr)
        XCTAssertNotNil(v)
        XCTAssertGreaterThan(v!, 0)
    }

    func testRmssdInsufficientIntervalsReturnsNil() {
        let short = Array(repeating: 800.0, count: 10)
        XCTAssertNil(StressHRVTransforms.rmssd(fromSuccessiveNNMilliseconds: short))
    }

    func testStressCalibrationLowAtBaselineProxy() {
        let atOne = StressHRVTransforms.calculateStress(lfHfProxy: 1.0)
        XCTAssertLessThan(atOne, 20)
        XCTAssertGreaterThanOrEqual(atOne, 0)
    }

    func testStressMonotonicWithProxy() {
        let low = StressHRVTransforms.calculateStress(lfHfProxy: 0.9)
        let high = StressHRVTransforms.calculateStress(lfHfProxy: 1.3)
        XCTAssertLessThan(low, high)
    }

    func testRegulationAllowsHeadroomBeyondLegacy120() {
        let score = StressHRVTransforms.calculateRegulationScore(currentCombined: 200, readinessBaselineCombined: 50)
        XCTAssertGreaterThan(score, 120)
        XCTAssertLessThanOrEqual(score, 250)
    }

    func testRmssdEffectivePrefersHeartbeatWhenProvided() {
        let x = StressHRVTransforms.rmssdEffective(sdnn: 50, heartbeatRmssdMs: 42)
        XCTAssertEqual(x.rmssd, 42, accuracy: 0.001)
        XCTAssertEqual(x.source, .heartbeatDerived)

        let y = StressHRVTransforms.rmssdEffective(sdnn: 50, heartbeatRmssdMs: nil)
        XCTAssertEqual(y.rmssd, 50 * 0.85, accuracy: 0.001)
        XCTAssertEqual(y.source, .sdnnProxy)
    }
}
