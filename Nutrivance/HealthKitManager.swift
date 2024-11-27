import HealthKit
import SwiftUI

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    struct NutritionEntry: Identifiable {
        let id: UUID
        let timestamp: Date
        let nutrients: [String: Double]
        let source: EntrySource
        let mealType: String?
        
        enum EntrySource {
            case scanner
            case search
            case savedMeal
        }
    }
    
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        let types = Set([
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!
        ])
        
        healthStore.requestAuthorization(toShare: types, read: types) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func fetchTodayNutrientData(for nutrientType: String, completion: @escaping (Double?, Error?) -> Void) {
        guard let type = quantityType(for: nutrientType) else {
            completion(nil, nil)
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: type,
                                    quantitySamplePredicate: predicate,
                                    options: .cumulativeSum) { _, result, error in
            DispatchQueue.main.async {
                let value = result?.sumQuantity()?.doubleValue(for: self.unit(for: nutrientType))
                completion(value, error)
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
        guard let type = quantityType(for: nutrientType) else {
            completion(nil, nil)
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: type,
                                    quantitySamplePredicate: predicate,
                                    options: .cumulativeSum) { _, result, error in
            DispatchQueue.main.async {
                let value = result?.sumQuantity()?.doubleValue(for: self.unit(for: nutrientType))
                completion(value, error)
            }
        }
        
        healthStore.execute(query)
    }
    
    func fetchNutrientHistory(from startDate: Date, to endDate: Date, completion: @escaping ([NutritionEntry]) -> Void) {
        let types = [
            (HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, "calories"),
            (HKObjectType.quantityType(forIdentifier: .dietaryProtein)!, "protein"),
            (HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!, "fats"),
            (HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!, "carbs"),
            (HKObjectType.quantityType(forIdentifier: .dietaryWater)!, "water")
        ]
        
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
                    
                    if var entry = entriesByID[entryId] {
                        var updatedNutrients = entry.nutrients
                        updatedNutrients[nutrientKey] = sample.quantity.doubleValue(for: self.unit(for: nutrientKey))
                        entriesByID[entryId] = NutritionEntry(
                            id: entry.id,
                            timestamp: entry.timestamp,
                            nutrients: updatedNutrients,
                            source: entry.source,
                            mealType: entry.mealType
                        )
                    } else {
                        let entrySource: NutritionEntry.EntrySource = {
                            switch source {
                            case "scanner": return .scanner
                            case "search": return .search
                            default: return .savedMeal
                            }
                        }()
                        
                        entriesByID[entryId] = NutritionEntry(
                            id: UUID(uuidString: entryId) ?? UUID(),
                            timestamp: sample.startDate,
                            nutrients: [nutrientKey: sample.quantity.doubleValue(for: self.unit(for: nutrientKey))],
                            source: entrySource,
                            mealType: mealType
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
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!
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
        case "calories":
            return HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        case "protein":
            return HKQuantityType.quantityType(forIdentifier: .dietaryProtein)
        case "carbs":
            return HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)
        case "fats":
            return HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
        case "water":
            return HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        default:
            return nil
        }
    }
    
    private func unit(for nutrientType: String) -> HKUnit {
        switch nutrientType.lowercased() {
        case "calories":
            return .kilocalorie()
        case "water":
            return .literUnit(with: .milli)
        default:
            return .gram()
        }
    }
}
