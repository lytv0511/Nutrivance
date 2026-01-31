//
//  SubcategoryDetailView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 1/17/25.
//

import Foundation
import SwiftUI
import Charts

struct NutrientDetailInfo {
    let description: String
    let recommendedIntake: String
    let foodSources: [String]
    let benefits: String
    let deficiencyRisks: String
    let interactions: String
}

struct SubcategoryDetailView: View {
    let nutrientName: String
    @State private var value: Double?
    @StateObject private var healthStore = HealthKitManager()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navigationState: NavigationState
    
    private var nutrientInfo: NutrientDetailInfo {
        NutrientDatabase.getInfo(for: nutrientName)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(title: "Overview", content: nutrientInfo.description)
                
                IntakeSection(value: value ?? 0, unit: NutritionUnit.getUnit(for: nutrientName))
                
                InfoSection(title: "Recommended Daily Intake", content: nutrientInfo.recommendedIntake)
                
                FoodSourcesSection(sources: nutrientInfo.foodSources)
                
                InfoSection(title: "Health Benefits", content: nutrientInfo.benefits)
                
                InfoSection(title: "Deficiency Risks", content: nutrientInfo.deficiencyRisks)
                
                InfoSection(title: "Nutrient Interactions", content: nutrientInfo.interactions)
                
                HistoricalDataSection(nutrientName: nutrientName)
            }
            .padding()
        }
        .navigationTitle(nutrientName)
        .onAppear {
            fetchCurrentValue()
            navigationState.setDismissAction {
                dismiss()
            }
        }
        .onDisappear {
            navigationState.clearDismissAction()
        }
    }
    
    private func fetchCurrentValue() {
        healthStore.fetchTodayNutrientData(for: nutrientName.lowercased()) { fetchedValue, _ in
            DispatchQueue.main.async {
                value = fetchedValue
            }
        }
    }
}

struct InfoSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct IntakeSection: View {
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Intake")
                .font(.headline)
            HStack {
                Text(String(format: "%.1f", value))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                Text(unit)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct FoodSourcesSection: View {
    let sources: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Food Sources")
                .font(.headline)
            ForEach(sources, id: \.self) { source in
                HStack {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                    Text(source)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

enum TimeFrame: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    
    var id: String { self.rawValue }
}

struct HistoricalDataSection: View {
    let nutrientName: String
    @StateObject private var healthStore = HealthKitManager()
    @State private var timeFrame: TimeFrame = .week
    @State private var historicalData: [(Date, Double)] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historical Data")
                .font(.headline)
            
            Picker("Time Frame", selection: $timeFrame) {
                ForEach(TimeFrame.allCases) { timeFrame in
                    Text(timeFrame.rawValue).tag(timeFrame)
                }
            }
            .pickerStyle(.segmented)
            
            NutrientChart(data: historicalData, nutrientName: nutrientName)
                .frame(height: 250)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .onAppear {
            fetchHistoricalData()
        }
        .onChange(of: timeFrame) { _, _ in
            fetchHistoricalData()
        }
    }
    
    private func fetchHistoricalData() {
        // To-do
    }
}

struct NutrientChart: View {
    let data: [(Date, Double)]
    let nutrientName: String
    
    var body: some View {
        Chart {
            ForEach(data, id: \.0) { date, value in
                LineMark(
                    x: .value("Date", date),
                    y: .value(nutrientName, value)
                )
                .foregroundStyle(.blue.gradient)
                
                AreaMark(
                    x: .value("Date", date),
                    y: .value(nutrientName, value)
                )
                .foregroundStyle(.blue.opacity(0.1))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel("\(value.index)")
            }
        }
    }
}


struct NutrientDatabase {
    static let nutrientData: [String: NutrientDetailInfo] = [
        "Thiamin": NutrientDetailInfo(
            description: "Thiamin (Vitamin B1) is crucial for energy metabolism and nerve function.",
            recommendedIntake: "Men: 1.2mg/day\nWomen: 1.1mg/day",
            foodSources: ["Whole grains", "Legumes", "Nuts", "Pork", "Fish", "Fortified cereals"],
            benefits: "Supports energy production\nMaintains nervous system health\nPromotes healthy brain function",
            deficiencyRisks: "Beriberi\nWernicke-Korsakoff syndrome\nNeurological problems",
            interactions: "Alcohol can decrease absorption\nCertain diuretics may increase excretion"
        ),

        "Riboflavin": NutrientDetailInfo(
            description: "Riboflavin (Vitamin B2) is essential for energy production and cellular function.",
            recommendedIntake: "Men: 1.3mg/day\nWomen: 1.1mg/day",
            foodSources: ["Dairy products", "Lean meats", "Fish", "Eggs", "Green vegetables", "Enriched grains"],
            benefits: "Supports energy metabolism\nMaintains healthy skin\nPromotes eye health",
            deficiencyRisks: "Skin problems\nLight sensitivity\nSore throat",
            interactions: "May affect absorption of certain medications\nWorks with other B vitamins"
        ),

        "Niacin": NutrientDetailInfo(
            description: "Niacin (Vitamin B3) is crucial for DNA repair and cellular energy production.",
            recommendedIntake: "Men: 16mg NE/day\nWomen: 14mg NE/day",
            foodSources: ["Meat", "Fish", "Peanuts", "Whole grains", "Avocados", "Mushrooms"],
            benefits: "Supports energy metabolism\nMaintains skin health\nMay help with cholesterol levels",
            deficiencyRisks: "Pellagra\nDermatitis\nDementia",
            interactions: "May interact with diabetes medications\nCan affect blood pressure medications"
        ),

        "Vitamin B6": NutrientDetailInfo(
            description: "Vitamin B6 (Pyridoxine) is vital for protein metabolism and cognitive development.",
            recommendedIntake: "Adults 19-50: 1.3mg/day\nMen 51+: 1.7mg/day\nWomen 51+: 1.5mg/day",
            foodSources: ["Chickpeas", "Tuna", "Salmon", "Potatoes", "Turkey", "Bananas"],
            benefits: "Supports brain function\nAids in hemoglobin production\nHelps convert food into energy",
            deficiencyRisks: "Depression\nConfusion\nWeakened immune system",
            interactions: "May interact with certain epilepsy medications\nAffects absorption of B12"
        ),

        "Vitamin B12": NutrientDetailInfo(
            description: "Vitamin B12 (Cobalamin) is essential for nerve function and DNA synthesis.",
            recommendedIntake: "Adults: 2.4mcg/day\nPregnant women: 2.6mcg/day",
            foodSources: ["Beef", "Clams", "Fish", "Milk", "Eggs", "Fortified cereals"],
            benefits: "Supports red blood cell formation\nMaintains nervous system health\nAids in DNA synthesis",
            deficiencyRisks: "Anemia\nNeurological problems\nFatigue",
            interactions: "Reduced absorption with certain stomach medications\nMay be affected by metformin"
        ),

        "Biotin": NutrientDetailInfo(
            description: "Biotin (Vitamin B7) is important for metabolism of fats, proteins, and carbohydrates.",
            recommendedIntake: "Adults: 30mcg/day",
            foodSources: ["Eggs", "Nuts", "Seeds", "Salmon", "Sweet potatoes", "Avocados"],
            benefits: "Promotes healthy hair and nails\nSupports metabolism\nMaintains healthy skin",
            deficiencyRisks: "Hair loss\nSkin rashes\nNail brittleness",
            interactions: "Raw egg whites can reduce absorption\nCertain anticonvulsants may decrease levels"
        ),

        "Pantothenic Acid": NutrientDetailInfo(
            description: "Pantothenic Acid (Vitamin B5) is essential for making blood cells and converting food into energy.",
            recommendedIntake: "Adults: 5mg/day",
            foodSources: ["Whole grains", "Legumes", "Eggs", "Milk", "Vegetables", "Beef"],
            benefits: "Helps produce energy\nSupports adrenal function\nAids in making neurotransmitters",
            deficiencyRisks: "Fatigue\nHeadaches\nNausea\nTingling in hands",
            interactions: "Works with other B vitamins\nMay be affected by certain antibiotics"
        ),

        "Vitamin A": NutrientDetailInfo(
            description: "Vitamin A is crucial for vision, immune function, and cell growth.",
            recommendedIntake: "Men: 900mcg RAE/day\nWomen: 700mcg RAE/day",
            foodSources: ["Sweet potatoes", "Carrots", "Spinach", "Eggs", "Beef liver", "Mangoes"],
            benefits: "Essential for vision\nSupports immune system\nMaintains skin health",
            deficiencyRisks: "Night blindness\nCompromised immunity\nSkin problems",
            interactions: "Fat enhances absorption\nMay interact with certain acne medications"
        ),

        "Vitamin D": NutrientDetailInfo(
            description: "Vitamin D is crucial for calcium absorption and bone health.",
            recommendedIntake: "Adults up to 70: 600 IU/day\nAdults over 70: 800 IU/day",
            foodSources: ["Fatty fish", "Egg yolks", "Fortified milk", "Mushrooms", "Cod liver oil"],
            benefits: "Promotes bone health\nSupports immune function\nRegulates mood",
            deficiencyRisks: "Rickets\nOsteomalacia\nDepression",
            interactions: "Works with calcium and phosphorus\nMay affect thyroid medication absorption"
        ),

        "Vitamin E": NutrientDetailInfo(
            description: "Vitamin E is a powerful antioxidant that supports immune function and skin health.",
            recommendedIntake: "Adults: 15mg/day",
            foodSources: ["Nuts", "Seeds", "Vegetable oils", "Avocados", "Spinach", "Broccoli"],
            benefits: "Acts as antioxidant\nSupports immune system\nPromotes skin health",
            deficiencyRisks: "Nerve and muscle damage\nWeakened immune system\nVision problems",
            interactions: "May interact with blood thinners\nAffects vitamin K absorption"
        ),

        "Vitamin K": NutrientDetailInfo(
            description: "Vitamin K is essential for blood clotting and bone health.",
            recommendedIntake: "Men: 120mcg/day\nWomen: 90mcg/day",
            foodSources: ["Green leafy vegetables", "Broccoli", "Brussels sprouts", "Vegetable oils", "Kiwi"],
            benefits: "Essential for blood clotting\nSupports bone health\nMay help heart health",
            deficiencyRisks: "Excessive bleeding\nBruising\nWeak bones",
            interactions: "Interacts with blood thinners\nFat enhances absorption"
        ),

        "Vitamin C": NutrientDetailInfo(
            description: "Vitamin C is essential for collagen synthesis and immune function.",
            recommendedIntake: "Men: 90mg/day\nWomen: 75mg/day\nSmokers: Add 35mg/day",
            foodSources: ["Citrus fruits", "Bell peppers", "Strawberries", "Broccoli", "Brussels sprouts"],
            benefits: "Boosts immune system\nActs as antioxidant\nEnhances iron absorption",
            deficiencyRisks: "Scurvy\nPoor wound healing\nWeakened immunity",
            interactions: "Enhances iron absorption\nMay interact with chemotherapy"
        ),

        "Iron": NutrientDetailInfo(
            description: "Iron is essential for oxygen transport in blood and energy metabolism.",
            recommendedIntake: "Men: 8mg/day\nWomen (19-50): 18mg/day\nWomen (51+): 8mg/day",
            foodSources: ["Red meat", "Spinach", "Lentils", "Fortified cereals", "Oysters", "Beans"],
            benefits: "Prevents anemia\nSupports energy levels\nEnhances immune function",
            deficiencyRisks: "Anemia\nFatigue\nWeakened immune system",
            interactions: "Vitamin C enhances absorption\nCalcium may decrease absorption"
        ),

        "Calcium": NutrientDetailInfo(
            description: "Calcium is crucial for bone health, muscle function, and nerve signaling.",
            recommendedIntake: "Adults 19-50: 1000mg/day\nAdults 51+: 1200mg/day",
            foodSources: ["Dairy products", "Leafy greens", "Fortified foods", "Sardines", "Tofu"],
            benefits: "Strengthens bones and teeth\nSupports muscle function\nAids blood clotting",
            deficiencyRisks: "Osteoporosis\nMuscle cramps\nDental problems",
            interactions: "Vitamin D enhances absorption\nIron supplements may interfere"
        ),

        "Magnesium": NutrientDetailInfo(
            description: "Magnesium is involved in over 300 enzymatic reactions in the body.",
            recommendedIntake: "Men: 400-420mg/day\nWomen: 310-320mg/day",
            foodSources: ["Nuts", "Seeds", "Whole grains", "Leafy greens", "Dark chocolate"],
            benefits: "Supports energy production\nRegulates muscle function\nMaintains bone health",
            deficiencyRisks: "Muscle weakness\nIrregular heartbeat\nAnxiety",
            interactions: "May interact with certain antibiotics\nAffects calcium absorption"
        ),

        "Zinc": NutrientDetailInfo(
            description: "Zinc is essential for immune function, wound healing, and protein synthesis.",
            recommendedIntake: "Men: 11mg/day\nWomen: 8mg/day",
            foodSources: ["Oysters", "Beef", "Crab", "Pumpkin seeds", "Chickpeas"],
            benefits: "Boosts immune system\nPromotes wound healing\nSupports growth",
            deficiencyRisks: "Delayed wound healing\nHair loss\nLoss of taste",
            interactions: "High iron intake may decrease absorption\nMay affect copper levels"
        ),

        "Copper": NutrientDetailInfo(
            description: "Copper aids in iron metabolism and formation of connective tissue.",
            recommendedIntake: "Adults: 900mcg/day",
            foodSources: ["Liver", "Shellfish", "Seeds", "Dark chocolate", "Avocados"],
            benefits: "Supports iron absorption\nAids collagen formation\nActs as antioxidant",
            deficiencyRisks: "Anemia\nBone problems\nNeurological issues",
            interactions: "High zinc intake may decrease absorption\nVitamin C affects absorption"
        ),

        "Manganese": NutrientDetailInfo(
            description: "Manganese is crucial for bone formation and blood sugar regulation.",
            recommendedIntake: "Men: 2.3mg/day\nWomen: 1.8mg/day",
            foodSources: ["Whole grains", "Nuts", "Leafy vegetables", "Tea", "Pineapple"],
            benefits: "Supports bone health\nAids wound healing\nAntioxidant properties",
            deficiencyRisks: "Impaired growth\nBone problems\nFertility issues",
            interactions: "Iron supplements may decrease absorption\nMay affect medication absorption"
        ),

        "Selenium": NutrientDetailInfo(
            description: "Selenium is a trace mineral important for DNA synthesis and thyroid function.",
            recommendedIntake: "Adults: 55mcg/day",
            foodSources: ["Brazil nuts", "Fish", "Eggs", "Sunflower seeds", "Mushrooms"],
            benefits: "Protects against oxidative stress\nSupports thyroid function\nBoosts immunity",
            deficiencyRisks: "Weakened immune system\nThyroid dysfunction\nMale infertility",
            interactions: "Works with vitamin E\nMay interact with certain medications"
        ),

        "Chromium": NutrientDetailInfo(
            description: "Chromium helps regulate blood sugar and metabolism.",
            recommendedIntake: "Men: 35mcg/day\nWomen: 25mcg/day",
            foodSources: ["Broccoli", "Grape juice", "Whole grains", "Beef", "Turkey"],
            benefits: "Enhances insulin function\nSupports metabolism\nMay help weight management",
            deficiencyRisks: "Blood sugar problems\nMetabolic issues\nAnxiety",
            interactions: "May interact with diabetes medications\nAffects iron absorption"
        ),

        "Molybdenum": NutrientDetailInfo(
            description: "Molybdenum is essential for processing proteins and genetic material.",
            recommendedIntake: "Adults: 45mcg/day",
            foodSources: ["Legumes", "Grains", "Nuts", "Dairy products", "Leafy vegetables"],
            benefits: "Supports enzyme function\nAids in detoxification\nHelps process sulfites",
            deficiencyRisks: "Rare but may affect metabolism\nSulfite sensitivity",
            interactions: "High sulfur intake may increase needs\nCopper may affect absorption"
        ),

        "Iodine": NutrientDetailInfo(
            description: "Iodine is crucial for thyroid hormone production and metabolism.",
            recommendedIntake: "Adults: 150mcg/day\nPregnant women: 220mcg/day",
            foodSources: ["Seaweed", "Iodized salt", "Fish", "Dairy", "Eggs"],
            benefits: "Supports thyroid function\nPromotes growth\nAids cognitive development",
            deficiencyRisks: "Goiter\nHypothyroidism\nDevelopmental issues",
            interactions: "Certain foods may block absorption\nMay interact with thyroid medications"
        ),

        "Sodium": NutrientDetailInfo(
            description: "Sodium is essential for nerve function and fluid balance.",
            recommendedIntake: "Adults: 1500-2300mg/day",
            foodSources: ["Table salt", "Processed foods", "Canned foods", "Pickled foods", "Cheese"],
            benefits: "Maintains fluid balance\nSupports nerve transmission\nAids muscle function",
            deficiencyRisks: "Headache\nMuscle cramps\nConfusion\nSeizures",
            interactions: "Interacts with potassium balance\nAffects blood pressure medications"
        ),

        "Potassium": NutrientDetailInfo(
            description: "Potassium is crucial for heart rhythm and muscle contraction.",
            recommendedIntake: "Adults: 2600-3400mg/day",
            foodSources: ["Bananas", "Sweet potatoes", "Yogurt", "Spinach", "Avocados"],
            benefits: "Regulates blood pressure\nSupports muscle function\nMaintains heart rhythm",
            deficiencyRisks: "Muscle weakness\nIrregular heartbeat\nConstipation",
            interactions: "Interacts with sodium balance\nMay affect heart medications"
        ),

        "Chloride": NutrientDetailInfo(
            description: "Chloride helps maintain proper fluid balance and stomach acid production.",
            recommendedIntake: "Adults: 2300mg/day",
            foodSources: ["Table salt", "Seaweed", "Rye", "Tomatoes", "Lettuce"],
            benefits: "Maintains acid-base balance\nSupports digestion\nAids in fluid regulation",
            deficiencyRisks: "Alkalosis\nFluid imbalance\nDigestive issues",
            interactions: "Works with sodium and potassium\nAffects kidney function"
        ),

        "Phosphorus": NutrientDetailInfo(
            description: "Phosphorus is vital for bone structure and energy production.",
            recommendedIntake: "Adults: 700mg/day",
            foodSources: ["Dairy", "Meat", "Fish", "Eggs", "Nuts", "Legumes"],
            benefits: "Strengthens bones and teeth\nHelps produce energy\nSupports cell repair",
            deficiencyRisks: "Bone problems\nWeakness\nAnxiety",
            interactions: "Works with calcium and vitamin D\nMay affect certain medications"
        )
    ]

    static func getInfo(for nutrient: String) -> NutrientDetailInfo {
       return nutrientData[nutrient] ?? defaultInfo(for: nutrient)
   }
   
   static func defaultInfo(for nutrient: String) -> NutrientDetailInfo {
       return NutrientDetailInfo(
           description: "\(nutrient) is an essential nutrient for human health.",
           recommendedIntake: "Specific recommendations vary by age, sex, and health status.",
           foodSources: ["Varied whole foods", "Fortified foods"],
           benefits: "Supports overall health\nContributes to body functions\nMaintains wellness",
           deficiencyRisks: "May affect overall health\nConsult healthcare provider for specific concerns",
           interactions: "May interact with other nutrients and medications"
       )
   }
}
