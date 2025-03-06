import SwiftUI
import Charts
import HealthKit

struct HealthInsightsView: View {
    @State private var selectedPoint: NutrientDataPoint?
    @State private var selectedDate: Date = Date()
    
    struct NutrientDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let nutrient: String
    }
    
    @StateObject private var healthStore = HealthKitManager()
    @State private var nutrientData: [String: [NutrientDataPoint]] = [:]
    
    private var startOfSelectedDay: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }
    
    private var endOfSelectedDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfSelectedDay)!
    }
    
    private var dateTitle: String {
        selectedDate.formatted(.dateTime.month().day())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text(dateTitle)
                                .font(.title2.bold())
                            
                            Spacer()
                            
                            HStack(spacing: 20) {
                                Button {
                                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                                    Task {
                                        await fetchHourlyNutrientData()
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .padding()
                                .hoverEffect(.automatic)
                                
                                Button {
                                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                                    Task {
                                        await fetchHourlyNutrientData()
                                    }
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .padding()
                                .hoverEffect(.automatic)
                            }
                        }
                        .padding()
                        
                        Chart {
                            ForEach(Array(0..<24), id: \.self) { hour in
                                if let date = Calendar.current.date(byAdding: .hour, value: hour, to: startOfSelectedDay) {
                                    RuleMark(
                                        x: .value("Hour", date, unit: .hour)
                                    )
                                    .lineStyle(StrokeStyle(dash: [2, 4]))
                                    .foregroundStyle(.gray.opacity(0.3))
                                }
                            }
                            
                            ForEach(nutrientData["Protein"] ?? []) { point in
                                PointMark(
                                    x: .value("Time", point.date, unit: .hour),
                                    y: .value("Grams", point.value)
                                )
                                .foregroundStyle(.red)
                                .symbol(.circle)
                            }
                            
                            ForEach(nutrientData["Carbs"] ?? []) { point in
                                PointMark(
                                    x: .value("Time", point.date, unit: .hour),
                                    y: .value("Grams", point.value)
                                )
                                .foregroundStyle(.green)
                                .symbol(.circle)
                            }
                            
                            ForEach(nutrientData["Fats"] ?? []) { point in
                                PointMark(
                                    x: .value("Time", point.date, unit: .hour),
                                    y: .value("Grams", point.value)
                                )
                                .foregroundStyle(.blue)
                                .symbol(.circle)
                            }
                            
                            if let selected = selectedPoint {
                                RuleMark(
                                    x: .value("Selected", selected.date, unit: .hour)
                                )
                                .foregroundStyle(.ultraThinMaterial)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: [startOfSelectedDay,
                                             Calendar.current.date(byAdding: .hour, value: 6, to: startOfSelectedDay)!,
                                             Calendar.current.date(byAdding: .hour, value: 12, to: startOfSelectedDay)!,
                                             Calendar.current.date(byAdding: .hour, value: 18, to: startOfSelectedDay)!,
                                             endOfSelectedDay]) { value in
                                AxisGridLine()
                                AxisTick()
                                if let date = value.as(Date.self) {
                                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                                }
                            }
                        }
                        .chartXScale(domain: startOfSelectedDay...endOfSelectedDay)
                        .frame(height: 300)
                        .padding()
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .onTapGesture { location in
                                        let xPosition = location.x - geometry.frame(in: .local).origin.x
                                        guard let date = proxy.value(atX: xPosition) as Date? else { return }
                                        
                                        let allPoints = (nutrientData["Protein"] ?? []) + (nutrientData["Carbs"] ?? []) + (nutrientData["Fats"] ?? [])
                                        selectedPoint = allPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                                    }
                            }
                        }
                    }
                    
                    if let selected = selectedPoint {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(selected.date, format: .dateTime.month(.abbreviated).day())
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                            
                            let selectedTime = selected.date
                            ForEach(["Protein", "Carbs", "Fats"], id: \.self) { nutrient in
                                if let point = nutrientData[nutrient]?.first(where: {
                                    Calendar.current.compare($0.date, to: selectedTime, toGranularity: .hour) == .orderedSame
                                }) {
                                    HStack {
                                        Text(nutrient)
                                            .font(.headline)
                                            .foregroundStyle(nutrient == "Protein" ? .red :
                                                            nutrient == "Carbs" ? .green : .blue)
                                        Spacer()
                                        Text("\(Int(point.value))")
                                            .font(.title3.bold())
                                        Text("grams")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            Text("\(selected.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)))):00-\((Calendar.current.date(byAdding: .hour, value: 1, to: selected.date)?.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))!):00")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    }
                    
                    HStack(spacing: 20) {
                        Label("Protein", systemImage: "circle.fill")
                            .foregroundColor(.red)
                        Label("Carbs", systemImage: "circle.fill")
                            .foregroundColor(.green)
                        Label("Fats", systemImage: "circle.fill")
                            .foregroundColor(.blue)
                    }
                    .padding()
                }
            }
            .navigationTitle("Macronutrients")
            .task {
                await fetchHourlyNutrientData()
            }
        }
    }
    
    private func fetchHourlyNutrientData() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        
        let intervals = (0...23).map { hour -> (start: Date, end: Date) in
            let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
            let end = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!
            return (start: start, end: end)
        }
        
        for nutrient in ["Protein", "Carbs", "Fats"] {
            var hourlyData: [NutrientDataPoint] = []
            
            for interval in intervals {
                let value = await withCheckedContinuation { continuation in
                    healthStore.fetchNutrientDataForInterval(
                        nutrientType: nutrient.lowercased(),
                        start: interval.start,
                        end: interval.end
                    ) { value, _ in
                        continuation.resume(returning: value)
                    }
                }
                
                if let value = value {
                    hourlyData.append(NutrientDataPoint(
                        date: interval.start,
                        value: value,
                        nutrient: nutrient
                    ))
                }
            }
            
            await MainActor.run {
                nutrientData[nutrient] = hourlyData.sorted(by: { $0.date < $1.date })
            }
        }
    }
}

