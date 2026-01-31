import SwiftUI
import Charts
import HealthKit

protocol NutrientChartView: View {}

struct NutrientDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let nutrient: String
}

struct DayNutrientData: Identifiable {
    let id = UUID()
    let hourStart: Date
    let value: Double
    let nutrient: String
    
    @MainActor
    static func fetchDayData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [DayNutrientData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        var hourlyData: [DayNutrientData] = []
        
        for hour in 0..<24 {
            let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
            
            let value = await withCheckedContinuation { continuation in
                healthStore.fetchNutrientDataForInterval(
                    nutrientType: nutrientType.lowercased(),
                    start: hourStart,
                    end: hourEnd
                ) { value, _ in
                    continuation.resume(returning: value ?? 0)
                }
            }
            
            hourlyData.append(DayNutrientData(
                hourStart: hourStart,
                value: value,
                nutrient: nutrientType
            ))
        }
        
        return hourlyData
    }
}

struct WeekNutrientData: Identifiable {
    let id = UUID()
    let date: Date
    let totalValue: Double
    let nutrient: String
    let dayOfWeek: Int
    
    @MainActor
    static func fetchWeekData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [WeekNutrientData] {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        var weekData: [WeekNutrientData] = []
        
        for dayOffset in 0...6 {
            let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let value = await withCheckedContinuation { continuation in
                healthStore.fetchNutrientDataForInterval(
                    nutrientType: nutrientType.lowercased(),
                    start: dayStart,
                    end: dayEnd
                ) { value, _ in
                    continuation.resume(returning: value ?? 0)
                }
            }
            
            weekData.append(WeekNutrientData(
                date: dayStart,
                totalValue: value,
                nutrient: nutrientType,
                dayOfWeek: calendar.component(.weekday, from: dayStart)
            ))
        }
        
        return weekData
    }
}

struct MonthNutrientData: Identifiable {
    let id = UUID()
    let weekStart: Date
    let weekEnd: Date
    let averageValue: Double
    let nutrient: String
    let weekNumber: Int
    
    @MainActor
    static func fetchMonthData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [MonthNutrientData] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        
        // Find the closest Sunday before or on the start of the month
        var firstWeekStart = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: monthStart) + 1, to: monthStart)!
        if calendar.component(.weekday, from: monthStart) == 1 {
            firstWeekStart = monthStart
        }
        
        // Find the closest Saturday after the end of the month
        var lastWeekEnd = calendar.date(byAdding: .day, value: 6 - calendar.component(.weekday, from: nextMonth), to: nextMonth)!
        if calendar.component(.weekday, from: nextMonth) != 7 {
            lastWeekEnd = calendar.date(byAdding: .day, value: 7 - calendar.component(.weekday, from: nextMonth), to: nextMonth)!
        }
        
        var monthData: [MonthNutrientData] = []
        let weekRange = stride(from: firstWeekStart, to: lastWeekEnd, by: 7 * 24 * 60 * 60)
        
        for (weekNumber, weekStart) in weekRange.enumerated() {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            var weekTotal: Double = 0
            var validDays = 0
            
            let dayRange = stride(from: weekStart, through: min(weekEnd, lastWeekEnd), by: 24 * 60 * 60)
            
            for currentDay in dayRange {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
                let value = await withCheckedContinuation { continuation in
                    healthStore.fetchNutrientDataForInterval(
                        nutrientType: nutrientType.lowercased(),
                        start: currentDay,
                        end: nextDay
                    ) { value, _ in
                        continuation.resume(returning: value)
                    }
                }
                
                if let value = value, value > 0 {
                    weekTotal += value
                    validDays += 1
                }
            }
            
            if validDays > 0 {
                let averageValue = (weekTotal / Double(validDays)).rounded() // Round the average value
                monthData.append(MonthNutrientData(
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    averageValue: averageValue,
                    nutrient: nutrientType,
                    weekNumber: weekNumber + 1
                ))
            }
        }
        
        return monthData
    }
}

struct YearNutrientData: Identifiable {
    let id = UUID()
    let monthStart: Date
    let averageValue: Double
    let nutrient: String
    let monthOfYear: Int
    
    @MainActor
    static func fetchYearData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [YearNutrientData] {
        let calendar = Calendar.current
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: date))!
        var yearData: [YearNutrientData] = []
        
        for monthOffset in 0...11 {
            let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: yearStart)!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            
            var monthTotal: Double = 0
            var daysCount = 0
            
            var currentDate = monthStart
            while currentDate < monthEnd {
                let value = await withCheckedContinuation { continuation in
                    healthStore.fetchNutrientDataForInterval(
                        nutrientType: nutrientType.lowercased(),
                        start: currentDate,
                        end: calendar.date(byAdding: .day, value: 1, to: currentDate)!
                    ) { value, _ in
                        continuation.resume(returning: value ?? 0)
                    }
                }
                monthTotal += value
                daysCount += 1
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
            
            yearData.append(YearNutrientData(
                monthStart: monthStart,
                averageValue: daysCount > 0 ? monthTotal / Double(daysCount) : 0,
                nutrient: nutrientType,
                monthOfYear: calendar.component(.month, from: monthStart)
            ))
        }
        
        return yearData
    }
}

private func findClosestPoint<T>(
    to xPosition: Double,
    in data: [T],
    xKeyPath: KeyPath<T, Double>,
    tolerance: Double = 0.5
) -> T? {
    let sortedPoints = data.sorted { abs($0[keyPath: xKeyPath] - xPosition) < abs($1[keyPath: xKeyPath] - xPosition) }
    guard let closest = sortedPoints.first else { return nil }
    
    // Only return if within tolerance
    return abs(closest[keyPath: xKeyPath] - xPosition) <= tolerance ? closest : nil
}


struct DayChartView: View {
    let hourlyData: [String: [DayNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    let selectedDiet: DietPlan?
    let strictLevel: StrictLevel
    let tdee: Double
    @State private var isDragging = false
    
    private var maxValue: Double {
       let baseMax = hourlyData.values.flatMap { $0 }.map(\.value).max() ?? 100
       let increment = 100.0
       return ceil(baseMax / increment) * increment
    }
    
    var body: some View {
        if hourlyData.values.flatMap({ $0 }).allSatisfy({ $0.value == 0 }) {
            Text("No Data")
                .font(.title)
                .foregroundColor(.secondary)
                .frame(height: 300)
        } else {
            Chart {
                if let selectedDiet = selectedDiet {
                    let ranges = getRangesForStrictLevel(diet: selectedDiet, level: strictLevel)
                    
                    RectangleMark(
                        xStart: .value("Start", 0),
                        xEnd: .value("End", 23),
                        yStart: .value("Lower", ranges.carbs.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.carbs.upperBound * tdee)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                    
                    RectangleMark(
                        xStart: .value("Start", 0),
                        xEnd: .value("End", 23),
                        yStart: .value("Lower", ranges.protein.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.protein.upperBound * tdee)
                    )
                    .foregroundStyle(.red.opacity(0.1))
                    
                    RectangleMark(
                        xStart: .value("Start", 0),
                        xEnd: .value("End", 23),
                        yStart: .value("Lower", ranges.fat.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.fat.upperBound * tdee)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                
                ForEach(["Protein", "Carbs", "Fats"], id: \.self) { nutrient in
                    ForEach(hourlyData[nutrient] ?? [], id: \.id) { point in
                        if point.value > 0 {
                            PointMark(
                                x: .value("Hour", Double(Calendar.current.component(.hour, from: point.hourStart))),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(nutrient == "Protein" ? .red :
                                            nutrient == "Carbs" ? .green : .blue)
                        }
                    }
                }
                
                if let selected = selectedPoint {
                    RuleMark(
                        x: .value("Selected", Double(Calendar.current.component(.hour, from: selected.date)))
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .chartXScale(domain: 0...24)
            .frame(height: 300)
            .chartPlotStyle { plotArea in
                plotArea.frame(height: 300)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 6)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        Text(String(format: "%02d", value.as(Int.self) ?? 0))
                    }
                }
            }
            .chartOverlay { chartProxy in
                GeometryReader { geometryProxy in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        let generator = UIImpactFeedbackGenerator(style: .rigid)
                                        generator.impactOccurred()
                                    }
                                    
                                    let xPosition = value.location.x - geometryProxy.frame(in: .local).origin.x
                                    if let hour = chartProxy.value(atX: xPosition) as Double? {
                                        let points = hourlyData.values.flatMap { $0 }.filter { $0.value > 0 }
                                        let closest = points.min(by: { point1, point2 in
                                            let hour1 = Calendar.current.component(.hour, from: point1.hourStart)
                                            let hour2 = Calendar.current.component(.hour, from: point2.hourStart)
                                            return abs(Double(hour1) - hour) < abs(Double(hour2) - hour)
                                        })
                                        
                                        if let closest = closest,
                                           abs(Double(Calendar.current.component(.hour, from: closest.hourStart)) - hour) <= 0.5 {
                                            let newPoint = NutrientDataPoint(
                                                date: closest.hourStart,
                                                value: closest.value,
                                                nutrient: closest.nutrient
                                            )
                                            
                                            if newPoint.date != selectedPoint?.date {
                                                let generator = UIImpactFeedbackGenerator(style: .rigid)
                                                generator.impactOccurred()
                                                selectedPoint = newPoint
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
        }
    }
}

struct WeekChartView: View {
    let weekData: [String: [WeekNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    let selectedDiet: DietPlan?
    let strictLevel: StrictLevel
    let tdee: Double
    @State private var isDragging = false
    
    var body: some View {
        if (weekData["Protein"]?.isEmpty ?? true) &&
           (weekData["Carbs"]?.isEmpty ?? true) &&
           (weekData["Fats"]?.isEmpty ?? true) {
            Text("No data")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 300)
        } else {
            Chart {
                if let selectedDiet = selectedDiet {
                    let ranges = getRangesForStrictLevel(diet: selectedDiet, level: strictLevel)
                    
                    RectangleMark(
                        xStart: .value("Start", 1),
                        xEnd: .value("End", 7),
                        yStart: .value("Lower", ranges.carbs.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.carbs.upperBound * tdee)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                    
                    RectangleMark(
                        xStart: .value("Start", 1),
                        xEnd: .value("End", 7),
                        yStart: .value("Lower", ranges.protein.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.protein.upperBound * tdee)
                    )
                    .foregroundStyle(.red.opacity(0.1))
                    
                    RectangleMark(
                        xStart: .value("Start", 1),
                        xEnd: .value("End", 7),
                        yStart: .value("Lower", ranges.fat.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.fat.upperBound * tdee)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                
                ForEach(weekData["Protein"]?.filter { $0.totalValue > 0 } ?? []) { point in
                    PointMark(
                        x: .value("Day", point.dayOfWeek),
                        y: .value("Grams", point.totalValue)
                    )
                    .foregroundStyle(.red)
                }
                
                ForEach(weekData["Carbs"]?.filter { $0.totalValue > 0 } ?? []) { point in
                    PointMark(
                        x: .value("Day", point.dayOfWeek),
                        y: .value("Grams", point.totalValue)
                    )
                    .foregroundStyle(.green)
                }
                
                ForEach(weekData["Fats"]?.filter { $0.totalValue > 0 } ?? []) { point in
                    PointMark(
                        x: .value("Day", point.dayOfWeek),
                        y: .value("Grams", point.totalValue)
                    )
                    .foregroundStyle(.blue)
                }
                
                if let selected = selectedPoint {
                    RuleMark(
                        x: .value("Selected", Calendar.current.component(.weekday, from: selected.date))
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .chartXAxis {
                AxisMarks(values: Array(1...7)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        let calendar = Calendar.current
                        let weekdays = calendar.shortWeekdaySymbols
                        let index = (value.as(Int.self)! - 1) % 7
                        Text(weekdays[index])
                    }
                }
            }
            .chartXScale(domain: 1...7)
            .chartOverlay { chartProxy in
                GeometryReader { geometryProxy in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        let generator = UIImpactFeedbackGenerator(style: .rigid)
                                        generator.impactOccurred()
                                    }
                                    
                                    let xPosition = value.location.x - geometryProxy.frame(in: .local).origin.x
                                    if let weekday = chartProxy.value(atX: xPosition) as Double? {
                                        let points = weekData.values.flatMap { $0 }.filter { $0.totalValue > 0 }
                                        let closest = points.min(by: { point1, point2 in
                                            abs(Double(point1.dayOfWeek) - weekday) < abs(Double(point2.dayOfWeek) - weekday)
                                        })
                                        
                                        if let closest = closest,
                                           abs(Double(closest.dayOfWeek) - weekday) <= 0.5 {
                                            let newPoint = NutrientDataPoint(
                                                date: closest.date,
                                                value: closest.totalValue,
                                                nutrient: closest.nutrient
                                            )
                                            
                                            if newPoint.date != selectedPoint?.date {
                                                let generator = UIImpactFeedbackGenerator(style: .rigid)
                                                generator.impactOccurred()
                                                selectedPoint = newPoint
                                            }
                                        } else {
                                            selectedPoint = nil
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
        }
    }
}

struct MonthChartView: View {
    let monthData: [String: [MonthNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    let selectedDiet: DietPlan?
    let strictLevel: StrictLevel
    let tdee: Double
    @State private var isDragging = false
    let viewingMonth: Date // Add the current viewing month

    var body: some View {
        if (monthData["Protein"]?.isEmpty ?? true) &&
           (monthData["Carbs"]?.isEmpty ?? true) &&
           (monthData["Fats"]?.isEmpty ?? true) {
            Text("No data")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 300)
        } else {
            Chart {
                if let selectedDiet = selectedDiet {
                    let ranges = getRangesForStrictLevel(diet: selectedDiet, level: strictLevel)
                    
                    RectangleMark(
                        xStart: .value("Start", 1),
                        xEnd: .value("End", 5),
                        yStart: .value("Lower", ranges.carbs.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.carbs.upperBound * tdee)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                    
                    RectangleMark(
                        xStart: .value("Start", 1),
                        xEnd: .value("End", 5),
                        yStart: .value("Lower", ranges.protein.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.protein.upperBound * tdee)
                    )
                    .foregroundStyle(.red.opacity(0.1))
                    
                    RectangleMark(
                        xStart: .value("Start", 1),
                        xEnd: .value("End", 5),
                        yStart: .value("Lower", ranges.fat.lowerBound * tdee),
                        yEnd: .value("Upper", ranges.fat.upperBound * tdee)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                
                ForEach(monthData["Protein"] ?? []) { point in
                    PointMark(
                        x: .value("Week", weekNumber(for: point.weekStart, in: viewingMonth)),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.red)
                }
                
                ForEach(monthData["Carbs"] ?? []) { point in
                    PointMark(
                        x: .value("Week", weekNumber(for: point.weekStart, in: viewingMonth)),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.green)
                }
                
                ForEach(monthData["Fats"] ?? []) { point in
                    PointMark(
                        x: .value("Week", weekNumber(for: point.weekStart, in: viewingMonth)),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.blue)
                }
                
                if let selected = selectedPoint {
                    RuleMark(
                        x: .value("Selected", weekNumber(for: selected.date, in: viewingMonth))
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .chartXScale(domain: 1...5)
            .chartXAxis {
                AxisMarks(values: Array(1...5)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        Text("Week \(value.as(Int.self) ?? 0)")
                    }
                }
            }
            .chartYAxis {
                AxisMarks() { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        Text("\(value.as(Double.self) ?? 0, specifier: "%.0f")")
                    }
                }
            }
            .chartOverlay { chartProxy in
                GeometryReader { geometryProxy in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        let generator = UIImpactFeedbackGenerator(style: .rigid)
                                        generator.impactOccurred()
                                    }
                                    
                                    let xPosition = value.location.x - geometryProxy.frame(in: .local).origin.x
                                    if let week = chartProxy.value(atX: xPosition) as Double? {
                                        let weekIndex = Int(week.rounded())
                                        let points = monthData.values.flatMap { $0 }
                                        let closest = points.first { weekNumber(for: $0.weekStart, in: viewingMonth) == weekIndex }
                                        
                                        if let closest = closest {
                                            let newPoint = NutrientDataPoint(
                                                date: closest.weekStart,
                                                value: closest.averageValue,
                                                nutrient: closest.nutrient
                                            )
                                            
                                            if newPoint.date != selectedPoint?.date {
                                                let generator = UIImpactFeedbackGenerator(style: .rigid)
                                                generator.impactOccurred()
                                                selectedPoint = newPoint
                                            }
                                        } else {
                                            selectedPoint = nil
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
        }
    }
    
    private func weekNumber(for date: Date, in viewingMonth: Date) -> Int {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: viewingMonth))!
        let firstSunday = calendar.nextDate(after: monthStart, matching: DateComponents(weekday: 1), matchingPolicy: .nextTime, direction: .backward)!
        let weekOfMonth = calendar.dateComponents([.weekOfMonth], from: firstSunday, to: date).weekOfMonth ?? 0
        return weekOfMonth + 1
    }
}
extension Date {
    func startOfMonth() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)!
    }

    func endOfMonth() -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = 1
        components.day = -1
        return calendar.date(byAdding: components, to: startOfMonth())!
    }
}
struct SixMonthChartView: View {
    let sixMonthData: [String: [SixMonthNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    let selectedDiet: DietPlan?
    let strictLevel: StrictLevel
    let tdee: Double
    @State private var isDragging = false
    
    var body: some View {
        Chart {
            ForEach(["Protein", "Carbs", "Fats"], id: \.self) { nutrient in
                ForEach(sixMonthData[nutrient] ?? []) { point in
                    PointMark(
                        x: .value("Month", point.monthIndex),
                        y: .value("Value", point.averageValue)
                    )
                    .foregroundStyle(nutrient == "Protein" ? .red :
                                    nutrient == "Carbs" ? .green : .blue)
                }
            }
            
            if let selected = selectedPoint {
                RuleMark(
                    x: .value("Selected", Double(sixMonthData.values.first?.first { $0.monthStart == selected.date }?.monthIndex ?? 0))
                )
                .foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXScale(domain: 0...5)
        .chartXAxis {
            let calendar = Calendar.current
            let firstPoint = sixMonthData.values.first?.first
            let startMonth = calendar.component(.month, from: firstPoint?.monthStart ?? Date())
            
            let monthLabels = startMonth <= 6 ?
                ["Jan", "Feb", "Mar", "Apr", "May", "Jun"] :
                ["Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            
            AxisMarks(values: Array(0...5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    Text(monthLabels[value.as(Int.self)!])
                        .font(.caption2)
                }
            }
        }
        .chartOverlay { chartProxy in
            GeometryReader { geometryProxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    let generator = UIImpactFeedbackGenerator(style: .rigid)
                                    generator.impactOccurred()
                                }
                                
                                let xPosition = value.location.x - geometryProxy.frame(in: .local).origin.x
                                if let monthIndex = chartProxy.value(atX: xPosition) as Double? {
                                    let points = sixMonthData.values.flatMap { $0 }
                                    let closest = points.min(by: { point1, point2 in
                                        abs(Double(point1.monthIndex) - monthIndex) < abs(Double(point2.monthIndex) - monthIndex)
                                    })
                                    
                                    if let closest = closest,
                                       abs(Double(closest.monthIndex) - monthIndex) <= 0.5 {
                                        let newPoint = NutrientDataPoint(
                                            date: closest.monthStart,
                                            value: closest.averageValue,
                                            nutrient: closest.nutrient
                                        )
                                        
                                        if newPoint.date != selectedPoint?.date {
                                            let generator = UIImpactFeedbackGenerator(style: .rigid)
                                            generator.impactOccurred()
                                            selectedPoint = newPoint
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
        }
        .frame(height: 300)
    }
}

struct YearChartView: View {
    let yearData: [String: [YearNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    let selectedDiet: DietPlan?
    let strictLevel: StrictLevel
    let tdee: Double
    @State private var isDragging = false
    
    var body: some View {
        Chart {
            ForEach(["Protein", "Carbs", "Fats"], id: \.self) { nutrient in
                ForEach(yearData[nutrient] ?? []) { point in
                    PointMark(
                        x: .value("Month", point.monthOfYear - 1),
                        y: .value("Value", point.averageValue)
                    )
                    .foregroundStyle(nutrient == "Protein" ? .red :
                                    nutrient == "Carbs" ? .green : .blue)
                }
            }
            
            if let selected = selectedPoint {
                RuleMark(
                    x: .value("Selected", Calendar.current.component(.month, from: selected.date) - 1)
                )
                .foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXScale(domain: 0...11)
        .chartXAxis {
            let monthLabels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"]
            
            AxisMarks(values: Array(0...11)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    Text(monthLabels[value.as(Int.self)!])
                        .font(.caption2)
                }
            }
        }
        .chartOverlay { chartProxy in
            GeometryReader { geometryProxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    let generator = UIImpactFeedbackGenerator(style: .rigid)
                                    generator.impactOccurred()
                                }
                                
                                let xPosition = value.location.x - geometryProxy.frame(in: .local).origin.x
                                if let monthIndex = chartProxy.value(atX: xPosition) as Double? {
                                    let points = yearData.values.flatMap { $0 }
                                    let closest = points.min(by: { point1, point2 in
                                        abs(Double(point1.monthOfYear - 1) - monthIndex) < abs(Double(point2.monthOfYear - 1) - monthIndex)
                                    })
                                    
                                    if let closest = closest,
                                       abs(Double(closest.monthOfYear - 1) - monthIndex) <= 0.5 {
                                        let newPoint = NutrientDataPoint(
                                            date: closest.monthStart,
                                            value: closest.averageValue,
                                            nutrient: closest.nutrient
                                        )
                                        
                                        if newPoint.date != selectedPoint?.date {
                                            let generator = UIImpactFeedbackGenerator(style: .rigid)
                                            generator.impactOccurred()
                                            selectedPoint = newPoint
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
        }
        .frame(height: 300)
    }
}

struct SixMonthNutrientData: Identifiable {
    let id = UUID()
    let monthStart: Date
    let averageValue: Double
    let nutrient: String
    let monthIndex: Int
    
    @MainActor
    static func fetchSixMonthData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [SixMonthNutrientData] {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        let isFirstHalf = month <= 6
        let startMonth = isFirstHalf ? 7 : 1
        let startYear = isFirstHalf ? year - 1 : year
        
        var components = DateComponents()
        components.year = startYear
        components.month = startMonth
        components.day = 1
        let startDate = calendar.date(from: components)!

        var monthlyData: [SixMonthNutrientData] = []
        
        for monthOffset in 0..<6 {
            let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: startDate)!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            
            let value = await withCheckedContinuation { continuation in
                healthStore.fetchNutrientDataForInterval(
                    nutrientType: nutrientType.lowercased(),
                    start: monthStart,
                    end: monthEnd
                ) { value, _ in
                    continuation.resume(returning: value ?? 0)
                }
            }
            
            monthlyData.append(SixMonthNutrientData(
                monthStart: monthStart,
                averageValue: value,
                nutrient: nutrientType,
                monthIndex: monthOffset
            ))
        }
        
        return monthlyData.sorted(by: { $0.monthStart < $1.monthStart })
    }
}

struct HealthInsightsView: View {
    @State private var showDatePicker = false
    @StateObject private var viewModel = HealthInsightsViewModel()
    @State private var selectedPoint: NutrientDataPoint?
    @State private var selectedDate: Date = Date()
    @State private var hourlyData: [String: [DayNutrientData]] = [:]
    @State private var weekData: [String: [WeekNutrientData]] = [:]
    @State private var monthData: [String: [MonthNutrientData]] = [:]
    @State private var sixMonthData: [String: [SixMonthNutrientData]] = [:]
    @State private var yearData: [String: [YearNutrientData]] = [:]
    @State private var animationPhase: Double = 0
    @State private var selectedDiet: DietPlan?
    @State private var strictLevel: StrictLevel = .medium
    
    let dietPlans = [
        DietPlan(name: "Balanced Diet",
                 strictRanges: (carbs: 0.1...0.1, protein: 0.075...0.075, fat: 0.033...0.033),
                 lenientRanges: (carbs: 0.11...0.125, protein: 0.05...0.075, fat: 0.028...0.039)),
        
        DietPlan(name: "High-Protein Diet",
                 strictRanges: (carbs: 0.075...0.075, protein: 0.1...0.1, fat: 0.033...0.033),
                 lenientRanges: (carbs: 0.063...0.088, protein: 0.088...0.113, fat: 0.022...0.033)),
        
        DietPlan(name: "Low-Carb Diet",
                 strictRanges: (carbs: 0.038...0.05, protein: 0.088...0.1, fat: 0.044...0.056),
                 lenientRanges: (carbs: 0.05...0.075, protein: 0.063...0.088, fat: 0.039...0.05)),
        
        DietPlan(name: "Ketogenic Diet",
                 strictRanges: (carbs: 0.013...0.025, protein: 0.05...0.063, fat: 0.072...0.083),
                 lenientRanges: (carbs: 0.013...0.038, protein: 0.038...0.075, fat: 0.067...0.089)),
        
        DietPlan(name: "Paleo Diet",
                 strictRanges: (carbs: 0.05...0.075, protein: 0.075...0.1, fat: 0.033...0.044),
                 lenientRanges: (carbs: 0.063...0.1, protein: 0.063...0.088, fat: 0.033...0.05)),
        
        DietPlan(name: "Mediterranean Diet",
                 strictRanges: (carbs: 0.1...0.125, protein: 0.05...0.075, fat: 0.033...0.044),
                 lenientRanges: (carbs: 0.113...0.138, protein: 0.038...0.063, fat: 0.028...0.039)),
        
        DietPlan(name: "Vegetarian Diet",
                 strictRanges: (carbs: 0.125...0.138, protein: 0.05...0.063, fat: 0.022...0.033),
                 lenientRanges: (carbs: 0.113...0.15, protein: 0.038...0.063, fat: 0.022...0.039)),
        
        DietPlan(name: "Vegan Diet",
                 strictRanges: (carbs: 0.125...0.15, protein: 0.05...0.063, fat: 0.017...0.028),
                 lenientRanges: (carbs: 0.113...0.163, protein: 0.038...0.063, fat: 0.017...0.033)),
        
        DietPlan(name: "Carnivore Diet",
                 strictRanges: (carbs: 0.0...0.013, protein: 0.088...0.125, fat: 0.056...0.072),
                 lenientRanges: (carbs: 0.0...0.025, protein: 0.075...0.113, fat: 0.056...0.078)),
        
        DietPlan(name: "DASH Diet",
                 strictRanges: (carbs: 0.125...0.138, protein: 0.05...0.063, fat: 0.022...0.033),
                 lenientRanges: (carbs: 0.113...0.15, protein: 0.038...0.075, fat: 0.022...0.039)),
        
        DietPlan(name: "Zone Diet",
                 strictRanges: (carbs: 0.1...0.1, protein: 0.075...0.075, fat: 0.033...0.033),
                 lenientRanges: (carbs: 0.088...0.113, protein: 0.063...0.088, fat: 0.028...0.039)),
        
        DietPlan(name: "Intermittent Fasting",
                 strictRanges: (carbs: 0.0...0.25, protein: 0.0...0.25, fat: 0.0...0.11),
                 lenientRanges: (carbs: 0.0...0.25, protein: 0.0...0.25, fat: 0.0...0.11))
    ]
    
    enum TimePeriod: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case sixMonth = "6 Months"
        case year = "Year"
    }
    
    @State private var selectedTimePeriod: TimePeriod = .week
    @StateObject private var healthStore = HealthKitManager()
    @State private var nutrientData: [String: [NutrientDataPoint]] = [:]
    
    private var startOfSelectedDay: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }
    
    private var endOfSelectedDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfSelectedDay)!
    }
    
    private var dateTitle: String {
        let formatter = DateFormatter()
        
        switch selectedTimePeriod {
            case .day:
                return selectedDate.formatted(.dateTime.month().day())
            case .week:
                let calendar = Calendar.current
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
                return "\(weekStart.formatted(.dateTime.month().day())) - \(weekEnd.formatted(.dateTime.month().day())), \(calendar.component(.year, from: selectedDate))"
            case .month:
                formatter.dateFormat = "MMM yyyy"
                return formatter.string(from: selectedDate)
            case .sixMonth:
                let month = Calendar.current.component(.month, from: selectedDate)
                let year = Calendar.current.component(.year, from: selectedDate)
                let isFirstHalf = month <= 6
                return "\(year) \(isFirstHalf ? "First" : "Second") Half"
            case .year:
                return selectedDate.formatted(.dateTime.year())
        }
    }
    
    private func weekdayName(for day: Int) -> String {
        let calendar = Calendar.current
        let weekdays = calendar.shortWeekdaySymbols
        let index = (day - 1) % 7
        return weekdays[index]
    }
    
    var chartView: some View {
        switch selectedTimePeriod {
        case .day:
            AnyView(DayChartView(hourlyData: hourlyData, selectedPoint: $selectedPoint, selectedDiet: selectedDiet, strictLevel: strictLevel, tdee: viewModel.tdee)
                .task {
                    await fetchData()
                })
        case .week:
            AnyView(WeekChartView(weekData: weekData, selectedPoint: $selectedPoint, selectedDiet: selectedDiet, strictLevel: strictLevel, tdee: viewModel.tdee))
        case .month:
            AnyView(
                MonthChartView(
                    monthData: monthData,
                    selectedPoint: $selectedPoint,
                    selectedDiet: selectedDiet,
                    strictLevel: strictLevel,
                    tdee: viewModel.tdee,
                    viewingMonth: selectedDate
                ))
        case .sixMonth:
            AnyView(SixMonthChartView(sixMonthData: sixMonthData, selectedPoint: $selectedPoint, selectedDiet: selectedDiet, strictLevel: strictLevel, tdee: viewModel.tdee)
                .task {
                    await fetchData()
                })
        case .year:
            AnyView(YearChartView(yearData: yearData, selectedPoint: $selectedPoint, selectedDiet: selectedDiet, strictLevel: strictLevel, tdee: viewModel.tdee))
        }
    }
    
    private var timeNavigationHeader: some View {
        HStack {
            Text(dateTitle)
                .font(.title2.bold())
                .onLongPressGesture {
                    showDatePicker.toggle()
                    selectedPoint = nil
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
                .sheet(isPresented: $showDatePicker) {
                    DatePickerSheet(selectedDate: $selectedDate, timePeriod: selectedTimePeriod)
                        .presentationDetents([.height(300)])
                        .onChange(of: selectedDate) { oldValue, newValue in
                            Task {
                                await fetchData()
                            }
                        }
                }
            
            Spacer()
            
            HStack(spacing: 10) {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    let today = Date()
                    switch selectedTimePeriod {
                    case .day:
                        selectedDate = today
                    case .week:
                        selectedDate = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
                    case .month:
                        selectedDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today))!
                    case .sixMonth:
                        let month = Calendar.current.component(.month, from: today)
                        let halfYearStart = month <= 6 ? 1 : 7
                        selectedDate = Calendar.current.date(from: DateComponents(
                            year: Calendar.current.component(.year, from: today),
                            month: halfYearStart,
                            day: 1
                        ))!
                    case .year:
                        selectedDate = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: today))!
                    }
                    Task {
                        await fetchData()
                    }
                }) {
                    Text("Today")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(minWidth: 20)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
                .hoverEffect(.lift)

                Button {
                    switch selectedTimePeriod {
                    case .day:
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                    case .week:
                        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate)!
                    case .month:
                           selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate)!
                    case .sixMonth:
                        selectedDate = Calendar.current.date(byAdding: .month, value: -6, to: selectedDate)!
                    case .year:
                        selectedDate = Calendar.current.date(byAdding: .year, value: -1, to: selectedDate)!
                    }
                    selectedPoint = nil
                    Task {
                        await fetchData()
                    }
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .padding(8)
                .hoverEffect(.automatic)
                
                Button {
                    switch selectedTimePeriod {
                    case .day:
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                    case .week:
                        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate)!
                    case .month:
                           selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate)!
                    case .sixMonth:
                        selectedDate = Calendar.current.date(byAdding: .month, value: 6, to: selectedDate)!
                    case .year:
                        selectedDate = Calendar.current.date(byAdding: .year, value: 1, to: selectedDate)!
                    }
                    selectedPoint = nil
                    Task {
                        await fetchData()
                    }
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .padding(8)
                .hoverEffect(.automatic)
                .disabled(canNavigateForward)
                .opacity(canNavigateForward ? 0.3 : 1)
            }
        }
        .padding()
    }
    
    private var canNavigateForward: Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimePeriod {
        case .day:
            return calendar.startOfDay(for: selectedDate) >= calendar.startOfDay(for: now)
        case .week:
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let selectedWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
            return selectedWeekStart >= currentWeekStart
        case .month:
           let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
           let selectedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
           return selectedMonthStart >= currentMonthStart
        case .sixMonth:
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let selectedYear = calendar.component(.year, from: selectedDate)
            
            let currentHalf = currentMonth <= 6 ? 1 : 2
            let selectedHalf = selectedMonth <= 6 ? 1 : 2
            
            return selectedYear > currentYear || (selectedYear == currentYear && selectedHalf >= currentHalf)
        case .year:
            let currentYear = calendar.component(.year, from: now)
            let selectedYear = calendar.component(.year, from: selectedDate)
            return selectedYear >= currentYear
        }
    }
    
    private var chartContent: some View {
        Group {
            let hasData: Bool = {
                switch selectedTimePeriod {
                    case .day: return !(hourlyData.values.flatMap { $0 }.allSatisfy { $0.value == 0 })
                    case .week: return !(weekData.values.allSatisfy { $0.isEmpty })
                    case .month: return !(monthData.values.allSatisfy { $0.isEmpty })
                    case .sixMonth: return !(sixMonthData.values.allSatisfy { $0.isEmpty })
                    case .year: return !(yearData.values.allSatisfy { $0.isEmpty })
                }
            }()

            if hasData {
                VStack {
                    HStack(spacing: 0) {
                        GeometryReader { geometry in
                            chartView
                                .frame(width: geometry.size.width - 32) // Adjust width dynamically
                                .frame(height: 300)
                                .padding()
                        }
                    }
                }
            } else {
                VStack {
                    Text("No data")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                }
            }
        }
    }

    private var nutrientLegend: some View {
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

    private func selectedPointDetail(_ selected: NutrientDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selectedTimePeriod {
            case .day:
                let hourStart = Calendar.current.component(.hour, from: selected.date)
                let hourEnd = hourStart + 1
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).day())) \(String(format: "%02d:00-%02d:00", hourStart, hourEnd)) (total):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .week:
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).day())) (total):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .month:
                let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selected.date))!
                let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
                Text("\(weekStart.formatted(.dateTime.month().day())) - \(weekEnd.formatted(.dateTime.month().day())) (average):")
                 .font(.footnote.bold())
                 .foregroundStyle(.secondary)
              
            case .sixMonth:
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).year())) (average):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .year:
                Text("\(selected.date.formatted(.dateTime.month(.defaultDigits)))/\(selected.date.formatted(.dateTime.year())) (average):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            }
            
            ForEach(["Protein", "Carbs", "Fats"], id: \.self) { nutrient in
                let value: Double = {
                    switch selectedTimePeriod {
                    case .day:
                        return hourlyData[nutrient]?.first(where: {
                            Calendar.current.component(.hour, from: $0.hourStart) ==
                            Calendar.current.component(.hour, from: selected.date)
                        })?.value ?? 0
                    case .week:
                        return weekData[nutrient]?.first(where: {
                            Calendar.current.compare($0.date, to: selected.date, toGranularity: .day) == .orderedSame
                        })?.totalValue ?? 0
                    case .month:
                        return monthData[nutrient]?.first(where: {
                            Calendar.current.compare($0.weekStart, to: selected.date, toGranularity: .weekOfYear) == .orderedSame
                        })?.averageValue ?? 0
                    case .sixMonth:
                        return sixMonthData[nutrient]?.first(where: {
                            Calendar.current.compare($0.monthStart, to: selected.date, toGranularity: .month) == .orderedSame
                        })?.averageValue ?? 0
                    case .year:
                        return yearData[nutrient]?.first(where: {
                            Calendar.current.compare($0.monthStart, to: selected.date, toGranularity: .month) == .orderedSame
                        })?.averageValue ?? 0
                    }
                }()
                
                if value > 0 {
                    HStack {
                        Text(nutrient)
                            .font(.headline)
                            .foregroundStyle(nutrient == "Protein" ? .red :
                                            nutrient == "Carbs" ? .green : .blue)
                        Spacer()
                        Text("\(Int(value))")
                            .font(.title3.bold())
                        Text("grams")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    
    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Time Period", selection: $selectedTimePeriod) {
                    ForEach(TimePeriod.allCases, id: \.self) { period in
                        Text(UIDevice.current.userInterfaceIdiom == .pad ? period.rawValue :
                            period == .sixMonth ? "6M" : String(period.rawValue.prefix(1)))
                            .tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTimePeriod) { oldValue, newValue in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    selectedPoint = nil
                    Task {
                        await fetchData()
                    }
                }
                
                timeNavigationHeader
                chartContent
                    .frame(height: 300)
                    .padding()

                if let selected = selectedPoint {
                    selectedPointDetail(selected)
                }
                nutrientLegend
                Picker("Diet Plan", selection: $selectedDiet) {
                    ForEach(dietPlans) { plan in
                        Text(plan.name).tag(Optional(plan))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedDiet) { oldValue, newValue in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
                
                Picker("Strictness Level", selection: $strictLevel) {
                    Text("Strict").tag(StrictLevel.strict)
                    Text("Medium").tag(StrictLevel.medium)
                    Text("Lenient").tag(StrictLevel.lenient)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: strictLevel) { oldValue, newValue in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
                
                CalorieNeedsCard(
                    tdee: viewModel.calculateTDEE(),
                    exerciseCalories: viewModel.todayExerciseCalories,
                    foodCalories: viewModel.todayFoodCalories
                )
                
                ExploreDietsCard()
            }
            .task {
                await fetchData()
            }
            .navigationTitle("Macronutrients")
            .task {
                switch selectedTimePeriod {
                    case .day:
                        await fetchHourlyNutrientData()
                    case .week:
                        for nutrient in ["Protein", "Carbs", "Fats"] {
                            weekData[nutrient] = await WeekNutrientData.fetchWeekData(
                                for: selectedDate,
                                nutrientType: nutrient,
                                healthStore: healthStore
                            )
                        }
                    case .month:
                        for nutrient in ["Protein", "Carbs", "Fats"] {
                            monthData[nutrient] = await MonthNutrientData.fetchMonthData(
                                for: selectedDate,
                                nutrientType: nutrient,
                                healthStore: healthStore
                            )
                        }
                    case .sixMonth:
                        for nutrient in ["Protein", "Carbs", "Fats"] {
                            sixMonthData[nutrient] = await SixMonthNutrientData.fetchSixMonthData(
                                for: selectedDate,
                                nutrientType: nutrient,
                                healthStore: healthStore
                            )
                        }
                    case .year:
                        for nutrient in ["Protein", "Carbs", "Fats"] {
                            yearData[nutrient] = await YearNutrientData.fetchYearData(
                                for: selectedDate,
                                nutrientType: nutrient,
                                healthStore: healthStore
                            )
                        }
                }
            }
            .background(
                GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
        }
    }
    
    struct DatePickerSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var selectedDate: Date
        let timePeriod: TimePeriod
        @State private var animationPhase: Double = 0
        
        private let calendar = Calendar.current
        private let now = Date()
        @State private var halfSelection = 1
        
        var body: some View {
            NavigationStack {
                Group {
                    switch timePeriod {
                    case .day:
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: ...now,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                    case .week:
                        Picker("Week", selection: $selectedDate) {
                            ForEach(getPastWeeks(), id: \.self) { weekStart in
                                let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
                                Text("\(weekStart.formatted(.dateTime.month().day())) - \(weekEnd.formatted(.dateTime.month().day())) \(String(calendar.component(.year, from: weekStart)))")
                                    .tag(weekStart)
                            }
                        }
                        .pickerStyle(.wheel)
                    case .month:
                        HStack {
                            Picker("Month", selection: $selectedDate) {
                                ForEach(getPastMonths(), id: \.self) { date in
                                    Text("\(date.formatted(.dateTime.month(.wide))) \(String(calendar.component(.year, from: date)))")
                                        .tag(date)
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                    case .sixMonth:
                        HStack {
                            let currentYear = calendar.component(.year, from: now)
                            let currentHalf = calendar.component(.month, from: now) <= 6 ? 1 : 2
                            let selectedYear = calendar.component(.year, from: selectedDate)
                            
                            Picker("Year", selection: Binding(
                                get: { selectedYear },
                                set: { newYear in
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    
                                    let isCurrentlySecondHalf = calendar.component(.month, from: selectedDate) > 6
                                    
                                    if newYear == currentYear && isCurrentlySecondHalf {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            halfSelection = 1
                                            selectedDate = calendar.date(from: DateComponents(year: newYear, month: 1, day: 1))!
                                        }
                                    } else {
                                        let month = isCurrentlySecondHalf ? 7 : 1
                                        selectedDate = calendar.date(from: DateComponents(year: newYear, month: month, day: 1))!
                                    }
                                }
                            )) {
                                ForEach((1970...currentYear).reversed(), id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.wheel)

                            Picker("Half", selection: $halfSelection) {
                                Text("First Half").tag(1)
                                Text("Second Half").tag(2)
                            }
                            .pickerStyle(.wheel)
                            .onChange(of: halfSelection) { oldValue, newValue in
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                
                                if selectedYear == currentYear && currentHalf == 1 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        halfSelection = 1
                                    }
                                } else {
                                    let month = newValue == 1 ? 1 : 7
                                    selectedDate = calendar.date(from: DateComponents(year: selectedYear, month: month, day: 1))!
                                }
                            }
                        }
                    case .year:
                        Picker("Year", selection: Binding(
                            get: { calendar.component(.year, from: selectedDate) },
                            set: { newYear in
                                selectedDate = calendar.date(from: DateComponents(year: newYear, month: 1, day: 1))!
                            }
                        )) {
                            ForEach((1970...calendar.component(.year, from: now)).reversed(), id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                }
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        
        private func getPastWeeks() -> [Date] {
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return stride(from: 0, through: 520, by: 1).compactMap { weekOffset in
                calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeekStart)
            }
        }
        
        private func getPastMonths() -> [Date] {
            let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return stride(from: 0, through: 120, by: 1).compactMap { monthOffset in
                calendar.date(byAdding: .month, value: -monthOffset, to: currentMonth)
            }
        }
    }
    
    private func fetchData() async {
        switch selectedTimePeriod {
            case .day:
                for nutrient in ["Protein", "Carbs", "Fats"] {
                    let data = await DayNutrientData.fetchDayData(
                        for: selectedDate,
                        nutrientType: nutrient,
                        healthStore: healthStore
                    )
                    hourlyData[nutrient] = data
                }
            case .week:
                let calendar = Calendar.current
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
                
                for nutrient in ["Protein", "Carbs", "Fats"] {
                    var weeklyData: [WeekNutrientData] = []
                    
                    for dayOffset in 0...6 {
                        let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                        
                        let value = await withCheckedContinuation { continuation in
                            healthStore.fetchNutrientDataForInterval(
                                nutrientType: nutrient.lowercased(),
                                start: dayStart,
                                end: dayEnd
                            ) { value, _ in
                                continuation.resume(returning: value)
                            }
                        }
                        
                        if let value = value {
                            weeklyData.append(WeekNutrientData(
                                date: dayStart,
                                totalValue: value,
                                nutrient: nutrient,
                                dayOfWeek: calendar.component(.weekday, from: dayStart)
                            ))
                        }
                    }
                    
                    weekData[nutrient] = weeklyData
                }
                
            case .month:
               let calendar = Calendar.current
               let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
               let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
               
               // Find the closest Sunday before the start of the month
               var firstWeekStart = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: monthStart), to: monthStart)!
               if calendar.component(.weekday, from: monthStart) != 1 {
                   firstWeekStart = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: monthStart) - 1), to: monthStart)!
               }
               
               // Find the closest Saturday after the end of the month
               var lastWeekEnd = calendar.date(byAdding: .day, value: 6 - calendar.component(.weekday, from: nextMonth), to: nextMonth)!
               if calendar.component(.weekday, from: nextMonth) != 7 {
                   lastWeekEnd = calendar.date(byAdding: .day, value: 7 - calendar.component(.weekday, from: nextMonth), to: nextMonth)!
               }
               
               for nutrient in ["Protein", "Carbs", "Fats"] {
                   var monthlyData: [MonthNutrientData] = []
                   let weekRange = stride(from: firstWeekStart, to: lastWeekEnd, by: 7 * 24 * 60 * 60)
                   
                   for (weekNumber, weekStart) in weekRange.enumerated() {
                       let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
                       var weekTotal: Double = 0
                       var validDays = 0
                       
                       let dayRange = stride(from: weekStart, through: min(weekEnd, lastWeekEnd), by: 24 * 60 * 60)
                       
                       for currentDay in dayRange {
                           let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
                           let value = await withCheckedContinuation { continuation in
                               healthStore.fetchNutrientDataForInterval(
                                   nutrientType: nutrient.lowercased(),
                                   start: currentDay,
                                   end: nextDay
                               ) { value, _ in
                                   continuation.resume(returning: value)
                               }
                           }
                           
                           if let value = value, value > 0 {
                               weekTotal += value
                               validDays += 1
                           }
                       }
                       
                       if validDays > 0 {
                           monthlyData.append(MonthNutrientData(
                               weekStart: weekStart,
                               weekEnd: weekEnd,
                               averageValue: weekTotal / Double(validDays),
                               nutrient: nutrient,
                               weekNumber: weekNumber + 1
                           ))
                       }
                   }
                   
                   monthData[nutrient] = monthlyData
               }
            
        case .sixMonth:
            let calendar = Calendar.current
            let month = calendar.component(.month, from: selectedDate)
            let year = calendar.component(.year, from: selectedDate)
            let isFirstHalf = month <= 6
            let startMonth = isFirstHalf ? 1 : 7
            
            let halfYearStart = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))!
            
            for nutrient in ["Protein", "Carbs", "Fats"] {
                var sixMonthPoints: [SixMonthNutrientData] = []
                
                for monthOffset in 0...5 {
                    let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: halfYearStart)!
                    let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
                    var monthTotal: Double = 0
                    var validDays = 0
                    
                    var currentDay = monthStart
                    while currentDay < monthEnd {
                        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
                        let value = await withCheckedContinuation { continuation in
                            healthStore.fetchNutrientDataForInterval(
                                nutrientType: nutrient.lowercased(),
                                start: currentDay,
                                end: nextDay
                            ) { value, _ in
                                continuation.resume(returning: value)
                            }
                        }
                        
                        if let value = value, value > 0 {
                            monthTotal += value
                            validDays += 1
                        }
                        currentDay = nextDay
                    }
                    
                    if validDays > 0 {
                        sixMonthPoints.append(SixMonthNutrientData(
                            monthStart: monthStart,
                            averageValue: monthTotal / Double(validDays),
                            nutrient: nutrient,
                            monthIndex: monthOffset
                        ))
                    }
                }
                
                sixMonthData[nutrient] = sixMonthPoints
            }
                
        case .year:
            let calendar = Calendar.current
            let year = calendar.component(.year, from: selectedDate)
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            
            for nutrient in ["Protein", "Carbs", "Fats"] {
                var yearPoints: [YearNutrientData] = []
                
                for monthOffset in 0...11 {
                    let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: yearStart)!
                    let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
                    var monthTotal: Double = 0
                    var validDays = 0
                    
                    var currentDay = monthStart
                    while currentDay < monthEnd {
                        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
                        let value = await withCheckedContinuation { continuation in
                            healthStore.fetchNutrientDataForInterval(
                                nutrientType: nutrient.lowercased(),
                                start: currentDay,
                                end: nextDay
                            ) { value, _ in
                                continuation.resume(returning: value)
                            }
                        }
                        
                        if let value = value, value > 0 {
                            monthTotal += value
                            validDays += 1
                        }
                        currentDay = nextDay
                    }
                    
                    if validDays > 0 {
                        yearPoints.append(YearNutrientData(
                            monthStart: monthStart,
                            averageValue: monthTotal / Double(validDays),
                            nutrient: nutrient,
                            monthOfYear: monthOffset + 1
                        ))
                    }
                }
                
                yearData[nutrient] = yearPoints
            }
        }
    }
    
    private func fetchHourlyNutrientData() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        _ = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        for nutrient in ["Protein", "Carbs", "Fats"] {
            var hourlyData: [NutrientDataPoint] = []
            
            for hour in 0...23 {
                let intervalStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
                let intervalEnd = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!
                
                let value = await withCheckedContinuation { continuation in
                    healthStore.fetchNutrientDataForInterval(
                        nutrientType: nutrient.lowercased(),
                        start: intervalStart,
                        end: intervalEnd
                    ) { value, _ in
                        continuation.resume(returning: value)
                    }
                }
                
                if let value = value {
                    hourlyData.append(NutrientDataPoint(
                        date: intervalStart,
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

struct DietPlan: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let strictRanges: (carbs: ClosedRange<Double>, protein: ClosedRange<Double>, fat: ClosedRange<Double>)
    let lenientRanges: (carbs: ClosedRange<Double>, protein: ClosedRange<Double>, fat: ClosedRange<Double>)
    
    static func == (lhs: DietPlan, rhs: DietPlan) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum StrictLevel: Int, CaseIterable {
    case strict = 0
    case medium = 1
    case lenient = 2
}

struct CalorieNeedsCard: View {
    let tdee: Double
    let exerciseCalories: Double
    let foodCalories: Double
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Daily Energy Balance")
                .font(.headline)
            
            HStack {
                Spacer()
                VStack(alignment: .center) {
                    Text("Base Needs")
                        .font(.subheadline)
                    Text("\(Int(tdee))")
                        .font(.title2.bold())
                }
                Spacer()
                Text("+")
                Spacer()
                VStack(alignment: .center) {
                    Text("Exercise")
                        .font(.subheadline)
                    Text("\(Int(exerciseCalories))")
                        .font(.title2.bold())
                }
                Spacer()
                Text("-")
                Spacer()
                VStack(alignment: .center) {
                    Text("Food")
                        .font(.subheadline)
                    Text("\(Int(foodCalories))")
                        .font(.title2.bold())
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
}

struct ExploreDietsCard: View {
    var body: some View {
        NavigationLink(destination: DietsExplorerView()) {
            VStack {
                Text("Explore Diets")
                    .font(.title)
                    .bold()
                Text("Discover different dietary approaches and find what works best for you")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 5)
            .padding()
        }
    }
}

class HealthInsightsViewModel: ObservableObject {
    @Published var tdee: Double = 2000
    @Published var todayExerciseCalories: Double = 0
    @Published var todayFoodCalories: Double = 0
    
    func calculateTDEE() -> Double {
        // Implement TDEE calculation logic
        return tdee
    }
}

func getRangesForStrictLevel(diet: DietPlan, level: StrictLevel) -> (carbs: ClosedRange<Double>, protein: ClosedRange<Double>, fat: ClosedRange<Double>) {
    switch level {
    case .strict:
        return diet.strictRanges
    case .lenient:
        return diet.lenientRanges
    case .medium:
        return (
            carbs: (diet.strictRanges.carbs.lowerBound + diet.lenientRanges.carbs.lowerBound)/2...(diet.strictRanges.carbs.upperBound + diet.lenientRanges.carbs.upperBound)/2,
            protein: (diet.strictRanges.protein.lowerBound + diet.lenientRanges.protein.lowerBound)/2...(diet.strictRanges.protein.upperBound + diet.lenientRanges.protein.upperBound)/2,
            fat: (diet.strictRanges.fat.lowerBound + diet.lenientRanges.fat.lowerBound)/2...(diet.strictRanges.fat.upperBound + diet.lenientRanges.fat.upperBound)/2
        )
    }
}

struct DietsExplorerView: View {
    var body: some View {
        Text("Coming Soon")
    }
}
