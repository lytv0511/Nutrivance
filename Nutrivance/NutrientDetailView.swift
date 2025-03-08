import SwiftUI
import HealthKit
import Combine
import CoreML

struct NutrientDetailView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var todayCurrentNutrient: Double?
    @State private var recommendedIntake: String?
    let nutrientName: String
    let mlModel: nutrition_prediction_model? = {
        do {
            let config = MLModelConfiguration()
            return try nutrition_prediction_model(configuration: config)
        } catch {
            print("ML Model initialization failed: \(error)")
            return nil
        }
    }()
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var nutrientDetails: [String: NutrientInfo] = [
        "Carbs": NutrientInfo(
            todayConsumption: "0 g",
            weeklyConsumption: "1.4kg",
            monthlyConsumption: "6kg",
            recommendedIntake: "45-65% of total calories",
            foodsRichInNutrient: "Bread, Pasta, Rice",
            benefits: "Provides energy, aids in digestion."
        ),
        "Protein": NutrientInfo(
            todayConsumption: "50g",
            weeklyConsumption: "350g",
            monthlyConsumption: "1.5kg",
            recommendedIntake: "10-35% of total calories",
            foodsRichInNutrient: "Meat, Beans, Nuts",
            benefits: "Essential for muscle repair and growth."
        ),
        "Fats": NutrientInfo(
            todayConsumption: "70g",
            weeklyConsumption: "490g",
            monthlyConsumption: "2.1kg",
            recommendedIntake: "20-35% of total calories",
            foodsRichInNutrient: "Oils, Nuts, Avocados",
            benefits: "Supports cell growth, provides energy."
        ),
        "Calories": NutrientInfo(
            todayConsumption: "2000 kcal",
            weeklyConsumption: "14000 kcal",
            monthlyConsumption: "60000 kcal",
            recommendedIntake: "Varies based on activity level",
            foodsRichInNutrient: "All foods contribute calories",
            benefits: "Essential for energy."
        ),
        // New categories
        "Fiber": NutrientInfo(
            todayConsumption: "25g",
            weeklyConsumption: "175g",
            monthlyConsumption: "750g",
            recommendedIntake: "Women: 25g; Men: 38g",
            foodsRichInNutrient: "Fruits, Vegetables, Whole Grains",
            benefits: "Aids digestion, helps maintain a healthy weight."
        ),
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
        "Water": NutrientInfo(
            todayConsumption: "2L",
            weeklyConsumption: "14L",
            monthlyConsumption: "60L",
            recommendedIntake: "8 cups per day",
            foodsRichInNutrient: "Water, Fruits, Vegetables",
            benefits: "Essential for hydration, regulates body temperature."
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
    
    let themeColors: [String: Color] = [
        "Carbs": Color.green.opacity(0.4),        // Darker green
        "Protein": Color.orange.opacity(0.4),     // Darker orange
        "Fats": Color.blue.opacity(0.4),          // Darker blue
        "Calories": Color.red.opacity(0.4),       // Darker red
        "Fiber": Color.purple.opacity(0.4),       // Darker purple
        "Vitamins": Color.yellow.opacity(0.4),    // Darker yellow
        "Minerals": Color.teal.opacity(0.4),      // Darker teal
        "Water": Color.cyan.opacity(0.4),         // Darker cyan
        "Phytochemicals": Color.pink.opacity(0.4), // Darker pink
        "Antioxidants": Color.indigo.opacity(0.4), // Darker indigo
        "Electrolytes": Color.mint.opacity(0.4)    // Darker mint
    ]

    private func standardize(_ value: Float, mean: Float, std: Float) -> Float {
        return (value - mean) / std
    }

    private func getPredictedIntake() {
        guard let model = mlModel else { return }
        
        healthKitManager.fetchSteps { steps in
            healthKitManager.fetchWalkingRunningMinutes { walkingMinutes in
                healthKitManager.fetchFlightsClimbed { flights in
                    do {
                        let inputArray = MLShapedArray<Float>(
                            scalars: [
                                28.0,    // age
                                2400.0,  // tdee
                                12000.0, // steps
                                45.0,    // walking_running_minutes
                                15.0,    // flights_climbed
                                45.0,    // cardio_vo2max
                                65.0     // cardio_recovery_bpm
                            ],
                            shape: [1, 7]
                        )
                        
                        let modelInput = nutrition_prediction_modelInput(inputs: inputArray)
                        let prediction = try model.prediction(input: modelInput)
                        
                        let value = switch nutrientName.lowercased() {
                            case "protein": prediction.Identity[0].doubleValue
                            case "fats": prediction.Identity[1].doubleValue
                            case "carbs": prediction.Identity[2].doubleValue
                            case "water": prediction.Identity[3].doubleValue * 1000
                            default: 0.0
                        }
                        
                        DispatchQueue.main.async {
                            recommendedIntake = "\(value) \(NutritionUnit.getUnit(for: nutrientName))"
                        }
                    } catch {
                        print("Prediction error: \(error)")
                    }
                }
            }
        }
    }

    // Computed property to determine the display value and unit
    private var displayValue: String {
        print("NutrientDetailView: Computing displayValue with todayCurrentNutrient: \(String(describing: todayCurrentNutrient))")
        let unit = NutritionUnit.getUnit(for: nutrientName)

        #if targetEnvironment(macCatalyst)
        return "Please see Health data on iPhone or iPad."
        #else
        return "\(String(format: "%.2f", todayCurrentNutrient ?? 0)) \(unit)"
        #endif
    }
    
    var body: some View {
        NavigationStack {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: themeColors[nutrientName] ?? Color(.systemBackground), location: 0.0),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.95), location: 0.02),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.90), location: 0.04),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.85), location: 0.06),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.80), location: 0.08),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.75), location: 0.10),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.70), location: 0.12),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.65), location: 0.14),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.60), location: 0.16),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.55), location: 0.20),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.50), location: 0.24),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.45), location: 0.28),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.40), location: 0.32),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.35), location: 0.36),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.30), location: 0.40),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.25), location: 0.44),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.20), location: 0.48),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.15), location: 0.52),
                    Gradient.Stop(color: Color(.systemBackground).opacity(0.10), location: 0.56),
                    Gradient.Stop(color: Color(.systemBackground), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    VStack {
                        let columns = horizontalSizeClass == .regular ?
                        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3) :
                        Array(repeating: GridItem(.flexible(), spacing: 10), count: 1)
                        
                        LazyVGrid(columns: columns, spacing: 10) {
                            if isGroupCategory(nutrientName) {
                                if let details = nutrientDetails[nutrientName] {
                                    NutrientCard(title: "Category Overview",
                                                 content: details.todayConsumption,
                                                 cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : geometry.size.width * 0.9,
                                                 titleColor: .red,
                                                 symbolName: "doc.text.magnifyingglass")
                                    
                                    Group {
                                        NutrientCard(title: "Weekly Consumption", content: details.weeklyConsumption, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : geometry.size.width * 0.9, titleColor: .green, symbolName: "calendar")
                                        NutrientCard(title: "Monthly Consumption", content: details.monthlyConsumption, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : geometry.size.width * 0.9, titleColor: .blue, symbolName: "calendar")
                                        NutrientCard(title: "Recommended Intake", content: details.recommendedIntake, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : geometry.size.width * 0.9, titleColor: .orange, symbolName: "star")
                                        NutrientCard(title: "Foods Rich In \(nutrientName)", content: details.foodsRichInNutrient, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : geometry.size.width * 0.9, titleColor: .purple, symbolName: "leaf.arrow.triangle.circlepath")
                                        NutrientCard(title: "Benefits", content: details.benefits, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : geometry.size.width * 0.9, titleColor: .yellow, symbolName: "heart.fill")
                                    }
                                }
                            } else {
                                if let details = nutrientDetails[nutrientName] {
                                    Group {
                                        NutrientCard(title: "Today's Consumption",
                                                     content: displayValue,
                                                     cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.30 : geometry.size.width * 0.9,
                                                     titleColor: .red,
                                                     symbolName: "doc.text.magnifyingglass")
                                        
                                        NutrientCard(title: "Weekly Consumption", content: details.weeklyConsumption, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.30 : geometry.size.width * 0.9, titleColor: .green, symbolName: "calendar")
                                        NutrientCard(title: "Monthly Consumption", content: details.monthlyConsumption, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.30 : geometry.size.width * 0.9, titleColor: .blue, symbolName: "calendar")
                                        NutrientCard(
                                            title: "Recommended Intake",
                                            content: recommendedIntake != nil ? String(format: "%.2f %@", Double(recommendedIntake?.split(separator: " ")[0] ?? "0") ?? 0, NutritionUnit.getUnit(for: nutrientName)) : "Calculating...",
                                            cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.30 : geometry.size.width * 0.9,
                                            titleColor: .orange,
                                            symbolName: "star"
                                        )
                                        NutrientCard(title: "Foods Rich In \(nutrientName)", content: details.foodsRichInNutrient, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.30 : geometry.size.width * 0.9, titleColor: .purple, symbolName: "leaf.arrow.triangle.circlepath")
                                        NutrientCard(title: "Benefits", content: details.benefits, cardWidth: horizontalSizeClass == .regular ? geometry.size.width * 0.30 : geometry.size.width * 0.9, titleColor: .yellow, symbolName: "heart.fill")
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        if isGroupCategory(nutrientName) {
                            CategoryDetailView(category: nutrientName)
                                .padding()
                        }
                    }
                }
                .navigationTitle(nutrientName)
                }
            }
        }
        .onAppear {
            print("NutrientDetailView onAppear for: \(nutrientName)")
            if isGroupCategory(nutrientName) {
                fetchCategoryData(for: nutrientName)
            } else {
                fetchNutrientData(for: nutrientName)
                getPredictedIntake()
            }
        }

        // Also add to onChange
        .onChange(of: nutrientName) { oldValue, newNutrient in
            todayCurrentNutrient = nil
            if isGroupCategory(newNutrient) {
                fetchCategoryData(for: newNutrient)
            } else {
                fetchNutrientData(for: newNutrient)
                getPredictedIntake()
            }
        }
    }
    
    private func fetchCategoryData(for category: String) {
        healthKitManager.fetchCategoryAggregate(for: category) { totalValue, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Debug: Error fetching category data: \(error.localizedDescription)")
                    return
                }
                if let total = totalValue {
                    self.nutrientDetails[category]?.todayConsumption = "\(total) \(NutritionUnit.getUnit(for: category))"
                    print("Debug: Updated category \(category) with total: \(total)")
                }
            }
        }
    }
    
    private func isGroupCategory(_ category: String) -> Bool {
        ["Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"].contains(category)
    }
    
    private func fetchNutrientData(for nutrient: String) {
        print("NutrientDetailView: Starting fetch for \(nutrient)")
        healthKitManager.fetchTodayNutrientData(for: nutrient) { totalNutrient, error in
            print("NutrientDetailView: Received value: \(String(describing: totalNutrient)) for \(nutrient)")
            DispatchQueue.main.async {
                if let error = error {
                    print("NutrientDetailView: Error fetching \(nutrient): \(error.localizedDescription)")
                    return
                }
                self.todayCurrentNutrient = totalNutrient
                print("NutrientDetailView: Updated todayCurrentNutrient to \(String(describing: totalNutrient))")
            }
        }
    }

    }

    struct NutrientInfo {
        var todayConsumption: String
        let weeklyConsumption: String
        let monthlyConsumption: String
        let recommendedIntake: String
        let foodsRichInNutrient: String
        let benefits: String
    }

struct NutrientCard: View {
    let title: String
    let content: String
    let cardWidth: CGFloat
    let titleColor: Color
    let symbolName: String

    private func parseContent() -> [(String, Bool)] {
        let pattern = "([0-9]+[.-]?[0-9]*)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsString = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
        
        var segments: [(String, Bool)] = []
        var currentIndex = 0
        
        for match in matches {
            let numberRange = match.range(at: 1)
            
            if currentIndex < numberRange.location {
                segments.append((nsString.substring(with: NSRange(location: currentIndex, length: numberRange.location - currentIndex)), false))
            }
            
            segments.append((nsString.substring(with: numberRange), true))
            currentIndex = numberRange.location + numberRange.length
        }
        
        if currentIndex < nsString.length {
            segments.append((nsString.substring(from: currentIndex), false))
        }
        
        return segments
    }

    @ViewBuilder
    private func formatContent() -> some View {
        let segments = parseContent()
        HStack(spacing: 0) {
            ForEach(segments.indices, id: \.self) { index in
                Text(segments[index].0)
                    .font(segments[index].1 ? .title2 : .body)
                    .fontWeight(segments[index].1 ? .bold : .bold)
                    .foregroundColor(segments[index].1 ? .primary : .secondary)
            }
        }
    }
    var body: some View {
        HStack {
            Image(systemName: symbolName)
                .foregroundColor(titleColor)
                .font(.title)
                .padding(.trailing)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .padding(.bottom, 5)
                    .foregroundColor(titleColor)
                formatContent()
            }
        }
        .padding()
        .frame(width: cardWidth, height: 125)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6)))
    }
}



    struct NutrientDetailView_Previews: PreviewProvider {
        static var previews: some View {
            NutrientDetailView(nutrientName: "Carbs")
        }
    }

struct CategoryDetailView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let category: String
    let CategoryDetailWidthScaling: CGFloat = 0.975
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
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
                    .background(Color(.systemGray6))
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
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 1)
            .padding(.horizontal)
            .task {
                await fetchNutrientValues()
            }
        }
    
    struct NutrientSubcategoryDetailView: View {
        var body: some View {
            VStack(spacing: 20) {
                Text("Detailed Nutrient Information")
                    .font(.title)
                    .padding()
                
                Text("Coming Soon!")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding()
            }
            .navigationTitle("Nutrient Details")
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
}

struct SubcategoryCard: View {
    let nutrient: String
    @StateObject private var healthStore = HealthKitManager()
    @State private var value: Double?
    
    var body: some View {
        HStack {
            Image(systemName: "leaf.circle")
                .foregroundColor(.green)
                .font(.title)
                .padding(.trailing)
            
            VStack(alignment: .leading) {
                Text(nutrient)
                    .font(.headline)
                    .padding(.bottom, 5)
                if let value = value {
                    Text("\(String(format: "%.1f", value)) \(NutritionUnit.getUnit(for: nutrient))")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                } else {
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .frame(height: 125)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6)))
        .onAppear {
            fetchValue()
        }
    }
    private func fetchValue() {
        healthStore.fetchTodayNutrientData(for: nutrient.lowercased()) { fetchedValue, _ in
            DispatchQueue.main.async {
                value = fetchedValue
            }
        }
    }
}
