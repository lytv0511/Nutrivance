// MARK: - Array average helper
extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
import SwiftUI
import Charts

struct HealthChartStatusDescriptor {
    let title: String
    let color: Color
    let detail: String?
}

struct HealthCard<ExpandedContent: View>: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    let trend: String?
    let color: Color
    let chartData: [(Date, Double)]
    let chartLabel: String
    let chartUnit: String
    let badgeText: String?
    let badgeColor: Color?
    let chartStatusProvider: ((Double) -> HealthChartStatusDescriptor?)?
    let customChartPreview: AnyView?
    let customChartSheet: AnyView?
    let expandedContent: () -> ExpandedContent

    @State private var expanded = false
    @State private var showChartSheet = false
    
    private var chartIdentity: String {
        let firstDate = chartData.first?.0.timeIntervalSince1970 ?? -1
        let lastDate = chartData.last?.0.timeIntervalSince1970 ?? -1
        let lastValue = chartData.last?.1 ?? -1
        return "\(title)|\(chartLabel)|\(chartUnit)|\(chartData.count)|\(firstDate)|\(lastDate)|\(lastValue)"
    }
    
    init(
        symbol: String,
        title: String,
        value: String,
        unit: String,
        trend: String? = nil,
        color: Color,
        chartData: [(Date, Double)],
        chartLabel: String,
        chartUnit: String,
        badgeText: String? = nil,
        badgeColor: Color? = nil,
        chartStatusProvider: ((Double) -> HealthChartStatusDescriptor?)? = nil,
        customChartPreview: AnyView? = nil,
        customChartSheet: AnyView? = nil,
        @ViewBuilder expandedContent: @escaping () -> ExpandedContent
    ) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.unit = unit
        self.trend = trend
        self.color = color
        self.chartData = chartData
        self.chartLabel = chartLabel
        self.chartUnit = chartUnit
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.chartStatusProvider = chartStatusProvider
        self.customChartPreview = customChartPreview
        self.customChartSheet = customChartSheet
        self.expandedContent = expandedContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        if let badgeText, let badgeColor {
                            Text(badgeText)
                                .font(.caption.bold())
                                .foregroundColor(badgeColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(badgeColor.opacity(0.14), in: Capsule())
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(color)
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .baselineOffset(2)
                    }
                    if let trend = trend {
                        Text(trend)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { withAnimation { expanded.toggle() }
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()}) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            Button {
                showChartSheet = true
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } label: {
                Group {
                    if let customChartPreview {
                        customChartPreview
                    } else {
                        HealthLineChartPreview(data: chartData, label: chartLabel, unit: chartUnit, color: color)
                            .id(chartIdentity)
                    }
                }
                .frame(height: 80)
                .padding(.trailing, 8)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showChartSheet) {
                Group {
                    if let customChartSheet {
                        customChartSheet
                    } else {
                        HealthLineChartSheet(
                            data: chartData,
                            label: chartLabel,
                            unit: chartUnit,
                            color: color,
                            statusProvider: chartStatusProvider
                        )
                            .id(chartIdentity)
                    }
                }
            }

            if expanded {
                Divider().padding(.vertical, 2)
                expandedContent()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1.2)
        )
        .shadow(color: color.opacity(0.08), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: expanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit). \(trend ?? "")")
    }
}

struct HeartRateZoneProfileSummaryView: View {
    let profile: HRZoneProfile
    var displayedMaxHR: Double? = nil
    var displayedRestingHR: Double? = nil
    var maxHRLabel: String = "Max HR"
    var restingHRLabel: String = "Resting HR"
    var schemaTitleOverride: String? = nil
    var descriptionOverride: String? = nil
    var showsDescription: Bool = true

    private var schemaTitle: String {
        schemaTitleOverride ?? profile.schema.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var schemaDescription: String {
        descriptionOverride ?? "Zones are calculated using the \(profile.schema.rawValue.replacingOccurrences(of: "_", with: " ").lowercased()) method and may update as new training data becomes available."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate Zones")
                .font(.subheadline)
                .bold()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schema")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(schemaTitle)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let maxHR = displayedMaxHR ?? profile.maxHR {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(maxHRLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(maxHR)) bpm")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let restingHR = displayedRestingHR ?? profile.restingHR {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(restingHRLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(restingHR)) bpm")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            if showsDescription {
                Text(schemaDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct HealthLineChartPreview: View {
    let data: [(Date, Double)]
    let label: String
    let unit: String
    let color: Color
    
    private var lastPoint: (Date, Double)? {
        data.last
    }
    
    var body: some View {
        Chart {
            ForEach(data, id: \ .0) { point in
                AreaMark(
                    x: .value("Date", point.0),
                    y: .value(label, point.1)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Date", point.0),
                    y: .value(label, point.1)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let lastPoint {
                PointMark(
                    x: .value("Date", lastPoint.0),
                    y: .value(label, lastPoint.1)
                )
                .foregroundStyle(color)
                .symbolSize(45)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}

struct HealthLineChartSheet: View {
    let data: [(Date, Double)]
    let label: String
    let unit: String
    let color: Color
    let statusProvider: ((Double) -> HealthChartStatusDescriptor?)?
    @State private var selected: (Date, Double)? = nil
    @Environment(\.dismiss) private var dismiss

    init(
        data: [(Date, Double)],
        label: String,
        unit: String,
        color: Color,
        statusProvider: ((Double) -> HealthChartStatusDescriptor?)? = nil
    ) {
        self.data = data
        self.label = label
        self.unit = unit
        self.color = color
        self.statusProvider = statusProvider
    }

    private static let fullDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return df
    }()
    
    private var showsPerformanceNote: Bool {
        ["Strain", "Effort", "Acute Load", "Session Load"].contains(label)
    }

    private struct SelectionCallout {
        let title: String
        let color: Color
        let detail: String?
    }

    private func genericCallout(for selection: (Date, Double)) -> SelectionCallout? {
        let minVal = data.map(\.1).min() ?? selection.1
        let maxVal = data.map(\.1).max() ?? selection.1
        let idx = data.firstIndex(where: { $0.0 == selection.0 && $0.1 == selection.1 }) ?? 0
        let prev = idx > 0 ? data[idx - 1].1 : selection.1
        let range = max(maxVal - minVal, 0.0001)

        if selection.1 == minVal {
            return SelectionCallout(title: "Minimum", color: .blue, detail: "Lowest value in the visible window.")
        }
        if selection.1 == maxVal {
            return SelectionCallout(title: "Maximum", color: .red, detail: "Highest value in the visible window.")
        }
        if showsPerformanceNote && abs(selection.1 - prev) > 0.15 * range {
            return SelectionCallout(title: "High Increase", color: .green, detail: "A sharp move versus the prior visible point.")
        }
        return nil
    }

    private func callout(for selection: (Date, Double)) -> SelectionCallout? {
        if let status = statusProvider?(selection.1) {
            return SelectionCallout(title: status.title, color: status.color, detail: status.detail)
        }
        return genericCallout(for: selection)
    }

    private func accentColor(for selection: (Date, Double)) -> Color {
        callout(for: selection)?.color ?? color
    }

    private func updateSelection(
        from location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard !data.isEmpty else {
            selected = nil
            return
        }

        let minX = plotFrame.minX - ChartInteractionSmoothing.horizontalTolerance
        let maxX = plotFrame.maxX + ChartInteractionSmoothing.horizontalTolerance
        guard location.x >= minX && location.x <= maxX else {
            selected = nil
            return
        }

        let safeMinX = plotFrame.minX + ChartInteractionSmoothing.horizontalInset
        let safeMaxX = max(safeMinX, plotFrame.maxX - ChartInteractionSmoothing.horizontalInset)
        let xPosition = min(max(location.x, safeMinX), safeMaxX) - plotFrame.minX

        let date = proxy.value(atX: xPosition) as Date?
            ?? ChartInteractionSmoothing.fallbackBoundaryDate(
                for: xPosition,
                plotFrame: plotFrame,
                data: data
            )
        guard let date else { return }

        guard let closest = data.min(by: {
            abs($0.0.timeIntervalSince1970 - date.timeIntervalSince1970) <
            abs($1.0.timeIntervalSince1970 - date.timeIntervalSince1970)
        }) else { return }

        if selected?.0 != closest.0 || selected?.1 != closest.1 {
            selected = closest
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundColor(color)
                        Text("Drag or hover anywhere across the chart to inspect a specific day.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let selected {
                        let accent = accentColor(for: selected)
                        let selectionCallout = callout(for: selected)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(selected.0, formatter: HealthLineChartSheet.fullDateFormatter)")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(String(format: "%.1f", selected.1))
                                            .font(.system(size: 42, weight: .bold, design: .rounded))
                                            .foregroundColor(accent)
                                        Text(unit)
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if let selectionCallout {
                                    Text(selectionCallout.title)
                                        .font(.caption.bold())
                                        .foregroundColor(selectionCallout.color)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectionCallout.color.opacity(0.15), in: Capsule())
                                }
                            }
                            if let detail = selectionCallout?.detail {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(accent.opacity(0.18), lineWidth: 1.2)
                        )
                    }

                    Chart {
                        ForEach(data, id: \.0) { point in
                            AreaMark(
                                x: .value("Date", point.0),
                                y: .value(label, point.1)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [color.opacity(0.22), color.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            LineMark(
                                x: .value("Date", point.0),
                                y: .value(label, point.1)
                            )
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(.init(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                        }
                        if let selected = selected {
                            let accent = accentColor(for: selected)
                            RuleMark(x: .value("Date", selected.0))
                                .foregroundStyle(accent.opacity(0.38))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4]))
                            PointMark(
                                x: .value("Date", selected.0),
                                y: .value(label, selected.1)
                            )
                            .symbolSize(135)
                            .foregroundStyle(accent)
                        }
                    }
                    .frame(height: 320)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day(), centered: true)
                                .font(.headline)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                                .font(.headline)
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
                                            updateSelection(from: value.location, proxy: proxy, geometry: geo)
                                        }
                                        .onEnded { _ in }
                                )
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        updateSelection(from: location, proxy: proxy, geometry: geo)
                                    case .ended:
                                        break
                                    }
                                }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(color.opacity(0.14), lineWidth: 1.1)
                    )
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), color.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if selected == nil {
                    selected = data.last
                }
            }
        }
    }
}
