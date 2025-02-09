import HealthKit
import SwiftUI

let types = [
    // Existing
    (HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, "calories"),
    (HKObjectType.quantityType(forIdentifier: .dietaryProtein)!, "protein"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!, "fats"),
    (HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!, "carbs"),
    (HKObjectType.quantityType(forIdentifier: .dietaryWater)!, "water"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFiber)!, "fiber"),
    
    // Vitamins
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
    
    // Minerals
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
    
    // Others
    (HKObjectType.quantityType(forIdentifier: .dietaryCholesterol)!, "cholesterol"),
    (HKObjectType.quantityType(forIdentifier: .dietarySugar)!, "sugar"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatMonounsaturated)!, "monounsaturated fat"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatPolyunsaturated)!, "polyunsaturated fat"),
    (HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!, "saturated fat"),
    (HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!, "caffeine")
]

// Add these new types to the existing types array
let additionalTypes: [(HKSampleType, String)] = [
    // Physical Activity
    (HKObjectType.quantityType(forIdentifier: .stepCount)!, "steps"),
    (HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!, "distance"),
    (HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!, "active_calories"),
    (HKObjectType.workoutType(), "workouts"),
    
    // Vital Signs
    (HKObjectType.quantityType(forIdentifier: .heartRate)!, "heart_rate"),
    (HKObjectType.quantityType(forIdentifier: .restingHeartRate)!, "resting_heart_rate"),
    (HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, "hrv"),
    (HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!, "oxygen"),
    (HKObjectType.quantityType(forIdentifier: .respiratoryRate)!, "respiratory_rate"),
    
    // Sleep
    (HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, "sleep"),
    
    // Mindfulness
    (HKObjectType.categoryType(forIdentifier: .mindfulSession)!, "mindfulness"),
    
    // Mood & Symptoms
    (HKObjectType.categoryType(forIdentifier: .moodChanges)!, "mood"),
    (HKObjectType.categoryType(forIdentifier: .sleepChanges)!, "sleep_changes"),
    (HKObjectType.categoryType(forIdentifier: .appetiteChanges)!, "appetite_changes")
]

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    struct NutritionEntry: Identifiable {
        let id: UUID
        let timestamp: Date
        let nutrients: [String: Double]
        let source: EntrySource
        let mealType: String?
        let category: NutrientCategory
        
        enum EntrySource {
            case scanner
            case search
            case savedMeal
        }
        
        enum NutrientCategory {
            case macronutrient
            case vitamin
            case mineral
            case other
            
            var subcategories: [String] {
                switch self {
                case .vitamin:
                    return ["A", "B Complex", "C", "D", "E", "K"]
                case .mineral:
                    return ["Electrolytes", "Non-Electrolytes"]
                case .macronutrient:
                    return ["Protein", "Carbs", "Fats"]
                case .other:
                    return ["Cholesterol", "Sugar", "Caffeine"]
                }
            }
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
        let types = Set([
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
        ])
        
        healthStore.requestAuthorization(toShare: types, read: types) { success, error in
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
    
    private func determineCategory(for nutrient: String) -> NutritionEntry.NutrientCategory {
        let categories = getNutrientsByCategory()
        if categories["Vitamins"]?.contains(nutrient) ?? false {
            return .vitamin
        } else if categories["Minerals"]?.contains(nutrient) ?? false {
            return .mineral
        } else if ["protein", "carbs", "fats"].contains(nutrient) {
            return .macronutrient
        } else {
            return .other
        }
    }
    
    func fetchNutrientHistory(from startDate: Date, to endDate: Date, completion: @escaping ([NutritionEntry]) -> Void) {
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        var entriesByID: [String: NutritionEntry] = [:]
        let group = DispatchGroup()
        
        for (type, nutrientKey) in types {
            group.enter()
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                guard let samples = samples as? [HKQuantitySample] else { return }
                
                for sample in samples {
                    let entryId = sample.metadata?["entryId"] as? String ?? UUID().uuidString
                    let source = sample.metadata?["source"] as? String ?? "unknown"
                    let mealType = sample.metadata?["mealType"] as? String
                    
                    let entrySource: NutritionEntry.EntrySource = {
                        switch source {
                        case "scanner": return .scanner
                        case "search": return .search
                        default: return .savedMeal
                        }
                    }()
                    
                    if let entry = entriesByID[entryId] {
                        var updatedNutrients = entry.nutrients
                        updatedNutrients[nutrientKey] = sample.quantity.doubleValue(for: self.unit(for: nutrientKey))
                        entriesByID[entryId] = NutritionEntry(
                            id: entry.id,
                            timestamp: entry.timestamp,
                            nutrients: updatedNutrients,
                            source: entry.source,
                            mealType: entry.mealType,
                            category: self.determineCategory(for: nutrientKey)
                        )
                    } else {
                        entriesByID[entryId] = NutritionEntry(
                            id: UUID(uuidString: entryId) ?? UUID(),
                            timestamp: sample.startDate,
                            nutrients: [nutrientKey: sample.quantity.doubleValue(for: self.unit(for: nutrientKey))],
                            source: entrySource,
                            mealType: mealType,
                            category: self.determineCategory(for: nutrientKey)
                        )
                    }
                }
            }
            
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            let entries = Array(entriesByID.values).sorted { $0.timestamp > $1.timestamp }
            completion(entries)
        }
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
            
            // Vitamins (typically measured in micrograms or milligrams)
            case "vitamin a", "vitamin d", "vitamin k", "biotin", "folate":
                return .gramUnit(with: .micro)
            case "vitamin b6", "vitamin b12", "vitamin c", "vitamin e",
                 "thiamin", "riboflavin", "niacin", "pantothenic acid":
                return .gramUnit(with: .milli)
                
            // Minerals (various units)
            case "sodium", "potassium", "calcium", "phosphorus", "magnesium":
                return .gramUnit(with: .milli)
            case "iron", "zinc", "copper", "manganese":
                return .gramUnit(with: .milli)
            case "selenium", "chromium", "molybdenum", "iodine":
                return .gramUnit(with: .micro)
                
            // Others
            case "cholesterol": return .gramUnit(with: .milli)
            case "caffeine": return .gramUnit(with: .milli)
            
            // Default for most nutrients (proteins, carbs, fats, etc.)
            default: return .gram()
        }
    }
    
    // Add inside HealthKitManager class

    func fetchMentalHealthData(from startDate: Date, to endDate: Date, completion: @escaping ([String: Any]) -> Void) {
        let group = DispatchGroup()
        var results: [String: Any] = [:]
        
        // Fetch mindfulness minutes
        group.enter()
        fetchMindfulnessMinutes(from: startDate, to: endDate) { minutes in
            results["mindfulness_minutes"] = minutes
            group.leave()
        }
        
        // Fetch mood data
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
        
        // Fetch steps
        group.enter()
        fetchStepCount(from: startDate, to: endDate) { steps in
            results["steps"] = steps
            group.leave()
        }
        
        // Fetch workouts
        group.enter()
        fetchWorkouts(from: startDate, to: endDate) { workouts in
            results["workouts"] = workouts
            group.leave()
        }
        
        // Fetch heart rate data
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

    private func fetchWorkouts(from startDate: Date, to endDate: Date, completion: @escaping ([HKWorkout]) -> Void) {
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
