import HealthKit
import SwiftUI

let types = [
    (HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, "calories"),
    (HKObjectType.quantityType(forIdentifier: .dietaryProtein)!, "protein"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!, "fats"),
    (HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!, "carbs"),
    (HKObjectType.quantityType(forIdentifier: .dietaryWater)!, "water"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFiber)!, "fiber"),
    
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminA)!, "vitamin a"),
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminB6)!, "vitamin b6"),
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminB12)!, "vitamin b12"),
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminC)!, "vitamin c"),
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminD)!, "vitamin d"),
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminE)!, "vitamin e"),
    (HKObjectType.quantityType(forIdentifier: .dietaryVitaminK)!, "vitamin k"),
    (HKObjectType.quantityType(forIdentifier: .dietaryThiamin)!, "thiamin"),
    (HKObjectType.quantityType(forIdentifier: .dietaryRiboflavin)!, "riboflavin"),
    (HKObjectType.quantityType(forIdentifier: .dietaryNiacin)!, "niacin"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFolate)!, "folate"),
    (HKObjectType.quantityType(forIdentifier: .dietaryBiotin)!, "biotin"),
    (HKObjectType.quantityType(forIdentifier: .dietaryPantothenicAcid)!, "pantothenic acid"),
    
    (HKObjectType.quantityType(forIdentifier: .dietaryCalcium)!, "calcium"),
    (HKObjectType.quantityType(forIdentifier: .dietaryIron)!, "iron"),
    (HKObjectType.quantityType(forIdentifier: .dietaryMagnesium)!, "magnesium"),
    (HKObjectType.quantityType(forIdentifier: .dietaryPhosphorus)!, "phosphorus"),
    (HKObjectType.quantityType(forIdentifier: .dietaryPotassium)!, "potassium"),
    (HKObjectType.quantityType(forIdentifier: .dietarySodium)!, "sodium"),
    (HKObjectType.quantityType(forIdentifier: .dietaryZinc)!, "zinc"),
    (HKObjectType.quantityType(forIdentifier: .dietaryIodine)!, "iodine"),
    (HKObjectType.quantityType(forIdentifier: .dietaryCopper)!, "copper"),
    (HKObjectType.quantityType(forIdentifier: .dietarySelenium)!, "selenium"),
    (HKObjectType.quantityType(forIdentifier: .dietaryManganese)!, "manganese"),
    (HKObjectType.quantityType(forIdentifier: .dietaryChromium)!, "chromium"),
    (HKObjectType.quantityType(forIdentifier: .dietaryMolybdenum)!, "molybdenum"),
    (HKObjectType.quantityType(forIdentifier: .dietaryChloride)!, "chloride"),
    
    (HKObjectType.quantityType(forIdentifier: .dietaryCholesterol)!, "cholesterol"),
    (HKObjectType.quantityType(forIdentifier: .dietarySugar)!, "sugar"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatMonounsaturated)!, "monounsaturated fat"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatPolyunsaturated)!, "polyunsaturated fat"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!, "saturated fat"),
    (HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!, "caffeine")
]

let additionalTypes: [(HKSampleType, String)] = [
    (HKObjectType.quantityType(forIdentifier: .stepCount)!, "steps"),
    (HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!, "distance"),
    (HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!, "active_calories"),
    (HKObjectType.workoutType(), "workouts"),
    
    (HKObjectType.quantityType(forIdentifier: .heartRate)!, "heart_rate"),
    (HKObjectType.quantityType(forIdentifier: .restingHeartRate)!, "resting_heart_rate"),
    (HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, "hrv"),
    (HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!, "oxygen"),
    (HKObjectType.quantityType(forIdentifier: .respiratoryRate)!, "respiratory_rate"),
    
    (HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, "sleep"),
    
    (HKObjectType.categoryType(forIdentifier: .mindfulSession)!, "mindfulness"),
    
    (HKObjectType.categoryType(forIdentifier: .moodChanges)!, "mood"),
    (HKObjectType.categoryType(forIdentifier: .sleepChanges)!, "sleep_changes"),
    (HKObjectType.categoryType(forIdentifier: .appetiteChanges)!, "appetite_changes"),
    (HKObjectType.quantityType(forIdentifier: .stepCount)!, "steps"),
    (HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!, "exercise"),
    (HKObjectType.quantityType(forIdentifier: .appleStandTime)!, "stand"),
    (HKObjectType.quantityType(forIdentifier: .flightsClimbed)!, "flights")
]

@MainActor
final class HealthKitManager: ObservableObject, @unchecked Sendable {
    let healthStore: HKHealthStore
    
    init() {
        self.healthStore = HKHealthStore()
    }
    
    nonisolated func unit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .activeEnergyBurned, .basalEnergyBurned:
            return .kilocalorie()
        case .distanceWalkingRunning, .distanceCycling:
            return .meter()
        case .stepCount, .flightsClimbed:
            return .count()
        case .appleExerciseTime, .appleStandTime:
            return .minute()
        default:
            return .count()
        }
    }
    
    struct NutritionEntry {
        enum NutrientCategory: String {
            case protein = "Protein"
            case fats = "Fats"
            case carbs = "Carbs"
            case other = "Other"
        }
        
        enum EntrySource: String {
           case manual = "Manual"
           case automatic = "Automatic"
           case scanner = "Scanner"
           case search = "Search"
       }
        
        let id: UUID
        let timestamp: Date
        var nutrients: [String: Double]
        let source: EntrySource
        let mealType: String
        let category: NutrientCategory
    }

    nonisolated func getUnit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .activeEnergyBurned, .basalEnergyBurned:
            return .kilocalorie()
        case .stepCount, .flightsClimbed:
            return .count()
        case .distanceWalkingRunning:
            return .meter()
        case .appleExerciseTime:
            return .minute()
        case .appleStandTime:
            return .hour()
        default:
            return .count()
        }
    }

    nonisolated func determineCategory(for nutrientKey: HKQuantityTypeIdentifier) -> NutritionEntry.NutrientCategory {
        switch nutrientKey {
        case .dietaryProtein: return .protein
        case .dietaryFatTotal: return .fats
        case .dietaryCarbohydrates: return .carbs
        default: return .other
        }
    }

    private func processNutritionEntries(entriesByID: inout [String: NutritionEntry],
                                       sample: HKQuantitySample,
                                       entryId: String,
                                       nutrientKey: HKQuantityTypeIdentifier,
                                       entrySource: NutritionEntry.EntrySource,
                                       mealType: String) {
        let unit = getUnit(for: nutrientKey)
        let category = determineCategory(for: nutrientKey)
        
        if let entry = entriesByID[entryId] {
            var updatedNutrients = entry.nutrients
            updatedNutrients[nutrientKey.rawValue] = sample.quantity.doubleValue(for: unit)
            
            entriesByID[entryId] = NutritionEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                nutrients: updatedNutrients,
                source: entry.source,
                mealType: entry.mealType,
                category: category
            )
        } else {
            entriesByID[entryId] = NutritionEntry(
                id: UUID(uuidString: entryId) ?? UUID(),
                timestamp: sample.startDate,
                nutrients: [nutrientKey.rawValue: sample.quantity.doubleValue(for: unit)],
                source: entrySource,
                mealType: mealType,
                category: category
            )
        }
    }

    struct NutrientRecommendation {
        let dailyValue: Double
        let unit: String
        let description: String
    }

    struct NutrientInteraction {
        let primaryNutrient: String
        let interactingNutrients: [(nutrient: String, effect: InteractionEffect)]
        
        enum InteractionEffect {
            case enhances
            case inhibits
            case requires
        }
    }
    
    func fetchAge(completion: @escaping (Double) -> Void) {
        let birthdayComponents = Calendar.current.dateComponents([.year], from: Date())
        completion(Double(birthdayComponents.year ?? 30))
    }

    func fetchTDEE(completion: @escaping (Double) -> Void) {
        guard let tdeeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(2200.0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: tdeeType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let tdee = result?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 2200.0
            DispatchQueue.main.async {
                completion(tdee)
            }
        }
        healthStore.execute(query)
    }

    func fetchVO2Max(completion: @escaping (Double) -> Void) {
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            completion(40.0)
            return
        }
        
        let query = HKStatisticsQuery(quantityType: vo2Type, quantitySamplePredicate: nil, options: .discreteAverage) { _, result, _ in
            let vo2max = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "ml/kg*min")) ?? 40.0
            DispatchQueue.main.async {
                completion(vo2max)
            }
        }
        healthStore.execute(query)
    }

    func fetchRecoveryHeartRate(completion: @escaping (Double) -> Void) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(70.0)
            return
        }
        
        let query = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: nil, options: .discreteAverage) { _, result, _ in
            let hr = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 70.0
            DispatchQueue.main.async {
                completion(hr)
            }
        }
        healthStore.execute(query)
    }
    
    func fetchSteps(completion: @escaping (Double) -> Void) {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
            DispatchQueue.main.async {
                completion(steps)
            }
        }
        healthStore.execute(query)
    }

    func fetchWalkingRunningMinutes(completion: @escaping (Double) -> Void) {
        guard let walkingType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: walkingType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let minutes = result?.sumQuantity()?.doubleValue(for: HKUnit.minute()) ?? 0
            DispatchQueue.main.async {
                completion(minutes)
            }
        }
        healthStore.execute(query)
    }

    func fetchFlightsClimbed(completion: @escaping (Double) -> Void) {
        guard let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: flightsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let flights = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
            DispatchQueue.main.async {
                completion(flights)
            }
        }
        healthStore.execute(query)
    }

    func fetchStandTime(completion: @escaping (Double) -> Void) {
        guard let standTimeType = HKQuantityType.quantityType(forIdentifier: .appleStandTime) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: standTimeType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let standTime = result?.sumQuantity()?.doubleValue(for: HKUnit.minute()) ?? 0
            let standHours = standTime / 60.0
            DispatchQueue.main.async {
                completion(standHours)
            }
        }
        healthStore.execute(query)
    }

    func getNutrientInteractions(for nutrient: String) -> NutrientInteraction {
        switch nutrient.lowercased() {
        case "iron":
            return NutrientInteraction(
                primaryNutrient: "iron",
                interactingNutrients: [
                    ("vitamin c", .enhances),
                    ("calcium", .inhibits)
                ]
            )
        case "calcium":
            return NutrientInteraction(
                primaryNutrient: "calcium",
                interactingNutrients: [
                    ("vitamin d", .requires),
                    ("iron", .inhibits)
                ]
            )
        default:
            return NutrientInteraction(primaryNutrient: nutrient, interactingNutrients: [])
        }
    }

    func convertNutrientUnit(value: Double, from sourceUnit: String, to targetUnit: String) -> Double {
        let conversions: [String: Double] = [
            "mg_to_g": 0.001,
            "mcg_to_mg": 0.001,
            "g_to_mg": 1000,
            "mg_to_mcg": 1000
        ]
        
        let conversionKey = "\(sourceUnit)_to_\(targetUnit)"
        if let conversion = conversions[conversionKey] {
            return value * conversion
        }
        return value
    }
    
    func getRecommendedValue(for nutrient: String) -> NutrientRecommendation {
        switch nutrient.lowercased() {
            // Vitamins
            case "vitamin a": return NutrientRecommendation(dailyValue: 900, unit: "mcg", description: "Supports vision and immune system")
            case "vitamin c": return NutrientRecommendation(dailyValue: 90, unit: "mg", description: "Antioxidant properties")
            case "vitamin d": return NutrientRecommendation(dailyValue: 20, unit: "mcg", description: "Bone health")
            case "vitamin e": return NutrientRecommendation(dailyValue: 15, unit: "mg", description: "Antioxidant protection")
            case "vitamin k": return NutrientRecommendation(dailyValue: 120, unit: "mcg", description: "Blood clotting")
            
            // Minerals
            case "calcium": return NutrientRecommendation(dailyValue: 1000, unit: "mg", description: "Bone strength")
            case "iron": return NutrientRecommendation(dailyValue: 18, unit: "mg", description: "Oxygen transport")
            case "magnesium": return NutrientRecommendation(dailyValue: 400, unit: "mg", description: "Energy production")
            case "zinc": return NutrientRecommendation(dailyValue: 11, unit: "mg", description: "Immune function")
            
            // Default case
            default: return NutrientRecommendation(dailyValue: 0, unit: "g", description: "No specific recommendation")
        }
    }
    
    struct NutrientHierarchy {
        let category: String
        let subcategories: [SubCategory]
        
        struct SubCategory {
            let name: String
            let nutrients: [String]
            let unit: String
        }
    }

    func getNutrientHierarchy() -> [NutrientHierarchy] {
        return [
            NutrientHierarchy(category: "Vitamins", subcategories: [
                .init(name: "B Complex", nutrients: ["thiamin", "riboflavin", "niacin", "vitamin b6", "vitamin b12", "folate", "biotin", "pantothenic acid"], unit: "mg"),
                .init(name: "Fat Soluble", nutrients: ["vitamin a", "vitamin d", "vitamin e", "vitamin k"], unit: "mcg"),
                .init(name: "Water Soluble", nutrients: ["vitamin c"], unit: "mg")
            ]),
            NutrientHierarchy(category: "Minerals", subcategories: [
                .init(name: "Electrolytes", nutrients: ["sodium", "potassium", "calcium", "magnesium", "chloride", "phosphorus"], unit: "mg"),
                .init(name: "Trace Minerals", nutrients: ["iron", "zinc", "copper", "manganese", "iodine", "selenium", "chromium", "molybdenum"], unit: "mg")
            ])
        ]
    }
    
    func getNutrientsByCategory() -> [String: [String]] {
        return [
            "Vitamins": [
                "vitamin a", "vitamin b6", "vitamin b12", "vitamin c",
                "vitamin d", "vitamin e", "vitamin k", "thiamin",
                "riboflavin", "niacin", "folate", "biotin",
                "pantothenic acid"
            ],
            "Minerals": [
                "calcium", "iron", "magnesium", "phosphorus",
                "potassium", "sodium", "zinc", "iodine", "copper",
                "selenium", "manganese", "chromium", "molybdenum",
                "chloride"
            ],
            "Electrolytes": [
                "sodium", "potassium", "calcium", "magnesium",
                "chloride", "phosphorus"
            ],
            "Others": [
                "cholesterol", "sugar", "monounsaturated fat",
                "polyunsaturated fat", "saturated fat", "caffeine"
            ]
        ]
    }
    
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        print("HealthKitManager: Requesting authorization")
        
        let typesToShare: Set<HKSampleType> = Set([
            // Dietary
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            
            // Vitamins
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminA)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminB6)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminB12)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminC)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminD)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminE)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminK)!,
            HKObjectType.quantityType(forIdentifier: .dietaryThiamin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryRiboflavin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryNiacin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFolate)!,
            HKObjectType.quantityType(forIdentifier: .dietaryBiotin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryPantothenicAcid)!,
            
            // Minerals
            HKObjectType.quantityType(forIdentifier: .dietaryCalcium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryIron)!,
            HKObjectType.quantityType(forIdentifier: .dietaryMagnesium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryPhosphorus)!,
            HKObjectType.quantityType(forIdentifier: .dietaryPotassium)!,
            HKObjectType.quantityType(forIdentifier: .dietarySodium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryZinc)!,
            HKObjectType.quantityType(forIdentifier: .dietaryIodine)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCopper)!,
            HKObjectType.quantityType(forIdentifier: .dietarySelenium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryManganese)!,
            HKObjectType.quantityType(forIdentifier: .dietaryChromium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryMolybdenum)!,
            HKObjectType.quantityType(forIdentifier: .dietaryChloride)!,
            
            // Others
            HKObjectType.quantityType(forIdentifier: .dietaryCholesterol)!,
            HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatMonounsaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatPolyunsaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!,
            
            // Workouts
            HKObjectType.workoutType()
        ])
        
        let typesToRead: Set<HKSampleType> = Set([
            // Activity and Fitness
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKQuantityType.quantityType(forIdentifier: .appleStandTime)!,
            HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!
        ]).union(typesToShare)
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func fetchCategoryAggregate(for category: String, completion: @escaping (Double?, Error?) -> Void) {
        let nutrients = getNutrientsByCategory()[category] ?? []
        var totalValue: Double = 0
        let group = DispatchGroup()
        
        for nutrient in nutrients {
            group.enter()
            fetchTodayNutrientData(for: nutrient) { value, error in
                if let value = value {
                    totalValue += value
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(totalValue, nil)
        }
    }
    
    func fetchTodayNutrientData(for nutrientType: String, completion: @escaping (Double?, Error?) -> Void) {
        let mappedType = nutrientType.lowercased()
        
        print("HealthKitManager: Fetching \(nutrientType)")
        
        guard let type = quantityType(for: mappedType) else {
            print("Debug: No quantity type for \(mappedType)")
            completion(nil, nil)
            return
        }
        
        print("HealthKitManager: Found quantity type for \(nutrientType)")
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        print("Debug: Starting fetch for \(nutrientType)")
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            print("HealthKitManager: Query completed for \(nutrientType)")
            print("HealthKitManager: Result: \(String(describing: result))")
            DispatchQueue.main.async {
                if let quantity = result?.sumQuantity() {
                    let unit = self.unit(for: nutrientType)
                    let value = quantity.doubleValue(for: unit)
                    let unitString = unit.unitString
                    
                    print("HealthKitManager: Final value: \(value) \(unitString)")
                    print("Debug: Raw HealthKit result for \(nutrientType): \(String(describing: result))")
                    print("Debug: Converted value: \(value) \(unitString)")
                    
                    completion(value, error)
                } else {
                    completion(nil, error)
                }
            }
        }
        
        healthStore.execute(query)
    }

    
    func saveNutrients(_ nutrients: [NutrientData], completion: @escaping (Bool) -> Void) {
        let entryId = UUID()
        let samples = nutrients.compactMap { nutrient -> HKQuantitySample? in
            guard let type = quantityType(for: nutrient.name) else { return nil }
            let quantity = HKQuantity(unit: unit(for: nutrient.name), doubleValue: nutrient.value)
            let metadata: [String: Any] = [
                "entryId": entryId.uuidString,
                "source": "manual",
                "mealType": "meal"
            ]
            return HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date(), metadata: metadata)
        }
        
        healthStore.save(samples) { success, error in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func fetchNutrientData(for nutrientType: String, completion: @escaping (Double?, Error?) -> Void) {
        fetchTodayNutrientData(for: nutrientType, completion: completion)
    }
    
    func fetchNutrientHistory(from startDate: Date, to endDate: Date) async throws -> [NutritionEntry] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        var entriesByID: [String: NutritionEntry] = [:]
        
        for (type, nutrientKey) in types {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let samples = samples as? [HKQuantitySample] {
                        continuation.resume(returning: samples)
                    } else {
                        continuation.resume(returning: [])
                    }
                }
                healthStore.execute(query)
            }
            
            for sample in samples {
                let entryId = sample.metadata?["entryId"] as? String ?? UUID().uuidString
                let source = sample.metadata?["source"] as? String ?? "unknown"
                let mealType = sample.metadata?["mealType"] as? String ?? "Unknown"
                
                let entrySource: NutritionEntry.EntrySource = {
                    switch source {
                    case "scanner": return .scanner
                    case "search": return .search
                    case "manual": return .manual
                    case "automatic": return .automatic
                    default: return .manual
                    }
                }()
                
                let typeIdentifier = HKQuantityTypeIdentifier(rawValue: type.identifier)
                
                if let entry = entriesByID[entryId] {
                    var updatedNutrients = entry.nutrients
                    updatedNutrients[String(describing: nutrientKey)] = sample.quantity.doubleValue(for: getUnit(for: typeIdentifier))
                    
                    entriesByID[entryId] = NutritionEntry(
                        id: entry.id,
                        timestamp: entry.timestamp,
                        nutrients: updatedNutrients,
                        source: entry.source,
                        mealType: mealType,
                        category: determineCategory(for: typeIdentifier)
                    )
                } else {
                    entriesByID[entryId] = NutritionEntry(
                        id: UUID(uuidString: entryId) ?? UUID(),
                        timestamp: sample.startDate,
                        nutrients: [String(describing: nutrientKey): sample.quantity.doubleValue(for: getUnit(for: typeIdentifier))],
                        source: entrySource,
                        mealType: mealType,
                        category: determineCategory(for: typeIdentifier)
                    )
                }
            }
        }
        
        return Array(entriesByID.values).sorted { $0.timestamp > $1.timestamp }
    }



    
    func deleteNutrientData(for id: UUID, completion: @escaping (Bool) -> Void) {
        
        let types = [
            // Existing
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            
            // Vitamins
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminA)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminB6)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminB12)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminC)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminD)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminE)!,
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminK)!,
            HKObjectType.quantityType(forIdentifier: .dietaryThiamin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryRiboflavin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryNiacin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFolate)!,
            HKObjectType.quantityType(forIdentifier: .dietaryBiotin)!,
            HKObjectType.quantityType(forIdentifier: .dietaryPantothenicAcid)!,
            
            // Minerals
            HKObjectType.quantityType(forIdentifier: .dietaryCalcium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryIron)!,
            HKObjectType.quantityType(forIdentifier: .dietaryMagnesium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryPhosphorus)!,
            HKObjectType.quantityType(forIdentifier: .dietaryPotassium)!,
            HKObjectType.quantityType(forIdentifier: .dietarySodium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryZinc)!,
            HKObjectType.quantityType(forIdentifier: .dietaryIodine)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCopper)!,
            HKObjectType.quantityType(forIdentifier: .dietarySelenium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryManganese)!,
            HKObjectType.quantityType(forIdentifier: .dietaryChromium)!,
            HKObjectType.quantityType(forIdentifier: .dietaryMolybdenum)!,
            HKObjectType.quantityType(forIdentifier: .dietaryChloride)!,
            
            // Others
            HKObjectType.quantityType(forIdentifier: .dietaryCholesterol)!,
            HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatMonounsaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatPolyunsaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!
        ]
        
        let group = DispatchGroup()
        var success = true
        
        for type in types {
            group.enter()
            let predicate = HKQuery.predicateForObjects(withMetadataKey: "entryId", operatorType: .equalTo, value: id.uuidString)
            
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples else {
                    group.leave()
                    return
                }
                
                self.healthStore.delete(samples) { result, error in
                    if !result || error != nil {
                        success = false
                    }
                    group.leave()
                }
            }
            
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            completion(success)
        }
    }
    
    private func quantityType(for nutrientType: String) -> HKQuantityType? {
        switch nutrientType.lowercased() {
            // Existing
            case "calories": return HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
            case "protein": return HKQuantityType.quantityType(forIdentifier: .dietaryProtein)
            case "carbs": return HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)
            case "fats": return HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
            case "water": return HKQuantityType.quantityType(forIdentifier: .dietaryWater)
            case "fiber": return HKQuantityType.quantityType(forIdentifier: .dietaryFiber)
            
            // Vitamins
            case "vitamin a": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminA)
            case "b6", "vitamin b6": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminB6)
            case "b12", "vitamin b12": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminB12)
            case "vitamin c": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminC)
            case "vitamin d": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD)
            case "vitamin e": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminE)
            case "vitamin k": return HKQuantityType.quantityType(forIdentifier: .dietaryVitaminK)
            case "thiamin": return HKQuantityType.quantityType(forIdentifier: .dietaryThiamin)
            case "riboflavin": return HKQuantityType.quantityType(forIdentifier: .dietaryRiboflavin)
            case "niacin": return HKQuantityType.quantityType(forIdentifier: .dietaryNiacin)
            case "folate": return HKQuantityType.quantityType(forIdentifier: .dietaryFolate)
            case "biotin": return HKQuantityType.quantityType(forIdentifier: .dietaryBiotin)
            case "pantothenic acid": return HKQuantityType.quantityType(forIdentifier: .dietaryPantothenicAcid)
            
            // Minerals
            case "calcium": return HKQuantityType.quantityType(forIdentifier: .dietaryCalcium)
            case "iron": return HKQuantityType.quantityType(forIdentifier: .dietaryIron)
            case "magnesium": return HKQuantityType.quantityType(forIdentifier: .dietaryMagnesium)
            case "phosphorus": return HKQuantityType.quantityType(forIdentifier: .dietaryPhosphorus)
            case "potassium": return HKQuantityType.quantityType(forIdentifier: .dietaryPotassium)
            case "sodium": return HKQuantityType.quantityType(forIdentifier: .dietarySodium)
            case "zinc": return HKQuantityType.quantityType(forIdentifier: .dietaryZinc)
            case "iodine": return HKQuantityType.quantityType(forIdentifier: .dietaryIodine)
            case "copper": return HKQuantityType.quantityType(forIdentifier: .dietaryCopper)
            case "selenium": return HKQuantityType.quantityType(forIdentifier: .dietarySelenium)
            case "manganese": return HKQuantityType.quantityType(forIdentifier: .dietaryManganese)
            case "chromium": return HKQuantityType.quantityType(forIdentifier: .dietaryChromium)
            case "molybdenum": return HKQuantityType.quantityType(forIdentifier: .dietaryMolybdenum)
            case "chloride": return HKQuantityType.quantityType(forIdentifier: .dietaryChloride)
            
            // Others
            case "cholesterol": return HKQuantityType.quantityType(forIdentifier: .dietaryCholesterol)
            case "sugar": return HKQuantityType.quantityType(forIdentifier: .dietarySugar)
            case "monounsaturated fat": return HKQuantityType.quantityType(forIdentifier: .dietaryFatMonounsaturated)
            case "polyunsaturated fat": return HKQuantityType.quantityType(forIdentifier: .dietaryFatPolyunsaturated)
            case "saturated fat": return HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated)
            case "caffeine": return HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine)
            
            default: return nil
        }
    }

    
    private func unit(for nutrientType: String) -> HKUnit {
        switch nutrientType.lowercased() {
            case "calories": return .kilocalorie()
            case "water": return .literUnit(with: .milli)
            
            case "vitamin a", "vitamin d", "vitamin k", "biotin", "folate":
                return .gramUnit(with: .micro)
            case "vitamin b6", "vitamin b12", "vitamin c", "vitamin e",
                 "thiamin", "riboflavin", "niacin", "pantothenic acid":
                return .gramUnit(with: .milli)
                
            case "sodium", "potassium", "calcium", "phosphorus", "magnesium":
                return .gramUnit(with: .milli)
            case "iron", "zinc", "copper", "manganese":
                return .gramUnit(with: .milli)
            case "selenium", "chromium", "molybdenum", "iodine":
                return .gramUnit(with: .micro)
                
            case "cholesterol": return .gramUnit(with: .milli)
            case "caffeine": return .gramUnit(with: .milli)
            
            default: return .gram()
        }
    }

    func fetchMentalHealthData(from startDate: Date, to endDate: Date, completion: @escaping ([String: Any]) -> Void) {
        let group = DispatchGroup()
        var results: [String: Any] = [:]
        
        group.enter()
        fetchMindfulnessMinutes(from: startDate, to: endDate) { minutes in
            results["mindfulness_minutes"] = minutes
            group.leave()
        }
        
        group.enter()
        fetchMoodData(from: startDate, to: endDate) { moodData in
            results["mood_patterns"] = moodData
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(results)
        }
    }

    func fetchPhysicalActivityData(from startDate: Date, to endDate: Date, completion: @escaping ([String: Any]) -> Void) {
        let group = DispatchGroup()
        var results: [String: Any] = [:]
        
        group.enter()
        fetchStepCount(from: startDate, to: endDate) { steps in
            results["steps"] = steps
            group.leave()
        }
        
        group.enter()
        fetchWorkouts(from: startDate, to: endDate) { workouts in
            results["workouts"] = workouts
            group.leave()
        }
        
        group.enter()
        fetchHeartRateData(from: startDate, to: endDate) { heartData in
            results["heart_rate"] = heartData
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(results)
        }
    }

    private func fetchMindfulnessMinutes(from startDate: Date, to endDate: Date, completion: @escaping (Double) -> Void) {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let totalMinutes = samples?.reduce(0.0) { total, sample in
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                return total + duration
            } ?? 0.0
            
            DispatchQueue.main.async {
                completion(totalMinutes)
            }
        }
        healthStore.execute(query)
    }

    private func fetchStepCount(from startDate: Date, to endDate: Date, completion: @escaping (Int) -> Void) {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let steps = Int(result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0)
            DispatchQueue.main.async {
                completion(steps)
            }
        }
        healthStore.execute(query)
    }
    
    private func fetchMoodData(from startDate: Date, to endDate: Date, completion: @escaping ([String: Any]) -> Void) {
        guard let moodType = HKObjectType.categoryType(forIdentifier: .moodChanges) else {
            completion([:])
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: moodType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let moodData = samples?.reduce(into: [String: Int]()) { dict, sample in
                if let categorySample = sample as? HKCategorySample {
                    dict["\(categorySample.value)"] = (dict["\(categorySample.value)"] ?? 0) + 1
                }
            } ?? [:]
            DispatchQueue.main.async {
                completion(moodData)
            }
        }
        healthStore.execute(query)
    }

    func fetchNutrientValueAsync(for nutrient: String) async -> Double {
        return await withCheckedContinuation { continuation in
            fetchNutrientData(for: nutrient) { value, _ in
                continuation.resume(returning: value ?? 0)
            }
        }
    }
    
    func fetchMentalHealthDataAsync(from startDate: Date, to endDate: Date) async -> [String: Any] {
        return await withCheckedContinuation { continuation in
            fetchMentalHealthData(from: startDate, to: endDate) { data in
                continuation.resume(returning: data)
            }
        }
    }
    
    func fetchHRVAsync() async -> Double {
        return await withCheckedContinuation { continuation in
            fetchHeartRateVariability { value in
                continuation.resume(returning: value)
            }
        }
    }

    func fetchRHRAsync() async -> Double {
        return await withCheckedContinuation { continuation in
            fetchRecoveryHeartRate { value in
                continuation.resume(returning: value)
            }
        }
    }
    
    func fetchQuantity(for identifier: HKQuantityTypeIdentifier, start: Date, end: Date) async throws -> Double {
            let type = HKQuantityType(.init(rawValue: identifier.rawValue))
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let unit = getUnit(for: identifier)
            
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                    continuation.resume(returning: value)
                }
                
                healthStore.execute(query)
            }
        }

    
    func fetchActivityGoals() async throws -> (activeEnergy: Double, exerciseTime: Double, standHours: Double) {
        let calendar = Calendar.current
        let now = Date()
        let components = DateComponents(calendar: calendar, year: calendar.component(.year, from: now), month: calendar.component(.month, from: now), day: calendar.component(.day, from: now))
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { query, summaries, error in
                if let summary = summaries?.first {
                    let activeEnergyGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                    let exerciseTimeGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
                    let standHoursGoal = summary.appleStandHoursGoal.doubleValue(for: .count())
                    continuation.resume(returning: (activeEnergyGoal, exerciseTimeGoal, standHoursGoal))
                } else {
                    continuation.resume(returning: (600, 30, 12))
                }
            }
            healthStore.execute(query)
        }
    }
    
    func fetchWorkouts(from startDate: Date, to endDate: Date, completion: @escaping ([HKWorkout]) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            let workouts = samples as? [HKWorkout] ?? []
            DispatchQueue.main.async {
                completion(workouts)
            }
        }
        healthStore.execute(query)
    }

    private func fetchHeartRateData(from startDate: Date, to endDate: Date, completion: @escaping ([String: Double]) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion([:])
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMin, .discreteMax]) { _, result, _ in
            var heartData: [String: Double] = [:]
            
            if let avg = result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                heartData["average"] = avg
            }
            if let min = result?.minimumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                heartData["minimum"] = min
            }
            if let max = result?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                heartData["maximum"] = max
            }
            
            DispatchQueue.main.async {
                completion(heartData)
            }
        }
        healthStore.execute(query)
    }
}

extension HealthKitManager {
func fetchMostRecentWorkout(completion: @escaping (HKWorkout?) -> Void) {
        let workoutType = HKObjectType.workoutType()
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in
            DispatchQueue.main.async {
                completion(samples?.first as? HKWorkout)
            }
        }
        healthStore.execute(query)
    }
    
    func fetchHydration(completion: @escaping (Double) -> Void) {
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            completion(0)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )
        
        let query = HKStatisticsQuery(
            quantityType: waterType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            let waterAmount = result?.sumQuantity()?.doubleValue(for: .liter()) ?? 0
            DispatchQueue.main.async {
                completion(waterAmount)
            }
        }
        healthStore.execute(query)
    }
    
    func fetchHeartRateVariability(completion: @escaping (Double) -> Void) {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            completion(0)
            return
        }
        
        let query = HKStatisticsQuery(
            quantityType: hrvType,
            quantitySamplePredicate: nil,
            options: .discreteAverage
        ) { _, result, _ in
            let hrv = result?.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli)) ?? 0
            DispatchQueue.main.async {
                completion(hrv)
            }
        }
        healthStore.execute(query)
    }
    
    func fetchBodyComposition(completion: @escaping ((fatPercentage: Double, leanMass: Double)) -> Void) {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
              let leanMassType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) else {
            completion((0, 0))
            return
        }
        
        let bodyFatQuery = HKStatisticsQuery(
            quantityType: bodyFatType,
            quantitySamplePredicate: nil,
            options: .discreteAverage
        ) { _, result, _ in
            let fatPercentage = result?.averageQuantity()?.doubleValue(for: .percent()) ?? 0
            
            let leanMassQuery = HKStatisticsQuery(
                quantityType: leanMassType,
                quantitySamplePredicate: nil,
                options: .discreteAverage
            ) { _, result, _ in
                let leanMass = result?.averageQuantity()?.doubleValue(for: .gramUnit(with: .kilo)) ?? 0
                DispatchQueue.main.async {
                    completion((fatPercentage, leanMass))
                }
            }
            self.healthStore.execute(leanMassQuery)
        }
        healthStore.execute(bodyFatQuery)
    }
    
    func calculateWorkoutEnergy(workout: HKWorkout) async -> Double {
        let energyType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let energy = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: energy)
            }
            healthStore.execute(query)
        }
    }
    
    func calculateWorkoutStrain(completion: @escaping (Double) -> Void) {
        fetchMostRecentWorkout { workout in
            let energyBurned = workout?.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let strain = workout?.duration ?? 0 * energyBurned / 1000
            completion(min(max(strain, 0), 10))
        }
    }
}

extension HealthKitManager {
    struct NutrientData {
        let name: String
        let value: Double
        let unit: String
    }

    private func fetchNutrientValue(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double {
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

}

extension HealthKitManager {
    func fetchWorkoutEnergy(for workout: HKWorkout) async -> Double {
        let energyType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let energy = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: energy)
            }
            healthStore.execute(query)
        }
    }
}
extension HealthKitManager {
    func createWorkout(configuration: HKWorkoutConfiguration, duration: Double, completion: @escaping (HKWorkout?, Error?) -> Void) {
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        
        builder.beginCollection(withStart: Date()) { success, error in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * 60) {
                    builder.endCollection(withEnd: Date()) { success, error in
                        if success {
                            builder.finishWorkout(completion: completion)
                        }
                    }
                }
            }
        }
    }
}

extension HealthKitManager {
    func executeQuery(_ query: HKQuery) {
        healthStore.execute(query)
    }
}

extension HealthKitManager {
    func fetchCurrentHeartRate(completion: @escaping (Double) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(0)
            return
        }
        
        let query = HKStatisticsQuery(
            quantityType: heartRateType,
            quantitySamplePredicate: nil,
            options: .discreteAverage
        ) { _, result, _ in
            let heartRate = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
            DispatchQueue.main.async {
                completion(heartRate)
            }
        }
        healthStore.execute(query)
    }
}

extension HealthKitManager {
    func fetchTodayQuantity(for identifier: HKQuantityTypeIdentifier) async throws -> Double {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let quantityType = HKQuantityType(identifier)
        let unit = getUnit(for: identifier)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            
            healthStore.execute(query)
        }
    }
    
    func fetchDashboardMetrics() async throws -> DashboardMetrics {
            var metrics = DashboardMetrics()
            
            let types: [HKQuantityTypeIdentifier] = [
                .activeEnergyBurned,
                .basalEnergyBurned,
                .stepCount,
                .distanceWalkingRunning,
                .appleStandTime,
                .appleExerciseTime,
                .flightsClimbed
            ]
            
            for type in types {
                if let quantity = try? await fetchTodayQuantity(for: type) {
                    switch type {
                    case .activeEnergyBurned:
                        metrics.activeEnergy = String(format: "%.0f", quantity)
                    case .basalEnergyBurned:
                        metrics.restingEnergy = String(format: "%.0f", quantity)
                    case .stepCount:
                        metrics.steps = String(format: "%.0f", quantity)
                    case .distanceWalkingRunning:
                        metrics.distance = String(format: "%.1f", quantity/1000)
                    case .appleStandTime:
                        metrics.standHours = String(format: "%.0f", quantity)
                    case .appleExerciseTime:
                        metrics.exercise = String(format: "%.0f", quantity)
                    case .flightsClimbed:
                        metrics.flights = String(format: "%.0f", quantity)
                    default:
                        break
                    }
                }
            }
            
            return metrics
        }
}

extension HealthKitManager {
    func startObservingHealthData(updateHandler: @escaping () -> Void) {
        let types: [HKQuantityType] = [
            .quantityType(forIdentifier: .activeEnergyBurned)!,
            .quantityType(forIdentifier: .stepCount)!,
            .quantityType(forIdentifier: .distanceWalkingRunning)!,
            .quantityType(forIdentifier: .appleExerciseTime)!,
            .quantityType(forIdentifier: .flightsClimbed)!
        ]
        
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, _, error in
                if error == nil {
                    DispatchQueue.main.async {
                        updateHandler()
                    }
                }
            }
            
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: HKUpdateFrequency.immediate) { _, _ in }
        }
    }
}
