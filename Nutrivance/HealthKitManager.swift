import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    let healthStore = HKHealthStore()
    @Published var isAuthorized = false

    // Define the types of data you want to read
    let healthDataTypes: Set<HKSampleType> = {
        var types = Set<HKSampleType>()
        if let carbs = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            types.insert(carbs)
        }
        if let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            types.insert(protein)
        }
        if let fat = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            types.insert(fat)
        }
        if let calories = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            types.insert(calories)
        }
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        return types
    }()

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        if HKHealthStore.isHealthDataAvailable() {
            print("Good")
        } else {
            print ("Bad")
        }
            // Check if running on Mac Catalyst
            #if targetEnvironment(macCatalyst)
            healthStore.requestAuthorization(toShare: [], read: healthDataTypes) { success, error in
                DispatchQueue.main.async {
                    self.isAuthorized = success
                    if success {
                        print("HealthKit authorization granted on Mac Catalyst")
                    } else if let error = error {
                        print("Authorization error: \(error.localizedDescription)")
                    }
                    completion(success, error)
                }
            }
            #else
            // iOS request authorization as usual
            healthStore.requestAuthorization(toShare: [], read: healthDataTypes) { success, error in
                DispatchQueue.main.async {
                    self.isAuthorized = success
                    if success {
                        print("HealthKit authorization granted on iOS")
                    } else if let error = error {
                        print("Authorization error: \(error.localizedDescription)")
                    }
                    completion(success, error)
                }
            }
            #endif
        }

    func fetchNutrientData(for nutrient: String, completion: @escaping (Double?, Error?) -> Void) {
        guard let type = nutritionTypeFor(nutrient) else {
            completion(nil, nil)
            return
        }
        
        let query = HKStatisticsQuery(quantityType: type,
                                     quantitySamplePredicate: nil,
                                     options: .cumulativeSum) { _, result, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: self.unitFor(nutrient))
                completion(value, nil)
            }
        }
        healthStore.execute(query)
    }

    func fetchTodayNutrientData(for nutrient: String, completion: @escaping (Double?, Error?) -> Void) {
        let nutrientType: HKQuantityType?
        let unit: HKUnit

        switch nutrient.lowercased() {
        case "calories":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
            unit = HKUnit.kilocalorie()
        case "carbs", "carbohydrates":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)
            unit = HKUnit.gram()
        case "water":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)
            unit = HKUnit.liter()
        case "protein":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)
            unit = HKUnit.gram()
        case "fats":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
            unit = HKUnit.gram()
        default:
            nutrientType = nil
            unit = HKUnit.gram()
        }


        guard let type = nutrientType else {
            completion(nil, NSError(domain: "HealthKitManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid nutrient type."]))
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                completion(nil, error)
                return
            }
            let total = sum.doubleValue(for: unit)
            completion(total, nil)
        }

        healthStore.execute(query)
    }



    // New save functionality
    func saveNutrients(_ nutrients: [NutrientData], completion: @escaping (Bool) -> Void) {
        var samples: [HKQuantitySample] = []
        
        for nutrient in nutrients {
            if let type = nutritionTypeFor(nutrient.name) {
                let unit = nutrient.name.lowercased() == "water" ? HKUnit.liter() :
                          nutrient.name.lowercased() == "calories" ? HKUnit.kilocalorie() :
                          HKUnit.gram()
                
                let quantity = HKQuantity(unit: unit, doubleValue: nutrient.value)
                let sample = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())
                samples.append(sample)
            }
        }
        
        healthStore.save(samples) { success, error in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }


    private func nutritionTypeFor(_ name: String) -> HKQuantityType? {
        switch name.lowercased() {
        case "calories":
            return HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        case "protein":
            return HKObjectType.quantityType(forIdentifier: .dietaryProtein)
        case "fat":
            return HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
        case "carbohydrates", "carbs":
            return HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
        case "water":
            return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        default:
            return nil
        }
    }
    
    private func unitFor(_ nutrient: String) -> HKUnit {
        switch nutrient.lowercased() {
        case "Calories":
            return .kilocalorie()
        case "Protein", "Carbs", "Fats", "Fiber":
            return .gram()
        case "Water":
            return .liter()
        default:
            return .gram()
        }
    }

}
