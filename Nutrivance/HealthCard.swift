// MARK: - Array average helper
extension Array where Element == Double {
    func average() -> Double {
        guard !self.isEmpty else { return 0 }
        return self.reduce(0, +) / Double(self.count)
    }
}
import SwiftUI
import Charts

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
    let expandedContent: () -> ExpandedContent

    @State private var expanded = false

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
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
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
                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            // Chart is always visible
            HealthLineChart(data: chartData, label: chartLabel, unit: chartUnit, color: color)
                .frame(height: 80)
                .padding(.trailing, 8)

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

struct HealthLineChart: View {
    let data: [(Date, Double)]
    let label: String
    let unit: String
    let color: Color
    @State private var selected: (Date, Double)? = nil

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df
    }()
    
    var body: some View {
        ZStack {
            Chart {
                ForEach(data, id: \.0) { point in
                    LineMark(
                        x: .value("Date", point.0),
                        y: .value(label, point.1)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                    .accessibilityLabel("\(label)")
                    .accessibilityValue("\(point.1, specifier: "%.1f") \(unit)")
                }
                if let selected = selected {
                    PointMark(
                        x: .value("Date", selected.0),
                        y: .value(label, selected.1)
                    )
                    .symbolSize(80)
                    .foregroundStyle(.orange)
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
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geo[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    if let closest = data.min(by: { abs($0.0.timeIntervalSince1970 - date.timeIntervalSince1970) < abs($1.0.timeIntervalSince1970 - date.timeIntervalSince1970) }) {
                                        self.selected = closest
                                    }
                                }
                            }
                            .onEnded { _ in self.selected = nil }
                        )
                }
            }
            // Value label overlay
            if let selected = selected {
                VStack(spacing: 2) {
                    Text("\(selected.0, formatter: HealthLineChart.shortDateFormatter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(selected.1, specifier: "%.1f") \(unit)")
                        .font(.caption.bold())
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .shadow(radius: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 12)
                .padding(.top, 8)
            }
        }
    }
}
