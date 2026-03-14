// MARK: - Workout Analytics Struct

struct WorkoutAnalytics {
    let workout: HKWorkout
    let heartRates: [(Date, Double)]
    let vo2Max: Double?
    let metTotal: Double?
    let metAverage: Double?
    let metSeries: [(Date, Double)]
    let postWorkoutHRSeries: [(Date, Double)]
    let peakHR: Double?
    let hrr0: Double?
    let hrr1: Double?
    let hrr2: Double?
    let powerSeries: [(Date, Double)] // For cycling
}

extension Array where Element == (Date, Double) {
    // SDNN: Standard deviation of NN intervals (ms)
    var sdnn: Double? {
        guard self.count > 1 else { return nil }
        var intervals: [Double] = []
        let pairs = zip(self.dropFirst(), self)
        for (next, prev) in pairs {
            let interval = next.0.timeIntervalSince(prev.0) * 1000 // ms
            intervals.append(interval)
        }
        guard !intervals.isEmpty else { return nil }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        return sqrt(variance)
    }
}

extension HealthKitManager {
    /// Compute analytics for a given workout: VO2 max, METs, post-workout HR time series, HRR
    func computeWorkoutAnalytics(for workout: HKWorkout) async -> WorkoutAnalytics {
        // Fetch heart rate samples for the workout
        let hrSamples = await fetchHeartRateSamples(for: workout)

        var powerSeries: [(Date, Double)] = []

        // --- VO2 Max Calculation ---
        var vo2Max: Double? = nil
        let activityType = workout.workoutActivityType
        if activityType == .cycling {
            // Fetch cycling power as a time series and compute average
            let powerType = HKQuantityType.quantityType(forIdentifier: .cyclingPower)
            var powerSeries: [(Date, Double)] = []
            var avgPower: Double? = nil
            if let powerType {
                let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
                let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                    let query = HKSampleQuery(sampleType: powerType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                        continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                    }
                    self.healthStore.execute(query)
                }
                powerSeries = samples.map { ($0.startDate, $0.quantity.doubleValue(for: .watt())) }
                if !powerSeries.isEmpty {
                    avgPower = powerSeries.map { $0.1 }.reduce(0, +) / Double(powerSeries.count)
                }
            }
            let mass = 56.79 // TODO: fetch real user mass if possible
            let maxHR = 220.0 - 30.0 // TODO: fetch real age if possible
            let hrRest = 60.0 // TODO: fetch real resting HR if possible
            let avgHR = hrSamples.map { $0.1 }.reduce(0, +) / Double(hrSamples.count)
            if let avgPower, mass > 0, avgHR > 0 {
                let vo2Current = 10.8 * (avgPower / mass) + 7.0
                vo2Max = vo2Current * ((maxHR - hrRest) / (avgHR - hrRest))
            }
            print("  Cycling Power time series: \(powerSeries)")
            print("  Cycling Power average: \(avgPower.map { String(format: "%.1f", $0) } ?? "-") W")
        } else if activityType == .running || activityType == .walking {
            // Use HealthKit's VO2 max if available
            let hkVO2 = await withCheckedContinuation { continuation in
                self.fetchVO2Max { value in
                    continuation.resume(returning: value)
                }
            }
            vo2Max = hkVO2 > 0 ? hkVO2 : nil
        }

        // --- METs ---
        var metSeries: [(Date, Double)] = []
        // Fetch METs as a time series from HealthKit (physicalEffort)
        if let metType = HKQuantityType.quantityType(forIdentifier: .physicalEffort) {
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: metType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
                self.healthStore.execute(query)
            }
            metSeries = samples.map { ($0.startDate, $0.quantity.doubleValue(for: HKUnit(from: "kcal/(kg*hr)"))) }
        }
        // Fallback: try to get average MET from workout metadata if no samples
        if metSeries.isEmpty, let avgMET = workout.metadata?[HKMetadataKeyAverageMETs] as? Double {
            metSeries.append((workout.startDate, avgMET))
        }

        // Welltory-style forward-fill MET-minutes calculation
        
        var totalMETMinutes: Double = 0
        var beneficialMETMinutes: Double = 0
        let threshold = 7.34
        if metSeries.count > 1 {
            for i in 0..<(metSeries.count - 1) {
                let (currentDate, currentValue) = metSeries[i]
                let (nextDate, _) = metSeries[i+1]
                let durationMinutes = nextDate.timeIntervalSince(currentDate) / 60.0
                let volume = currentValue * durationMinutes
                totalMETMinutes += volume
                if currentValue >= threshold {
                    beneficialMETMinutes += volume
                }
            }
        }
        // If only one sample, treat duration as workout duration
        else if metSeries.count == 1 {
            let (date, value) = metSeries[0]
            let durationMinutes = workout.endDate.timeIntervalSince(date) / 60.0
            let volume = value * durationMinutes
            totalMETMinutes += volume
            if value >= threshold {
                beneficialMETMinutes += volume
            }
        }
        let metTotal = totalMETMinutes
        let metBeneficial = beneficialMETMinutes
        let metAverage = metSeries.isEmpty ? nil : (metSeries.map { $0.1 }.reduce(0, +) / Double(metSeries.count))

        // --- Post-Workout HR Time Series & HRR ---
        var postWorkoutHRSeries: [(Date, Double)] = []
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let start = workout.endDate
        let end = start.addingTimeInterval(5 * 60) // 5 min window
        if let hrType {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
                self.healthStore.execute(query)
            }
            postWorkoutHRSeries = samples.map { ($0.startDate, $0.quantity.doubleValue(for: .init(from: "count/min"))) }
        }
        // Find peak HR during workout
        let peakHR = hrSamples.map { $0.1 }.max()
        // HR at workout end, 1, 2 min after
        func hrAt(_ minAfter: Double) -> Double? {
            let target = workout.endDate.addingTimeInterval(minAfter * 60)
            let closest = postWorkoutHRSeries.min(by: { abs($0.0.timeIntervalSince(target)) < abs($1.0.timeIntervalSince(target)) })
            return closest?.1
        }
        let hrr0 = (peakHR != nil && hrAt(0) != nil) ? peakHR! - hrAt(0)! : nil
        let hrr1 = (peakHR != nil && hrAt(1) != nil) ? peakHR! - hrAt(1)! : nil
        let hrr2 = (peakHR != nil && hrAt(2) != nil) ? peakHR! - hrAt(2)! : nil

        // Print all calculated values for testing
        print("--- Workout Analytics ---")
        print("Workout: \(workout.startDate) - \(workout.endDate), type: \(workout.workoutActivityType.name)")
        print("  VO2 Max: \(vo2Max.map { String(format: "%.2f", $0) } ?? "-")")
        print("  Active MET-minutes: total=\(String(format: "%.2f", metTotal)), beneficial=\(String(format: "%.2f", metBeneficial)), avg=\(metAverage.map { String(format: "%.2f", $0) } ?? "-")")
        print("  MET time series: \(metSeries)")
        print("  Peak HR: \(peakHR.map { String(format: "%.1f", $0) } ?? "-")")
        print("  Post-Workout HR time series: \(postWorkoutHRSeries)")
        print("  HRR (0,1,2 min): \(hrr0.map { String(format: "%.1f", $0) } ?? "-")", "\(hrr1.map { String(format: "%.1f", $0) } ?? "-")", "\(hrr2.map { String(format: "%.1f", $0) } ?? "-")")
        print("  HR samples: \(hrSamples.count)")

        return WorkoutAnalytics(
            workout: workout,
            heartRates: hrSamples,
            vo2Max: vo2Max,
            metTotal: metTotal,
            metAverage: metAverage,
            metSeries: metSeries,
            postWorkoutHRSeries: postWorkoutHRSeries,
            peakHR: peakHR,
            hrr0: hrr0,
            hrr1: hrr1,
            hrr2: hrr2,
            powerSeries: powerSeries
        )
    }
}

// --- Place these in an extension at the end of the file ---

// --- Place these in an extension at the end of the file ---

extension HealthKitManager {
    /// Fetch all workouts in a given date range, and for each, fetch all heart rate samples during the workout.
    /// Prints all data fetched (workout summary and HR samples) to the terminal.
    @MainActor
    func fetchWorkoutsAndHeartRates(from startDate: Date, to endDate: Date) async -> [(workout: HKWorkout, heartRates: [(Date, Double)])] {
        // Refactored to be fully async/await, no blocking
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            self.fetchWorkouts(from: startDate, to: endDate) { wos in
                continuation.resume(returning: wos)
            }
        }
        print("Fetched \(workouts.count) workouts from \(startDate) to \(endDate)")
        var result: [(HKWorkout, [(Date, Double)])] = []
        for workout in workouts {
            let hrSamples = await self.fetchHeartRateSamples(for: workout)
            print("Workout: \(workout.startDate) - \(workout.endDate), type: \(workout.workoutActivityType.name), duration: \(workout.duration/60) min, totalDistance: \(workout.totalDistance?.doubleValue(for: .meter()) ?? 0) m, energy: \(workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0) kcal, HR samples: \(hrSamples.count)")
            for (date, bpm) in hrSamples {
                print("  HR: \(date) - \(String(format: "%.1f", bpm)) bpm")
            }
            result.append((workout, hrSamples))
        }
        return result
    }

    /// Fetch all heart rate samples for a given workout.
    @MainActor
    func fetchHeartRateSamples(for workout: HKWorkout) async -> [(Date, Double)] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map { ($0.startDate, $0.quantity.doubleValue(for: .init(from: "count/min"))) } ?? []
                continuation.resume(returning: values)
            }
            self.healthStore.execute(query)
        }
    }
}

extension HealthKitManager {
    /// Async: Fetch post-workout heart rate recovery for the most recent workout.
    /// Returns: (recoveryBPM: Double, recoveryDelta: Double, recoveryTime: Double, workoutType: String, workoutDate: Date)?
    @MainActor
    func fetchPostWorkoutHRRecovery() async -> (Double, Double, Double, String, Date)? {
        let workout = await withCheckedContinuation { continuation in
            self.fetchMostRecentWorkout { workout in
                continuation.resume(returning: workout)
            }
        }
        guard let workout else { return nil }
        let end = workout.endDate
        let start = end
        let recoveryWindow: TimeInterval = 120 // 2 min window after workout
        let recoveryEnd = end.addingTimeInterval(recoveryWindow)
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: recoveryEnd)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let bpmValues: [Double] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: .init(from: "count/min")) } ?? []
                continuation.resume(returning: values)
            }
            self.healthStore.execute(query)
        }
        guard let first = bpmValues.first, let last = bpmValues.last else { return nil }
        let delta = first - last
        let duration = recoveryWindow
        let workoutType = workout.workoutActivityType.name
        return (last, delta, duration, workoutType, workout.endDate)
    }

    /// Async: Estimate VO2 max using best available method for the most recent workout.
    /// Uses HealthKit VO2 max if available, else estimates from HR and workout type.
    @MainActor
    func fetchEstimatedVO2Max() async -> Double? {
        let workout = await withCheckedContinuation { continuation in
            self.fetchMostRecentWorkout { workout in
                continuation.resume(returning: workout)
            }
        }
        guard let workout else { return nil }
        // Try HealthKit's VO2 max first
        let hkVO2 = await withCheckedContinuation { continuation in
            self.fetchVO2Max { value in
                continuation.resume(returning: value)
            }
        }
        if hkVO2 > 0 { return hkVO2 }
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let hrValues: [Double] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: .init(from: "count/min")) } ?? []
                continuation.resume(returning: values)
            }
            self.healthStore.execute(query)
        }
        guard !hrValues.isEmpty else { return nil }
        let avgHR = hrValues.reduce(0, +) / Double(hrValues.count)
        let durationMin = workout.duration / 60.0
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let type = workout.workoutActivityType
        var vo2: Double? = nil
        switch type {
        case .running:
            if distance > 0, durationMin > 0 {
                let speed = distance / durationMin // m/min
                let grade = 0.0
                vo2 = (0.2 * speed) + (0.9 * speed * grade) + 3.5
            }
        case .cycling:
            let age = 30.0 // TODO: fetch real age if possible
            let maxHR = 220.0 - age
            let hrRest = 60.0 // TODO: fetch real resting HR if possible
            if avgHR > 0 {
                vo2 = 15.3 * (maxHR / hrRest)
            }
        case .walking:
            if distance > 0, durationMin > 0 {
                let speed = distance / durationMin // m/min
                let grade = 0.0
                vo2 = (0.1 * speed) + (1.8 * speed * grade) + 3.5
            }
        default:
            if avgHR > 0, durationMin > 0 {
                let mets = (avgHR / 220.0) * 10.0
                vo2 = mets * 3.5
            }
        }
        return vo2
    }
}
import HealthKit
import SwiftUI

enum HealthError: Error {
    case invalidType
    case noData
    case queryFailed
}

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
    
    nonisolated func unit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        // Energy Metrics
        case .activeEnergyBurned, .basalEnergyBurned:
            return .kilocalorie()
            
        // Distance Metrics
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
             .distanceDownhillSnowSports, .distanceWheelchair:
            return .meter()
            
        // Count-based Metrics
        case .stepCount, .flightsClimbed, .pushCount, .swimmingStrokeCount:
            return .count()
            
        // Time-based Metrics
        case .appleExerciseTime, .appleStandTime:
            return .minute()
            
        // Speed Metrics
        case .walkingSpeed, .runningSpeed:
            return .meter().unitDivided(by: .second())
            
        // Percentage Metrics
        case .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage:
            return .percent()
            
        // Length Metrics
        case .walkingStepLength:
            return .meter()
            
        // Heart Rate Metrics
        case .heartRate, .restingHeartRate:
            return .count().unitDivided(by: .minute())
            
        // Heart Rate Variability
        case .heartRateVariabilitySDNN:
            return .secondUnit(with: .milli)
            
        // Power Metrics
        case .runningPower, .cyclingPower:
            return .watt()
            
        // Cadence Metrics
        case .cyclingCadence:
            return .count().unitDivided(by: .minute())
            
        // Respiratory Metrics
        case .respiratoryRate:
            return .count().unitDivided(by: .minute())
            
        // Specialized Metrics
        case .vo2Max:
            return HKUnit(from: "ml/kg*min")
            
        // Default case
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

    func getUnit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .dietaryWater:
            return .literUnit(with: .milli)
        case .dietaryEnergyConsumed:
            return .kilocalorie()
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber,
             .dietaryVitaminA, .dietaryVitaminB6, .dietaryVitaminB12, .dietaryVitaminC,
             .dietaryVitaminD, .dietaryVitaminE, .dietaryVitaminK, .dietaryThiamin,
             .dietaryRiboflavin, .dietaryNiacin, .dietaryFolate, .dietaryBiotin,
             .dietaryPantothenicAcid, .dietaryCalcium, .dietaryIron, .dietaryMagnesium,
             .dietaryPhosphorus, .dietaryPotassium, .dietarySodium, .dietaryZinc,
             .dietaryIodine, .dietaryCopper, .dietarySelenium, .dietaryManganese,
             .dietaryChromium, .dietaryMolybdenum, .dietaryChloride, .dietaryCholesterol,
             .dietarySugar, .dietaryFatMonounsaturated, .dietaryFatPolyunsaturated,
             .dietaryFatSaturated, .dietaryCaffeine:
            return .gram()
        case .appleExerciseTime, .appleStandTime:
            return .minute()
        case .activeEnergyBurned:
            return .kilocalorie()
        case .stepCount, .flightsClimbed:
            return .count()
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming:
            return .meter()
        case .heartRate, .restingHeartRate:
            return .count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:
            return .secondUnit(with: .milli)
        default:
            return .gram()
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
            HKSampleType.stateOfMindType(),
            
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
            // Add cycling power and METs (physicalEffort)
            HKQuantityType.quantityType(forIdentifier: .cyclingPower)!,
            HKQuantityType.quantityType(forIdentifier: .physicalEffort)!,
            
            // Heart Rate and Health Metrics
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!,
            
            // Sleep and Mindfulness
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKSampleType.stateOfMindType()
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
    
    private func getQuantityTypeIdentifier(for nutrientType: String) -> HKQuantityTypeIdentifier {
        switch nutrientType.lowercased() {
        case "calories":
            return .dietaryEnergyConsumed
        case "protein":
            return .dietaryProtein
        case "carbs":
            return .dietaryCarbohydrates
        case "fats":
            return .dietaryFatTotal
        case "water":
            return .dietaryWater
        case "fiber":
            return .dietaryFiber
        default:
            return .dietaryProtein
        }
    }
    
    func fetchNutrientDataForInterval(
        nutrientType: String,
        start: Date,
        end: Date,
        completion: @escaping (Double?, Error?) -> Void
    ) {
        guard let type = HKQuantityType.quantityType(forIdentifier: getQuantityTypeIdentifier(for: nutrientType)) else {
            completion(nil, nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        
        let typeIdentifier = getQuantityTypeIdentifier(for: nutrientType)
        let unit = getUnit(for: typeIdentifier)
        
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            let value = result?.sumQuantity()?.doubleValue(for: unit)
            completion(value, error)
        }
        
        healthStore.execute(query)
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
        Task {
            let heartData = await fetchHeartRateData(from: startDate, to: endDate)
            results["heart_rate"] = heartData
            group.leave()
        }

        group.notify(queue: .main) {
            completion(results)
        }
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
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                throw HealthError.invalidType
            }
            
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let statsOption: HKStatisticsOptions = statisticsOptions(for: identifier)
            let unit = getUnit(for: identifier)
            
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: statsOption
                ) { _, statistics, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let value: Double
                    do {
                        if statsOption.contains(.cumulativeSum) {
                            value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                        } else if statsOption.contains(.discreteAverage) {
                            value = statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0
                        } else {
                            value = 0
                        }
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    
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

    private func fetchHeartRateData(from startDate: Date, to endDate: Date) async -> [String: Double] {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return [:]
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMin, .discreteMax]
            ) { _, result, _ in
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
                
                continuation.resume(returning: heartData)
            }
            
            healthStore.execute(query)
        }
    }
    struct TSBMetrics: Codable {
        let date: Date
        let workout_Duration: Double
        let avg_Heart_Rate: Double
        let active_Energy: Double
        let exercise_Time: Double
        let steps_Count: Double
        let distance: Double
        let resting_HR: Double
        let sleep_Duration: Double
        let training_Load: Double
        let workout_Intensity: Double
        let vo2_Max: Double
        let hrv: Double
        let sleep_Awake: Double
        let sleep_Light: Double
        let sleep_Deep: Double
        let sleep_REM: Double
        let mindfulness: Double
        let bp_Systolic: Double
        let bp_Diastolic: Double
        let glucose: Double
        let o2_Saturation: Double
        let body_Temp: Double
    }

    func fetchReadinessMetrics(days: Int = 42) async throws -> [TSBMetrics] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!
        
        var metrics: [TSBMetrics] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            let metricDate = currentDate // Create local copy
            async let workoutMetrics = fetchWorkoutMetrics(from: metricDate, to: nextDate)
            async let sleepMetrics = fetchSleepMetrics(from: metricDate, to: nextDate)
            async let vitalsMetrics = fetchVitalsMetrics(from: metricDate, to: nextDate)
            async let activityMetrics = fetchActivityMetrics(from: metricDate, to: nextDate)
            
            let dailyMetrics = TSBMetrics(
                date: currentDate,
                workout_Duration: try await workoutMetrics.duration,
                avg_Heart_Rate: try await workoutMetrics.avgHeartRate,
                active_Energy: try await activityMetrics.activeEnergy,
                exercise_Time: try await activityMetrics.exerciseTime,
                steps_Count: try await activityMetrics.steps,
                distance: try await activityMetrics.distance / 1000, // Convert to km
                resting_HR: try await vitalsMetrics.restingHR,
                sleep_Duration: try await sleepMetrics.totalDuration,
                training_Load: try await workoutMetrics.trainingLoad,
                workout_Intensity: try await workoutMetrics.intensity,
                vo2_Max: try await vitalsMetrics.vo2Max,
                hrv: try await vitalsMetrics.hrv,
                sleep_Awake: try await sleepMetrics.awake,
                sleep_Light: try await sleepMetrics.light,
                sleep_Deep: try await sleepMetrics.deep,
                sleep_REM: try await sleepMetrics.rem,
                mindfulness: try await activityMetrics.mindfulness,
                bp_Systolic: try await vitalsMetrics.systolic,
                bp_Diastolic: try await vitalsMetrics.diastolic,
                glucose: try await vitalsMetrics.glucose,
                o2_Saturation: try await vitalsMetrics.o2Saturation,
                body_Temp: try await vitalsMetrics.bodyTemp
            )
            
            metrics.append(dailyMetrics)
            currentDate = nextDate
        }
        
        return metrics
    }

    func fetchWorkoutMetrics(from start: Date, to end: Date) async throws -> (duration: Double, avgHeartRate: Double, trainingLoad: Double, intensity: Double) {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            self.healthStore.execute(query)
        }
        
        let duration = workouts.reduce(0.0) { $0 + $1.duration / 60.0 }
        let avgHeartRate = try await calculateAverageHeartRate(for: workouts)
        let trainingLoad = workouts.reduce(0.0) { total, workout in
            let energyStats = workout.statistics(for: HKQuantityType(.activeEnergyBurned))
            let energy = energyStats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return total + energy
        }
        let intensity = try await calculateWorkoutIntensity(for: workouts)
        
        return (duration, avgHeartRate, trainingLoad, intensity)
    }

    private func fetchSleepMetrics(from start: Date, to end: Date) async throws -> (totalDuration: Double, awake: Double, light: Double, deep: Double, rem: Double) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Initialize accumulators for each sleep category
                var awakeDuration = 0.0
                var coreSleepduration = 0.0
                var deepSleepDuration = 0.0
                var remSleepDuration = 0.0
                var unspecifiedAsleepDuration = 0.0
                
                // Process all samples
                if let samples = samples as? [HKCategorySample] {
                    for sample in samples {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                        
                        switch sample.value {
                        case HKCategoryValueSleepAnalysis.awake.rawValue:
                            awakeDuration += duration
                        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                            coreSleepduration += duration
                        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                            deepSleepDuration += duration
                        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                            remSleepDuration += duration
                        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                            unspecifiedAsleepDuration += duration
                        default:
                            break
                        }
                    }
                }
                
                // Sum all durations for total
                let totalDuration = awakeDuration + coreSleepduration + deepSleepDuration + remSleepDuration + unspecifiedAsleepDuration
                
                // Return tuple with correct mappings:
                // awake: actual awake time
                // light: unspecified asleep (since we don't have explicit light sleep, this is the closest)
                // deep: actual deep sleep
                // rem: actual REM sleep
                // Note: coreSleepduration is counted in the total but not separated in the tuple
                continuation.resume(returning: (totalDuration, awakeDuration, unspecifiedAsleepDuration, deepSleepDuration, remSleepDuration))
            }
            self.healthStore.execute(query)
        }
    }

    private func fetchVitalsMetrics(from start: Date, to end: Date) async throws -> (restingHR: Double, vo2Max: Double, hrv: Double, systolic: Double, diastolic: Double, glucose: Double, o2Saturation: Double, bodyTemp: Double) {
        async let restingHR = try fetchAverageQuantity(for: .restingHeartRate, from: start, to: end)
        async let vo2Max = try fetchAverageQuantity(for: .vo2Max, from: start, to: end)
        async let hrv = try fetchAverageQuantity(for: .heartRateVariabilitySDNN, from: start, to: end)
        async let systolic = try fetchAverageQuantity(for: .bloodPressureSystolic, from: start, to: end)
        async let diastolic = try fetchAverageQuantity(for: .bloodPressureDiastolic, from: start, to: end)
        async let glucose = try fetchAverageQuantity(for: .bloodGlucose, from: start, to: end)
        async let o2Saturation = try fetchAverageQuantity(for: .oxygenSaturation, from: start, to: end)
        async let bodyTemp = try fetchAverageQuantity(for: .bodyTemperature, from: start, to: end)
        
        return (
            try await restingHR,
            try await vo2Max,
            try await hrv,
            try await systolic,
            try await diastolic,
            try await glucose,
            try await o2Saturation,
            try await bodyTemp
        )
    }

    private func fetchActivityMetrics(from start: Date, to end: Date) async throws -> (activeEnergy: Double, exerciseTime: Double, steps: Double, distance: Double, mindfulness: Double) {
        async let activeEnergy = fetchSumQuantity(for: .activeEnergyBurned, from: start, to: end)
        async let exerciseTime = fetchSumQuantity(for: .appleExerciseTime, from: start, to: end)
        async let steps = fetchSumQuantity(for: .stepCount, from: start, to: end)
        async let distance = fetchSumQuantity(for: .distanceWalkingRunning, from: start, to: end)
        
        // Use the existing mindfulness function
        let mindfulness = await withCheckedContinuation { continuation in
            fetchMindfulnessMinutes(from: start, to: end) { minutes in
                continuation.resume(returning: minutes)
            }
        }
        
        return (
            try await activeEnergy,
            try await exerciseTime,
            try await steps,
            try await distance,
            mindfulness
        )
    }

    private func fetchAverageQuantity(for identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.averageQuantity()?.doubleValue(for: self.unit(for: identifier)) ?? 0
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }

    private func fetchSumQuantity(for identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: self.unit(for: identifier)) ?? 0
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }

    private func calculateAverageHeartRate(for workouts: [HKWorkout]) async throws -> Double {
        var totalHeartRate = 0.0
        var count = 0
        
        for workout in workouts {
            if let heartRateStats = workout.statistics(for: HKQuantityType(.heartRate)) {
                if let avg = heartRateStats.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                    totalHeartRate += avg
                    count += 1
                }
            }
        }
        
        return count > 0 ? totalHeartRate / Double(count) : 0
    }

    // Update where totalEnergyBurned is used
    private func calculateWorkoutIntensity(for workouts: [HKWorkout]) async throws -> Double {
        var totalIntensity = 0.0
        
        for workout in workouts {
            let energyBurned = await calculateWorkoutEnergy(workout: workout)
            let duration = workout.duration / 60.0 // Convert to minutes
            let intensity = energyBurned / duration
            totalIntensity += intensity
        }
        
        return totalIntensity
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
    nonisolated func samples(for categoryType: HKCategoryType, predicate: NSPredicate?) async throws -> [HKCategorySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("HKSampleQuery error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = samples as? [HKCategorySample] ?? []
                print("Fetched \(categorySamples.count) category samples")
                continuation.resume(returning: categorySamples)
            }
            self.healthStore.execute(query)
        }
    }
    
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
    func statisticsOptions(for identifier: HKQuantityTypeIdentifier) -> HKStatisticsOptions {
        switch identifier {
        // Discrete measurements that need averaging
        case .walkingSpeed,
             .walkingAsymmetryPercentage,
             .walkingDoubleSupportPercentage,
             .heartRate,
             .restingHeartRate,
             .heartRateVariabilitySDNN,
             .respiratoryRate,
             .vo2Max,
             .runningSpeed,
             .runningPower,
             .cyclingPower,
             .cyclingCadence:
            return .discreteAverage
            
        // Cumulative measurements that need summing
        case .activeEnergyBurned,
             .basalEnergyBurned,
             .stepCount,
             .distanceWalkingRunning,
             .distanceCycling,
             .distanceSwimming,
             .distanceDownhillSnowSports,
             .distanceWheelchair,
             .flightsClimbed,
             .pushCount,
             .swimmingStrokeCount,
             .appleExerciseTime,
             .appleStandTime,
             .dietaryEnergyConsumed,
             .dietaryProtein,
             .dietaryCarbohydrates,
             .dietaryFatTotal,
             .dietaryWater,
             .dietaryFiber,
             .dietaryVitaminA,
             .dietaryVitaminB6,
             .dietaryVitaminB12,
             .dietaryVitaminC,
             .dietaryVitaminD,
             .dietaryVitaminE,
             .dietaryVitaminK,
             .dietaryThiamin,
             .dietaryRiboflavin,
             .dietaryNiacin,
             .dietaryFolate,
             .dietaryBiotin,
             .dietaryPantothenicAcid,
             .dietaryCalcium,
             .dietaryIron,
             .dietaryMagnesium,
             .dietaryPhosphorus,
             .dietaryPotassium,
             .dietarySodium,
             .dietaryZinc,
             .dietaryIodine,
             .dietaryCopper,
             .dietarySelenium,
             .dietaryManganese,
             .dietaryChromium,
             .dietaryMolybdenum,
             .dietaryChloride,
             .dietaryCholesterol,
             .dietarySugar,
             .dietaryFatMonounsaturated,
             .dietaryFatPolyunsaturated,
             .dietaryFatSaturated,
             .dietaryCaffeine:
            return .cumulativeSum
            
        // Default to cumulative sum for any new types
        default:
            return .cumulativeSum
        }
    }

    func fetchTodayQuantity(for identifier: HKQuantityTypeIdentifier) async throws -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthError.invalidType
        }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let options: HKStatisticsOptions = switch identifier {
            case .walkingHeartRateAverage,
                 .walkingSpeed,
                 .walkingAsymmetryPercentage,
                 .walkingDoubleSupportPercentage,
                 .walkingStepLength,
                 .heartRate,
                 .restingHeartRate,
                 .heartRateVariabilitySDNN,
                 .heartRateRecoveryOneMinute,
                 .respiratoryRate,
                 .vo2Max,
                 .runningSpeed,
                 .runningPower,
                 .cyclingPower,
                 .cyclingCadence:
                .discreteAverage
            default:
                .cumulativeSum
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let value = switch options {
                    case .discreteAverage:
                        statistics?.averageQuantity()?.doubleValue(for: self.unit(for: identifier)) ?? 0
                    default:
                        statistics?.sumQuantity()?.doubleValue(for: self.unit(for: identifier)) ?? 0
                }
                
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

//    func fetchDashboardMetrics() async throws -> DashboardMetrics {
//            var metrics = DashboardMetrics()
//            
//            let types: [HKQuantityTypeIdentifier] = [
//                .activeEnergyBurned,
//                .basalEnergyBurned,
//                .stepCount,
//                .distanceWalkingRunning,
//                .appleStandTime,
//                .appleExerciseTime,
//                .flightsClimbed
//            ]
//            
//            for type in types {
//                if let quantity = try? await fetchTodayQuantity(for: type) {
//                    switch type {
//                    case .activeEnergyBurned:
//                        metrics.activeEnergy = String(format: "%.0f", quantity)
//                    case .stepCount:
//                        metrics.steps = String(format: "%.0f", quantity)
//                    case .distanceWalkingRunning:
//                        metrics.distance = String(format: "%.1f", quantity/1000)
//                    case .appleStandTime:
//                        metrics.standHours = String(format: "%.0f", quantity)
//                    case .appleExerciseTime:
//                        metrics.exercise = String(format: "%.0f", quantity)
//                    case .flightsClimbed:
//                        metrics.flights = String(format: "%.0f", quantity)
//                    default:
//                        break
//                    }
//                }
//                if let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
//                    let mindfulPredicate = HKQuery.predicateForSamples(
//                        withStart: Calendar.current.startOfDay(for: Date()),
//                        end: Date(),
//                        options: .strictStartDate
//                    )
//                    
//                    if let minutes = try? await healthStore.fetchSum(for: mindfulType, predicate: mindfulPredicate) {
//                        metrics.mindfulnessMinutes = String(format: "%.0f", minutes)
//                    }
//                }
//            }
//            
//            return metrics
//        }
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

extension HKHealthStore {
    func fetchSum(for categoryType: HKCategoryType, predicate: NSPredicate) async throws -> Double {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let totalMinutes = samples?.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                } ?? 0.0
                
                continuation.resume(returning: totalMinutes)
            }
            self.execute(query)
        }
    }
}

extension HealthKitManager {
    func fetchHRVSamples(days: Int = 10, completion: @escaping ([Double]) -> Void) {

        guard let hrvType = HKObjectType.quantityType(
            forIdentifier: .heartRateVariabilitySDNN
        ) else {
            completion([])
            return
        }

        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        )!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in

            guard let samples = samples as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }

            let values = samples.map {
                $0.quantity.doubleValue(
                    for: HKUnit.secondUnit(with: .milli)
                )
            }

            completion(values)
        }

        healthStore.execute(query)
    }
}

extension HealthKitManager {
    /// Fetch all workouts in a date range with analytics (VO2 max, HRV trend, post-workout HR, recovery)
    @MainActor
    func fetchWorkoutsWithAnalytics(from startDate: Date, to endDate: Date) async -> [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            fetchWorkouts(from: startDate, to: endDate) { result in
                continuation.resume(returning: result)
            }
        }
        var result: [(HKWorkout, WorkoutAnalytics)] = []
        for workout in workouts {
            let analytics = await computeWorkoutAnalytics(for: workout)
            result.append((workout, analytics))
        }
        return result
    }
}
