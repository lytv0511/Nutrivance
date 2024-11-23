import SwiftUI
import HealthKit
import Combine

struct NutrientDetailView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var todayCurrentNutrient: Double?
    let nutrientName: String
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
            recommendedIntake: "25g for women, 38g for men",
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
            recommendedIntake: "Sodium: <2300 mg, Potassium: 3500 mg",
            foodsRichInNutrient: "Bananas, Salt, Coconut Water",
            benefits: "Regulates fluid balance, supports muscle function."
        )
        
    ]
    
    let themeColors: [String: Color] = [
        "Carbs": Color.green.opacity(0.7),        // Darker green
        "Protein": Color.orange.opacity(0.7),     // Darker orange
        "Fats": Color.blue.opacity(0.7),          // Darker blue
        "Calories": Color.red.opacity(0.7),       // Darker red
        "Fiber": Color.purple.opacity(0.7),       // Darker purple
        "Vitamins": Color.yellow.opacity(0.7),    // Darker yellow
        "Minerals": Color.teal.opacity(0.7),      // Darker teal
        "Water": Color.cyan.opacity(0.7),         // Darker cyan
        "Phytochemicals": Color.pink.opacity(0.7), // Darker pink
        "Antioxidants": Color.indigo.opacity(0.7), // Darker indigo
        "Electrolytes": Color.mint.opacity(0.7)    // Darker mint
    ]
    
    let nutrientUnits: [String: String] = [
        "Carbs": "g",
        "Protein": "g",
        "Fats": "g",
        "Calories": "kcal", // using kcal for calories
        "Water": "L"
    ]
    

    // Computed property to determine the display value and unit
    private var displayValue: String {
        let unit: String
        switch nutrientName {
        case "Calories":
            unit = "kcal"
        case "Water":
            unit = "L"
        default:
            unit = "g"
        }
        
        // Check if todayCurrentNutrient is nil, not zero
        if let currentNutrient = todayCurrentNutrient {
            return "\(String(format: "%.2f", currentNutrient)) \(unit)"
        } else {
            #if targetEnvironment(macCatalyst)
            return "Please see Health data on iPhone or iPad."
            #else
            return "Fetching..." // Only when data is actually unavailable
            #endif
        }
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: themeColors[nutrientName] ?? .black, location: 0.0),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.9), location: 0.02),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.8), location: 0.04),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.7), location: 0.06),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.6), location: 0.08),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.5), location: 0.10),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.4), location: 0.12),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.3), location: 0.14),
                    Gradient.Stop(color: themeColors[nutrientName]!.opacity(0.2), location: 0.16),
                    Gradient.Stop(color: .black.opacity(0.5), location: 0.20),
                    Gradient.Stop(color: .black, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 10) {
                        Spacer()
                            .padding()
                            .padding()
                        Text(nutrientName)
                            .font(.largeTitle)
                            .bold()
                            .padding()

                        if let details = nutrientDetails[nutrientName] {
                            NutrientCard(title: "Today's Consumption",
                                         content: displayValue,
                                         cardWidth: geometry.size.width * 0.9,
                                         titleColor: .red,
                                         symbolName: "doc.text.magnifyingglass")

                            NutrientCard(title: "Weekly Consumption", content: details.weeklyConsumption, cardWidth: geometry.size.width * 0.9, titleColor: .green, symbolName: "calendar")
                            NutrientCard(title: "Monthly Consumption", content: details.monthlyConsumption, cardWidth: geometry.size.width * 0.9, titleColor: .blue, symbolName: "calendar")
                            NutrientCard(title: "Recommended Intake", content: details.recommendedIntake, cardWidth: geometry.size.width * 0.9, titleColor: .orange, symbolName: "star")
                            NutrientCard(title: "Foods Rich In \(nutrientName)", content: details.foodsRichInNutrient, cardWidth: geometry.size.width * 0.9, titleColor: .purple, symbolName: "leaf.arrow.triangle.circlepath")
                            NutrientCard(title: "Benefits", content: details.benefits, cardWidth: geometry.size.width * 0.9, titleColor: .yellow, symbolName: "heart.fill")
                        } else {
                            Text("No details available.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center) // Center content
                    .padding()
                }
                .edgesIgnoringSafeArea(.top)
                .contentShape(Rectangle())
                .onAppear {
                    healthKitManager.fetchTodayNutrientData(for: nutrientName) { result, error in
                        if let error = error {
                            print("Error fetching nutrient data: \(error.localizedDescription)")
                        } else {
                            todayCurrentNutrient = result
                            if let totalNutrient = result {
                                nutrientDetails[nutrientName]?.todayConsumption = "\(totalNutrient) g"
                            }
                        }
                    }
                }
                .onChange(of: nutrientName) { oldValue, newNutrient in
                    todayCurrentNutrient = nil
                    fetchNutrientData(for: newNutrient)
                }
            }
        }
    }
    
    private func fetchNutrientData(for nutrient: String) {
        healthKitManager.fetchTodayNutrientData(for: nutrient) { totalNutrient, error in
            if let error = error {
                print("Error fetching \(nutrient) data: \(error.localizedDescription)")
                return
            }
            // Update today's current nutrient
            todayCurrentNutrient = totalNutrient
            // Update the nutrient's today consumption based on the fetched value
            if let nutrientInfo = nutrientDetails[nutrient] {
                nutrientDetails[nutrient]?.todayConsumption = "\(totalNutrient ?? 0) g" // Adjust for units if necessary
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
                    Text(content)
                        .font(.body)
                }
            }
            .padding()
            .frame(width: cardWidth)
            .background(Color.white.opacity(0.1))
            .cornerRadius(10)
        }
    }

    struct NutrientDetailView_Previews: PreviewProvider {
        static var previews: some View {
            NutrientDetailView(nutrientName: "Carbs")
        }
    }
