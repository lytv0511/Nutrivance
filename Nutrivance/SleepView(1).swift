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
    case core = 3       // asleepCore
    case deep = 4       // asleepDeep
    case rem = 5        // asleepREM
    
    var label: String {
        switch self {
        case .awake: return "Awake"
        case .core: return "Core Sleep"
        case .deep: return "Deep Sleep"
        case .rem: return "REM Sleep"
        }
    }
    
    var description: String {
        switch self {
        case .awake:
            return "Time awake during your sleep period. Some brief awakenings during sleep are normal."
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
    
    var awakePercentage: Double {
        totalMinutes > 0 ? (awakeMinutes / totalMinutes) * 100 : 0
    }
    
    var deepPercentage: Double {
        totalMinutes > 0 ? (deepMinutes / totalMinutes) * 100 : 0
    }
    
    var corePercentage: Double {
        totalMinutes > 0 ? (coreMinutes / totalMinutes) * 100 : 0
    }
    
    var remPercentage: Double {
        totalMinutes > 0 ? (remMinutes / totalMinutes) * 100 : 0
    }
}

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
    
    private let healthStore = HealthKitManager()
    
    init() {
        Task {
            await self.fetchEarliestSleepDate()
        }
    }
    
    func fetchEarliestSleepDate() async {
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
    }
    
    func loadSleepData(for date: Date) async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        
        switch selectedPeriod {
        case .lastNight:
            await loadLastNightData(calendar: calendar, for: date)
        case .thisWeek:
            await loadWeekData(calendar: calendar, for: date)
        case .thisMonth:
            await loadMonthData(calendar: calendar, for: date)
        case .thisYear:
            await loadYearData(calendar: calendar, for: date)
        }
    }
    
    private func loadLastNightData(calendar: Calendar, for date: Date) async {
        // Use night-based boundaries, matching fetchDaySleepSummary
        let nightStart = sleepNightStart(for: date, calendar: calendar)
        let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart)!
        // Wide fetch window to capture cross‑midnight samples
        let predicate = HKQuery.predicateForSamples(
            withStart: calendar.date(byAdding: .hour, value: -12, to: nightStart)!,
            end: nightEnd,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

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

        // Filter to only samples attributed to this night
        let filteredSamples = sleepSamples.filter {
            sleepNightStart(for: $0.startDate, calendar: calendar) == nightStart
        }

        // Convert to SleepStageData - include values 2 (awake), 3 (core), 4 (deep), 5 (rem)
        var stages: [SleepStageData] = []
        for sample in filteredSamples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
            // Filter out very short stages (less than 2 minutes)
            if duration < 2 {
                continue
            }
            let metrics = await fetchMetricsDuringStage(startTime: sample.startDate, endTime: sample.endDate)
            if sample.value == 2 {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .awake,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == 3 {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .core,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == 4 {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .deep,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            } else if sample.value == 5 {
                stages.append(SleepStageData(
                    startTime: sample.startDate,
                    endTime: sample.endDate,
                    stage: .rem,
                    averageHeartRate: metrics.heartRate,
                    averageRespiratoryRate: metrics.respiratoryRate
                ))
            }
        }

        // Merge consecutive stages of the same type
        let consolidatedStages = consolidateSleepStages(stages)
        self.sleepData = consolidatedStages
    }
    
    private func loadWeekData(calendar: Calendar, for date: Date) async {
        var summaries: [DailySleepSummary] = []
        // date is a Sunday; show 7 days starting from date
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: date)!
            let startOfDay = calendar.startOfDay(for: day)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let summary = await fetchDaySleepSummary(startDate: startOfDay, endDate: endOfDay)
            if summary.totalMinutes > 0 {
                summaries.append(summary)
            }
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
            if summary.totalMinutes > 0 {
                summaries.append(summary)
            }
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
                remMinutes: monthSummary.remMinutes / nights
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
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return DailySleepSummary(date: startDate, totalMinutes: 0, awakeMinutes: 0, deepMinutes: 0, coreMinutes: 0, remMinutes: 0)
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
        let awakeMinutes = calculateStageMinutes(samples: samples, stageValue: 2, nightStart: nightStart, calendar: calendar)
        let coreMinutes = calculateStageMinutes(samples: samples, stageValue: 3, nightStart: nightStart, calendar: calendar)
        let deepMinutes = calculateStageMinutes(samples: samples, stageValue: 4, nightStart: nightStart, calendar: calendar)
        let remMinutes = calculateStageMinutes(samples: samples, stageValue: 5, nightStart: nightStart, calendar: calendar)
        let totalMinutes = awakeMinutes + coreMinutes + deepMinutes + remMinutes
        return DailySleepSummary(
            date: nightStart,
            totalMinutes: totalMinutes,
            awakeMinutes: awakeMinutes,
            deepMinutes: deepMinutes,
            coreMinutes: coreMinutes,
            remMinutes: remMinutes
        )
    }
    
    private func fetchMonthSleepSummary(startDate: Date, endDate: Date) async -> DailySleepSummary {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return DailySleepSummary(date: startDate, totalMinutes: 0, awakeMinutes: 0, deepMinutes: 0, coreMinutes: 0, remMinutes: 0)
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

        var night = sleepNightStart(for: startDate, calendar: calendar)
        while night < endDate {
            awakeMinutes += calculateStageMinutes(samples: samples, stageValue: 2, nightStart: night, calendar: calendar)
            coreMinutes  += calculateStageMinutes(samples: samples, stageValue: 3, nightStart: night, calendar: calendar)
            deepMinutes  += calculateStageMinutes(samples: samples, stageValue: 4, nightStart: night, calendar: calendar)
            remMinutes   += calculateStageMinutes(samples: samples, stageValue: 5, nightStart: night, calendar: calendar)
            night = calendar.date(byAdding: .day, value: 1, to: night)!
        }
        let totalMinutes = awakeMinutes + coreMinutes + deepMinutes + remMinutes

        return DailySleepSummary(
            date: startDate,
            totalMinutes: totalMinutes,
            awakeMinutes: awakeMinutes,
            deepMinutes: deepMinutes,
            coreMinutes: coreMinutes,
            remMinutes: remMinutes
        )
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
        
        var consolidated: [SleepStageData] = []
        var currentStage = stages[0]
        
        for i in 1..<stages.count {
            let nextStage = stages[i]
            
            // If same stage type and consecutive (or very close), merge them
            if currentStage.stage == nextStage.stage {
                // Create merged stage
                currentStage = SleepStageData(
                    startTime: currentStage.startTime,
                    endTime: nextStage.endTime,
                    stage: currentStage.stage,
                    averageHeartRate: currentStage.averageHeartRate,
                    averageRespiratoryRate: currentStage.averageRespiratoryRate
                )
            } else {
                // Different stage type, save current and start new one
                consolidated.append(currentStage)
                currentStage = nextStage
            }
        }
        
        // Don't forget the last stage
        consolidated.append(currentStage)
        
        return consolidated
    }

    /// Computes per-stage averages for the current and previous period (week/month/year),
    /// returning an array suitable for SleepSummaryCard.
    /// Returns: [(stage, currentAvgMinutes, prevAvgMinutes, percentOfTotal)]
    func computeStageAveragesForPeriod(summaries: [DailySleepSummary], period: SleepPeriod) -> [(stage: SleepStage, current: Double, previous: Double, percent: Double)] {
        guard !summaries.isEmpty else { return [] }

        // Helper to get stage minutes from a summary
        func stageMinutes(_ summary: DailySleepSummary, _ stage: SleepStage) -> Double {
            switch stage {
            case .awake: return summary.awakeMinutes
            case .core:  return summary.coreMinutes
            case .deep:  return summary.deepMinutes
            case .rem:   return summary.remMinutes
            }
        }

        // Determine current and previous period slices
        let stages: [SleepStage] = [.awake, .deep, .core, .rem]
        var currentSummaries: [DailySleepSummary] = []
        var prevSummaries: [DailySleepSummary] = []

        switch period {
        case .thisWeek:
            // Last 7 items = current, previous 7 = prev (if available)
            if summaries.count >= 7 {
                currentSummaries = Array(summaries.suffix(7))
                if summaries.count >= 14 {
                    prevSummaries = Array(summaries.dropLast(7).suffix(7))
                } else {
                    prevSummaries = Array(summaries.prefix(summaries.count - 7))
                }
            } else {
                currentSummaries = summaries
                prevSummaries = []
            }
        case .thisMonth:
            // Assume summaries are per day in month (1...n)
            let days = summaries.count
            let half = days/2
            if days > 0 {
                currentSummaries = Array(summaries.suffix(half == 0 ? days : days - half))
                prevSummaries = Array(summaries.prefix(half))
            }
        case .thisYear:
            // Assume summaries are per month (12)
            let months = summaries.count
            let half = months/2
            if months > 0 {
                currentSummaries = Array(summaries.suffix(half == 0 ? months : months - half))
                prevSummaries = Array(summaries.prefix(half))
            }
        case .lastNight:
            // Only one summary
            currentSummaries = summaries
            prevSummaries = []
        }

        // Compute averages per stage for current and previous period
        func avg(_ arr: [Double]) -> Double {
            guard !arr.isEmpty else { return 0 }
            return arr.reduce(0,+)/Double(arr.count)
        }
        let totalCurrentMinutes = avg(currentSummaries.map { $0.totalMinutes })
        // For percent, percent of total sleep time in current period

        return stages.map { stage in
            let currAvg = avg(currentSummaries.map { stageMinutes($0, stage) })
            let prevAvg = avg(prevSummaries.map { stageMinutes($0, stage) })
            let percent = totalCurrentMinutes > 0 ? (currAvg / totalCurrentMinutes) * 100 : 0
            return (stage, currAvg, prevAvg, percent)
        }
    }
}

enum SleepPeriod: String, CaseIterable {
    case lastNight = "Night"
    case thisWeek = "Week"
    case thisMonth = "Month"
    case thisYear = "Year"
}

struct SleepView: View {
    @StateObject private var viewModel = SleepViewModel()
    @State private var animationPhase: Double = 0
    @State private var expandedStage: UUID?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    


    
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
            return today
        case .thisWeek:
            // Most recent Sunday
            return calendar.nextDate(after: today, matching: DateComponents(weekday: 1), matchingPolicy: .previousTimePreservingSmallerComponents) ?? today
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        case .thisYear:
            return calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1))!
        }
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
                    VStack(spacing: 24) {
                        // Filter buttons
                        HStack(spacing: 12) {
                            ForEach(SleepPeriod.allCases, id: \.self) { period in
                                Button(action: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    viewModel.selectedPeriod = period
                                    let newDate = defaultDate(for: period)
                                    selectedDate = newDate
                                    Task { await viewModel.loadSleepData(for: newDate) }
                                }) {
                                    Text(period.rawValue)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(viewModel.selectedPeriod == period ? .white : .gray)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(viewModel.selectedPeriod == period ?
                                                      Color.blue.opacity(0.7) : Color.clear)
                                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Date picker popup button in top bar
                        SleepDatePopupPicker(
                            selectedPeriod: viewModel.selectedPeriod,
                            earliestSleepDate: viewModel.earliestSleepDate,
                            selectedDate: $selectedDate,
                            onDateChange: { newDate in
                                selectedDate = newDate
                                Task { await viewModel.loadSleepData(for: newDate) }
                            }
                        )
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .padding()
                        } else if viewModel.selectedPeriod == .lastNight {
                            VStack(spacing: 16) {
                                SleepStagesDropdownCard(stages: viewModel.sleepData)
                                SleepQualityCard(stages: viewModel.sleepData)
                            }
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(viewModel.dailySummaries) { summary in
                                    SleepBarChart(summary: summary)
                                }
                                SleepSummaryCard(summaries: viewModel.dailySummaries, period: viewModel.selectedPeriod)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            let defaultD = defaultDate(for: viewModel.selectedPeriod)
            selectedDate = defaultD
            await viewModel.loadSleepData(for: defaultD)
        }
        .environmentObject(viewModel)
    }
}

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
    
    private var glowOpacity: Double {
        guard let hr = stage.averageHeartRate, let rr = stage.averageRespiratoryRate else { return 0.3 }
        
        switch stage.stage {
        case .awake:
            // Slightly more glow for long awake periods
            return stage.duration / 300 > 1 ? 0.5 : 0.3
        case .core:
            // Stronger glow for long, restorative core sessions
            return (stage.duration > Double(averageDuration(for: .core) * 60) && hr >= 50 && hr <= 60 && rr >= 10 && rr <= 14) ? 0.8 : 0.4
        case .deep:
            // Strongest glow for long, restorative deep sessions
            return (stage.duration > Double(averageDuration(for: .deep) * 60) && hr < 55 && rr >= 10 && rr <= 14) ? 0.9 : 0.4
        case .rem:
            // Stronger glow for long, healthy REM sessions
            return (stage.duration > Double(averageDuration(for: .rem) * 60) && hr >= 65 && hr <= 75 && rr >= 12 && rr <= 18) ? 0.8 : 0.4
        }
    }
    
    // MARK: - Sleep Insights
    
    private func averageDuration(for stageType: SleepStage) -> Int {
        // Flatten all sleep stage segments from the last 7 days
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        let recentStages = viewModel.sleepData.filter { $0.startTime >= oneWeekAgo }
        
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
            } else if isLong && hr >= 65 && hr <= 75 && rr >= 12 && rr <= 18 {
                insight += " Wow, this was a long, healthy REM session—time to store up what you learned! I guess some great dreams were happening."
            } else {
                insight += " Solid REM, your brain got some valuable processing done."
            }
        case .deep:
            insight = "Deep sleep is your body's repair shop. This session lasted \(comparison)."
            if isShort {
                insight += " A brief visit—your body may have done a little repair, but not a full restorative cycle."
            } else if isLong && hr < 55 && rr >= 10 && rr <= 14 {
                insight += " Excellent! A long deep sleep session—muscles and immune system probably feeling recharged."
            } else {
                insight += " Good deep sleep—your body got some well-deserved repair time."
            }
        case .core:
            insight = "Core sleep keeps your cycles steady and energy balanced. This session lasted \(comparison)."
            if isShort {
                insight += " A short core stretch—just a little stabilizing action."
            } else if isLong && hr >= 50 && hr <= 60 && rr >= 10 && rr <= 14 {
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
        switch stage {
        case .awake:
            return hr > 80 ? "Elevated HR while awake—may indicate brief arousal." : "Normal HR during wake time."
        case .core:
            return hr < 50 ? "Very low HR—good cardiovascular rest during core sleep." : hr < 60 ? "Healthy HR during core sleep." : "Slightly elevated HR during core sleep."
        case .deep:
            return hr < 50 ? "Excellent—very low HR during restorative deep sleep." : hr < 60 ? "Good—HR is resting during deep sleep." : "Slightly elevated HR during deep sleep."
        case .rem:
            return hr > 70 ? "REM sleep HR elevated—active dreaming with higher heart rate." : "Moderate HR during REM sleep."
        }
    }
    
    private func rrAnalysis(for stage: SleepStage, rr: Int) -> String {
        switch stage {
        case .awake:
            return rr > 20 ? "Higher breathing rate while awake." : "Normal breathing rate while awake."
        case .core:
            return rr < 12 ? "Slow, steady breathing during core sleep—very restful." : rr < 14 ? "Good—regular breathing during core sleep." : "Slightly elevated breathing during core sleep."
        case .deep:
            return rr < 12 ? "Excellent—slow, deep breathing during restorative sleep." : "Normal breathing pattern during deep sleep."
        case .rem:
            return rr > 14 ? "REM sleep typically has variable, slightly elevated breathing." : "Regular breathing during REM sleep."
        }
    }
}

struct SleepBarChart: View {
    let summary: DailySleepSummary

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.component(.day, from: summary.date) == 1 ? "MMM" : "MMM d"
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
                let totalHours = summary.totalMinutes / 60
                let actualSleepHours = (summary.totalMinutes - summary.awakeMinutes) / 60

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f h", totalHours))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(String(format: "(%.1f h actual sleep)", actualSleepHours))
                        .font(.caption2)
                        .foregroundColor(.gray)
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
    
    private var qualityAnalysis: String {
        guard !stages.isEmpty else { return "Insufficient data" }
        
        let remCount = stages.filter { $0.stage == .rem }.count
        let coreCount = stages.filter { $0.stage == .core }.count
        let totalDuration = stages.reduce(0) { $0 + $1.duration }
        let hours = totalDuration / 3600
        
        var analysis = ""
        
        if hours < 7 {
            analysis = "You got less than your recommended 7–9 hours. Try to extend your sleep duration."
        } else if hours > 9 {
            analysis = "You exceeded 9 hours. Quality over quantity—consider optimizing your sleep schedule."
        } else {
            analysis = "Your sleep duration is within the optimal range (7–9 hours)."
        }
        
        if remCount > coreCount * 2 {
            analysis += " You had extended REM sleep, which is great for cognitive function and emotional processing."
        }
        
        if stages.first?.stage == .rem {
            analysis += " ⚠️ You entered REM quickly—possible sleep deficit recovery."
        }
        
        return analysis
    }

    // MARK: - Deep Sleep Insight Logic (Refined)
    private func mergeIntervals(
        _ intervals: [(Date, Date)],
        maxGapMinutes: Double = 5
    ) -> [(Date, Date)] {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []

        for interval in sorted {
            if let last = merged.last,
               interval.0.timeIntervalSince(last.1) <= maxGapMinutes * 60 {
                merged[merged.count - 1].1 = max(last.1, interval.1)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private var nextDayReadinessAnalysis: String {
        // Compute the last 7 sleep nights (using anchor hour) for deep sleep sessions
        let calendar = Calendar.current
        let todayNight = sleepNightStart(for: Date(), calendar: calendar)
        let last7Nights: Set<Date> = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayNight)
        }.reduce(into: Set<Date>()) { $0.insert($1) }

        // 1. Filter for deep sleep samples (precisely, not core/unspecified)
        let deepSamples = stages.filter { $0.stage == .deep }

        // 2. Only sessions in last 7 sleep nights
        let recentDeepSamples = deepSamples.filter {
            last7Nights.contains(sleepNightStart(for: $0.startTime, calendar: calendar))
        }

        // 3. Merge contiguous intervals (within 5 minutes)
        let deepIntervals = mergeIntervals(
            recentDeepSamples.map { ($0.startTime, $0.endTime) }
        )

        // 4. Build session objects: start, end, durationMinutes
        let recentDeepSessions = deepIntervals.map {
            (
                start: $0.0,
                end: $0.1,
                durationMinutes: $0.1.timeIntervalSince($0.0) / 60
            )
        }

        // 5. “Long” deep sessions: duration >= 20 min
        let longDeepSessions = recentDeepSessions.filter {
            $0.durationMinutes >= 20
        }

        // 6. Compute total deep sleep minutes in the window
        let totalDeepMinutes = recentDeepSessions
            .map { $0.durationMinutes }
            .reduce(0, +)

        // Average HR for deep sessions (use original samples for HR)
        let avgDeepHR = recentDeepSamples.compactMap { $0.averageHeartRate }.reduce(0, +) / max(1, recentDeepSamples.compactMap { $0.averageHeartRate }.count)

        // REM sessions and average HR (unchanged)
        let remSessions = stages.filter { $0.stage == .rem }
        let avgRemHR = remSessions.compactMap { $0.averageHeartRate }.reduce(0, +) / max(1, remSessions.compactMap { $0.averageHeartRate }.count)

        var analysis = "Next-Day Readiness:\n"

        // Physical recovery
        if totalDeepMinutes >= 30 {
            analysis += "Physical recovery: \(longDeepSessions.count) long deep sleep session(s) with average HR \(avgDeepHR) bpm—supports muscle and immune recovery.\n"
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
        analysis += "Emotional balance: assessed based on REM and deep sleep patterns; your sleep appears " +
            (remSessions.count >= 2 && !longDeepSessions.isEmpty ? "balanced." : "somewhat irregular.")

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
            
            Text(qualityAnalysis)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(nil)

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

struct SleepSummaryCard: View {
    let summaries: [DailySleepSummary]
    let period: SleepPeriod

    @EnvironmentObject private var viewModel: SleepViewModel

    // Use viewModel's computeStageAveragesForPeriod to get data
    private var stageComparisonData: [(stage: SleepStage, current: Double, previous: Double, percent: Double)] {
        viewModel.computeStageAveragesForPeriod(summaries: summaries, period: period)
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
                        Text(data.stage.label)
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f h", data.current / 60))
                                .font(.headline)
                                .foregroundColor(.white)
                            // Show actual sleep (excluding awake) for non-awake stages
                            if data.stage != .awake {
                                let totalSleep = data.current
                                Text(String(format: "(%.1f h actual sleep)", totalSleep / 60))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    HStack {
                        if period != .lastNight {
                            let diff = data.current - data.previous
                            let diffSign = diff >= 0 ? "+" : "-"
                            Text(String(format: "(%@%.1f h vs prev) • %.0f%%", diffSign, abs(diff)/60, data.percent))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        } else {
                            Text(String(format: "%.0f%% of total", data.percent))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                Divider()
                    .background(Color.white.opacity(0.2))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }
}

// MARK: - SleepStagesDropdownCard
struct SleepStagesDropdownCard: View {
    let stages: [SleepStageData]
    
    @State private var isExpanded: Bool = false
    @State private var expandedStageIds: [UUID: Bool] = [:]
    
    private var statsPerStage: [SleepStage: (longCount: Int, shortCount: Int)] {
        var dict: [SleepStage: (Int, Int)] = [:]
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        
        for stageType in [SleepStage.core, .deep, .rem, .awake] {
            let sessions = stages.filter { $0.stage == stageType }
            let avg = sessions.filter { $0.startTime >= oneWeekAgo }
                              .map { $0.duration / 60 }.reduce(0, +) / max(1, Double(sessions.count))
            
            let long = sessions.filter { $0.duration / 60 >= avg * 1.5 }.count
            let short = sessions.filter { $0.duration / 60 < avg * 0.5 }.count
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
                    // Stage labels row
                    HStack(spacing: 0) {
                        ForEach([SleepStage.core, .rem, SleepStage.deep], id: \.self) { stageType in
                            if let counts = statsPerStage[stageType] {
                                VStack(spacing: 4) {
                                    Text(stageType.label)
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    // Long + short sessions
                                    HStack(spacing: 2) {
                                        Text("\(counts.longCount)")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        if counts.shortCount > 0 {
                                            Text("(+\(counts.shortCount))")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }

                                    // Total and average duration (now split into two lines)
                                    let stageSessions = stages.filter { $0.stage == stageType }
                                    let totalDuration = stageSessions.reduce(0) { $0 + $1.duration } / 3600.0
                                    let avgDuration = stageSessions.isEmpty ? 0 : totalDuration / Double(stageSessions.count)
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.1f h total", totalDuration))
                                            .font(.caption2)
                                            .foregroundColor(.gray)

                                        Text(String(format: "%.1f h × %d sessions", avgDuration, stageSessions.count))
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
                        let totalAwakeDuration = awakeSessions.reduce(0) { $0 + $1.duration } / 3600.0
                        let avgHR = awakeSessions.compactMap { $0.averageHeartRate }.reduce(0, +) / max(1, awakeSessions.compactMap { $0.averageHeartRate }.count)
                        let avgRR = awakeSessions.compactMap { $0.averageRespiratoryRate }.reduce(0, +) / max(1, awakeSessions.compactMap { $0.averageRespiratoryRate }.count)

                        let interruptionType = awakeSessions.contains { $0.duration / 60 > 5 || ($0.averageHeartRate ?? 0) > 80 || ($0.averageRespiratoryRate ?? 0) > 20 } ? "Major" : "Minor"

                        VStack(spacing: 4) {
                            Text("Awake")
                                .font(.caption)
                                .foregroundColor(.gray)
                            HStack(spacing: 2) {
                                Text(String(format: "%.1f h", totalAwakeDuration))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("(\(awakeSessions.count) times, \(interruptionType))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            // Optional short analysis
                            Text(interruptionType == "Major" ? "Frequent/long interruptions may reduce sleep quality." : "Brief interruptions—minimal impact on recovery.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
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
    switch period {
    case .lastNight:
        let minDate = earliest.map { calendar.startOfDay(for: $0) } ?? calendar.date(byAdding: .year, value: -5, to: today)!
        let maxDate = today
        return (minDate, maxDate)
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
        return (minDate, thisSunday)
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
        return (minDate, currentFirst)
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
        return (minDate, currentJan1)
    }
}
