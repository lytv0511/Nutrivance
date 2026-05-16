//
//  StressHeartbeatRmssd.swift
//  Nutrivance
//
//  Optional RMSSD from HKHeartbeatSeriesSample windows aligned to HRV SDNN timestamps (iOS).
//

import Foundation
import HealthKit

enum StressHeartbeatRmssd {
    static let anchorHalfWindowSeconds: TimeInterval = 180
    /// Minimum successive RR intervals fully inside the anchor window for RMSSD.
    static let minimumRRIntervalsInWindow = 31

    /// RR intervals in ms from a heartbeat series sample (requires sequential beat callbacks).
    static func extractRRMilliseconds(from series: HKHeartbeatSeriesSample, healthStore: HKHealthStore, completion: @escaping ([Double]?) -> Void) {
        var timesSinceStart: [TimeInterval] = []
        let query = HKHeartbeatSeriesQuery(heartbeatSeries: series, dataHandler: { _, timeSinceSeriesStart, _, done, error in
            if error != nil {
                if done { completion(nil) }
                return
            }
            timesSinceStart.append(timeSinceSeriesStart)
            if done {
                guard timesSinceStart.count >= StressHeartbeatRmssd.minimumRRIntervalsInWindow + 1 else {
                    completion(nil)
                    return
                }
                var rrMs: [Double] = []
                rrMs.reserveCapacity(timesSinceStart.count - 1)
                for i in 1..<timesSinceStart.count {
                    rrMs.append((timesSinceStart[i] - timesSinceStart[i - 1]) * 1000.0)
                }
                completion(rrMs)
            }
        })
        healthStore.execute(query)
    }

    static func rmssdNearAnchor(
        anchor: Date,
        seriesStart: Date,
        rrMilliseconds: [Double],
        halfWindow: TimeInterval = StressHeartbeatRmssd.anchorHalfWindowSeconds
    ) -> Double? {
        let anchorSec = anchor.timeIntervalSince1970
        let lo = anchorSec - halfWindow
        let hi = anchorSec + halfWindow
        var beatTimes: [TimeInterval] = []
        beatTimes.reserveCapacity(rrMilliseconds.count + 1)
        var t = seriesStart.timeIntervalSince1970
        beatTimes.append(t)
        for rr in rrMilliseconds {
            t += rr / 1000.0
            beatTimes.append(t)
        }
        guard let firstIdx = beatTimes.firstIndex(where: { $0 >= lo }),
              let lastIdx = beatTimes.lastIndex(where: { $0 <= hi }) else {
            return nil
        }
        guard lastIdx >= firstIdx + StressHeartbeatRmssd.minimumRRIntervalsInWindow else { return nil }
        let slice = Array(rrMilliseconds[firstIdx..<lastIdx])
        return StressHRVTransforms.rmssd(fromSuccessiveNNMilliseconds: slice)
    }

    private static func expandedOverlaps(_ hb: HKHeartbeatSeriesSample, hrvTime: Date, halfWindow: TimeInterval) -> Bool {
        let l = hrvTime.addingTimeInterval(-halfWindow)
        let r = hrvTime.addingTimeInterval(halfWindow)
        return hb.startDate < r && hb.endDate > l
    }

    /// Builds RMSSD (ms) per HRV quantity sample UUID when heartbeat windows permit (recent history only).
    static func prefetchRmssdByHRVSamples(
        hrvSamples: [HKQuantitySample],
        healthStore: HKHealthStore,
        completion: @escaping ([UUID: Double]) -> Void
    ) {
        guard !hrvSamples.isEmpty else {
            completion([:])
            return
        }
        let sorted = hrvSamples.sorted { $0.startDate < $1.startDate }
        guard let newestDate = sorted.last?.startDate else {
            completion([:])
            return
        }
        let oldestAllowed = Calendar.current.date(byAdding: .day, value: -400, to: newestDate) ?? sorted.first!.startDate
        let fetchStart = max(sorted.first!.startDate, oldestAllowed)
        let hbType = HKSeriesType.heartbeat()
        let predicate = HKQuery.predicateForSamples(withStart: fetchStart, end: newestDate.addingTimeInterval(120), options: .strictStartDate)

        let sampleQuery = HKSampleQuery(sampleType: hbType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, hbSamples, error in
            guard error == nil, let seriesSamples = hbSamples as? [HKHeartbeatSeriesSample], !seriesSamples.isEmpty else {
                completion([:])
                return
            }

            let hrvInRange = sorted.filter { $0.startDate >= fetchStart }
            var rrByHb: [ObjectIdentifier: [Double]] = [:]
            let rrLock = NSLock()
            let group = DispatchGroup()

            for hb in seriesSamples {
                group.enter()
                extractRRMilliseconds(from: hb, healthStore: healthStore) { rr in
                    if let rr {
                        rrLock.lock()
                        rrByHb[ObjectIdentifier(hb)] = rr
                        rrLock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: DispatchQueue.global(qos: .utility)) {
                var result: [UUID: Double] = [:]
                for sample in hrvInRange {
                    let overlaps = seriesSamples.filter { expandedOverlaps($0, hrvTime: sample.startDate, halfWindow: anchorHalfWindowSeconds) }
                    for hb in overlaps {
                        guard let rr = rrByHb[ObjectIdentifier(hb)] else { continue }
                        if let v = rmssdNearAnchor(anchor: sample.startDate, seriesStart: hb.startDate, rrMilliseconds: rr) {
                            result[sample.uuid] = v
                            break
                        }
                    }
                }
                completion(result)
            }
        }
        healthStore.execute(sampleQuery)
    }
}
