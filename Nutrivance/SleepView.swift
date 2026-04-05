//
//  SleepView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

import Foundation
import SwiftUI
import HealthKit
import UIKit
import Charts
#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SleepStageData: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let stage: SleepStage
    let averageHeartRate: Int?
    let averageRespiratoryRate: Int?
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let startStr = formatter.string(from: startTime)
        let endStr = formatter.string(from: endTime)
        return "\(startStr) - \(endStr)"
    }
}

enum SleepStage: Int {
    case awake = 2      // awake during sleep
    case unspecifiedAsleep = 1  // asleepUnspecified (generic asleep)
    case core = 3       // asleepCore
    case deep = 4       // asleepDeep
    case rem = 5        // asleepREM
    
    var label: String {
        switch self {
        case .awake: return "Awake"
        case .unspecifiedAsleep: return "Asleep"
        case .core: return "Core Sleep"
        case .deep: return "Deep Sleep"
        case .rem: return "REM Sleep"
        }
    }
    
    var description: String {
        switch self {
        case .awake:
            return "Time awake during your sleep period. Some brief awakenings during sleep are normal."
        case .unspecifiedAsleep:
            return "Generic asleep time recorded by your device. This contributes to your total sleep duration but doesn't specify the sleep stage."
        case .core:
            return "Core sleep is your body's main restorative stage. It helps regulate temperature, process emotions, and prepare for the day ahead."
        case .deep:
            return "Deep sleep is the most restorative stage. This is when your body repairs tissues, builds muscle, and strengthens your immune system."
        case .rem:
            return "REM (Rapid Eye Movement) sleep is when most vivid dreams occur. This stage is vital for cognitive development, memory consolidation, and emotional processing."
        }
    }
    
    var color: Color {
        switch self {
        case .awake: return Color(red: 0.5, green: 0.5, blue: 0.5)  // Gray
        case .unspecifiedAsleep: return Color(red: 0.3, green: 0.3, blue: 0.6)  // Darker gray-blue
        case .core: return Color(red: 0.6, green: 0.3, blue: 0.8)
        case .deep: return Color(red: 0.4, green: 0.2, blue: 0.6)  // Darker purple
        case .rem: return Color(red: 1.0, green: 0.4, blue: 0.6)
        }
    }
}

struct DailySleepSummary: Identifiable {
    let id = UUID()
    let date: Date
    let totalMinutes: Double
    let awakeMinutes: Double
    let deepMinutes: Double
    let coreMinutes: Double
    let remMinutes: Double
    let unspecifiedAsleepMinutes: Double  // Generic/malformed asleep data
    
    // Percentages are calculated only from specific stages (not including unspecified)
    private var specificSleepMinutes: Double {
        awakeMinutes + deepMinutes + coreMinutes + remMinutes
    }
    
    var awakePercentage: Double {
        specificSleepMinutes > 0 ? (awakeMinutes / specificSleepMinutes) * 100 : 0
    }
    
    var deepPercentage: Double {
        specificSleepMinutes > 0 ? (deepMinutes / specificSleepMinutes) * 100 : 0
    }
    
    var corePercentage: Double {
        specificSleepMinutes > 0 ? (coreMinutes / specificSleepMinutes) * 100 : 0
    }
    
    var remPercentage: Double {
        specificSleepMinutes > 0 ? (remMinutes / specificSleepMinutes) * 100 : 0
    }
}

// Formats a minutes value into a human-friendly hours/minutes string.
// Examples: 125 -> "2h 5m", 45 -> "45m", 60 -> "1h". Returns "0m" for non-positive values.
func formatMinutesToHoursMinutes(_ minutesDouble: Double) -> String {
    guard minutesDouble.isFinite else { return "" }
    let totalMinutes = Int(round(minutesDouble))
    if totalMinutes <= 0 { return "0m" }
    let h = totalMinutes / 60
    let m = totalMinutes % 60
    if h > 0 {
        if m > 0 { return "\(h)h \(m)m" }
        return "\(h)h"
    }
    return "\(m)m"
}

// MARK: - Rule-based sleep quality copy (non–Apple Intelligence)

func ruleBasedSleepQualitySummary(stages: [SleepStageData], last7AvgSleepHours: Double?) -> String {
    guard !stages.isEmpty else { return "Insufficient data" }
    let totalDuration = stages.reduce(0) { $0 + $1.duration }
    let awakeDuration = stages.filter { $0.stage == .awake }.reduce(0) { $0 + $1.duration }
    let actualHours = max(0, totalDuration - awakeDuration) / 3600.0
    var analysis = ""
    if actualHours < 7 {
        analysis = "You slept less than the recommended 7–9 hours. Try to extend your sleep duration."
    } else if actualHours > 9 {
        analysis = "You exceeded 9 hours. Quality over quantity—consider keeping a more regular schedule."
    } else {
        analysis = "Your sleep duration is within the recommended 7–9 hour range."
    }
    if let avg7 = last7AvgSleepHours {
        let diff = actualHours - avg7
        let symbol: String
        if diff > 0.75 { symbol = "↑" }
        else if diff < -0.75 { symbol = "↓" }
        else { symbol = "=" }
        let lastMinutes = actualHours * 60.0
        let avg7Minutes = avg7 * 60.0
        analysis += " Sleep consistency: \(symbol) (last night \(formatMinutesToHoursMinutes(lastMinutes)) vs 7-day avg \(formatMinutesToHoursMinutes(avg7Minutes)))."
    }
    let remCount = stages.filter { $0.stage == .rem }.count
    let coreCount = stages.filter { $0.stage == .core }.count
    if remCount > coreCount * 2 {
        analysis += " You had extended REM sleep, which supports learning and emotional processing."
    }
    if stages.first?.stage == .rem {
        analysis += " You entered REM very quickly—possible sleep deficit recovery."
    }
    return analysis
}

private func sleepViewDeviceSupportsAppleIntelligence() -> Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
        let model = SystemLanguageModel(useCase: .general)
        return model.isAvailable
    }
    #endif
    return false
}

// MARK: - Heart rate dip (nocturnal dipping)

enum HeartRateDipBand: String {
    case extremeDipper = "Extreme dipper"
    case dipper = "Dipper (normal)"
    case nonDipper = "Non-dipper"
    case reverseDipper = "Reverse dipper"
    case insufficientData = "Insufficient data"

    var detail: String {
        switch self {
        case .extremeDipper: return "High parasympathetic tone; strong overnight HR reduction vs daytime living."
        case .dipper: return "Healthy cardiovascular rest pattern overnight."
        case .nonDipper: return "Limited dip vs daytime—stress, late meals, or illness can blunt dipping."
        case .reverseDipper: return "HR higher when asleep than daytime baseline—worth discussing with a clinician if persistent."
        case .insufficientData: return "Need more heart rate samples during confirmed sleep."
        }
    }
}

struct HeartRateDipSummary: Sendable {
    var daytimeAvgBpm: Double?
    var nocturnalAvgBpm: Double?
    var dipPercent: Double?
    var band: HeartRateDipBand
    var daytimeSampleCount: Int
    var nocturnalSampleCount: Int
}

// MARK: - Bedtime consistency (deviation from mean)

struct BedtimeConsistencyNight: Identifiable, Sendable {
    var id: Date { nightStart }
    let nightStart: Date
    let firstAsleepTime: Date
    /// Minutes after `nightStart` (6 PM anchor) until first core/deep/REM onset.
    let minutesFromNightAnchor: Double
    /// Deviation from mean `minutesFromNightAnchor`.
    let deviationMinutes: Double
}

// MARK: - Overnight vitals normality strip

struct OvernightVitalMetric: Identifiable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    /// -1 = low/outlier band, 0 = normal band, 1 = high/outlier band (coarse)
    let normalityPosition: Double
    let isOutlier: Bool
    let valueLabel: String
}

/// One row for overnight vitals normality (HealthKit interval averages or engine daily aggregates on Catalyst).
private struct OvernightNormalityNightAgg {
    let sleepMin: Double
    let hr: Double?
    let rr: Double?
    let o2Pct: Double?
    let tempC: Double?
}

private let heartRateDipMinNocturnalSamples = 20
private let heartRateDipMinDaytimeSamples = 5

let sleepAnchorHour = 18 // 6pm anchor for sleep night

// Helper: Given a date, returns the start of the "sleep night" for that date according to the anchor hour.
// If the time is >= anchor hour (e.g., 6pm), the night starts at that day's anchor hour.
// If before anchor hour, the night starts at the previous day's anchor hour.
func sleepNightStart(for date: Date, calendar: Calendar) -> Date {
    let anchorComponents = calendar.dateComponents([.year, .month, .day], from: date)
    let anchorDate = calendar.date(bySettingHour: sleepAnchorHour, minute: 0, second: 0, of: calendar.date(from: anchorComponents)!)!
    if date >= anchorDate {
        return anchorDate
    } else {
        // Previous day's anchor hour
        let prevDay = calendar.date(byAdding: .day, value: -1, to: anchorDate)!
        return prevDay
    }
}

@MainActor
class SleepViewModel: ObservableObject {
    @Published var sleepData: [SleepStageData] = []
    @Published var dailySummaries: [DailySleepSummary] = []
    @Published var isLoading = false
    @Published var selectedPeriod: SleepPeriod = .lastNight
    @Published var earliestSleepDate: Date? = nil
    @Published var last7AvgSleepHours: Double? = nil // average *actual* sleep (excludes awake)
    @Published var heartRateDip: HeartRateDipSummary?
    @Published var bedtimeConsistency: [BedtimeConsistencyNight] = []
    @Published var overnightVitals: [OvernightVitalMetric] = []

    private let healthStore = HealthKitManager()
    /// Cancels stale work when the user switches nights before enrichment finishes.
    private var lastNightEnrichmentTask: Task<Void, Never>?
    
    init() {
        Task {
            await self.fetchEarliestSleepDate()
        }
    }

    #if targetEnvironment(macCatalyst)
    private func engineSleepStages(forDay day: Date, calendar: Calendar) -> [String: Double] {
        let key = calendar.startOfDay(for: day)
        let engine = HealthStateEngine.shared
        if let s = engine.sleepStages[key] { return s }
        for (d, s) in engine.sleepStages where calendar.isDate(d, inSameDayAs: key) {
            return s
        }
        return [:]
    }

    /// Per-day stage map for the **wake calendar day** of this anchor night (matches HealthKit row for `dayStart`: night `nightStart` → `nightStart + 12h` at local midnight).
    /// Using `max` across both spanning calendar days pulled the wrong night’s hours onto zero-sleep days on Catalyst.
    private func engineStageHoursForNightWakeDay(nightStart: Date, calendar: Calendar) -> [String: Double] {
        let probe = calendar.date(byAdding: .hour, value: 12, to: nightStart)!
        let wakeDayStart = calendar.startOfDay(for: probe)
        return engineSleepStages(forDay: wakeDayStart, calendar: calendar)
    }

    /// Maps a sleep-night anchor (6pm–6pm start) to the calendar `dayStart` that `dailySummaryFromEngine` expects.
    private func dailySummaryFromEngineForNightStart(_ nightStart: Date, calendar: Calendar) -> DailySleepSummary {
        let probe = calendar.date(byAdding: .hour, value: 12, to: nightStart)!
        let dayStart = calendar.startOfDay(for: probe)
        return dailySummaryFromEngine(dayStart: dayStart, calendar: calendar)
    }

    /// When detailed segments exist, per-night totals must come from the timeline (same as HealthKit), not `max` of two calendar `sleepStages` buckets — otherwise a missed night can show another night’s hours.
    private func dailySummaryFromSyncedTimeline(dayStart: Date, nightStart: Date, nightEnd: Date, calendar: Calendar) -> DailySleepSummary {
        let raw = HealthStateEngine.shared.sleepTimelineSegments.filter { seg in
            guard seg.end > nightStart && seg.start < nightEnd else { return false }
            return syncedSegmentSleepNightStart(seg, calendar: calendar) == nightStart
        }
        let segs = dedupeEngineTimelineSegments(raw)
        if segs.isEmpty {
            return DailySleepSummary(
                date: dayStart,
                totalMinutes: 0,
                awakeMinutes: 0,
                deepMinutes: 0,
                coreMinutes: 0,
                remMinutes: 0,
                unspecifiedAsleepMinutes: 0
            )
        }
        var out: [SleepStageData] = []
        for seg in segs.sorted(by: { $0.start < $1.start }) {
            guard let st = sleepStageForSyncedTimeline(seg.stageValue) else { continue }
            let s = max(seg.start, nightStart)
            let e = min(seg.end, nightEnd)
            let durMin = e.timeIntervalSince(s) / 60
            if durMin < 2 { continue }
            out.append(SleepStageData(
                startTime: s,
                endTime: e,
                stage: st,
                averageHeartRate: nil,
                averageRespiratoryRate: nil
            ))
        }
        let consolidated = consolidateSleepStages(out)
        guard syncedTimelineAsleepMinutesPlausible(consolidated) else {
            return DailySleepSummary(
                date: dayStart,
                totalMinutes: 0,
                awakeMinutes: 0,
                deepMinutes: 0,
                coreMinutes: 0,
                remMinutes: 0,
                unspecifiedAsleepMinutes: 0
            )
        }
        var awake: Double = 0
        var core: Double = 0
        var deep: Double = 0
        var rem: Double = 0
        var unspec: Double = 0
        for block in consolidated {
            let mins = block.duration / 60
            switch block.stage {
            case .awake: awake += mins
            case .core: core += mins
            case .deep: deep += mins
            case .rem: rem += mins
            case .unspecifiedAsleep: unspec += mins
            }
        }
        let total = awake + core + deep + rem + unspec
        let cappedTotal = min(total, 16 * 60)
        if cappedTotal < total, total > 0 {
            let scale = cappedTotal / total
            return DailySleepSummary(
                date: dayStart,
                totalMinutes: cappedTotal,
                awakeMinutes: awake * scale,
                deepMinutes: deep * scale,
                coreMinutes: core * scale,
                remMinutes: rem * scale,
                unspecifiedAsleepMinutes: unspec * scale
            )
        }
        return DailySleepSummary(
            date: dayStart,
            totalMinutes: total,
            awakeMinutes: awake,
            deepMinutes: deep,
            coreMinutes: core,
            remMinutes: rem,
            unspecifiedAsleepMinutes: unspec
        )
    }

    private func dailySummaryFromEngine(dayStart: Date, calendar: Calendar) -> DailySleepSummary {
        let nightStart = sleepNightStart(for: dayStart, calendar: calendar)
        let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart)!
        if !HealthStateEngine.shared.sleepTimelineSegments.isEmpty {
            return dailySummaryFromSyncedTimeline(dayStart: dayStart, nightStart: nightStart, nightEnd: nightEnd, calendar: calendar)
        }
        let merged = engineStageHoursForNightWakeDay(nightStart: nightStart, calendar: calendar)
        func minutes(_ k: String) -> Double { (merged[k] ?? 0) * 60 }
        let awake = minutes("awake")
        let core = minutes("core")
        let deep = minutes("deep")
        let rem = minutes("rem")
        let unspec = minutes("unspecified")
        let total = awake + core + deep + rem + unspec
        let cappedTotal = min(total, 16 * 60)
        if cappedTotal < total, total > 0 {
            let scale = cappedTotal / total
            return DailySleepSummary(
                date: dayStart,
                totalMinutes: cappedTotal,
                awakeMinutes: awake * scale,
                deepMinutes: deep * scale,
                coreMinutes: core * scale,
                remMinutes: rem * scale,
                unspecifiedAsleepMinutes: unspec * scale
            )
        }
        return DailySleepSummary(
            date: dayStart,
            totalMinutes: total,
            awakeMinutes: awake,
            deepMinutes: deep,
            coreMinutes: core,
            remMinutes: rem,
            unspecifiedAsleepMinutes: unspec
        )
    }

    private func sleepStageForSyncedTimeline(_ raw: Int) -> SleepStage? {
        switch raw {
        case SleepStage.awake.rawValue: return .awake
        case SleepStage.unspecifiedAsleep.rawValue: return .unspecifiedAsleep
        case SleepStage.core.rawValue: return .core
        case SleepStage.deep.rawValue: return .deep
        case SleepStage.rem.rawValue: return .rem
        default: return nil
        }
    }

    /// Drops exact duplicate rows (e.g. repeated CloudKit merges) before consolidation.
    private func dedupeEngineTimelineSegments(_ segs: [EngineSleepTimelineSegment]) -> [EngineSleepTimelineSegment] {
        var seen = Set<String>()
        var out: [EngineSleepTimelineSegment] = []
        for s in segs.sorted(by: { $0.start < $1.start }) {
            let key = String(format: "%.3f_%.3f_%d", s.start.timeIntervalSince1970, s.end.timeIntervalSince1970, s.stageValue)
            guard seen.insert(key).inserted else { continue }
            out.append(s)
        }
        return out
    }

    /// True if summed asleep time is within a plausible single-night bound (guards corrupted / triple-counted sync).
    private func syncedTimelineAsleepMinutesPlausible(_ stages: [SleepStageData]) -> Bool {
        let asleepMin = stages.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration } / 60
        return asleepMin <= 18 * 60 + 30
    }

    /// Prefer midpoint for night attribution so segments starting just before the anchor hour still map to the correct sleep night on Mac.
    private func syncedSegmentSleepNightStart(_ seg: EngineSleepTimelineSegment, calendar: Calendar) -> Date {
        let mid = seg.start.addingTimeInterval(seg.end.timeIntervalSince(seg.start) / 2)
        return sleepNightStart(for: mid, calendar: calendar)
    }

    /// Real HealthKit segments synced from iPhone/iPad via `EngineSleepTimelineBlob` (CloudKit).
    private func engineTimelineStagesForNight(nightStart: Date, nightEnd: Date, calendar: Calendar) -> [SleepStageData] {
        let raw = HealthStateEngine.shared.sleepTimelineSegments.filter { seg in
            guard seg.end > nightStart && seg.start < nightEnd else { return false }
            // Match HK night window; midpoint avoids losing stages whose sample start falls in the prior calendar window.
            return syncedSegmentSleepNightStart(seg, calendar: calendar) == nightStart
        }
        let segs = dedupeEngineTimelineSegments(raw)
        var out: [SleepStageData] = []
        for seg in segs.sorted(by: { $0.start < $1.start }) {
            guard let st = sleepStageForSyncedTimeline(seg.stageValue) else { continue }
            let s = max(seg.start, nightStart)
            let e = min(seg.end, nightEnd)
            let durMin = e.timeIntervalSince(s) / 60
            if durMin < 2 { continue }
            out.append(SleepStageData(
                startTime: s,
                endTime: e,
                stage: st,
                averageHeartRate: nil,
                averageRespiratoryRate: nil
            ))
        }
        let consolidated = consolidateSleepStages(out)
        guard syncedTimelineAsleepMinutesPlausible(consolidated) else { return [] }
        return consolidated
    }

    private func synthesizedSleepStagesFromEngine(
        nightStart: Date,
        nightEnd: Date,
        mergedHours: [String: Double],
        preferredSleepStart: Date?,
        preferredSleepEnd: Date?
    ) -> [SleepStageData] {
        let awakeH = mergedHours["awake"] ?? 0
        let coreH = mergedHours["core"] ?? 0
        let deepH = mergedHours["deep"] ?? 0
        let remH = mergedHours["rem"] ?? 0
        let unspecH = mergedHours["unspecified"] ?? 0
        let splitAwake1 = awakeH * 0.2
        let splitAwake2 = max(0, awakeH - splitAwake1)
        let ordered: [(SleepStage, Double)] = [
            (.awake, splitAwake1),
            (.deep, deepH),
            (.core, coreH),
            (.rem, remH),
            (.unspecifiedAsleep, unspecH),
            (.awake, splitAwake2)
        ]
        let totalW = ordered.map(\.1).reduce(0, +)
        guard totalW > 1e-6 else { return [] }
        var cursor = nightStart
        if let ps = preferredSleepStart, ps >= nightStart, ps < nightEnd {
            cursor = ps
        }
        var span = nightEnd.timeIntervalSince(cursor)
        if span < 60 { return [] }
        if let pe = preferredSleepEnd, pe > cursor {
            let capped = min(pe, nightEnd)
            span = capped.timeIntervalSince(cursor)
        }
        // Without a real sleep window, spreading weights across the full 6pm–6pm interval (~24h) makes totals look like “23h sleep”.
        let plausibleSleepSeconds = min(max(totalW * 3600, 2.5 * 3600), 14 * 3600)
        let hasPreferredWindow = preferredSleepStart.map { $0 >= nightStart && $0 < nightEnd } == true
        if !hasPreferredWindow {
            span = min(span, plausibleSleepSeconds)
        } else if span > plausibleSleepSeconds + 2 * 3600 {
            span = min(span, plausibleSleepSeconds + 1800)
        }
        var out: [SleepStageData] = []
        for (stage, weight) in ordered where weight > 1e-9 {
            let dur = span * (weight / totalW)
            if dur < 30 { continue }
            let end = min(cursor.addingTimeInterval(dur), nightEnd)
            if end > cursor {
                out.append(SleepStageData(
                    startTime: cursor,
                    endTime: end,
                    stage: stage,
                    averageHeartRate: nil,
                    averageRespiratoryRate: nil
                ))
                cursor = end
            }
        }
        return out
    }

    private func updateLast7AvgSleepHoursFromEngine(referenceNightStart: Date, calendar: Calendar) {
        var totals: [Double] = []
        for offset in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: referenceNightStart) else { continue }
            let startOfDay = calendar.startOfDay(for: d)
            let summary = dailySummaryFromEngine(dayStart: startOfDay, calendar: calendar)
            let actualMinutes = max(0, summary.totalMinutes - summary.awakeMinutes)
            totals.append(actualMinutes / 60.0)
        }
        guard totals.count == 7 else {
            last7AvgSleepHours = nil
            return
        }
        last7AvgSleepHours = totals.reduce(0, +) / 7.0
    }

    private func engineDailyScalar(wakeDay: Date, dict: [Date: Double], calendar: Calendar) -> Double? {
        let k = calendar.startOfDay(for: wakeDay)
        if let v = dict[k] { return v }
        for (dk, v) in dict where calendar.isDate(dk, inSameDayAs: k) { return v }
        return nil
    }

    private func coreDeepREMIntervalsFromEngineTimeline(nightStart: Date, nightEnd: Date, calendar: Calendar) -> [(Date, Date)] {
        let asleepVals: Set<Int> = [SleepStage.core.rawValue, SleepStage.deep.rawValue, SleepStage.rem.rawValue]
        let raw = HealthStateEngine.shared.sleepTimelineSegments.filter { seg in
            guard asleepVals.contains(seg.stageValue) else { return false }
            guard seg.end > nightStart && seg.start < nightEnd else { return false }
            return syncedSegmentSleepNightStart(seg, calendar: calendar) == nightStart
        }
        let segs = dedupeEngineTimelineSegments(raw).sorted { $0.start < $1.start }
        var intervals: [(Date, Date)] = []
        for seg in segs {
            let a = max(seg.start, nightStart)
            let b = min(seg.end, nightEnd)
            if b > a { intervals.append((a, b)) }
        }
        return intervals
    }

    private func firstAsleepOnsetFromEngineTimeline(nightStart: Date, nightEnd: Date, calendar: Calendar) -> Date? {
        let merged = mergeIntervals(coreDeepREMIntervalsFromEngineTimeline(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar))
        return merged.first?.0
    }

    /// Uses synced daily resting vs sleep HR from `HealthStateEngine` (not raw HK samples on Catalyst).
    private func loadHeartRateDipFromEngine(nightStart: Date, nightEnd _: Date, calendar: Calendar) async {
        let engine = HealthStateEngine.shared
        let probe = calendar.date(byAdding: .hour, value: 12, to: nightStart)!
        let wakeDay = calendar.startOfDay(for: probe)
        let nMean = engineDailyScalar(wakeDay: wakeDay, dict: engine.dailySleepHeartRate, calendar: calendar)
            ?? engineDailyScalar(wakeDay: wakeDay, dict: engine.basalSleepingHeartRate, calendar: calendar)
        let dMean = engineDailyScalar(wakeDay: wakeDay, dict: engine.dailyRestingHeartRate, calendar: calendar) ?? engine.restingHeartRate
        let syntheticSamples = 24
        let summary: HeartRateDipSummary
        if let d = dMean, d > 0, let n = nMean, n > 0 {
            let dip = ((d - n) / d) * 100.0
            let band: HeartRateDipBand
            if dip > 20 { band = .extremeDipper }
            else if dip >= 10 { band = .dipper }
            else if dip >= 0 { band = .nonDipper }
            else { band = .reverseDipper }
            summary = HeartRateDipSummary(
                daytimeAvgBpm: d,
                nocturnalAvgBpm: n,
                dipPercent: dip,
                band: band,
                daytimeSampleCount: syntheticSamples,
                nocturnalSampleCount: syntheticSamples
            )
        } else {
            summary = HeartRateDipSummary(
                daytimeAvgBpm: dMean,
                nocturnalAvgBpm: nMean,
                dipPercent: nil,
                band: .insufficientData,
                daytimeSampleCount: 0,
                nocturnalSampleCount: 0
            )
        }
        await MainActor.run { self.heartRateDip = summary }
    }

    private func loadBedtimeConsistencyFromEngine(currentNightStart: Date, calendar: Calendar, nights: Int) async {
        var rows: [BedtimeConsistencyNight] = []
        for i in 0..<nights {
            guard let ns = calendar.date(byAdding: .day, value: -i, to: currentNightStart) else { continue }
            let ne = calendar.date(byAdding: .day, value: 1, to: ns)!
            if let onset = firstAsleepOnsetFromEngineTimeline(nightStart: ns, nightEnd: ne, calendar: calendar) {
                let offsetMin = max(0, onset.timeIntervalSince(ns) / 60.0)
                rows.append(BedtimeConsistencyNight(
                    nightStart: ns,
                    firstAsleepTime: onset,
                    minutesFromNightAnchor: offsetMin,
                    deviationMinutes: 0
                ))
            }
        }
        let meanOffset = rows.isEmpty ? 0 : rows.map(\.minutesFromNightAnchor).reduce(0, +) / Double(rows.count)
        let adjusted = rows.map { r in
            BedtimeConsistencyNight(
                nightStart: r.nightStart,
                firstAsleepTime: r.firstAsleepTime,
                minutesFromNightAnchor: r.minutesFromNightAnchor,
                deviationMinutes: r.minutesFromNightAnchor - meanOffset
            )
        }.sorted { $0.nightStart < $1.nightStart }
        await MainActor.run { self.bedtimeConsistency = adjusted }
    }

    private func loadOvernightVitalsFromEngine(currentNightStart: Date, calendar: Calendar) async {
        let engine = HealthStateEngine.shared
        var aggs: [OvernightNormalityNightAgg] = []
        for i in 0..<14 {
            guard let ns = calendar.date(byAdding: .day, value: -i, to: currentNightStart) else { continue }
            let ne = calendar.date(byAdding: .day, value: 1, to: ns)!
            let probe = calendar.date(byAdding: .hour, value: 12, to: ns)!
            let wakeDay = calendar.startOfDay(for: probe)
            let ivs = mergeIntervals(coreDeepREMIntervalsFromEngineTimeline(nightStart: ns, nightEnd: ne, calendar: calendar))
            let totalMin: Double
            if !ivs.isEmpty {
                totalMin = ivs.reduce(0.0) { acc, pair in acc + pair.1.timeIntervalSince(pair.0) } / 60.0
            } else {
                let sum = dailySummaryFromEngine(dayStart: wakeDay, calendar: calendar)
                totalMin = max(0, sum.totalMinutes - sum.awakeMinutes)
            }
            guard totalMin >= 15 else { continue }
            let hrV = engineDailyScalar(wakeDay: wakeDay, dict: engine.dailySleepHeartRate, calendar: calendar)
                ?? engineDailyScalar(wakeDay: wakeDay, dict: engine.basalSleepingHeartRate, calendar: calendar)
            let rrV = engineDailyScalar(wakeDay: wakeDay, dict: engine.respiratoryRate, calendar: calendar)
            let o2V = engineDailyScalar(wakeDay: wakeDay, dict: engine.spO2, calendar: calendar)
            let wtV = engineDailyScalar(wakeDay: wakeDay, dict: engine.wristTemperature, calendar: calendar)
            aggs.append(OvernightNormalityNightAgg(sleepMin: totalMin, hr: hrV, rr: rrV, o2Pct: o2V, tempC: wtV))
        }
        let metrics = overnightVitalsMetricsFromAggregates(aggs)
        await MainActor.run { self.overnightVitals = metrics }
    }

    private func loadLastNightDataFromEngine(calendar: Calendar, for date: Date) async {
        heartRateDip = nil
        bedtimeConsistency = []
        overnightVitals = []
        let nightStart = sleepNightStart(for: date, calendar: calendar)
        let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart)!
        let engine = HealthStateEngine.shared
        let wakeProbe = calendar.date(byAdding: .hour, value: 12, to: nightStart)!
        let wakeDay = calendar.startOfDay(for: wakeProbe)

        let uiPkg = engine.sleepNightUIPackage(forWakeDay: wakeDay)
        let handoffBed = engine.sleepUIMetricsHandoff.bedtimeNights

        var usedHandoffStages = false
        if let pkg = uiPkg, !pkg.segments.isEmpty {
            var mapped: [SleepStageData] = []
            mapped.reserveCapacity(pkg.segments.count)
            for seg in pkg.segments {
                guard let st = sleepStageForSyncedTimeline(seg.stageValue) else { continue }
                mapped.append(SleepStageData(
                    startTime: seg.start,
                    endTime: seg.end,
                    stage: st,
                    averageHeartRate: seg.averageHeartRate,
                    averageRespiratoryRate: seg.averageRespiratoryRate
                ))
            }
            if !mapped.isEmpty {
                sleepData = consolidateSleepStages(mapped)
                usedHandoffStages = true
                if let d = pkg.heartRateDip {
                    heartRateDip = HeartRateDipSummary(
                        daytimeAvgBpm: d.daytimeAvgBpm,
                        nocturnalAvgBpm: d.nocturnalAvgBpm,
                        dipPercent: d.dipPercent,
                        band: HeartRateDipBand(rawValue: d.bandRaw) ?? .insufficientData,
                        daytimeSampleCount: d.daytimeSampleCount,
                        nocturnalSampleCount: d.nocturnalSampleCount
                    )
                }
                if !pkg.overnightVitals.isEmpty {
                    overnightVitals = pkg.overnightVitals.map {
                        OvernightVitalMetric(
                            id: $0.id,
                            title: $0.title,
                            systemImage: $0.systemImage,
                            normalityPosition: $0.normalityPosition,
                            isOutlier: $0.isOutlier,
                            valueLabel: $0.valueLabel
                        )
                    }
                }
            }
        }

        if !usedHandoffStages {
            let merged = engineStageHoursForNightWakeDay(nightStart: nightStart, calendar: calendar)
            let fromTimeline = engineTimelineStagesForNight(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar)
            var stages: [SleepStageData] = fromTimeline
            let ls = engine.lastSleepStart
            let le = engine.lastSleepEnd
            let useLastSleepWindow: Bool = {
                guard let s = ls, let e = le else { return false }
                return s >= nightStart && s < nightEnd && e > s && e <= nightEnd
            }()
            if stages.isEmpty && engine.sleepTimelineSegments.isEmpty {
                stages = synthesizedSleepStagesFromEngine(
                    nightStart: nightStart,
                    nightEnd: nightEnd,
                    mergedHours: merged,
                    preferredSleepStart: useLastSleepWindow ? ls : nil,
                    preferredSleepEnd: useLastSleepWindow ? le : nil
                )
            }
            sleepData = consolidateSleepStages(stages)
        }

        if !handoffBed.isEmpty {
            bedtimeConsistency = handoffBed.map {
                BedtimeConsistencyNight(
                    nightStart: $0.nightStart,
                    firstAsleepTime: $0.firstAsleepTime,
                    minutesFromNightAnchor: $0.minutesFromNightAnchor,
                    deviationMinutes: $0.deviationMinutes
                )
            }.sorted { $0.nightStart < $1.nightStart }
        } else {
            await loadBedtimeConsistencyFromEngine(currentNightStart: nightStart, calendar: calendar, nights: 14)
        }

        updateLast7AvgSleepHoursFromEngine(referenceNightStart: nightStart, calendar: calendar)

        if heartRateDip == nil {
            await loadHeartRateDipFromEngine(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar)
        }
        if overnightVitals.isEmpty {
            await loadOvernightVitalsFromEngine(currentNightStart: nightStart, calendar: calendar)
        }
    }
    #endif
    
    func fetchEarliestSleepDate() async {
        #if targetEnvironment(macCatalyst)
        let cal = Calendar.current
        let engine = HealthStateEngine.shared
        var keys: [Date] = []
        keys.append(contentsOf: engine.sleepStages.keys.map { cal.startOfDay(for: $0) })
        keys.append(contentsOf: engine.dailySleepDuration.keys.map { cal.startOfDay(for: $0) })
        keys.append(contentsOf: engine.anchoredSleepDuration.keys.map { cal.startOfDay(for: $0) })
        let rawMin = keys.min()
        let floor = MacCatalystHealthDataPolicy.minimumAllowedDate
        await MainActor.run {
            if let m = rawMin {
                self.earliestSleepDate = max(m, floor)
            } else {
                self.earliestSleepDate = floor
            }
        }
        return
        #else
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date(), options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let earliest: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.healthStore.execute(query)
        }
        DispatchQueue.main.async {
            self.earliestSleepDate = earliest.first?.startDate
        }
        #endif
    }
    
    func loadSleepData(for date: Date) async {
        isLoading = true
        lastNightEnrichmentTask?.cancel()
        lastNightEnrichmentTask = nil
        let calendar = Calendar.current

        switch selectedPeriod {
        case .lastNight:
            #if targetEnvironment(macCatalyst)
            await loadLastNightDataFromEngine(calendar: calendar, for: date)
            #else
            if let payload = await loadLastNightPrimaryFromHealthKit(calendar: calendar, for: date) {
                lastNightEnrichmentTask = Task { [weak self] in
                    guard let self else { return }
                    await self.loadLastNightSecondaryFromHealthKit(
                        nightStart: payload.nightStart,
                        nightEnd: payload.nightEnd,
                        calendar: calendar,
                        consolidatedStages: payload.consolidatedStages
                    )
                }
            }
            #endif
        case .thisWeek:
            await MainActor.run {
                self.heartRateDip = nil
                self.bedtimeConsistency = []
                self.overnightVitals = []
            }
            await loadWeekData(calendar: calendar, for: date)
        case .thisMonth:
            await MainActor.run {
                self.heartRateDip = nil
                self.bedtimeConsistency = []
                self.overnightVitals = []
            }
            await loadMonthData(calendar: calendar, for: date)
        case .thisYear:
            await MainActor.run {
                self.heartRateDip = nil
                self.bedtimeConsistency = []
                self.overnightVitals = []
            }
            await loadYearData(calendar: calendar, for: date)
        }

        isLoading = false
    }

    #if !targetEnvironment(macCatalyst)
    private struct LastNightPrimaryPayload {
        let nightStart: Date
        let nightEnd: Date
        let consolidatedStages: [SleepStageData]
    }

    /// HealthKit timeline + per-stage vitals only. Does not run dip / bedtime / overnight normality / CloudKit (those are secondary).
    private func loadLastNightPrimaryFromHealthKit(calendar: Calendar, for date: Date) async -> LastNightPrimaryPayload? {
        let nightStart = sleepNightStart(for: date, calendar: calendar)
        let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart)!
        let predicate = HKQuery.predicateForSamples(
            withStart: calendar.date(byAdding: .hour, value: -12, to: nightStart)!,
            end: nightEnd,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let sleepSamples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }
            healthStore.healthStore.execute(query)
        }

        let filteredSamples = sleepSamples.filter {
            sleepNightStart(for: $0.startDate, calendar: calendar) == nightStart
        }

        var stages: [SleepStageData] = []
        for sample in filteredSamples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
            if duration < 2 {
                continue
            }
            let metrics = await fetchMetricsDuringStage(startTime: sample.startDate, endTime: sample.endDate)
            if sample.value == SleepStage.awake.rawValue {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .awake,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == SleepStage.unspecifiedAsleep.rawValue {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .unspecifiedAsleep,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == SleepStage.core.rawValue {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .core,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == SleepStage.deep.rawValue {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .deep,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == SleepStage.rem.rawValue {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .rem,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            }
        }

        let consolidatedStages = consolidateSleepStages(stages)
        let cal = Calendar.current
        var totals: [Double] = []
        for offset in 0..<7 {
            let d = cal.date(byAdding: .day, value: -offset, to: nightStart)!
            let startOfDay = cal.startOfDay(for: d)
            let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
            Task {
                let summary = await self.fetchDaySleepSummary(startDate: startOfDay, endDate: endOfDay)
                let actualMinutes = max(0, summary.totalMinutes - summary.awakeMinutes)
                totals.append(actualMinutes / 60.0)
                if totals.count == 7 {
                    let avg = totals.reduce(0, +) / 7.0
                    await MainActor.run { self.last7AvgSleepHours = avg }
                }
            }
        }
        sleepData = consolidatedStages
        return LastNightPrimaryPayload(nightStart: nightStart, nightEnd: nightEnd, consolidatedStages: consolidatedStages)
    }

    private func loadLastNightSecondaryFromHealthKit(
        nightStart: Date,
        nightEnd: Date,
        calendar: Calendar,
        consolidatedStages: [SleepStageData]
    ) async {
        if Task.isCancelled { return }
        async let dip: Void = loadHeartRateDip(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar)
        async let bed: Void = loadBedtimeConsistencySeries(currentNightStart: nightStart, calendar: calendar, nights: 14)
        async let vit: Void = loadOvernightVitalsNormality(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar)
        _ = await (dip, bed, vit)
        if Task.isCancelled { return }
        recordSleepUIMetricsHandoffForCloudKit(
            nightStart: nightStart,
            calendar: calendar,
            consolidatedStages: consolidatedStages
        )
    }
    #endif

    #if !targetEnvironment(macCatalyst)
    /// Packages Sleep tab state for Mac Catalyst (CloudKit `sleepUIMetricsDetailed`). Runs off the night load critical path; CloudKit upload is scheduled inside the engine.
    private func recordSleepUIMetricsHandoffForCloudKit(
        nightStart: Date,
        calendar: Calendar,
        consolidatedStages: [SleepStageData]
    ) {
        let probe = calendar.date(byAdding: .hour, value: 12, to: nightStart)!
        let wakeDay = calendar.startOfDay(for: probe)
        let groups = Dictionary(grouping: consolidatedStages, by: { $0.stage.rawValue })
        var aggs: [EngineSleepStageAggregateHandoff] = []
        for (raw, arr) in groups {
            let hrs = arr.compactMap { $0.averageHeartRate }
            let rrs = arr.compactMap { $0.averageRespiratoryRate }
            aggs.append(EngineSleepStageAggregateHandoff(
                stageValue: raw,
                blockCount: arr.count,
                hrMin: hrs.min(),
                hrMax: hrs.max(),
                hrAvg: hrs.isEmpty ? nil : Double(hrs.reduce(0, +)) / Double(hrs.count),
                rrMin: rrs.min(),
                rrMax: rrs.max(),
                rrAvg: rrs.isEmpty ? nil : Double(rrs.reduce(0, +)) / Double(rrs.count)
            ))
        }
        aggs.sort { $0.stageValue < $1.stageValue }
        let segs = consolidatedStages.map {
            EngineSleepSegmentVitalsHandoff(
                start: $0.startTime,
                end: $0.endTime,
                stageValue: $0.stage.rawValue,
                averageHeartRate: $0.averageHeartRate,
                averageRespiratoryRate: $0.averageRespiratoryRate
            )
        }
        let dipH = heartRateDip.map {
            EngineHeartRateDipHandoff(
                daytimeAvgBpm: $0.daytimeAvgBpm,
                nocturnalAvgBpm: $0.nocturnalAvgBpm,
                dipPercent: $0.dipPercent,
                bandRaw: $0.band.rawValue,
                daytimeSampleCount: $0.daytimeSampleCount,
                nocturnalSampleCount: $0.nocturnalSampleCount
            )
        }
        let bed = bedtimeConsistency.map {
            EngineBedtimeNightHandoff(
                nightStart: $0.nightStart,
                firstAsleepTime: $0.firstAsleepTime,
                minutesFromNightAnchor: $0.minutesFromNightAnchor,
                deviationMinutes: $0.deviationMinutes
            )
        }
        let vit = overnightVitals.map {
            EngineOvernightVitalHandoff(
                id: $0.id,
                title: $0.title,
                systemImage: $0.systemImage,
                normalityPosition: $0.normalityPosition,
                isOutlier: $0.isOutlier,
                valueLabel: $0.valueLabel
            )
        }
        let pkg = EngineSleepNightUIPackage(
            wakeDayStart: wakeDay,
            stageAggregates: aggs,
            segments: segs,
            heartRateDip: dipH,
            overnightVitals: vit
        )
        HealthStateEngine.shared.upsertSleepUIMetricsHandoff(pkg, bedtimeNights: bed)
    }
    #endif

    private func fetchQuantitySamples(
        type: HKQuantityType,
        from start: Date,
        to end: Date
    ) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.healthStore.execute(q)
        }
    }

    private func fetchWorkouts(from start: Date, to end: Date) async -> [HKWorkout] {
        let type = HKObjectType.workoutType()
        return await withCheckedContinuation { continuation in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.healthStore.execute(q)
        }
    }

    private func asleepCoreDeepREMIntervals(nightStart: Date, nightEnd: Date, calendar: Calendar) async -> [(Date, Date)] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let pred = HKQuery.predicateForSamples(
            withStart: calendar.date(byAdding: .hour, value: -12, to: nightStart)!,
            end: nightEnd,
            options: .strictStartDate
        )
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: sleepType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                continuation.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            healthStore.healthStore.execute(q)
        }
        let asleepValues: Set<Int> = [SleepStage.core.rawValue, SleepStage.deep.rawValue, SleepStage.rem.rawValue]
        var intervals: [(Date, Date)] = []
        for sa in samples where asleepValues.contains(sa.value) {
            let a = max(sa.startDate, nightStart)
            let b = min(sa.endDate, nightEnd)
            if b > a { intervals.append((a, b)) }
        }
        return intervals.sorted { $0.0 < $1.0 }
    }

    private func mergeIntervals(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        guard !intervals.isEmpty else { return [] }
        var merged: [(Date, Date)] = []
        for iv in intervals {
            if let last = merged.last, iv.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, iv.1)
            } else {
                merged.append(iv)
            }
        }
        return merged
    }

    private func overnightVitalsMetricsFromAggregates(_ aggs: [OvernightNormalityNightAgg]) -> [OvernightVitalMetric] {
        guard !aggs.isEmpty else { return [] }
        let historyHR = aggs.compactMap(\.hr)
        let historyRR = aggs.compactMap(\.rr)
        let historyO2 = aggs.compactMap(\.o2Pct)
        let historyTemp = aggs.compactMap(\.tempC)
        let historySleepMin = aggs.map(\.sleepMin)
        func median(_ a: [Double]) -> Double? {
            guard !a.isEmpty else { return nil }
            let s = a.sorted()
            return s[s.count / 2]
        }
        let curHR = aggs.first?.hr
        let curRR = aggs.first?.rr
        let curO2 = aggs.first?.o2Pct
        let curTemp = aggs.first?.tempC
        let curSleep = aggs.first.map(\.sleepMin)
        let hrP = curHR.map { v in
            let med = median(historyHR) ?? v
            let dev = v - med
            let absDevs = historyHR.map { abs($0 - med) }.sorted()
            let m = max(absDevs[absDevs.count / 2], 1)
            let z = dev / m
            return (max(-1, min(1, z / 2.5)), abs(z) >= 2, String(format: "%.0f bpm", v))
        }
        let rrP = curRR.map { v in
            let med = median(historyRR) ?? v
            let dev = v - med
            let absDevs = historyRR.map { abs($0 - med) }.sorted()
            let m = max(absDevs[absDevs.count / 2], 0.5)
            let z = dev / m
            return (max(-1, min(1, z / 2.5)), abs(z) >= 2, String(format: "%.1f /min", v))
        }
        let o2P = curO2.map { v in
            let med = median(historyO2) ?? v
            let dev = v - med
            let absDevs = historyO2.map { abs($0 - med) }.sorted()
            let m = max(absDevs[absDevs.count / 2], 0.5)
            let z = dev / m
            return (max(-1, min(1, z / 2.5)), abs(z) >= 2 && dev < 0, String(format: "%.0f%%", v))
        }
        let tempP = curTemp.map { v in
            let med = median(historyTemp) ?? v
            let dev = v - med
            let absDevs = historyTemp.map { abs($0 - med) }.sorted()
            let m = max(absDevs[absDevs.count / 2], 0.05)
            let z = dev / m
            return (max(-1, min(1, z / 2.5)), abs(z) >= 2 && dev > 0, String(format: "%.1f °C", v))
        }
        let sleepP = curSleep.map { v in
            let med = median(historySleepMin) ?? v
            let dev = v - med
            let absDevs = historySleepMin.map { abs($0 - med) }.sorted()
            let m = max(absDevs[absDevs.count / 2], 15)
            let z = dev / m
            return (max(-1, min(1, z / 2.5)), abs(z) >= 2, formatMinutesToHoursMinutes(v))
        }
        var metrics: [OvernightVitalMetric] = []
        if let h = hrP {
            metrics.append(OvernightVitalMetric(id: "hr", title: "Heart rate", systemImage: "heart.fill", normalityPosition: h.0, isOutlier: h.1, valueLabel: h.2))
        }
        if let r = rrP {
            metrics.append(OvernightVitalMetric(id: "rr", title: "Respiratory", systemImage: "lungs.fill", normalityPosition: r.0, isOutlier: r.1, valueLabel: r.2))
        }
        if let t = tempP {
            metrics.append(OvernightVitalMetric(id: "temp", title: "Wrist temp", systemImage: "thermometer.medium", normalityPosition: t.0, isOutlier: t.1, valueLabel: t.2))
        }
        if let o = o2P {
            metrics.append(OvernightVitalMetric(id: "o2", title: "Blood O₂", systemImage: "drop.fill", normalityPosition: o.0, isOutlier: o.1, valueLabel: o.2))
        }
        if let s = sleepP {
            metrics.append(OvernightVitalMetric(id: "sleep", title: "Sleep (asleep)", systemImage: "bed.double.fill", normalityPosition: s.0, isOutlier: s.1, valueLabel: s.2))
        }
        return metrics
    }

    private func sampleOverlapsAsleep(_ t: Date, intervals: [(Date, Date)]) -> Bool {
        intervals.contains { t >= $0.0 && t <= $0.1 }
    }

    /// True when the sample’s time range intersects any merged asleep interval (handles point samples and samples whose start is just outside asleep but overlap).
    private func quantitySampleOverlapsAsleepIntervals(_ sample: HKQuantitySample, intervals: [(Date, Date)]) -> Bool {
        let s0 = sample.startDate
        let s1 = max(sample.endDate, s0.addingTimeInterval(0.001))
        for (a, b) in intervals where b > a {
            if s1 > a && s0 < b { return true }
        }
        return false
    }

    private func loadHeartRateDip(nightStart: Date, nightEnd: Date, calendar: Calendar) async {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            await MainActor.run { self.heartRateDip = nil }
            return
        }
        let bedDayStart = calendar.startOfDay(for: nightStart)
        guard let dayStart8 = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: bedDayStart),
              let dayEnd20 = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: bedDayStart) else {
            await MainActor.run { self.heartRateDip = nil }
            return
        }
        let workouts = await fetchWorkouts(from: dayStart8, to: dayEnd20)
        let workoutRanges = workouts.map { ($0.startDate, $0.endDate) }
        let daySamples = await fetchQuantitySamples(type: hrType, from: dayStart8, to: dayEnd20)
        let dayFiltered = daySamples.filter { s in
            let t = s.startDate
            guard !workoutRanges.contains(where: { t >= $0.0 && t <= $0.1 }) else { return false }
            if let ctx = s.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber {
                let v = ctx.intValue
                if v == HKHeartRateMotionContext.active.rawValue { return false }
            }
            return true
        }
        let dayBpms = dayFiltered.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
        let dayMean = dayBpms.isEmpty ? nil : dayBpms.reduce(0, +) / Double(dayBpms.count)

        let asleep = mergeIntervals(await asleepCoreDeepREMIntervals(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar))
        let nightAll = await fetchQuantitySamples(type: hrType, from: nightStart, to: nightEnd)
        let nightBpms: [Double] = nightAll.compactMap { s in
            guard quantitySampleOverlapsAsleepIntervals(s, intervals: asleep) else { return nil }
            if let ctx = s.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber,
               ctx.intValue == HKHeartRateMotionContext.active.rawValue { return nil }
            return s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        let nightMean = nightBpms.isEmpty ? nil : nightBpms.reduce(0, +) / Double(nightBpms.count)

        let summary: HeartRateDipSummary = {
            guard let dMean = dayMean, dMean > 0, let nMean = nightMean,
                  dayBpms.count >= heartRateDipMinDaytimeSamples,
                  nightBpms.count >= heartRateDipMinNocturnalSamples else {
                return HeartRateDipSummary(
                    daytimeAvgBpm: dayMean,
                    nocturnalAvgBpm: nightMean,
                    dipPercent: nil,
                    band: .insufficientData,
                    daytimeSampleCount: dayBpms.count,
                    nocturnalSampleCount: nightBpms.count
                )
            }
            let dip = ((dMean - nMean) / dMean) * 100.0
            let band: HeartRateDipBand
            if dip > 20 { band = .extremeDipper }
            else if dip >= 10 { band = .dipper }
            else if dip >= 0 { band = .nonDipper }
            else { band = .reverseDipper }
            return HeartRateDipSummary(
                daytimeAvgBpm: dMean,
                nocturnalAvgBpm: nMean,
                dipPercent: dip,
                band: band,
                daytimeSampleCount: dayBpms.count,
                nocturnalSampleCount: nightBpms.count
            )
        }()
        await MainActor.run { self.heartRateDip = summary }
    }

    private func firstAsleepOnset(nightStart: Date, nightEnd: Date, calendar: Calendar) async -> Date? {
        let intervals = mergeIntervals(await asleepCoreDeepREMIntervals(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar))
        return intervals.first?.0
    }

    private func loadBedtimeConsistencySeries(currentNightStart: Date, calendar: Calendar, nights: Int) async {
        var rows: [BedtimeConsistencyNight] = []
        for i in 0..<nights {
            guard let ns = calendar.date(byAdding: .day, value: -i, to: currentNightStart) else { continue }
            let ne = calendar.date(byAdding: .day, value: 1, to: ns)!
            if let onset = await firstAsleepOnset(nightStart: ns, nightEnd: ne, calendar: calendar) {
                let offsetMin = max(0, onset.timeIntervalSince(ns) / 60.0)
                rows.append(BedtimeConsistencyNight(
                    nightStart: ns,
                    firstAsleepTime: onset,
                    minutesFromNightAnchor: offsetMin,
                    deviationMinutes: 0
                ))
            }
        }
        let meanOffset = rows.isEmpty ? 0 : rows.map(\.minutesFromNightAnchor).reduce(0, +) / Double(rows.count)
        let adjusted = rows.map { r in
            BedtimeConsistencyNight(
                nightStart: r.nightStart,
                firstAsleepTime: r.firstAsleepTime,
                minutesFromNightAnchor: r.minutesFromNightAnchor,
                deviationMinutes: r.minutesFromNightAnchor - meanOffset
            )
        }.sorted { $0.nightStart < $1.nightStart }
        await MainActor.run { self.bedtimeConsistency = adjusted }
    }

    /// Averages quantity samples that **overlap** merged asleep intervals. Uses `fetchFrom`…`fetchTo` (e.g. full sleep night) so samples aren’t dropped by `strictStartDate` when their start is before the first asleep segment. For heart rate, optionally drops active-motion samples to align closer with Health’s resting/sleep averages.
    private func averageQuantityDuringIntervals(
        type: HKQuantityType,
        unit: HKUnit,
        intervals: [(Date, Date)],
        fetchFrom: Date,
        fetchTo: Date,
        excludeActiveMotionHeartRate: Bool = false
    ) async -> Double? {
        guard !intervals.isEmpty else { return nil }
        let isHR = type.identifier == HKQuantityTypeIdentifier.heartRate.rawValue
        let samples = await fetchQuantitySamples(type: type, from: fetchFrom, to: fetchTo)
        var vals: [Double] = []
        for s in samples {
            guard quantitySampleOverlapsAsleepIntervals(s, intervals: intervals) else { continue }
            if excludeActiveMotionHeartRate, isHR,
               let ctx = s.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber,
               ctx.intValue == HKHeartRateMotionContext.active.rawValue {
                continue
            }
            vals.append(s.quantity.doubleValue(for: unit))
        }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func loadOvernightVitalsNormality(nightStart: Date, nightEnd: Date, calendar: Calendar) async {
        let asleep = mergeIntervals(await asleepCoreDeepREMIntervals(nightStart: nightStart, nightEnd: nightEnd, calendar: calendar))
        guard !asleep.isEmpty else {
            await MainActor.run { self.overnightVitals = [] }
            return
        }
        var aggs: [OvernightNormalityNightAgg] = []
        for i in 0..<14 {
            guard let ns = calendar.date(byAdding: .day, value: -i, to: nightStart) else { continue }
            let ne = calendar.date(byAdding: .day, value: 1, to: ns)!
            let ivs = mergeIntervals(await asleepCoreDeepREMIntervals(nightStart: ns, nightEnd: ne, calendar: calendar))
            guard !ivs.isEmpty else { continue }
            let totalMin = ivs.reduce(0.0) { acc, pair in acc + pair.1.timeIntervalSince(pair.0) } / 60.0
            var hrV: Double?
            var rrV: Double?
            var o2V: Double?
            var wtV: Double?
            if let hrT = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                hrV = await averageQuantityDuringIntervals(
                    type: hrT,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    intervals: ivs,
                    fetchFrom: ns,
                    fetchTo: ne,
                    excludeActiveMotionHeartRate: true
                )
            }
            if let rrT = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
                rrV = await averageQuantityDuringIntervals(
                    type: rrT,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    intervals: ivs,
                    fetchFrom: ns,
                    fetchTo: ne
                )
            }
            if let o2T = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation),
               let raw = await averageQuantityDuringIntervals(
                type: o2T,
                unit: HKUnit.percent(),
                intervals: ivs,
                fetchFrom: ns,
                fetchTo: ne
               ) {
                o2V = raw * 100
            }
            if let wtT = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                wtV = await averageQuantityDuringIntervals(
                    type: wtT,
                    unit: HKUnit.degreeCelsius(),
                    intervals: ivs,
                    fetchFrom: ns,
                    fetchTo: ne
                )
            }
            if wtV == nil, let bt = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
                wtV = await averageQuantityDuringIntervals(
                    type: bt,
                    unit: HKUnit.degreeCelsius(),
                    intervals: ivs,
                    fetchFrom: ns,
                    fetchTo: ne
                )
            }
            aggs.append(OvernightNormalityNightAgg(sleepMin: totalMin, hr: hrV, rr: rrV, o2Pct: o2V, tempC: wtV))
        }
        let metrics = overnightVitalsMetricsFromAggregates(aggs)
        await MainActor.run { self.overnightVitals = metrics }
    }
    
    private func loadWeekData(calendar: Calendar, for date: Date) async {
        var summaries: [DailySleepSummary] = []
        // date is a Sunday; show 7 days starting from date
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: date)!
            let startOfDay = calendar.startOfDay(for: day)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let summary = await fetchDaySleepSummary(startDate: startOfDay, endDate: endOfDay)
            // Always keep all 7 days so Saturday is not dropped from the chart.
            // (Zeros can be handled later in averaging logic, but the bar should still exist.)
            summaries.append(summary)
        }
        self.dailySummaries = summaries
    }
    
    private func loadMonthData(calendar: Calendar, for date: Date) async {
        var summaries: [DailySleepSummary] = []
        // date is first of the month
        let range = calendar.range(of: .day, in: .month, for: date)!
        let components = calendar.dateComponents([.year, .month], from: date)
        for day in 1...range.count {
            let d = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day))!
            let startOfDay = calendar.startOfDay(for: d)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let summary = await fetchDaySleepSummary(startDate: startOfDay, endDate: endOfDay)
            // Always keep every calendar day so missing sleep does not shift bars vs axis labels.
            summaries.append(summary)
        }
        self.dailySummaries = summaries
    }
    
    private func loadYearData(calendar: Calendar, for date: Date) async {
        var monthlySummaries: [DailySleepSummary] = []
        // date is Jan 1 of the year
        let year = calendar.component(.year, from: date)
        for month in 1...12 {
            let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            let monthSummary = await fetchMonthSleepSummary(startDate: startOfMonth, endDate: endOfMonth)
            let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
            let nights = Double(range.count)
            let avgSummary = DailySleepSummary(
                date: startOfMonth,
                totalMinutes: monthSummary.totalMinutes / nights,
                awakeMinutes: monthSummary.awakeMinutes / nights,
                deepMinutes: monthSummary.deepMinutes / nights,
                coreMinutes: monthSummary.coreMinutes / nights,
                remMinutes: monthSummary.remMinutes / nights,
                unspecifiedAsleepMinutes: monthSummary.unspecifiedAsleepMinutes / nights
            )
            monthlySummaries.append(avgSummary)
        }
        self.dailySummaries = monthlySummaries
    }
    
    // Helper: Merge overlapping intervals and sum durations (in minutes), by sleep night using anchor hour.
    // Only explicit samples are counted; never fill gaps.
    private func calculateStageMinutes(
        samples: [HKCategorySample],
        stageValue: Int,
        nightStart: Date,
        calendar: Calendar
    ) -> Double {
        // Only use samples for this stage and night.
        // For each sample, split if it crosses night boundaries.
        let anchorHour = sleepAnchorHour
        let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart)!
        let stageSamples = samples.filter { $0.value == stageValue }
        var intervals: [(Date, Date)] = []
        for sample in stageSamples {
            // Split sample if it crosses night boundaries
            let sampleStart = max(sample.startDate, nightStart)
            let sampleEnd = min(sample.endDate, nightEnd)
            if sampleEnd <= sampleStart { continue }
            // Only include if this segment belongs to this night
            // (i.e., sleepNightStart(sampleStart) == nightStart)
            // (samples that start before nightStart but end after: clamp to this night)
            let segNightStart = sleepNightStart(for: sampleStart, calendar: calendar)
            if segNightStart != nightStart {
                continue
            }
            intervals.append((sampleStart, sampleEnd))
        }
        // Sort by start
        let sorted = intervals.sorted { $0.0 < $1.0 }
        // Merge overlapping intervals
        var merged: [(Date, Date)] = []
        for interval in sorted {
            if let last = merged.last, interval.0 <= last.1 {
                // Overlap, merge
                merged[merged.count - 1].1 = max(last.1, interval.1)
            } else {
                merged.append(interval)
            }
        }
        // Sum durations (in minutes)
        let total = merged.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) / 60.0 }
        return total
    }

    // Returns summary for a sleep night (anchor hour to anchor hour next day)
    private func fetchDaySleepSummary(startDate: Date, endDate: Date) async -> DailySleepSummary {
        #if targetEnvironment(macCatalyst)
        return dailySummaryFromEngine(dayStart: startDate, calendar: Calendar.current)
        #else
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return DailySleepSummary(date: startDate, totalMinutes: 0, awakeMinutes: 0, deepMinutes: 0, coreMinutes: 0, remMinutes: 0, unspecifiedAsleepMinutes: 0)
        }
        let calendar = Calendar.current
        // Compute nightStart for this "date" (which is the selection, e.g., Sunday)
        let nightStart = sleepNightStart(for: startDate, calendar: calendar)
        let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart)!
        // Fetch all samples that could overlap with this night
        // Use a wide window to catch cross-midnight samples
        let predicate = HKQuery.predicateForSamples(withStart: calendar.date(byAdding: .hour, value: -12, to: nightStart)!, end: nightEnd, options: .strictStartDate)
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.healthStore.execute(query)
        }
        // Only count samples whose segment for this night is attributed to this night (by anchor rule)
        // Use enum raw values which correspond to actual HealthKit values sent by device
        let asleepUnspecifiedMinutes = calculateStageMinutes(samples: samples, stageValue: SleepStage.unspecifiedAsleep.rawValue, nightStart: nightStart, calendar: calendar)
        let awakeMinutes = calculateStageMinutes(samples: samples, stageValue: SleepStage.awake.rawValue, nightStart: nightStart, calendar: calendar)
        let coreMinutes = calculateStageMinutes(samples: samples, stageValue: SleepStage.core.rawValue, nightStart: nightStart, calendar: calendar)
        let deepMinutes = calculateStageMinutes(samples: samples, stageValue: SleepStage.deep.rawValue, nightStart: nightStart, calendar: calendar)
        let remMinutes = calculateStageMinutes(samples: samples, stageValue: SleepStage.rem.rawValue, nightStart: nightStart, calendar: calendar)
        let totalMinutes = asleepUnspecifiedMinutes + awakeMinutes + coreMinutes + deepMinutes + remMinutes
        return DailySleepSummary(
            date: startDate,
            totalMinutes: totalMinutes,
            awakeMinutes: awakeMinutes,
            deepMinutes: deepMinutes,
            coreMinutes: coreMinutes,
            remMinutes: remMinutes,
            unspecifiedAsleepMinutes: asleepUnspecifiedMinutes
        )
        #endif
    }
    
    private func fetchMonthSleepSummary(startDate: Date, endDate: Date) async -> DailySleepSummary {
        #if targetEnvironment(macCatalyst)
        let calendar = Calendar.current
        var awakeMinutes: Double = 0
        var coreMinutes: Double = 0
        var deepMinutes: Double = 0
        var remMinutes: Double = 0
        var asleepUnspecifiedMinutes: Double = 0
        var night = sleepNightStart(for: startDate, calendar: calendar)
        while night < endDate {
            let s = dailySummaryFromEngineForNightStart(night, calendar: calendar)
            awakeMinutes += s.awakeMinutes
            coreMinutes += s.coreMinutes
            deepMinutes += s.deepMinutes
            remMinutes += s.remMinutes
            asleepUnspecifiedMinutes += s.unspecifiedAsleepMinutes
            night = calendar.date(byAdding: .day, value: 1, to: night)!
        }
        let totalMinutes = asleepUnspecifiedMinutes + awakeMinutes + coreMinutes + deepMinutes + remMinutes
        return DailySleepSummary(
            date: startDate,
            totalMinutes: totalMinutes,
            awakeMinutes: awakeMinutes,
            deepMinutes: deepMinutes,
            coreMinutes: coreMinutes,
            remMinutes: remMinutes,
            unspecifiedAsleepMinutes: asleepUnspecifiedMinutes
        )
        #else
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return DailySleepSummary(date: startDate, totalMinutes: 0, awakeMinutes: 0, deepMinutes: 0, coreMinutes: 0, remMinutes: 0, unspecifiedAsleepMinutes: 0)
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.healthStore.execute(query)
        }

        // Use night-based aggregation for each night in the month
        let calendar = Calendar.current
        var awakeMinutes: Double = 0
        var coreMinutes: Double = 0
        var deepMinutes: Double = 0
        var remMinutes: Double = 0

        var asleepUnspecifiedMinutes: Double = 0
        var night = sleepNightStart(for: startDate, calendar: calendar)
        while night < endDate {
            // Use enum raw values which correspond to actual HealthKit values sent by device
            asleepUnspecifiedMinutes += calculateStageMinutes(samples: samples, stageValue: SleepStage.unspecifiedAsleep.rawValue, nightStart: night, calendar: calendar)
            awakeMinutes += calculateStageMinutes(samples: samples, stageValue: SleepStage.awake.rawValue, nightStart: night, calendar: calendar)
            coreMinutes  += calculateStageMinutes(samples: samples, stageValue: SleepStage.core.rawValue, nightStart: night, calendar: calendar)
            deepMinutes  += calculateStageMinutes(samples: samples, stageValue: SleepStage.deep.rawValue, nightStart: night, calendar: calendar)
            remMinutes   += calculateStageMinutes(samples: samples, stageValue: SleepStage.rem.rawValue, nightStart: night, calendar: calendar)
            night = calendar.date(byAdding: .day, value: 1, to: night)!
        }
        let totalMinutes = asleepUnspecifiedMinutes + awakeMinutes + coreMinutes + deepMinutes + remMinutes

        return DailySleepSummary(
            date: startDate,
            totalMinutes: totalMinutes,
            awakeMinutes: awakeMinutes,
            deepMinutes: deepMinutes,
            coreMinutes: coreMinutes,
            remMinutes: remMinutes,
            unspecifiedAsleepMinutes: asleepUnspecifiedMinutes
        )
        #endif
    }
    
    private func fetchMetricsDuringStage(startTime: Date, endTime: Date) async -> (heartRate: Int?, respiratoryRate: Int?) {
        var heartRates: [Double] = []
        var respiratoryRates: [Double] = []
        
        // Fetch heart rate samples during this stage
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let predicate = HKQuery.predicateForSamples(withStart: startTime, end: endTime, options: .strictStartDate)
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: hrType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, _ in
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                healthStore.healthStore.execute(query)
            }
            heartRates = samples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())) }
        }
        
        // Fetch respiratory rate samples during this stage
        if let rrType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            let predicate = HKQuery.predicateForSamples(withStart: startTime, end: endTime, options: .strictStartDate)
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: rrType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, _ in
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                healthStore.healthStore.execute(query)
            }
            respiratoryRates = samples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())) }
        }
        
        let avgHeartRate = heartRates.isEmpty ? nil : Int(heartRates.reduce(0, +) / Double(heartRates.count))
        let avgRespiratoryRate = respiratoryRates.isEmpty ? nil : Int(respiratoryRates.reduce(0, +) / Double(respiratoryRates.count))
        
        return (avgHeartRate, avgRespiratoryRate)
    }
    
    private func consolidateSleepStages(_ stages: [SleepStageData]) -> [SleepStageData] {
        guard !stages.isEmpty else { return [] }
        /// Same stage samples must touch or overlap; otherwise merging bridged gaps inflated totals (~24h “core”).
        let gapMergeTolerance: TimeInterval = 2 * 60
        let sortedStages = stages.sorted { $0.startTime < $1.startTime }

        var consolidated: [SleepStageData] = []
        var currentStage = sortedStages[0]

        for i in 1..<sortedStages.count {
            let nextStage = sortedStages[i]

            if currentStage.stage == nextStage.stage {
                let gap = nextStage.startTime.timeIntervalSince(currentStage.endTime)
                let overlaps = nextStage.startTime < currentStage.endTime
                if overlaps || gap <= gapMergeTolerance {
                    currentStage = SleepStageData(
                        startTime: min(currentStage.startTime, nextStage.startTime),
                        endTime: max(currentStage.endTime, nextStage.endTime),
                        stage: currentStage.stage,
                        averageHeartRate: currentStage.averageHeartRate,
                        averageRespiratoryRate: currentStage.averageRespiratoryRate
                    )
                } else {
                    consolidated.append(currentStage)
                    currentStage = nextStage
                }
            } else {
                consolidated.append(currentStage)
                currentStage = nextStage
            }
        }

        consolidated.append(currentStage)
        return consolidated
    }

    /// Computes per-stage averages for the current and previous period (week/month/year),
    /// returning an array suitable for SleepSummaryCard.
    /// Returns: [(stage, currentAvgMinutes, prevAvgMinutes, percentOfTotal)]
    func computeStageAveragesForPeriod(summaries: [DailySleepSummary], period: SleepPeriod, referenceDate: Date) async -> [(stage: SleepStage, current: Double, previous: Double, percent: Double)] {
        guard !summaries.isEmpty else { return [] }

        let stages: [SleepStage] = [.awake, .deep, .core, .rem, .unspecifiedAsleep]

        // Current period summaries are passed in
        let currentSummaries = summaries

        // Load previous period independently
        let prevSummaries = await loadPreviousPeriodSummaries(reference: referenceDate, period: period)

        func stageMinutes(_ summary: DailySleepSummary, _ stage: SleepStage) -> Double {
            switch stage {
            case .awake: return summary.awakeMinutes
            case .core:  return summary.coreMinutes
            case .deep:  return summary.deepMinutes
            case .rem:   return summary.remMinutes
            case .unspecifiedAsleep: return summary.unspecifiedAsleepMinutes
            }
        }

        func avg(_ arr: [Double]) -> Double {
            guard !arr.isEmpty else { return 0 }
            return arr.reduce(0,+)/Double(arr.count)
        }

        let totalCurrentMinutes = avg(currentSummaries.map { $0.totalMinutes })

        return stages.map { stage in
            let currAvg = avg(currentSummaries.map { stageMinutes($0, stage) })
            let prevAvg = avg(prevSummaries.map { stageMinutes($0, stage) })
            let percent = totalCurrentMinutes > 0 ? (currAvg / totalCurrentMinutes) * 100 : 0
            return (stage, currAvg, prevAvg, percent)
        }
    }

    /// Fetches summaries for the previous interval relative to a reference date (week/month/year)
    func loadPreviousPeriodSummaries(reference date: Date, period: SleepPeriod) async -> [DailySleepSummary] {
        let calendar = Calendar.current
        var results: [DailySleepSummary] = []

        switch period {
        case .thisWeek:
            // Previous week = 7 days immediately before the reference date (Sunday)
            let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: date)!
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: prevWeekStart)!
                let startOfDay = calendar.startOfDay(for: day)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                let summary = await fetchDaySleepSummary(startDate: startOfDay, endDate: endOfDay)
                results.append(summary)
            }

        case .thisMonth:
            // Previous month relative to the 1st of the selected month
            let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: date)!
            let range = calendar.range(of: .day, in: .month, for: prevMonthStart)!
            let comps = calendar.dateComponents([.year, .month], from: prevMonthStart)
            for day in 1...range.count {
                let d = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: day))!
                let startOfDay = calendar.startOfDay(for: d)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                let summary = await fetchDaySleepSummary(startDate: startOfDay, endDate: endOfDay)
                results.append(summary)
            }

        case .thisYear:
            // Previous calendar year relative to Jan 1 of selected year
            let prevYear = calendar.component(.year, from: date) - 1
            for month in 1...12 {
                let startOfMonth = calendar.date(from: DateComponents(year: prevYear, month: month, day: 1))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                let monthSummary = await fetchMonthSleepSummary(startDate: startOfMonth, endDate: endOfMonth)
                let daysInMonth = Double(calendar.range(of: .day, in: .month, for: startOfMonth)!.count)
                let avgSummary = DailySleepSummary(
                    date: startOfMonth,
                    totalMinutes: monthSummary.totalMinutes / daysInMonth,
                    awakeMinutes: monthSummary.awakeMinutes / daysInMonth,
                    deepMinutes: monthSummary.deepMinutes / daysInMonth,
                    coreMinutes: monthSummary.coreMinutes / daysInMonth,
                    remMinutes: monthSummary.remMinutes / daysInMonth,
                    unspecifiedAsleepMinutes: monthSummary.unspecifiedAsleepMinutes / daysInMonth
                )
                results.append(avgSummary)
            }

        case .lastNight:
            return []
        }

        return results
    }
}

enum SleepPeriod: String, CaseIterable {
    case lastNight = "Night"
    case thisWeek = "Week"
    case thisMonth = "Month"
    case thisYear = "Year"
}

private func sleepWindowLabelForVitals(stages: [SleepStageData]) -> String? {
    guard let first = stages.map(\.startTime).min(),
          let last = stages.map(\.endTime).max() else { return nil }
    let f = DateFormatter()
    f.timeStyle = .short
    return "\(f.string(from: first)) – \(f.string(from: last))"
}

struct SleepView: View {
    @StateObject private var viewModel = SleepViewModel()
    @StateObject private var wakeAlarmStore = WakeUpAlarmStore()
    @State private var animationPhase: Double = 0
    @State private var expandedStage: UUID?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingWakeAlarmView = false
    
    private var availablePeriods: [SleepPeriod] {
        MacCatalystHealthDataPolicy.isActive ? [.lastNight, .thisWeek, .thisMonth] : SleepPeriod.allCases
    }

    private var minimumSelectableDate: Date {
        MacCatalystHealthDataPolicy.isActive ? MacCatalystHealthDataPolicy.minimumAllowedDate : .distantPast
    }


    
    private func periodPickerLabel(period: SleepPeriod) -> String {
        switch period {
        case .lastNight: return "Pick Night"
        case .thisWeek: return "Pick Week"
        case .thisMonth: return "Pick Month"
        case .thisYear: return "Pick Year"
        }
    }
    
    private func validPickerDate(_ date: Date, for period: SleepPeriod) -> Bool {
        let calendar = Calendar.current
        switch period {
        case .lastNight:
            return date <= calendar.startOfDay(for: Date())
        case .thisWeek:
            // Only Sundays
            return calendar.component(.weekday, from: date) == 1 && date <= calendar.startOfDay(for: Date())
        case .thisMonth:
            // Only first of month
            let comps = calendar.dateComponents([.day], from: date)
            return comps.day == 1 && date <= calendar.startOfDay(for: Date())
        case .thisYear:
            // Only Jan 1
            let comps = calendar.dateComponents([.month, .day], from: date)
            return comps.month == 1 && comps.day == 1 && date <= calendar.startOfDay(for: Date())
        }
    }
    
    private func defaultDate(for period: SleepPeriod) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch period {
        case .lastNight:
            return max(today, minimumSelectableDate)
        case .thisWeek:
            // Most recent Sunday on or before today
            let currentWeekday = calendar.component(.weekday, from: today)
            let daysBack = currentWeekday == 1 ? 0 : (currentWeekday - 1)
            return max(calendar.date(byAdding: .day, value: -daysBack, to: today)!, minimumSelectableDate)
        case .thisMonth:
            return max(calendar.date(from: calendar.dateComponents([.year, .month], from: today))!, minimumSelectableDate)
        case .thisYear:
            return max(calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1))!, minimumSelectableDate)
        }
    }
    
    private func nextPeriodComponent() -> Calendar.Component {
        switch viewModel.selectedPeriod {
        case .lastNight:
            return .day
        case .thisWeek:
            return .weekOfYear
        case .thisMonth:
            return .month
        case .thisYear:
            return .year
        }
    }
    
    private func isValidDate(_ date: Date, for period: SleepPeriod) -> Bool {
        let calendar = Calendar.current
        guard date >= minimumSelectableDate else { return false }
        switch period {
        case .lastNight:
            return date <= calendar.startOfDay(for: Date())
        case .thisWeek:
            // Only Sundays and must be before or equal to this week's Sunday
            let thisSunday = calendar.nextDate(after: calendar.startOfDay(for: Date()), matching: DateComponents(weekday: 1), matchingPolicy: .previousTimePreservingSmallerComponents) ?? calendar.startOfDay(for: Date())
            return calendar.component(.weekday, from: date) == 1 && date <= thisSunday
        case .thisMonth:
            // Only first of month and must be before or equal to this month
            let today = calendar.startOfDay(for: Date())
            let thisMonthFirst = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            let comps = calendar.dateComponents([.day], from: date)
            return comps.day == 1 && date <= thisMonthFirst
        case .thisYear:
            // Only Jan 1 and must be before or equal to this year
            let today = calendar.startOfDay(for: Date())
            let thisYearFirst = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1))!
            let comps = calendar.dateComponents([.month, .day], from: date)
            return comps.month == 1 && comps.day == 1 && date <= thisYearFirst
        }
    }
    
    private var calendar: Calendar {
        Calendar.current
    }
    
    private func selectPeriod(_ period: SleepPeriod) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        viewModel.selectedPeriod = period
        let newDate = defaultDate(for: period)
        selectedDate = newDate
        Task { await viewModel.loadSleepData(for: newDate) }
    }
    
    private func stepSelectedDate(by value: Int) {
        let newDate = calendar.date(byAdding: nextPeriodComponent(), value: value, to: selectedDate) ?? selectedDate
        guard isValidDate(newDate, for: viewModel.selectedPeriod) else { return }
        selectedDate = newDate
        Task { await viewModel.loadSleepData(for: newDate) }
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    private func jumpToToday() {
        let newDate = defaultDate(for: viewModel.selectedPeriod)
        selectedDate = newDate
        Task { await viewModel.loadSleepData(for: newDate) }
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    @ViewBuilder
    private var sleepPeriodFilterRow: some View {
        HStack(spacing: 12) {
            ForEach(availablePeriods, id: \.self) { period in
                Button {
                    selectPeriod(period)
                } label: {
                    sleepPeriodChip(for: period)
                }
                .buttonStyle(.plain)
                .catalystDesktopFocusable()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func sleepPeriodChip(for period: SleepPeriod) -> some View {
        let selected = viewModel.selectedPeriod == period
        Text(period.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(selected ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(selected ? Color.blue.opacity(0.7) : Color.clear)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var catalystSleepNotice: some View {
        if MacCatalystHealthDataPolicy.isActive {
            Text(MacCatalystHealthDataPolicy.historyNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var sleepPeriodBody: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(.white)
                .padding()
        } else if viewModel.selectedPeriod == .lastNight {
            VStack(spacing: 16) {
                SleepStagesDropdownCard(stages: viewModel.sleepData)
                SleepQualityCard(stages: viewModel.sleepData)
                HeartRateDipCard(summary: viewModel.heartRateDip)
                SleepBedtimeConsistencyCard(nights: viewModel.bedtimeConsistency)
                OvernightVitalsNormalityCard(
                    metrics: viewModel.overnightVitals,
                    sleepWindowLabel: sleepWindowLabelForVitals(stages: viewModel.sleepData)
                )
            }
            .padding(.horizontal)
        } else {
            VStack(spacing: 16) {
                ForEach(viewModel.dailySummaries) { summary in
                    SleepBarChart(summary: summary, period: viewModel.selectedPeriod)
                }
                SleepSummaryCard(summaries: viewModel.dailySummaries, period: viewModel.selectedPeriod)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var sleepScrollColumn: some View {
        VStack(spacing: 24) {
            sleepPeriodFilterRow
            catalystSleepNotice
            SleepDatePopupPicker(
                selectedPeriod: viewModel.selectedPeriod,
                earliestSleepDate: viewModel.earliestSleepDate,
                selectedDate: $selectedDate,
                onDateChange: { newDate in
                    selectedDate = newDate
                    Task { await viewModel.loadSleepData(for: newDate) }
                }
            )
            sleepPeriodBody
        }
        .padding(.vertical, 20)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dreamy sleep background
                GradientBackgrounds().spiritGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
                    .ignoresSafeArea()
                
                ScrollView {
                    sleepScrollColumn
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: {
                        jumpToToday()
                    }) {
                        Text("Today")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        stepSelectedDate(by: -1)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.body)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        stepSelectedDate(by: 1)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.body)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showingWakeAlarmView = true
                    }) {
                        Image(systemName: "alarm")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Wake-up alarms")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlToday)) { _ in
                jumpToToday()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlPrevious)) { _ in
                stepSelectedDate(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlNext)) { _ in
                stepSelectedDate(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter1)) { _ in
                selectPeriod(.lastNight)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter2)) { _ in
                selectPeriod(.thisWeek)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter3)) { _ in
                selectPeriod(.thisMonth)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter4)) { _ in
                if availablePeriods.contains(.thisYear) {
                    selectPeriod(.thisYear)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlSleepWakeAlarms)) { _ in
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showingWakeAlarmView = true
            }
        }
        .task {
            if !availablePeriods.contains(viewModel.selectedPeriod) {
                viewModel.selectedPeriod = availablePeriods.first ?? .lastNight
            }
            let defaultD = defaultDate(for: viewModel.selectedPeriod)
            selectedDate = defaultD
            await viewModel.loadSleepData(for: defaultD)
        }
        .fullScreenCover(isPresented: $showingWakeAlarmView) {
            WakeUpAlarmView(store: wakeAlarmStore)
        }
        .environmentObject(viewModel)
    }
}

private struct WakeAlarmDaySetting: Identifiable, Codable, Hashable, Sendable {
    let weekday: Int
    var isEnabled: Bool
    var minutesFromMidnight: Int

    var id: Int { weekday }
}

private struct WakeAlarmPreferences: Codable, Sendable {
    var weeklyDays: [WakeAlarmDaySetting]
    var selectedWeekday: Int
    var tomorrowOnlyEnabled: Bool
    var tomorrowAlarmDate: Date
    var windDownLeadMinutes: Double
    var scheduledAlarmIDs: [String]

    static func `default`() -> WakeAlarmPreferences {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let baseMinutes = 7 * 60
        return WakeAlarmPreferences(
            weeklyDays: [
                WakeAlarmDaySetting(weekday: 2, isEnabled: true, minutesFromMidnight: baseMinutes),
                WakeAlarmDaySetting(weekday: 3, isEnabled: true, minutesFromMidnight: baseMinutes),
                WakeAlarmDaySetting(weekday: 4, isEnabled: true, minutesFromMidnight: baseMinutes),
                WakeAlarmDaySetting(weekday: 5, isEnabled: true, minutesFromMidnight: baseMinutes),
                WakeAlarmDaySetting(weekday: 6, isEnabled: true, minutesFromMidnight: baseMinutes),
                WakeAlarmDaySetting(weekday: 7, isEnabled: false, minutesFromMidnight: 8 * 60),
                WakeAlarmDaySetting(weekday: 1, isEnabled: false, minutesFromMidnight: 8 * 60)
            ],
            selectedWeekday: 2,
            tomorrowOnlyEnabled: false,
            tomorrowAlarmDate: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
            windDownLeadMinutes: 60,
            scheduledAlarmIDs: []
        )
    }
}

private struct WakeAlarmScheduleSummary {
    let title: String
    let detail: String
}

@MainActor
private final class WakeUpAlarmStore: ObservableObject {
    @Published var weeklyDays: [WakeAlarmDaySetting] = []
    @Published var selectedWeekday: Int = 2
    @Published var tomorrowOnlyEnabled = false
    @Published var tomorrowAlarmDate = Date()
    @Published var windDownLeadMinutes: Double = 60
    @Published var statusText = "No wake alarms scheduled yet"
    @Published var authorizationText = "Schedule a system wake alarm that breaks through silent mode."
    @Published var isScheduling = false

    private let storageKey = "sleep.wakeAlarm.preferences.v2"
    private let defaults = UserDefaults.standard
    private let scheduler = WakeUpSystemAlarmScheduler()
    private var scheduledAlarmIDs: [String] = []

    init() {
        load()
    }

    var selectedDayIndex: Int? {
        weeklyDays.firstIndex(where: { $0.weekday == selectedWeekday })
    }

    var selectedDayBinding: Binding<Date> {
        Binding<Date>(
            get: { [weak self] in
                guard let self, let index = self.selectedDayIndex else { return Date() }
                return Self.date(for: self.weeklyDays[index].minutesFromMidnight)
            },
            set: { [weak self] newValue in
                guard let self, let index = self.selectedDayIndex else { return }
                self.weeklyDays[index].minutesFromMidnight = Self.minutesFromMidnight(for: newValue)
                self.persist()
            }
        )
    }

    var enabledWeekdays: [WakeAlarmDaySetting] {
        weeklyDays.filter(\.isEnabled)
    }

    var nextWakeSummary: WakeAlarmScheduleSummary {
        let calendar = Calendar.current
        var upcoming: [(Date, String)] = []

        for day in enabledWeekdays {
            if let nextDate = nextDate(forWeekday: day.weekday, minutesFromMidnight: day.minutesFromMidnight, from: Date()) {
                upcoming.append((nextDate, weekdayTitle(for: day.weekday)))
            }
        }

        if tomorrowOnlyEnabled {
            upcoming.append((tomorrowAlarmDate, "Tomorrow only"))
        }

        guard let earliest = upcoming.sorted(by: { $0.0 < $1.0 }).first else {
            return WakeAlarmScheduleSummary(
                title: "No wake alarm yet",
                detail: "Pick the mornings you want protected, then schedule them as system alarms."
            )
        }

        let bedtime = calendar.date(byAdding: .hour, value: -8, to: earliest.0) ?? earliest.0
        let formatter = DateFormatter()
        formatter.dateStyle = calendar.isDateInTomorrow(earliest.0) ? .medium : .none
        formatter.timeStyle = .short

        return WakeAlarmScheduleSummary(
            title: earliest.0.formatted(date: calendar.isDateInToday(earliest.0) ? .omitted : .abbreviated, time: .shortened),
            detail: "\(earliest.1) wake. Aim to be asleep around \(bedtime.formatted(date: .omitted, time: .shortened))."
        )
    }

    var nextWindDownDate: Date? {
        let calendar = Calendar.current
        let nextAlarmDate: Date?

        var upcoming: [Date] = enabledWeekdays.compactMap {
            nextDate(forWeekday: $0.weekday, minutesFromMidnight: $0.minutesFromMidnight, from: Date())
        }
        if tomorrowOnlyEnabled {
            upcoming.append(tomorrowAlarmDate)
        }
        nextAlarmDate = upcoming.sorted().first

        guard let nextAlarmDate else { return nil }
        let sleepTarget = calendar.date(byAdding: .hour, value: -8, to: nextAlarmDate) ?? nextAlarmDate
        return calendar.date(byAdding: .minute, value: -Int(windDownLeadMinutes.rounded()), to: sleepTarget)
    }

    var consistencyScore: Int {
        let enabled = enabledWeekdays
        guard enabled.count > 1 else { return 100 }
        let average = enabled.map(\.minutesFromMidnight).reduce(0, +) / enabled.count
        let averageDistance = enabled
            .map { abs($0.minutesFromMidnight - average) }
            .reduce(0, +) / enabled.count
        let score = max(58, 100 - Int(Double(averageDistance) / 1.4))
        return min(score, 100)
    }

    var consistencyGuidance: String {
        let enabled = enabledWeekdays
        guard !enabled.isEmpty else {
            return "Start with the mornings you care about most. Two or three anchor wake times are enough to build consistency."
        }
        if consistencyScore >= 90 {
            return "Your wake times are already tightly clustered. Protect the same wind-down window and let your body learn the rhythm."
        }
        if consistencyScore >= 75 {
            return "You are close. Tightening your wake times to within about 30 minutes on most days should make bedtime feel easier."
        }
        return "The biggest win is regularity. Try bringing your earliest and latest wake times closer together before chasing more total sleep."
    }

    var rhythmStartMinutes: Int {
        let nextMinutes = enabledWeekdays.map(\.minutesFromMidnight) + (tomorrowOnlyEnabled ? [Self.minutesFromMidnight(for: tomorrowAlarmDate)] : [])
        let earliestWake = nextMinutes.min() ?? (7 * 60)
        return max(17 * 60, earliestWake - 9 * 60)
    }

    var rhythmWakeMinutes: Int {
        enabledWeekdays.map(\.minutesFromMidnight).min() ?? Self.minutesFromMidnight(for: tomorrowAlarmDate)
    }

    var rhythmWindDownMinutes: Int {
        max(rhythmStartMinutes, rhythmBedtimeMinutes - Int(windDownLeadMinutes.rounded()))
    }

    var rhythmBedtimeMinutes: Int {
        max(rhythmStartMinutes + 30, rhythmWakeMinutes - (8 * 60))
    }

    func toggleDay(_ weekday: Int) {
        guard let index = weeklyDays.firstIndex(where: { $0.weekday == weekday }) else { return }
        selectedWeekday = weekday
        weeklyDays[index].isEnabled.toggle()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        persist()
    }

    func selectDay(_ weekday: Int) {
        selectedWeekday = weekday
        UISelectionFeedbackGenerator().selectionChanged()
        persist()
    }

    func scheduleAlarms() async {
        persist()
        isScheduling = true
        defer { isScheduling = false }

        do {
            let result = try await scheduler.schedule(preferences: currentPreferences())
            scheduledAlarmIDs = result.alarmIDs.map(\.uuidString)
            statusText = result.statusText
            authorizationText = result.authorizationText
            persist()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            authorizationText = error.localizedDescription
            if scheduledAlarmIDs.isEmpty {
                statusText = "Wake alarms are not scheduled"
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func clearScheduledAlarms() async {
        isScheduling = true
        defer { isScheduling = false }

        do {
            try await scheduler.cancel(ids: scheduledAlarmIDs.compactMap(UUID.init(uuidString:)))
            scheduledAlarmIDs = []
            statusText = "Wake alarms cleared"
            authorizationText = "Choose mornings again whenever you want to schedule a new system alarm."
            persist()
        } catch {
            authorizationText = "Couldn't clear every alarm. You can still update them by scheduling again."
        }
    }

    func saveDraft() {
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode(WakeAlarmPreferences.self, from: data) else {
            apply(WakeAlarmPreferences.default())
            persist()
            return
        }
        apply(preferences)
    }

    private func apply(_ preferences: WakeAlarmPreferences) {
        weeklyDays = preferences.weeklyDays.sorted { sortIndex(for: $0.weekday) < sortIndex(for: $1.weekday) }
        selectedWeekday = preferences.selectedWeekday
        tomorrowOnlyEnabled = preferences.tomorrowOnlyEnabled
        tomorrowAlarmDate = preferences.tomorrowAlarmDate
        windDownLeadMinutes = preferences.windDownLeadMinutes
        scheduledAlarmIDs = preferences.scheduledAlarmIDs
        statusText = scheduledAlarmIDs.isEmpty ? "No wake alarms scheduled yet" : "Wake alarms are ready"
    }

    private func persist() {
        let payload = currentPreferences()
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func currentPreferences() -> WakeAlarmPreferences {
        WakeAlarmPreferences(
            weeklyDays: weeklyDays,
            selectedWeekday: selectedWeekday,
            tomorrowOnlyEnabled: tomorrowOnlyEnabled,
            tomorrowAlarmDate: tomorrowAlarmDate,
            windDownLeadMinutes: windDownLeadMinutes,
            scheduledAlarmIDs: scheduledAlarmIDs
        )
    }

    private func nextDate(forWeekday weekday: Int, minutesFromMidnight: Int, from now: Date) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = weekday
        components.hour = minutesFromMidnight / 60
        components.minute = minutesFromMidnight % 60
        components.second = 0
        return calendar.nextDate(after: now.addingTimeInterval(-1), matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
    }

    private func weekdayTitle(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }

    private func sortIndex(for weekday: Int) -> Int {
        let ordered = [2, 3, 4, 5, 6, 7, 1]
        return ordered.firstIndex(of: weekday) ?? weekday
    }

    private static func date(for minutes: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: base) ?? base
    }

    private static func minutesFromMidnight(for date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

private struct WakeUpAlarmView: View {
    @ObservedObject var store: WakeUpAlarmStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.09, blue: 0.16),
                        Color(red: 0.08, green: 0.17, blue: 0.23),
                        Color(red: 0.14, green: 0.19, blue: 0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        WakeAlarmHeroCard(store: store)
                        SleepRhythmCanvas(store: store)
                        WakeAlarmWindDownCard(store: store)
                        WakeAlarmConsistencyCard(store: store)
                        WakeAlarmWeeklyScheduleCard(store: store)
                        WakeAlarmTomorrowCard(store: store)
                        WakeAlarmFooterCard(store: store)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Wake-Up Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.isScheduling {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Button("Set") {
                            Task {
                                await store.scheduleAlarms()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onChange(of: store.weeklyDays) { _, _ in
                store.saveDraft()
            }
            .onChange(of: store.tomorrowOnlyEnabled) { _, _ in
                store.saveDraft()
            }
            .onChange(of: store.tomorrowAlarmDate) { _, _ in
                store.saveDraft()
            }
            .onChange(of: store.windDownLeadMinutes) { _, _ in
                store.saveDraft()
            }
        }
    }
}

private struct WakeAlarmHeroCard: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("System wake alarm", systemImage: "alarm.waves.left.and.right.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(store.nextWakeSummary.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(store.nextWakeSummary.detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))

            HStack(spacing: 10) {
                WakeAlarmPill(text: "Breaks through silent mode", systemImage: "speaker.wave.3.fill")
                if let windDown = store.nextWindDownDate {
                    WakeAlarmPill(
                        text: "Wind down \(windDown.formatted(date: .omitted, time: .shortened))",
                        systemImage: "moon.stars.fill"
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color(red: 0.40, green: 0.62, blue: 0.77).opacity(0.22),
                            Color(red: 0.65, green: 0.82, blue: 0.80).opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

private struct SleepRhythmCanvas: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight's rhythm")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text("A gentle target for easing into sleep and waking at a steadier hour.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            GeometryReader { proxy in
                let width = proxy.size.width
                let trackWidth = max(width - 36, 40)
                let start = CGFloat(store.rhythmStartMinutes)
                let range = CGFloat(max(10 * 60, store.rhythmWakeMinutes - store.rhythmStartMinutes + 120))

                let windDownX = max(18, min(width - 18, 18 + trackWidth * CGFloat(store.rhythmWindDownMinutes - store.rhythmStartMinutes) / range))
                let bedX = max(18, min(width - 18, 18 + trackWidth * CGFloat(store.rhythmBedtimeMinutes - store.rhythmStartMinutes) / range))
                let wakeX = max(18, min(width - 18, 18 + trackWidth * CGFloat(store.rhythmWakeMinutes - store.rhythmStartMinutes) / range))

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 88)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.50, blue: 0.67).opacity(0.45),
                                    Color(red: 0.17, green: 0.25, blue: 0.39).opacity(0.88),
                                    Color(red: 0.74, green: 0.80, blue: 0.79).opacity(0.55)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(24, wakeX - windDownX), height: 32)
                        .position(x: (windDownX + wakeX) / 2, y: 44)

                    WakeRhythmMarker(title: "Wind down", x: windDownX, color: Color(red: 0.69, green: 0.82, blue: 0.82))
                    WakeRhythmMarker(title: "Asleep", x: bedX, color: Color(red: 0.56, green: 0.67, blue: 0.90))
                    WakeRhythmMarker(title: "Wake", x: wakeX, color: Color(red: 0.94, green: 0.86, blue: 0.65))
                }
            }
            .frame(height: 96)
        }
        .modifier(WakeAlarmCardStyle())
    }
}

private struct WakeRhythmMarker: View {
    let title: String
    let x: CGFloat
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2))
            Capsule()
                .fill(color.opacity(0.8))
                .frame(width: 2, height: 36)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .position(x: x, y: 46)
    }
}

private struct WakeAlarmWindDownCard: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wind down")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Give yourself a softer runway into bed. The earlier you start, the easier consistency becomes.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            HStack {
                Text("\(Int(store.windDownLeadMinutes.rounded())) min")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if let windDown = store.nextWindDownDate {
                    Text(windDown.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.74, green: 0.87, blue: 0.85))
                }
            }

            Slider(value: $store.windDownLeadMinutes, in: 15...120, step: 5)
                .tint(Color(red: 0.70, green: 0.84, blue: 0.82))
                .onChange(of: store.windDownLeadMinutes) { _, _ in
                    UISelectionFeedbackGenerator().selectionChanged()
                }
        }
        .modifier(WakeAlarmCardStyle())
    }
}

private struct WakeAlarmConsistencyCard: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep consistency")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(store.consistencyGuidance)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 10)
                        .frame(width: 70, height: 70)
                    Circle()
                        .trim(from: 0, to: CGFloat(store.consistencyScore) / 100)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.67, green: 0.84, blue: 0.82),
                                    Color(red: 0.94, green: 0.88, blue: 0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 70, height: 70)
                    Text("\(store.consistencyScore)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .modifier(WakeAlarmCardStyle())
    }
}

private struct WakeAlarmWeeklyScheduleCard: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly schedule")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Mix different wake times by day, then turn on only the mornings you want protected.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(store.weeklyDays) { day in
                    Button(action: {
                        store.selectDay(day.weekday)
                    }) {
                        WakeAlarmDayCard(
                            day: day,
                            isSelected: store.selectedWeekday == day.weekday,
                            label: shortWeekday(for: day.weekday)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            store.toggleDay(day.weekday)
                        }
                    )
                }
            }

            if store.selectedDayIndex != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { store.selectedDayIndex.map { store.weeklyDays[$0].isEnabled } ?? false },
                        set: { newValue in
                            guard let index = store.selectedDayIndex else { return }
                            store.weeklyDays[index].isEnabled = newValue
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                    )) {
                        Text("Enable \(selectedWeekdayTitle)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .tint(Color(red: 0.73, green: 0.86, blue: 0.84))
                    .catalystDesktopFocusable()

                    DatePicker(
                        "Wake time",
                        selection: store.selectedDayBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .frame(height: 120)
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .modifier(WakeAlarmCardStyle())
    }

    private var selectedWeekdayTitle: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, store.selectedWeekday - 1))
        return symbols[index]
    }

    private func shortWeekday(for weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }
}

private struct WakeAlarmDayCard: View {
    let day: WakeAlarmDaySetting
    let isSelected: Bool
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(day.isEnabled ? Color(red: 0.74, green: 0.87, blue: 0.84) : Color.white.opacity(0.18))
                    .frame(width: 10, height: 10)
            }

            Text(timeLabel(for: day.minutesFromMidnight))
                .font(.title3.weight(.bold))
                .foregroundStyle(day.isEnabled ? .white : .white.opacity(0.52))

            Text(day.isEnabled ? "Active" : "Off")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? Color(red: 0.75, green: 0.88, blue: 0.84) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func timeLabel(for minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let base = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: base) ?? base
        return formatter.string(from: date)
    }
}

private struct WakeAlarmTomorrowCard: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $store.tomorrowOnlyEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tomorrow only")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Use this when you need one earlier start without changing your weekly rhythm.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .tint(Color(red: 0.73, green: 0.86, blue: 0.84))
            .catalystDesktopFocusable()

            if store.tomorrowOnlyEnabled {
                DatePicker(
                    "Tomorrow wake time",
                    selection: $store.tomorrowAlarmDate,
                    in: tomorrowDateRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .accentColor(Color(red: 0.76, green: 0.88, blue: 0.84))
            }
        }
        .modifier(WakeAlarmCardStyle())
    }

    private var tomorrowDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let start = calendar.startOfDay(for: tomorrow)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start...end
    }
}

private struct WakeAlarmFooterCard: View {
    @ObservedObject var store: WakeUpAlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.statusText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(store.authorizationText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 12) {
                Button {
                    Task {
                        await store.scheduleAlarms()
                    }
                } label: {
                    Label("Set wake alarms", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WakeAlarmPrimaryButtonStyle())

                Button {
                    Task {
                        await store.clearScheduledAlarms()
                    }
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WakeAlarmSecondaryButtonStyle())
            }
        }
        .modifier(WakeAlarmCardStyle())
    }
}

private struct WakeAlarmPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.84))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct WakeAlarmCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
    }
}

private struct WakeAlarmPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.07, green: 0.12, blue: 0.18))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.76, green: 0.89, blue: 0.84),
                                Color(red: 0.94, green: 0.88, blue: 0.69)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(configuration.isPressed ? 0.82 : 1)
            )
    }
}

private struct WakeAlarmSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
    }
}

private struct ScheduledWakeAlarmResult {
    let alarmIDs: [UUID]
    let statusText: String
    let authorizationText: String
}

private enum WakeAlarmSchedulerError: LocalizedError {
    case unavailable
    case unauthorized
    case noSchedule

    var errorDescription: String? {
        switch self {
        case .unavailable:
            #if targetEnvironment(macCatalyst)
            return "Wake alarms via AlarmKit are not available on Mac. Schedule alarms on iPhone or iPad."
            #else
            return "AlarmKit needs iOS 26 or later to create a true system alarm from Nutrivance."
            #endif
        case .unauthorized:
            return "Allow Nutrivance to schedule alarms in Settings so wake alarms can break through silent mode."
        case .noSchedule:
            return "Choose at least one weekday or enable the tomorrow-only alarm."
        }
    }
}

@MainActor
private final class WakeUpSystemAlarmScheduler {
    func schedule(preferences: WakeAlarmPreferences) async throws -> ScheduledWakeAlarmResult {
        let enabledWeekdays = preferences.weeklyDays.filter(\.isEnabled)
        guard preferences.tomorrowOnlyEnabled || !enabledWeekdays.isEmpty else {
            throw WakeAlarmSchedulerError.noSchedule
        }

        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            try await cancel(ids: preferences.scheduledAlarmIDs.compactMap(UUID.init(uuidString:)))

            let state = try await manager.requestAuthorization()
            guard state == .authorized else {
                throw WakeAlarmSchedulerError.unauthorized
            }

            var scheduledIDs: [UUID] = []
            let grouped = Dictionary(grouping: enabledWeekdays, by: \.minutesFromMidnight)

            for days in grouped.values.sorted(by: { ($0.first?.minutesFromMidnight ?? 0) < ($1.first?.minutesFromMidnight ?? 0) }) {
                guard let first = days.first else { continue }
                let id = UUID()
                let weekdays = days.compactMap { localeWeekday(for: $0.weekday) }
                let time = Alarm.Schedule.Relative.Time(hour: first.minutesFromMidnight / 60, minute: first.minutesFromMidnight % 60)
                let schedule = Alarm.Schedule.relative(.init(time: time, repeats: .weekly(weekdays)))
                let configuration = AlarmManager.AlarmConfiguration(
                    countdownDuration: nil,
                    schedule: schedule,
                    attributes: attributes(title: "Wake Up", subtitle: weeklySubtitle(for: days)),
                    stopIntent: nil,
                    secondaryIntent: nil,
                    sound: .default
                )
                _ = try await manager.schedule(id: id, configuration: configuration)
                scheduledIDs.append(id)
            }

            if preferences.tomorrowOnlyEnabled {
                let id = UUID()
                let configuration = AlarmManager.AlarmConfiguration(
                    countdownDuration: nil,
                    schedule: .fixed(preferences.tomorrowAlarmDate),
                    attributes: attributes(title: "Tomorrow's Wake Up", subtitle: "One-time morning alarm"),
                    stopIntent: nil,
                    secondaryIntent: nil,
                    sound: .default
                )
                _ = try await manager.schedule(id: id, configuration: configuration)
                scheduledIDs.append(id)
            }

            let summary = buildSummary(from: preferences)
            return ScheduledWakeAlarmResult(
                alarmIDs: scheduledIDs,
                statusText: summary,
                authorizationText: "Wake alarms are scheduled as system alarms and can alert on a paired Apple Watch when it is nearby."
            )
        }
        #endif

        throw WakeAlarmSchedulerError.unavailable
    }

    func cancel(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            for id in ids {
                try? await manager.cancel(id: id)
            }
        }
        #endif
    }

    #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private func attributes(title: String, subtitle: String) -> AlarmAttributes<WakeAlarmMetadata> {
        let stopButton = AlarmButton(
            text: "Dismiss",
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let openButton = AlarmButton(
            text: "Open",
            textColor: .white,
            systemImageName: "arrow.right.circle.fill"
        )
        let alertContent = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )
        return AlarmAttributes(
            presentation: AlarmPresentation(alert: alertContent),
            metadata: WakeAlarmMetadata(subtitle: subtitle),
            tintColor: Color(red: 0.61, green: 0.81, blue: 0.84)
        )
    }

    @available(iOS 26.0, *)
    private func localeWeekday(for weekday: Int) -> Locale.Weekday? {
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
    #endif

    private func weeklySubtitle(for days: [WakeAlarmDaySetting]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let dayLabels = days
            .sorted { $0.weekday < $1.weekday }
            .map { symbols[max(0, min(symbols.count - 1, $0.weekday - 1))] }
            .joined(separator: ", ")
        return "Repeats on \(dayLabels)"
    }

    private func buildSummary(from preferences: WakeAlarmPreferences) -> String {
        let enabledDays = preferences.weeklyDays.filter(\.isEnabled).count
        if preferences.tomorrowOnlyEnabled && enabledDays > 0 {
            return "Weekly wake alarms plus tomorrow's one-time alarm are ready"
        }
        if preferences.tomorrowOnlyEnabled {
            return "Tomorrow's one-time wake alarm is ready"
        }
        return enabledDays == 1 ? "One weekly wake alarm is ready" : "\(enabledDays) weekly wake mornings are ready"
    }
}

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
@available(iOS 26.0, *)
private struct WakeAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
    var subtitle: String
}
#endif

// MARK: - SleepDatePopupPicker
struct SleepDatePopupPicker: View {
    let selectedPeriod: SleepPeriod
    let earliestSleepDate: Date?
    @Binding var selectedDate: Date
    var onDateChange: (Date) -> Void

    private func periodLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedPeriod {
        case .lastNight:
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        case .thisWeek:
            formatter.dateFormat = "'Week of' MMM d, yyyy"
            return formatter.string(from: date)
        case .thisMonth:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        case .thisYear:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        }
    }

    private func validDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let (minDate, maxDate) = periodDateRange(period: selectedPeriod, earliest: earliestSleepDate)
        switch selectedPeriod {
        case .lastNight:
            return date >= minDate && date <= maxDate
        case .thisWeek:
            // Only Sundays
            return calendar.component(.weekday, from: date) == 1 && date >= minDate && date <= maxDate
        case .thisMonth:
            // Only first of month
            let comps = calendar.dateComponents([.day], from: date)
            return comps.day == 1 && date >= minDate && date <= maxDate
        case .thisYear:
            // Only Jan 1
            let comps = calendar.dateComponents([.month, .day], from: date)
            return comps.month == 1 && comps.day == 1 && date >= minDate && date <= maxDate
        }
    }

    private func stepComponent() -> Calendar.Component {
        switch selectedPeriod {
        case .lastNight:
            return .day
        case .thisWeek:
            return .weekOfYear
        case .thisMonth:
            return .month
        case .thisYear:
            return .year
        }
    }

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundColor(.white)
                Text(periodLabel(selectedDate))
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.45)))
            DatePicker(
                "",
                selection: Binding(
                    get: { selectedDate },
                    set: { newDate in
                        // Only allow valid dates for the period
                        if validDate(newDate) {
                            if selectedDate != newDate {
                                onDateChange(newDate)
                            }
                        }
                    }
                ),
                in: {
                    let (min, max) = periodDateRange(period: selectedPeriod, earliest: earliestSleepDate)
                    return min...max
                }(),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: 150)
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct SleepStageRow: View {
    let stage: SleepStageData
    let isExpanded: Bool
    let onTap: () -> Void
    
    @EnvironmentObject private var viewModel: SleepViewModel
    
    // Quality ranges for sleep stages (HR and RR thresholds)
    private func qualityRanges(for stage: SleepStage) -> (hrMin: Int?, hrMax: Int?, rrMin: Int?, rrMax: Int?) {
        switch stage {
        case .awake:
            return (nil, nil, nil, nil)
        case .core:
            return (50, 70, 10, 18)
        case .deep:
            return (nil, 60, 10, 16)
        case .rem:
            return (60, 80, 12, 22)
        case .unspecifiedAsleep:
            return (nil, nil, nil, nil)
        }
    }
    
    // Check if HR is within quality range
    private func isHRInRange(hr: Int, for stage: SleepStage) -> Bool {
        let ranges = qualityRanges(for: stage)
        if let min = ranges.hrMin, let max = ranges.hrMax {
            return hr >= min && hr <= max
        } else if let max = ranges.hrMax {
            return hr < max
        }
        return false
    }
    
    // Check if RR is within quality range
    private func isRRInRange(rr: Int, for stage: SleepStage) -> Bool {
        let ranges = qualityRanges(for: stage)
        if let min = ranges.rrMin, let max = ranges.rrMax {
            return rr >= min && rr <= max
        }
        return false
    }
    
    private var glowOpacity: Double {
        guard let hr = stage.averageHeartRate, let rr = stage.averageRespiratoryRate else { return 0.0 }
        
        switch stage.stage {
        case .awake:
            // Slightly more glow for quality awake periods
            return stage.duration / 300 > 1 ? 1.0 : 0.0
        case .core:
            // Stronger glow for quality, restorative core sessions
            return (stage.duration > Double(averageDuration(for: .core) * 60) && isHRInRange(hr: hr, for: .core) && isRRInRange(rr: rr, for: .core)) ? 1.0 : 0.0
        case .deep:
            // Strongest glow for quality, restorative deep sessions
            return (stage.duration > Double(averageDuration(for: .deep) * 60) && isHRInRange(hr: hr, for: .deep) && isRRInRange(rr: rr, for: .deep)) ? 1.0 : 0.0
        case .rem:
            // Stronger glow for quality, healthy REM sessions
            return (stage.duration > Double(averageDuration(for: .rem) * 60) && isHRInRange(hr: hr, for: .rem) && isRRInRange(rr: rr, for: .rem)) ? 1.0 : 0.0
        case .unspecifiedAsleep:
            // Moderate glow for unspecified asleep
            return 0.75
        }
    }
    
    // MARK: - Sleep Insights
    
    private func averageDuration(for stageType: SleepStage) -> Int {
        // Calculate baseline from 7 days relative to the current stage's date, not from today
        // This ensures old data is compared against its own historical context
        let oneWeekBeforeStage = Calendar.current.date(byAdding: .day, value: -7, to: stage.startTime) ?? Date.distantPast
        let recentStages = viewModel.sleepData.filter { $0.startTime >= oneWeekBeforeStage && $0.startTime <= stage.startTime }
        
        // Collect all segments of the requested stage type
        let stageSegments = recentStages.filter { $0.stage == stageType }
        
        guard !stageSegments.isEmpty else { return 0 } // no data
        
        // Compute the average duration per segment in minutes
        let durations = stageSegments.map { $0.duration / 60 }
        let avgMinutes = durations.reduce(0, +) / Double(durations.count)
        
        return Int(avgMinutes)
    }
    
    private func dynamicStageInsight() -> String {
        let minutes = Int(stage.duration / 60)
        let avgPerSession = averageDuration(for: stage.stage)
        let comparison = "\(minutes) min vs avg \(avgPerSession) min per session"
        
        // Determine if the session is short or long compared to past 7-day average
        let isShort = minutes < Int(Double(avgPerSession) * 0.5)
        let isLong = minutes > Int(Double(avgPerSession) * 1.5)
        
        // Healthy HR/RR ranges for highlighting
        let hr = stage.averageHeartRate ?? 0
        let rr = stage.averageRespiratoryRate ?? 0
        
        var insight = ""
        
        switch stage.stage {
        case .rem:
            insight = "REM sleep is when your brain dances through dreams. This session lasted \(comparison)."
            if isShort {
                insight += " A short trip through REM—may not have contributed much to memory processing this time."
            } else if isLong && isHRInRange(hr: hr, for: .rem) && isRRInRange(rr: rr, for: .rem) {
                insight += " Wow, this was a long, healthy REM session—time to store up what you learned! I guess some great dreams were happening."
            } else {
                insight += " Solid REM, your brain got some valuable processing done."
            }
        case .deep:
            insight = "Deep sleep is your body's repair shop. This session lasted \(comparison)."
            if isShort {
                insight += " A brief visit—your body may have done a little repair, but not a full restorative cycle."
            } else if isLong && isHRInRange(hr: hr, for: .deep) && isRRInRange(rr: rr, for: .deep) {
                insight += " Excellent! A long deep sleep session—muscles and immune system probably feeling recharged."
            } else {
                insight += " Good deep sleep—your body got some well-deserved repair time."
            }
        case .core:
            insight = "Core sleep keeps your cycles steady and energy balanced. This session lasted \(comparison)."
            if isShort {
                insight += " A short core stretch—just a little stabilizing action."
            } else if isLong && isHRInRange(hr: hr, for: .core) && isRRInRange(rr: rr, for: .core) {
                insight += " Strong core session—your sleep rhythm is looking happy tonight."
            } else {
                insight += " Nice core session—your body is keeping a steady pace."
            }
        case .awake:
            insight = "Awake periods happen naturally. This session lasted \(comparison)."
            if isShort {
                insight += " Brief interruptions—nothing to worry about, just a blink in your night."
            } else if isLong {
                insight += " Longer awake session—sometimes the mind takes a little stroll, but all is fine."
            }
        case .unspecifiedAsleep:
            insight = "Unspecified asleep time recorded by your device. This session lasted \(comparison)."
            if isLong {
                insight += " A longer recording—contributes to your total sleep duration."
            } else {
                insight += " Brief unspecified asleep time—still counts toward your total sleep."
            }
        }
        
        return insight
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            stageHeaderButton
            if isExpanded {
                expandedContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(stage.stage.color.opacity(glowOpacity * 0.1))
                .blur(radius: 12)
                .padding(-8)
        )
    }
    
    private var stageHeaderButton: some View {
        Button(action: {
            // Haptic feedback - different sensations for opening vs closing
            if isExpanded {
                // Closing: lighter, snappy feel
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            } else {
                // Opening: medium-heavy, satisfying reveal feel
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }
            onTap()
        }) {
            HStack(spacing: 12) {
                stageInfoColumn
                Spacer()
                stageIndicator
            }
            .padding(16)
            .background(stageHeaderBackground)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(stage.stage.color.opacity(0.4), lineWidth: 1)
        )
    }
    
    private var stageInfoColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stage.stage.label)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(stage.formattedTime)
                .font(.caption)
                .foregroundColor(.gray)
            
            let duration = Int(stage.duration / 60)
            Text("\(duration) min")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
    
    private var stageIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stage.stage.color)
                .frame(width: 12, height: 12)
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
    }
    
    private var stageHeaderBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(stage.stage.color.opacity(glowOpacity * 0.2))
                    .blur(radius: 8)
            )
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.2))
            
            stageDescriptionSection
            
            // --- Dynamic Insight Section ---
            Text(dynamicStageInsight())
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(nil)
            // --- End Dynamic Insight Section ---
            
            if let hr = stage.averageHeartRate {
                heartRateCard(hr: hr)
            }
            
            if let rr = stage.averageRespiratoryRate {
                respiratoryRateCard(rr: rr)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .background(.ultraThinMaterial)
        .background(
            ZStack {
                // Multi-layered glow for enhanced effect
                RoundedRectangle(cornerRadius: 12)
                    .fill(stage.stage.color.opacity(glowOpacity * 0.25))
                    .blur(radius: 16)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(stage.stage.color.opacity(glowOpacity * 0.15))
                    .blur(radius: 8)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(stage.stage.color.opacity(glowOpacity * 0.1))
                    .blur(radius: 4)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.scale.combined(with: .opacity))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(stage.stage.color.opacity(glowOpacity * 0.05))
        )
    }
    
    private var stageDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About \(stage.stage.label)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(stage.stage.description)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(nil)
        }
    }
    
    private func heartRateCard(hr: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                Text("Avg Heart Rate: \(hr) bpm")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            Text(hrAnalysis(for: stage.stage, hr: hr))
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(glowOpacity * 0.15))
                        .blur(radius: 6)
                )
        )
    }
    
    private func respiratoryRateCard(rr: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .foregroundColor(.cyan)
                Text("Avg Respiratory Rate: \(rr) breaths/min")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            Text(rrAnalysis(for: stage.stage, rr: rr))
                .font(.caption2)
                .foregroundColor(.cyan)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cyan.opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cyan.opacity(glowOpacity * 0.15))
                        .blur(radius: 6)
                )
        )
    }
    
    private func hrAnalysis(for stage: SleepStage, hr: Int) -> String {
        let ranges = qualityRanges(for: stage)
        let inRange = isHRInRange(hr: hr, for: stage)
        
        switch stage {
        case .awake:
            return hr > 80 ? "Elevated HR while awake—may indicate brief arousal." : "Normal HR during wake time."
        case .core:
            let (_, hrMax, _, _) = ranges
            if hr < 50 {
                return "Very low HR—good cardiovascular rest during core sleep."
            } else if hr >= 50 && hr <= hrMax! {
                return "Healthy HR during core sleep (within quality range)."
            } else {
                return "Slightly elevated HR during core sleep."
            }
        case .deep:
            let (_, hrMax, _, _) = ranges
            if hr < 50 {
                return "Excellent—very low HR during restorative deep sleep."
            } else if hr < hrMax! {
                return "Good—HR is resting during deep sleep (within quality range)."
            } else {
                return "Slightly elevated HR during deep sleep."
            }
        case .rem:
            let (hrMin, hrMax, _, _) = ranges
            if hr >= hrMin! && hr <= hrMax! {
                return "REM sleep HR in optimal quality range—supports healthy dreaming."
            } else if hr > 70 {
                return "REM sleep HR elevated—active dreaming with higher heart rate."
            } else {
                return "Moderate HR during REM sleep."
            }
        case .unspecifiedAsleep:
            return "HR during generic asleep time recorded by device."
        }
    }
    
    private func rrAnalysis(for stage: SleepStage, rr: Int) -> String {
        let ranges = qualityRanges(for: stage)
        let inRange = isRRInRange(rr: rr, for: stage)
        
        switch stage {
        case .awake:
            return rr > 20 ? "Higher breathing rate while awake." : "Normal breathing rate while awake."
        case .core:
            let (_, _, rrMin, rrMax) = ranges
            if rr < 12 {
                return "Slow, steady breathing during core sleep—very restful."
            } else if rr >= rrMin! && rr <= rrMax! {
                return "Good—regular breathing during core sleep (within quality range)."
            } else {
                return "Slightly elevated breathing during core sleep."
            }
        case .deep:
            let (_, _, rrMin, rrMax) = ranges
            if rr < 12 {
                return "Excellent—slow, deep breathing during restorative sleep."
            } else if rr >= rrMin! && rr <= rrMax! {
                return "Good—breathing within quality range during deep sleep."
            } else {
                return "Normal breathing pattern during deep sleep."
            }
        case .rem:
            let (_, _, rrMin, rrMax) = ranges
            if rr >= rrMin! && rr <= rrMax! {
                return "REM sleep breathing in optimal quality range—supports memory consolidation."
            } else if rr > 14 {
                return "REM sleep typically has variable, slightly elevated breathing."
            } else {
                return "Regular breathing during REM sleep."
            }
        case .unspecifiedAsleep:
            return "Breathing rate during generic asleep time recorded by device."
        }
    }
}

struct SleepBarChart: View {
    let summary: DailySleepSummary
    let period: SleepPeriod

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = period == .thisYear ? "MMM" : "MMM d"
        return formatter.string(from: summary.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateString)
                    .font(.caption)
                    .foregroundColor(.gray)

                Spacer()

                // Total including awake
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatMinutesToHoursMinutes(summary.totalMinutes))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatMinutesToHoursMinutes(summary.totalMinutes - summary.awakeMinutes))
                            .font(.caption2)
                            .foregroundColor(.gray)
                        
                        if summary.unspecifiedAsleepMinutes > 0 {
                            Text("(+\(formatMinutesToHoursMinutes(summary.unspecifiedAsleepMinutes)) unspecified)")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    }
                }
            }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    if summary.awakePercentage > 0 {
                        SleepStage.awake.color
                            .frame(width: geo.size.width * summary.awakePercentage / 100)
                    }
                    if summary.deepPercentage > 0 {
                        SleepStage.deep.color
                            .frame(width: geo.size.width * summary.deepPercentage / 100)
                    }
                    if summary.corePercentage > 0 {
                        SleepStage.core.color
                            .frame(width: geo.size.width * summary.corePercentage / 100)
                    }
                    if summary.remPercentage > 0 {
                        SleepStage.rem.color
                            .frame(width: geo.size.width * summary.remPercentage / 100)
                    }
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))

            // Legend
            HStack(spacing: 16) {
                if summary.awakePercentage > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(SleepStage.awake.color).frame(width: 8, height: 8)
                        Text(String(format: "Awake: %.0f%%", summary.awakePercentage))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }

                if summary.deepPercentage > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(SleepStage.deep.color).frame(width: 8, height: 8)
                        Text(String(format: "Deep: %.0f%%", summary.deepPercentage))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }

                if summary.corePercentage > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(SleepStage.core.color).frame(width: 8, height: 8)
                        Text(String(format: "Core: %.0f%%", summary.corePercentage))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }

                if summary.remPercentage > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(SleepStage.rem.color).frame(width: 8, height: 8)
                        Text(String(format: "REM: %.0f%%", summary.remPercentage))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }
}

struct SleepQualityCard: View {
    let stages: [SleepStageData]
    @EnvironmentObject private var viewModel: SleepViewModel

    @State private var appleIntelligenceAnalysis = ""
    @State private var isAIAnalysisLoading = false

    private var ruleBasedLine: String {
        ruleBasedSleepQualitySummary(stages: stages, last7AvgSleepHours: viewModel.last7AvgSleepHours)
    }

    private var aiTaskIdentity: String {
        let dip = viewModel.heartRateDip.map { "\(Int($0.dipPercent ?? -1))_\($0.band.rawValue)_\($0.nocturnalSampleCount)" } ?? "nodip"
        let bc = viewModel.bedtimeConsistency.count
        let vitCount = viewModel.overnightVitals.count
        let vitOut = viewModel.overnightVitals.filter(\.isOutlier).count
        return "\(stages.count)_\(viewModel.last7AvgSleepHours ?? 0)_\(stages.first?.startTime.timeIntervalSince1970 ?? 0)_\(dip)_\(bc)_\(vitCount)_\(vitOut)"
    }

    private func sleepQualityFactsForPrompt() -> String {
        let totalDuration = stages.reduce(0) { $0 + $1.duration }
        let awakeMin = stages.filter { $0.stage == .awake }.reduce(0) { $0 + $1.duration } / 60.0
        let actualSleepMin = max(0, totalDuration / 60.0 - awakeMin)
        let remMin = stages.filter { $0.stage == .rem }.reduce(0) { $0 + $1.duration } / 60.0
        let deepMin = stages.filter { $0.stage == .deep }.reduce(0) { $0 + $1.duration } / 60.0
        let coreMin = stages.filter { $0.stage == .core }.reduce(0) { $0 + $1.duration } / 60.0
        let unspecifiedMin = stages.filter { $0.stage == .unspecifiedAsleep }.reduce(0) { $0 + $1.duration } / 60.0
        let firstStage = stages.first?.stage.label ?? "—"
        let lastStage = stages.last?.stage.label ?? "—"
        let sessionCounts: [String] = [SleepStage.core, .deep, .rem, .awake].map { st in
            let n = stages.filter { $0.stage == st }.count
            return "\(st.label) segments: \(n)"
        }
        let fmtT: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
        let sleepWindow: String
        if let s = stages.map(\.startTime).min(), let e = stages.map(\.endTime).max() {
            sleepWindow = "Recorded sleep window about \(fmtT(s)) to \(fmtT(e))."
        } else {
            sleepWindow = "Sleep window unknown."
        }
        var lines: [String] = [
            sleepWindow,
            "Actual sleep about \(formatMinutesToHoursMinutes(actualSleepMin)) (total stage time minus awake segments).",
            "Stage minutes (approx): core \(Int(coreMin)), deep \(Int(deepMin)), REM \(Int(remMin)), awake \(Int(awakeMin)), unspecified asleep \(Int(unspecifiedMin)).",
            "First recorded stage: \(firstStage). Last recorded stage: \(lastStage).",
            sessionCounts.joined(separator: "; ") + "."
        ]
        if let a7 = viewModel.last7AvgSleepHours {
            let diffHr = (actualSleepMin / 60.0) - a7
            lines.append("7-day average actual sleep: \(formatMinutesToHoursMinutes(a7 * 60)) per night; last night about \(diffHr >= 0 ? "+" : "")\(String(format: "%.1f", diffHr)) h vs that average.")
        }
        for st in [SleepStage.core, .deep, .rem, .awake] {
            let seg = stages.filter { $0.stage == st }
            let hrs = seg.compactMap { $0.averageHeartRate }
            let rrs = seg.compactMap { $0.averageRespiratoryRate }
            if !hrs.isEmpty || !rrs.isEmpty {
                var bit = "\(st.label) physiology:"
                if !hrs.isEmpty {
                    let a = Int(Double(hrs.reduce(0, +)) / Double(hrs.count))
                    bit += " avg HR ~\(a) bpm across segments."
                }
                if !rrs.isEmpty {
                    let a = Int(Double(rrs.reduce(0, +)) / Double(rrs.count))
                    bit += " avg respiratory ~\(a)/min across segments."
                }
                lines.append(bit)
            }
        }
        if let dip = viewModel.heartRateDip {
            if let d = dip.daytimeAvgBpm, let n = dip.nocturnalAvgBpm, let pct = dip.dipPercent {
                lines.append("Heart rate dip: daytime living avg \(Int(d)) bpm (\(dip.daytimeSampleCount) samples), asleep (core/deep/REM) avg \(Int(n)) bpm (\(dip.nocturnalSampleCount) samples), dip \(String(format: "%.1f", pct))%, classification: \(dip.band.rawValue).")
            } else {
                lines.append("Heart rate dip: insufficient samples (day \(dip.daytimeSampleCount), night \(dip.nocturnalSampleCount)); band \(dip.band.rawValue).")
            }
        } else {
            lines.append("Heart rate dip: not computed yet.")
        }
        let bc = viewModel.bedtimeConsistency
        if bc.count >= 2 {
            let devs = bc.map(\.deviationMinutes)
            if let mn = devs.min(), let mx = devs.max() {
                lines.append("Bedtime consistency (first asleep core/deep/REM vs 6pm anchor): \(bc.count) nights; deviation from your mean ranges about \(Int(mn)) to \(Int(mx)) minutes.")
            }
            if let last = bc.max(by: { $0.nightStart < $1.nightStart }) {
                lines.append("Most recent night in series: first asleep about \(fmtT(last.firstAsleepTime)).")
            }
        } else if bc.count == 1, let only = bc.first {
            lines.append("Bedtime consistency: only one night with onset data (\(fmtT(only.firstAsleepTime))); need more nights for a trend.")
        } else {
            lines.append("Bedtime consistency: no multi-night onset data.")
        }
        let vit = viewModel.overnightVitals
        if vit.isEmpty {
            lines.append("Overnight vitals normality: no metric bundle (wear watch overnight for HR, RR, O₂, wrist temp).")
        } else {
            let out = vit.filter(\.isOutlier)
            lines.append("Overnight vitals vs recent asleep nights: \(vit.count) metrics; \(out.count) flagged outside typical range for you.")
            for m in vit {
                lines.append("— \(m.title): \(m.valueLabel); typical range for you: \(m.isOutlier ? "outside" : "inside").")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func runSleepQualityAppleIntelligence() async {
        guard sleepViewDeviceSupportsAppleIntelligence(), !stages.isEmpty else {
            await MainActor.run { appleIntelligenceAnalysis = "" }
            return
        }
        await MainActor.run { isAIAnalysisLoading = true }
        defer { Task { @MainActor in isAIAnalysisLoading = false } }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            guard model.isAvailable else { return }
            do {
                let session = LanguageModelSession(model: model)
                let prompt = """
                You write a detailed sleep quality summary in the tone of Apple Watch Overnight / Vitals: calm, observational, second person "you", not alarmist. This is wellness copy, not a diagnosis.

                Output plain text only:
                — Line 1: one concise headline (max 12 words).
                — Then 5–8 sentences that naturally weave together, when the facts support it: total sleep vs the 7-day average; stage balance (core, deep, REM, awake) and segment counts; sleep timing window; stage-specific HR/respiratory notes if given; heart rate dipping (day vs asleep HR and classification) if given; bedtime consistency / first-asleep stability across recent nights if given; overnight vitals normality and any outliers if given. If a fact block says "not computed", "insufficient", or "no data", do not invent numbers—briefly note that that signal was missing.
                No bullets, no numbering, no emoji, no markdown, no section headers.

                Facts (only source of truth; each line may be used or skipped if irrelevant):
                \(sleepQualityFactsForPrompt())
                """
                let text = try await session.respond(to: prompt).content
                await MainActor.run {
                    appleIntelligenceAnalysis = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                await MainActor.run { appleIntelligenceAnalysis = "" }
            }
        }
        #endif
    }

    private var nextDayReadinessAnalysis: String {
        let calendar = Calendar.current
        let todayNight = sleepNightStart(for: Date(), calendar: calendar)

        // --- Build the last 7 sleep nights window ---
        let last7Nights: Set<Date> = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayNight)
        }.reduce(into: Set<Date>()) { $0.insert($1) }

        // --- 1) Get only deep sessions in the last 7 sleep nights ---
        let recentDeepSamples = stages.filter {
            $0.stage == .deep && last7Nights.contains(
                sleepNightStart(for: $0.startTime, calendar: calendar)
            )
        }

        // --- 2) Compute average deep-session length (matches your card logic) ---
        let deepDurations = recentDeepSamples.map { $0.duration / 60.0 } // minutes per session
        let avgDeepMinutes = deepDurations.isEmpty
            ? 0
            : deepDurations.reduce(0, +) / Double(deepDurations.count)

        // Threshold for a "long" deep session = 1.5 × recent average (same idea as statsPerStage)
        let longThreshold = avgDeepMinutes * 1.5

        // --- 3) Count long deep sessions using THIS threshold (not a fixed 20 min) ---
        let longDeepSessions = recentDeepSamples.filter {
            ($0.duration / 60.0) >= longThreshold && longThreshold > 0
        }

        // --- 4) Total deep minutes in the window ---
        let totalDeepMinutes = recentDeepSamples
            .map { $0.duration / 60.0 }
            .reduce(0, +)

        // --- 5) Average HR for deep sessions ---
        let deepHRValues = recentDeepSamples.compactMap { $0.averageHeartRate }
        let avgDeepHR = deepHRValues.isEmpty
            ? 0
            : deepHRValues.reduce(0, +) / deepHRValues.count

        // --- 6) REM stats (unchanged) ---
        let remSessions = stages.filter { $0.stage == .rem }
        let remHRValues = remSessions.compactMap { $0.averageHeartRate }
        let avgRemHR = remHRValues.isEmpty
            ? 0
            : remHRValues.reduce(0, +) / remHRValues.count

        // --- Build the analysis text ---
        var analysis = "Next-Day Readiness:\n"

        // Physical recovery uses the SAME notion of "long" as your dropdown card
        if totalDeepMinutes >= 30 {
            analysis += "Physical recovery: \(longDeepSessions.count) long deep sleep session(s) "
            analysis += "(threshold ≈ \(Int(longThreshold)) min) with average HR \(avgDeepHR) bpm—supports muscle and immune recovery.\n"
        } else {
            analysis += "Physical recovery: limited deep sleep detected; consider improving sleep hygiene.\n"
        }

        // Cognitive readiness
        if !remSessions.isEmpty {
            analysis += "Cognitive readiness: \(remSessions.count) REM session(s) with average HR \(avgRemHR) bpm—supports memory consolidation and emotional processing.\n"
        } else {
            analysis += "Cognitive readiness: minimal REM sleep; learning and memory may be suboptimal.\n"
        }

        // Emotional balance
        let balanced = (remSessions.count >= 2 && !longDeepSessions.isEmpty)
        analysis += "Emotional balance: assessed based on REM and deep sleep patterns; your sleep appears "
            + (balanced ? "balanced." : "somewhat irregular.")

        return analysis
    }
    
    private func stats(for stage: SleepStage) -> (
        hrMin: Int?, hrAvg: Int?, hrMax: Int?,
        rrMin: Int?, rrAvg: Int?, rrMax: Int?
    ) {
        let filtered = stages.filter { $0.stage == stage }

        let hrs = filtered.compactMap { $0.averageHeartRate }
        let rrs = filtered.compactMap { $0.averageRespiratoryRate }

        func minAvgMax(_ values: [Int]) -> (Int?, Int?, Int?) {
            guard !values.isEmpty else { return (nil, nil, nil) }
            let minVal = values.min()
            let maxVal = values.max()
            let avgVal = Int(Double(values.reduce(0, +)) / Double(values.count))
            return (minVal, avgVal, maxVal)
        }

        let (hrMin, hrAvg, hrMax) = minAvgMax(hrs)
        let (rrMin, rrAvg, rrMax) = minAvgMax(rrs)

        return (hrMin, hrAvg, hrMax, rrMin, rrAvg, rrMax)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                
                Text("Sleep Quality Analysis")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Group {
                if sleepViewDeviceSupportsAppleIntelligence() {
                    if isAIAnalysisLoading {
                        ProgressView()
                            .tint(.yellow)
                    }
                    Text(appleIntelligenceAnalysis.isEmpty ? ruleBasedLine : appleIntelligenceAnalysis)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(nil)
                } else {
                    Text(ruleBasedLine)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(nil)
                }
            }
            .task(id: aiTaskIdentity) {
                await runSleepQualityAppleIntelligence()
            }

            Text(nextDayReadinessAnalysis)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(nil)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            VStack(spacing: 8) {
                ForEach([SleepStage.core, .deep, .rem, .awake], id: \.self) { stage in
                    let stats = stats(for: stage)

                    if stats.hrAvg != nil || stats.rrAvg != nil {
                        HStack {
                            Circle()
                                .fill(stage.color)
                                .frame(width: 8, height: 8)

                            Text(stage.label)
                                .font(.caption)
                                .foregroundColor(.white)

                            Spacer()

                            if let avgHR = stats.hrAvg {
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.red)
                                    Text("\(stats.hrMin ?? avgHR)–\(stats.hrMax ?? avgHR) bpm (avg \(avgHR))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }

                            if let avgRR = stats.rrAvg {
                                HStack(spacing: 4) {
                                    Image(systemName: "wind")
                                        .foregroundColor(.cyan)
                                    Text("\(stats.rrMin ?? avgRR)–\(stats.rrMax ?? avgRR)/min (avg \(avgRR))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.1))
                .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Heart rate dip card

struct HeartRateDipCard: View {
    let summary: HeartRateDipSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.mint)
                Text("Heart rate dip")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            if let s = summary {
                if let day = s.daytimeAvgBpm, let night = s.nocturnalAvgBpm {
                    Text(String(format: "Daytime living avg (8am–8pm, no workouts): %.0f bpm (%d samples). Asleep (core/deep/REM) avg: %.0f bpm (%d samples).",
                                day, s.daytimeSampleCount, night, s.nocturnalSampleCount))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                if let dip = s.dipPercent {
                    Text(String(format: "Dip: %.1f%%", dip))
                        .font(.title3.bold())
                        .foregroundColor(.cyan)
                }
                Text(s.band.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor({
                        switch s.band {
                        case .extremeDipper, .dipper: return Color.green
                        case .nonDipper, .reverseDipper: return Color.orange
                        case .insufficientData: return Color.gray
                        }
                    }())
                Text(s.band.detail)
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                Text("No dip result yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Text("HR dipping is a wellness trend metric, not a diagnosis. Persistent reverse dipping or symptoms like snoring or daytime sleepiness deserve a clinician’s input.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.18))
                .strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Bedtime consistency (deviation chart)

struct SleepBedtimeConsistencyCard: View {
    let nights: [BedtimeConsistencyNight]
    /// `nil` after scrub ends → UI falls back to the latest night on the chart.
    @State private var selectedNightStart: Date?

    private var meanOffsetMinutes: Double {
        guard !nights.isEmpty else { return 0 }
        return nights.map(\.minutesFromNightAnchor).reduce(0, +) / Double(nights.count)
    }

    private var averageBedtimeString: String? {
        guard let ref = nights.last?.nightStart else { return nil }
        let t = ref.addingTimeInterval(meanOffsetMinutes * 60)
        return t.formatted(date: .omitted, time: .shortened)
    }

    /// X-axis anchor for the highlighted point and caption: explicit scrub, else latest night (rightmost).
    private var displayNightAnchor: Date? {
        selectedNightStart ?? nights.last?.nightStart
    }

    private var displayRow: BedtimeConsistencyNight? {
        guard let anchor = displayNightAnchor else { return nil }
        return nights.min(by: { abs($0.nightStart.timeIntervalSince(anchor)) < abs($1.nightStart.timeIntervalSince(anchor)) })
    }

    private var scrubCaptionPrefix: String {
        selectedNightStart == nil ? "Latest night: " : "Selected: "
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.indigo)
                Text("Sleep consistency")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            Text("Deviation from your average first-asleep time (core/deep/REM onset after 6 PM anchor). Scrub the chart to compare nights; the label stays visible and defaults to the latest.")
                .font(.caption2)
                .foregroundColor(.gray)
            if nights.count >= 2 {
                Chart {
                    ForEach(nights) { n in
                        LineMark(
                            x: .value("Night", n.nightStart),
                            y: .value("Δ min", n.deviationMinutes)
                        )
                        .foregroundStyle(.cyan.gradient)
                        PointMark(
                            x: .value("Night", n.nightStart),
                            y: .value("Δ min", n.deviationMinutes)
                        )
                        .foregroundStyle(displayRow?.nightStart == n.nightStart ? Color.yellow : Color.cyan)
                    }
                    RuleMark(y: .value("Average", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(height: 160)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .automatic) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)) } }
                .chartXSelection(value: $selectedNightStart)
                if let avg = averageBedtimeString {
                    Text("Typical first-asleep time ≈ \(avg) (0 line = that average).")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                }
                if let row = displayRow {
                    let dev = Int(round(row.deviationMinutes))
                    let devStr = dev >= 0 ? "+\(dev)" : "\(dev)"
                    Text("\(scrubCaptionPrefix)\(row.firstAsleepTime.formatted(date: .abbreviated, time: .shortened)) · Δ \(devStr) min from avg")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.yellow.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Need at least two nights with stage data for this chart.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.indigo.opacity(0.15))
                .strokeBorder(Color.indigo.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Overnight vitals normality (Watch-inspired strip)

struct OvernightVitalsNormalityCard: View {
    let metrics: [OvernightVitalMetric]
    let sleepWindowLabel: String?

    private let bandHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Overnight vitals")
                            .font(.headline)
                            .foregroundColor(.white)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    let outCount = metrics.filter(\.isOutlier).count
                    if outCount > 0 {
                        Text("\(outCount) outlier\(outCount == 1 ? "" : "s")")
                            .font(.title2.bold())
                            .foregroundStyle(
                                LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                    } else {
                        Text("Within typical range")
                            .font(.title3.bold())
                            .foregroundColor(.cyan)
                    }
                    if let w = sleepWindowLabel {
                        Text(w)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Spacer()
            }
            if metrics.isEmpty {
                Text("Wear Apple Watch overnight with vitals enabled to see this view.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                GeometryReader { geo in
                    let colW = geo.size.width / CGFloat(max(1, metrics.count))
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.12, green: 0.06, blue: 0.22).opacity(0.9))
                        // Normal band (middle third)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.22))
                            .frame(height: bandHeight * 0.42)
                            .padding(.horizontal, 8)
                            .padding(.top, bandHeight * 0.29 + 8)
                        ForEach(Array(metrics.enumerated()), id: \.element.id) { i, m in
                            let x = CGFloat(i) * colW + colW / 2
                            let y = 8 + (1.0 - (m.normalityPosition + 1) / 2.0) * (bandHeight - 16) + 8
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(m.isOutlier ? Color.pink.opacity(0.35) : Color.blue.opacity(0.35))
                                        .frame(width: 22, height: 22)
                                        .blur(radius: 4)
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 10, height: 10)
                                    Circle()
                                        .stroke(m.isOutlier ? Color.pink : Color.cyan, lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                }
                                Image(systemName: m.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(m.isOutlier ? Color.pink : Color.cyan)
                            }
                            .position(x: x, y: y)
                        }
                    }
                    .frame(height: bandHeight + 36)
                }
                .frame(height: bandHeight + 36)
                HStack(spacing: 0) {
                    ForEach(metrics) { m in
                        VStack(spacing: 2) {
                            Text(m.title)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(m.valueLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Text("Compared to your recent asleep windows (up to 14 nights). Not medical advice.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.08, green: 0.04, blue: 0.16))
                .strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)
        )
    }
}

struct SleepSummaryCard: View {
    let summaries: [DailySleepSummary]
    let period: SleepPeriod

    @EnvironmentObject private var viewModel: SleepViewModel

    @State private var previousStageAverages: [SleepStage: Double] = [:]

    // Helper to calculate stage percentages
    private func getStagPercentages() -> (deep: Int, core: Int, rem: Int) {
        let totalCurrentAvg = summaries.map { $0.totalMinutes }.reduce(0,+) / Double(max(1, summaries.count))
        
        if totalCurrentAvg <= 0 {
            return (0, 0, 0)
        }
        
        let deepAvg = summaries.map { $0.deepMinutes }.reduce(0,+) / Double(summaries.count)
        let coreAvg = summaries.map { $0.coreMinutes }.reduce(0,+) / Double(summaries.count)
        let remAvg = summaries.map { $0.remMinutes }.reduce(0,+) / Double(summaries.count)
        
        let deepPercent = Int(deepAvg / totalCurrentAvg * 100)
        let corePercent = Int(coreAvg / totalCurrentAvg * 100)
        let remPercent = Int(remAvg / totalCurrentAvg * 100)
        
        return (deepPercent, corePercent, remPercent)
    }

    // Non-async computed property for stage comparison
    private var stageComparisonData: [(stage: SleepStage, current: Double, previous: Double?, percent: Double)] {
        let stages: [SleepStage] = [.awake, .deep, .core, .rem, .unspecifiedAsleep]
        let totalCurrentAvg = summaries.map { $0.totalMinutes }.reduce(0,+)
            / Double(max(1, summaries.count))

        return stages.map { stage in
            let currentAvg = summaries.map { summary -> Double in
                switch stage {
                case .awake: return summary.awakeMinutes
                case .core: return summary.coreMinutes
                case .deep: return summary.deepMinutes
                case .rem: return summary.remMinutes
                case .unspecifiedAsleep: return summary.unspecifiedAsleepMinutes
                }
            }.reduce(0,+) / Double(summaries.count)

            let prevAvg = previousStageAverages[stage]
            let percent = totalCurrentAvg > 0 ? (currentAvg / totalCurrentAvg) * 100 : 0
            return (stage, currentAvg, prevAvg, percent)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Summary")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(stageComparisonData, id: \.stage) { data in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                            Circle()
                                .fill(data.stage.color)
                                .frame(width: 8, height: 8)

                            // Stage label + indicator
                            HStack(spacing: 6) {
                                Text(data.stage.label)
                                    .foregroundColor(.white)

                                // Indicator next to the label: up / down / = based on change vs previous
                                if period != .lastNight, let prev = data.previous {
                                    let diff = data.current - prev
                                    // relative change vs previous; if previous is zero, treat as significant unless exactly equal
                                    let relChange = prev != 0 ? diff / prev : (diff == 0 ? 0 : 1)

                                    if abs(relChange) <= 0.20 {
                                        Text("=")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    } else if diff > 0 {
                                        Image(systemName: "chevron.up")
                                            .foregroundColor(data.stage == .awake ? .red : .green)
                                    } else {
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(data.stage == .awake ? .green : .red)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                            Text(formatMinutesToHoursMinutes(data.current))
                                .font(.headline)
                                .foregroundColor(.white)
                            // Show only corresponding stage percentage
                            if data.stage != .awake {
                                let percentages = getStagPercentages()
                                let percentageText: String = {
                                    switch data.stage {
                                    case .deep:
                                        return "\(percentages.deep)% on average"
                                    case .core:
                                        return "\(percentages.core)% on average"
                                    case .rem:
                                        return "\(percentages.rem)% on average"
                                    case .awake:
                                        return ""
                                    case .unspecifiedAsleep:
                                        return ""
                                    }
                                }()
                                Text(percentageText)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                Divider()
                    .background(Color.white.opacity(0.2))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
        .onAppear {
            Task {
                guard let firstDate = summaries.first?.date else { return }
                let prevSummaries = await viewModel.loadPreviousPeriodSummaries(reference: firstDate, period: period)
                var dict: [SleepStage: Double] = [:]
                for stage in [SleepStage.awake, SleepStage.deep, SleepStage.core, SleepStage.rem, SleepStage.unspecifiedAsleep] {
                    let avgValue = prevSummaries.map { summary -> Double in
                        switch stage {
                        case .awake: return summary.awakeMinutes
                        case .core: return summary.coreMinutes
                        case .deep: return summary.deepMinutes
                        case .rem: return summary.remMinutes
                        case .unspecifiedAsleep: return summary.unspecifiedAsleepMinutes
                        }
                    }.reduce(0,+) / Double(prevSummaries.count)
                    dict[stage] = avgValue
                }
                await MainActor.run {
                    previousStageAverages = dict
                }
            }
        }
    }
}

// MARK: - SleepStagesDropdownCard
struct SleepStagesDropdownCard: View {
    let stages: [SleepStageData]
    var expandAll: Binding<Bool>?
    
    @State private var isExpanded: Bool = false
    @State private var expandedStageIds: [UUID: Bool] = [:]
    
    // Quality ranges for sleep stages (HR and RR thresholds) - matches SleepStageRow
    private func qualityRanges(for stage: SleepStage) -> (hrMin: Int?, hrMax: Int?, rrMin: Int?, rrMax: Int?) {
        switch stage {
        case .awake:
            return (nil, nil, nil, nil)
        case .core:
            return (50, 70, 10, 18)
        case .deep:
            return (nil, 60, 10, 16)
        case .rem:
            return (60, 80, 12, 22)
        case .unspecifiedAsleep:
            return (nil, nil, nil, nil)
        }
    }
    
    // Check if HR is within quality range
    private func isHRInRange(hr: Int, for stage: SleepStage) -> Bool {
        let ranges = qualityRanges(for: stage)
        if let min = ranges.hrMin, let max = ranges.hrMax {
            return hr >= min && hr <= max
        } else if let max = ranges.hrMax {
            return hr < max
        }
        return false
    }
    
    // Check if RR is within quality range
    private func isRRInRange(rr: Int, for stage: SleepStage) -> Bool {
        let ranges = qualityRanges(for: stage)
        if let min = ranges.rrMin, let max = ranges.rrMax {
            return rr >= min && rr <= max
        }
        return false
    }
    
    // Check if a session meets quality criteria (matching glowOpacity logic)
    private func isQualitySession(_ session: SleepStageData, avgDuration: Double) -> Bool {
        guard let hr = session.averageHeartRate, let rr = session.averageRespiratoryRate else { return false }
        
        switch session.stage {
        case .awake:
            return session.duration / 300 > 1  // More than 5 minutes
        case .core, .deep, .rem:
            return (session.duration > avgDuration * 60) && isHRInRange(hr: hr, for: session.stage) && isRRInRange(rr: rr, for: session.stage)
        case .unspecifiedAsleep:
            return false
        }
    }
    
    private var statsPerStage: [SleepStage: (longCount: Int, shortCount: Int)] {
        var dict: [SleepStage: (Int, Int)] = [:]
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        
        for stageType in [SleepStage.core, .deep, .rem, .awake, .unspecifiedAsleep] {
            let allSessions = stages.filter { $0.stage == stageType }
            let recentSessions = allSessions.filter { $0.startTime >= oneWeekAgo }
            
            // Calculate average duration from recent sessions
            let avgDuration: Double = recentSessions.isEmpty ? 0 : recentSessions.map { $0.duration / 60 }.reduce(0, +) / Double(recentSessions.count)
            
            // Count long and short sessions from recent data only
            let long = recentSessions.filter { ($0.duration / 60) >= avgDuration * 1.5 && avgDuration > 0 }.count
            let short = recentSessions.filter { ($0.duration / 60) < avgDuration * 0.5 && avgDuration > 0 }.count
            dict[stageType] = (long, short)
        }
        return dict
    }
    
    private var notableHighlight: String {
        guard let maxStage = stages.max(by: { $0.duration < $1.duration }) else { return "" }
        return "Longest session: \(maxStage.stage.label) – \(Int(maxStage.duration/60)) min"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    expandAll?.wrappedValue = isExpanded
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundColor(.yellow)
                        .font(.title2)
                    Text("Sleep Stages")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.2)))
            }
            
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(stages) { stage in
                        let isRowExpanded = expandedStageIds[stage.id] ?? false
                        SleepStageRow(
                            stage: stage,
                            isExpanded: isRowExpanded,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    expandedStageIds[stage.id] = !(expandedStageIds[stage.id] ?? false)
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            } else {
                VStack(spacing: 12) {
                    // Stage labels row - only show core, rem, deep (not awake or unspecifiedAsleep)
                    HStack(spacing: 0) {
                        ForEach([SleepStage.core, .rem, SleepStage.deep], id: \.self) { stageType in
                            if let counts = statsPerStage[stageType] {
                                VStack(spacing: 4) {
                                    Text(stageType.label)
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    // Long + short sessions - use 7‑day baseline like statsPerStage
                                    let stageSessions = stages.filter { $0.stage == stageType }
                                    let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                                    let recentSessions = stageSessions.filter { $0.startTime >= oneWeekAgo }

                                    // Average duration from recent sessions only (minutes)
                                    let avgDuration: Double = recentSessions.isEmpty
                                        ? 0
                                        : recentSessions.map { $0.duration / 60.0 }.reduce(0, +) / Double(recentSessions.count)

                                    let totalDurationMinutes = stageSessions.reduce(0) { $0 + $1.duration } / 60.0

                                    HStack(spacing: 2) {
                                        Text(formatMinutesToHoursMinutes(totalDurationMinutes))
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .minimumScaleFactor(0.5)
                                            .lineLimit(1)

//                                        if avgDuration > 0 {
//                                            // Count quality sessions using the same logic used by glowOpacity
//                                            let qualityCount = stageSessions.filter {
//                                                isQualitySession($0, avgDuration: avgDuration)
//                                            }.count
//
//                                            if qualityCount > 0 {
//                                                Text("(\(qualityCount) quality)")
//                                                    .font(.caption2)
//                                                    .foregroundColor(.yellow)
//                                            }
//                                        }
                                    }

                                    let avgDurationMinutes = stageSessions.isEmpty ? 0 : totalDurationMinutes / Double(stageSessions.count)
                                    VStack(spacing: 2) {
                                        Text("\(stageSessions.count) block\(stageSessions.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundColor(.gray)

                                        Text("\(formatMinutesToHoursMinutes(avgDurationMinutes)) avg / block")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                if stageType != .deep { // add vertical divider except last
                                    Divider()
                                        .frame(height: 50)
                                        .background(Color.white.opacity(0.3))
                                }
                            }
                        }
                    }
                    // --- Begin Awake Row Addition ---
                    if let awakeCounts = statsPerStage[.awake] {
                        let awakeSessions = stages.filter { $0.stage == .awake }
                        let interruptionType = awakeSessions.contains { $0.duration / 60 > 5 || ($0.averageHeartRate ?? 0) > 80 || ($0.averageRespiratoryRate ?? 0) > 20 } ? "Major" : "Minor"

                        VStack(spacing: 4) {
                            Text("Awake")
                                .font(.caption)
                                .foregroundColor(.gray)

                            // Awake time
                            let totalAwakeMinutes = awakeSessions.reduce(0) { $0 + $1.duration } / 60.0
                            // Total actual sleep (excluding awake) in minutes
                            let totalSleepMinutes = stages.filter { $0.stage != .awake }
                                .reduce(0) { $0 + $1.duration } / 60.0

                            HStack(spacing: 2) {
                                Text(formatMinutesToHoursMinutes(totalAwakeMinutes))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("(\(awakeSessions.count) times, \(interruptionType))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }

                            // Text(String(format: "Total sleep: %.1f h", totalSleepHours))
                            //     .font(.caption2)
                            //     .foregroundColor(.gray)

                            Text(interruptionType == "Major" ? "Frequent/long interruptions may reduce sleep quality." : "Brief interruptions—minimal impact on recovery.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.02)))

                        // --- Insert new Total Sleep row ---
                        VStack(spacing: 4) {
                            Text("Total Sleep")
                                .font(.caption)
                                .foregroundColor(.gray)

                            let totalSleepMinutes = stages.filter { $0.stage != .awake }
                                .reduce(0) { $0 + $1.duration } / 60.0
                            Text(formatMinutesToHoursMinutes(totalSleepMinutes))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.02)))
                    }
                    // --- End Awake Row Addition ---
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                .transition(.opacity.combined(with: .scale))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isExpanded)
            }
        }
        .padding(.horizontal, 8)
    }
}


// MARK: - Global periodDateRange function
func periodDateRange(period: SleepPeriod, earliest: Date?) -> (Date, Date) {
    let calendar = Calendar.current
    let now = Date()
    let today = calendar.startOfDay(for: now)
    let catalystMinimum = MacCatalystHealthDataPolicy.isActive ? MacCatalystHealthDataPolicy.minimumAllowedDate : .distantPast
    switch period {
    case .lastNight:
        let minDate = earliest.map { calendar.startOfDay(for: $0) } ?? calendar.date(byAdding: .year, value: -5, to: today)!
        let maxDate = today
        let clampedMin = max(minDate, catalystMinimum)
        return (min(clampedMin, maxDate), maxDate)
    case .thisWeek:
        // Only Sundays selectable, from earliest Sunday after earliestSleepDate up to this week's Sunday
        let thisSunday = calendar.nextDate(after: today, matching: DateComponents(weekday: 1), matchingPolicy: .previousTimePreservingSmallerComponents) ?? today
        let minDate: Date
        if let earliest = earliest {
            let e = calendar.startOfDay(for: earliest)
            let weekday = calendar.component(.weekday, from: e)
            // Go to the next Sunday on or after earliest
            let offset = (8 - weekday) % 7
            minDate = calendar.date(byAdding: .day, value: offset, to: e)!
        } else {
            minDate = calendar.date(byAdding: .year, value: -5, to: thisSunday)!
        }
        let clampedMin = max(minDate, catalystMinimum)
        return (min(clampedMin, thisSunday), thisSunday)
    case .thisMonth:
        // Only first of month selectable, from earliest first-of-month to this month
        let currentFirst = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let minDate: Date
        if let earliest = earliest {
            let e = calendar.startOfDay(for: earliest)
            let comps = calendar.dateComponents([.year, .month], from: e)
            minDate = calendar.date(from: comps)!
        } else {
            minDate = calendar.date(byAdding: .year, value: -5, to: currentFirst)!
        }
        let clampedMin = max(minDate, catalystMinimum)
        return (min(clampedMin, currentFirst), currentFirst)
    case .thisYear:
        // Only Jan 1 selectable, from earliest year to current year
        let currentJan1 = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1))!
        let minDate: Date
        if let earliest = earliest {
            let e = calendar.startOfDay(for: earliest)
            let comps = calendar.dateComponents([.year], from: e)
            minDate = calendar.date(from: DateComponents(year: comps.year, month: 1, day: 1))!
        } else {
            minDate = calendar.date(byAdding: .year, value: -5, to: currentJan1)!
        }
        let clampedMin = max(minDate, catalystMinimum)
        return (min(clampedMin, currentJan1), currentJan1)
    }
}
