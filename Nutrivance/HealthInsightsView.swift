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
    let averageValue: Double
    let nutrient: String
    let weekOfMonth: Int
    
    @MainActor
    static func fetchMonthData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [MonthNutrientData] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        var monthData: [MonthNutrientData] = []
        
        let weeksInMonth = calendar.range(of: .weekOfMonth, in: .month, for: monthStart)!
        
        for week in weeksInMonth {
            let weekStart = calendar.date(bySetting: .weekday, value: calendar.firstWeekday, of: monthStart)!
            let weekStartDate = calendar.date(byAdding: .weekOfMonth, value: week - 1, to: weekStart)!
            let weekEndDate = calendar.date(byAdding: .weekOfMonth, value: 1, to: weekStartDate)!
            
            var weekTotal: Double = 0
            var daysCount = 0
            
            for dayOffset in 0...6 {
                let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStartDate)!
                if dayDate < weekEndDate {
                    let value = await withCheckedContinuation { continuation in
                        healthStore.fetchNutrientDataForInterval(
                            nutrientType: nutrientType.lowercased(),
                            start: dayDate,
                            end: calendar.date(byAdding: .day, value: 1, to: dayDate)!
                        ) { value, _ in
                            continuation.resume(returning: value ?? 0)
                        }
                    }
                    weekTotal += value
                    daysCount += 1
                }
            }
            
            monthData.append(MonthNutrientData(
                weekStart: weekStartDate,
                averageValue: daysCount > 0 ? weekTotal / Double(daysCount) : 0,
                nutrient: nutrientType,
                weekOfMonth: week
            ))
        }
        
        return monthData
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
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -5, to: date)!
        var sixMonthData: [SixMonthNutrientData] = []
        
        for monthOffset in 0...5 {
            let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: sixMonthsAgo)!
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
            
            sixMonthData.append(SixMonthNutrientData(
                monthStart: monthStart,
                averageValue: value,
                nutrient: nutrientType,
                monthIndex: monthOffset
            ))
        }
        
        return sixMonthData
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

struct DayChartView: View, NutrientChartView {
    let nutrientData: [String: [NutrientDataPoint]]
    let startOfDay: Date
    let endOfDay: Date
    @Binding var selectedPoint: NutrientDataPoint?
    
    var body: some View {
        if (nutrientData["Protein"]?.isEmpty ?? true) &&
              (nutrientData["Carbs"]?.isEmpty ?? true) &&
              (nutrientData["Fats"]?.isEmpty ?? true) {
               Text("No data")
                   .font(.title2)
                   .foregroundStyle(.secondary)
                   .frame(height: 300)
        } else {
            Chart {
                ForEach(Array(0..<24), id: \.self) { hour in
                    if let date = Calendar.current.date(byAdding: .hour, value: hour, to: startOfDay) {
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
                    .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .chartXAxis {
                AxisMarks(values: [startOfDay,
                                   Calendar.current.date(byAdding: .hour, value: 6, to: startOfDay)!,
                                   Calendar.current.date(byAdding: .hour, value: 12, to: startOfDay)!,
                                   Calendar.current.date(byAdding: .hour, value: 18, to: startOfDay)!,
                                   endOfDay]) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))
                        }
                    }
                }
            }
            .chartXScale(domain: startOfDay...endOfDay)
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
    }
}

struct WeekChartView: View, NutrientChartView {
    let weekData: [String: [WeekNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    
    var body: some View {
        if (weekData["Protein"]?.isEmpty ?? true) &&
              (weekData["Carbs"]?.isEmpty ?? true) &&
              (weekData["Fats"]?.isEmpty ?? true) {
            Text("No data")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 300)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Chart {
                ForEach(weekData["Protein"] ?? []) { point in
                    PointMark(
                        x: .value("Day", point.dayOfWeek),
                        y: .value("Grams", point.totalValue)
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                }
                
                ForEach(weekData["Carbs"] ?? []) { point in
                    PointMark(
                        x: .value("Day", point.dayOfWeek),
                        y: .value("Grams", point.totalValue)
                    )
                    .foregroundStyle(.green)
                    .symbol(.circle)
                }
                
                ForEach(weekData["Fats"] ?? []) { point in
                    PointMark(
                        x: .value("Day", point.dayOfWeek),
                        y: .value("Grams", point.totalValue)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let xPosition = location.x - geometry.frame(in: .local).origin.x
                            guard let weekday = proxy.value(atX: xPosition) as Int? else { return }
                            
                            let allPoints = weekData.values.flatMap { weekPoints in
                                weekPoints.map { point in
                                    NutrientDataPoint(date: point.date, value: point.totalValue, nutrient: point.nutrient)
                                }
                            }
                            selectedPoint = allPoints.first { Calendar.current.component(.weekday, from: $0.date) == weekday }
                        }
                }
            }
        }
    }
}

struct MonthChartView: View, NutrientChartView {
    let monthData: [String: [MonthNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    
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
                ForEach(monthData["Protein"] ?? []) { point in
                    PointMark(
                        x: .value("Week", point.weekOfMonth),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                }
                
                ForEach(monthData["Carbs"] ?? []) { point in
                    PointMark(
                        x: .value("Week", point.weekOfMonth),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.green)
                    .symbol(.circle)
                }
                
                ForEach(monthData["Fats"] ?? []) { point in
                    PointMark(
                        x: .value("Week", point.weekOfMonth),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
                
                if let selected = selectedPoint {
                    RuleMark(
                        x: .value("Selected", Calendar.current.component(.weekOfMonth, from: selected.date))
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .chartXScale(domain: 1...5)  // Show all 5 weeks
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        Text("Week \(value.index + 1)")
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let xPosition = location.x - geometry.frame(in: .local).origin.x
                            guard let weekOfMonth = proxy.value(atX: xPosition) as Int? else { return }
                            
                            let allPoints = monthData.values.flatMap { monthPoints in
                                monthPoints.map { point in
                                    NutrientDataPoint(date: point.weekStart, value: point.averageValue, nutrient: point.nutrient)
                                }
                            }
                            selectedPoint = allPoints.first { Calendar.current.component(.weekOfMonth, from: $0.date) == weekOfMonth }
                        }
                }
            }
        }
    }
}

struct SixMonthChartView: View, NutrientChartView {
    let sixMonthData: [String: [SixMonthNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    
    private var currentHalfYear: String {
        let currentMonth = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        return "\(year) \(currentMonth <= 6 ? "First" : "Second") Half"
    }
    
    var body: some View {
        Chart {
            ForEach(sixMonthData["Protein"] ?? []) { point in
                PointMark(
                    x: .value("Month", point.monthIndex),
                    y: .value("Grams", point.averageValue)
                )
                .foregroundStyle(.red)
                .symbol(.circle)
            }
            
            ForEach(sixMonthData["Carbs"] ?? []) { point in
                PointMark(
                    x: .value("Month", point.monthIndex),
                    y: .value("Grams", point.averageValue)
                )
                .foregroundStyle(.green)
                .symbol(.circle)
            }
            
            ForEach(sixMonthData["Fats"] ?? []) { point in
                PointMark(
                    x: .value("Month", point.monthIndex),
                    y: .value("Grams", point.averageValue)
                )
                .foregroundStyle(.blue)
                .symbol(.circle)
            }
            
            if let selected = selectedPoint {
                RuleMark(
                    x: .value("Selected", Calendar.current.component(.month, from: selected.date))
                )
                .foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXAxis {
            let currentMonth = Calendar.current.component(.month, from: Date())
            let startMonth = currentMonth <= 6 ? 1 : 7
            AxisMarks(values: Array(startMonth...startMonth+5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    Text(Calendar.current.monthSymbols[value.as(Int.self)! - 1].prefix(3))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        let xPosition = location.x - geometry.frame(in: .local).origin.x
                        guard let date = proxy.value(atX: xPosition) as Date? else { return }
                        
                        let currentMonth = Calendar.current.component(.month, from: Date())
                        let startMonth = currentMonth <= 6 ? 1 : 7
                        let allPoints = sixMonthData.values.flatMap { points in
                            points.filter { point in
                                let pointMonth = Calendar.current.component(.month, from: point.monthStart)
                                return pointMonth >= startMonth && pointMonth < startMonth + 6
                            }.map { point in
                                NutrientDataPoint(date: point.monthStart, value: point.averageValue, nutrient: point.nutrient)
                            }
                        }
                        selectedPoint = allPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                    }
            }
        }
    }
}

struct YearChartView: View, NutrientChartView {
    let yearData: [String: [YearNutrientData]]
    @Binding var selectedPoint: NutrientDataPoint?
    
    var xAxisValues: [Date] {
        let year = Calendar.current.component(.year, from: Date())
        let startOfYear = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))!
        let endOfYear = Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31))!
        return [startOfYear, endOfYear]
    }
    
    var body: some View {
        if (yearData["Protein"]?.isEmpty ?? true) &&
              (yearData["Carbs"]?.isEmpty ?? true) &&
              (yearData["Fats"]?.isEmpty ?? true) {
               Text("No data")
                   .font(.title2)
                   .foregroundStyle(.secondary)
                   .frame(height: 300)
        } else {
            Chart {
                ForEach(yearData["Protein"] ?? []) { point in
                    PointMark(
                        x: .value("Month", point.monthOfYear),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                }
                
                ForEach(yearData["Carbs"] ?? []) { point in
                    PointMark(
                        x: .value("Month", point.monthOfYear),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.green)
                    .symbol(.circle)
                }
                
                ForEach(yearData["Fats"] ?? []) { point in
                    PointMark(
                        x: .value("Month", point.monthOfYear),
                        y: .value("Grams", point.averageValue)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
                
                if let selected = selectedPoint {
                    RuleMark(
                        x: .value("Selected", Calendar.current.component(.month, from: selected.date))
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        Text(value.as(Date.self)?.formatted(.dateTime.month(.abbreviated)) ?? "")
                    }
                }
            }
            .chartXScale(domain: xAxisValues.first!...xAxisValues.last!)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let xPosition = location.x - geometry.frame(in: .local).origin.x
                            guard let date = proxy.value(atX: xPosition) as Date? else { return }
                            
                            let year = Calendar.current.component(.year, from: Date())
                            let allPoints = yearData.values.flatMap { points in
                                points.filter { point in
                                    Calendar.current.component(.year, from: point.monthStart) == year
                                }.map { point in
                                    NutrientDataPoint(date: point.monthStart, value: point.averageValue, nutrient: point.nutrient)
                                }
                            }
                            selectedPoint = allPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                        }
                }
            }
        }
    }
}


struct HealthInsightsView: View {
    @State private var selectedPoint: NutrientDataPoint?
    @State private var selectedDate: Date = Date()
    @State private var weekData: [String: [WeekNutrientData]] = [:]
    @State private var monthData: [String: [MonthNutrientData]] = [:]
    @State private var sixMonthData: [String: [SixMonthNutrientData]] = [:]
    @State private var yearData: [String: [YearNutrientData]] = [:]
    @State private var animationPhase: Double = 0
    
    enum TimePeriod: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case sixMonth = "6 Months"
        case year = "Year"
    }
    
    @State private var selectedTimePeriod: TimePeriod = .day
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
                return "\(year) \(month <= 6 ? "First" : "Second") Half"
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
                AnyView(DayChartView(nutrientData: nutrientData,
                            startOfDay: startOfSelectedDay,
                            endOfDay: endOfSelectedDay,
                            selectedPoint: $selectedPoint))
            case .week:
                AnyView(WeekChartView(weekData: weekData, selectedPoint: $selectedPoint))
            case .month:
                AnyView(MonthChartView(monthData: monthData, selectedPoint: $selectedPoint))
            case .sixMonth:
            AnyView(SixMonthChartView(sixMonthData: sixMonthData, selectedPoint: $selectedPoint))
            case .year:
            AnyView(YearChartView(yearData: yearData, selectedPoint: $selectedPoint))
        }
    }
    
    private var timeNavigationHeader: some View {
        HStack {
            Text(dateTitle)
                .font(.title2.bold())
            
            Spacer()
            
            HStack(spacing: 20) {
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
                        selectedDate = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: today), month: halfYearStart, day: 1))!
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
                    Task {
                        await fetchData()
                    }
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
                    Task {
                        await fetchData()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .padding(8)
                .hoverEffect(.automatic)
            }
        }
        .padding()
    }
    
    private var chartContent: some View {
        Group {
            let hasData: Bool = {
                switch selectedTimePeriod {
                    case .day: return !(nutrientData.values.allSatisfy { $0.isEmpty })
                    case .week: return !(weekData.values.allSatisfy { $0.isEmpty })
                    case .month: return !(monthData.values.allSatisfy { $0.isEmpty })
                    case .sixMonth: return !(sixMonthData.values.allSatisfy { $0.isEmpty })
                    case .year: return !(yearData.values.allSatisfy { $0.isEmpty })
                }
            }()
            
            if hasData {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        chartView
                            .frame(width: UIScreen.main.bounds.width - 32)
                            .frame(height: 300)
                            .padding()
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
            // Date header based on time period
            switch selectedTimePeriod {
            case .day:
                Text(selected.date, format: .dateTime.month(.abbreviated).day())
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .week:
                Text(selected.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .month:
                let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: selected.date)!
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).day())) - \(weekEnd.formatted(.dateTime.month(.abbreviated).day())), \(selected.date.formatted(.dateTime.year()))")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .sixMonth:
                Text(selected.date.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .year:
                Text(selected.date.formatted(.dateTime.year()))
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            }
            
            // Nutrient values
            ForEach(["Protein", "Carbs", "Fats"], id: \.self) { nutrient in
                let value: Double = {
                    switch selectedTimePeriod {
                    case .day:
                        return nutrientData[nutrient]?.first(where: {
                            Calendar.current.compare($0.date, to: selected.date, toGranularity: .hour) == .orderedSame
                        })?.value ?? 0
                    case .week:
                        return weekData[nutrient]?.first(where: {
                            Calendar.current.compare($0.date, to: selected.date, toGranularity: .day) == .orderedSame
                        })?.totalValue ?? 0
                    case .month:
                        return monthData[nutrient]?.first(where: {
                            Calendar.current.compare($0.weekStart, to: selected.date, toGranularity: .weekOfMonth) == .orderedSame
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
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTimePeriod) { oldValue, newValue in
                    Task {
                        await fetchData()
                    }
                }
                
                timeNavigationHeader
                chartContent
                if let selected = selectedPoint {
                    selectedPointDetail(selected)
                }
                nutrientLegend
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
    
    private func fetchData() async {
        switch selectedTimePeriod {
            case .day:
                await fetchHourlyNutrientData()
                
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
                
                for nutrient in ["Protein", "Carbs", "Fats"] {
                    var monthlyData: [MonthNutrientData] = []
                    var currentWeekStart = monthStart
                    var weekNumber = 1
                    
                    while currentWeekStart < nextMonth {
                        let weekEnd = calendar.date(byAdding: .weekOfMonth, value: 1, to: currentWeekStart)!
                        var weekTotal: Double = 0
                        var validDays = 0
                        
                        var currentDay = currentWeekStart
                        while currentDay < weekEnd {
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
                            currentDay = nextDay
                        }
                        
                        if validDays > 0 {
                            monthlyData.append(MonthNutrientData(
                                weekStart: currentWeekStart,
                                averageValue: weekTotal / Double(validDays),
                                nutrient: nutrient,
                                weekOfMonth: weekNumber
                            ))
                        }
                        
                        currentWeekStart = weekEnd
                        weekNumber += 1
                    }
                    
                    monthData[nutrient] = monthlyData
                }
                
            case .sixMonth:
                let calendar = Calendar.current
                let sixMonthsAgo = calendar.date(byAdding: .month, value: -5, to: selectedDate)!
                
                for nutrient in ["Protein", "Carbs", "Fats"] {
                    var sixMonthPoints: [SixMonthNutrientData] = []
                    
                    for monthOffset in 0...5 {
                        let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: sixMonthsAgo)!
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
                let yearStart = calendar.date(from: calendar.dateComponents([.year], from: selectedDate))!
                
                for nutrient in ["Protein", "Carbs", "Fats"] {
                    var yearlyPoints: [YearNutrientData] = []
                    
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
                            yearlyPoints.append(YearNutrientData(
                                monthStart: monthStart,
                                averageValue: monthTotal / Double(validDays),
                                nutrient: nutrient,
                                monthOfYear: calendar.component(.month, from: monthStart)
                            ))
                        }
                    }
                    
                    yearData[nutrient] = yearlyPoints
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

