import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    private let container = CKContainer.default()
    private let database: CKDatabase
    
    init() {
        self.database = container.privateCloudDatabase
    }
    
    func saveNutrientsToCloud(_ nutrients: [NutrientData], completion: @escaping (Bool) -> Void) {
        let records = nutrients.map { nutrient -> CKRecord in
            let record = CKRecord(recordType: "Nutrient")
            record.setValue(nutrient.name, forKey: "name")
            record.setValue(nutrient.value, forKey: "value")
            record.setValue(nutrient.unit, forKey: "unit")
            return record
        }
        
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    completion(true)
                }
            case .failure:
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
        database.add(operation)
    }
}


protocol CloudKitRecord {
    static var recordType: String { get }
    var record: CKRecord { get }
    init(record: CKRecord) throws
}
