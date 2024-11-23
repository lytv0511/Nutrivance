//
//  CloudKitManager.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/22/24.
//

import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    private let database = CKContainer.default().privateCloudDatabase
    
    // Function to save nutrient data to CloudKit
    func saveNutrientsToCloud(_ nutrients: [NutrientData], completion: @escaping (Bool) -> Void) {
        var records: [CKRecord] = []
        
        for nutrient in nutrients {
            let record = CKRecord(recordType: "NutrientData") // Record type is "NutrientData"
            
            // Populate the record with nutrient data
            record["name"] = nutrient.name
            record["value"] = nutrient.value
            record["unit"] = nutrient.unit
            
            records.append(record)
        }
        
        // Use CKModifyRecordsOperation to save the records in batch
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        
        modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving data to CloudKit: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("Successfully saved nutrients to CloudKit")
                    completion(true)
                }
            }
        }
        
        // Execute the operation
        database.add(modifyOperation)
    }
    
    // Function to fetch nutrient data from CloudKit
    func fetchNutrientsFromCloud(completion: @escaping ([NutrientData]?, Error?) -> Void) {
        let query = CKQuery(recordType: "NutrientData", predicate: NSPredicate(value: true)) // Fetch all records
        let sortDescriptor = NSSortDescriptor(key: "creationDate", ascending: false)
        query.sortDescriptors = [sortDescriptor]
        
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                completion(nil, error)
            } else {
                var fetchedNutrients: [NutrientData] = []
                for record in records ?? [] {
                    if let name = record["name"] as? String,
                       let value = record["value"] as? Double,
                       let unit = record["unit"] as? String {
                        let nutrient = NutrientData(name: name, value: value, unit: unit)
                        fetchedNutrients.append(nutrient)
                    }
                }
                completion(fetchedNutrients, nil)
            }
        }
    }
}
