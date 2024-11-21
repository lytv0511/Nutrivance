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
        healthStore.requestAuthorization(toShare: healthDataTypes, read: healthDataTypes) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                completion(success, error)
            }
        }
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

        switch nutrient {
        case "Carbs":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)
        case "Protein":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)
        case "Fats":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
        case "Calories":
            nutrientType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        default:
            nutrientType = nil
        }

        guard let type = nutrientType else {
            completion(nil, NSError(domain: "HealthKitManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid nutrient type."]))
            return
        }

        // Create a date range for today
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!

        // Create a predicate to filter for today's data
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        // Create the query with the predicate
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, results, error) in
            if let error = error {
                print("Error fetching data: \(error.localizedDescription)") // Print error
                completion(nil, error)
                return
            }

            var total: Double = 0

            if let samples = results as? [HKQuantitySample] {
                for sample in samples {
                    total += sample.quantity.doubleValue(for: HKUnit.gram())
                }
                print("Total \(nutrient): \(total)") // Print total for debugging
            } else {
                print("No samples found for \(nutrient)") // Print if no samples found
            }

            completion(total, nil)
        }

        healthStore.execute(query)
    }


    // New save functionality
    func saveNutrients(_ nutrients: [NutrientData], completion: @escaping (Bool) -> Void) {
        var samples: [HKQuantitySample] = []
        
        for nutrient in nutrients {
            if let type = nutritionTypeFor(nutrient.name) {
                let quantity = HKQuantity(unit: HKUnit(from: nutrient.unit), doubleValue: nutrient.value)
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
        case "carbohydrates":
            return HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
        case "water":
            return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        default:
            return nil
        }
    }
    
    private func unitFor(_ nutrient: String) -> HKUnit {
        switch nutrient {
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
