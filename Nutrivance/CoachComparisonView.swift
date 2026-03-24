import SwiftUI
import Charts
import HealthKit
import UIKit

struct CoachSummaryInsight: Identifiable, Hashable {
    let id: String
    let snippet: String
    let metrics: [CoachMetricKey]
    let startDate: Date?
    let endDate: Date?
    let label: String
    let range: NSRange
}

enum CoachMetricKey: String, CaseIterable, Hashable {
    case strainScore
    case recoveryScore
    case readinessScore
    case hrv
    case restingHeartRate
    case sleepHours
    case sleepConsistency
    case sleepEfficiency
    case sleepHeartRate
    case respiratoryRate
    case wristTemperature
    case spO2
    case effort
    case sessionLoad
    case acuteLoad
    case chronicLoad
    case acwr
    case hrr
    case vo2Max
    case mets
    case power
    case cadence
    case zone4
    case zone5
    case peakHeartRate

    var displayName: String {
        switch self {
        case .strainScore: return "Strain Score"
        case .recoveryScore: return "Recovery Score"
        case .readinessScore: return "Readiness Score"
        case .hrv: return "HRV"
        case .restingHeartRate: return "Resting Heart Rate"
        case .sleepHours: return "Sleep Hours"
        case .sleepConsistency: return "Sleep Consistency"
        case .sleepEfficiency: return "Sleep Efficiency"
        case .sleepHeartRate: return "Sleep Heart Rate"
        case .respiratoryRate: return "Respiratory Rate"
        case .wristTemperature: return "Wrist Temperature"
        case .spO2: return "SpO₂"
        case .effort: return "Effort"
        case .sessionLoad: return "Session Load"
        case .acuteLoad: return "Acute Load"
        case .chronicLoad: return "Chronic Load"
        case .acwr: return "ACWR"
        case .hrr: return "HRR"
        case .vo2Max: return "VO₂ Max"
        case .mets: return "METs"
        case .power: return "Power"
        case .cadence: return "Cadence"
        case .zone4: return "Zone 4"
        case .zone5: return "Zone 5"
        case .peakHeartRate: return "Peak HR"
        }
    }

    var unit: String {
        switch self {
        case .strainScore, .recoveryScore, .readinessScore, .sleepEfficiency:
            return "%"
        case .hrv:
            return "ms"
        case .restingHeartRate, .sleepHeartRate, .hrr, .peakHeartRate:
            return "bpm"
        case .sleepHours:
            return "h"
        case .sleepConsistency:
            return "min"
        case .respiratoryRate:
            return "br/min"
        case .wristTemperature:
            return "°C"
        case .spO2:
            return "%"
        case .effort:
            return "/10"
        case .sessionLoad, .acuteLoad, .chronicLoad, .mets:
            return "pts"
        case .acwr:
            return ""
        case .vo2Max:
            return "ml/kg/min"
        case .power:
            return "W"
        case .cadence:
            return "rpm"
        case .zone4, .zone5:
            return "min"
        }
    }

    var color: Color {
        switch self {
        case .strainScore, .acuteLoad, .sessionLoad, .mets, .zone4, .zone5:
            return .orange
        case .recoveryScore, .readinessScore, .hrv:
            return .green
        case .restingHeartRate, .sleepHeartRate, .peakHeartRate:
            return .red
        case .sleepHours, .sleepConsistency, .sleepEfficiency:
            return .indigo
        case .respiratoryRate, .wristTemperature, .spO2:
            return .mint
        case .effort, .power, .cadence:
            return .blue
        case .chronicLoad, .acwr, .hrr, .vo2Max:
            return .purple
        }
    }

    var aliases: [String] {
        switch self {
        case .strainScore:
            return ["strain score", "strain"]
        case .recoveryScore:
            return ["recovery score", "recovery"]
        case .readinessScore:
            return ["readiness score", "readiness"]
        case .hrv:
            return ["hrv", "heart rate variability"]
        case .restingHeartRate:
            return ["resting heart rate", "resting hr", "rhr"]
        case .sleepHours:
            return ["sleep hours", "sleep duration", "hours of sleep", "sleep"]
        case .sleepConsistency:
            return ["sleep consistency", "sleep timing", "sleep regularity"]
        case .sleepEfficiency:
            return ["sleep efficiency"]
        case .sleepHeartRate:
            return ["sleep heart rate", "sleep hr"]
        case .respiratoryRate:
            return ["respiratory rate", "breathing rate"]
        case .wristTemperature:
            return ["wrist temperature", "temperature"]
        case .spO2:
            return ["spo2", "spo₂", "oxygen saturation"]
        case .effort:
            return ["effort", "effort score"]
        case .sessionLoad:
            return ["session load", "workout load", "load"]
        case .acuteLoad:
            return ["acute load"]
        case .chronicLoad:
            return ["chronic load"]
        case .acwr:
            return ["acwr", "acute to chronic", "acute-to-chronic"]
        case .hrr:
            return ["hrr", "heart rate recovery"]
        case .vo2Max:
            return ["vo2 max", "vo₂ max", "vo2"]
        case .mets:
            return ["mets", "met", "mets spikes", "met spikes"]
        case .power:
            return ["power", "cycling power", "running power"]
        case .cadence:
            return ["cadence"]
        case .zone4:
            return ["zone 4", "hr zone 4"]
        case .zone5:
            return ["zone 5", "hr zone 5"]
        case .peakHeartRate:
            return ["peak hr", "max hr", "peak heart rate", "max heart rate"]
        }
    }
}

struct CoachMetricSeries: Identifiable {
    let id: CoachMetricKey
    let title: String
    let unit: String
    let color: Color
    let data: [(Date, Double)]
}

private enum CoachComparisonFocusKind: String, Identifiable, CaseIterable {
    case average
    case maximum
    case total
    case trend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .average:
            return "Average"
        case .maximum:
            return "Peak"
        case .total:
            return "Total"
        case .trend:
            return "Trend"
        }
    }

    var icon: String {
        switch self {
        case .average:
            return "line.3.horizontal.decrease.circle"
        case .maximum:
            return "scope"
        case .total:
            return "sum"
        case .trend:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

private enum CoachTrendDirection {
    case up
    case down
    case flat

    var symbolName: String {
        switch self {
        case .up:
            return "arrow.up.right"
        case .down:
            return "arrow.down.right"
        case .flat:
            return "equal"
        }
    }

    var title: String {
        switch self {
        case .up:
            return "Uptrend"
        case .down:
            return "Downtrend"
        case .flat:
            return "Flat"
        }
    }
}

private struct CoachComparisonFocusPresentation: Identifiable {
    let kind: CoachComparisonFocusKind
    let title: String
    let chipValueText: String
    let explanation: String
    let zoomRange: ClosedRange<Date>?
    let averageValue: Double?
    let targetPoint: (Date, Double)?
    let totalValue: Double?
    let trendDirection: CoachTrendDirection?

    var id: CoachComparisonFocusKind { kind }
}

private struct CoachComparisonFloatingState: Identifiable, Equatable {
    let sourceMetric: CoachMetricKey
    let presentation: CoachComparisonFocusPresentation
    let color: Color

    var id: String {
        "\(sourceMetric.rawValue)-\(presentation.kind.rawValue)"
    }

    static func == (lhs: CoachComparisonFloatingState, rhs: CoachComparisonFloatingState) -> Bool {
        lhs.sourceMetric == rhs.sourceMetric &&
        lhs.presentation.id == rhs.presentation.id &&
        lhs.presentation.chipValueText == rhs.presentation.chipValueText &&
        lhs.presentation.explanation == rhs.presentation.explanation
    }
}

enum CoachSummaryNLP {
    static func detectInsights(
        in summary: String,
        anchorDate: Date,
        timeFilter: StrainRecoveryView.TimeFilter
    ) -> [CoachSummaryInsight] {
        let sentences = splitSentences(summary)
        let relationshipMarkers = [
            " vs ", " versus ", " compared", " comparison", " link", " relationship",
            " higher than ", " lower than ", " rose with ", " fell with ", " while ",
            " alongside ", " relative to ", " against ", " balance", " imbalance", " between "
        ]

        var insights: [CoachSummaryInsight] = []
        var seen = Set<String>()

        for sentence in sentences {
            let lower = sentence.text.lowercased()
            var detectedMetrics = CoachMetricKey.allCases.filter { metric in
                metric.aliases.contains { alias in lower.contains(alias) }
            }

            if lower.contains("heart rate") && !detectedMetrics.contains(.restingHeartRate) && !detectedMetrics.contains(.sleepHeartRate) && !detectedMetrics.contains(.peakHeartRate) {
                detectedMetrics.append(.peakHeartRate)
            }

            var dedupedMetrics: [CoachMetricKey] = []
            for metric in detectedMetrics where !dedupedMetrics.contains(metric) {
                dedupedMetrics.append(metric)
            }
            detectedMetrics = dedupedMetrics

            let hasRelationshipCue = relationshipMarkers.contains { lower.contains($0) }
            guard detectedMetrics.count >= 2 || (detectedMetrics.count == 1 && hasRelationshipCue) else {
                continue
            }

            let dateBounds = detectDateBounds(in: sentence.text, anchorDate: anchorDate, timeFilter: timeFilter)
            let key = detectedMetrics.map(\.rawValue).joined(separator: "|") + "|" + sentence.text
            guard seen.insert(key).inserted else { continue }

            insights.append(
                CoachSummaryInsight(
                    id: "coach-insight-\(insights.count)",
                    snippet: sentence.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    metrics: detectedMetrics,
                    startDate: dateBounds?.0,
                    endDate: dateBounds?.1,
                    label: relationshipLabel(for: sentence.text),
                    range: sentence.range
                )
            )
        }

        return insights
    }

    private struct SentenceSlice {
        let text: String
        let range: NSRange
    }

    private static func splitSentences(_ text: String) -> [SentenceSlice] {
        var result: [SentenceSlice] = []
        let nsText = text as NSString
        var sentenceStart = 0

        func isDigit(at index: Int) -> Bool {
            guard index >= 0, index < nsText.length else { return false }
            guard let scalar = UnicodeScalar(nsText.character(at: index)) else { return false }
            return CharacterSet.decimalDigits.contains(scalar)
        }

        func appendSentence(start: Int, endExclusive: Int) {
            guard endExclusive > start else { return }

            var trimmedStart = start
            var trimmedEnd = endExclusive

            while trimmedStart < trimmedEnd,
                  let scalar = UnicodeScalar(nsText.character(at: trimmedStart)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) {
                trimmedStart += 1
            }

            while trimmedEnd > trimmedStart,
                  let scalar = UnicodeScalar(nsText.character(at: trimmedEnd - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) {
                trimmedEnd -= 1
            }

            guard trimmedEnd > trimmedStart else { return }

            let range = NSRange(location: trimmedStart, length: trimmedEnd - trimmedStart)
            let snippet = nsText.substring(with: range)
            guard !snippet.isEmpty else { return }
            result.append(SentenceSlice(text: snippet, range: range))
        }

        for index in 0..<nsText.length {
            let character = nsText.character(at: index)
            let isSentenceBoundary: Bool

            switch character {
            case 10, 13:
                isSentenceBoundary = true
            case 46, 33, 63: // . ! ?
                let decimalBoundary = isDigit(at: index - 1) && isDigit(at: index + 1)
                isSentenceBoundary = !decimalBoundary
            default:
                isSentenceBoundary = false
            }

            guard isSentenceBoundary else { continue }
            let boundaryEnd = (character == 10 || character == 13) ? index : index + 1
            appendSentence(start: sentenceStart, endExclusive: boundaryEnd)
            sentenceStart = index + 1
        }

        appendSentence(start: sentenceStart, endExclusive: nsText.length)
        return result
    }

    private static func detectDateBounds(
        in text: String,
        anchorDate: Date,
        timeFilter: StrainRecoveryView.TimeFilter
    ) -> (Date, Date)? {
        let pattern = #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:\s*[-–]\s*(\d{1,2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM d yyyy"
        let year = Calendar.current.component(.year, from: anchorDate)

        var resolvedDates: [Date] = []
        for match in matches {
            guard
                let monthRange = Range(match.range(at: 1), in: text),
                let dayRange = Range(match.range(at: 2), in: text)
            else { continue }

            let month = String(text[monthRange]).prefix(3).capitalized
            let startDay = String(text[dayRange])
            if let date = formatter.date(from: "\(month) \(startDay) \(year)") {
                resolvedDates.append(Calendar.current.startOfDay(for: date))
            }

            if match.range(at: 3).location != NSNotFound,
               let endDayRange = Range(match.range(at: 3), in: text),
               let date = formatter.date(from: "\(month) \(text[endDayRange]) \(year)") {
                resolvedDates.append(Calendar.current.startOfDay(for: date))
            }
        }

        guard let start = resolvedDates.min(), let end = resolvedDates.max() else { return nil }
        return (start, end)
    }

    private static func relationshipLabel(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("good") || lower.contains("balanced") {
            return "Balanced"
        }
        if lower.contains("higher than") || lower.contains("outran") || lower.contains("over") {
            return "Above"
        }
        if lower.contains("lower than") || lower.contains("under") {
            return "Below"
        }
        if lower.contains("stable") {
            return "Stable"
        }
        return "Coach Highlight"
    }
}

struct CoachSummaryInteractiveText: View {
    let text: String
    let insights: [CoachSummaryInsight]
    let onSelect: (CoachSummaryInsight) -> Void

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        for insight in insights {
            if let stringRange = Range(insight.range, in: text),
               let attributedRange = Range(stringRange, in: attributed) {
                attributed[attributedRange].foregroundColor = .orange
                attributed[attributedRange].backgroundColor = Color.orange.opacity(0.12)
                attributed[attributedRange].underlineStyle = .single
                attributed[attributedRange].link = URL(string: "nutrivance-coach://comparison/\(insight.id)")
                continue
            }

            guard let attributedRange = attributed.range(of: insight.snippet) else {
                continue
            }
            attributed[attributedRange].foregroundColor = .orange
            attributed[attributedRange].backgroundColor = Color.orange.opacity(0.12)
            attributed[attributedRange].underlineStyle = .single
            attributed[attributedRange].link = URL(string: "nutrivance-coach://comparison/\(insight.id)")
        }
        return attributed
    }

    var body: some View {
        Text(attributedText)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "nutrivance-coach",
                      url.host == "comparison",
                      let id = url.pathComponents.last,
                      let insight = insights.first(where: { $0.id == id }) else {
                    return .systemAction
                }
                onSelect(insight)
                return .handled
            })
    }
}

struct CoachComparisonView: View {
    @ObservedObject var engine: HealthStateEngine
    let insight: CoachSummaryInsight
    let summaryText: String
    let timeFilter: StrainRecoveryView.TimeFilter
    let sportFilter: String?
    let anchorDate: Date

    @State private var selectedDate: Date? = nil
    @State private var floatingOverlayState: CoachComparisonFloatingState? = nil
    @State private var floatingOverlayPosition: CGPoint? = nil

    private var chartSeries: [CoachMetricSeries] {
        insight.metrics.compactMap {
            $0.makeSeries(
                engine: engine,
                timeFilter: timeFilter,
                sportFilter: sportFilter,
                anchorDate: anchorDate
            )
        }
        .filter { !$0.data.isEmpty }
    }

    private var snippetLowercased: String {
        insight.snippet.lowercased()
    }

    private var timeFilterContextText: String {
        switch timeFilter {
        case .day:
            return "This comparison is anchored to one day, so the chart keeps a week of surrounding context while still treating the selected day as the main point."
        case .week:
            return "This comparison is a weekly window, so the coach cue can point to a seven-day average, a weekly total, or the direction of the week-to-week trend."
        case .month:
            return "This comparison is a monthly window, so the coach cue should be read as a 30-day story: either the rolling average day, the total accumulated work, or the larger direction of the month."
        }
    }

    private var highlightRange: ClosedRange<Date>? {
        let calendar = Calendar.current
        if let start = insight.startDate {
            let end = insight.endDate ?? start
            return calendar.startOfDay(for: start)...calendar.startOfDay(for: end)
        }
        guard timeFilter == .day else { return nil }
        let day = calendar.startOfDay(for: anchorDate)
        return day...day
    }

    private var comparisonSupportText: String {
        if timeFilter == .day {
            return "The chart keeps a full week of surrounding data in view so the highlighted day has context. The tinted band marks the exact day the coach is emphasizing."
        }
        guard let highlightRange else {
            return "The coach note is supported by the related metric charts below. Scrub across the graph to inspect how the nearby data builds the point."
        }
        if Calendar.current.isDate(highlightRange.lowerBound, inSameDayAs: highlightRange.upperBound) {
            return "The tinted band marks the exact point the coach is talking about, while the surrounding trend shows what led into it."
        }
        return "The tinted band marks the exact window the coach is referencing, and the surrounding trend explains the lead-in and follow-through."
    }

    private var highlightWindow: DateInterval? {
        guard let highlightRange else { return nil }
        let calendar = Calendar.current
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: highlightRange.upperBound) ?? highlightRange.upperBound
        return DateInterval(start: highlightRange.lowerBound, end: endExclusive)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 18) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Coach Whiteboard")
                                        .font(.title2.bold())
                                    Text(insight.label)
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text(insight.snippet)
                                        .font(.body)
                                    Text(timeFilterContextText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(comparisonSupportText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let highlightRange {
                                        Text("Highlighted window: \(highlightRange.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \(highlightRange.upperBound.formatted(date: .abbreviated, time: .omitted)) • \(insight.label)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(18)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                )

                                ForEach(chartSeries) { series in
                                    CoachComparisonChartCard(
                                        series: series,
                                        selectedDate: $selectedDate,
                                        floatingOverlayState: $floatingOverlayState,
                                        floatingOverlayPosition: $floatingOverlayPosition,
                                        highlightRange: highlightRange,
                                        highlightWindow: highlightWindow,
                                        label: insight.label,
                                        supportingText: comparisonSupportText,
                                        timeFilter: timeFilter,
                                        snippet: insight.snippet
                                    )
                                }

                                if chartSeries.isEmpty {
                                    Text("No chart-ready metric series were found for this coach comparison yet.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(18)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                            }

                            if let floatingOverlayState {
                                CoachComparisonFloatingOverlay(
                                    presentation: floatingOverlayState.presentation,
                                    color: floatingOverlayState.color,
                                    position: $floatingOverlayPosition,
                                    canvasSize: geometry.size
                                )
                                .zIndex(100)
                            }
                        }
                        .padding()
                        .coordinateSpace(name: "comparisonCanvas")
                    }
                    .background(
                        GradientBackgrounds().burningGradient(animationPhase: .constant(16))
                    )
                    .background(
                        PencilSqueezeCatcher {
                            NotificationCenter.default.post(name: .coachComparisonPencilSqueeze, object: nil)
                        }
                    )

                }
            }
            .navigationTitle("Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ComparisonDismissButton()
                }
            }
            .onChange(of: floatingOverlayState) { _, newValue in
                guard newValue != nil else {
                    floatingOverlayPosition = nil
                    return
                }
            }
        }
    }
}

private struct CoachComparisonChartCard: View {
    let series: CoachMetricSeries
    @Binding var selectedDate: Date?
    @Binding var floatingOverlayState: CoachComparisonFloatingState?
    @Binding var floatingOverlayPosition: CGPoint?
    let highlightRange: ClosedRange<Date>?
    let highlightWindow: DateInterval?
    let label: String
    let supportingText: String
    let timeFilter: StrainRecoveryView.TimeFilter
    let snippet: String

    @State private var focusedKind: CoachComparisonFocusKind? = nil
    @State private var isInteractionPaletteExpanded = false
    @State private var isHoveringChart = false
    @State private var cardFrameInCanvas: CGRect = .zero
    @State private var hoverLocationInCanvas: CGPoint? = nil

    private var currentSelection: (Date, Double)? {
        guard let selectedDate else { return nil }
        return nearestPoint(in: series.data, to: selectedDate)
    }

    private var highlightedPoints: [(Date, Double)] {
        guard let highlightWindow else { return [] }
        let calendar = Calendar.current
        return series.data.filter { point in
            highlightWindow.contains(calendar.startOfDay(for: point.0))
        }
    }

    private var snippetLowercased: String {
        snippet.lowercased()
    }

    private var focusKinds: [CoachComparisonFocusKind] {
        let explicitKinds = detectedFocusKinds(
            in: snippetLowercased,
            supportsTotal: series.id.supportsTotalComparison
        )
        if !explicitKinds.isEmpty {
            return explicitKinds
        }

        switch timeFilter {
        case .day:
            return [.maximum, .trend]
        case .week:
            return series.id.supportsTotalComparison ? [.average, .total, .trend] : [.average, .trend]
        case .month:
            return series.id.supportsTotalComparison ? [.trend, .average, .total] : [.trend, .average]
        }
    }

    private var focusPresentations: [CoachComparisonFocusPresentation] {
        focusKinds.compactMap { focusPresentation(for: $0) }
    }

    private var activePresentation: CoachComparisonFocusPresentation? {
        guard let focusedKind else { return nil }
        return focusPresentations.first(where: { $0.kind == focusedKind })
    }

    private var chartDomain: ClosedRange<Date> {
        activePresentation?.zoomRange ?? fullDomain
    }

    private var fullDomain: ClosedRange<Date> {
        let firstDate = series.data.first?.0 ?? Date()
        let lastDate = series.data.last?.0 ?? firstDate
        return firstDate...lastDate
    }

    private var averagePresentation: CoachComparisonFocusPresentation? {
        focusPresentations.first(where: { $0.kind == .average })
    }

    private var maximumPresentation: CoachComparisonFocusPresentation? {
        focusPresentations.first(where: { $0.kind == .maximum })
    }

    private var totalPresentation: CoachComparisonFocusPresentation? {
        focusPresentations.first(where: { $0.kind == .total })
    }

    private var trendPresentation: CoachComparisonFocusPresentation? {
        focusPresentations.first(where: { $0.kind == .trend })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.title)
                        .font(.headline)
                    Text("Tap a focus chip to zoom into what the coach likely means, or scrub the chart to inspect the exact day.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if !focusPresentations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(focusPresentations) { presentation in
                            Button {
                                toggleFocus(presentation.kind)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: presentation.kind.icon)
                                    Text(presentation.title)
                                    Text(presentation.chipValueText)
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    (focusedKind == presentation.kind ? series.color.opacity(0.18) : Color.white.opacity(0.06)),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            focusedKind == presentation.kind ? series.color.opacity(0.9) : series.color.opacity(0.28),
                                            lineWidth: focusedKind == presentation.kind ? 1.5 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .opacity(isInteractionPaletteExpanded || focusedKind != nil ? 1 : 0.75)
            }

            Chart {
                if let highlightRange {
                    RectangleMark(
                        xStart: .value("Highlight Start", highlightRange.lowerBound),
                        xEnd: .value("Highlight End", highlightWindow?.end ?? highlightRange.upperBound),
                        yStart: .value("Min", series.data.map(\.1).min() ?? 0),
                        yEnd: .value("Max", series.data.map(\.1).max() ?? 1)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [series.color.opacity(0.24), series.color.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .annotation(position: .topLeading, alignment: .leading) {
                        Text(label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }

                if let averageValue = averagePresentation?.averageValue {
                    RuleMark(y: .value("Average", averageValue))
                        .foregroundStyle(series.color.opacity(0.5))
                        .lineStyle(.init(lineWidth: focusedKind == .average ? 2 : 1.2, dash: [5, 5]))
                        .annotation(position: .topTrailing, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text("Avg \(valueString(for: averageValue))")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                }

                ForEach(series.data, id: \.0) { point in
                    AreaMark(
                        x: .value("Date", point.0),
                        y: .value(series.title, point.1)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [series.color.opacity(0.28), series.color.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.0),
                        y: .value(series.title, point.1)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(.init(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                ForEach(highlightedPoints, id: \.0) { point in
                    PointMark(
                        x: .value("Highlighted Date", point.0),
                        y: .value(series.title, point.1)
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(80)
                }

                if let targetPoint = maximumPresentation?.targetPoint {
                    RuleMark(x: .value("Peak Date Line", targetPoint.0))
                        .foregroundStyle(series.color.opacity(0.22))
                        .lineStyle(.init(lineWidth: focusedKind == .maximum ? 1.8 : 1, dash: [3, 5]))

                    PointMark(
                        x: .value("Peak Date", targetPoint.0),
                        y: .value(series.title, targetPoint.1)
                    )
                    .foregroundStyle(series.color)
                    .symbol(.diamond)
                    .symbolSize(focusedKind == .maximum ? 180 : 120)
                    .annotation(position: .top, spacing: 10, overflowResolution: .init(x: .fit, y: .disabled)) {
                        Text("\(isMinimumCue(in: snippetLowercased) ? "Low" : "Peak") \(valueString(for: targetPoint.1))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }

                if let selection = currentSelection {
                    RuleMark(x: .value("Selected Date", selection.0))
                        .foregroundStyle(series.color.opacity(0.38))
                        .lineStyle(.init(lineWidth: 1, dash: [4]))
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selection.0, format: .dateTime.month().day())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(valueString(for: selection.1))
                                    .font(.caption.bold())
                                    .foregroundColor(series.color)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                    PointMark(
                        x: .value("Selected Date", selection.0),
                        y: .value(series.title, selection.1)
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(110)
                }
            }
            .frame(height: 220)
            .chartXScale(domain: chartDomain)
            .scaleEffect(focusedKind == nil ? 1 : 1.015)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isInteractionPaletteExpanded = true
                                    isHoveringChart = true
                                    updateSelection(from: value.location, proxy: proxy, geometry: geo)
                                }
                                .onEnded { _ in
                                    selectedDate = nil
                                    isHoveringChart = false
                                    if focusedKind == nil {
                                        isInteractionPaletteExpanded = false
                                    }
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                isInteractionPaletteExpanded = true
                                isHoveringChart = true
                                updateSelection(from: location, proxy: proxy, geometry: geo)
                            case .ended:
                                selectedDate = nil
                                isHoveringChart = false
                                if focusedKind == nil {
                                    isInteractionPaletteExpanded = false
                                }
                            }
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let trendDirection = trendPresentation?.trendDirection {
                    HStack(spacing: 6) {
                        Image(systemName: trendDirection.symbolName)
                        Text(trendDirection.title)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(series.color.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
                    .offset(y: activePresentation == nil ? 0 : 72)
                }
            }
            .animation(.interactiveSpring(response: 0.44, dampingFraction: 0.76, blendDuration: 0.14), value: focusedKind)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.12), value: chartDomain.lowerBound)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.12), value: chartDomain.upperBound)
            .onReceive(NotificationCenter.default.publisher(for: .coachComparisonPencilSqueeze)) { _ in
                if focusedKind != nil {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.12)) {
                        focusedKind = nil
                    }
                    if floatingOverlayState?.sourceMetric == series.id {
                        floatingOverlayState = nil
                    }
                    return
                }

                guard isHoveringChart, let defaultFocus = focusPresentations.first?.kind else { return }
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.7, blendDuration: 0.12)) {
                    focusedKind = defaultFocus
                    if let hoverLocationInCanvas {
                        floatingOverlayPosition = CGPoint(
                            x: hoverLocationInCanvas.x + 130,
                            y: hoverLocationInCanvas.y + 10
                        )
                    } else {
                        floatingOverlayPosition = defaultOverlayPosition()
                    }
                }
            }

            if let selection = currentSelection {
                HStack {
                    Text(selection.0.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(valueString(for: selection.1))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(series.color)
                }
            }

            if let totalPresentation {
                HStack {
                    Text("Integrated \(timeFilter.rawValue) total")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(totalPresentation.chipValueText)
                        .font(.caption.weight(.bold))
                        .foregroundColor(series.color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(series.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(supportingText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(series.color.opacity(0.22), lineWidth: 1)
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        cardFrameInCanvas = geo.frame(in: .named("comparisonCanvas"))
                    }
                    .onChange(of: geo.frame(in: .named("comparisonCanvas"))) { _, newValue in
                        cardFrameInCanvas = newValue
                    }
            }
        )
        .onChange(of: focusedKind) { _, newValue in
            guard let newValue,
                  let presentation = focusPresentations.first(where: { $0.kind == newValue }) else {
                if floatingOverlayState?.sourceMetric == series.id {
                    floatingOverlayState = nil
                }
                return
            }

            floatingOverlayState = CoachComparisonFloatingState(
                sourceMetric: series.id,
                presentation: presentation,
                color: series.color
            )
            if floatingOverlayPosition == nil {
                floatingOverlayPosition = defaultOverlayPosition()
            }
        }
    }

    private func valueString(for value: Double) -> String {
        if series.unit.isEmpty {
            return String(format: "%.2f", value)
        }
        if series.unit == "%" || series.unit == "min" || series.unit == "bpm" || series.unit == "W" || series.unit == "rpm" || series.unit == "pts" {
            return String(format: "%.0f %@", value, series.unit)
        }
        return String(format: "%.1f %@", value, series.unit)
    }

    private func nearestPoint(in data: [(Date, Double)], to date: Date) -> (Date, Double)? {
        data.min { lhs, rhs in
            abs(lhs.0.timeIntervalSince(date)) < abs(rhs.0.timeIntervalSince(date))
        }
    }

    private func updateSelection(from location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard let xPosition = ChartInteractionSmoothing.clampedXPosition(
            for: location,
            plotFrame: plotFrame
        ) else {
            selectedDate = nil
            return
        }

        let date = proxy.value(atX: xPosition) as Date?
            ?? ChartInteractionSmoothing.fallbackBoundaryDate(
                for: xPosition,
                plotFrame: plotFrame,
                data: series.data
            )
        let overlayFrame = geometry.frame(in: .named("comparisonCanvas"))
        hoverLocationInCanvas = CGPoint(
            x: overlayFrame.minX + location.x,
            y: overlayFrame.minY + location.y
        )
        guard let date else { return }
        if let closest = nearestPoint(in: series.data, to: date) {
            if selectedDate != closest.0 {
                selectedDate = closest.0
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func toggleFocus(_ kind: CoachComparisonFocusKind) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.7, blendDuration: 0.12)) {
            if focusedKind == kind {
                focusedKind = nil
                if floatingOverlayState?.sourceMetric == series.id {
                    floatingOverlayState = nil
                }
                if hoverLocationInCanvas == nil {
                    floatingOverlayPosition = nil
                }
            } else {
                focusedKind = kind
                isInteractionPaletteExpanded = true
                floatingOverlayPosition = defaultOverlayPosition()
                if let targetDate = focusPresentations.first(where: { $0.kind == kind })?.targetPoint?.0 {
                    selectedDate = targetDate
                }
            }
        }
    }

    private func defaultOverlayPosition() -> CGPoint {
        CGPoint(
            x: max(cardFrameInCanvas.minX + 150, cardFrameInCanvas.maxX - 145),
            y: cardFrameInCanvas.minY + 120
        )
    }

    private func focusPresentation(for kind: CoachComparisonFocusKind) -> CoachComparisonFocusPresentation? {
        switch kind {
        case .average:
            let averageValue = series.data.map(\.1).average
            guard let averageValue else { return nil }
            return CoachComparisonFocusPresentation(
                kind: .average,
                title: "\(timeFilter.rawValue) Average",
                chipValueText: valueString(for: averageValue),
                explanation: "\(series.title) is being read as an average across the \(timeFilter.rawValue) window here, so the dotted line shows the level the coach is describing rather than one isolated day.",
                zoomRange: contextualZoomRange(around: highlightRange?.lowerBound ?? series.data.last?.0, preferredVisiblePoints: timeFilter == .month ? 12 : 5),
                averageValue: averageValue,
                targetPoint: nil,
                totalValue: nil,
                trendDirection: nil
            )
        case .maximum:
            guard let targetPoint = isMinimumCue(in: snippetLowercased)
                ? series.data.min(by: { $0.1 < $1.1 })
                : series.data.max(by: { $0.1 < $1.1 }) else {
                return nil
            }
            let title = isMinimumCue(in: snippetLowercased) ? "Lowest Point" : "Peak Point"
            return CoachComparisonFocusPresentation(
                kind: .maximum,
                title: title,
                chipValueText: valueString(for: targetPoint.1),
                explanation: "\(title) is marked directly on the chart so you can see the exact point the coach is anchoring to and the days wrapped around it.",
                zoomRange: contextualZoomRange(around: targetPoint.0, preferredVisiblePoints: timeFilter == .month ? 9 : 5),
                averageValue: nil,
                targetPoint: targetPoint,
                totalValue: nil,
                trendDirection: nil
            )
        case .total:
            guard series.id.supportsTotalComparison else { return nil }
            let totalValue = series.data.map(\.1).reduce(0, +)
            return CoachComparisonFocusPresentation(
                kind: .total,
                title: "\(timeFilter.rawValue) Total",
                chipValueText: valueString(for: totalValue),
                explanation: "This cue reads \(series.title.lowercased()) as accumulated exposure across the displayed window, so the value below the chart sums the visible curve rather than pointing to one day.",
                zoomRange: contextualZoomRange(around: series.data.last?.0, preferredVisiblePoints: timeFilter == .month ? 14 : 7),
                averageValue: nil,
                targetPoint: nil,
                totalValue: totalValue,
                trendDirection: nil
            )
        case .trend:
            let direction = derivedTrendDirection(for: series.data)
            let delta = (series.data.last?.1 ?? 0) - (series.data.first?.1 ?? 0)
            return CoachComparisonFocusPresentation(
                kind: .trend,
                title: "\(timeFilter.rawValue) Trend",
                chipValueText: signedValueString(for: delta),
                explanation: "The faint trend marker summarizes the overall direction of \(series.title.lowercased()) across this \(timeFilter.rawValue) window, so you can see whether the coach is describing climb, fade, or stability.",
                zoomRange: contextualZoomRange(around: series.data.last?.0, preferredVisiblePoints: timeFilter == .month ? 15 : 7),
                averageValue: nil,
                targetPoint: nil,
                totalValue: nil,
                trendDirection: direction
            )
        }
    }

    private func contextualZoomRange(around centerDate: Date?, preferredVisiblePoints: Int) -> ClosedRange<Date>? {
        guard let centerDate,
              let centerIndex = series.data.firstIndex(where: { Calendar.current.isDate($0.0, inSameDayAs: centerDate) }) ?? nearestIndex(to: centerDate) else {
            return nil
        }

        let halfWindow = max(1, preferredVisiblePoints / 2)
        let lowerBound = max(0, centerIndex - halfWindow)
        let upperBound = min(series.data.count - 1, centerIndex + halfWindow)
        guard lowerBound < upperBound else { return nil }
        return series.data[lowerBound].0...series.data[upperBound].0
    }

    private func nearestIndex(to date: Date) -> Int? {
        guard let point = nearestPoint(in: series.data, to: date) else { return nil }
        return series.data.firstIndex(where: { $0.0 == point.0 && $0.1 == point.1 })
    }

    private func signedValueString(for value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        if series.unit.isEmpty {
            return "\(prefix)\(String(format: "%.2f", value))"
        }
        if series.unit == "%" || series.unit == "min" || series.unit == "bpm" || series.unit == "W" || series.unit == "rpm" || series.unit == "pts" {
            return "\(prefix)\(String(format: "%.0f", value)) \(series.unit)"
        }
        return "\(prefix)\(String(format: "%.1f", value)) \(series.unit)"
    }
}

@MainActor
private extension CoachMetricKey {
    func makeSeries(
        engine: HealthStateEngine,
        timeFilter: StrainRecoveryView.TimeFilter,
        sportFilter: String?,
        anchorDate: Date
    ) -> CoachMetricSeries? {
        let data = buildData(engine: engine, timeFilter: timeFilter, sportFilter: sportFilter, anchorDate: anchorDate)
        guard !data.isEmpty else { return nil }
        return CoachMetricSeries(id: self, title: displayName, unit: unit, color: color, data: data)
    }

    func buildData(
        engine: HealthStateEngine,
        timeFilter: StrainRecoveryView.TimeFilter,
        sportFilter: String?,
        anchorDate: Date
    ) -> [(Date, Double)] {
        let window = comparisonWindow(for: timeFilter, anchorDate: anchorDate)
        switch self {
        case .hrv:
            return filterComparisonSeries(Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) }), window: window)
        case .restingHeartRate:
            return filterComparisonSeries(engine.dailyRestingHeartRate, window: window)
        case .sleepHours:
            return filterComparisonSeries(engine.dailySleepDuration, window: window)
        case .sleepEfficiency:
            return filterComparisonSeries(engine.sleepEfficiency.mapValues { $0 * 100 }, window: window)
        case .sleepConsistency:
            return sleepConsistencySeries(engine: engine, window: window)
        case .sleepHeartRate:
            return filterComparisonSeries(engine.dailySleepHeartRate, window: window)
        case .respiratoryRate:
            return filterComparisonSeries(engine.respiratoryRate, window: window)
        case .wristTemperature:
            return filterComparisonSeries(engine.wristTemperature, window: window)
        case .spO2:
            return filterComparisonSeries(engine.spO2, window: window)
        case .effort:
            return filterComparisonSeries(engine.effortRating, window: window)
        case .recoveryScore:
            return estimatedRecoverySeries(engine: engine, window: window)
        case .strainScore:
            return derivedLoadSnapshots(engine: engine, sportFilter: sportFilter, window: window).map { ($0.date, $0.strainScore) }
        case .readinessScore:
            let strain = Dictionary(uniqueKeysWithValues: derivedLoadSnapshots(engine: engine, sportFilter: sportFilter, window: window).map { ($0.date, $0.strainScore) })
            let recovery = Dictionary(uniqueKeysWithValues: estimatedRecoverySeries(engine: engine, window: window))
            return mergeSeriesDates(window: window) { date in
                guard let strainValue = strain[date], let recoveryValue = recovery[date] else { return nil }
                return max(0, min(100, recoveryValue * 0.7 - strainValue * 0.25 + 35))
            }
        case .sessionLoad:
            return derivedLoadSnapshots(engine: engine, sportFilter: sportFilter, window: window).map { ($0.date, $0.sessionLoad) }
        case .acuteLoad:
            return derivedLoadSnapshots(engine: engine, sportFilter: sportFilter, window: window).map { ($0.date, $0.acuteLoad) }
        case .chronicLoad:
            return derivedLoadSnapshots(engine: engine, sportFilter: sportFilter, window: window).map { ($0.date, $0.chronicLoad) }
        case .acwr:
            return derivedLoadSnapshots(engine: engine, sportFilter: sportFilter, window: window).map { ($0.date, $0.acwr) }
        case .hrr:
            return filterComparisonSeries(engine.dailyHRRAggregates, window: window)
        case .vo2Max:
            return filterComparisonSeries(engine.dailyVO2Aggregates, window: window)
        case .mets:
            return filterComparisonSeries(engine.dailyMETAggregates, window: window)
        case .power:
            return workoutAggregateSeries(engine: engine, sportFilter: sportFilter, window: window) { analytics in
                let values = analytics.powerSeries.map(\.1).filter { $0 > 0 }
                return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
        case .cadence:
            return workoutAggregateSeries(engine: engine, sportFilter: sportFilter, window: window) { analytics in
                let values = analytics.cadenceSeries.map(\.1).filter { $0 > 0 }
                return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
        case .zone4:
            return workoutAggregateSeries(engine: engine, sportFilter: sportFilter, window: window) { analytics in
                (analytics.hrZoneBreakdown.first(where: { $0.zone.zoneNumber == 4 })?.timeInZone ?? 0) / 60.0
            }
        case .zone5:
            return workoutAggregateSeries(engine: engine, sportFilter: sportFilter, window: window) { analytics in
                (analytics.hrZoneBreakdown.first(where: { $0.zone.zoneNumber == 5 })?.timeInZone ?? 0) / 60.0
            }
        case .peakHeartRate:
            return workoutAggregateSeries(engine: engine, sportFilter: sportFilter, window: window) { analytics in
                analytics.peakHR
            }
        }
    }
}

private struct DerivedLoadPoint {
    let date: Date
    let sessionLoad: Double
    let acuteLoad: Double
    let chronicLoad: Double
    let acwr: Double
    let strainScore: Double
}

private func comparisonWindow(
    for timeFilter: StrainRecoveryView.TimeFilter,
    anchorDate: Date
) -> (start: Date, end: Date, endExclusive: Date) {
    let calendar = Calendar.current
    let end = calendar.startOfDay(for: anchorDate)
    let dayCount: Int
    switch timeFilter {
    case .day:
        dayCount = 7
    case .week:
        dayCount = 7
    case .month:
        dayCount = 30
    }
    let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) ?? end
    let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    return (start, end, endExclusive)
}

private func filterComparisonSeries(
    _ values: [Date: Double],
    window: (start: Date, end: Date, endExclusive: Date)
) -> [(Date, Double)] {
    values
        .filter { date, value in
            date >= window.start && date <= window.end && value != 0
        }
        .sorted { $0.0 < $1.0 }
}

@MainActor
private func sleepConsistencySeries(
    engine: HealthStateEngine,
    window: (start: Date, end: Date, endExclusive: Date)
) -> [(Date, Double)] {
    let ordered = engine.sleepMidpointHours
        .filter { $0.key >= window.start && $0.key <= window.end }
        .sorted { $0.key < $1.key }

    guard !ordered.isEmpty else { return [] }
    var result: [(Date, Double)] = []
    for index in ordered.indices {
        let startIndex = max(0, index - 2)
        let slice = ordered[startIndex...index].map(\.value)
        let mean = slice.reduce(0, +) / Double(slice.count)
        let variance = slice.map { pow(($0 - mean) * 60, 2) }.reduce(0, +) / Double(slice.count)
        result.append((ordered[index].key, sqrt(variance)))
    }
    return result
}

@MainActor
private func estimatedRecoverySeries(
    engine: HealthStateEngine,
    window: (start: Date, end: Date, endExclusive: Date)
) -> [(Date, Double)] {
    let hrvDict = Dictionary(uniqueKeysWithValues: engine.dailyHRV.map { ($0.date, $0.average) })
    return mergeSeriesDates(window: window) { date in
        let hrv = hrvDict[date]
        let rhr = engine.dailyRestingHeartRate[date]
        let sleep = engine.dailySleepDuration[date]
        guard hrv != nil || rhr != nil || sleep != nil else { return nil }

        var score = 0.0
        if let hrv, let baseline = engine.hrvBaseline7Day, baseline > 0 {
            score += normalizedSignal(value: hrv, baseline: baseline, higherIsBetter: true) * 0.4
        } else {
            score += 20
        }
        if let rhr, let baseline = engine.rhrBaseline7Day, baseline > 0 {
            score += normalizedSignal(value: rhr, baseline: baseline, higherIsBetter: false) * 0.25
        } else {
            score += 12.5
        }
        if let sleep {
            let normalizedSleep = max(0, min(100, (sleep / 8.0) * 100))
            score += normalizedSleep * 0.25
        } else {
            score += 12.5
        }
        score += 10
        return min(100, max(0, score))
    }
}

private func normalizedSignal(value: Double, baseline: Double, higherIsBetter: Bool) -> Double {
    guard baseline != 0 else { return 50 }
    let deviation = higherIsBetter ? (value - baseline) / baseline : (baseline - value) / baseline
    return max(0, min(100, (deviation * 150) + 50))
}

private func mergeSeriesDates(
    window: (start: Date, end: Date, endExclusive: Date),
    transform: (Date) -> Double?
) -> [(Date, Double)] {
    let dates = comparisonDateSequence(from: window.start, to: window.end)
    return dates.compactMap { date in
        transform(date).map { (date, $0) }
    }
}

private func comparisonDateSequence(from start: Date, to end: Date) -> [Date] {
    let calendar = Calendar.current
    let safeStart = calendar.startOfDay(for: start)
    let safeEnd = calendar.startOfDay(for: end)
    guard safeStart <= safeEnd else { return [] }
    let count = (calendar.dateComponents([.day], from: safeStart, to: safeEnd).day ?? 0) + 1
    return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: safeStart) }
}

private func detectedFocusKinds(
    in snippet: String,
    supportsTotal: Bool
) -> [CoachComparisonFocusKind] {
    var kinds: [CoachComparisonFocusKind] = []

    let averageKeywords = ["average", "avg", "mean", "baseline", "typical"]
    let maxKeywords = ["max", "maximum", "highest", "peak", "spike", "top", "lowest", "minimum", "bottom"]
    let totalKeywords = ["total", "sum", "overall", "accumulated", "cumulative", "combined"]
    let trendKeywords = ["trend", "trending", "rising", "climbing", "improving", "dropping", "falling", "declining", "stable", "flat", "holding", "direction"]

    if averageKeywords.contains(where: snippet.contains) {
        kinds.append(.average)
    }
    if maxKeywords.contains(where: snippet.contains) {
        kinds.append(.maximum)
    }
    if supportsTotal && totalKeywords.contains(where: snippet.contains) {
        kinds.append(.total)
    }
    if trendKeywords.contains(where: snippet.contains) {
        kinds.append(.trend)
    }

    if kinds.isEmpty {
        kinds.append(.trend)
    }

    return kinds.removingDuplicates()
}

private func isMinimumCue(in snippet: String) -> Bool {
    ["lowest", "minimum", "bottom", "dip", "drop", "suppressed"].contains(where: snippet.contains)
}

private func derivedTrendDirection(for data: [(Date, Double)]) -> CoachTrendDirection {
    guard data.count >= 2 else { return .flat }
    let firstSlice = Array(data.prefix(max(1, data.count / 3))).map(\.1)
    let lastSlice = Array(data.suffix(max(1, data.count / 3))).map(\.1)
    let firstAverage = firstSlice.reduce(0, +) / Double(firstSlice.count)
    let lastAverage = lastSlice.reduce(0, +) / Double(lastSlice.count)
    let span = max(1, abs(data.map(\.1).max() ?? 0 - (data.map(\.1).min() ?? 0)))
    let normalizedDelta = (lastAverage - firstAverage) / span

    if normalizedDelta > 0.08 {
        return .up
    }
    if normalizedDelta < -0.08 {
        return .down
    }
    return .flat
}

private extension CoachMetricKey {
    var supportsTotalComparison: Bool {
        switch self {
        case .sleepHours, .effort, .sessionLoad, .mets, .zone4, .zone5:
            return true
        default:
            return false
        }
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private struct ComparisonDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") {
            dismiss()
        }
        .font(.body.weight(.semibold))
    }
}

private struct CoachComparisonFloatingOverlay: View {
    let presentation: CoachComparisonFocusPresentation
    let color: Color
    @Binding var position: CGPoint?
    let canvasSize: CGSize

    @GestureState private var dragTranslation: CGSize = .zero

    private let overlaySize = CGSize(width: 240, height: 150)

    private var resolvedPosition: CGPoint {
        position ?? CGPoint(
            x: max(overlaySize.width / 2 + 16, canvasSize.width - (overlaySize.width / 2) - 20),
            y: max(overlaySize.height / 2 + 24, 140)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: presentation.kind.icon)
                    .foregroundColor(color)
                Text("\(presentation.title) Focus")
                    .font(.caption.weight(.bold))
                Spacer()
                Text(presentation.chipValueText)
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
            }

            Text(presentation.explanation)
                .font(.subheadline)
                .foregroundColor(.primary)

            Text("Drag this card anywhere on the canvas. Tap the active chip again, or use Apple Pencil squeeze, to zoom back out.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: overlaySize.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.14), radius: 14, x: 0, y: 8)
        .position(
            x: clampedPosition(
                x: resolvedPosition.x + dragTranslation.width,
                y: resolvedPosition.y + dragTranslation.height
            ).x,
            y: clampedPosition(
                x: resolvedPosition.x + dragTranslation.width,
                y: resolvedPosition.y + dragTranslation.height
            ).y
        )
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    position = clampedPosition(
                        x: resolvedPosition.x + value.translation.width,
                        y: resolvedPosition.y + value.translation.height
                    )
                }
        )
        .onAppear {
            if position == nil {
                position = resolvedPosition
            }
        }
    }

    private func clampedPosition(x: CGFloat, y: CGFloat) -> CGPoint {
        let halfWidth = overlaySize.width / 2
        let halfHeight = overlaySize.height / 2
        return CGPoint(
            x: min(max(x, halfWidth + 12), max(halfWidth + 12, canvasSize.width - halfWidth - 12)),
            y: min(max(y, halfHeight + 12), max(halfHeight + 12, canvasSize.height - halfHeight - 12))
        )
    }
}

private struct PencilSqueezeCatcher: UIViewRepresentable {
    let onSqueeze: () -> Void

    func makeUIView(context: Context) -> PencilSqueezeView {
        PencilSqueezeView(onSqueeze: onSqueeze)
    }

    func updateUIView(_ uiView: PencilSqueezeView, context: Context) {
        uiView.onSqueeze = onSqueeze
    }
}

private final class PencilSqueezeView: UIView, UIPencilInteractionDelegate {
    var onSqueeze: () -> Void

    init(onSqueeze: @escaping () -> Void) {
        self.onSqueeze = onSqueeze
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        if #available(iOS 17.5, *) {
            addInteraction(UIPencilInteraction(delegate: self))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        onSqueeze()
    }
}

private extension Notification.Name {
    static let coachComparisonPencilSqueeze = Notification.Name("coachComparisonPencilSqueeze")
}

@MainActor
private func derivedLoadSnapshots(
    engine: HealthStateEngine,
    sportFilter: String?,
    window: (start: Date, end: Date, endExclusive: Date)
) -> [DerivedLoadPoint] {
    let calendar = Calendar.current
    let workouts = engine.workoutAnalytics.filter { pair in
        pair.workout.startDate < window.endExclusive &&
        pair.workout.startDate >= calendar.date(byAdding: .day, value: -27, to: window.start) ?? window.start &&
        (sportFilter == nil || pair.workout.workoutActivityType.name == sportFilter)
    }

    var loadByDay: [Date: Double] = [:]
    for pair in workouts {
        let day = calendar.startOfDay(for: pair.workout.startDate)
        loadByDay[day, default: 0] += max(0, comparisonWorkoutSessionLoad(for: pair.workout, analytics: pair.analytics))
    }

    let dates = comparisonDateSequence(
        from: calendar.date(byAdding: .day, value: -27, to: window.start) ?? window.start,
        to: window.end
    )
    let loads = dates.map { loadByDay[$0, default: 0] }

    func ewma(_ values: ArraySlice<Double>, lambda: Double) -> Double {
        var avg = 0.0
        for value in values {
            avg = lambda * value + (1 - lambda) * avg
        }
        return avg
    }

    var derived: [DerivedLoadPoint] = []
    for index in dates.indices {
        let date = dates[index]
        let sevenStart = max(0, index - 6)
        let acute = ewma(loads[sevenStart...index], lambda: 2.0 / 8.0)
        let chronic = ewma(loads[0...index], lambda: 2.0 / 29.0)
        let acwr = chronic > 0 ? acute / chronic : 0
        let strainScore: Double
        switch acwr {
        case ..<0.8: strainScore = 30
        case 0.8..<1.3: strainScore = 50
        case 1.3..<1.5: strainScore = 75
        default: strainScore = 95
        }
        if date >= window.start && date <= window.end {
            derived.append(
                DerivedLoadPoint(
                    date: date,
                    sessionLoad: loads[index],
                    acuteLoad: acute,
                    chronicLoad: chronic,
                    acwr: acwr,
                    strainScore: strainScore
                )
            )
        }
    }
    return derived
}

@MainActor
private func workoutAggregateSeries(
    engine: HealthStateEngine,
    sportFilter: String?,
    window: (start: Date, end: Date, endExclusive: Date),
    metric: (WorkoutAnalytics) -> Double?
) -> [(Date, Double)] {
    let calendar = Calendar.current
    let filtered = engine.workoutAnalytics.filter { pair in
        pair.workout.startDate >= window.start &&
        pair.workout.startDate < window.endExclusive &&
        (sportFilter == nil || pair.workout.workoutActivityType.name == sportFilter)
    }

    let grouped = Dictionary(grouping: filtered, by: { calendar.startOfDay(for: $0.workout.startDate) })
    return grouped.compactMap { date, items in
        let values = items.compactMap { metric($0.analytics) }.filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return (date, values.reduce(0, +) / Double(values.count))
    }
    .sorted { $0.0 < $1.0 }
}

private func comparisonWorkoutSessionLoad(for workout: HKWorkout, analytics: WorkoutAnalytics) -> Double {
    let zoneWeightedLoad = analytics.hrZoneBreakdown.reduce(0.0) { partial, entry in
        let zoneWeight = Double(min(max(entry.zone.zoneNumber, 1), 5))
        let zoneMinutes = entry.timeInZone / 60.0
        return partial + (zoneMinutes * zoneWeight)
    }

    if zoneWeightedLoad > 0 {
        return zoneWeightedLoad.rounded()
    }

    let durationMinutes = workout.duration / 60.0
    let powerValues = analytics.powerSeries.map(\.1).filter { $0 > 0 }
    if !powerValues.isEmpty {
        let averagePower = powerValues.reduce(0, +) / Double(powerValues.count)
        return max(durationMinutes, (durationMinutes * max(1.0, averagePower / 100)).rounded())
    }

    return durationMinutes.rounded()
}
