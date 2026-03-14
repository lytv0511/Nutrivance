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
    @State private var showChartSheet = false

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
                HealthLineChartPreview(data: chartData, label: chartLabel, unit: chartUnit, color: color)
                    .frame(height: 80)
                    .padding(.trailing, 8)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showChartSheet) {
                HealthLineChartSheet(data: chartData, label: chartLabel, unit: chartUnit, color: color)
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

struct HealthLineChartPreview: View {
    let data: [(Date, Double)]
    let label: String
    let unit: String
    let color: Color
    var body: some View {
        Chart {
            ForEach(data, id: \ .0) { point in
                LineMark(
                    x: .value("Date", point.0),
                    y: .value(label, point.1)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .symbol(Circle())
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
    @State private var selected: (Date, Double)? = nil

    private static let fullDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return df
    }()

    var body: some View {
        VStack(spacing: 16) {
            Text(label)
                .font(.title.bold())
                .foregroundColor(color)
            Chart {
                ForEach(data, id: \ .0) { point in
                    LineMark(
                        x: .value("Date", point.0),
                        y: .value(label, point.1)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                }
                if let selected = selected {
                    PointMark(
                        x: .value("Date", selected.0),
                        y: .value(label, selected.1)
                    )
                    .symbolSize(120)
                    .foregroundStyle(.orange)
                }
            }
            .frame(height: 260)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                        .font(.headline)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.headline)
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
                                        if self.selected?.0 != closest.0 || self.selected?.1 != closest.1 {
                                            self.selected = closest
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.impactOccurred()
                                        }
                                    }
                                }
                            }
                            // Persistent indicator: do not clear selected on end
                        )
                }
            }
            .onAppear {
                if selected == nil, let last = data.last {
                    selected = last
                }
            }
            if let selected = selected {
                let minVal = data.map { $0.1 }.min() ?? selected.1
                let maxVal = data.map { $0.1 }.max() ?? selected.1
                let idx = data.firstIndex(where: { $0.0 == selected.0 && $0.1 == selected.1 }) ?? 0
                let prev = idx > 0 ? data[idx-1].1 : selected.1
                let note: String = {
                    if selected.1 == minVal {
                        return "Minimum"
                    } else if selected.1 == maxVal {
                        return "Maximum"
                    } else if abs(selected.1 - prev) > 0.15 * (maxVal - minVal) {
                        return "High Increase"
                    } else {
                        return ""
                    }
                }()
                HStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(selected.0, formatter: HealthLineChartSheet.fullDateFormatter)")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                        HStack(spacing: 8) {
                            Spacer()
                            Text(String(format: "%.1f \(unit)", selected.1))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                            if !note.isEmpty &&  label == "Strain" || label == "Effort" {
                                Spacer()
                                if note == "Maximum" {
                                    Image(systemName: "gauge.with.dots.needle.100percent")
                                } else if note == "High Increase" {
                                    Image(systemName: "gauge.with.dots.needle.bottom.50percent.badge.plus")
                                } else if note == "Minimum" {
                                    Image(systemName: "arrowtriangle.down.2.fill")
                                }
                                if note == "Maximum" {
                                    Text("Maximum")
                                        .font(.caption.bold())
                                        .foregroundColor(.red)
                                } else if note == "High Increase" {
                                    Text("High Increase")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                } else if note == "Minimum" {
                                    Text("Recovering")
                                        .font(.caption.bold())
                                        .foregroundColor(.blue)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    Spacer()
                }
            }
        }
        .padding()
    }
}
