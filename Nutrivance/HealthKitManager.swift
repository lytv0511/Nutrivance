import CoreLocation

// MARK: - Heart Rate Zone Types

final class AppResourceCoordinator {
    static let shared = AppResourceCoordinator()

    private let lock = NSLock()
    private var strainRecoveryForegroundCritical = false

    private init() {}

    func setStrainRecoveryForegroundCritical(_ enabled: Bool) {
        lock.lock()
        strainRecoveryForegroundCritical = enabled
        lock.unlock()
    }

    func isStrainRecoveryForegroundCritical() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return strainRecoveryForegroundCritical
    }
}

enum HRZoneSchema: String, Codable {
    case mhrPercentage = "mhr_percentage"
    case karvonen = "karvonen_hrr"
    case lactatThreshold = "lactate_threshold"
    case polarized = "polarized_3zone"
}

struct HeartRateZone: Identifiable, Codable {
    let id = UUID()
    let name: String
    let range: ClosedRange<Double>
    let color: String // Stored as hex for Codable
    let zoneNumber: Int
    var timeInZone: TimeInterval = 0
}

struct HRZoneProfile: Codable {
    var sport: HKWorkoutActivityType.RawValue
    var schema: HRZoneSchema
    var maxHR: Double?
    var restingHR: Double?
    var lactateThresholdHR: Double?
    var zones: [HeartRateZone]
    var lastUpdated: Date
    var adaptive: Bool = true
    var adjustmentFactor: Double = 1.0 // For dynamic adaptation
    
    func zone(for hr: Double) -> HeartRateZone? {
        zones.first { $0.range.contains(hr) }
    }
}

struct HRZoneAnchorMetrics: Codable {
    var age: Double?
    var restingHR: Double?
    var maxHR: Double? // Tested or measured
    var peakHRLast90Days: Double?
    var lactateThresholdHR: Double?
    var vo2Max: Double?
    var hrvTrendDays7: Double? // 7-day HRV trend
    var sleepQualityWeekly: Double? // 1-5 scale
    var recoveryScore: Double? // 0-100
    var lastUpdated: Date = Date()
}

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
    let speedSeries: [(Date, Double)] // Speed in m/s
    let cadenceSeries: [(Date, Double)] // Cadence in rpm
    let elevationSeries: [(Date, Double)] // Elevation in meters
    let elevationGain: Double? // Total elevation gain in meters
    let verticalOscillationSeries: [(Date, Double)] // cm
    let groundContactTimeSeries: [(Date, Double)] // ms
    let strideLengthSeries: [(Date, Double)] // m
    let strokeCountSeries: [(Date, Double)] // count per sample
    let verticalOscillation: Double? // For running, in cm
    let groundContactTime: Double? // For running, in ms
    let strideLength: Double? // For running, in meters
    var hrZoneProfile: HRZoneProfile?
    var hrZoneBreakdown: [(zone: HeartRateZone, timeInZone: TimeInterval)] = []
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
    private func fetchDiscreteAverageSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout,
        intervalSeconds: Int = 15
    ) async -> [(Date, Double)] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        var interval = DateComponents()
        interval.second = intervalSeconds

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: workout.startDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }

                var series: [(Date, Double)] = []
                results.enumerateStatistics(from: workout.startDate, to: workout.endDate) { statistics, _ in
                    if let quantity = statistics.averageQuantity() {
                        series.append((statistics.startDate, quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: series)
            }

            self.healthStore.execute(query)
        }
    }

    private func fetchCumulativeSumSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout,
        intervalSeconds: Int = 15
    ) async -> [(Date, Double)] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        var interval = DateComponents()
        interval.second = intervalSeconds

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: workout.startDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }

                var series: [(Date, Double)] = []
                results.enumerateStatistics(from: workout.startDate, to: workout.endDate) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        series.append((statistics.startDate, quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: series)
            }

            self.healthStore.execute(query)
        }
    }

    private func deriveSpeedSeries(from routeLocations: [CLLocation]) -> [(Date, Double)] {
        guard routeLocations.count > 1 else { return [] }

        var series: [(Date, Double)] = []
        series.reserveCapacity(routeLocations.count - 1)

        for pair in zip(routeLocations, routeLocations.dropFirst()) {
            let deltaT = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard deltaT > 0 else { continue }
            let distance = pair.1.distance(from: pair.0)
            let speed = max(0, distance / deltaT)
            let timestamp = pair.1.timestamp
            series.append((timestamp, speed))
        }

        return series
    }

    /// Compute analytics for a given workout: VO2 max, METs, post-workout HR time series, HRR
    func computeWorkoutAnalytics(for workout: HKWorkout) async -> WorkoutAnalytics {
        // Fetch heart rate samples for the workout
        let hrSamples = await fetchHeartRateSamples(for: workout)
        
        // Fetch user data for VO2 calculations
        let userMass = await fetchBodyMass()
        let userAge = await fetchAgeAsync()
        let userRestingHR = await fetchRestingHeartRateLatest()

        var powerSeries: [(Date, Double)] = []

        // --- VO2 Max Calculation ---
        var vo2Max: Double? = nil
        let activityType = workout.workoutActivityType
        if activityType == .cycling {
            // Fetch cycling power as a time series and compute average
            let powerType = HKQuantityType.quantityType(forIdentifier: .cyclingPower)
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
            // --- Improved VO2 Calculation Logic ---
            let mass = userMass
            let maxHR = 220.0 - userAge
            let hrRest = userRestingHR
            let avgHR = hrSamples.isEmpty ? 0 : hrSamples.map { $0.1 }.reduce(0, +) / Double(hrSamples.count)

            if let avgPower, mass > 0, avgPower > 0 {
                // --- PRO POWER-BASED VO2 MODEL ---
                // Step 1: Estimate VO2 from power (ml/kg/min)
                let vo2Current = 10.8 * (avgPower / mass) + 7.0
                
                // Step 2: HR reserve scaling with clamp for stability
                let hrReserve = maxHR - hrRest
                let hrUsed = max(avgHR - hrRest, 10) // prevent explosion
                let intensityFactor = min(hrUsed / hrReserve, 1.0)
                
                // Step 3: Estimate VO2 max
                vo2Max = vo2Current / max(intensityFactor, 0.5) // avoid over-scaling low intensity
            } else if avgHR > 0 {
                // --- FALLBACK HR-BASED MODEL (NO POWER) ---
                let hrReserve = maxHR - hrRest
                let intensity = (avgHR - hrRest) / hrReserve
                
                // Estimate METs from HR intensity (rough but stable)
                let estimatedMET = 6.0 + (intensity * 6.0) // range ~6–12 METs
                
                // Convert MET → VO2
                let vo2Current = estimatedMET * 3.5
                
                // Scale to VO2 max
                vo2Max = vo2Current / max(intensity, 0.5)
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

        // --- Speed Series ---
        let routeLocations = await fetchWorkoutRouteLocations(for: workout)
        var speedSeries: [(Date, Double)] = []
        let speedIdentifier: HKQuantityTypeIdentifier? = {
            switch activityType {
            case .cycling:
                return .cyclingSpeed
            case .walking, .hiking:
                return .walkingSpeed
            case .running:
                return .runningSpeed
            default:
                return .runningSpeed
            }
        }()
        if let speedIdentifier {
            speedSeries = await fetchDiscreteAverageSeries(
                for: speedIdentifier,
                unit: .meter().unitDivided(by: .second()),
                workout: workout
            )
        }
        if speedSeries.count <= 1 {
            speedSeries = deriveSpeedSeries(from: routeLocations)
        }

        // --- Cadence Series ---
        var cadenceSeries: [(Date, Double)] = []
        if activityType == .cycling {
            cadenceSeries = await fetchDiscreteAverageSeries(
                for: .cyclingCadence,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                workout: workout
            )
        }

        // --- Elevation Series and Gain ---
        var elevationSeries: [(Date, Double)] = []
        var elevationGain: Double? = nil
        // Elevation gain from metadata
        if let elevationQuantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            elevationGain = elevationQuantity.doubleValue(for: .meter())
        }
        elevationSeries = routeLocations.compactMap { location in
            guard location.verticalAccuracy >= 0 else { return nil }
            return (location.timestamp, location.altitude)
        }
        if elevationGain == nil, elevationSeries.count > 1 {
            var computedGain = 0.0
            for pair in zip(elevationSeries, elevationSeries.dropFirst()) {
                let delta = pair.1.1 - pair.0.1
                if delta > 0 {
                    computedGain += delta
                }
            }
            elevationGain = computedGain > 0 ? computedGain : nil
        }

        // --- Running Metrics ---
        var verticalOscillationSeries: [(Date, Double)] = []
        var groundContactTimeSeries: [(Date, Double)] = []
        var strideLengthSeries: [(Date, Double)] = []
        var strokeCountSeries: [(Date, Double)] = []
        var verticalOscillation: Double? = nil
        var groundContactTime: Double? = nil
        var strideLength: Double? = nil
        if activityType == .running {
            verticalOscillationSeries = await fetchDiscreteAverageSeries(
                for: .runningVerticalOscillation,
                unit: .meter(),
                workout: workout
            ).map { ($0.0, $0.1 * 100) }
            verticalOscillation = verticalOscillationSeries.map(\.1).average

            groundContactTimeSeries = await fetchDiscreteAverageSeries(
                for: .runningGroundContactTime,
                unit: .secondUnit(with: .milli),
                workout: workout
            )
            groundContactTime = groundContactTimeSeries.map(\.1).average

            strideLengthSeries = await fetchDiscreteAverageSeries(
                for: .runningStrideLength,
                unit: .meter(),
                workout: workout
            )
            strideLength = strideLengthSeries.map(\.1).average

            if cadenceSeries.isEmpty, !speedSeries.isEmpty, !strideLengthSeries.isEmpty {
                cadenceSeries = strideLengthSeries.compactMap { point in
                    guard point.1 > 0 else { return nil }
                    let nearestSpeed = speedSeries.min { lhs, rhs in
                        abs(lhs.0.timeIntervalSince(point.0)) < abs(rhs.0.timeIntervalSince(point.0))
                    }?.1 ?? 0
                    guard nearestSpeed > 0 else { return nil }
                    return (point.0, (nearestSpeed / point.1) * 60)
                }
            }
        } else if activityType == .swimming {
            strokeCountSeries = await fetchCumulativeSumSeries(
                for: .swimmingStrokeCount,
                unit: .count(),
                workout: workout
            )
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
            for i in metSeries.indices.dropLast() {
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

        // HRR diagnostic logging
        if let peak = peakHR {
            let hr2Raw = hrAt(2)
            let target2min = workout.endDate.addingTimeInterval(2 * 60)
            let closest2 = postWorkoutHRSeries.min(by: { abs($0.0.timeIntervalSince(target2min)) < abs($1.0.timeIntervalSince(target2min)) })
            let offsetSec = closest2.map { abs($0.0.timeIntervalSince(target2min)) }
            print("[HRR-diag] workout=\(workout.workoutActivityType.name) date=\(workout.startDate.formatted(date: .abbreviated, time: .shortened))")
            print("[HRR-diag]   peakHR=\(String(format: "%.1f", peak)) hrAt(2)=\(hr2Raw.map { String(format: "%.1f", $0) } ?? "nil") offsetFromTarget=\(offsetSec.map { String(format: "%.1f", $0) + "s" } ?? "nil")")
            print("[HRR-diag]   hrr2=\(hrr2.map { String(format: "%.1f", $0) } ?? "nil") (peak - hrAt2)")
            print("[HRR-diag]   postWorkoutSamples=\(postWorkoutHRSeries.count) firstSample=\(postWorkoutHRSeries.first.map { "\($0.0.formatted(date: .omitted, time: .standard)) \(String(format: "%.0f", $0.1))bpm" } ?? "none")")
        }

        // --- HR Zone Profile & Breakdown ---
        let zoneProfile = await getOrCreateZoneProfile(for: workout.workoutActivityType)
        let zoneBreakdown = calculateZoneBreakdown(heartRates: hrSamples, zoneProfile: zoneProfile)
        
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
        print("  HR Zone Profile: \(zoneProfile.schema.rawValue) - max HR: \(zoneProfile.maxHR ?? 0), resting HR: \(zoneProfile.restingHR ?? 0)")
        print("  Zone breakdown: \(zoneBreakdown.map { "\($0.zone.name): \(Int($0.timeInZone))s" }.joined(separator: ", "))")

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
            powerSeries: powerSeries,
            speedSeries: speedSeries,
            cadenceSeries: cadenceSeries,
            elevationSeries: elevationSeries,
            elevationGain: elevationGain,
            verticalOscillationSeries: verticalOscillationSeries,
            groundContactTimeSeries: groundContactTimeSeries,
            strideLengthSeries: strideLengthSeries,
            strokeCountSeries: strokeCountSeries,
            verticalOscillation: verticalOscillation,
            groundContactTime: groundContactTime,
            strideLength: strideLength,
            hrZoneProfile: zoneProfile,
            hrZoneBreakdown: zoneBreakdown
        )
    }
}

// --- Place these in an extension at the end of the file ---

// --- Place these in an extension at the end of the file ---

extension HealthKitManager {
    /// Fetch all workouts in a given date range, and for each, fetch all heart rate samples during the workout.
    /// Prints all data fetched (workout summary and HR samples) to the terminal.
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
        
        // Fetch user data for VO2 calculations
        let userAge = await fetchAgeAsync()
        let userRestingHR = await fetchRestingHeartRateLatest()
        
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
            let age = userAge
            let maxHR = 220.0 - age
            let hrRest = userRestingHR
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

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running:
            return "running"
        case .walking:
            return "walking"
        case .cycling:
            return "cycling"
        case .swimming:
            return "swimming"
        case .hiking:
            return "hiking"
        case .traditionalStrengthTraining:
            return "strength"
        case .functionalStrengthTraining:
            return "functional strength"
        case .highIntensityIntervalTraining:
            return "hiit"
        case .yoga:
            return "yoga"
        case .mixedCardio:
            return "mixed cardio"
        case .elliptical:
            return "elliptical"
        case .rowing:
            return "rowing"
        case .stairClimbing:
            return "stair climbing"
        case .cooldown:
            return "cooldown"
        case .flexibility:
            return "flexibility"
        case .coreTraining:
            return "core training"
        case .pilates:
            return "pilates"
        case .dance:
            return "dance"
        case .barre:
            return "barre"
        case .mindAndBody:
            return "mind and body"
        case .preparationAndRecovery:
            return "preparation and recovery"
        case .other:
            return "other"
        default:
            return String(describing: self)
                .replacingOccurrences(of: "HKWorkoutActivityType", with: "")
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
    }
}

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
    (HKObjectType.quantityType(forIdentifier: .flightsClimbed)!, "flights"),
    
    // Additional workout metrics
    (HKObjectType.quantityType(forIdentifier: .cyclingPower)!, "cycling_power"),
    (HKObjectType.quantityType(forIdentifier: .runningSpeed)!, "running_speed"),
    (HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!, "running_vertical_oscillation"),
    (HKObjectType.quantityType(forIdentifier: .runningGroundContactTime)!, "running_ground_contact_time"),
    (HKObjectType.quantityType(forIdentifier: .runningStrideLength)!, "running_stride_length"),
    (HKObjectType.quantityType(forIdentifier: .cyclingCadence)!, "cycling_cadence"),
    (HKObjectType.quantityType(forIdentifier: .physicalEffort)!, "physical_effort")
]

final class HealthKitManager: ObservableObject, @unchecked Sendable {
    let healthStore: HKHealthStore
    private var maxHR7DayCache: [Date: Double?] = [:]
    private var restingHR7DayCache: [Date: Double?] = [:]
    private var lthrDateCache: [Date: Double?] = [:]
    
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
        // Request biological sex for better age handling
        let sexType = HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        
        // Request authorization specifically for characteristics
        healthStore.requestAuthorization(toShare: [], read: [sexType, dobType]) { success, error in
            DispatchQueue.main.async {
                do {
                    let dateOfBirth = try self.healthStore.dateOfBirthComponents().date
                    if let dob = dateOfBirth {
                        let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 30
                        completion(Double(age))
                    } else {
                        print("Date of birth not set in HealthKit")
                        completion(30.0) // Default fallback
                    }
                } catch {
                    print("Error fetching date of birth: \(error)")
                    completion(30.0)
                }
            }
        }
    }
    
    func fetchAgeAsync() async -> Double {
        return await withCheckedContinuation { continuation in
            self.fetchAge { age in
                continuation.resume(returning: age)
            }
        }
    }
    
    func fetchBodyMass() async -> Double {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return 70.0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    let mass = sample.quantity.doubleValue(for: HKUnit(from: "kg"))
                    continuation.resume(returning: mass)
                } else {
                    continuation.resume(returning: 70.0) // Default fallback
                }
            }
            self.healthStore.execute(query)
        }
    }
    
    func fetchRestingHeartRateLatest() async -> Double {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return 60.0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: restingHRType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    let hr = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    continuation.resume(returning: hr)
                } else {
                    continuation.resume(returning: 60.0) // Default fallback
                }
            }
            self.healthStore.execute(query)
        }
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
            
            // Mindfulness (journal editor sessions → Mindful Minutes)
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            
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
            
            // Cycling Metrics
            HKQuantityType.quantityType(forIdentifier: .cyclingPower)!,
            HKQuantityType.quantityType(forIdentifier: .cyclingCadence)!,
            HKQuantityType.quantityType(forIdentifier: .cyclingSpeed)!,
            
            // Running Metrics
            HKQuantityType.quantityType(forIdentifier: .walkingSpeed)!,
            HKQuantityType.quantityType(forIdentifier: .runningSpeed)!,
            HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKQuantityType.quantityType(forIdentifier: .runningStrideLength)!,
            HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount)!,
            
            // METs and Effort
            HKQuantityType.quantityType(forIdentifier: .physicalEffort)!,
            
            // Heart Rate and Health Metrics
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!,
            HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!,

            // Workout route series (GPS)
            HKSeriesType.workoutRoute(),
            
            // Body Measurements
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            
            // Sleep and Mindfulness
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKSampleType.stateOfMindType()
        ]).union(typesToShare)
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                #if os(iOS)
                if success {
                    HealthKitCloudSyncProducer.shared.startIfPossible(healthStore: self.healthStore)
                }
                #endif
                completion(success, error)
            }
        }
    }

    private func fetchWorkoutRouteLocations(for workout: HKWorkout) async -> [CLLocation] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeType = HKSeriesType.workoutRoute()

        let route: HKWorkoutRoute? = await withCheckedContinuation { continuation in
            let sampleQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil,
                      let routes = samples as? [HKWorkoutRoute],
                      let route = routes.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: route)
            }
            self.healthStore.execute(sampleQuery)
        }

        guard let route else { return [] }

        return await withCheckedContinuation { continuation in
            var allLocations: [CLLocation] = []
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                guard error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                if let locations {
                    allLocations.append(contentsOf: locations)
                }

                if done {
                    continuation.resume(returning: allLocations)
                }
            }
            self.healthStore.execute(routeQuery)
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

    /// Writes a mindful session interval to Health (counts toward Mindful Minutes). Requires mindful session in share authorization.
    func saveMindfulSession(start: Date, end: Date, completion: ((Bool, Error?) -> Void)? = nil) {
        guard end > start else {
            completion?(false, nil)
            return
        }
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 15 else {
            completion?(false, nil)
            return
        }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            completion?(false, nil)
            return
        }
        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end,
            metadata: ["NutrivanceActivity": "journal_editor"]
        )
        healthStore.save(sample) { success, error in
            DispatchQueue.main.async {
                completion?(success, error)
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
        if AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            DispatchQueue.main.async {
                completion([:])
            }
            return
        }

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

    func fetchStateOfMindSamples(from startDate: Date, to endDate: Date) async -> [HKStateOfMind] {
        let sampleType = HKSampleType.stateOfMindType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let states = (samples ?? []).compactMap { $0 as? HKStateOfMind }
                continuation.resume(returning: states)
            }
            self.healthStore.execute(query)
        }
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
    
    func fetchWorkouts(
        from startDate: Date,
        to endDate: Date,
        allowDuringForegroundCritical: Bool = false,
        completion: @escaping ([HKWorkout]) -> Void
    ) {
        if !allowDuringForegroundCritical, AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

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
    func fetchWorkoutsWithAnalytics(
        from startDate: Date,
        to endDate: Date,
        allowDuringForegroundCritical: Bool = false
    ) async -> [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        if !allowDuringForegroundCritical, AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            return []
        }

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            fetchWorkouts(
                from: startDate,
                to: endDate,
                allowDuringForegroundCritical: allowDuringForegroundCritical
            ) { result in
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

    func fetchDailyOxygenSaturation(
        from startDate: Date,
        to endDate: Date
    ) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                let calendar = Calendar.current
                let grouped = Dictionary(grouping: quantitySamples) {
                    calendar.startOfDay(for: $0.endDate)
                }

                var daily: [Date: Double] = [:]
                for (day, samples) in grouped {
                    let values = samples.map { $0.quantity.doubleValue(for: HKUnit.percent()) }
                    guard !values.isEmpty else { continue }
                    daily[day] = (values.reduce(0, +) / Double(values.count)) * 100.0
                }

                continuation.resume(returning: daily)
            }

            self.healthStore.execute(query)
        }
    }
}

// MARK: - Heart Rate Zone Calculations

extension HealthKitManager {
    
    /// Calculate maximum heart rate using Tanaka formula: 208 - 0.7 * age
    func estimateMaxHRTanaka(age: Double) -> Double {
        return 208.0 - (0.7 * age)
    }
    
    /// Fetch anchor metrics needed for zone calculation
    func fetchAnchorMetrics() async -> HRZoneAnchorMetrics {
        var metrics = HRZoneAnchorMetrics()
        
        metrics.age = await fetchAgeAsync()
        metrics.restingHR = await fetchRestingHeartRateLatest()
        
        // Fetch peak HR from last 90 days of workouts
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recentPeak = await fetchPeakHRLast90Days(from: ninetyDaysAgo)
        metrics.peakHRLast90Days = recentPeak
        
        // Fetch VO2 max
        metrics.vo2Max = await withCheckedContinuation { continuation in
            fetchVO2Max { value in
                continuation.resume(returning: value > 0 ? value : nil)
            }
        }
        
        metrics.lastUpdated = Date()
        return metrics
    }
    
    /// Fetch peak HR from workouts in a date range
    func fetchPeakHRLast90Days(from startDate: Date) async -> Double? {
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            fetchWorkouts(from: startDate, to: Date()) { result in
                continuation.resume(returning: result)
            }
        }
        
        var peakHR: Double? = nil
        for workout in workouts {
            let hrSamples = await fetchHeartRateSamples(for: workout)
            if let maxHRInWorkout = hrSamples.map({ $0.1 }).max() {
                if peakHR == nil || maxHRInWorkout > peakHR! {
                    peakHR = maxHRInWorkout
                }
            }
        }
        return peakHR
    }
    
    /// Calculate heart rate reserve: MHR - RHR
    func calculateHeartRateReserve(maxHR: Double, restingHR: Double) -> Double {
        return max(0, maxHR - restingHR)
    }
    
    /// Infer lactate threshold HR from recent workouts
    /// Uses 95th percentile of max HRs in high-intensity efforts (>80% estimated maxHR)
    func inferLactateThresholdHR(from startDate: Date = Date(timeIntervalSinceNow: -30 * 86400)) async -> Double? {
        let anchor = await fetchAnchorMetrics()
        guard let age = anchor.age else { return nil }
        
        let estimatedMaxHR = estimateMaxHRTanaka(age: age)
        let threshold = estimatedMaxHR * 0.80
        
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            fetchWorkouts(from: startDate, to: Date()) { result in
                continuation.resume(returning: result)
            }
        }
        
        var highIntensityHRValues: [Double] = []
        for workout in workouts {
            let hrSamples = await fetchHeartRateSamples(for: workout)
            let highIntensity = hrSamples.filter { $0.1 >= threshold }.map { $0.1 }
            highIntensityHRValues.append(contentsOf: highIntensity)
        }
        
        guard !highIntensityHRValues.isEmpty else { return nil }
        let sorted = highIntensityHRValues.sorted()
        let p95Index = Int(Double(sorted.count) * 0.95)
        return sorted[min(p95Index, sorted.count - 1)]
    }
    
    /// Determines the best zone schema for a sport
    func recommendedSchema(for sport: HKWorkoutActivityType) -> HRZoneSchema {
        switch sport {
        case .running, .cycling, .rowing:
            return .lactatThreshold
        case .swimming:
            return .mhrPercentage
        case .walking, .preparationAndRecovery, .yoga, .pilates, .flexibility:
            return .karvonen
        default:
            return .mhrPercentage
        }
    }
    
    /// Generate HR zones using Maximum Heart Rate % schema
    func generateMHRPercentageZones(maxHR: Double) -> [HeartRateZone] {
        let zoneRanges: [(String, Double, Double, String, Int)] = [
            ("Zone 1: Easy", 0.50, 0.60, "0099FF", 1),
            ("Zone 2: Base", 0.60, 0.70, "00CC00", 2),
            ("Zone 3: Tempo", 0.70, 0.80, "FFCC00", 3),
            ("Zone 4: Threshold", 0.80, 0.90, "FF6600", 4),
            ("Zone 5: Max", 0.90, 1.00, "FF0000", 5)
        ]
        
        return zoneRanges.map { name, lowPct, highPct, color, num in
            let lower = maxHR * lowPct
            let upper = maxHR * highPct
            return HeartRateZone(name: name, range: lower...upper, color: color, zoneNumber: num)
        }
    }
    
    /// Generate HR zones using Karvonen (HRR) formula
    func generateKarvonenZones(maxHR: Double, restingHR: Double) -> [HeartRateZone] {
        let hrr = calculateHeartRateReserve(maxHR: maxHR, restingHR: restingHR)
        
        let zoneRanges: [(String, Double, Double, String, Int)] = [
            ("Zone 1: Easy", 0.50, 0.60, "0099FF", 1),
            ("Zone 2: Base", 0.60, 0.70, "00CC00", 2),
            ("Zone 3: Tempo", 0.70, 0.80, "FFCC00", 3),
            ("Zone 4: Threshold", 0.80, 0.90, "FF6600", 4),
            ("Zone 5: Max", 0.90, 1.00, "FF0000", 5)
        ]
        
        return zoneRanges.map { name, lowPct, highPct, color, num in
            let lower = (hrr * lowPct) + restingHR
            let upper = (hrr * highPct) + restingHR
            return HeartRateZone(name: name, range: lower...upper, color: color, zoneNumber: num)
        }
    }
    
    /// Generate HR zones based on Lactate Threshold
    func generateLTHRZones(lthr: Double) -> [HeartRateZone] {
        let zoneRanges: [(String, Double, Double, String, Int)] = [
            ("Zone 1: Endurance Z1", 0.00, 0.85, "0099FF", 1),
            ("Zone 2: Endurance Z2", 0.85, 0.89, "00CC00", 2),
            ("Zone 3: Tempo", 0.90, 0.94, "FFCC00", 3),
            ("Zone 4: Threshold", 0.95, 0.99, "FF6600", 4),
            ("Zone 5: VO₂ Max", 1.00, 1.20, "FF0000", 5)
        ]
        
        return zoneRanges.map { name, lowPct, highPct, color, num in
            let lower = lthr * lowPct
            let upper = lthr * highPct
            return HeartRateZone(name: name, range: lower...upper, color: color, zoneNumber: num)
        }
    }
    
    /// Generate polarized 3-zone model
    func generatePolarizedZones(lthr: Double) -> [HeartRateZone] {
        return [
            HeartRateZone(name: "Zone 1: Low", range: 0...(lthr * 0.80), color: "0099FF", zoneNumber: 1),
            HeartRateZone(name: "Zone 2: Threshold", range: (lthr * 0.80)...lthr, color: "FFCC00", zoneNumber: 2),
            HeartRateZone(name: "Zone 3: High", range: lthr...250, color: "FF0000", zoneNumber: 3)
        ]
    }
    
    /// Create an HR zone profile for a sport
    func createHRZoneProfile(
        for sport: HKWorkoutActivityType,
        schema: HRZoneSchema? = nil,
        customMaxHR: Double? = nil,
        customRestingHR: Double? = nil,
        customLTHR: Double? = nil
    ) async -> HRZoneProfile {
        let metricsSchema = schema ?? recommendedSchema(for: sport)
        
        // Fetch or use custom metrics
        let maxHR: Double
        let restingHR: Double
        
        if let customMax = customMaxHR {
            maxHR = customMax
        } else {
            let anchor = await fetchAnchorMetrics()
            if let custom = customMaxHR {
                maxHR = custom
            } else if let peak = anchor.peakHRLast90Days, peak > 0 {
                maxHR = peak * 1.05 // Override Tanaka with measured + buffer
            } else if let age = anchor.age {
                maxHR = estimateMaxHRTanaka(age: age)
            } else {
                maxHR = 190 // Fallback
            }
        }
        
        if let customResting = customRestingHR {
            restingHR = customResting
        } else {
        restingHR = await fetchRestingHeartRateLatest()
        }
        
        // Infer lactate threshold before switch to avoid async in autoclosure
        let inferredLTHR: Double?
        if let customLTHR {
            inferredLTHR = customLTHR
        } else {
            inferredLTHR = await inferLactateThresholdHR()
        }
        
        // Generate zones based on schema
        let zones: [HeartRateZone]
        switch metricsSchema {
        case .mhrPercentage:
            zones = generateMHRPercentageZones(maxHR: maxHR)
        case .karvonen:
            zones = generateKarvonenZones(maxHR: maxHR, restingHR: restingHR)
        case .lactatThreshold:
            let lthr = customLTHR ?? (inferredLTHR ?? maxHR * 0.88)
            zones = generateLTHRZones(lthr: lthr)
        case .polarized:
            let lthr = customLTHR ?? (inferredLTHR ?? maxHR * 0.88)
            zones = generatePolarizedZones(lthr: lthr)
        }
        
        let lactateThresholdHR = customLTHR ?? (inferredLTHR ?? maxHR * 0.88)
        
        return HRZoneProfile(
            sport: sport.rawValue,
            schema: metricsSchema,
            maxHR: maxHR,
            restingHR: restingHR,
            lactateThresholdHR: lactateThresholdHR,
            zones: zones,
            lastUpdated: Date(),
            adaptive: true
        )
    }
    
    /// Calculate time in each zone for a workout
    func calculateZoneBreakdown(
        heartRates: [(Date, Double)],
        zoneProfile: HRZoneProfile
    ) -> [(zone: HeartRateZone, timeInZone: TimeInterval)] {
        var zoneTimeMap: [Int: TimeInterval] = [:]
        for zone in zoneProfile.zones {
            zoneTimeMap[zone.zoneNumber] = 0
        }
        
        let sorted = heartRates.sorted { $0.0 < $1.0 }
        for i in sorted.indices.dropLast() {
            let hr = sorted[i].1
            let timeToNext = sorted[i + 1].0.timeIntervalSince(sorted[i].0)
            
            if let zone = zoneProfile.zone(for: hr) {
                zoneTimeMap[zone.zoneNumber, default: 0] += timeToNext
            }
        }
        
        return zoneProfile.zones.map { zone in
            (zone, zoneTimeMap[zone.zoneNumber] ?? 0)
        }.filter { $0.1 > 0 }
    }
    
    /// Apply adaptive adjustments based on HRV, sleep, recovery
    func adaptZoneProfile(
        _ profile: inout HRZoneProfile,
        adjustmentFactor: Double = 1.0
    ) {
        profile.adjustmentFactor = adjustmentFactor
        
        // Multiply zone boundaries by adjustment factor
        profile.zones = profile.zones.map { zone in
            let adjustedLower = zone.range.lowerBound * adjustmentFactor
            let adjustedUpper = zone.range.upperBound * adjustmentFactor
            let adjustedRange = adjustedLower...adjustedUpper
            
            return HeartRateZone(
                name: zone.name,
                range: adjustedRange,
                color: zone.color,
                zoneNumber: zone.zoneNumber,
                timeInZone: zone.timeInZone
            )
        }
    }
    
    /// Save zone profile to UserDefaults for persistence
    func saveZoneProfile(_ profile: HRZoneProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "hr_zone_profile_\(profile.sport)")
        }
    }
    
    /// Load zone profile from UserDefaults
    func loadZoneProfile(for sport: HKWorkoutActivityType) -> HRZoneProfile? {
        guard let data = UserDefaults.standard.data(forKey: "hr_zone_profile_\(sport.rawValue)") else {
            return nil
        }
        return try? JSONDecoder().decode(HRZoneProfile.self, from: data)
    }
    
    /// Get cached zone profile or create new one
    func getOrCreateZoneProfile(
        for sport: HKWorkoutActivityType,
        forceRefresh: Bool = false
    ) async -> HRZoneProfile {
        if !forceRefresh, let cached = loadZoneProfile(for: sport) {
            // Check if cache is fresh (within 7 days)
            if Date().timeIntervalSince(cached.lastUpdated) < 7 * 86400 {
                return cached
            }
        }
        
        let profile = await createHRZoneProfile(for: sport)
        saveZoneProfile(profile)
        return profile
    }

    func fetchMaxHR(workoutDate: Date) async -> Double? {
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: workoutDate)
        if let cached = maxHR7DayCache[anchorDate] {
            return cached
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            maxHR7DayCache[anchorDate] = nil
            return nil
        }

        let startDate = calendar.date(byAdding: .day, value: -6, to: anchorDate) ?? anchorDate
        let endDate = calendar.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let result: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let unit = HKUnit.count().unitDivided(by: .minute())
                let maxHeartRate = quantitySamples
                    .map { $0.quantity.doubleValue(for: unit) }
                    .max()

                guard let maxHeartRate else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: maxHeartRate)
            }

            self.healthStore.execute(query)
        }

        maxHR7DayCache[anchorDate] = result
        return result
    }

    func fetchRHR(workoutDate: Date) async -> Double? {
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: workoutDate)
        if let cached = restingHR7DayCache[anchorDate] {
            return cached
        }

        guard let restingHeartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            restingHR7DayCache[anchorDate] = nil
            return nil
        }

        let startDate = calendar.date(byAdding: .day, value: -6, to: anchorDate) ?? anchorDate
        let endDate = calendar.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let result: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHeartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let unit = HKUnit.count().unitDivided(by: .minute())
                let dailyAverages = Dictionary(grouping: quantitySamples) {
                    calendar.startOfDay(for: $0.endDate)
                }
                .compactMap { _, daySamples -> Double? in
                    let values = daySamples.map { $0.quantity.doubleValue(for: unit) }
                    guard !values.isEmpty else { return nil }
                    return values.reduce(0, +) / Double(values.count)
                }

                guard !dailyAverages.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: dailyAverages.reduce(0, +) / Double(dailyAverages.count))
            }

            self.healthStore.execute(query)
        }

        restingHR7DayCache[anchorDate] = result
        return result
    }

    func fetchLTHR(workoutDate: Date, maxHR: Double? = nil) async -> Double? {
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: workoutDate)
        if let cached = lthrDateCache[anchorDate] {
            return cached
        }

        let defaults = UserDefaults.standard
        let manualLTHR = defaults.object(forKey: "manual_lthr_value") as? Double
        let manualEffectiveDate = defaults.object(forKey: "manual_lthr_effective_date") as? Date
        if let manualLTHR, let manualEffectiveDate, manualEffectiveDate <= anchorDate {
            lthrDateCache[anchorDate] = manualLTHR
            return manualLTHR
        }

        let endDate = calendar.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate
        let startDate = calendar.date(byAdding: .day, value: -30, to: anchorDate) ?? anchorDate
        let referenceMaxHR: Double
        if let maxHR {
            referenceMaxHR = maxHR
        } else if let fetchedMaxHR = await fetchMaxHR(workoutDate: workoutDate) {
            referenceMaxHR = fetchedMaxHR
        } else {
            referenceMaxHR = 190
        }
        let intensityThreshold = referenceMaxHR * 0.80

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            fetchWorkouts(from: startDate, to: endDate) { result in
                continuation.resume(returning: result)
            }
        }

        var highIntensityHRValues: [Double] = []
        for workout in workouts {
            let hrSamples = await fetchHeartRateSamples(for: workout)
            let highIntensity = hrSamples
                .map { $0.1 }
                .filter { $0 >= intensityThreshold }
            highIntensityHRValues.append(contentsOf: highIntensity)
        }

        if !highIntensityHRValues.isEmpty {
            let sorted = highIntensityHRValues.sorted()
            let p95Index = Int(Double(sorted.count - 1) * 0.95)
            let inferred = sorted[max(0, min(p95Index, sorted.count - 1))]
            lthrDateCache[anchorDate] = inferred
            return inferred
        }

        let fallback = referenceMaxHR * 0.88
        lthrDateCache[anchorDate] = fallback
        return fallback
    }
}

// MARK: - Heart rate recovery analysis (coach + Heart Zones)

enum HRRRecoveryScenario: String, Codable, Sendable {
    /// Abrupt stop: late peak ≈ HR at end; classic peak − HR@2m applies.
    case staticHRR
    /// Cooled down before end; HRR anchored on HR at workout end.
    case activeRecovery
    /// Session peak far from end-of-work window; sustained intensity — interpret zones, not HRR.
    case falsePeakSustained
    /// Low headroom vs resting or flat post-end HR—equilibrium, not “failed” recovery.
    case steadyStateMaintained
    /// Borderline / noisy signal; use caution.
    case lowConfidence
    case insufficientData
}

/// Heart-rate recovery: static vs end-anchored 2m drop, late-peak–anchored 10s sliding recovery power (v4).
struct HeartRateRecoveryResult: Codable, Equatable, Sendable {
    /// Detected end of the final high-intensity segment, used as the recovery anchor when available.
    var endOfEffortDate: Date?
    /// Latest time at max HR within the final 30s before workout end.
    var effectivePeakDate: Date?
    var recoveryStartDate: Date?
    var recoveryWindowEnd: Date?
    /// Max HR in [end−30s, end] (drop-off peak near stop).
    var windowedPeakBpm: Double
    var sessionPeakBpm: Double
    /// HR at workout end (sample closest to `endDate`).
    var hrAtWorkoutEndBpm: Double?
    var hrAtStopBpm: Double?
    var hrAt60sBpm: Double?
    var hrAt120sBpm: Double?
    /// Signed: anchor − HR @ 60s after **workout end** (positive = HR fell).
    var dropBpm1m: Double?
    /// Signed: anchor − HR @ 120s after **workout end** (positive = HR fell; primary HRR).
    var dropBpm2m: Double?
    /// True → anchor = late peak; false → anchor = HR at end (active cooldown).
    var isStaticRecovery: Bool
    /// Steepest mean drop rate (bpm/s) over ~10s in [latePeak, latePeak+5m]; positive magnitude.
    var recoveryPowerBpmPerSec: Double?
    /// End time of the segment that defined `recoveryPowerBpmPerSec` (second endpoint of the 8–12s window).
    var derivativeSteepestDropDate: Date?
    /// Resting HR supplied to analysis (nil if not passed).
    var restingHRUsed: Double?
    /// `windowedPeakBpm − resting` when resting was provided.
    var headroomBpm: Double?
    /// When true, omit 1m/2m deltas from primary UI (late peak within 30 bpm of resting).
    var excludeTwoMinuteFromPrimaryMetrics: Bool
    /// Merged-series window used for recovery power (late-peak anchor).
    var recoveryPowerWindowStart: Date?
    var recoveryPowerWindowEnd: Date?
    /// First post–workout-end time HR ≤ anchor − 20 bpm (seconds after `end`); capped search window.
    var secondsToDrop20Bpm: Double?
    /// `dropBpm1m / headroomBpm` when headroom ≥ 5 and primary 2m metrics are shown.
    var recoveryIndex60s: Double?
    /// `dropBpm2m / headroomBpm` when headroom is available.
    var recoveryIndex120s: Double?
    /// Exponential-decay recovery constant from the fitted post-stop curve; larger = faster recovery.
    var recoveryRateConstantK: Double?
    var scenario: HRRRecoveryScenario
    var confidence: Double
    var debugNotes: String
}

enum HeartRateRecoveryAnalysis {
    /// Bump invalidates UserDefaults cache entries keyed with prior version.
    static let algorithmVersion = 5

    static func mergedSamples(analytics: WorkoutAnalytics) -> [(Date, Double)] {
        var combined = analytics.heartRates + analytics.postWorkoutHRSeries
        combined.sort { $0.0 < $1.0 }
        var out: [(Date, Double)] = []
        for (d, v) in combined where v > 30 && v < 250 {
            if let last = out.last, abs(last.0.timeIntervalSince(d)) < 0.01 {
                out[out.count - 1] = (d, v)
            } else {
                out.append((d, v))
            }
        }
        return out
    }

    private static func rollingAverageSamples(
        _ samples: [(Date, Double)],
        windowSeconds: TimeInterval
    ) -> [(Date, Double)] {
        guard !samples.isEmpty else { return [] }
        let radius = windowSeconds / 2
        return samples.map { sample in
            let neighbors = samples.filter { abs($0.0.timeIntervalSince(sample.0)) <= radius }
            let avg = neighbors.map(\.1).reduce(0, +) / Double(neighbors.count)
            return (sample.0, avg)
        }
    }

    private static func averageHR(
        near target: Date,
        in samples: [(Date, Double)],
        windowSeconds: TimeInterval
    ) -> Double? {
        let radius = windowSeconds / 2
        let window = samples.filter { abs($0.0.timeIntervalSince(target)) <= radius }
        guard !window.isEmpty else { return nil }
        return window.map(\.1).reduce(0, +) / Double(window.count)
    }

    private static func detectEndOfEffort(
        inWorkout: [(Date, Double)],
        workout: HKWorkout
    ) -> Date? {
        guard let last = inWorkout.last else { return nil }
        let searchStart = max(workout.startDate, workout.endDate.addingTimeInterval(-180))
        let recent = inWorkout.filter { $0.0 >= searchStart && $0.0 <= last.0 }
        guard recent.count >= 3 else { return nil }

        let recentPeak = recent.map(\.1).max() ?? 0
        guard recentPeak > 0 else { return nil }
        let sorted = recent.map(\.1).sorted()
        let percentile80 = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.8))]
        let threshold = max(recentPeak - 6, percentile80)
        let candidates = recent.filter { $0.1 >= threshold }
        guard let candidate = candidates.last?.0 else { return nil }
        return min(candidate, workout.endDate)
    }

    private static func isHeavyMovement(
        around target: Date,
        analytics: WorkoutAnalytics
    ) -> Bool {
        let speedWindow = analytics.speedSeries.filter { abs($0.0.timeIntervalSince(target)) <= 15 }
        let cadenceWindow = analytics.cadenceSeries.filter { abs($0.0.timeIntervalSince(target)) <= 15 }
        let avgSpeed = speedWindow.isEmpty ? nil : speedWindow.map(\.1).reduce(0, +) / Double(speedWindow.count)
        let avgCadence = cadenceWindow.isEmpty ? nil : cadenceWindow.map(\.1).reduce(0, +) / Double(cadenceWindow.count)

        switch analytics.workout.workoutActivityType {
        case .running:
            return (avgSpeed ?? 0) > 2.5 || (avgCadence ?? 0) > 130
        case .walking, .hiking:
            return (avgSpeed ?? 0) > 1.9 || (avgCadence ?? 0) > 120
        case .cycling:
            return (avgSpeed ?? 0) > 6.0 || (avgCadence ?? 0) > 65
        default:
            return (avgSpeed ?? 0) > 2.2 || (avgCadence ?? 0) > 125
        }
    }

    private static func fitRecoveryRateConstant(
        anchorHR: Double,
        anchorDate: Date,
        asymptoteHR: Double,
        samples: [(Date, Double)]
    ) -> Double? {
        let eligible = samples.compactMap { sample -> (Double, Double)? in
            let dt = sample.0.timeIntervalSince(anchorDate)
            guard dt >= 0, dt <= 300 else { return nil }
            let excess = sample.1 - asymptoteHR
            guard excess > 1, anchorHR > asymptoteHR + 1 else { return nil }
            let normalized = excess / (anchorHR - asymptoteHR)
            guard normalized > 0, normalized < 1 else { return nil }
            return (dt, log(normalized))
        }
        guard eligible.count >= 3 else { return nil }

        let n = Double(eligible.count)
        let sumX = eligible.map(\.0).reduce(0, +)
        let sumY = eligible.map(\.1).reduce(0, +)
        let sumXY = eligible.reduce(0) { $0 + ($1.0 * $1.1) }
        let sumXX = eligible.reduce(0) { $0 + ($1.0 * $1.0) }
        let denom = (n * sumXX) - (sumX * sumX)
        guard abs(denom) > 0.0001 else { return nil }
        let slope = ((n * sumXY) - (sumX * sumY)) / denom
        guard slope < 0 else { return nil }
        return -slope
    }

    /// Steepest mean downward slope (positive bpm/s) using pairs with Δt in [8, 12]s inside `[windowStart, windowEnd]`.
    private static func recoveryPowerSliding10s(
        samples: [(Date, Double)],
        windowStart: Date,
        windowEnd: Date
    ) -> (bpmPerSec: Double, segmentEnd: Date)? {
        let win = samples.filter { $0.0 >= windowStart && $0.0 <= windowEnd }
        guard win.count >= 2 else { return nil }
        var bestDropRate = 0.0
        var bestEnd: Date?
        for i in win.indices {
            for j in win.indices where j > i {
                let (t1, h1) = win[i]
                let (t2, h2) = win[j]
                let dt = t2.timeIntervalSince(t1)
                guard dt >= 8, dt <= 12 else { continue }
                let slope = (h2 - h1) / dt
                guard slope < 0 else { continue }
                let dropRate = -slope
                if dropRate > bestDropRate {
                    bestDropRate = dropRate
                    bestEnd = t2
                }
            }
        }
        guard bestDropRate > 0, let bestEnd else { return nil }
        return (bestDropRate, bestEnd)
    }

    static func analyze(workout: HKWorkout, analytics: WorkoutAnalytics, restingHRBpm: Double? = nil) -> HeartRateRecoveryResult {
        let start = workout.startDate
        let end = workout.endDate
        let samples = mergedSamples(analytics: analytics)
        // Strictly at or before official end — never treat post-workout HR as “in workout” (avoids peak dot after end).
        let inWorkout = samples.filter { $0.0 >= start && $0.0 <= end }
        // Prefer strictly post-end; fall back to ≥ end if HK only tags samples on the boundary.
        let postStrict = samples.filter { $0.0 > end }
        let postAfterEnd = postStrict.isEmpty ? samples.filter { $0.0 >= end } : postStrict

        guard inWorkout.count >= 3 else {
            return HeartRateRecoveryResult(
                endOfEffortDate: nil,
                effectivePeakDate: nil,
                recoveryStartDate: nil,
                recoveryWindowEnd: nil,
                windowedPeakBpm: 0,
                sessionPeakBpm: 0,
                hrAtWorkoutEndBpm: nil,
                hrAtStopBpm: nil,
                hrAt60sBpm: nil,
                hrAt120sBpm: nil,
                dropBpm1m: nil,
                dropBpm2m: nil,
                isStaticRecovery: true,
                recoveryPowerBpmPerSec: nil,
                derivativeSteepestDropDate: nil,
                restingHRUsed: restingHRBpm,
                headroomBpm: nil,
                excludeTwoMinuteFromPrimaryMetrics: false,
                recoveryPowerWindowStart: nil,
                recoveryPowerWindowEnd: nil,
                secondsToDrop20Bpm: nil,
                recoveryIndex60s: nil,
                recoveryIndex120s: nil,
                recoveryRateConstantK: nil,
                scenario: .insufficientData,
                confidence: 0,
                debugNotes: "Too few in-workout HR samples."
            )
        }

        let smoothedInWorkout = rollingAverageSamples(inWorkout, windowSeconds: 10)
        let smoothedMerged = rollingAverageSamples(samples, windowSeconds: 10)
        let endOfEffort = detectEndOfEffort(inWorkout: smoothedInWorkout, workout: workout) ?? end

        let sessionPeak = smoothedInWorkout.map(\.1).max() ?? 0
        let sessionPeakTime = smoothedInWorkout.max(by: { $0.1 < $1.1 })?.0

        let peakWindowStart = max(start, endOfEffort.addingTimeInterval(-60))
        let peakWindow = smoothedInWorkout.filter { $0.0 >= peakWindowStart && $0.0 <= endOfEffort }
        let recentPeakBpm: Double
        let recentPeakTimeRaw: Date?
        if peakWindow.isEmpty {
            recentPeakBpm = smoothedInWorkout.map(\.1).max() ?? 0
            recentPeakTimeRaw = smoothedInWorkout.max(by: { $0.1 < $1.1 })?.0
        } else {
            let m = peakWindow.map(\.1).max() ?? 0
            recentPeakBpm = m
            let atMax = peakWindow.filter { abs($0.1 - m) < 0.51 }
            recentPeakTimeRaw = atMax.map(\.0).max()
        }
        let recentPeakTime = recentPeakTimeRaw.map { min($0, endOfEffort) }

        let hrAtEnd = averageHR(near: end, in: smoothedMerged, windowSeconds: 10)
            ?? sampleClosest(to: end, in: smoothedInWorkout)?.1
            ?? smoothedInWorkout.last?.1
            ?? recentPeakBpm
        let hrAtStop = averageHR(near: endOfEffort, in: smoothedMerged, windowSeconds: 10)
            ?? sampleClosest(to: endOfEffort, in: smoothedInWorkout)?.1
            ?? recentPeakBpm

        let peakMinusEnd = recentPeakBpm - hrAtStop
        let absTol = max(6.0, recentPeakBpm * 0.04)
        let activeTol = max(10.0, recentPeakBpm * 0.07)
        let isStatic = peakMinusEnd <= absTol
        let isActiveCooldown = peakMinusEnd >= activeTol

        let anchorHR: Double
        let isStaticRecovery: Bool
        if isStatic {
            anchorHR = recentPeakBpm
            isStaticRecovery = true
        } else if isActiveCooldown {
            anchorHR = hrAtStop
            isStaticRecovery = false
        } else {
            anchorHR = peakMinusEnd > absTol * 0.65 ? hrAtStop : recentPeakBpm
            isStaticRecovery = peakMinusEnd <= absTol * 1.25
        }

        let t1m = endOfEffort.addingTimeInterval(60)
        let t2m = endOfEffort.addingTimeInterval(120)
        let hr60 = isHeavyMovement(around: t1m, analytics: analytics)
            ? nil
            : averageHR(near: t1m, in: smoothedMerged, windowSeconds: 10)
        let hr120 = isHeavyMovement(around: t2m, analytics: analytics)
            ? nil
            : averageHR(near: t2m, in: smoothedMerged, windowSeconds: 10)
        let drop1Raw = hr60.map { anchorHR - $0 }
        let drop2Raw = hr120.map { anchorHR - $0 }

        let headroom: Double? = restingHRBpm.map { recentPeakBpm - $0 }
        let exclude2m = headroom.map { $0 < 30 } ?? false
        let drop1 = exclude2m ? nil : drop1Raw
        let drop2 = exclude2m ? nil : drop2Raw
        let recoveryIndex120: Double? = {
            guard let h = headroom, h >= 5, let d2 = drop2Raw else { return nil }
            return d2 / h
        }()

        let t0Power = recentPeakTime ?? endOfEffort
        let powerWindowStart = max(start, t0Power)
        let powerWindowEnd = t0Power.addingTimeInterval(300)
        let powerPair = recoveryPowerSliding10s(samples: smoothedMerged, windowStart: powerWindowStart, windowEnd: powerWindowEnd)
        let recoveryPower = powerPair?.bpmPerSec
        let derivativeEnd = powerPair?.segmentEnd

        let searchUntil = endOfEffort.addingTimeInterval(600)
        let secondsToDrop20: Double? = {
            let threshold = anchorHR - 20
            let post = smoothedMerged.filter { $0.0 > endOfEffort && $0.0 <= searchUntil }.sorted { $0.0 < $1.0 }
            for (t, hr) in post where hr <= threshold {
                return t.timeIntervalSince(endOfEffort)
            }
            return nil
        }()

        let recoveryIndex: Double? = {
            guard !exclude2m, let h = headroom, h >= 5, let d1 = drop1Raw else { return nil }
            return d1 / h
        }()

        let asymptoteHR = restingHRBpm ?? smoothedMerged
            .filter { $0.0 >= endOfEffort.addingTimeInterval(120) && $0.0 <= endOfEffort.addingTimeInterval(300) }
            .map(\.1)
            .min()
            ?? min(hr120 ?? anchorHR, anchorHR)
        let recoveryK = fitRecoveryRateConstant(
            anchorHR: anchorHR,
            anchorDate: endOfEffort,
            asymptoteHR: asymptoteHR,
            samples: smoothedMerged
        )

        // UI band: workout end → ~2.5 min after (1m/2m sample semantics).
        let recoveryStart = endOfEffort
        let recoveryWindowEnd = endOfEffort.addingTimeInterval(150)

        var scenario: HRRRecoveryScenario = .lowConfidence
        var confidence = 0.5
        var notes = String(format: "%@ HRR anchor %.0f bpm (%@). End of effort %@. Smoothed peak in final 60s before stop %.0f bpm; HR @ stop %.0f bpm; HR @ workout end %.0f bpm.",
                           isStaticRecovery ? "Static" : "Active",
                           anchorHR,
                           isStaticRecovery ? "peak−HR@2m post-stop" : "stop-HR−HR@2m post-stop",
                           endOfEffort.formatted(date: .omitted, time: .standard),
                           recentPeakBpm,
                           hrAtStop,
                           hrAtEnd)
        if let rhr = restingHRBpm {
            notes += String(format: " Resting HR (for headroom): %.0f bpm; headroom %.0f bpm.", rhr, recentPeakBpm - rhr)
        }
        if hr60 == nil || hr120 == nil {
            notes += " One or more recovery checkpoints were dropped because the athlete still appeared to be moving heavily or the HR window was too sparse."
        }
        if exclude2m {
            notes += " Primary 1m/2m HRR deltas omitted (late peak within 30 bpm of resting—noisy)."
        }
        if let rp = recoveryPower {
            notes += String(format: " Recovery power (10s max slope in 5m after late peak): %.2f bpm/s.", rp)
        }
        if let tt = secondsToDrop20 {
            notes += String(format: " Time to drop 20 bpm post-end: %.0f s.", tt)
        }
        if let ri = recoveryIndex {
            notes += String(format: " Recovery index (60s drop / headroom): %.0f%%.", ri * 100)
        }
        if let ri120 = recoveryIndex120 {
            notes += String(format: " Normalized 2m HRR: %.0f%% of headroom.", ri120 * 100)
        }
        if let k = recoveryK {
            notes += String(format: " Decay-fit k: %.4f s^-1.", k)
        }
        if let d2r = drop2Raw {
            notes += String(format: " Signed 2m drop (internal): %.0f (positive = HR fell).", d2r)
        }

        let falsePeak = sessionPeakTime.map { st in
            st < end.addingTimeInterval(-90) && recentPeakBpm < sessionPeak - 12 && sessionPeak > 80
        } ?? false

        let d2ForRules = drop2Raw
        let staticThreshold: Double = (headroom.map { $0 >= 30 } ?? false) ? 7 : 8

        if falsePeak && (d2ForRules ?? 0) < 6 {
            scenario = .falsePeakSustained
            confidence = 0.28
            notes += " Session peak far from end window—HRR may misrepresent effort."
        } else if exclude2m {
            scenario = .steadyStateMaintained
            confidence = 0.5
        } else if let h = headroom, h < 50, let d2r = d2ForRules, abs(d2r) <= 4 {
            scenario = .steadyStateMaintained
            confidence = 0.48
        } else if isStaticRecovery, let d2r = d2ForRules, d2r >= staticThreshold {
            scenario = .staticHRR
            confidence = min(0.92, 0.55 + d2r / 80.0)
        } else if !isStaticRecovery, let d2r = d2ForRules, d2r >= 5 {
            scenario = .activeRecovery
            confidence = 0.52 + min(0.25, d2r / 100.0)
        } else if let d2r = d2ForRules, d2r < 0 {
            let lowHead = headroom.map { $0 < 50 } ?? false
            if lowHead {
                scenario = .steadyStateMaintained
                confidence = 0.46
                notes += " Near-flat 2m change with limited headroom vs resting—treat as steady state, not pathology."
            } else {
                scenario = .lowConfidence
                confidence = 0.35
                notes += " HR rose after end—no clear recovery drop."
            }
        } else {
            scenario = .lowConfidence
            confidence = 0.4
        }

        return HeartRateRecoveryResult(
            endOfEffortDate: endOfEffort,
            effectivePeakDate: recentPeakTime,
            recoveryStartDate: recoveryStart,
            recoveryWindowEnd: recoveryWindowEnd,
            windowedPeakBpm: recentPeakBpm,
            sessionPeakBpm: sessionPeak,
            hrAtWorkoutEndBpm: hrAtEnd,
            hrAtStopBpm: hrAtStop,
            hrAt60sBpm: hr60,
            hrAt120sBpm: hr120,
            dropBpm1m: drop1,
            dropBpm2m: drop2,
            isStaticRecovery: isStaticRecovery,
            recoveryPowerBpmPerSec: recoveryPower,
            derivativeSteepestDropDate: derivativeEnd,
            restingHRUsed: restingHRBpm,
            headroomBpm: headroom,
            excludeTwoMinuteFromPrimaryMetrics: exclude2m,
            recoveryPowerWindowStart: powerWindowStart,
            recoveryPowerWindowEnd: powerWindowEnd,
            secondsToDrop20Bpm: secondsToDrop20,
            recoveryIndex60s: recoveryIndex,
            recoveryIndex120s: recoveryIndex120,
            recoveryRateConstantK: recoveryK,
            scenario: scenario,
            confidence: confidence,
            debugNotes: notes
        )
    }

    private static func sampleClosest(to target: Date, in series: [(Date, Double)]) -> (Date, Double)? {
        guard !series.isEmpty else { return nil }
        return series.min(by: { abs($0.0.timeIntervalSince(target)) < abs($1.0.timeIntervalSince(target)) })
    }

    /// Prefer signed **2m** drop when it indicates real recovery (positive); omit false-peak garbage and headroom-gated rows.
    static func coachPreferredDropBpm(result: HeartRateRecoveryResult) -> Double? {
        guard result.scenario != .insufficientData else { return nil }
        guard result.scenario != .falsePeakSustained else { return nil }
        guard result.scenario != .steadyStateMaintained else { return nil }
        guard !result.excludeTwoMinuteFromPrimaryMetrics else { return nil }
        guard let d2 = result.dropBpm2m, d2 > 0, d2 < 100 else { return nil }
        guard result.confidence >= 0.35 else { return nil }
        return d2
    }

    /// Daily chart/trend-safe HRR value. Keeps the graph on refined 2m drop values only.
    static func trendPreferredDropBpm(result: HeartRateRecoveryResult) -> Double? {
        if let preferred = coachPreferredDropBpm(result: result) {
            return preferred
        }
        guard result.scenario != .insufficientData else { return nil }
        guard result.scenario != .falsePeakSustained else { return nil }
        guard result.scenario != .steadyStateMaintained else { return nil }
        guard !result.excludeTwoMinuteFromPrimaryMetrics else { return nil }
        guard let d2 = result.dropBpm2m, d2 > 0, d2 < 100 else { return nil }
        return d2
    }

    /// When 2m delta is omitted, coarse scalar for trends (not a literal bpm drop).
    static func coachComparableRecoveryScore(result: HeartRateRecoveryResult) -> Double? {
        if let d = coachPreferredDropBpm(result: result) { return d }
        guard result.scenario != .insufficientData, result.scenario != .falsePeakSustained else { return nil }
        if let p = result.recoveryPowerBpmPerSec, p > 0 {
            return min(95, p * 45)
        }
        return nil
    }
}

/// Latest resting HR for HRR headroom (coach + Heart Zones agree on the same value).
final class CoachHRRRestingGate: @unchecked Sendable {
    static let shared = CoachHRRRestingGate()
    private let lock = NSLock()
    private var resting = 60.0
    func update(_ value: Double) {
        lock.lock()
        resting = value
        lock.unlock()
    }
    func current() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return resting
    }
}

final class HRRAnalysisCache: @unchecked Sendable {
    static let shared = HRRAnalysisCache()
    private let defaults = UserDefaults.standard
    private let prefix = "nutrivance.hrr.v\(HeartRateRecoveryAnalysis.algorithmVersion)."
    private var memory: [UUID: HeartRateRecoveryResult] = [:]
    private let lock = NSLock()

    func result(for workoutUUID: UUID) -> HeartRateRecoveryResult? {
        lock.lock()
        if let m = memory[workoutUUID] {
            lock.unlock()
            return m
        }
        lock.unlock()
        guard let data = defaults.data(forKey: prefix + workoutUUID.uuidString),
              let decoded = try? JSONDecoder().decode(HeartRateRecoveryResult.self, from: data) else {
            return nil
        }
        lock.lock()
        memory[workoutUUID] = decoded
        lock.unlock()
        return decoded
    }

    func store(_ result: HeartRateRecoveryResult, workoutUUID: UUID) {
        lock.lock()
        memory[workoutUUID] = result
        lock.unlock()
        if let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: prefix + workoutUUID.uuidString)
        }
    }
}
