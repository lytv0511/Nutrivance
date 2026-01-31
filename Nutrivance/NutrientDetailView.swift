import SwiftUI
import Charts
import HealthKit

enum CardType: String {
    case today = "Today's Consumption"
    case weekly = "Weekly Consumption"
    case monthly = "Monthly Consumption"
    case recommended = "Recommended Intake"
    case foods = "Foods Rich In"
    case benefits = "Benefits"
}

struct SingleNutrientDayData: Identifiable {
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

struct SingleNutrientWeekData: Identifiable {
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

struct SingleNutrientMonthData: Identifiable {
    let id = UUID()
    let weekStart: Date
    let averageValue: Double
    let nutrient: String
    let weekOfMonth: Int
    
    @MainActor
    static func fetchMonthData(for date: Date, nutrientType: String, healthStore: HealthKitManager) async -> [MonthNutrientData] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        
        // Find the first Sunday on or before month start
        var weekStart = monthStart
        while calendar.component(.weekday, from: weekStart) != 1 { // 1 is Sunday
            weekStart = calendar.date(byAdding: .day, value: -1, to: weekStart)!
        }
        
        var monthData: [MonthNutrientData] = []
        var weekNumber = 1
        var currentWeekStart = weekStart
        
        while currentWeekStart < nextMonth {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: currentWeekStart)!
            var weekTotal: Double = 0
            var validDays = 0
            
            var currentDay = currentWeekStart
            while currentDay < weekEnd {
                if currentDay >= monthStart && currentDay < nextMonth {
                    let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
                    let value = await withCheckedContinuation { continuation in
                        healthStore.fetchNutrientDataForInterval(
                            nutrientType: nutrientType.lowercased(),
                            start: currentDay,
                            end: nextDay
                        ) { value, _ in
                            continuation.resume(returning: value ?? 0)
                        }
                    }
                    
                    if value > 0 {
                        weekTotal += value
                        validDays += 1
                    }
                }
                currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
            }
            
            if validDays > 0 {
                monthData.append(MonthNutrientData(
                    weekStart: currentWeekStart,
                    weekEnd: weekEnd,
                    averageValue: weekTotal / Double(validDays),
                    nutrient: nutrientType,
                    weekNumber: weekNumber
                ))
            }
            
            currentWeekStart = weekEnd
            weekNumber += 1
        }
        
        return monthData
    }

}


struct NutrientDetailView: View {
    let nutrientName: String
    @State private var showDetailSheet = false
    @StateObject private var healthStore = HealthKitManager()
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var selectedCard: CardType = .today
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var dayData: [DayNutrientData] = []
    @State private var weekData: [WeekNutrientData] = []
    @State private var monthData: [MonthNutrientData] = []
    @State private var nutrientData: [String: [NutrientDataPoint]] = [:]
    @State private var selectedPoint: NutrientDataPoint?
    var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    private func computeLayout(for size: CGSize) -> (columns: Int, cardWidth: CGFloat) {
        let availableWidth = size.width
        let minPadding: CGFloat = 16
        let sidePadding: CGFloat = 24
        
        let layout = switch (availableWidth, columnVisibility) {
        // No Sidebar (.detailOnly)
        case (1366..., .detailOnly):
            (3, availableWidth / 3 - minPadding * 2)
        case (1194...1365, .detailOnly):
            (3, (availableWidth - minPadding * 4) / 3)
        case (1024...1193, .detailOnly):
            (3, (availableWidth - minPadding * 4) / 3)
        case (981...1023, .detailOnly):
            (2, (availableWidth - minPadding * 3) / 2)
        case (820...980, .detailOnly):
            (2, (availableWidth - minPadding * 3) / 2)
        case (744...819, .detailOnly):
            (1, availableWidth - sidePadding * 2 - 40)
        case (694...743, .detailOnly):
            (1, availableWidth - sidePadding * 2 + 100)  // Wider
        case (639...693, .detailOnly):
            (1, availableWidth - sidePadding * 2 + 120)  // Wider
        // With Sidebar (all good, keeping as is)
        case (1366..., _):
            (2, (availableWidth - minPadding * 4) / 2)
        case (1024...1365, _):
            (2, (availableWidth - minPadding * 4) / 2)
        case (820...1023, _):
            (2, (availableWidth - minPadding * 4) / 2)
        case (744...819, _):
            (2, (availableWidth - minPadding * 4) / 2)
        case (639...743, _):
            (2, (availableWidth - minPadding * 4) / 2)
        default:
            (1, availableWidth - sidePadding * 2)
        }
        
        return layout
    }

    private func getNutrientColor() -> Color {
        switch nutrientName {
        case "Protein": return .red
        case "Carbs": return .green
        case "Fats": return .blue
        default: return .primary
        }
    }

    private func getSymbolName(for cardType: CardType) -> String {
        switch cardType {
        case .today: return "chart.bar.fill"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .recommended: return "target"
        case .foods: return "leaf.fill"
        case .benefits: return "heart.fill"
        }
    }

    private func getCardColor(for cardType: CardType) -> Color {
        switch cardType {
        case .today: return .red
        case .weekly: return .green
        case .monthly: return .blue
        case .recommended: return .orange
        case .foods: return .purple
        case .benefits: return .yellow
        }
    }

    @ViewBuilder
    private var selectedDetailView: some View {
        switch selectedCard {
        case .today:
            DayChartView(
                hourlyData: [nutrientName: dayData],
                selectedPoint: $selectedPoint,
                selectedDiet: nil,
                strictLevel: .medium,
                tdee: 2000
            )
            .frame(height: horizontalSizeClass == .compact ? 250 : 300)
            .padding()
            
        case .weekly:
            WeekChartView(
                weekData: [nutrientName: weekData],
                selectedPoint: $selectedPoint,
                selectedDiet: nil,
                strictLevel: .medium,
                tdee: 2000
            )
            .frame(height: horizontalSizeClass == .compact ? 250 : 300)
            .padding()
            
        case .monthly:
            MonthChartView(
                monthData: [nutrientName: monthData],
                selectedPoint: $selectedPoint,
                selectedDiet: nil,
                strictLevel: .medium,
                tdee: 2000,
                viewingMonth: selectedDate
            )
            .frame(height: horizontalSizeClass == .compact ? 250 : 300)
            .padding()
        case .recommended:
            RecommendedIntakeDetailView(nutrientName: nutrientName)
        case .foods:
            FoodSourcesDetailView(nutrientName: nutrientName)
        case .benefits:
            BenefitsDetailView(nutrientName: nutrientName)
        }
    }

    private func fetchAllData() async {
        let dayResult = await DayNutrientData.fetchDayData(
            for: selectedDate,
            nutrientType: nutrientName,
            healthStore: healthStore
        )
        dayData = dayResult
        
        let weekResult = await WeekNutrientData.fetchWeekData(
            for: selectedDate,
            nutrientType: nutrientName,
            healthStore: healthStore
        )
        weekData = weekResult
        
        let monthResult = await MonthNutrientData.fetchMonthData(
            for: selectedDate,
            nutrientType: nutrientName,
            healthStore: healthStore
        )
        monthData = monthResult
    }
    
    private func selectedPointDetail(_ selected: NutrientDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selectedCard {
            case .today:
                let hourStart = Calendar.current.component(.hour, from: selected.date)
                let hourEnd = hourStart + 1
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).day())) \(String(format: "%02d:00-%02d:00", hourStart, hourEnd)) (total):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .weekly:
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).day())) (total):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            case .monthly:
                let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: selected.date)!
                Text("\(selected.date.formatted(.dateTime.month(.abbreviated).day())) - \(weekEnd.formatted(.dateTime.month(.abbreviated).day())), \(selected.date.formatted(.dateTime.year())) (average):")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }

            HStack {
                Text(nutrientName)
                    .font(.headline)
                    .foregroundStyle(getNutrientColor())
                Spacer()
                Text("\(Int(selected.value))")
                    .font(.title3.bold())
                Text("grams")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        themeColors[nutrientName] ?? Color(.systemBackground),
                        Color(.systemBackground)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Text(selectedDate.formatted(.dateTime.day().month().year()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    GeometryReader { geometry in
                        let layout = computeLayout(for: geometry.size)
                        
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: layout.columns),
                                spacing: 16
                            ) {
                                // Use the same card layout for all nutrient types
                                ForEach([CardType.today, .weekly, .monthly, .recommended, .foods, .benefits], id: \.self) { cardType in
                                    NutrientCard(
                                        type: cardType,
                                        nutrientName: nutrientName,
                                        selectedDate: $selectedDate,
                                        isSelected: selectedCard == cardType,
                                        healthStore: healthStore,
                                        titleColor: getNutrientColor(),
                                        symbolName: getSymbolName(for: cardType),
                                        cardWidth: layout.cardWidth
                                    )
                                    .onTapGesture {
                                        withAnimation(.spring()) {
                                            selectedCard = cardType
                                            selectedPoint = nil
                                            if horizontalSizeClass == .compact {
                                                showDetailSheet.toggle() // This will trigger the sheet
                                            }
                                        }
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                    }
                                }
                            }
                            .padding()
                            
                            if let selected = selectedPoint {
                                selectedPointDetail(selected)
                            }
                            
                            if horizontalSizeClass == .regular {
                                // iPad layout - show at bottom
                                selectedDetailView
                                    .task {
                                        await fetchAllData()
                                    }
                                    .onChange(of: selectedDate) { _, _ in
                                        Task {
                                            await fetchAllData()
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 300)
                                    .padding()
                            }
                            
                            // Add CategoryDetailView at the bottom for special categories
                            if ["Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"].contains(nutrientName),
                               let _ = nutrientDetails[nutrientName] {
                                CategoryDetailView(category: nutrientName)
                                    .padding()
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showDetailSheet) {
                selectedDetailView
                    .task {
                        await fetchAllData()
                    }
                    .onChange(of: selectedDate) { _, _ in
                        Task {
                            await fetchAllData()
                        }
                    }
            }
            .navigationTitle(nutrientName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DateButton(selectedDate: $selectedDate, selectedPoint: $selectedPoint, showPicker: $showDatePicker)
                }
            }
        }
    }
}

struct NutrientCard: View {
    let type: CardType
    let nutrientName: String
    @Binding var selectedDate: Date
    let isSelected: Bool
    let healthStore: HealthKitManager
    let titleColor: Color
    let symbolName: String
    let cardWidth: CGFloat
    @State private var nutrientValue: Double = 0
    @State private var weekData: [NutrientDataPoint] = []
    @State private var monthData: [NutrientDataPoint] = []
    @State private var nutrientData: [String: [NutrientDataPoint]] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbolName)
                    .foregroundColor(titleColor)
                    .font(.title2)
                
                Text(type.rawValue + (type == .foods ? " \(nutrientName)" : ""))
                    .font(.headline)
                    .foregroundColor(titleColor)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            switch type {
            case .today:
                todayContent
            case .weekly:
                weeklyContent
            case .monthly:
                monthlyContent
            case .recommended:
                recommendedContent
            case .foods:
                foodsContent
            case .benefits:
                benefitsContent
            }
        }
        .padding()
        .frame(width: max(cardWidth, 0), height: 150)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .task {
            await updateNutrientValue()
            await fetchWeekData()
            await fetchMonthData()
        }
        .onChange(of: selectedDate) { _, _ in
            Task {
                await updateNutrientValue()
                await fetchWeekData()
                await fetchMonthData()
            }
        }
    }
    
    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Int(nutrientValue))")
                    .font(.title.bold())
                Text("grams")
                    .foregroundStyle(.secondary)
            }
            Text(selectedDate.formatted(.dateTime.month().day()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var weeklyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Int(nutrientValue))")
                    .fontWeight(.bold)
                Text("grams weekly")
                    .foregroundStyle(.secondary)
            }
            Text(getWeekRange())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var monthlyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Int(nutrientValue))")
                    .fontWeight(.bold)
                Text("grams monthly")
                    .foregroundStyle(.secondary)
            }
            Text(selectedDate.formatted(.dateTime.month().year()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var recommendedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(getRecommendedRange())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Recommended daily intake")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var foodsContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(getFoodSources().prefix(2), id: \.self) { food in
                Text("• \(food)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    private var benefitsContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(getBenefits().prefix(2), id: \.self) { benefit in
                Text("• \(benefit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func updateNutrientValue() async {
        let calendar = Calendar.current
        
        switch type {
        case .today:
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let value = await fetchNutrientData(start: startOfDay, end: endOfDay)
            await MainActor.run { nutrientValue = value }
            
        case .weekly:
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            let value = await fetchNutrientData(start: weekStart, end: weekEnd)
            await MainActor.run { nutrientValue = value }
            
        case .monthly:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            let value = await fetchNutrientData(start: monthStart, end: monthEnd)
            await MainActor.run { nutrientValue = value }
            
        default:
            break
        }
    }
    
    private func fetchNutrientData(start: Date, end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            healthStore.fetchNutrientDataForInterval(
                nutrientType: nutrientName.lowercased(),
                start: start,
                end: end
            ) { value, _ in
                continuation.resume(returning: value ?? 0)
            }
        }
    }
    
    private func fetchWeekData() async {
        let weekResult = await WeekNutrientData.fetchWeekData(
            for: selectedDate,
            nutrientType: nutrientName,
            healthStore: healthStore
        )
        
        let weekPoints = weekResult.map { weekData in
            NutrientDataPoint(
                date: weekData.date,
                value: weekData.totalValue,
                nutrient: weekData.nutrient
            )
        }
        
        nutrientData[nutrientName] = weekPoints
    }

    private func fetchMonthData() async {
        let monthResult = await MonthNutrientData.fetchMonthData(
            for: selectedDate,
            nutrientType: nutrientName,
            healthStore: healthStore
        )
        
        let monthPoints = monthResult.map { monthData in
            NutrientDataPoint(
                date: monthData.weekStart,
                value: monthData.averageValue,
                nutrient: monthData.nutrient
            )
        }
        
        nutrientData[nutrientName] = monthPoints
    }

    private func getWeekRange() -> String {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(weekStart.formatted(.dateTime.month().day())) - \(weekEnd.formatted(.dateTime.month().day()))"
    }
    
    private func getRecommendedRange() -> String {
        switch nutrientName {
        case "Protein": return "0.8-1.2g per kg body weight"
        case "Carbs": return "45-65% of daily calories"
        case "Fats": return "20-35% of daily calories"
        default: return ""
        }
    }
    
    private func getFoodSources() -> [String] {
        switch nutrientName {
        case "Protein":
            return ["Chicken breast", "Eggs", "Fish", "Greek yogurt", "Lean beef"]
        case "Carbs":
            return ["Brown rice", "Sweet potatoes", "Quinoa", "Oatmeal", "Whole grain bread"]
        case "Fats":
            return ["Avocados", "Nuts", "Olive oil", "Salmon", "Chia seeds"]
        default:
            return []
        }
    }
    
    private func getBenefits() -> [String] {
        switch nutrientName {
        case "Protein":
            return ["Muscle growth and repair",
                    "Immune system support",
                    "Enzyme production",
                    "Hormone regulation"]
        case "Carbs":
            return ["Primary energy source",
                    "Brain function",
                    "Muscle glycogen storage",
                    "Fiber for digestive health"]
        case "Fats":
            return ["Hormone production",
                    "Nutrient absorption",
                    "Brain development",
                    "Cell membrane structure"]
        case "Calories":
            return ["Provide energy for all bodily functions",
                    "Support physical activity",
                    "Essential for metabolism",
                    "Maintain body weight and function"]
        case "Water":
            return ["Hydration and fluid balance",
                    "Temperature regulation",
                    "Nutrient transport",
                    "Joint lubrication and detoxification"]
        case "Fiber":
            return ["Promotes digestive health",
                    "Supports healthy blood sugar levels",
                    "Helps manage cholesterol",
                    "Enhances satiety and weight control"]
        case "Vitamins":
            return ["Support immune function",
                    "Aid in energy production",
                    "Protect vision and skin health",
                    "Help blood clotting and red blood cell formation"]
        case "Minerals":
            return ["Build strong bones and teeth",
                    "Support nerve function",
                    "Regulate muscle contraction",
                    "Maintain fluid and electrolyte balance"]
        case "Phytochemicals":
            return ["Support immune health",
                    "May reduce risk of chronic diseases",
                    "Provide anti-inflammatory effects",
                    "Protect against cell damage"]
        case "Antioxidants":
            return ["Combat oxidative stress",
                    "Protect cells from damage",
                    "May reduce risk of chronic diseases",
                    "Support healthy aging"]
        case "Electrolytes":
            return ["Regulate fluid balance",
                    "Support nerve and muscle function",
                    "Maintain pH balance",
                    "Prevent dehydration and cramping"]
        default:
            return []
        }
    }
}

struct DateButton: View {
    @Binding var selectedDate: Date
    @Binding var selectedPoint: NutrientDataPoint?  // Add this binding
    @Binding var showPicker: Bool
    
    var body: some View {
        Button {
            showPicker.toggle()
            selectedPoint = nil
        } label: {
            Image(systemName: "calendar")
                .symbolVariant(.fill)
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.height(400)])
        }
    }
}

struct RecommendedIntakeDetailView: View {
    let nutrientName: String
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            
            VStack(alignment: .leading) {
                Text("Daily Recommended Intake")
                    .font(.title2.bold())
                    .padding()
                
                if isLandscape && isPad {
                    HStack(alignment: .top, spacing: 24) {
                        switch nutrientName {
                        case "Protein":
                            VStack(alignment: .leading) {
                                Text("General recommendation:")
                                    .font(.headline)
                                Text("• 0.8-1.2g per kg of body weight")
                                Text("• 10-35% of total daily calories")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                Text("Athletes and active individuals:")
                                    .font(.headline)
                                Text("• 1.2-2.0g per kg of body weight")
                                Text("• Higher needs during intense training")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                Text("Factors affecting needs:")
                                    .font(.headline)
                                Text("• Activity level")
                                Text("• Training goals")
                                Text("• Age and gender")
                                Text("• Overall health status")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        case "Carbs":
                            VStack(alignment: .leading) {
                                Text("General recommendation:")
                                    .font(.headline)
                                Text("• 45-65% of total daily calories")
                                Text("• 3-10g per kg of body weight")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                Text("Athletes and active individuals:")
                                    .font(.headline)
                                Text("• 5-12g per kg of body weight")
                                Text("• Higher during intense training periods")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                Text("Types of carbohydrates:")
                                    .font(.headline)
                                Text("• Complex carbs: whole grains, vegetables")
                                Text("• Simple carbs: fruits, sports drinks")
                                Text("• Fiber: 25-38g daily")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        case "Fats":
                            VStack(alignment: .leading) {
                                Text("General recommendation:")
                                    .font(.headline)
                                Text("• 20-35% of total daily calories")
                                Text("• 0.5-1.0g per kg of body weight")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                Text("Essential fatty acids:")
                                    .font(.headline)
                                Text("• Omega-3: 1.1-1.6g daily")
                                Text("• Omega-6: 11-17g daily")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                Text("Types of fats:")
                                    .font(.headline)
                                Text("• Unsaturated: olive oil, nuts, avocados")
                                Text("• Saturated: limit to <10% of calories")
                                Text("• Trans fats: avoid when possible")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        default:
                            Text("No specific recommendations available")
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch nutrientName {
                            case "Protein":
                                Text("General recommendation:")
                                    .font(.headline)
                                Text("• 0.8-1.2g per kg of body weight")
                                Text("• 10-35% of total daily calories")
                                
                                Text("\nAthletes and active individuals:")
                                    .font(.headline)
                                Text("• 1.2-2.0g per kg of body weight")
                                Text("• Higher needs during intense training")
                                
                                Text("\nFactors affecting needs:")
                                    .font(.headline)
                                Text("• Activity level")
                                Text("• Training goals")
                                Text("• Age and gender")
                                Text("• Overall health status")
                                
                            case "Carbs":
                                Text("General recommendation:")
                                    .font(.headline)
                                Text("• 45-65% of total daily calories")
                                Text("• 3-10g per kg of body weight")
                                
                                Text("\nAthletes and active individuals:")
                                    .font(.headline)
                                Text("• 5-12g per kg of body weight")
                                Text("• Higher during intense training periods")
                                
                                Text("\nTypes of carbohydrates:")
                                    .font(.headline)
                                Text("• Complex carbs: whole grains, vegetables")
                                Text("• Simple carbs: fruits, sports drinks")
                                Text("• Fiber: 25-38g daily")
                                
                            case "Fats":
                                Text("General recommendation:")
                                    .font(.headline)
                                Text("• 20-35% of total daily calories")
                                Text("• 0.5-1.0g per kg of body weight")
                                
                                Text("\nEssential fatty acids:")
                                    .font(.headline)
                                Text("• Omega-3: 1.1-1.6g daily")
                                Text("• Omega-6: 11-17g daily")
                                
                                Text("\nTypes of fats:")
                                    .font(.headline)
                                Text("• Unsaturated: olive oil, nuts, avocados")
                                Text("• Saturated: limit to <10% of calories")
                                Text("• Trans fats: avoid when possible")
                                
                            default:
                                Text("No specific recommendations available")
                            }
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding()
        }
    }
}

struct FoodSourcesDetailView: View {
    let nutrientName: String
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            
            VStack(alignment: .leading) {
                Text("Rich Food Sources")
                    .font(.title2.bold())
                
                if isLandscape && isPad {
                    HStack(alignment: .top, spacing: 24) {
                        switch nutrientName {
                        case "Protein":
                            makeSection("Animal Sources:", items: [
                                "Chicken breast (31g per 100g)",
                                "Lean beef (26g per 100g)",
                                "Fish (20-25g per 100g)",
                                "Eggs (6g per large egg)",
                                "Greek yogurt (10g per 100g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeSection("Plant Sources:", items: [
                                "Lentils (9g per 100g cooked)",
                                "Chickpeas (15g per 100g)",
                                "Quinoa (4.4g per 100g cooked)",
                                "Tofu (8g per 100g)",
                                "Almonds (21g per 100g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeSection("Protein Supplements:", items: [
                                "Whey protein powder (24g per 30g)",
                                "Casein protein powder (24g per 30g)",
                                "Pea protein powder (21g per 30g)",
                                "Soy protein powder (22g per 30g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                        case "Carbs":
                            makeSection("Whole Grains:", items: [
                                "Brown rice (23g per 100g cooked)",
                                "Quinoa (21g per 100g cooked)",
                                "Oatmeal (27g per 100g)",
                                "Whole wheat bread (43g per 100g)",
                                "Barley (28g per 100g cooked)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeSection("Starchy Vegetables:", items: [
                                "Sweet potatoes (20g per 100g)",
                                "Potatoes (17g per 100g)",
                                "Corn (19g per 100g)",
                                "Peas (14g per 100g)",
                                "Winter squash (10g per 100g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeSection("Fruits:", items: [
                                "Bananas (23g per 100g)",
                                "Apples (14g per 100g)",
                                "Oranges (12g per 100g)",
                                "Grapes (17g per 100g)",
                                "Mangoes (15g per 100g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                        case "Fats":
                            makeSection("Healthy Oils:", items: [
                                "Olive oil (100g fat per 100ml)",
                                "Avocado oil (100g fat per 100ml)",
                                "Coconut oil (99g fat per 100g)",
                                "MCT oil (100g fat per 100ml)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeSection("Nuts and Seeds:", items: [
                                "Almonds (49g fat per 100g)",
                                "Walnuts (65g fat per 100g)",
                                "Chia seeds (31g fat per 100g)",
                                "Flaxseeds (42g fat per 100g)",
                                "Pumpkin seeds (46g fat per 100g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeSection("Other Sources:", items: [
                                "Avocados (15g fat per 100g)",
                                "Salmon (13g fat per 100g)",
                                "Eggs (11g fat per 100g)",
                                "Dark chocolate (31g fat per 100g)",
                                "Cheese (33g fat per 100g)"
                            ])
                            .frame(maxWidth: .infinity)
                            
                        default:
                            Text("No specific food sources available")
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch nutrientName {
                            case "Protein":
                                Group {
                                    makeSection("Animal Sources:", items: [
                                        "Chicken breast (31g per 100g)",
                                        "Lean beef (26g per 100g)",
                                        "Fish (20-25g per 100g)",
                                        "Eggs (6g per large egg)",
                                        "Greek yogurt (10g per 100g)"
                                    ])
                                    
                                    makeSection("Plant Sources:", items: [
                                        "Lentils (9g per 100g cooked)",
                                        "Chickpeas (15g per 100g)",
                                        "Quinoa (4.4g per 100g cooked)",
                                        "Tofu (8g per 100g)",
                                        "Almonds (21g per 100g)"
                                    ])
                                    
                                    makeSection("Protein Supplements:", items: [
                                        "Whey protein powder (24g per 30g)",
                                        "Casein protein powder (24g per 30g)",
                                        "Pea protein powder (21g per 30g)",
                                        "Soy protein powder (22g per 30g)"
                                    ])
                                }
                                
                            case "Carbs":
                                Group {
                                    makeSection("Whole Grains:", items: [
                                        "Brown rice (23g per 100g cooked)",
                                        "Quinoa (21g per 100g cooked)",
                                        "Oatmeal (27g per 100g)",
                                        "Whole wheat bread (43g per 100g)",
                                        "Barley (28g per 100g cooked)"
                                    ])
                                    
                                    makeSection("Starchy Vegetables:", items: [
                                        "Sweet potatoes (20g per 100g)",
                                        "Potatoes (17g per 100g)",
                                        "Corn (19g per 100g)",
                                        "Peas (14g per 100g)",
                                        "Winter squash (10g per 100g)"
                                    ])
                                    
                                    makeSection("Fruits:", items: [
                                        "Bananas (23g per 100g)",
                                        "Apples (14g per 100g)",
                                        "Oranges (12g per 100g)",
                                        "Grapes (17g per 100g)",
                                        "Mangoes (15g per 100g)"
                                    ])
                                }
                                
                            case "Fats":
                                Group {
                                    makeSection("Healthy Oils:", items: [
                                        "Olive oil (100g fat per 100ml)",
                                        "Avocado oil (100g fat per 100ml)",
                                        "Coconut oil (99g fat per 100g)",
                                        "MCT oil (100g fat per 100ml)"
                                    ])
                                    
                                    makeSection("Nuts and Seeds:", items: [
                                        "Almonds (49g fat per 100g)",
                                        "Walnuts (65g fat per 100g)",
                                        "Chia seeds (31g fat per 100g)",
                                        "Flaxseeds (42g fat per 100g)",
                                        "Pumpkin seeds (46g fat per 100g)"
                                    ])
                                    
                                    makeSection("Other Sources:", items: [
                                        "Avocados (15g fat per 100g)",
                                        "Salmon (13g fat per 100g)",
                                        "Eggs (11g fat per 100g)",
                                        "Dark chocolate (31g fat per 100g)",
                                        "Cheese (33g fat per 100g)"
                                    ])
                                }
                                
                            default:
                                Text("No specific food sources available")
                            }
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding()
        }
    }
    
    private func makeSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding()
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
            }
            Spacer(minLength: 16)
        }
    }
}

struct BenefitsDetailView: View {
    let nutrientName: String
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            
            VStack(alignment: .leading) {
                Text("Health Benefits")
                    .font(.title2.bold())
                
                if isLandscape && isPad {
                    HStack(alignment: .top, spacing: 24) {
                        switch nutrientName {
                        case "Protein":
                            makeBenefitSection("Muscle Health:", benefits: [
                                "Essential for muscle growth and repair",
                                "Prevents muscle loss during weight loss",
                                "Supports recovery after exercise",
                                "Maintains muscle mass during aging"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeBenefitSection("Body Function:", benefits: [
                                "Creates enzymes and hormones",
                                "Supports immune system function",
                                "Maintains fluid balance",
                                "Forms antibodies for immune defense"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeBenefitSection("Other Benefits:", benefits: [
                                "Promotes feeling of fullness",
                                "Supports healthy skin and hair",
                                "Helps maintain strong bones",
                                "Essential for blood clotting"
                            ])
                            .frame(maxWidth: .infinity)
                            
                        case "Carbs":
                            makeBenefitSection("Energy:", benefits: [
                                "Primary energy source for body",
                                "Fuels brain function",
                                "Provides quick energy for exercise",
                                "Spares protein from being used for energy"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeBenefitSection("Digestive Health:", benefits: [
                                "Fiber supports digestive health",
                                "Feeds beneficial gut bacteria",
                                "Helps maintain regular bowel movements",
                                "Supports healthy cholesterol levels"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeBenefitSection("Performance:", benefits: [
                                "Essential for high-intensity exercise",
                                "Maintains blood glucose levels",
                                "Replenishes muscle glycogen",
                                "Supports athletic performance"
                            ])
                            .frame(maxWidth: .infinity)
                            
                        case "Fats":
                            makeBenefitSection("Essential Functions:", benefits: [
                                "Supports cell membrane structure",
                                "Essential for hormone production",
                                "Aids in nutrient absorption",
                                "Provides insulation and protection"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeBenefitSection("Brain Health:", benefits: [
                                "Crucial for brain development",
                                "Supports cognitive function",
                                "Essential for nerve signaling",
                                "Maintains brain tissue health"
                            ])
                            .frame(maxWidth: .infinity)
                            
                            makeBenefitSection("Other Benefits:", benefits: [
                                "Provides long-lasting energy",
                                "Helps maintain healthy skin",
                                "Supports vitamin absorption",
                                "Important for inflammation response"
                            ])
                            .frame(maxWidth: .infinity)
                            
                        default:
                            Text("No specific benefits information available")
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch nutrientName {
                            case "Protein":
                                Group {
                                    makeBenefitSection("Muscle Health:", benefits: [
                                        "Essential for muscle growth and repair",
                                        "Prevents muscle loss during weight loss",
                                        "Supports recovery after exercise",
                                        "Maintains muscle mass during aging"
                                    ])
                                    
                                    makeBenefitSection("Body Function:", benefits: [
                                        "Creates enzymes and hormones",
                                        "Supports immune system function",
                                        "Maintains fluid balance",
                                        "Forms antibodies for immune defense"
                                    ])
                                    
                                    makeBenefitSection("Other Benefits:", benefits: [
                                        "Promotes feeling of fullness",
                                        "Supports healthy skin and hair",
                                        "Helps maintain strong bones",
                                        "Essential for blood clotting"
                                    ])
                                }
                                
                            case "Carbs":
                                Group {
                                    makeBenefitSection("Energy:", benefits: [
                                        "Primary energy source for body",
                                        "Fuels brain function",
                                        "Provides quick energy for exercise",
                                        "Spares protein from being used for energy"
                                    ])
                                    
                                    makeBenefitSection("Digestive Health:", benefits: [
                                        "Fiber supports digestive health",
                                        "Feeds beneficial gut bacteria",
                                        "Helps maintain regular bowel movements",
                                        "Supports healthy cholesterol levels"
                                    ])
                                    
                                    makeBenefitSection("Performance:", benefits: [
                                        "Essential for high-intensity exercise",
                                        "Maintains blood glucose levels",
                                        "Replenishes muscle glycogen",
                                        "Supports athletic performance"
                                    ])
                                }
                                
                            case "Fats":
                                Group {
                                    makeBenefitSection("Essential Functions:", benefits: [
                                        "Supports cell membrane structure",
                                        "Essential for hormone production",
                                        "Aids in nutrient absorption",
                                        "Provides insulation and protection"
                                    ])
                                    
                                    makeBenefitSection("Brain Health:", benefits: [
                                        "Crucial for brain development",
                                        "Supports cognitive function",
                                        "Essential for nerve signaling",
                                        "Maintains brain tissue health"
                                    ])
                                    
                                    makeBenefitSection("Other Benefits:", benefits: [
                                        "Provides long-lasting energy",
                                        "Helps maintain healthy skin",
                                        "Supports vitamin absorption",
                                        "Important for inflammation response"
                                    ])
                                }
                                
                            default:
                                Text("No specific benefits information available")
                            }
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding()
        }
    }
    
    private func makeBenefitSection(_ title: String, benefits: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding()
            ForEach(benefits, id: \.self) { benefit in
                Text("• \(benefit)")
            }
            Spacer(minLength: 16)
        }
    }
}

struct NutrientChartData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let type: String
}

extension View {
    func nutrientCardStyle() -> some View {
        self
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ChartHeaderView: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            HStack {
                Text("\(Int(value))")
                    .font(.title.bold())
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nutrientCardStyle()
    }
}

struct NutrientLegendView: View {
    var body: some View {
        HStack(spacing: 20) {
            LegendItem(color: .red, label: "Protein")
            LegendItem(color: .green, label: "Carbs")
            LegendItem(color: .blue, label: "Fats")
        }
        .padding()
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        Label {
            Text(label)
                .font(.caption)
        } icon: {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

let themeColors: [String: Color] = [
    "Carbs": Color.green.opacity(0.4),
    "Protein": Color.red.opacity(0.4),
    "Fats": Color.blue.opacity(0.4),
    "Calories": Color.orange.opacity(0.4),
    "Fiber": Color.purple.opacity(0.4),
    "Vitamins": Color.yellow.opacity(0.4),
    "Minerals": Color.teal.opacity(0.4),
    "Water": Color.cyan.opacity(0.4),
    "Phytochemicals": Color.pink.opacity(0.4),
    "Antioxidants": Color.indigo.opacity(0.4),
    "Electrolytes": Color.mint.opacity(0.4)
]

let nutrientDetails: [String: NutrientInfo] = [
    "Vitamins": NutrientInfo(
        todayConsumption: "A, C, D, E",
        weeklyConsumption: "Varies",
        monthlyConsumption: "Varies",
        recommendedIntake: "Varies by vitamin",
        foodsRichInNutrient: "Fruits, Vegetables, Dairy",
        benefits: "Supports immune function, promotes vision."
    ),
    "Minerals": NutrientInfo(
        todayConsumption: "Iron, Calcium",
        weeklyConsumption: "Varies",
        monthlyConsumption: "Varies",
        recommendedIntake: "Varies by mineral",
        foodsRichInNutrient: "Meat, Dairy, Leafy Greens",
        benefits: "Supports bone health, aids in oxygen transport."
    ),
    "Phytochemicals": NutrientInfo(
        todayConsumption: "Varies",
        weeklyConsumption: "Varies",
        monthlyConsumption: "Varies",
        recommendedIntake: "Include colorful fruits and vegetables",
        foodsRichInNutrient: "Berries, Green Tea, Nuts",
        benefits: "Antioxidant properties, may reduce disease risk."
    ),
    "Antioxidants": NutrientInfo(
        todayConsumption: "Varies",
        weeklyConsumption: "Varies",
        monthlyConsumption: "Varies",
        recommendedIntake: "Include a variety of foods",
        foodsRichInNutrient: "Berries, Dark Chocolate, Spinach",
        benefits: "Protects cells from damage, supports overall health."
    ),
    "Electrolytes": NutrientInfo(
        todayConsumption: "Sodium, Potassium",
        weeklyConsumption: "Varies",
        monthlyConsumption: "Varies",
        recommendedIntake: "Varies by electrolyte",
        foodsRichInNutrient: "Bananas, Salt, Coconut Water",
        benefits: "Regulates fluid balance, supports muscle function."
    )
]

struct CategoryDetailView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let category: String
    let CategoryDetailWidthScaling: CGFloat = 0.975
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 40) {
            switch category {
            case "Vitamins":
                NutrientSubcategoryCard(title: "B Complex", nutrients: [
                    "Thiamin", "Riboflavin", "Niacin",
                    "Vitamin B6", "Vitamin B12", "Folate", "Biotin", "Pantothenic Acid"
                ])
                .frame(maxWidth: .infinity)
                
                NutrientSubcategoryCard(title: "Fat Soluble", nutrients: [
                    "Vitamin A", "Vitamin D", "Vitamin E", "Vitamin K"
                ])
                .frame(maxWidth: .infinity)
                
                NutrientSubcategoryCard(title: "Water Soluble", nutrients: [
                    "Vitamin C"
                ])
                .frame(maxWidth: .infinity)
                
            case "Minerals":
                NutrientSubcategoryCard(title: "Electrolytes", nutrients: [
                    "Sodium", "Potassium", "Calcium", "Magnesium",
                    "Chloride", "Phosphorus"
                ])
                .frame(maxWidth: .infinity)
                
                NutrientSubcategoryCard(title: "Trace Minerals", nutrients: [
                    "Iron", "Zinc", "Copper", "Manganese",
                    "Iodine", "Selenium", "Chromium", "Molybdenum"
                ])
                .frame(maxWidth: .infinity)
                
            case "Phytochemicals":
                NutrientSubcategoryCard(title: "Plant Compounds", nutrients: [
                    "Flavonoids", "Carotenoids", "Glucosinolates",
                    "Phytosterols"
                ])
                .frame(maxWidth: .infinity)
                
            case "Antioxidants":
                NutrientSubcategoryCard(title: "Antioxidant Compounds", nutrients: [
                    "Vitamin C", "Vitamin E", "Beta-carotene",
                    "Selenium", "Zinc"
                ])
                .frame(maxWidth: .infinity)
                
            case "Electrolytes":
                NutrientSubcategoryCard(title: "Essential Electrolytes", nutrients: [
                    "Sodium", "Potassium", "Calcium", "Magnesium",
                    "Chloride", "Phosphorus"
                ])
                .frame(maxWidth: .infinity)
            default:
                EmptyView()
            }
        }
    }
}

enum TimePeriod: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case sixMonth = "6 Months"
    case year = "Year"
}

struct NutrientInfo {
    var todayConsumption: String
    let weeklyConsumption: String
    let monthlyConsumption: String
    let recommendedIntake: String
    let foodsRichInNutrient: String
    let benefits: String
}

struct NutrientSubcategoryCard: View {
    let title: String
    let nutrients: [String]
    @StateObject private var healthStore = HealthKitManager()
    @State private var values: [String: Double] = [:]
    @State private var isExpanded = true
    @Namespace private var namespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation { isExpanded.toggle() }
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
            }) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.blue)
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.8))
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .allowsHitTesting(false)
                )
                .cornerRadius(12, corners: [.topLeft, .topRight])
            }
            
            if isExpanded {
                ForEach(nutrients, id: \.self) { nutrient in
                    NavigationLink(
                        destination: SubcategoryDetailView(nutrientName: nutrient)
                    ) {
                        HStack {
                            Text(nutrient)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(formatValue(values[nutrient.lowercased()] ?? 0)) \(NutritionUnit.getUnit(for: nutrient))")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                        .frame(height: 44)
                    }
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 1)
        .frame(maxWidth: .infinity)
        .task {
            await fetchNutrientValues()
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        if value >= 1 {
            return String(format: "%.1f", value)
        } else if value > 0 {
            return String(format: "%.3f", value)
        } else {
            return "0"
        }
    }
    
    private func fetchNutrientValues() async {
        for nutrient in nutrients {
            let normalizedName = normalizeNutrientName(nutrient)
            healthStore.fetchTodayNutrientData(for: normalizedName) { value, _ in
                if let value = value {
                    DispatchQueue.main.async {
                        values[nutrient.lowercased()] = value
                    }
                }
            }
        }
    }
    
    private func normalizeNutrientName(_ name: String) -> String {
        let baseName = name.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
                          .trimmingCharacters(in: .whitespaces)
                          .lowercased()
        
        switch baseName {
        case "thiamin": return "thiamin"
        case "riboflavin": return "riboflavin"
        case "niacin": return "niacin"
        case "b6": return "vitamin b6"
        case "b12": return "vitamin b12"
        case "folate": return "folate"
        case "biotin": return "biotin"
        case "pantothenic acid": return "pantothenic acid"
        case let name where name.contains("vitamin"):
            return name
        default:
            return baseName
        }
    }
}

// Add this extension for rounded corners if not already present
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
