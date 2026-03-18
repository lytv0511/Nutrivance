import Foundation
import HealthKit
import Combine

/// Central physiology engine for Nutrivance.
/// All health calculations should live here, not in Views.
@MainActor
final class HealthStateEngine: ObservableObject {
    // Shared singleton instance - persists for entire app session
    static let shared = HealthStateEngine()
    
    // Use a shared HealthKitManager instance
    private let hkManager = HealthKitManager()

    // MARK: - Workout/HR Data Cache
    private var allWorkoutHRCache: [(workout: HKWorkout, heartRates: [(Date, Double)])] = []
    // Persistent cache for analytics
    private var analyticsCache: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []
    // Published staged analytics
    @Published var stagedWorkoutAnalytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []

    // MARK: - Vitals & Advanced Metrics
    @Published var sleepStages: [Date: [String: Double]] = [:] // [date: [stage: hours]]
    @Published var sleepEfficiency: [Date: Double] = [:] // [date: efficiency 0-1]
    @Published var sleepConsistency: Double? // stddev of sleep start times (hours)
    @Published var respiratoryRate: [Date: Double] = [:] // [date: breaths/min]
    @Published var wristTemperature: [Date: Double] = [:] // [date: deg C]
    @Published var spO2: [Date: Double] = [:] // [date: %]
    @Published var postWorkoutHR: [Date: Double] = [:] // [date: bpm]
    @Published var vo2Max: [Date: Double] = [:] // [date: ml/kg/min]
    @Published var heartRateZones: [Date: [String: Double]] = [:] // [date: [zone: minutes]]
    @Published var kcalBurned: [Date: Double] = [:] // [date: kcal]
    @Published var effortRating: [Date: Double] = [:] // [date: 1-10]
    @Published var favoriteSport: String? = nil
    @Published var trainingFrequency: Double? = nil // sessions/week
    @Published var trainingFrequencyBySport: [String: Double] = [:] // sport: sessions/week

    // MARK: - Workout Analytics
    @Published var workoutAnalytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []
    @Published var hasInitializedWorkoutAnalytics: Bool = false // Track if initial load completed
    @Published var hasNewDataAvailable: Bool = false // Track if new data differs from cache
    
    // MARK: - Analytics Cache Management
    private var workoutAnalyticsCacheTimestamp: Date? = nil
    private var lastCacheDaysRequested: Int = 0
    private let cacheValidityDuration: TimeInterval = 60 * 60 // 1 hour cache validity
    private let cacheFileName = "workoutAnalyticsCache.json"
    private var lastCachedWorkoutDate: Date? = nil // Tracks latest workout in persistent cache
    private var diskCacheLoaded: Bool = false

    // MARK: - Persistent Cache Management
    private func cacheDirectoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    private func persistentCacheURL() -> URL? {
        guard let dir = cacheDirectoryURL() else { return nil }
        return dir.appendingPathComponent(cacheFileName)
    }
    
    /// Save complete cache metadata for fast load on app restart
    private func savePersistentCacheMetadata(_ analytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)]) {
        guard let url = persistentCacheURL() else { return }
        let cacheData = analytics.map { pair -> [String: Any] in
            // Store essential metrics that define a workout display
            var dict: [String: Any] = [
                "workoutStartDate": pair.workout.startDate.timeIntervalSince1970,
                "workoutEndDate": pair.workout.endDate.timeIntervalSince1970,
                "workoutDuration": pair.workout.duration,
                "workoutType": pair.workout.workoutActivityType.rawValue,
                "metTotal": pair.analytics.metTotal ?? 0,
                "vo2Max": pair.analytics.vo2Max ?? 0,
                "avgHR": pair.analytics.heartRates.map { $0.1 }.average ?? 0,
                "peakHR": pair.analytics.peakHR ?? 0,
                "totalKcal": pair.workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                "distance": pair.workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                "elevationGain": pair.analytics.elevationGain ?? 0
            ]
            return dict
        }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: cacheData, options: .prettyPrinted)
            try jsonData.write(to: url, options: .atomicWrite)
            print("[Cache] Saved \(cacheData.count) workouts to disk")
        } catch {
            print("Failed to save persistent cache: \(error)")
        }
    }
    
    /// Check if persistent cache exists and extract metadata for differential refresh
    /// This runs synchronously and reads cache metadata only, not full objects
    private func loadCachedAnalyticsFromDisk() -> [CachedWorkoutSummary] {
        guard let url = persistentCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            print("[Cache] No persistent cache file found")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            if let cacheArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("[Cache] Cache file exists with \(cacheArray.count) workouts")
                let summaries = cacheArray.compactMap { dict -> CachedWorkoutSummary? in
                    guard let startTime = dict["workoutStartDate"] as? TimeInterval else { return nil }
                    return CachedWorkoutSummary(
                        startDate: Date(timeIntervalSince1970: startTime),
                        endDate: Date(timeIntervalSince1970: (dict["workoutEndDate"] as? TimeInterval) ?? startTime),
                        duration: (dict["workoutDuration"] as? Double) ?? 0,
                        workoutType: dict["workoutType"] as? String ?? "other",
                        metTotal: (dict["metTotal"] as? Double) ?? 0,
                        vo2Max: dict["vo2Max"] as? Double,
                        avgHR: (dict["avgHR"] as? Double) ?? 0,
                        peakHR: dict["peakHR"] as? Double,
                        totalKcal: (dict["totalKcal"] as? Double) ?? 0,
                        distance: (dict["distance"] as? Double) ?? 0
                    )
                }
                return summaries
            }
        } catch {
            print("[Cache] Failed to load persistent cache: \(error)")
        }
        return []
    }
    
    /// Load cache synchronously from disk - returns immediately without blocking
    private func loadCachedWorkoutsFromDisk() -> [CachedWorkoutSummary] {
        guard let url = persistentCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            if let cacheArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return cacheArray.compactMap { dict in
                    guard let startTime = dict["workoutStartDate"] as? TimeInterval else { return nil }
                    return CachedWorkoutSummary(
                        startDate: Date(timeIntervalSince1970: startTime),
                        endDate: Date(timeIntervalSince1970: (dict["workoutEndDate"] as? TimeInterval) ?? startTime),
                        duration: (dict["workoutDuration"] as? Double) ?? 0,
                        workoutType: dict["workoutType"] as? String ?? "other",
                        metTotal: (dict["metTotal"] as? Double) ?? 0,
                        vo2Max: dict["vo2Max"] as? Double,
                        avgHR: (dict["avgHR"] as? Double) ?? 0,
                        peakHR: dict["peakHR"] as? Double,
                        totalKcal: (dict["totalKcal"] as? Double) ?? 0,
                        distance: (dict["distance"] as? Double) ?? 0
                    )
                }
            }
        } catch {
            print("Failed to load persistent cache: \(error)")
        }
        return []
    }
    
    private func loadPersistentCache() {
        guard let url = persistentCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            diskCacheLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            if let cacheArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let maxDate = cacheArray.compactMap { $0["workoutStartDate"] as? TimeInterval }
                    .map { Date(timeIntervalSince1970: $0) }
                    .max()
                lastCachedWorkoutDate = maxDate
            }
            diskCacheLoaded = true
        } catch {
            print("Failed to load persistent cache: \(error)")
            diskCacheLoaded = true
        }
    }
    
    // MARK: - Cached Workout Summary for Display
    struct CachedWorkoutSummary {
        let startDate: Date
        let endDate: Date
        let duration: Double
        let workoutType: String
        let metTotal: Double
        let vo2Max: Double?
        let avgHR: Double
        let peakHR: Double?
        let totalKcal: Double
        let distance: Double
    }
    
    // MARK: - Vitals Baseline/Trend Accessors
    public var vitalsSummary: [String: (current: Double?, baseline: Double?, trend: Double?)] {
        // Example for HRV, RHR, sleep, respiratoryRate, temp, spO2
        let today = Calendar.current.startOfDay(for: Date())
        func avg(_ dict: [Date: Double], days: Int) -> Double? {
            let dates = (0..<days).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
            let vals = dates.compactMap { dict[$0] }
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        return [
            "HRV": (latestHRV, hrvBaseline7Day, hrvTrendScore),
            "RHR": (restingHeartRate, rhrBaseline7Day, nil),
            "Sleep": (sleepHours, sleepBaseline7Day, nil),
            "RespiratoryRate": (respiratoryRate[today], avg(respiratoryRate, days: 7), nil),
            "WristTemp": (wristTemperature[today], avg(wristTemperature, days: 7), nil),
            "SpO2": (spO2[today], avg(spO2, days: 7), nil)
        ]
    }

    // MARK: - Daily Workout Aggregates
    public var dailyMETAggregates: [Date: Double] {
        var aggregates: [Date: Double] = [:]
        let calendar = Calendar.current
        for (workout, analytics) in workoutAnalytics {
            let day = calendar.startOfDay(for: workout.startDate)
            let met = analytics.metTotal ?? 0
            aggregates[day, default: 0] += met
        }
        return aggregates
    }

    public var dailyVO2Aggregates: [Date: Double] {
        var aggregates: [Date: [Double]] = [:]
        let calendar = Calendar.current
        for (workout, analytics) in workoutAnalytics {
            let day = calendar.startOfDay(for: workout.startDate)
            if let vo2 = analytics.vo2Max {
                aggregates[day, default: []].append(vo2)
            }
        }
        return aggregates.mapValues { $0.reduce(0, +) / Double($0.count) }
    }

    public var dailyHRRAggregates: [Date: Double] {
        var aggregates: [Date: Double] = [:]
        let calendar = Calendar.current
        for (workout, analytics) in workoutAnalytics {
            let day = calendar.startOfDay(for: workout.startDate)
            if let hrr2 = analytics.hrr2 {
                aggregates[day] = max(aggregates[day] ?? 0, hrr2)
            }
        }
        return aggregates
    }

    // MARK: - Sleep Quality Fetch (stages, efficiency, consistency)
    private func fetchSleepQuality() {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -28, to: endDate) ?? endDate
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
            guard let samples = samples as? [HKCategorySample], error == nil else { return }
            var stages: [Date: [String: Double]] = [:]
            var efficiency: [Date: Double] = [:]
            var startTimes: [Double] = []
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600 // hours
                let value = sample.value
                var stage: String? = nil
                var isInBed = false
                switch HKCategoryValueSleepAnalysis(rawValue: value) {
                case .inBed:
                    isInBed = true
                case .asleepCore:
                    stage = "core"
                case .asleepDeep:
                    stage = "deep"
                case .asleepREM:
                    stage = "rem"
                case .awake:
                    stage = "awake"
                case .asleepUnspecified:
                    stage = "core" // Add to core
                default:
                    continue
                }
                var dayData = stages[day] ?? ["deep": 0.0, "rem": 0.0, "core": 0.0, "awake": 0.0, "inBed": 0.0]
                if isInBed {
                    dayData["inBed"] = (dayData["inBed"] ?? 0.0) + duration
                    // Collect start time for consistency
                    let hour = Double(calendar.component(.hour, from: sample.startDate)) + Double(calendar.component(.minute, from: sample.startDate)) / 60.0
                    startTimes.append(hour)
                } else if let stage = stage {
                    dayData[stage] = (dayData[stage] ?? 0.0) + duration
                }
                stages[day] = dayData
            }
            // Calculate efficiency
            for (date, data) in stages {
                let totalAsleep = (data["deep"] ?? 0) + (data["rem"] ?? 0) + (data["core"] ?? 0)
                let totalInBed = data["inBed"] ?? 0
                if totalInBed > 0 {
                    efficiency[date] = totalAsleep / totalInBed
                }
            }
            // Calculate consistency
            var consistency: Double? = nil
            if !startTimes.isEmpty {
                let mean = startTimes.reduce(0, +) / Double(startTimes.count)
                let variance = startTimes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(startTimes.count)
                consistency = sqrt(variance)
            }
            DispatchQueue.main.async {
                // Remove inBed from stages
                self.sleepStages = stages.mapValues { dict in
                    var d = dict
                    d.removeValue(forKey: "inBed")
                    return d
                }
                self.sleepEfficiency = efficiency
                self.sleepConsistency = consistency
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Vitals Fetch (respiratory rate, temp, SpO2, post-workout HR, VO2 max)
    private func fetchVitals() {
        fetchRespiratoryRate(days: 28)
        fetchWristTemperature(days: 28)
        fetchSpO2(days: 28)

        // Async/await for post-workout HR recovery and VO2 Max
        Task { [weak self] in
            guard let self = self else { return }
            if let result = await self.hkManager.fetchPostWorkoutHRRecovery() {
                let (recoveryBPM, _, _, _, workoutDate) = result
                self.postWorkoutHR[Calendar.current.startOfDay(for: workoutDate)] = recoveryBPM
            }
            if let vo2 = await self.hkManager.fetchEstimatedVO2Max() {
                let today = Calendar.current.startOfDay(for: Date())
                self.vo2Max[today] = vo2
            }
        }
    }

    private func fetchRespiratoryRate(days: Int) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { return }
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let quantitySamples = samples as? [HKQuantitySample] else { return }
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: quantitySamples) {
                calendar.startOfDay(for: $0.endDate)
            }
            var daily: [Date: Double] = [:]
            for (day, samples) in grouped {
                let vals = samples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
                let avg = vals.reduce(0, +) / Double(vals.count)
                daily[day] = avg
            }
            DispatchQueue.main.async {
                self.respiratoryRate = daily
            }
        }
        healthStore.execute(query)
    }

    private func fetchWristTemperature(days: Int) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else { return }
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let quantitySamples = samples as? [HKQuantitySample] else { return }
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: quantitySamples) {
                calendar.startOfDay(for: $0.endDate)
            }
            var daily: [Date: Double] = [:]
            for (day, samples) in grouped {
                let vals = samples.map { $0.quantity.doubleValue(for: HKUnit.degreeCelsius()) }
                let avg = vals.reduce(0, +) / Double(vals.count)
                daily[day] = avg
            }
            DispatchQueue.main.async {
                self.wristTemperature = daily
            }
        }
        healthStore.execute(query)
    }

    private func fetchSpO2(days: Int) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let quantitySamples = samples as? [HKQuantitySample] else { return }
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: quantitySamples) {
                calendar.startOfDay(for: $0.endDate)
            }
            var daily: [Date: Double] = [:]
            for (day, samples) in grouped {
                let vals = samples.map { $0.quantity.doubleValue(for: HKUnit.percent()) }
                let avg = vals.reduce(0, +) / Double(vals.count)
                daily[day] = avg * 100.0 // convert to percentage
            }
            DispatchQueue.main.async {
                self.spO2 = daily
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Intensity Metrics Fetch (effort, kcal, HR zones)
    private func fetchIntensityMetrics() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -28, to: endDate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            let workouts = (samples as? [HKWorkout]) ?? []
            var effort: [Date: Double] = [:]
            var kcal: [Date: Double] = [:]
            var hrZones: [Date: [String: Double]] = [:]
            var activityLoad: Double = 0
            for workout in workouts {
                let day = calendar.startOfDay(for: workout.endDate)
                let durationMinutes = workout.duration / 60.0
                let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
                // Effort rating: kcal per minute as intensity proxy
                let intensity = durationMinutes > 0 ? energy / durationMinutes : 0
                let effortRating = min(10, max(1, intensity / 8))
                // Add to daily values
                effort[day, default: 0] += effortRating
                kcal[day, default: 0] += energy
                activityLoad += durationMinutes * effortRating
                // Heart rate zones (if available)
                if let metadata = workout.metadata {
                    var zones: [String: Double] = [:]
                    for i in 1...5 {
                        let key = "HKWorkoutZone\(i)"
                        if let min = metadata[key] as? Double {
                            zones["Zone\(i)"] = min
                        }
                    }
                    if !zones.isEmpty {
                        hrZones[day] = zones
                    }
                }
            }
            DispatchQueue.main.async {
                self.effortRating = effort
                self.kcalBurned = kcal
                self.heartRateZones = hrZones
                self.activityLoad = activityLoad
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Favorite Sport & Training Frequency
    private func inferFavoriteSportAndFrequency() {
        // Analyze workouts over the last 28 days to determine favorite sport and frequency
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -28, to: endDate) else { return }
        hkManager.fetchWorkouts(from: startDate, to: endDate) { workouts in
            // Count workouts by activityType
            let typeCounts = workouts.reduce(into: [HKWorkoutActivityType: Int]()) { dict, workout in
                dict[workout.workoutActivityType, default: 0] += 1
            }
            // Calculate per-sport frequency (sessions/week)
            let freqBySport: [HKWorkoutActivityType: Double] = typeCounts.mapValues { Double($0) / 4.0 }
            // Find the most frequent activity type
            let favorite = typeCounts.max { $0.value < $1.value }?.key
            let freq = Double(workouts.count) / 4.0 // overall sessions per week
            // Convert HKWorkoutActivityType keys to String for Published property
            let freqBySportString: [String: Double] = freqBySport.reduce(into: [String: Double]()) { dict, pair in
                dict[pair.key.name] = pair.value
            }
            DispatchQueue.main.async {
                self.favoriteSport = favorite.map { $0.name }
                self.trainingFrequency = freq
                self.trainingFrequencyBySport = freqBySportString
            }
        }
    }

    // MARK: - Public Accessors for Graphs/Trends
    public func timeSeries(for metric: String, days: Int = 28) -> [(Date, Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dict: [Date: Double]
        switch metric.lowercased() {
        case "hrv":
            dict = Dictionary(uniqueKeysWithValues: dailyHRV.map { ($0.date, $0.average) })
        case "rhr":
            dict = [:]  // Only real HealthKit data
        case "sleep":
            dict = [:]  // Only real HealthKit data
        case "respiratoryrate": dict = respiratoryRate
        case "wristtemp": dict = wristTemperature
        case "spo2": dict = spO2
        case "postworkouthr": dict = postWorkoutHR
        case "vo2max": dict = vo2Max
        case "kcal": dict = kcalBurned
        case "effort": dict = effortRating
        default: dict = [:]
        }
        return (0..<days).compactMap { i in
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            if let v = dict[date] { return (date, v) } else { return nil }
        }.reversed()
    }

    // MARK: - HealthKit

    private let healthStore = HKHealthStore()

    // MARK: - Raw Metrics (Fetched from HealthKit)

    @Published var latestHRV: Double?          // ms
    @Published var restingHeartRate: Double?   // bpm
    @Published var sleepHours: Double?         // hours
    @Published var activityLoad: Double = 0    // arbitrary training load
    @Published var hrvHistory: [Double] = []   // last 30 HRV values
    @Published var dailyHRV: [DailyHRVPoint] = []
    @Published var sleepHRVAverage: Double?
    // Track last completed sleep session
    @Published var lastSleepStart: Date?
    @Published var lastSleepEnd: Date?

    // MARK: - Baselines (7-day and 28-day windows)

    @Published var hrvBaseline7Day: Double?      // 7-day average
    @Published var rhrBaseline7Day: Double?      // 7-day average
    @Published var sleepBaseline7Day: Double?    // 7-day average
    @Published var hrvBaseline28Day: Double?     // 28-day average
    @Published var rhrBaseline28Day: Double?     // 28-day average
    
    @Published var recoveryBaseline7Day: Double?      // 7-day recovery score average
    @Published var strainBaseline7Day: Double?        // 7-day strain score average
    @Published var circadianBaseline7Day: Double?     // 7-day circadian score average
    @Published var autonomicBaseline7Day: Double?     // 7-day autonomic balance average
    @Published var moodBaseline7Day: Double?          // 7-day mood score average
    
    // Rolling history for baseline calculations
    private var recoveryScoreHistory: [Double] = []
    private var strainScoreHistory: [Double] = []
    private var circadianScoreHistory: [Double] = []
    private var autonomicScoreHistory: [Double] = []
    private var moodScoreHistory: [Double] = []

    // MARK: - Baseline / Load Models

    struct DailyHRVPoint {
        let date: Date
        let average: Double
        let min: Double
        let max: Double
    }

    struct PhysiologicalBaseline {
        let hrvBaseline: Double
        let rhrBaseline: Double
    }

    struct TrainingLoad {
        let acuteLoad: Double
        let chronicLoad: Double
        let acwr: Double
    }

    struct PhysiologySignal {
        enum Direction {
            case higherIsBetter
            case lowerIsBetter
        }

        let value: Double
        let baseline: Double
        let direction: Direction

        var deviation: Double {
            switch direction {
            case .higherIsBetter:
                return (value - baseline) / baseline
            case .lowerIsBetter:
                return (baseline - value) / baseline
            }
        }

        var score: Double {
            let scaled = (deviation * 150) + 50
            return max(0, min(100, scaled))
        }
    }

    struct HealthDomainSignal {
        let value: Double
        let baseline: Double?
        let direction: PhysiologySignal.Direction
        let weight: Double // importance weighting in composite scores
    }

    // Example usage for future expansion:
    // nutrition, mood, subjective readiness, illness, circadian chronotype
    @Published var nutritionScore: Double = 50
    @Published var moodScore: Double = 50
    @Published var subjectiveReadinessScore: Double = 50
    @Published var illnessScore: Double = 50
    @Published var chronotypeScore: Double = 50

    // MARK: - Derived Scores

    @Published var recoveryScore: Double = 0
    @Published var strainScore: Double = 0
    @Published var readinessScore: Double = 0
    @Published var hrvTrendScore: Double = 50
    @Published var circadianHRVScore: Double = 50
    @Published var sleepHRVScore: Double = 50
    @Published var allostaticStressScore: Double = 50
    @Published var autonomicBalanceScore: Double = 50

    // MARK: - Initialization

    init() {
        // Load persistent cache on startup (synchronously)
        loadPersistentCache()
        
        // Initialize with cached data IMMEDIATELY - starts loading before any view appears
        // This ensures data loads as soon as app launches, for fastest possible display
        initializeWithCachedData()
        
        // Request HealthKit authorization and refresh metrics (in parallel)
        hkManager.requestAuthorization { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.refreshAllMetrics()
                } else {
                    print("HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }

    // MARK: - Analytics Cache Helpers
    private func saveAnalyticsCache(_ analytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)]) {
        // TODO: Implement persistent cache (e.g., UserDefaults, CoreData, file)
        self.analyticsCache = analytics
    }
    private func loadAnalyticsCache() -> [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        // TODO: Load from persistent cache
        return analyticsCache
    }

    // MARK: - Permissions

    // Removed duplicate requestPermissions; now using hkManager.requestAuthorization

    // MARK: - Public Refresh

    func refreshAllMetrics() {
        // All fetches are now on the main actor
        self.fetchLatestHRV()
        self.fetchHRVHistory(days: 30)
        self.fetchRestingHeartRate()
        self.fetchSleep()
        self.fetchBaselines()
        self.fetchTrainingLoad()
        self.fetchSleepQuality()
        print("[refreshAllMetrics] calling fetchVitals...")
        self.fetchVitals()
        self.fetchIntensityMetrics()
        self.inferFavoriteSportAndFrequency()
        self.updateScores()
    }

    /// Refresh workout analytics with smart caching
    /// Only fetches from HealthKit if cache is stale or days range changed
    func refreshWorkoutAnalytics(days: Int = 30, forceRefresh: Bool = false) async {
        // Check if cache is still valid
        if !forceRefresh && isCacheValid(for: days) {
            return // Use cached data
        }
        
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let analytics = await hkManager.fetchWorkoutsWithAnalytics(from: start, to: end)
        self.workoutAnalytics = analytics
        self.workoutAnalyticsCacheTimestamp = Date()
        self.lastCacheDaysRequested = days
        self.hasInitializedWorkoutAnalytics = true // Mark initial load complete
    }
    
    /// Check if the current cache is valid
    private func isCacheValid(for requestedDays: Int) -> Bool {
        // Cache is invalid if:
        // 1. Never been fetched
        // 2. Requested days range changed
        // 3. Cache has expired (older than cacheValidityDuration)
        guard let timestamp = workoutAnalyticsCacheTimestamp else { return false }
        guard requestedDays == lastCacheDaysRequested else { return false }
        return Date().timeIntervalSince(timestamp) < cacheValidityDuration
    }
    
    /// Force refresh from HealthKit (bypasses cache)
    func forceRefreshWorkoutAnalytics(days: Int = 30) async {
        await refreshWorkoutAnalytics(days: days, forceRefresh: true)
    }
    
    // MARK: - Persistent Cache & Smart Differential Refresh
    
    /// Load cached workouts from disk synchronously - no blocking, immediate HealthKit fetch
    func initializeWithCachedData() {
        // CRITICAL: Check for persistent cache synchronously
        // Mark initialized immediately - view won't show stale data
        let cachedSummaries = loadCachedAnalyticsFromDisk()
        
        if !cachedSummaries.isEmpty {
            // Cache exists - extract latest date for differential refresh
            self.lastCachedWorkoutDate = cachedSummaries.map { $0.startDate }.max()
            print("[Cache] ✅ Found cached data for \(cachedSummaries.count) workouts (latest: \(self.lastCachedWorkoutDate?.formatted() ?? "unknown"))")
        } else {
            print("[Cache] No cached workouts found, will fetch all from HealthKit")
        }
        
        // Mark as initialized to prevent view reload loops
        self.hasInitializedWorkoutAnalytics = true
        
        // Launch background differential refresh to fetch real data
        // - If cache exists: fetch only NEW workouts + validate 30-day window
        // - If cache empty: fetch ALL workouts (first run)
        // Either way, smartDifferentialRefresh is optimized for speed
        Task.detached { [weak self] in
            guard let self = self else { return }
            print("[Cache] Starting differential refresh...")
            await self.smartDifferentialRefresh(totalDays: 3650)
        }
    }
    
    /// Load cached data from disk on app startup
    func loadCachedWorkoutAnalytics(days: Int = 3650) async {
        // Try to deserialize from disk (simplified - store workout dates + key metrics)
        guard diskCacheLoaded else { return }
        guard let url = persistentCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            // No persistent cache, start fresh
            await refreshWorkoutAnalytics(days: days)
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            if let cacheArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                // Reconstruct display from cache summary (limited, but shows something immediately)
                // This is a placeholder - in production, you'd store more complete data
                print("[Cache] Loaded \(cacheArray.count) cached workouts from disk")
                hasInitializedWorkoutAnalytics = true
                workoutAnalyticsCacheTimestamp = Date()
            }
        } catch {
            print("Failed to deserialize cache: \\(error)")
        }
        
        // Start smart differential background refresh
        await smartDifferentialRefresh(totalDays: days)
    }
    
    /// Smart differential refresh: fetch new data first, then batch-load historical data
    func smartDifferentialRefresh(totalDays: Int = 3650) async {
        let endDate = Date()
        let totalStartDate = Calendar.current.date(byAdding: .day, value: -totalDays, to: endDate) ?? endDate
        
        // PRIORITY: If we have cached data (lastCachedWorkoutDate is set), fetch with overlap
        // Re-fetch from 7 days BEFORE cached date to validate data and get real HKWorkout objects
        // This ensures we display fresh data without doing a full 10-year fetch
        if let cachedDate = lastCachedWorkoutDate {
            print("[Cache] Loading workouts with 7-day overlap from cache date...")
            
            // Fetch from 7 days before cached date to today (small overlap ensures fresh data)
            let overlapStart = Calendar.current.date(byAdding: .day, value: -7, to: cachedDate) ?? cachedDate
            let refreshedWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: overlapStart, to: endDate)
            
            // Set workoutAnalytics immediately with refreshed data (includes real HKWorkout objects)
            self.workoutAnalytics = refreshedWorkouts
            self.workoutAnalyticsCacheTimestamp = Date()
            self.lastCachedWorkoutDate = refreshedWorkouts.map { $0.workout.startDate }.max()
            self.hasNewDataAvailable = false // Reset since we just fetched fresh data
            savePersistentCacheMetadata(refreshedWorkouts)
            
            print("[Cache] ✅ Loaded \(refreshedWorkouts.count) workouts with fresh data")
            
            // NOW: Launch background batch loading for historical data (non-blocking)
            // This populates the view progressively without blocking UI
            if totalStartDate < overlapStart {
                Task.detached { [weak self] in
                    await self?.batchLoadHistoricalWorkouts(from: totalStartDate, to: overlapStart, batchSize: 30)
                }
            }
            return
        }
        
        // FALLBACK: If no cached date (first run), load all data from HealthKit
        // This only happens on very first app launch
        print("[Cache] First run: fetching ALL workouts from HealthKit in batches")
        if workoutAnalytics.isEmpty {
            // Fetch first batch (most recent 60 days) instantly
            let recentStart = Calendar.current.date(byAdding: .day, value: -60, to: endDate) ?? totalStartDate
            let recentWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: recentStart, to: endDate)
            
            self.workoutAnalytics = recentWorkouts
            self.workoutAnalyticsCacheTimestamp = Date()
            self.lastCacheDaysRequested = totalDays
            self.lastCachedWorkoutDate = recentWorkouts.map { $0.workout.startDate }.max()
            savePersistentCacheMetadata(recentWorkouts)
            
            print("[Cache] ✅ Initial load: \(recentWorkouts.count) recent workouts displayed")
            
            // Then batch-load remaining historical data in background (non-blocking)
            if totalStartDate < recentStart {
                Task.detached { [weak self] in
                    await self?.batchLoadHistoricalWorkouts(from: totalStartDate, to: recentStart, batchSize: 30)
                }
            }
            return
        }
        
        // Step 1: Fetch new workouts (after lastCachedWorkoutDate)
        let newStartDate = totalStartDate
        let newWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: newStartDate, to: endDate)
        
        var hasDataChanges = false
        var updatedAnalytics = self.workoutAnalytics
        
        // Step 2: Append new workouts to cache
        if !newWorkouts.isEmpty {
            let newLatest = newWorkouts.map { $0.workout.startDate }.max()
            lastCachedWorkoutDate = newLatest
            updatedAnalytics.append(contentsOf: newWorkouts)
            hasDataChanges = true
            
            // Update UI with new workouts immediately
            self.workoutAnalytics = updatedAnalytics
            savePersistentCacheMetadata(updatedAnalytics)
        }
        
        // Step 3: Background check for changes in old data (last 30 days of cached data)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: newStartDate) ?? newStartDate
        if newStartDate > thirtyDaysAgo {
            // Fetch old data to check for modifications
            let oldDataRange = thirtyDaysAgo ..< newStartDate
            let historicalRefresh = await hkManager.fetchWorkoutsWithAnalytics(from: thirtyDaysAgo, to: newStartDate)
            
            // Compare: if counts differ or metrics changed, flag as hasNewDataAvailable
            let historicalCount = historicalRefresh.count
            let cachedHistoricalCount = updatedAnalytics.filter { 
                $0.workout.startDate >= thirtyDaysAgo && $0.workout.startDate < newStartDate
            }.count
            
            if historicalCount != cachedHistoricalCount {
                hasDataChanges = true
                self.hasNewDataAvailable = true
            }
            // TODO: Deep comparison of workout metrics for more granular change detection
        }
        
        // If no data changes in old range, refresh button stays as "Reload"
        // If changes detected, refresh button shows "Load New Metrics"
        if !hasDataChanges {
            self.hasNewDataAvailable = false
        }
    }
    
    /// Batch-load historical workouts in chunks (non-blocking, progressive population)
    /// Loads data backwards in time: from newest unfetched to oldest
    /// This ensures batches append naturally to the view in chronological order
    private func batchLoadHistoricalWorkouts(from earliestDate: Date, to latestDate: Date, batchSize: Int = 30) async {
        print("[Cache] Starting batch historical load: \(earliestDate.formatted()) to \(latestDate.formatted())")
        
        // Start from latest (most recent unfetched) and work backwards
        var currentEnd = latestDate
        var batchCount = 0
        
        while currentEnd > earliestDate {
            let currentStart = Calendar.current.date(byAdding: .day, value: -batchSize, to: currentEnd) ?? earliestDate
            let batchStart = max(currentStart, earliestDate)
            
            print("[Cache] Loading batch \(batchCount + 1): \(batchStart.formatted()) to \(currentEnd.formatted())")
            
            let batchWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: batchStart, to: currentEnd)
            
            if !batchWorkouts.isEmpty {
                // Append batch to workoutAnalytics on main thread for UI update
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.workoutAnalytics.append(contentsOf: batchWorkouts)
                    self.savePersistentCacheMetadata(self.workoutAnalytics)
                    print("[Cache] ✅ Batch \(batchCount + 1) complete: +\(batchWorkouts.count) workouts (total: \(self.workoutAnalytics.count))")
                }
            } else {
                print("[Cache] Batch \(batchCount + 1): No workouts found")
            }
            
            currentEnd = batchStart
            batchCount += 1
            
            // Small delay between batches to avoid blocking HealthKit queries
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
        
        print("[Cache] 🎉 Historical batch load complete!")
    }
    
    /// Replace cache with new fetched data (called when user taps "Load New Metrics" button)
    func replaceWorkoutCacheWithNewData(days: Int = 3650) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let analytics = await hkManager.fetchWorkoutsWithAnalytics(from: start, to: end)
        
        self.workoutAnalytics = analytics
        self.workoutAnalyticsCacheTimestamp = Date()
        self.lastCacheDaysRequested = days
        self.lastCachedWorkoutDate = analytics.map { $0.workout.startDate }.max()
        self.hasNewDataAvailable = false
        
        // Save fresh copy
        savePersistentCacheMetadata(analytics)
    }

    // MARK: - Fetch HRV

    private func fetchLatestHRV() {

        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: type,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in

            guard let sample = samples?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))

            DispatchQueue.main.async {
                self.latestHRV = value
            }
        }

        healthStore.execute(query)
    }

    // MARK: - HRV History

    private func fetchHRVHistory(days: Int) {

        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in

            guard let quantitySamples = samples as? [HKQuantitySample] else { return }

            let samplesWithDates = quantitySamples.map {
                (
                    date: $0.endDate,
                    value: $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                )
            }

            let values = samplesWithDates.map { $0.value }

            let calendar = Calendar.current

            let grouped = Dictionary(grouping: samplesWithDates) {
                calendar.startOfDay(for: $0.date)
            }

            let dailyPoints: [DailyHRVPoint] = grouped.map { (day, samples) in

                let vals = samples.map { $0.value }

                let avg = vals.reduce(0, +) / Double(vals.count)

                return DailyHRVPoint(
                    date: day,
                    average: avg,
                    min: vals.min() ?? avg,
                    max: vals.max() ?? avg
                )

            }.sorted { $0.date < $1.date }

            DispatchQueue.main.async {
                self.hrvHistory = values
                self.dailyHRV = dailyPoints
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Fetch Resting HR

    private func fetchRestingHeartRate() {

        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: type,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in

            guard let sample = samples?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

            DispatchQueue.main.async {
                self.restingHeartRate = value
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Fetch Sleep

    private func fetchSleep() {

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        // Fetch last 3 days to capture sleep that spans midnight
        let start = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let end = Date()

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in

            guard let samples = samples as? [HKCategorySample] else { return }

            let calendar = Calendar.current
            
            // Categorize all samples by stage type and group by day
            // Stage values: awake=2, unspecifiedAsleep=1, core=3, deep=4, rem=5
            var stagesByDay: [Date: [Int: [HKCategorySample]]] = [:]  // [day: [stageValue: [samples]]]
            
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                
                if stagesByDay[day] == nil {
                    stagesByDay[day] = [:]
                }
                if stagesByDay[day]![sample.value] == nil {
                    stagesByDay[day]![sample.value] = []
                }
                stagesByDay[day]![sample.value]?.append(sample)
            }
            
            // Get the most recent day with sleep
            guard let mostRecentDay = stagesByDay.keys.max() else { return }
            guard let stageSamples = stagesByDay[mostRecentDay] else { return }
            
            // Aggregate sleep: sum unspecified (1), core (3), deep (4), rem (5) — exclude awake (2)
            var totalSleep: Double = 0
            var earliestStart: Date?
            var latestEnd: Date?
            
            let sleepStageValues = [1, 3, 4, 5]  // unspecified, core, deep, rem
            
            for stageValue in sleepStageValues {
                if let stageAmples = stageSamples[stageValue] {
                    for sample in stageAmples {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate)
                        if duration > 0 {  // >= 10 minutes
                            totalSleep += duration
                            
                            if earliestStart == nil || sample.startDate < earliestStart! {
                                earliestStart = sample.startDate
                            }
                            if latestEnd == nil || sample.endDate > latestEnd! {
                                latestEnd = sample.endDate
                            }
                        }
                    }
                }
            }

            // Cap total sleep to 9 hours
            let cappedSleepHours = min(totalSleep / 3600, 9.0)

            DispatchQueue.main.async {
                self.sleepHours = cappedSleepHours
                if let start = earliestStart, let end = latestEnd {
                    self.lastSleepStart = start
                    self.lastSleepEnd = end
                }
            }
        }

        healthStore.execute(query)
    }

    private func fetchHRVDuringSleep(start: Date, end: Date) {

        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        // Use earliest start and latest end across all sleep stages for HRV query
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in

            guard let quantitySamples = samples as? [HKQuantitySample], quantitySamples.count > 0 else { return }

            let values = quantitySamples.map {
                $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            }

            if !values.isEmpty {
                let avg = values.reduce(0, +) / Double(values.count)
                DispatchQueue.main.async {
                    self.sleepHRVAverage = avg
                    self.sleepHRVScore = self.analyzeSleepWeightedHRV()
                }
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Baseline Fetching

    private func fetchBaselines() {
        let calendar = Calendar.current
        let endDate = Date()

        // Fetch 7-day baselines
        guard let start7Day = calendar.date(byAdding: .day, value: -7, to: endDate) else { return }
        
        // Use a dispatch group to coordinate all baseline fetches
        let group = DispatchGroup()
        var hrvAvg7: Double?
        var rhrAvg7: Double?
        var sleepAvg7: Double?
        var hrvAvg28: Double?
        var rhrAvg28: Double?
        
        // 7-day baselines
        group.enter()
        fetchAverage(for: .heartRateVariabilitySDNN, start: start7Day, end: endDate) { value in
            hrvAvg7 = value
            group.leave()
        }
        
        group.enter()
        fetchAverage(for: .restingHeartRate, start: start7Day, end: endDate) { value in
            rhrAvg7 = value
            group.leave()
        }
        
        group.enter()
        fetchSleepBaseline(days: 7) { value in
            sleepAvg7 = value
            group.leave()
        }
        
        // 28-day baselines
        guard let start28Day = calendar.date(byAdding: .day, value: -28, to: endDate) else { return }
        
        group.enter()
        fetchAverage(for: .heartRateVariabilitySDNN, start: start28Day, end: endDate) { value in
            hrvAvg28 = value
            group.leave()
        }
        
        group.enter()
        fetchAverage(for: .restingHeartRate, start: start28Day, end: endDate) { value in
            rhrAvg28 = value
            group.leave()
        }
        
        // When all fetches complete, update on main thread
        group.notify(queue: .main) {
            if let hrvAvg7 { self.hrvBaseline7Day = hrvAvg7 }
            if let rhrAvg7 { self.rhrBaseline7Day = rhrAvg7 }
            if let sleepAvg7 { self.sleepBaseline7Day = sleepAvg7 }
            if let hrvAvg28 { self.hrvBaseline28Day = hrvAvg28 }
            if let rhrAvg28 { self.rhrBaseline28Day = rhrAvg28 }
        }
    }
    
    private func fetchSleepBaseline(days: Int, completion: @escaping (Double?) -> Void) {
        
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }
        
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        
        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
            
            guard let samples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }
            
            let calendar = Calendar.current
            var dailySleepHours: [Double] = []
            
            // Group samples by calendar day
            var stagesByDay: [Date: [Int: [HKCategorySample]]] = [:]
            
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                if stagesByDay[day] == nil {
                    stagesByDay[day] = [:]
                }
                if stagesByDay[day]![sample.value] == nil {
                    stagesByDay[day]![sample.value] = []
                }
                stagesByDay[day]![sample.value]?.append(sample)
            }
            
            // For each day, sum sleep stages (1, 3, 4, 5) — exclude awake (2)
            let sleepStageValues = [1, 3, 4, 5]
            
            for (_, stageSamples) in stagesByDay.sorted(by: { $0.key < $1.key }) {
                var totalSleep: Double = 0
                
                for stageValue in sleepStageValues {
                    if let stageAmples = stageSamples[stageValue] {
                        for sample in stageAmples {
                            let duration = sample.endDate.timeIntervalSince(sample.startDate)
                            if duration > 0 {
                                totalSleep += duration
                            }
                        }
                    }
                }
                
                let cappedSleep = min(totalSleep / 3600, 9.0)
                if cappedSleep > 0 {
                    dailySleepHours.append(cappedSleep)
                }
            }
            
            // Calculate average of daily values
            if !dailySleepHours.isEmpty {
                let average = dailySleepHours.reduce(0, +) / Double(dailySleepHours.count)
                completion(average)
            } else {
                completion(nil)
            }
        }
        
        healthStore.execute(query)
    }

    private func fetchAverage(
        for identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        completion: @escaping (Double?) -> Void
    ) {

        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, result, _ in

            guard let avg = result?.averageQuantity() else {
                completion(nil)
                return
            }

            let unit: HKUnit

            switch identifier {
            case .heartRateVariabilitySDNN:
                unit = HKUnit.secondUnit(with: .milli)

            case .restingHeartRate:
                unit = HKUnit.count().unitDivided(by: HKUnit.minute())

            default:
                unit = HKUnit.count()
            }

            completion(avg.doubleValue(for: unit))
        }

        healthStore.execute(query)
    }

    // MARK: - Training Load


    // Improved: Calculate rolling acute (7d) and chronic (28d) loads with exponential decay, and update strain/ACWR
    private func fetchTrainingLoad() {
        let calendar = Calendar.current
        let endDate = Date()
        guard
            let start28 = calendar.date(byAdding: .day, value: -28, to: endDate)
        else { return }

        // Fetch all workouts in the last 28 days
        let predicate = HKQuery.predicateForSamples(withStart: start28, end: endDate)
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            let workouts = (samples as? [HKWorkout]) ?? []
            // Build a daily load array for the last 28 days
            var dailyLoads = Array(repeating: 0.0, count: 28)
            for workout in workouts {
                let dayIndex = calendar.dateComponents([.day], from: start28, to: calendar.startOfDay(for: workout.endDate)).day ?? 0
                if dayIndex >= 0 && dayIndex < 28 {
                    let durationMinutes = workout.duration / 60.0
                    let effortRating: Double
                    if let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), durationMinutes > 0 {
                        let intensity = energy / durationMinutes
                        effortRating = min(10, max(1, intensity / 8))
                    } else {
                        effortRating = 5
                    }
                    dailyLoads[dayIndex] += durationMinutes * effortRating
                }
            }
            // Calculate EWMA for acute (7d) and chronic (28d) loads
            // EWMA: load_today = lambda * today + (1-lambda) * load_yesterday
            func ewma(_ loads: [Double], lambda: Double) -> Double {
                var avg = 0.0
                for load in loads {
                    avg = lambda * load + (1 - lambda) * avg
                }
                return avg
            }
            // Higher lambda = more weight to recent days
            let acuteLambda = 2.0 / (7.0 + 1.0) // ~0.25
            let chronicLambda = 2.0 / (28.0 + 1.0) // ~0.069
            let acuteLoad = ewma(dailyLoads.suffix(7), lambda: acuteLambda)
            let chronicLoad = ewma(dailyLoads, lambda: chronicLambda)
            DispatchQueue.main.async {
                self.activityLoad = acuteLoad
                // Avoid divide by zero
                let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 0
                // Strain score: optimal 0.8-1.3, high 1.3-1.5, overload >1.5, low <0.8
                let strain: Double
                switch acwr {
                case ..<0.8: strain = 30
                case 0.8..<1.3: strain = 50
                case 1.3..<1.5: strain = 75
                default: strain = 95
                }
                // Decay strain if no recent load
                let daysSinceLast = dailyLoads.lastIndex(where: { $0 > 0 })
                var decayFactor = 1.0
                if let lastDay = daysSinceLast, lastDay < 27 {
                    let daysNoLoad = 27 - lastDay
                    decayFactor = pow(0.85, Double(daysNoLoad)) // 15% decay per day without load
                }
                self.strainScore = min(100, strain * decayFactor)
            }
        }
        healthStore.execute(query)
    }

    private func fetchWorkoutLoad(
        start: Date,
        end: Date,
        completion: @escaping (Double?) -> Void
    ) {

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in

            guard let workouts = samples as? [HKWorkout] else {
                completion(nil)
                return
            }

            var totalLoad: Double = 0

            for workout in workouts {

                let durationMinutes = workout.duration / 60.0

                let effortRating: Double

                if let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), durationMinutes > 0 {
                    // kcal per minute as intensity proxy
                    let intensity = energy / durationMinutes

                    // map typical intensity range to 1–10 effort scale
                    effortRating = min(10, max(1, intensity / 8))
                } else {
                    effortRating = 5
                }

                let load = durationMinutes * effortRating

                totalLoad += load
            }

            completion(totalLoad)
        }

        healthStore.execute(query)
    }

    // MARK: - Feel-Good Score
    @Published var feelGoodScore: Double = 50

    /// Calculate the overall Feel-Good Score based on multiple metrics
    private func calculateFeelGoodScore(subjectiveInput: Double = 0.5) -> Double {
        guard let hrv = latestHRV, let rhr = restingHeartRate, let sleep = sleepHours else {
            return 50
        }

        // Normalize components using 7-day baselines
        let hrvNorm = min(hrv / (hrvBaseline7Day ?? hrv), 1)
        let rhrNorm = max(0, min((80 - rhr) / 20, 1)) // 60-80 bpm optimal
        let sleepNorm = min(sleep / 8.0, 1)
        let recoveryNorm = min(recoveryScore / 100, 1)
        let strainNorm = max(0, min(1 - strainScore / 100, 1))
        let circadianNorm = min(circadianHRVScore / 100, 1)
        let moodNorm = subjectiveInput // 0-1 from user feedback

        // Weighted combination
        let score = 0.25*hrvNorm
                  + 0.15*rhrNorm
                  + 0.2*sleepNorm
                  + 0.2*recoveryNorm
                  + 0.1*strainNorm
                  + 0.05*circadianNorm
                  + 0.05*moodNorm

        return max(0, min(100, score * 100))
    }

    /// Update Feel-Good Score whenever scores refresh
    private func updateFeelGoodScore() {
        feelGoodScore = calculateFeelGoodScore()
    }

    // MARK: - Score Calculations

    private func updateScores() {

        recoveryScore = calculateRecoveryScore()
        strainScore = calculateStrainScore()
        hrvTrendScore = analyzeHRVTrend()
        circadianHRVScore = analyzeCircadianHRV()
        sleepHRVScore = analyzeSleepWeightedHRV()
        allostaticStressScore = calculateAllostaticStress()
        autonomicBalanceScore = calculateAutonomicBalance()

        // Morning readiness model
        let readiness = (recoveryScore * 0.55)
                      + (hrvTrendScore * 0.15)
                      + (circadianHRVScore * 0.10)
                      + (sleepHRVScore * 0.20)
                      - (strainScore * 0.30)

        readinessScore = max(0, min(100, readiness))
        
        // Update 7-day rolling averages for score baselines
        updateScoreBaselines()

        // Update Feel-Good Score
        updateFeelGoodScore()
    }
    
    private func updateScoreBaselines() {
        // Add current scores to rolling history (keep only 7 days worth)
        recoveryScoreHistory.append(recoveryScore)
        strainScoreHistory.append(strainScore)
        circadianScoreHistory.append(circadianHRVScore)
        autonomicScoreHistory.append(autonomicBalanceScore)
        moodScoreHistory.append(moodScore)
        
        // Keep only 7 most recent values
        if recoveryScoreHistory.count > 7 { recoveryScoreHistory.removeFirst() }
        if strainScoreHistory.count > 7 { strainScoreHistory.removeFirst() }
        if circadianScoreHistory.count > 7 { circadianScoreHistory.removeFirst() }
        if autonomicScoreHistory.count > 7 { autonomicScoreHistory.removeFirst() }
        if moodScoreHistory.count > 7 { moodScoreHistory.removeFirst() }
        
        // Calculate 7-day averages
        if !recoveryScoreHistory.isEmpty {
            recoveryBaseline7Day = recoveryScoreHistory.reduce(0, +) / Double(recoveryScoreHistory.count)
        }
        if !strainScoreHistory.isEmpty {
            strainBaseline7Day = strainScoreHistory.reduce(0, +) / Double(strainScoreHistory.count)
        }
        if !circadianScoreHistory.isEmpty {
            circadianBaseline7Day = circadianScoreHistory.reduce(0, +) / Double(circadianScoreHistory.count)
        }
        if !autonomicScoreHistory.isEmpty {
            autonomicBaseline7Day = autonomicScoreHistory.reduce(0, +) / Double(autonomicScoreHistory.count)
        }
        if !moodScoreHistory.isEmpty {
            moodBaseline7Day = moodScoreHistory.reduce(0, +) / Double(moodScoreHistory.count)
        }
    }

    // MARK: - Recovery

    private func calculateRecoveryScore() -> Double {

        var score: Double = 0

        if let hrv = latestHRV {
            score += normalizeHRV(hrv) * 0.4
        }

        if let rhr = restingHeartRate {
            score += normalizeRHR(rhr) * 0.25
        }

        if let sleep = sleepHours {
            score += normalizeSleep(sleep) * 0.25
        }

        let sleepHRV = analyzeSleepWeightedHRV()
        score += sleepHRV * 0.10

        // HRV trend contributes slightly to recovery
        let trend = analyzeHRVTrend()
        score += trend * 0.10

        return max(0, min(100, score))
    }

    // MARK: - Sleep-Weighted HRV

    private func analyzeSleepWeightedHRV() -> Double {
        guard let baseline = hrvBaseline7Day else { return 50 }
        guard let avgHRV = sleepHRVAverage else { return 50 }

        var score = PhysiologySignal(
            value: avgHRV,
            baseline: baseline,
            direction: .higherIsBetter
        ).score

        if let sleep = sleepHours, sleep > 0 {
            let sleepFactor = min(1.0, sleep / 8.0)
            score *= sleepFactor
        }

        return max(0, min(100, score))
    }

    // MARK: - Circadian HRV Analyzer

    private func analyzeCircadianHRV() -> Double {

        guard hrvHistory.count >= 10 else { return 50 }

        // approximate circadian pattern using early vs late samples
        let midpoint = hrvHistory.count / 2

        let firstHalf = hrvHistory.prefix(midpoint)
        let secondHalf = hrvHistory.suffix(midpoint)

        guard firstHalf.count > 0 && secondHalf.count > 0 else { return 50 }

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        guard let baseline = hrvBaseline7Day else { return 50 }

        // healthy circadian rhythm usually shows higher nighttime HRV
        let circadianDelta = (secondAvg - firstAvg) / baseline

        let scaled = (circadianDelta * 200) + 50

        return max(0, min(100, scaled))
    }

    // MARK: - HRV Trend Analyzer

    private func analyzeHRVTrend() -> Double {

        guard hrvHistory.count >= 7 else { return 50 }

        let last7 = hrvHistory.suffix(7)
        let avg7 = last7.reduce(0, +) / Double(last7.count)

        guard let baseline = hrvBaseline7Day else { return 50 }

        // deviation of recent trend from baseline
        let deviation = (avg7 - baseline) / baseline

        // map roughly -25% to +25% trend into 0–100 score
        let scaled = (deviation * 200) + 50

        return max(0, min(100, scaled))
    }

    // MARK: - Autonomic Balance
    private func calculateAutonomicBalance() -> Double {

        guard let hrv = latestHRV, let rhr = restingHeartRate else { return 50 }

        let hrvSignal = PhysiologySignal(value: hrv, baseline: hrvBaseline7Day ?? hrv, direction: .higherIsBetter)
        let rhrSignal = PhysiologySignal(value: rhr, baseline: rhrBaseline7Day ?? rhr, direction: .lowerIsBetter)

        // Combine HRV and RHR for autonomic balance, equal weighting
        let balance = (hrvSignal.score * 0.5) + (rhrSignal.score * 0.5)

        return max(0, min(100, balance))
    }

    // MARK: - Strain

    private func calculateAllostaticStress() -> Double {

        var stress: Double = 0

        if let hrv = latestHRV {
            let hrvSignal = PhysiologySignal(value: hrv, baseline: hrvBaseline28Day ?? hrv, direction: .higherIsBetter)
            stress += (100 - hrvSignal.score) * 0.35
        }

        if let rhr = restingHeartRate {
            let rhrSignal = PhysiologySignal(value: rhr, baseline: rhrBaseline28Day ?? rhr, direction: .lowerIsBetter)
            stress += (100 - rhrSignal.score) * 0.25
        }

        if let sleep = sleepHours {
            let sleepScore = normalizeSleep(sleep)
            stress += (100 - sleepScore) * 0.20
        }

        let strain = calculateStrainScore()
        stress += strain * 0.20

        return max(0, min(100, stress))
    }

    private func calculateStrainScore() -> Double {

        let acute = activityLoad
        let chronic = max(activityLoad / 4, 1) // placeholder if chronic not available
        let acwr = acute / chronic

        // Map ACWR to strain score
        // 0.8-1.3 optimal, 1.3-1.5 high, >1.5 overload
        let strainScore: Double
        switch acwr {
        case ..<0.8:
            strainScore = 30 // low load
        case 0.8..<1.3:
            strainScore = 50 // optimal
        case 1.3..<1.5:
            strainScore = 75 // high load
        default:
            strainScore = 95 // overload
        }

        return min(100, strainScore)
    }

    // MARK: - Normalization Helpers

    private func normalizeHRV(_ hrv: Double) -> Double {
        guard let baseline = hrvBaseline7Day else { return 50 }

        let signal = PhysiologySignal(value: hrv, baseline: baseline, direction: .higherIsBetter)
        return signal.score
    }

    private func normalizeRHR(_ rhr: Double) -> Double {
        guard let baseline = rhrBaseline7Day else { return 50 }

        let signal = PhysiologySignal(value: rhr, baseline: baseline, direction: .lowerIsBetter)
        return signal.score
    }

    private func normalizeSleep(_ hours: Double) -> Double {

        let optimal = 8.0
        let ratio = hours / optimal

        return max(0, min(100, ratio * 100))
    }
}
