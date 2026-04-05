import Foundation
import HealthKit
import Combine
import SwiftUI

/// Central physiology engine for Nutrivance.
/// All health calculations should live here, not in Views.
@MainActor
final class HealthStateEngine: ObservableObject {
    private let longTermLookbackDays = 3650
    private let interactiveWorkoutLookbackDays = 120
    var interactiveWorkoutLookbackDaysForUI: Int { interactiveWorkoutLookbackDays }
    // Shared singleton instance - persists for entire app session
    static let shared = HealthStateEngine()
    
    // Use a shared HealthKitManager instance
    private let hkManager = HealthKitManager()
    private let metricsSnapshotFileName = "healthMetricsSnapshot.json"
    private let metricsSnapshotCloudKey = "health_metrics_snapshot_v1"
    /// Max samples/segments uploaded per handoff blob (keeps CloudKit assets reasonable).
    private let cloudHandoffMaxHRVSamples = 100_000
    private let cloudHandoffMaxSleepSegments = 28_000
    private var lastAppliedHRVSamplesHandoffAt: Date = .distantPast
    private var lastAppliedSleepTimelineHandoffAt: Date = .distantPast
    private var lastAppliedSleepUIMetricsHandoffAt: Date = .distantPast

    struct PersistedDateValue: Codable {
        let date: Date
        let value: Double
    }

    struct PersistedDailyHRVPoint: Codable {
        let date: Date
        let average: Double
        let min: Double
        let max: Double
    }

    struct PersistedHRVSamplePoint: Codable {
        let date: Date
        let value: Double
    }

    struct PersistedRollingBaselineStats: Codable {
        let mean: Double
        let standardDeviation: Double
        let sampleCount: Int
    }

    struct PersistedSleepStageDay: Codable {
        let date: Date
        let stages: [String: Double]
    }

    struct PersistedHeartRateZoneDay: Codable {
        let date: Date
        let zones: [String: Double]
    }

    struct PersistedStringDoubleValue: Codable {
        let key: String
        let value: Double
    }

    struct PersistedReadinessResult: Codable {
        let score: Int
        let confidence: Double
        let primaryDriver: String
    }

    struct PersistedWorkoutSeriesPoint: Codable {
        let date: Date
        let value: Double
    }

    struct PersistedWorkoutZoneBreakdown: Codable {
        let zone: HeartRateZone
        let timeInZone: TimeInterval
    }

    struct PersistedWorkoutAnalyticsEntry: Codable {
        let schemaVersion: Int
        let workoutUUID: String
        let workoutStartDate: Date
        let workoutEndDate: Date
        let workoutDuration: Double
        let workoutTypeRawValue: UInt
        let totalEnergyBurnedKilocalories: Double?
        let totalDistanceMeters: Double?
        let metadata: [String: Double]
        let heartRates: [PersistedWorkoutSeriesPoint]
        let vo2Max: Double?
        let metTotal: Double?
        let metAverage: Double?
        let metSeries: [PersistedWorkoutSeriesPoint]
        let postWorkoutHRSeries: [PersistedWorkoutSeriesPoint]
        let peakHR: Double?
        let hrr0: Double?
        let hrr1: Double?
        let hrr2: Double?
        let powerSeries: [PersistedWorkoutSeriesPoint]
        let speedSeries: [PersistedWorkoutSeriesPoint]
        let cadenceSeries: [PersistedWorkoutSeriesPoint]
        let elevationSeries: [PersistedWorkoutSeriesPoint]
        let elevationGain: Double?
        let verticalOscillationSeries: [PersistedWorkoutSeriesPoint]
        let groundContactTimeSeries: [PersistedWorkoutSeriesPoint]
        let strideLengthSeries: [PersistedWorkoutSeriesPoint]
        let strokeCountSeries: [PersistedWorkoutSeriesPoint]
        let verticalOscillation: Double?
        let groundContactTime: Double?
        let strideLength: Double?
        let hrZoneProfile: HRZoneProfile?
        let hrZoneBreakdown: [PersistedWorkoutZoneBreakdown]

        init(
            schemaVersion: Int,
            workoutUUID: String,
            workoutStartDate: Date,
            workoutEndDate: Date,
            workoutDuration: Double,
            workoutTypeRawValue: UInt,
            totalEnergyBurnedKilocalories: Double?,
            totalDistanceMeters: Double?,
            metadata: [String : Double],
            heartRates: [PersistedWorkoutSeriesPoint],
            vo2Max: Double?,
            metTotal: Double?,
            metAverage: Double?,
            metSeries: [PersistedWorkoutSeriesPoint],
            postWorkoutHRSeries: [PersistedWorkoutSeriesPoint],
            peakHR: Double?,
            hrr0: Double?,
            hrr1: Double?,
            hrr2: Double?,
            powerSeries: [PersistedWorkoutSeriesPoint],
            speedSeries: [PersistedWorkoutSeriesPoint],
            cadenceSeries: [PersistedWorkoutSeriesPoint],
            elevationSeries: [PersistedWorkoutSeriesPoint],
            elevationGain: Double?,
            verticalOscillationSeries: [PersistedWorkoutSeriesPoint],
            groundContactTimeSeries: [PersistedWorkoutSeriesPoint],
            strideLengthSeries: [PersistedWorkoutSeriesPoint],
            strokeCountSeries: [PersistedWorkoutSeriesPoint],
            verticalOscillation: Double?,
            groundContactTime: Double?,
            strideLength: Double?,
            hrZoneProfile: HRZoneProfile?,
            hrZoneBreakdown: [PersistedWorkoutZoneBreakdown]
        ) {
            self.schemaVersion = schemaVersion
            self.workoutUUID = workoutUUID
            self.workoutStartDate = workoutStartDate
            self.workoutEndDate = workoutEndDate
            self.workoutDuration = workoutDuration
            self.workoutTypeRawValue = workoutTypeRawValue
            self.totalEnergyBurnedKilocalories = totalEnergyBurnedKilocalories
            self.totalDistanceMeters = totalDistanceMeters
            self.metadata = metadata
            self.heartRates = heartRates
            self.vo2Max = vo2Max
            self.metTotal = metTotal
            self.metAverage = metAverage
            self.metSeries = metSeries
            self.postWorkoutHRSeries = postWorkoutHRSeries
            self.peakHR = peakHR
            self.hrr0 = hrr0
            self.hrr1 = hrr1
            self.hrr2 = hrr2
            self.powerSeries = powerSeries
            self.speedSeries = speedSeries
            self.cadenceSeries = cadenceSeries
            self.elevationSeries = elevationSeries
            self.elevationGain = elevationGain
            self.verticalOscillationSeries = verticalOscillationSeries
            self.groundContactTimeSeries = groundContactTimeSeries
            self.strideLengthSeries = strideLengthSeries
            self.strokeCountSeries = strokeCountSeries
            self.verticalOscillation = verticalOscillation
            self.groundContactTime = groundContactTime
            self.strideLength = strideLength
            self.hrZoneProfile = hrZoneProfile
            self.hrZoneBreakdown = hrZoneBreakdown
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            workoutUUID = try container.decode(String.self, forKey: .workoutUUID)
            workoutStartDate = try container.decode(Date.self, forKey: .workoutStartDate)
            workoutEndDate = try container.decode(Date.self, forKey: .workoutEndDate)
            workoutDuration = try container.decode(Double.self, forKey: .workoutDuration)
            workoutTypeRawValue = try container.decode(UInt.self, forKey: .workoutTypeRawValue)
            totalEnergyBurnedKilocalories = try container.decodeIfPresent(Double.self, forKey: .totalEnergyBurnedKilocalories)
            totalDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .totalDistanceMeters)
            metadata = try container.decode([String: Double].self, forKey: .metadata)
            heartRates = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .heartRates)
            vo2Max = try container.decodeIfPresent(Double.self, forKey: .vo2Max)
            metTotal = try container.decodeIfPresent(Double.self, forKey: .metTotal)
            metAverage = try container.decodeIfPresent(Double.self, forKey: .metAverage)
            metSeries = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .metSeries)
            postWorkoutHRSeries = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .postWorkoutHRSeries)
            peakHR = try container.decodeIfPresent(Double.self, forKey: .peakHR)
            hrr0 = try container.decodeIfPresent(Double.self, forKey: .hrr0)
            hrr1 = try container.decodeIfPresent(Double.self, forKey: .hrr1)
            hrr2 = try container.decodeIfPresent(Double.self, forKey: .hrr2)
            powerSeries = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .powerSeries)
            speedSeries = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .speedSeries)
            cadenceSeries = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .cadenceSeries)
            elevationSeries = try container.decode([PersistedWorkoutSeriesPoint].self, forKey: .elevationSeries)
            elevationGain = try container.decodeIfPresent(Double.self, forKey: .elevationGain)
            verticalOscillationSeries = try container.decodeIfPresent([PersistedWorkoutSeriesPoint].self, forKey: .verticalOscillationSeries) ?? []
            groundContactTimeSeries = try container.decodeIfPresent([PersistedWorkoutSeriesPoint].self, forKey: .groundContactTimeSeries) ?? []
            strideLengthSeries = try container.decodeIfPresent([PersistedWorkoutSeriesPoint].self, forKey: .strideLengthSeries) ?? []
            strokeCountSeries = try container.decodeIfPresent([PersistedWorkoutSeriesPoint].self, forKey: .strokeCountSeries) ?? []
            verticalOscillation = try container.decodeIfPresent(Double.self, forKey: .verticalOscillation)
            groundContactTime = try container.decodeIfPresent(Double.self, forKey: .groundContactTime)
            strideLength = try container.decodeIfPresent(Double.self, forKey: .strideLength)
            hrZoneProfile = try container.decodeIfPresent(HRZoneProfile.self, forKey: .hrZoneProfile)
            hrZoneBreakdown = try container.decodeIfPresent([PersistedWorkoutZoneBreakdown].self, forKey: .hrZoneBreakdown) ?? []
        }
    }

    private static let cachedWorkoutUUIDMetadataKey = "NutrivanceCachedWorkoutUUID"
    private static let workoutAnalyticsSchemaVersion = 3

    struct MetricsSnapshot: Codable {
        let updatedAt: Date
        let latestHRV: Double?
        let restingHeartRate: Double?
        let dailyRestingHeartRate: [PersistedDateValue]
        let dailySleepDuration: [PersistedDateValue]
        let sleepHours: Double?
        let activityLoad: Double
        let hrvHistory: [Double]
        let hrvSampleHistory: [PersistedHRVSamplePoint]
        let dailyHRV: [PersistedDailyHRVPoint]
        let sleepHRVAverage: Double?
        let lastSleepStart: Date?
        let lastSleepEnd: Date?
        let hrvBaseline7Day: Double?
        let rhrBaseline7Day: Double?
        let sleepBaseline7Day: Double?
        let hrvBaseline28Day: Double?
        let rhrBaseline28Day: Double?
        let hrvBaseline60Day: PersistedRollingBaselineStats?
        let rhrBaseline60Day: PersistedRollingBaselineStats?
        let sleepBaseline60Day: PersistedRollingBaselineStats?
        let estimatedMaxHeartRate: Double
        let userAge: Double?
        let acuteTrainingLoad: Double
        let chronicTrainingLoad: Double
        let trainingLoadRatio: Double
        let functionalOverreachingFlag: Bool
        let recoveryBaseline7Day: Double?
        let strainBaseline7Day: Double?
        let circadianBaseline7Day: Double?
        let autonomicBaseline7Day: Double?
        let moodBaseline7Day: Double?
        let sleepStages: [PersistedSleepStageDay]
        let sleepEfficiency: [PersistedDateValue]
        let sleepConsistency: Double?
        let sleepStartHours: [PersistedDateValue]
        let sleepMidpointHours: [PersistedDateValue]
        let dailySleepHeartRate: [PersistedDateValue]
        let nightlyAnchoredHRV: [PersistedDateValue]
        let effectHRV: [PersistedDateValue]
        let basalSleepingHeartRate: [PersistedDateValue]
        let anchoredSleepDuration: [PersistedDateValue]
        let anchoredTimeInBed: [PersistedDateValue]
        let readinessHRV: Double?
        let readinessEffectHRV: Double?
        let readinessBasalHeartRate: Double?
        let readinessSleepDuration: Double?
        let readinessTimeInBed: Double?
        let readinessSleepEfficiency: Double?
        let readinessSleepRatio: Double?
        let workoutHRVDecay: [PersistedDateValue]
        let recoverySuppressedFlag: Bool
        let respiratoryRate: [PersistedDateValue]
        let wristTemperature: [PersistedDateValue]
        let spO2: [PersistedDateValue]
        let postWorkoutHR: [PersistedDateValue]
        let vo2Max: [PersistedDateValue]
        let heartRateZones: [PersistedHeartRateZoneDay]
        let kcalBurned: [PersistedDateValue]
        let effortRating: [PersistedDateValue]
        let favoriteSport: String?
        let trainingFrequency: Double?
        let trainingFrequencyBySport: [PersistedStringDoubleValue]
        let recoveryScore: Double
        let strainScore: Double
        let readinessScore: Double
        let hrvTrendScore: Double
        let circadianHRVScore: Double
        let sleepHRVScore: Double
        let allostaticStressScore: Double
        let autonomicBalanceScore: Double
        let feelGoodScore: Double
        let feelGoodReadiness: PersistedReadinessResult
    }

    // MARK: - Workout/HR Data Cache
    private var allWorkoutHRCache: [(workout: HKWorkout, heartRates: [(Date, Double)])] = []
    // Persistent cache for analytics
    private var analyticsCache: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []
    // Published staged analytics
    @Published var stagedWorkoutAnalytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)] = []

    // MARK: - Vitals & Advanced Metrics
    @Published var sleepStages: [Date: [String: Double]] = [:] // [date: [stage: hours]]
    /// HealthKit sleep-analysis segments for cross-device graphs (CloudKit `sleepTimelineDetailed` handoff).
    @Published var sleepTimelineSegments: [EngineSleepTimelineSegment] = []
    /// iOS-built sleep cards (segments w/ HR/RR, dip, bedtime, overnight vitals) for Mac Catalyst.
    @Published private(set) var sleepUIMetricsHandoff: EngineSleepUIMetricsBlob = EngineSleepUIMetricsBlob(
        updatedAt: .distantPast,
        nights: [],
        bedtimeNights: []
    )
    @Published var sleepEfficiency: [Date: Double] = [:] // [date: efficiency 0-1]
    @Published var sleepConsistency: Double? // stddev of sleep start times (hours)
    @Published var sleepStartHours: [Date: Double] = [:] // [date: bedtime hour]
    @Published var sleepMidpointHours: [Date: Double] = [:] // [date: midpoint hour, wrapped across midnight]
    @Published var dailySleepHeartRate: [Date: Double] = [:] // [date: avg sleep HR bpm]
    @Published var nightlyAnchoredHRV: [Date: Double] = [:] // [date: special "Effect HRV" for recovery from last 3h of main sleep block]
    @Published var effectHRV: [Date: Double] = [:] // [date: recovery-specific sleep-anchored HRV shown separately from raw HRV]
    @Published var basalSleepingHeartRate: [Date: Double] = [:] // [date: 5th percentile HR during main sleep block]
    @Published var anchoredSleepDuration: [Date: Double] = [:] // [date: hours asleep in main sleep block]
    @Published var anchoredTimeInBed: [Date: Double] = [:] // [date: hours in bed overlapping main sleep block]
    @Published var readinessHRV: Double?
    @Published var readinessEffectHRV: Double?
    @Published var readinessBasalHeartRate: Double?
    @Published var readinessSleepDuration: Double?
    @Published var readinessTimeInBed: Double?
    @Published var readinessSleepEfficiency: Double?
    @Published var readinessSleepRatio: Double?
    @Published var workoutHRVDecay: [Date: Double] = [:] // [date: effect HRV minus mean workout HRV]
    @Published var recoverySuppressedFlag: Bool = false
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
    @Published var mindfulnessMinutesByDay: [Date: Double] = [:] // [date: minutes of mindfulness]

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
    private var earliestRequestedWorkoutDate: Date? = nil
    private var diskCacheLoaded: Bool = false
    private var metricsSnapshotSaveTask: Task<Void, Never>?
    private var metricsSnapshotWriteTask: Task<Void, Never>?
    private var metricsRefreshCompletionTask: Task<Void, Never>?
    private var foregroundResumeTask: Task<Void, Never>?
    private var startupWorkoutCoverageTask: Task<Void, Never>?
    private var cloudSnapshotObserver: NSObjectProtocol?
    private var workoutCloudUploadTask: Task<Void, Never>?
    @Published private(set) var hasHydratedCachedMetrics: Bool = false
    @Published private(set) var cachedMetricsUpdatedAt: Date?
    @Published private(set) var isRefreshingCachedMetrics: Bool = false
    @Published private(set) var requiresInitialFullSync: Bool = false
    @Published private(set) var isSyncingStartupWorkoutCoverage: Bool = false
    private var isAppActive = true

    // MARK: - Persistent Cache Management
    private func cacheDirectoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    private func persistentCacheURL() -> URL? {
        guard let dir = cacheDirectoryURL() else { return nil }
        return dir.appendingPathComponent(cacheFileName)
    }

    private func metricsSnapshotURL() -> URL? {
        guard let dir = cacheDirectoryURL() else { return nil }
        return dir.appendingPathComponent(metricsSnapshotFileName)
    }

    private func sortedDateValues(from values: [Date: Double], limit: Int? = nil) -> [PersistedDateValue] {
        let sorted = values
            .map { PersistedDateValue(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
        if let limit, sorted.count > limit {
            return Array(sorted.suffix(limit))
        }
        return sorted
    }

    private func dateValueDictionary(from values: [PersistedDateValue]) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.date, $0.value) })
    }

    private func currentMetricsSnapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            updatedAt: Date(),
            latestHRV: latestHRV,
            restingHeartRate: restingHeartRate,
            dailyRestingHeartRate: sortedDateValues(from: dailyRestingHeartRate),
            dailySleepDuration: sortedDateValues(from: dailySleepDuration),
            sleepHours: sleepHours,
            activityLoad: activityLoad,
            hrvHistory: hrvHistory,
            hrvSampleHistory: hrvSampleHistory.map { PersistedHRVSamplePoint(date: $0.date, value: $0.value) },
            dailyHRV: dailyHRV.map { PersistedDailyHRVPoint(date: $0.date, average: $0.average, min: $0.min, max: $0.max) },
            sleepHRVAverage: sleepHRVAverage,
            lastSleepStart: lastSleepStart,
            lastSleepEnd: lastSleepEnd,
            hrvBaseline7Day: hrvBaseline7Day,
            rhrBaseline7Day: rhrBaseline7Day,
            sleepBaseline7Day: sleepBaseline7Day,
            hrvBaseline28Day: hrvBaseline28Day,
            rhrBaseline28Day: rhrBaseline28Day,
            hrvBaseline60Day: hrvBaseline60Day.map { PersistedRollingBaselineStats(mean: $0.mean, standardDeviation: $0.standardDeviation, sampleCount: $0.sampleCount) },
            rhrBaseline60Day: rhrBaseline60Day.map { PersistedRollingBaselineStats(mean: $0.mean, standardDeviation: $0.standardDeviation, sampleCount: $0.sampleCount) },
            sleepBaseline60Day: sleepBaseline60Day.map { PersistedRollingBaselineStats(mean: $0.mean, standardDeviation: $0.standardDeviation, sampleCount: $0.sampleCount) },
            estimatedMaxHeartRate: estimatedMaxHeartRate,
            userAge: userAge,
            acuteTrainingLoad: acuteTrainingLoad,
            chronicTrainingLoad: chronicTrainingLoad,
            trainingLoadRatio: trainingLoadRatio,
            functionalOverreachingFlag: functionalOverreachingFlag,
            recoveryBaseline7Day: recoveryBaseline7Day,
            strainBaseline7Day: strainBaseline7Day,
            circadianBaseline7Day: circadianBaseline7Day,
            autonomicBaseline7Day: autonomicBaseline7Day,
            moodBaseline7Day: moodBaseline7Day,
            sleepStages: sleepStages
                .map { PersistedSleepStageDay(date: $0.key, stages: $0.value) }
                .sorted { $0.date < $1.date },
            sleepEfficiency: sortedDateValues(from: sleepEfficiency),
            sleepConsistency: sleepConsistency,
            sleepStartHours: sortedDateValues(from: sleepStartHours),
            sleepMidpointHours: sortedDateValues(from: sleepMidpointHours),
            dailySleepHeartRate: sortedDateValues(from: dailySleepHeartRate),
            nightlyAnchoredHRV: sortedDateValues(from: nightlyAnchoredHRV),
            effectHRV: sortedDateValues(from: effectHRV),
            basalSleepingHeartRate: sortedDateValues(from: basalSleepingHeartRate),
            anchoredSleepDuration: sortedDateValues(from: anchoredSleepDuration),
            anchoredTimeInBed: sortedDateValues(from: anchoredTimeInBed),
            readinessHRV: readinessHRV,
            readinessEffectHRV: readinessEffectHRV,
            readinessBasalHeartRate: readinessBasalHeartRate,
            readinessSleepDuration: readinessSleepDuration,
            readinessTimeInBed: readinessTimeInBed,
            readinessSleepEfficiency: readinessSleepEfficiency,
            readinessSleepRatio: readinessSleepRatio,
            workoutHRVDecay: sortedDateValues(from: workoutHRVDecay),
            recoverySuppressedFlag: recoverySuppressedFlag,
            respiratoryRate: sortedDateValues(from: respiratoryRate),
            wristTemperature: sortedDateValues(from: wristTemperature),
            spO2: sortedDateValues(from: spO2),
            postWorkoutHR: sortedDateValues(from: postWorkoutHR),
            vo2Max: sortedDateValues(from: vo2Max),
            heartRateZones: heartRateZones
                .map { PersistedHeartRateZoneDay(date: $0.key, zones: $0.value) }
                .sorted { $0.date < $1.date },
            kcalBurned: sortedDateValues(from: kcalBurned),
            effortRating: sortedDateValues(from: effortRating),
            favoriteSport: favoriteSport,
            trainingFrequency: trainingFrequency,
            trainingFrequencyBySport: trainingFrequencyBySport
                .map { PersistedStringDoubleValue(key: $0.key, value: $0.value) }
                .sorted { $0.key < $1.key },
            recoveryScore: recoveryScore,
            strainScore: strainScore,
            readinessScore: readinessScore,
            hrvTrendScore: hrvTrendScore,
            circadianHRVScore: circadianHRVScore,
            sleepHRVScore: sleepHRVScore,
            allostaticStressScore: allostaticStressScore,
            autonomicBalanceScore: autonomicBalanceScore,
            feelGoodScore: feelGoodScore,
            feelGoodReadiness: PersistedReadinessResult(
                score: feelGoodReadiness.score,
                confidence: feelGoodReadiness.confidence,
                primaryDriver: feelGoodReadiness.primaryDriver
            )
        )
    }

    private func cloudTrimmedSnapshot(from snapshot: MetricsSnapshot) -> MetricsSnapshot {
        let dayLimit = 180
        let sampleLimit = 5_000
        return MetricsSnapshot(
            updatedAt: snapshot.updatedAt,
            latestHRV: snapshot.latestHRV,
            restingHeartRate: snapshot.restingHeartRate,
            dailyRestingHeartRate: Array(snapshot.dailyRestingHeartRate.suffix(dayLimit)),
            dailySleepDuration: Array(snapshot.dailySleepDuration.suffix(dayLimit)),
            sleepHours: snapshot.sleepHours,
            activityLoad: snapshot.activityLoad,
            hrvHistory: Array(snapshot.hrvHistory.suffix(180)),
            hrvSampleHistory: Array(snapshot.hrvSampleHistory.suffix(sampleLimit)),
            dailyHRV: Array(snapshot.dailyHRV.suffix(dayLimit)),
            sleepHRVAverage: snapshot.sleepHRVAverage,
            lastSleepStart: snapshot.lastSleepStart,
            lastSleepEnd: snapshot.lastSleepEnd,
            hrvBaseline7Day: snapshot.hrvBaseline7Day,
            rhrBaseline7Day: snapshot.rhrBaseline7Day,
            sleepBaseline7Day: snapshot.sleepBaseline7Day,
            hrvBaseline28Day: snapshot.hrvBaseline28Day,
            rhrBaseline28Day: snapshot.rhrBaseline28Day,
            hrvBaseline60Day: snapshot.hrvBaseline60Day,
            rhrBaseline60Day: snapshot.rhrBaseline60Day,
            sleepBaseline60Day: snapshot.sleepBaseline60Day,
            estimatedMaxHeartRate: snapshot.estimatedMaxHeartRate,
            userAge: snapshot.userAge,
            acuteTrainingLoad: snapshot.acuteTrainingLoad,
            chronicTrainingLoad: snapshot.chronicTrainingLoad,
            trainingLoadRatio: snapshot.trainingLoadRatio,
            functionalOverreachingFlag: snapshot.functionalOverreachingFlag,
            recoveryBaseline7Day: snapshot.recoveryBaseline7Day,
            strainBaseline7Day: snapshot.strainBaseline7Day,
            circadianBaseline7Day: snapshot.circadianBaseline7Day,
            autonomicBaseline7Day: snapshot.autonomicBaseline7Day,
            moodBaseline7Day: snapshot.moodBaseline7Day,
            sleepStages: Array(snapshot.sleepStages.suffix(dayLimit)),
            sleepEfficiency: Array(snapshot.sleepEfficiency.suffix(dayLimit)),
            sleepConsistency: snapshot.sleepConsistency,
            sleepStartHours: Array(snapshot.sleepStartHours.suffix(dayLimit)),
            sleepMidpointHours: Array(snapshot.sleepMidpointHours.suffix(dayLimit)),
            dailySleepHeartRate: Array(snapshot.dailySleepHeartRate.suffix(dayLimit)),
            nightlyAnchoredHRV: Array(snapshot.nightlyAnchoredHRV.suffix(dayLimit)),
            effectHRV: Array(snapshot.effectHRV.suffix(dayLimit)),
            basalSleepingHeartRate: Array(snapshot.basalSleepingHeartRate.suffix(dayLimit)),
            anchoredSleepDuration: Array(snapshot.anchoredSleepDuration.suffix(dayLimit)),
            anchoredTimeInBed: Array(snapshot.anchoredTimeInBed.suffix(dayLimit)),
            readinessHRV: snapshot.readinessHRV,
            readinessEffectHRV: snapshot.readinessEffectHRV,
            readinessBasalHeartRate: snapshot.readinessBasalHeartRate,
            readinessSleepDuration: snapshot.readinessSleepDuration,
            readinessTimeInBed: snapshot.readinessTimeInBed,
            readinessSleepEfficiency: snapshot.readinessSleepEfficiency,
            readinessSleepRatio: snapshot.readinessSleepRatio,
            workoutHRVDecay: Array(snapshot.workoutHRVDecay.suffix(dayLimit)),
            recoverySuppressedFlag: snapshot.recoverySuppressedFlag,
            respiratoryRate: Array(snapshot.respiratoryRate.suffix(dayLimit)),
            wristTemperature: Array(snapshot.wristTemperature.suffix(dayLimit)),
            spO2: Array(snapshot.spO2.suffix(dayLimit)),
            postWorkoutHR: Array(snapshot.postWorkoutHR.suffix(dayLimit)),
            vo2Max: Array(snapshot.vo2Max.suffix(dayLimit)),
            heartRateZones: Array(snapshot.heartRateZones.suffix(dayLimit)),
            kcalBurned: Array(snapshot.kcalBurned.suffix(dayLimit)),
            effortRating: Array(snapshot.effortRating.suffix(dayLimit)),
            favoriteSport: snapshot.favoriteSport,
            trainingFrequency: snapshot.trainingFrequency,
            trainingFrequencyBySport: snapshot.trainingFrequencyBySport,
            recoveryScore: snapshot.recoveryScore,
            strainScore: snapshot.strainScore,
            readinessScore: snapshot.readinessScore,
            hrvTrendScore: snapshot.hrvTrendScore,
            circadianHRVScore: snapshot.circadianHRVScore,
            sleepHRVScore: snapshot.sleepHRVScore,
            allostaticStressScore: snapshot.allostaticStressScore,
            autonomicBalanceScore: snapshot.autonomicBalanceScore,
            feelGoodScore: snapshot.feelGoodScore,
            feelGoodReadiness: snapshot.feelGoodReadiness
        )
    }

    private func loadMetricsSnapshotFromDisk() -> MetricsSnapshot? {
        guard let url = metricsSnapshotURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(MetricsSnapshot.self, from: data)
    }

    private func loadMetricsSnapshotFromCloud() -> MetricsSnapshot? {
        let cloudStore = NSUbiquitousKeyValueStore.default
        guard let data = cloudStore.data(forKey: metricsSnapshotCloudKey) else {
            return nil
        }

        return try? JSONDecoder().decode(MetricsSnapshot.self, from: data)
    }

    private func applyMetricsSnapshot(_ snapshot: MetricsSnapshot) {
        latestHRV = snapshot.latestHRV
        restingHeartRate = snapshot.restingHeartRate
        dailyRestingHeartRate = dateValueDictionary(from: snapshot.dailyRestingHeartRate)
        dailySleepDuration = dateValueDictionary(from: snapshot.dailySleepDuration)
        sleepHours = snapshot.sleepHours
        activityLoad = snapshot.activityLoad
        hrvHistory = snapshot.hrvHistory
        hrvSampleHistory = snapshot.hrvSampleHistory.map { HRVSamplePoint(date: $0.date, value: $0.value) }
        dailyHRV = snapshot.dailyHRV.map {
            DailyHRVPoint(date: $0.date, average: $0.average, min: $0.min, max: $0.max)
        }
        sleepHRVAverage = snapshot.sleepHRVAverage
        lastSleepStart = snapshot.lastSleepStart
        lastSleepEnd = snapshot.lastSleepEnd
        hrvBaseline7Day = snapshot.hrvBaseline7Day
        rhrBaseline7Day = snapshot.rhrBaseline7Day
        sleepBaseline7Day = snapshot.sleepBaseline7Day
        hrvBaseline28Day = snapshot.hrvBaseline28Day
        rhrBaseline28Day = snapshot.rhrBaseline28Day
        hrvBaseline60Day = snapshot.hrvBaseline60Day.map {
            RollingBaselineStats(mean: $0.mean, standardDeviation: $0.standardDeviation, sampleCount: $0.sampleCount)
        }
        rhrBaseline60Day = snapshot.rhrBaseline60Day.map {
            RollingBaselineStats(mean: $0.mean, standardDeviation: $0.standardDeviation, sampleCount: $0.sampleCount)
        }
        sleepBaseline60Day = snapshot.sleepBaseline60Day.map {
            RollingBaselineStats(mean: $0.mean, standardDeviation: $0.standardDeviation, sampleCount: $0.sampleCount)
        }
        estimatedMaxHeartRate = snapshot.estimatedMaxHeartRate
        userAge = snapshot.userAge
        acuteTrainingLoad = snapshot.acuteTrainingLoad
        chronicTrainingLoad = snapshot.chronicTrainingLoad
        trainingLoadRatio = snapshot.trainingLoadRatio
        functionalOverreachingFlag = snapshot.functionalOverreachingFlag
        recoveryBaseline7Day = snapshot.recoveryBaseline7Day
        strainBaseline7Day = snapshot.strainBaseline7Day
        circadianBaseline7Day = snapshot.circadianBaseline7Day
        autonomicBaseline7Day = snapshot.autonomicBaseline7Day
        moodBaseline7Day = snapshot.moodBaseline7Day
        sleepStages = Dictionary(uniqueKeysWithValues: snapshot.sleepStages.map { ($0.date, $0.stages) })
        sleepEfficiency = dateValueDictionary(from: snapshot.sleepEfficiency)
        sleepConsistency = snapshot.sleepConsistency
        sleepStartHours = dateValueDictionary(from: snapshot.sleepStartHours)
        sleepMidpointHours = dateValueDictionary(from: snapshot.sleepMidpointHours)
        dailySleepHeartRate = dateValueDictionary(from: snapshot.dailySleepHeartRate)
        nightlyAnchoredHRV = dateValueDictionary(from: snapshot.nightlyAnchoredHRV)
        effectHRV = dateValueDictionary(from: snapshot.effectHRV)
        basalSleepingHeartRate = dateValueDictionary(from: snapshot.basalSleepingHeartRate)
        anchoredSleepDuration = dateValueDictionary(from: snapshot.anchoredSleepDuration)
        anchoredTimeInBed = dateValueDictionary(from: snapshot.anchoredTimeInBed)
        readinessHRV = snapshot.readinessHRV
        readinessEffectHRV = snapshot.readinessEffectHRV
        readinessBasalHeartRate = snapshot.readinessBasalHeartRate
        readinessSleepDuration = snapshot.readinessSleepDuration
        readinessTimeInBed = snapshot.readinessTimeInBed
        readinessSleepEfficiency = snapshot.readinessSleepEfficiency
        readinessSleepRatio = snapshot.readinessSleepRatio
        workoutHRVDecay = dateValueDictionary(from: snapshot.workoutHRVDecay)
        recoverySuppressedFlag = snapshot.recoverySuppressedFlag
        respiratoryRate = dateValueDictionary(from: snapshot.respiratoryRate)
        wristTemperature = dateValueDictionary(from: snapshot.wristTemperature)
        spO2 = dateValueDictionary(from: snapshot.spO2)
        postWorkoutHR = dateValueDictionary(from: snapshot.postWorkoutHR)
        vo2Max = dateValueDictionary(from: snapshot.vo2Max)
        heartRateZones = Dictionary(uniqueKeysWithValues: snapshot.heartRateZones.map { ($0.date, $0.zones) })
        kcalBurned = dateValueDictionary(from: snapshot.kcalBurned)
        effortRating = dateValueDictionary(from: snapshot.effortRating)
        favoriteSport = snapshot.favoriteSport
        trainingFrequency = snapshot.trainingFrequency
        trainingFrequencyBySport = Dictionary(uniqueKeysWithValues: snapshot.trainingFrequencyBySport.map { ($0.key, $0.value) })
        recoveryScore = snapshot.recoveryScore
        strainScore = snapshot.strainScore
        readinessScore = snapshot.readinessScore
        hrvTrendScore = snapshot.hrvTrendScore
        circadianHRVScore = snapshot.circadianHRVScore
        sleepHRVScore = snapshot.sleepHRVScore
        allostaticStressScore = snapshot.allostaticStressScore
        autonomicBalanceScore = snapshot.autonomicBalanceScore
        feelGoodScore = snapshot.feelGoodScore
        feelGoodReadiness = ReadinessResult(
            score: snapshot.feelGoodReadiness.score,
            confidence: snapshot.feelGoodReadiness.confidence,
            primaryDriver: snapshot.feelGoodReadiness.primaryDriver
        )
        cachedMetricsUpdatedAt = snapshot.updatedAt
        hasHydratedCachedMetrics = true
    }

    private func hydrateMetricsFromCacheIfAvailable() {
        let localSnapshot = loadMetricsSnapshotFromDisk()
        let cloudSnapshot = loadMetricsSnapshotFromCloud()

        let bestSnapshot = [localSnapshot, cloudSnapshot]
            .compactMap { $0 }
            .max(by: { $0.updatedAt < $1.updatedAt })

        guard let bestSnapshot else { return }
        applyMetricsSnapshot(bestSnapshot)
    }

    /// Mac Catalyst has no practical HealthKit access; UI reads the same **aggregated** `MetricsSnapshot` iPhone/iPad uploads to iCloud Key-Value (+ local file).
    private static var usesAggregatedCloudHealthPath: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// Pull latest snapshot from iCloud KVS + disk merge, then optionally await CloudKit `EngineSyncBlob` records.
    /// - Parameter userInitiatedRefresh: When true on iOS/iPadOS, also fetches CloudKit handoff (same as Catalyst always does) so pull-to-refresh can merge phone-exported series without querying HealthKit.
    private func reloadAggregatedHealthSnapshotFromICloud(userInitiatedRefresh: Bool = false) async {
        NSUbiquitousKeyValueStore.default.synchronize()
        hydrateMetricsFromCacheIfAvailable()
        updateScores()
        await pullEngineSyncBlobsFromCloudKit(allowOnNonCatalyst: userInitiatedRefresh)
    }

    /// Load **time series** snapshots from CloudKit (`EngineSyncBlob`) written by iOS (required on Mac Catalyst; optional on other platforms when `allowOnNonCatalyst` is set for user refresh).
    private func pullEngineSyncBlobsFromCloudKit(allowOnNonCatalyst: Bool = false) async {
        guard Self.usesAggregatedCloudHealthPath || allowOnNonCatalyst else { return }
        guard await CloudKitManager.shared.accountCanUseCloudKit() else { return }

        if let (_, data) = await CloudKitManager.shared.fetchEngineSyncBlob(
            recordName: NutrivanceEngineSyncSchema.RecordName.metricsSnapshot
        ),
           let snap = try? JSONDecoder().decode(MetricsSnapshot.self, from: data) {
            let localAnchor = cachedMetricsUpdatedAt ?? .distantPast
            let localSeriesEmpty = dailyHRV.isEmpty && dailyRestingHeartRate.isEmpty
            #if targetEnvironment(macCatalyst)
            let richerHandoffPending =
                snap.hrvSampleHistory.count > hrvSampleHistory.count
                || snap.sleepStages.count > sleepStages.count
            let shouldApplyMetrics = snap.updatedAt > localAnchor || localSeriesEmpty || richerHandoffPending
            #else
            let shouldApplyMetrics = snap.updatedAt > localAnchor || localSeriesEmpty
            #endif
            if shouldApplyMetrics {
                applyMetricsSnapshot(snap)
                if let url = metricsSnapshotURL(), let enc = try? JSONEncoder().encode(snap) {
                    try? enc.write(to: url, options: .atomic)
                }
            }
        }

        await mergeDetailedHealthHandoffsFromCloudKit()

        if let (ckUpdated, data) = await CloudKitManager.shared.fetchEngineSyncBlob(
            recordName: NutrivanceEngineSyncSchema.RecordName.workoutAnalytics
        ),
           let entries = try? JSONDecoder().decode([PersistedWorkoutAnalyticsEntry].self, from: data),
           entries.allSatisfy({ $0.schemaVersion >= Self.workoutAnalyticsSchemaVersion }) {
            let anchor = workoutAnalyticsCacheTimestamp ?? .distantPast
            if ckUpdated > anchor || workoutAnalytics.isEmpty {
                workoutAnalytics = rebuildWorkoutAnalytics(from: entries)
                workoutAnalyticsCacheTimestamp = ckUpdated
                lastCachedWorkoutDate = entries.map(\.workoutStartDate).max()
                earliestRequestedWorkoutDate = entries.map(\.workoutStartDate).min()
                hasInitializedWorkoutAnalytics = true
                if let url = persistentCacheURL() {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }

        updateScores()
        scheduleScoresRefresh()
    }

    private func clampSleepTimelineSegmentCount() {
        guard sleepTimelineSegments.count > cloudHandoffMaxSleepSegments else { return }
        sleepTimelineSegments = Array(sleepTimelineSegments.sorted { $0.start < $1.start }.suffix(cloudHandoffMaxSleepSegments))
    }

    private func dedupeSleepTimelineSegments(_ segs: [EngineSleepTimelineSegment]) -> [EngineSleepTimelineSegment] {
        var seen = Set<String>()
        var out: [EngineSleepTimelineSegment] = []
        for s in segs.sorted(by: { $0.start < $1.start }) {
            let key = String(format: "%.3f_%.3f_%d", s.start.timeIntervalSince1970, s.end.timeIntervalSince1970, s.stageValue)
            guard seen.insert(key).inserted else { continue }
            out.append(s)
        }
        return out
    }

    private func applyHRVSamplesHandoffPayload(_ payload: EngineHRVSamplesBlob) {
        let sorted = payload.samples.sorted { $0.date < $1.date }
        hrvSampleHistory = sorted.map { HRVSamplePoint(date: $0.date, value: $0.value) }
        hrvHistory = sorted.map(\.value)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.date) }
        dailyHRV = grouped.map { day, pts in
            let vals = pts.map(\.value)
            let avg = vals.reduce(0, +) / Double(max(vals.count, 1))
            return DailyHRVPoint(
                date: day,
                average: avg,
                min: vals.min() ?? avg,
                max: vals.max() ?? avg
            )
        }.sorted { $0.date < $1.date }
    }

    /// Merges full HRV sample list + sleep segment timeline from iPhone/iPad CloudKit handoff (Stress / Sleep graphs on Mac Catalyst).
    private func mergeDetailedHealthHandoffsFromCloudKit() async {
        guard await CloudKitManager.shared.accountCanUseCloudKit() else { return }

        if let (_, data) = await CloudKitManager.shared.fetchEngineSyncBlob(
            recordName: NutrivanceEngineSyncSchema.RecordName.hrvSamplesDetailed
        ),
           let payload = try? JSONDecoder().decode(EngineHRVSamplesBlob.self, from: data),
           !payload.samples.isEmpty {
            let shouldApply = payload.updatedAt > lastAppliedHRVSamplesHandoffAt
                || hrvSampleHistory.isEmpty
                || payload.samples.count > hrvSampleHistory.count
            if shouldApply {
                lastAppliedHRVSamplesHandoffAt = payload.updatedAt
                applyHRVSamplesHandoffPayload(payload)
            }
        }

        if let (_, data) = await CloudKitManager.shared.fetchEngineSyncBlob(
            recordName: NutrivanceEngineSyncSchema.RecordName.sleepTimelineDetailed
        ),
           let payload = try? JSONDecoder().decode(EngineSleepTimelineBlob.self, from: data),
           !payload.segments.isEmpty {
            let shouldApply = payload.updatedAt > lastAppliedSleepTimelineHandoffAt
                || sleepTimelineSegments.isEmpty
                || payload.segments.count > sleepTimelineSegments.count
            if shouldApply {
                lastAppliedSleepTimelineHandoffAt = payload.updatedAt
                sleepTimelineSegments = dedupeSleepTimelineSegments(payload.segments)
                clampSleepTimelineSegmentCount()
            }
        }

        if let (_, data) = await CloudKitManager.shared.fetchEngineSyncBlob(
            recordName: NutrivanceEngineSyncSchema.RecordName.sleepUIMetricsDetailed
        ),
           let payload = try? JSONDecoder().decode(EngineSleepUIMetricsBlob.self, from: data),
           (!payload.nights.isEmpty || !payload.bedtimeNights.isEmpty) {
            let shouldApply = payload.updatedAt > lastAppliedSleepUIMetricsHandoffAt
                || sleepUIMetricsHandoff.nights.isEmpty
                || payload.nights.count > sleepUIMetricsHandoff.nights.count
            if shouldApply {
                lastAppliedSleepUIMetricsHandoffAt = payload.updatedAt
                sleepUIMetricsHandoff = payload
            }
        }
    }

    /// Mac Catalyst: handoff package for a calendar wake day, if iPhone uploaded it.
    func sleepNightUIPackage(forWakeDay wakeDayStart: Date) -> EngineSleepNightUIPackage? {
        let cal = Calendar.current
        let key = cal.startOfDay(for: wakeDayStart)
        return sleepUIMetricsHandoff.nights.first { cal.isDate($0.wakeDayStart, inSameDayAs: key) }
    }

    #if !targetEnvironment(macCatalyst)
    /// Call after iOS loads a night in Sleep (HealthKit) so Mac gets segments, vitals, dip, charts. Updates in-memory handoff immediately; CloudKit upload is scheduled so iOS Sleep UI is not blocked.
    func upsertSleepUIMetricsHandoff(_ package: EngineSleepNightUIPackage, bedtimeNights: [EngineBedtimeNightHandoff]) {
        var nights = sleepUIMetricsHandoff.nights
        let cal = Calendar.current
        nights.removeAll { cal.isDate($0.wakeDayStart, inSameDayAs: package.wakeDayStart) }
        var trimmedSegs = package.segments
        if trimmedSegs.count > 120 { trimmedSegs = Array(trimmedSegs.prefix(120)) }
        var agg = package
        agg.segments = trimmedSegs
        nights.insert(agg, at: 0)
        if nights.count > 30 { nights = Array(nights.prefix(30)) }
        sleepUIMetricsHandoff = EngineSleepUIMetricsBlob(updatedAt: Date(), nights: nights, bedtimeNights: bedtimeNights)
        Task { await self.pushDetailedHealthHandoffsToCloudKit() }
    }

    private func pushDetailedHealthHandoffsToCloudKit() async {
        guard await CloudKitManager.shared.accountCanUseCloudKit() else { return }
        let sortedHRV = hrvSampleHistory.sorted { $0.date < $1.date }
        let hrvTrimmed = Array(sortedHRV.suffix(cloudHandoffMaxHRVSamples)).map {
            EngineHRVSamplePoint(date: $0.date, value: $0.value)
        }
        let hrvBlob = EngineHRVSamplesBlob(updatedAt: Date(), samples: hrvTrimmed)
        if let enc = try? JSONEncoder().encode(hrvBlob) {
            do {
                try await CloudKitManager.shared.uploadEngineSyncBlob(
                    recordName: NutrivanceEngineSyncSchema.RecordName.hrvSamplesDetailed,
                    data: enc
                )
            } catch {
                CloudKitManager.shared.reportHealthSyncError("HRV samples handoff: \(error.localizedDescription)")
            }
        }
        let sleepSorted = dedupeSleepTimelineSegments(sleepTimelineSegments)
        let sleepTrimmed = Array(sleepSorted.suffix(cloudHandoffMaxSleepSegments))
        let sleepBlob = EngineSleepTimelineBlob(updatedAt: Date(), segments: sleepTrimmed)
        if let enc = try? JSONEncoder().encode(sleepBlob) {
            do {
                try await CloudKitManager.shared.uploadEngineSyncBlob(
                    recordName: NutrivanceEngineSyncSchema.RecordName.sleepTimelineDetailed,
                    data: enc
                )
            } catch {
                CloudKitManager.shared.reportHealthSyncError("Sleep timeline handoff: \(error.localizedDescription)")
            }
        }
        if !sleepUIMetricsHandoff.nights.isEmpty || !sleepUIMetricsHandoff.bedtimeNights.isEmpty,
           let enc = try? JSONEncoder().encode(sleepUIMetricsHandoff) {
            do {
                try await CloudKitManager.shared.uploadEngineSyncBlob(
                    recordName: NutrivanceEngineSyncSchema.RecordName.sleepUIMetricsDetailed,
                    data: enc
                )
            } catch {
                CloudKitManager.shared.reportHealthSyncError("Sleep UI metrics handoff: \(error.localizedDescription)")
            }
        }
    }
    #endif

    /// User-visible refresh: merge **NSUbiquitousKeyValueStore** metrics snapshot with local cache and pull **CloudKit** engine blobs when the account allows. Does **not** run HealthKit coverage backfills.
    func refreshSyncedHealthDataFromICloud() async {
        await reloadAggregatedHealthSnapshotFromICloud(userInitiatedRefresh: true)
        scheduleScoresRefresh()
        scheduleMetricsSnapshotSave()
    }

    #if !targetEnvironment(macCatalyst)
    /// Push latest metrics + workout JSON to CloudKit immediately (e.g. app background) so Mac Catalyst can show frozen graph data.
    private func pushFrozenEngineHandoffToCloudKit() async {
        guard await CloudKitManager.shared.accountCanUseCloudKit() else { return }
        let snapshot = currentMetricsSnapshot()
        if let fullEncoded = try? JSONEncoder().encode(snapshot) {
            do {
                try await CloudKitManager.shared.uploadEngineSyncBlob(
                    recordName: NutrivanceEngineSyncSchema.RecordName.metricsSnapshot,
                    data: fullEncoded
                )
            } catch {
                CloudKitManager.shared.reportHealthSyncError("Engine metrics handoff: \(error.localizedDescription)")
            }
        }
        if let url = persistentCacheURL(),
           FileManager.default.fileExists(atPath: url.path),
           let wdata = try? Data(contentsOf: url),
           !wdata.isEmpty {
            do {
                try await CloudKitManager.shared.uploadEngineSyncBlob(
                    recordName: NutrivanceEngineSyncSchema.RecordName.workoutAnalytics,
                    data: wdata
                )
            } catch {
                CloudKitManager.shared.reportHealthSyncError("Engine workout handoff: \(error.localizedDescription)")
            }
        }
        await pushDetailedHealthHandoffsToCloudKit()
    }
    #endif

    private func saveMetricsSnapshotNow() {
        guard isAppActive else { return }
        let snapshot = currentMetricsSnapshot()
        cachedMetricsUpdatedAt = snapshot.updatedAt
        hasHydratedCachedMetrics = true

        let localURL = metricsSnapshotURL()
        let cloudKey = metricsSnapshotCloudKey
        let cloudSnapshot = cloudTrimmedSnapshot(from: snapshot)
        let fullEncoded = try? JSONEncoder().encode(snapshot)
        metricsSnapshotWriteTask?.cancel()
        #if !targetEnvironment(macCatalyst)
        metricsSnapshotWriteTask = Task.detached(priority: .utility) { [fullEncoded] in
            if let url = localURL, let fullEncoded {
                try? fullEncoded.write(to: url, options: .atomic)
            }
        }
        #endif

        #if !targetEnvironment(macCatalyst)
        Task { @MainActor in
            if let cloudData = try? JSONEncoder().encode(cloudSnapshot) {
                NSUbiquitousKeyValueStore.default.set(cloudData, forKey: cloudKey)
                NSUbiquitousKeyValueStore.default.synchronize()
            }
            if let fullEncoded {
                do {
                    try await CloudKitManager.shared.uploadEngineSyncBlob(
                        recordName: NutrivanceEngineSyncSchema.RecordName.metricsSnapshot,
                        data: fullEncoded
                    )
                } catch {
                    CloudKitManager.shared.reportHealthSyncError("Metrics snapshot CK upload: \(error.localizedDescription)")
                }
            }
            await pushDetailedHealthHandoffsToCloudKit()
        }
        #endif
    }

    private func scheduleMetricsSnapshotSave(delayNanoseconds: UInt64 = 600_000_000) {
        metricsSnapshotSaveTask?.cancel()
        metricsSnapshotSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled, self.isAppActive else { return }
            self.saveMetricsSnapshotNow()
        }
    }

    private func beginBackgroundMetricsRefreshWindow() {
        isRefreshingCachedMetrics = true
        metricsRefreshCompletionTask?.cancel()
        metricsRefreshCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isRefreshingCachedMetrics = false
            self.scheduleMetricsSnapshotSave(delayNanoseconds: 200_000_000)
        }
    }
    
    /// Save complete cache metadata for fast load on app restart
    private func savePersistentCacheMetadata(_ analytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)]) {
        guard let url = persistentCacheURL() else { return }
        let encoder = JSONEncoder()
        let cacheEntries = analytics.map { pair -> PersistedWorkoutAnalyticsEntry in
            let numericMetadata = (pair.workout.metadata ?? [:]).reduce(into: [String: Double]()) { partial, item in
                if let number = item.value as? NSNumber {
                    partial[item.key] = number.doubleValue
                } else if let value = item.value as? Double {
                    partial[item.key] = value
                }
            }

            return PersistedWorkoutAnalyticsEntry(
                schemaVersion: Self.workoutAnalyticsSchemaVersion,
                workoutUUID: canonicalWorkoutID(for: pair.workout),
                workoutStartDate: pair.workout.startDate,
                workoutEndDate: pair.workout.endDate,
                workoutDuration: pair.workout.duration,
                workoutTypeRawValue: pair.workout.workoutActivityType.rawValue,
                totalEnergyBurnedKilocalories: pair.workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                totalDistanceMeters: pair.workout.totalDistance?.doubleValue(for: .meter()),
                metadata: numericMetadata,
                heartRates: pair.analytics.heartRates.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                vo2Max: pair.analytics.vo2Max,
                metTotal: pair.analytics.metTotal,
                metAverage: pair.analytics.metAverage,
                metSeries: pair.analytics.metSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                postWorkoutHRSeries: pair.analytics.postWorkoutHRSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                peakHR: pair.analytics.peakHR,
                hrr0: pair.analytics.hrr0,
                hrr1: pair.analytics.hrr1,
                hrr2: pair.analytics.hrr2,
                powerSeries: pair.analytics.powerSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                speedSeries: pair.analytics.speedSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                cadenceSeries: pair.analytics.cadenceSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                elevationSeries: pair.analytics.elevationSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                elevationGain: pair.analytics.elevationGain,
                verticalOscillationSeries: pair.analytics.verticalOscillationSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                groundContactTimeSeries: pair.analytics.groundContactTimeSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                strideLengthSeries: pair.analytics.strideLengthSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                strokeCountSeries: pair.analytics.strokeCountSeries.map { PersistedWorkoutSeriesPoint(date: $0.0, value: $0.1) },
                verticalOscillation: pair.analytics.verticalOscillation,
                groundContactTime: pair.analytics.groundContactTime,
                strideLength: pair.analytics.strideLength,
                hrZoneProfile: pair.analytics.hrZoneProfile,
                hrZoneBreakdown: pair.analytics.hrZoneBreakdown.map {
                    PersistedWorkoutZoneBreakdown(zone: $0.zone, timeInZone: $0.timeInZone)
                }
            )
        }
        do {
            let jsonData = try encoder.encode(cacheEntries)
            try jsonData.write(to: url, options: .atomicWrite)
            print("[Cache] Saved \(cacheEntries.count) workouts to disk")
            #if !targetEnvironment(macCatalyst)
            scheduleWorkoutAnalyticsCloudUpload(jsonData: jsonData)
            #endif
        } catch {
            print("Failed to save persistent cache: \(error)")
        }
    }

    #if !targetEnvironment(macCatalyst)
    /// Debounced upload so CloudKit is not hammered while workout list updates rapidly.
    private func scheduleWorkoutAnalyticsCloudUpload(jsonData: Data) {
        workoutCloudUploadTask?.cancel()
        let payload = jsonData
        workoutCloudUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled, self.isAppActive else { return }
            guard await CloudKitManager.shared.accountCanUseCloudKit() else { return }
            do {
                try await CloudKitManager.shared.uploadEngineSyncBlob(
                    recordName: NutrivanceEngineSyncSchema.RecordName.workoutAnalytics,
                    data: payload
                )
            } catch {
                CloudKitManager.shared.reportHealthSyncError("Workout analytics CK upload: \(error.localizedDescription)")
            }
        }
    }
    #endif

    private func canonicalWorkoutID(for workout: HKWorkout) -> String {
        if let metadataValue = workout.metadata?[Self.cachedWorkoutUUIDMetadataKey] as? String,
           !metadataValue.isEmpty {
            return metadataValue
        }
        return workout.uuid.uuidString
    }

    private func rebuildWorkoutAnalytics(from cacheEntries: [PersistedWorkoutAnalyticsEntry]) -> [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        cacheEntries.compactMap { entry in
            guard let activityType = HKWorkoutActivityType(rawValue: entry.workoutTypeRawValue) else {
                return nil
            }

            let totalEnergyBurned = entry.totalEnergyBurnedKilocalories.map {
                HKQuantity(unit: .kilocalorie(), doubleValue: $0)
            }
            let totalDistance = entry.totalDistanceMeters.map {
                HKQuantity(unit: .meter(), doubleValue: $0)
            }
            var workoutMetadata = entry.metadata.reduce(into: [String: Any]()) { partial, item in
                partial[item.key] = item.value
            }
            workoutMetadata[Self.cachedWorkoutUUIDMetadataKey] = entry.workoutUUID

            let workout = HKWorkout(
                activityType: activityType,
                start: entry.workoutStartDate,
                end: entry.workoutEndDate,
                duration: entry.workoutDuration,
                totalEnergyBurned: totalEnergyBurned,
                totalDistance: totalDistance,
                metadata: workoutMetadata.isEmpty ? nil : workoutMetadata
            )

            let analytics = WorkoutAnalytics(
                workout: workout,
                heartRates: entry.heartRates.map { ($0.date, $0.value) },
                vo2Max: entry.vo2Max,
                metTotal: entry.metTotal,
                metAverage: entry.metAverage,
                metSeries: entry.metSeries.map { ($0.date, $0.value) },
                postWorkoutHRSeries: entry.postWorkoutHRSeries.map { ($0.date, $0.value) },
                peakHR: entry.peakHR,
                hrr0: entry.hrr0,
                hrr1: entry.hrr1,
                hrr2: entry.hrr2,
                powerSeries: entry.powerSeries.map { ($0.date, $0.value) },
                speedSeries: entry.speedSeries.map { ($0.date, $0.value) },
                cadenceSeries: entry.cadenceSeries.map { ($0.date, $0.value) },
                elevationSeries: entry.elevationSeries.map { ($0.date, $0.value) },
                elevationGain: entry.elevationGain,
                verticalOscillationSeries: entry.verticalOscillationSeries.map { ($0.date, $0.value) },
                groundContactTimeSeries: entry.groundContactTimeSeries.map { ($0.date, $0.value) },
                strideLengthSeries: entry.strideLengthSeries.map { ($0.date, $0.value) },
                strokeCountSeries: entry.strokeCountSeries.map { ($0.date, $0.value) },
                verticalOscillation: entry.verticalOscillation,
                groundContactTime: entry.groundContactTime,
                strideLength: entry.strideLength,
                hrZoneProfile: entry.hrZoneProfile,
                hrZoneBreakdown: entry.hrZoneBreakdown.map { ($0.zone, $0.timeInZone) }
            )

            return (workout, analytics)
        }
    }

    private func workoutAnalyticsNeedsSeriesBackfill(_ analytics: [(workout: HKWorkout, analytics: WorkoutAnalytics)]) -> Bool {
        analytics.contains { pair in
            switch pair.workout.workoutActivityType {
            case .running:
                return (pair.analytics.elevationGain != nil && pair.analytics.elevationSeries.isEmpty)
                    || (pair.analytics.verticalOscillation != nil && pair.analytics.verticalOscillationSeries.isEmpty)
                    || (pair.analytics.groundContactTime != nil && pair.analytics.groundContactTimeSeries.isEmpty)
                    || (pair.analytics.strideLength != nil && pair.analytics.strideLengthSeries.isEmpty)
            case .cycling:
                return (pair.analytics.elevationGain != nil && pair.analytics.elevationSeries.isEmpty)
                    || (pair.workout.totalDistance != nil && pair.analytics.speedSeries.isEmpty)
            case .swimming:
                return pair.workout.totalDistance != nil && pair.analytics.strokeCountSeries.isEmpty
            default:
                return false
            }
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
            let cacheEntries = try JSONDecoder().decode([PersistedWorkoutAnalyticsEntry].self, from: data)
            guard cacheEntries.allSatisfy({ $0.schemaVersion >= Self.workoutAnalyticsSchemaVersion }) else {
                print("[Cache] Workout analytics cache schema is outdated, ignoring disk cache")
                return []
            }
            print("[Cache] Cache file exists with \(cacheEntries.count) workouts")
            let summaries = cacheEntries.map { entry in
                CachedWorkoutSummary(
                    startDate: entry.workoutStartDate,
                    endDate: entry.workoutEndDate,
                    duration: entry.workoutDuration,
                    workoutType: HKWorkoutActivityType(rawValue: entry.workoutTypeRawValue)?.name ?? "other",
                    metTotal: entry.metTotal ?? 0,
                    vo2Max: entry.vo2Max,
                    avgHR: entry.heartRates.map(\.value).average ?? 0,
                    peakHR: entry.peakHR,
                    totalKcal: entry.totalEnergyBurnedKilocalories ?? 0,
                    distance: entry.totalDistanceMeters ?? 0
                )
            }
                return summaries
        } catch {
            print("[Cache] Failed to load persistent cache: \(error)")
        }
        return []
    }

    private func loadPersistedWorkoutAnalyticsEntries() -> [PersistedWorkoutAnalyticsEntry] {
        guard let url = persistentCacheURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        guard let entries = try? JSONDecoder().decode([PersistedWorkoutAnalyticsEntry].self, from: data) else {
            return []
        }
        guard entries.allSatisfy({ $0.schemaVersion >= Self.workoutAnalyticsSchemaVersion }) else {
            print("[Cache] Persisted workout analytics cache is outdated, forcing refresh")
            return []
        }
        return entries
    }
    
    private func loadPersistentCache() {
        guard let url = persistentCacheURL(), FileManager.default.fileExists(atPath: url.path) else {
            diskCacheLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let cacheEntries = try JSONDecoder().decode([PersistedWorkoutAnalyticsEntry].self, from: data)
            guard cacheEntries.allSatisfy({ $0.schemaVersion >= Self.workoutAnalyticsSchemaVersion }) else {
                print("Failed to load persistent cache: outdated workout analytics schema")
                diskCacheLoaded = true
                return
            }
            lastCachedWorkoutDate = cacheEntries.map(\.workoutStartDate).max()
            earliestRequestedWorkoutDate = cacheEntries.map(\.workoutStartDate).min()
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
        let resting = CoachHRRRestingGate.shared.current()
        let restingKey = Int(resting.rounded())
        for (workout, analytics) in workoutAnalytics {
            let day = calendar.startOfDay(for: workout.startDate)
            let result: HeartRateRecoveryResult
            if let cached = HRRAnalysisCache.shared.result(for: workout.uuid),
               cached.restingHRUsed.map({ Int($0.rounded()) }) == Optional(restingKey) {
                result = cached
            } else {
                let analyzed = HeartRateRecoveryAnalysis.analyze(workout: workout, analytics: analytics, restingHRBpm: resting)
                HRRAnalysisCache.shared.store(analyzed, workoutUUID: workout.uuid)
                result = analyzed
            }
            if let hrr2 = HeartRateRecoveryAnalysis.trendPreferredDropBpm(result: result) {
                aggregates[day] = max(aggregates[day] ?? 0, hrr2)
            }
        }
        return aggregates
    }

    // MARK: - Sleep Quality Fetch (stages, efficiency, consistency)
    private func fetchSleepQuality(days: Int = 28) {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        fetchSleepQuality(from: startDate, to: endDate, mergeIntoExisting: false)
    }

    private func fetchSleepQuality(
        from startDate: Date,
        to endDate: Date,
        mergeIntoExisting: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion?()
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
            guard let samples = samples as? [HKCategorySample], error == nil else {
                completion?()
                return
            }
            let calendar = Calendar.current
            var stages: [Date: [String: Double]] = [:]
            var efficiency: [Date: Double] = [:]
            var bedtimeHours: [Date: Double] = [:]
            var midpointHours: [Date: Double] = [:]
            // Keep separate interval collections so Sleep HR / consistency can use stage-based windows
            // even when `.inBed` samples are sparse in historical data.
            var stageSleepWindows: [Date: [(start: Date, end: Date)]] = [:]
            var inBedSleepWindows: [Date: [(start: Date, end: Date)]] = [:]
            var collectedSegments: [EngineSleepTimelineSegment] = []
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
                    stage = "unspecified"
                default:
                    continue
                }
                var dayData = stages[day] ?? ["deep": 0.0, "rem": 0.0, "core": 0.0, "unspecified": 0.0, "awake": 0.0, "inBed": 0.0]
                if isInBed {
                    dayData["inBed"] = (dayData["inBed"] ?? 0.0) + duration
                    // Collect start time for consistency
                    let hour = Double(calendar.component(.hour, from: sample.startDate)) + Double(calendar.component(.minute, from: sample.startDate)) / 60.0
                    bedtimeHours[day] = min(bedtimeHours[day] ?? hour, hour)
                    inBedSleepWindows[day, default: []].append((start: sample.startDate, end: sample.endDate))
                } else if let stage = stage {
                    dayData[stage] = (dayData[stage] ?? 0.0) + duration
                    stageSleepWindows[day, default: []].append((start: sample.startDate, end: sample.endDate))
                    collectedSegments.append(
                        EngineSleepTimelineSegment(start: sample.startDate, end: sample.endDate, stageValue: value)
                    )
                }
                stages[day] = dayData
            }

            // Merge overlapping/adjacent intervals per day so we don't end up with fragmented windows.
            let tolerance: TimeInterval = 5 * 60 // 5 minutes
            func mergedWindows(
                from windowsByDay: [Date: [(start: Date, end: Date)]]
            ) -> [Date: [(start: Date, end: Date)]] {
                var mergedByDay: [Date: [(start: Date, end: Date)]] = [:]
                for (day, intervals) in windowsByDay {
                    let sorted = intervals.sorted { $0.start < $1.start }
                    var merged: [(start: Date, end: Date)] = []
                    for interval in sorted {
                        guard var last = merged.last else {
                            merged.append(interval)
                            continue
                        }
                        if interval.start <= last.end.addingTimeInterval(tolerance) {
                            last.end = max(last.end, interval.end)
                            merged[merged.count - 1] = last
                        } else {
                            merged.append(interval)
                        }
                    }
                    mergedByDay[day] = merged
                }
                return mergedByDay
            }

            let mergedStageWindows = mergedWindows(from: stageSleepWindows)
            let mergedInBedWindows = mergedWindows(from: inBedSleepWindows)

            // Use stage-derived windows first (better historical coverage), fallback to inBed windows.
            let windowDays = Set(mergedStageWindows.keys).union(mergedInBedWindows.keys)
            var sleepWindows: [Date: [(start: Date, end: Date)]] = [:]
            for day in windowDays {
                if let stage = mergedStageWindows[day], !stage.isEmpty {
                    sleepWindows[day] = stage
                } else if let inBed = mergedInBedWindows[day], !inBed.isEmpty {
                    sleepWindows[day] = inBed
                }
            }
            // Calculate efficiency
            for (date, data) in stages {
                let totalAsleep = (data["deep"] ?? 0) + (data["rem"] ?? 0) + (data["core"] ?? 0)
                let totalInBed = data["inBed"] ?? 0
                if totalInBed > 0 {
                    efficiency[date] = totalAsleep / totalInBed
                }
            }
            // For consistency use the longest sleep window for each day (usually the nighttime block, not naps).
            for (date, windows) in sleepWindows {
                guard let longestWindow = windows.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) else { continue }
                let midpointDate = longestWindow.start.addingTimeInterval(longestWindow.end.timeIntervalSince(longestWindow.start) / 2)
                let rawHour = Double(calendar.component(.hour, from: midpointDate)) + Double(calendar.component(.minute, from: midpointDate)) / 60.0
                midpointHours[date] = rawHour < 12 ? rawHour + 24 : rawHour
            }
            // Calculate consistency
            var consistency: Double? = nil
            let midpointValues = midpointHours.values.map { $0 }
            if !midpointValues.isEmpty {
                let mean = midpointValues.reduce(0, +) / Double(midpointValues.count)
                let variance = midpointValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(midpointValues.count)
                consistency = sqrt(variance)
            }
            DispatchQueue.main.async {
                let sanitizedStages = stages.mapValues { dict in
                    var d = dict
                    d.removeValue(forKey: "inBed")
                    return d
                }

                if mergeIntoExisting {
                    self.sleepStages.merge(sanitizedStages) { _, new in new }
                    self.sleepEfficiency.merge(efficiency) { _, new in new }
                    self.sleepStartHours.merge(bedtimeHours) { _, new in new }
                    self.sleepMidpointHours.merge(midpointHours) { _, new in new }
                } else {
                    self.sleepStages = sanitizedStages
                    self.sleepEfficiency = efficiency
                    self.sleepStartHours = bedtimeHours
                    self.sleepMidpointHours = midpointHours
                }

                let sortedNewSegments = collectedSegments.sorted { $0.start < $1.start }
                if mergeIntoExisting {
                    let kept = self.sleepTimelineSegments.filter { !($0.end > startDate && $0.start < endDate) }
                    self.sleepTimelineSegments = self.dedupeSleepTimelineSegments(kept + sortedNewSegments)
                } else {
                    self.sleepTimelineSegments = self.dedupeSleepTimelineSegments(sortedNewSegments)
                }
                self.clampSleepTimelineSegmentCount()

                let midpointValues = self.sleepMidpointHours.values.map { $0 }
                if !midpointValues.isEmpty {
                    let mean = midpointValues.reduce(0, +) / Double(midpointValues.count)
                    let variance = midpointValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(midpointValues.count)
                    self.sleepConsistency = sqrt(variance)
                } else {
                    self.sleepConsistency = consistency
                }

                self.scheduleMetricsSnapshotSave()
            }
            
            Task { @MainActor in
                var pending = 2
                let finish: () -> Void = {
                    pending -= 1
                    if pending == 0 {
                        completion?()
                    }
                }
                self.fetchSleepHeartRateHistory(
                    sleepWindows: sleepWindows,
                    queryStart: startDate,
                    queryEnd: endDate,
                    mergeIntoExisting: mergeIntoExisting,
                    completion: finish
                )
                self.fetchSleepAnchoredRecoveryHistory(
                    stageSleepWindows: mergedStageWindows,
                    inBedSleepWindows: mergedInBedWindows,
                    queryStart: startDate,
                    queryEnd: endDate,
                    mergeIntoExisting: mergeIntoExisting,
                    completion: finish
                )
            }
        }
        healthStore.execute(query)
    }
    
    private func fetchSleepHeartRateHistory(
        sleepWindows: [Date: [(start: Date, end: Date)]],
        queryStart: Date,
        queryEnd: Date,
        mergeIntoExisting: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion?()
            return
        }
        
        let sortedDays = sleepWindows.keys.sorted(by: >)
        guard !sortedDays.isEmpty else {
            DispatchQueue.main.async {
                if !mergeIntoExisting {
                    self.dailySleepHeartRate = [:]
                }
            }
            completion?()
            return
        }
        
        // Fast-first UX: publish recent data immediately, backfill older history in larger chunks.
        let firstBatchDays = 21
        let subsequentBatchDays = 120
        
        Task {
            var aggregated: [Date: Double] = mergeIntoExisting ? self.dailySleepHeartRate : [:]
            var cursor = 0
            
            while cursor < sortedDays.count {
                let batchSize = (cursor == 0) ? firstBatchDays : subsequentBatchDays
                let end = min(cursor + batchSize, sortedDays.count)
                let daysBatch = Array(sortedDays[cursor..<end])
                
                let batchResult = await self.computeSleepHeartRateBatch(
                    days: daysBatch,
                    sleepWindows: sleepWindows,
                    fallbackStart: queryStart,
                    fallbackEnd: queryEnd,
                    heartRateType: type
                )
                
                if !batchResult.isEmpty {
                    aggregated.merge(batchResult) { _, new in new }
                    self.dailySleepHeartRate = aggregated
                }
                
                cursor = end
            }

            completion?()
        }
    }
    
    private func computeSleepHeartRateBatch(
        days: [Date],
        sleepWindows: [Date: [(start: Date, end: Date)]],
        fallbackStart: Date,
        fallbackEnd: Date,
        heartRateType: HKQuantityType
    ) async -> [Date: Double] {
        guard !days.isEmpty else { return [:] }
        
        let windows = days.flatMap { sleepWindows[$0] ?? [] }
        let batchStart = windows.map(\.start).min() ?? fallbackStart
        let batchEnd = windows.map(\.end).max() ?? fallbackEnd
        let predicate = HKQuery.predicateForSamples(withStart: batchStart, end: batchEnd)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }
        
        var result: [Date: Double] = [:]
        for day in days {
            guard let windows = sleepWindows[day], !windows.isEmpty else { continue }
            var sum = 0.0
            var count = 0
            
            for window in windows {
                for sample in samples {
                    // Include overlapping HR samples (not only fully-contained samples).
                    guard sample.endDate > window.start && sample.startDate < window.end else { continue }
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    sum += bpm
                    count += 1
                }
            }
            
            if count > 0 {
                result[day] = sum / Double(count)
            }
        }
        
        return result
    }

    private struct SleepAnchoredRecoveryDay {
        let anchoredHRV: Double?
        let basalHeartRate: Double?
        let asleepHours: Double
        let timeInBedHours: Double
        let sleepEfficiency: Double
    }

    private func isPlausibleHRV(_ value: Double) -> Bool {
        value > 0 && value <= 250
    }

    private func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile)))
        return sorted[index]
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func lowestFiveMinuteAverageHeartRate(from samples: [HKQuantitySample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        var bestAverage: Double?

        for sample in sortedSamples {
            let windowEnd = sample.startDate.addingTimeInterval(5 * 60)
            let values = sortedSamples.compactMap { candidate -> Double? in
                guard candidate.startDate >= sample.startDate && candidate.startDate <= windowEnd else { return nil }
                return candidate.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            guard !values.isEmpty else { continue }
            let average = values.reduce(0, +) / Double(values.count)
            if bestAverage == nil || average < (bestAverage ?? .infinity) {
                bestAverage = average
            }
        }

        return bestAverage
    }

    private func fetchSleepAnchoredRecoveryHistory(
        stageSleepWindows: [Date: [(start: Date, end: Date)]],
        inBedSleepWindows: [Date: [(start: Date, end: Date)]],
        queryStart: Date,
        queryEnd: Date,
        mergeIntoExisting: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion?()
            return
        }

        Task {
            let result = await self.computeSleepAnchoredRecoveryHistory(
                stageSleepWindows: stageSleepWindows,
                inBedSleepWindows: inBedSleepWindows,
                queryStart: queryStart,
                queryEnd: queryEnd,
                hrvType: hrvType,
                heartRateType: heartRateType
            )

            await MainActor.run {
                var mergedNightlyAnchoredHRV = mergeIntoExisting ? self.nightlyAnchoredHRV : [:]
                for (day, value) in result {
                    mergedNightlyAnchoredHRV[day] = value.anchoredHRV
                }
                self.nightlyAnchoredHRV = mergedNightlyAnchoredHRV
                let sortedDays = self.nightlyAnchoredHRV.keys.sorted()
                var smoothedEffectHRV: [Date: Double] = [:]
                var previousEffectiveHRV: Double?
                for day in sortedDays {
                    guard let nightlyHRV = self.nightlyAnchoredHRV[day] else { continue }
                    let effectiveHRV = previousEffectiveHRV.map { (nightlyHRV * 0.4) + ($0 * 0.6) } ?? nightlyHRV
                    smoothedEffectHRV[day] = effectiveHRV
                    previousEffectiveHRV = effectiveHRV
                }
                self.effectHRV = smoothedEffectHRV
                var mergedBasalHeartRate = mergeIntoExisting ? self.basalSleepingHeartRate : [:]
                var mergedSleepDuration = mergeIntoExisting ? self.anchoredSleepDuration : [:]
                var mergedTimeInBed = mergeIntoExisting ? self.anchoredTimeInBed : [:]
                for (day, value) in result {
                    mergedBasalHeartRate[day] = value.basalHeartRate
                    mergedSleepDuration[day] = value.asleepHours
                    mergedTimeInBed[day] = value.timeInBedHours
                }
                self.basalSleepingHeartRate = mergedBasalHeartRate
                self.anchoredSleepDuration = mergedSleepDuration
                self.anchoredTimeInBed = mergedTimeInBed

                if let latestDay = result.keys.max(), let latest = result[latestDay] {
                    self.readinessHRV = latest.anchoredHRV
                    self.readinessEffectHRV = self.effectHRV[latestDay] ?? latest.anchoredHRV
                    self.readinessBasalHeartRate = latest.basalHeartRate
                    self.readinessSleepDuration = latest.asleepHours
                    self.readinessTimeInBed = latest.timeInBedHours
                    self.readinessSleepEfficiency = latest.sleepEfficiency
                    let sleepGoal = Self.personalizedSleepGoalHours(
                        sleepBaseline60Day: self.sleepBaseline60Day,
                        sleepBaseline7Day: self.sleepBaseline7Day,
                        currentSleep: latest.asleepHours
                    )
                    self.readinessSleepRatio = min(1.0, max(0.0, latest.asleepHours / max(sleepGoal, 0.1)))
                    self.latestHRV = latest.anchoredHRV ?? self.latestHRV
                    self.restingHeartRate = latest.basalHeartRate ?? self.restingHeartRate
                    self.sleepHours = latest.asleepHours
                }
                if let latestRecentWindow = result
                    .filter({ $0.key >= Calendar.current.startOfDay(for: Date().addingTimeInterval(-(15 * 60 * 60))) })
                    .max(by: { $0.value.asleepHours < $1.value.asleepHours }) {
                    self.lastSleepStart = latestRecentWindow.key
                    self.lastSleepEnd = latestRecentWindow.key.addingTimeInterval(latestRecentWindow.value.asleepHours * 3600)
                }
                self.scheduleScoresRefresh()
                completion?()
            }
        }
    }

    private func computeSleepAnchoredRecoveryHistory(
        stageSleepWindows: [Date: [(start: Date, end: Date)]],
        inBedSleepWindows: [Date: [(start: Date, end: Date)]],
        queryStart: Date,
        queryEnd: Date,
        hrvType: HKQuantityType,
        heartRateType: HKQuantityType
    ) async -> [Date: SleepAnchoredRecoveryDay] {
        let allWindows = stageSleepWindows.values.flatMap { $0 }
        guard !allWindows.isEmpty else { return [:] }

        let batchStart = allWindows.map(\.start).min() ?? queryStart
        let batchEnd = allWindows.map(\.end).max() ?? queryEnd
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        async let hrvSamplesTask: [HKQuantitySample] = withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: HKQuery.predicateForSamples(withStart: batchStart, end: batchEnd),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }

        async let hrSamplesTask: [HKQuantitySample] = withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: HKQuery.predicateForSamples(withStart: batchStart, end: batchEnd),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }

        let hrvSamples = await hrvSamplesTask
        let hrSamples = await hrSamplesTask

        var result: [Date: SleepAnchoredRecoveryDay] = [:]

        for (day, windows) in stageSleepWindows {
            guard let longestWindow = windows.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) else { continue }

            let finalThreeHourStart = max(longestWindow.start, longestWindow.end.addingTimeInterval(-(3 * 60 * 60)))
            let finalThreeHours = hrvSamples.filter { sample in
                sample.endDate > finalThreeHourStart && sample.startDate < longestWindow.end
            }
            let sedentaryFinalThreeHours = finalThreeHours.filter { sample in
                guard let raw = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber else { return false }
                return raw.intValue == HKHeartRateMotionContext.sedentary.rawValue
            }
            let wholeWindowHRVSamples = hrvSamples.filter { sample in
                sample.endDate > longestWindow.start && sample.startDate < longestWindow.end
            }
            let anchoredHRVSamples = !sedentaryFinalThreeHours.isEmpty ? sedentaryFinalThreeHours : (!finalThreeHours.isEmpty ? finalThreeHours : wholeWindowHRVSamples)
            let anchoredHRVValues = anchoredHRVSamples.map {
                $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            }.filter { isPlausibleHRV($0) }
            let anchoredHRV = median(anchoredHRVValues)

            let sleepHeartRateSamples = hrSamples.filter { sample in
                sample.endDate > longestWindow.start && sample.startDate < longestWindow.end
            }
            let basalHeartRate = lowestFiveMinuteAverageHeartRate(from: sleepHeartRateSamples)

            let asleepHours = longestWindow.end.timeIntervalSince(longestWindow.start) / 3600
            let inBedOverlapHours: Double = (inBedSleepWindows[day] ?? []).reduce(0) { partial, window in
                let overlapStart = max(window.start, longestWindow.start)
                let overlapEnd = min(window.end, longestWindow.end)
                let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
                return partial + (overlap / 3600)
            }
            let timeInBedHours = max(asleepHours, inBedOverlapHours)
            let sleepEfficiency = timeInBedHours > 0 ? min(1.0, max(0.0, asleepHours / timeInBedHours)) : 1.0

            result[day] = SleepAnchoredRecoveryDay(
                anchoredHRV: anchoredHRV,
                basalHeartRate: basalHeartRate,
                asleepHours: asleepHours,
                timeInBedHours: timeInBedHours,
                sleepEfficiency: sleepEfficiency
            )
        }

        return result
    }

    // MARK: - Vitals Fetch (respiratory rate, temp, SpO2, post-workout HR, VO2 max)
    private func fetchVitals(days: Int = 28) {
        fetchRespiratoryRate(days: days)
        fetchWristTemperature(days: days)
        fetchSpO2(days: days)

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
    private func fetchIntensityMetrics(days: Int = 28) {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return }
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
                self.scheduleScoresRefresh()
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Mindfulness
    private func fetchMindfulness(days: Int = 7) {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return
        }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: endDate)) else {
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(
            sampleType: mindfulType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, _ in
            guard let self else { return }
            
            let grouped = (samples as? [HKCategorySample] ?? []).reduce(into: [Date: Double]()) { partialResult, sample in
                let day = calendar.startOfDay(for: sample.startDate)
                partialResult[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
            }
            
            DispatchQueue.main.async {
                self.mindfulnessMinutesByDay = grouped
                self.scheduleScoresRefresh()
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
            dict = dailyRestingHeartRate
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
    @Published var dailyRestingHeartRate: [Date: Double] = [:]
    @Published var dailySleepDuration: [Date: Double] = [:]
    @Published var sleepHours: Double?         // hours
    @Published var activityLoad: Double = 0    // arbitrary training load
    @Published var hrvHistory: [Double] = []   // last 30 HRV values
    @Published var hrvSampleHistory: [HRVSamplePoint] = []
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
    @Published var hrvBaseline60Day: RollingBaselineStats?
    @Published var rhrBaseline60Day: RollingBaselineStats?
    @Published var sleepBaseline60Day: RollingBaselineStats?
    @Published var estimatedMaxHeartRate: Double = 190
    @Published var userAge: Double?
    @Published var acuteTrainingLoad: Double = 0
    @Published var chronicTrainingLoad: Double = 0
    @Published var trainingLoadRatio: Double = 0
    @Published var functionalOverreachingFlag: Bool = false
    
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

    struct HRVSamplePoint {
        let date: Date
        let value: Double
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

    struct RollingBaselineStats {
        let mean: Double
        let standardDeviation: Double
        let sampleCount: Int
    }

    struct ReadinessResult {
        let score: Int
        let confidence: Double
        let primaryDriver: String

        static let unavailable = ReadinessResult(
            score: 0,
            confidence: 0,
            primaryDriver: "Waiting for more health data"
        )
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

    struct ProRecoveryInputs {
        let hrvZScore: Double?
        let restingHeartRateZScore: Double?
        let restingHeartRatePenaltyZScore: Double?
        let sleepRatio: Double?
        let sleepScalar: Double?
        let sleepGoalHours: Double
        let sleepDurationHours: Double?
        let timeInBedHours: Double?
        let sleepEfficiency: Double?
        let composite: Double
        let baseRecoveryScore: Double
        let finalRecoveryScore: Double
        let sleepDebtPenalty: Double
        let circadianPenalty: Double
        let efficiencyCap: Double?
        let bedtimeVarianceMinutes: Double?
        let isInconclusive: Bool
    }

    struct RecoveryDebugSnapshot {
        let label: String
        let hrvZScore: Double
        let rhrPenaltyZScore: Double
        let sleepRatio: Double
        let sleepEfficiency: Double
        let bedtimeVarianceMinutes: Double
        let composite: Double
        let baseRecoveryScore: Double
        let circadianPenalty: Double
        let gatedRecoveryScore: Double
        let efficiencyCap: Double?
        let finalRecoveryScore: Double
    }

    struct StrainDebugSnapshot {
        let label: String
        let acuteLoad: Double
        let chronicLoad: Double
        let loadRatio: Double
        let logarithmicLoad: Double
        let expandedLoad: Double
        let ratioAdjustment: Double
        let preSoftCapScore: Double
        let softCappedScore: Double
        let finalStrainScore: Double
    }

    nonisolated static func estimateMaxHeartRateNes(age: Double?) -> Double {
        guard let age else { return 190 }
        return max(150, 211.0 - (0.64 * age))
    }

    nonisolated static func strainScoreUnitMaximum() -> Double { 21 }
    nonisolated static func passiveDailyBaseLoad(activeMinutes: Double? = nil) -> Double {
        0.1 * max(0, activeMinutes ?? 20)
    }

    nonisolated static func normalizedStrainPercent(from strainScore: Double) -> Double {
        let maxScore = strainScoreUnitMaximum()
        guard maxScore > 0 else { return 0 }
        return max(0, min(100, (strainScore / maxScore) * 100))
    }

    nonisolated static func proReadinessScore(
        recoveryScore: Double,
        strainScore: Double,
        hrvTrendComponent: Double
    ) -> Double {
        let normalizedStrain = normalizedStrainPercent(from: strainScore)
        let readiness = (recoveryScore * 0.70) + (hrvTrendComponent * 0.10) - (normalizedStrain * 0.25) + 25
        return max(0, min(100, readiness))
    }

    nonisolated static func proZoneWeight(for zoneNumber: Int) -> Double {
        switch zoneNumber {
        case 1: return 1.0
        case 2: return 2.0
        case 3: return 3.5
        case 4: return 5.0
        default: return 6.0
        }
    }

    nonisolated static func derivedZoneNumber(for heartRate: Double, maxHeartRate: Double) -> Int {
        let safeMax = max(maxHeartRate, 1)
        let percentMax = heartRate / safeMax
        switch percentMax {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    nonisolated static func fallbackWorkoutEffortScore(from workout: HKWorkout) -> Double? {
        guard let metadata = workout.metadata else { return nil }

        let preferredKeys = [
            "HKMetadataKeyWorkloadEffortScore",
            "HKMetadataKeyWorkoutEffortScore"
        ]

        for key in preferredKeys {
            if let value = metadata[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = metadata[key] as? Double {
                return value
            }
        }

        for (key, value) in metadata where key.localizedCaseInsensitiveContains("effort") {
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let doubleValue = value as? Double {
                return doubleValue
            }
        }

        return nil
    }

    nonisolated static func proWorkoutLoad(
        for workout: HKWorkout,
        analytics: WorkoutAnalytics,
        estimatedMaxHeartRate: Double
    ) -> Double {
        let zoneWeightedLoad = analytics.hrZoneBreakdown.reduce(0.0) { partial, entry in
            let zoneMinutes = entry.timeInZone / 60.0
            return partial + (zoneMinutes * proZoneWeight(for: entry.zone.zoneNumber))
        }

        if zoneWeightedLoad > 0 {
            return zoneWeightedLoad
        }

        let sortedHeartRates = analytics.heartRates.sorted { $0.0 < $1.0 }
        if !sortedHeartRates.isEmpty {
            var load = 0.0
            for index in sortedHeartRates.indices {
                let sample = sortedHeartRates[index]
                let nextDate = index < sortedHeartRates.count - 1
                    ? sortedHeartRates[index + 1].0
                    : min(workout.endDate, sample.0.addingTimeInterval(5))
                let seconds = max(0, min(nextDate.timeIntervalSince(sample.0), 30))
                let zoneNumber = derivedZoneNumber(for: sample.1, maxHeartRate: estimatedMaxHeartRate)
                load += (seconds / 60.0) * proZoneWeight(for: zoneNumber)
            }
            if load > 0 {
                return load
            }
        }

        let durationMinutes = workout.duration / 60.0
        if let effortScore = fallbackWorkoutEffortScore(from: workout) {
            return durationMinutes * max(1, effortScore)
        }

        if let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), durationMinutes > 0 {
            let intensity = energy / durationMinutes
            return durationMinutes * min(10, max(1, intensity / 8))
        }

        return 0
    }

    nonisolated static func ewmaLoad(_ values: ArraySlice<Double>, lambda: Double) -> Double {
        var average = 0.0
        for value in values {
            average = lambda * value + (1 - lambda) * average
        }
        return average
    }

    nonisolated static func proTrainingLoadState(
        loads: [Double],
        index: Int
    ) -> TrainingLoad {
        let sevenDayStart = max(0, index - 6)
        let acute = ewmaLoad(loads[sevenDayStart...index], lambda: 2.0 / 8.0)
        let chronic = ewmaLoad(loads[0...index], lambda: 2.0 / 29.0)
        let acwr = chronic > 0 ? acute / chronic : 0
        return TrainingLoad(acuteLoad: acute, chronicLoad: chronic, acwr: acwr)
    }

    nonisolated static func proStrainScore(
        acuteLoad: Double,
        chronicLoad: Double
    ) -> Double {
        debugStrainSnapshot(label: "Live", acuteLoad: acuteLoad, chronicLoad: chronicLoad).finalStrainScore
    }

    nonisolated static func debugStrainSnapshot(
        label: String,
        acuteLoad: Double,
        chronicLoad: Double
    ) -> StrainDebugSnapshot {
        let safeAcuteLoad = max(0, acuteLoad)
        let safeChronicLoad = max(0, chronicLoad)
        let logarithmicLoad = safeAcuteLoad > 0 ? 6.2 * log10(safeAcuteLoad + 1) : 0
        let expandedLoad = safeAcuteLoad > 0 ? pow(logarithmicLoad, 1.08) : 0
        let loadRatio = safeChronicLoad > 0 ? safeAcuteLoad / safeChronicLoad : 1
        let ratioAdjustment = max(-1.5, min(4.5, 8.0 * (loadRatio - 1.0)))
        let preSoftCapScore = expandedLoad + ratioAdjustment
        let safePreSoftCapScore = max(0, preSoftCapScore)
        let softCappedScore = 21.0 * (1.0 - exp(-(safePreSoftCapScore / 18.0)))
        let finalStrainScore = max(0, min(strainScoreUnitMaximum(), softCappedScore + 0.5))

        return StrainDebugSnapshot(
            label: label,
            acuteLoad: safeAcuteLoad,
            chronicLoad: safeChronicLoad,
            loadRatio: loadRatio,
            logarithmicLoad: logarithmicLoad,
            expandedLoad: expandedLoad,
            ratioAdjustment: ratioAdjustment,
            preSoftCapScore: preSoftCapScore,
            softCappedScore: softCappedScore,
            finalStrainScore: finalStrainScore
        )
    }

    nonisolated static func fallbackStats(
        mean: Double?,
        coefficientOfVariation: Double,
        minimumStandardDeviation: Double
    ) -> RollingBaselineStats? {
        guard let mean else { return nil }
        let standardDeviation = max(abs(mean) * coefficientOfVariation, minimumStandardDeviation)
        return RollingBaselineStats(mean: mean, standardDeviation: standardDeviation, sampleCount: 7)
    }

    nonisolated static func clampedStats(
        _ stats: RollingBaselineStats?,
        minimumStandardDeviation: Double
    ) -> RollingBaselineStats? {
        guard let stats else { return nil }
        return RollingBaselineStats(
            mean: stats.mean,
            standardDeviation: max(stats.standardDeviation, minimumStandardDeviation),
            sampleCount: stats.sampleCount
        )
    }

    nonisolated static func zScore(
        current: Double,
        stats: RollingBaselineStats?
    ) -> Double? {
        guard let stats else { return nil }
        let denominator = stats.standardDeviation > 0.0001 ? stats.standardDeviation : max(abs(stats.mean) * 0.05, 0.1)
        return (current - stats.mean) / denominator
    }

    nonisolated static func personalizedSleepGoalHours(
        sleepBaseline60Day: RollingBaselineStats?,
        sleepBaseline7Day: Double?,
        currentSleep: Double?
    ) -> Double {
        let fallback = currentSleep ?? 8
        return min(9.5, max(7.0, sleepBaseline60Day?.mean ?? sleepBaseline7Day ?? fallback))
    }

    nonisolated static func circularStandardDeviationMinutes(from sleepStartHours: [Date: Double], around day: Date, windowDays: Int = 7) -> Double? {
        let calendar = Calendar.current
        let hours = (0..<windowDays).compactMap { offset -> Double? in
            guard let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) else { return nil }
            let normalizedDay = calendar.startOfDay(for: sourceDay)
            return sleepStartHours[normalizedDay]
        }
        guard !hours.isEmpty else { return nil }
        let radians = hours.map { (($0.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)) / 24.0 * (2.0 * Double.pi) }
        let sinMean = radians.map { Foundation.sin($0) }.reduce(0, +) / Double(radians.count)
        let cosMean = radians.map { Foundation.cos($0) }.reduce(0, +) / Double(radians.count)
        let resultantLength = sqrt((sinMean * sinMean) + (cosMean * cosMean))

        guard resultantLength > 0 else { return 12 * 60 }

        let circularStandardDeviationRadians = sqrt(max(0, -2.0 * log(resultantLength)))
        return circularStandardDeviationRadians * (24.0 / (2.0 * Double.pi)) * 60.0
    }

    nonisolated static func smoothedValue(
        for day: Date,
        values: [Date: Double],
        weights: [Double] = [0.6, 0.3, 0.1]
    ) -> Double? {
        let calendar = Calendar.current
        var weightedSum = 0.0
        var totalWeight = 0.0

        for (offset, weight) in weights.enumerated() {
            guard let sourceDay = calendar.date(byAdding: .day, value: -offset, to: day) else { continue }
            let normalizedSourceDay = calendar.startOfDay(for: sourceDay)
            guard let value = values[normalizedSourceDay] else { continue }
            weightedSum += value * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    nonisolated static func proRecoveryInputs(
        latestHRV: Double?,
        restingHeartRate: Double?,
        sleepDurationHours: Double?,
        timeInBedHours: Double?,
        hrvBaseline60Day: RollingBaselineStats?,
        rhrBaseline60Day: RollingBaselineStats?,
        sleepBaseline60Day: RollingBaselineStats?,
        hrvBaseline7Day: Double?,
        rhrBaseline7Day: Double?,
        sleepBaseline7Day: Double?,
        bedtimeVarianceMinutes: Double? = nil
    ) -> ProRecoveryInputs {
        let validatedHRV: Double? = {
            guard let latestHRV else { return nil }
            return (latestHRV > 0 && latestHRV <= 250) ? latestHRV : nil
        }()
        let transformedHRVMean = (hrvBaseline60Day?.mean ?? hrvBaseline7Day).map { log(max($0, 1)) }
        let transformedHRVSD: Double? = {
            let baseMean = hrvBaseline60Day?.mean ?? hrvBaseline7Day
            let baseSD = hrvBaseline60Day?.standardDeviation
            guard let baseMean else { return nil }
            let softFloor = max(baseMean * 0.12, 1.0)
            if let baseSD, baseMean > 0 {
                return max(baseSD / baseMean, softFloor / baseMean)
            }
            return softFloor / max(baseMean, 1.0)
        }()
        let hrvStats = transformedHRVMean.flatMap { mean in
            transformedHRVSD.map { RollingBaselineStats(mean: mean, standardDeviation: $0, sampleCount: hrvBaseline60Day?.sampleCount ?? 7) }
        }
        let rhrStats = clampedStats(
            rhrBaseline60Day ?? fallbackStats(mean: rhrBaseline7Day, coefficientOfVariation: 0.06, minimumStandardDeviation: 3),
            minimumStandardDeviation: 3
        )
        let sleepGoalHours = personalizedSleepGoalHours(
            sleepBaseline60Day: sleepBaseline60Day,
            sleepBaseline7Day: sleepBaseline7Day,
            currentSleep: sleepDurationHours
        )

        let hrvZ = validatedHRV.flatMap { value in
            let logValue = log(max(value, 1))
            return zScore(current: logValue, stats: hrvStats)
        }
        let rhrZ = restingHeartRate.flatMap { zScore(current: $0, stats: rhrStats) }
        let rhrPenaltyZ: Double? = { () -> Double? in
            guard
                let restingHeartRate,
                let rhrStats
            else { return nil }
            guard restingHeartRate > rhrStats.mean else { return 0 }
            return zScore(current: restingHeartRate, stats: rhrStats)
        }()
        let sleepEfficiency: Double? = { () -> Double? in
            guard let sleepDurationHours, let timeInBedHours, timeInBedHours > 0 else { return nil }
            return min(1.0, max(0.0, sleepDurationHours / timeInBedHours))
        }()
        let sleepRatio = sleepDurationHours.map { min(1.0, max(0.0, $0 / max(sleepGoalHours, 0.1))) }
        let sleepScalar = sleepRatio.map { 0.85 + (0.15 * $0) }
        let composite = ((hrvZ ?? 0) * 0.85) - ((rhrPenaltyZ ?? 0) * 0.25)
        let baseRecoveryScore = normalizedCompositeScore(from: composite)
        let sleepDebtPenalty = 0.0
        let circadianPenalty: Double = {
            let variance = bedtimeVarianceMinutes ?? 0
            guard variance > 90 else { return 0 }
            return min(10.0, (variance - 90.0) * 0.1)
        }()
        let afterPenalties = max(0, baseRecoveryScore - sleepDebtPenalty - circadianPenalty)
        let gatedRecovery = max(0, min(100, afterPenalties * (sleepScalar ?? 1.0)))
        let efficiencyCap = ((sleepEfficiency ?? 1.0) < 0.85) ? 70.0 : nil
        let finalRecoveryScore = min(gatedRecovery, efficiencyCap ?? gatedRecovery)
        let isInconclusive = latestHRV != nil && validatedHRV == nil

        return ProRecoveryInputs(
            hrvZScore: hrvZ,
            restingHeartRateZScore: rhrZ,
            restingHeartRatePenaltyZScore: rhrPenaltyZ,
            sleepRatio: sleepRatio,
            sleepScalar: sleepScalar,
            sleepGoalHours: sleepGoalHours,
            sleepDurationHours: sleepDurationHours,
            timeInBedHours: timeInBedHours,
            sleepEfficiency: sleepEfficiency,
            composite: composite,
            baseRecoveryScore: baseRecoveryScore,
            finalRecoveryScore: finalRecoveryScore,
            sleepDebtPenalty: sleepDebtPenalty,
            circadianPenalty: circadianPenalty,
            efficiencyCap: efficiencyCap,
            bedtimeVarianceMinutes: bedtimeVarianceMinutes,
            isInconclusive: isInconclusive
        )
    }

    nonisolated static func normalizedCompositeScore(from composite: Double) -> Double {
        let calibrationOffset = 1.6
        let normalized = (1.0 / (1.0 + exp(-0.6 * (composite + calibrationOffset)))) * 100
        return max(0, min(100, normalized))
    }

    nonisolated static func debugRecoverySnapshot(
        label: String,
        hrvZScore: Double,
        rhrPenaltyZScore: Double,
        sleepRatio: Double = 1.0,
        sleepEfficiency: Double = 1.0,
        bedtimeVarianceMinutes: Double = 0
    ) -> RecoveryDebugSnapshot {
        let normalizedSleepRatio = max(0, min(1, sleepRatio))
        let normalizedSleepEfficiency = max(0, min(1, sleepEfficiency))
        let sleepScalar = 0.85 + (0.15 * normalizedSleepRatio)
        let composite = (hrvZScore * 0.85) - (rhrPenaltyZScore * 0.25)
        let baseRecoveryScore = normalizedCompositeScore(from: composite)
        let circadianPenalty = bedtimeVarianceMinutes > 90
            ? min(10.0, (bedtimeVarianceMinutes - 90.0) * 0.1)
            : 0.0
        let afterPenalties = max(0, baseRecoveryScore - circadianPenalty)
        let gatedRecoveryScore = max(0, min(100, afterPenalties * sleepScalar))
        let efficiencyCap = normalizedSleepEfficiency < 0.85 ? 70.0 : nil
        let finalRecoveryScore = min(gatedRecoveryScore, efficiencyCap ?? gatedRecoveryScore)

        return RecoveryDebugSnapshot(
            label: label,
            hrvZScore: hrvZScore,
            rhrPenaltyZScore: rhrPenaltyZScore,
            sleepRatio: normalizedSleepRatio,
            sleepEfficiency: normalizedSleepEfficiency,
            bedtimeVarianceMinutes: bedtimeVarianceMinutes,
            composite: composite,
            baseRecoveryScore: baseRecoveryScore,
            circadianPenalty: circadianPenalty,
            gatedRecoveryScore: gatedRecoveryScore,
            efficiencyCap: efficiencyCap,
            finalRecoveryScore: finalRecoveryScore
        )
    }

    nonisolated static func proRecoveryScore(from inputs: ProRecoveryInputs) -> Double {
        max(0, min(100, inputs.finalRecoveryScore))
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
    private var scoreRefreshTask: Task<Void, Never>?
    private var lastMetricsRefreshAt: Date?
    private var activeWorkoutRefreshDays: Int?
    private var hasStartedInitialDifferentialRefresh = false
    private var smartDifferentialRefreshTask: Task<Void, Never>?
    private var historicalBatchLoadTask: Task<Void, Never>?
    private let metricsRefreshCooldown: TimeInterval = 20
    private let startupWorkoutCoverageDays = 42
    private let allowsAutomaticHistoricalBatchLoading = false

    // MARK: - Initialization

    init() {
        // Load persistent cache on startup (synchronously)
        loadPersistentCache()
        hydrateMetricsFromCacheIfAvailable()
        cloudSnapshotObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.isAppActive else { return }
            guard let snapshot = self.loadMetricsSnapshotFromCloud() else { return }
            if let cachedMetricsUpdatedAt = self.cachedMetricsUpdatedAt,
               cachedMetricsUpdatedAt >= snapshot.updatedAt {
                return
            }
            self.applyMetricsSnapshot(snapshot)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Let the app render its first frame before we kick off heavier health bootstrap work.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.initializeWithCachedData()

            // Stagger authorization-driven metric refresh slightly so launch feels responsive.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            if Self.usesAggregatedCloudHealthPath {
                await self.reloadAggregatedHealthSnapshotFromICloud()
                self.scheduleScoresRefresh()
                self.scheduleMetricsSnapshotSave(delayNanoseconds: 400_000_000)
                return
            }

            self.hkManager.requestAuthorization { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        guard let self else { return }
                        if self.requiresInitialFullSync {
                            self.refreshAllMetrics(force: true)
                        } else {
                            self.refreshStartupMetrics()
                        }
                        self.scheduleStartupWorkoutCoverageSync()
                    } else {
                        print("HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
        }
    }

    deinit {
        workoutCloudUploadTask?.cancel()
        if let cloudSnapshotObserver {
            NotificationCenter.default.removeObserver(cloudSnapshotObserver)
        }
    }

    func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        if scenePhase == .active {
            isAppActive = true
            foregroundResumeTask?.cancel()
            foregroundResumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, !Task.isCancelled, self.isAppActive else { return }
                self.refreshStartupMetrics()
                self.scheduleStartupWorkoutCoverageSync()
            }
            return
        }

        guard scenePhase == .background else { return }

        isAppActive = false

        foregroundResumeTask?.cancel()
        startupWorkoutCoverageTask?.cancel()
        workoutCloudUploadTask?.cancel()
        isSyncingStartupWorkoutCoverage = false
        scoreRefreshTask?.cancel()
        metricsSnapshotSaveTask?.cancel()
        metricsSnapshotWriteTask?.cancel()
        metricsRefreshCompletionTask?.cancel()
        smartDifferentialRefreshTask?.cancel()
        historicalBatchLoadTask?.cancel()

        isRefreshingCachedMetrics = false

        #if !targetEnvironment(macCatalyst)
        Task { [weak self] in
            await self?.pushFrozenEngineHandoffToCloudKit()
        }
        #endif
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

    func refreshAllMetrics(force: Bool = false) {
        if !force, AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            return
        }

        if !force,
           let lastMetricsRefreshAt,
           Date().timeIntervalSince(lastMetricsRefreshAt) < metricsRefreshCooldown {
            return
        }
        lastMetricsRefreshAt = Date()
        beginBackgroundMetricsRefreshWindow()

        if Self.usesAggregatedCloudHealthPath {
            Task { [weak self] in
                await self?.reloadAggregatedHealthSnapshotFromICloud()
                self?.scheduleScoresRefresh()
                self?.scheduleMetricsSnapshotSave(delayNanoseconds: 500_000_000)
            }
            return
        }

        // All fetches are now on the main actor
        self.fetchLatestHRV()
        self.fetchHRVHistory(days: longTermLookbackDays)
        self.fetchRestingHeartRate()
        self.fetchRestingHeartRateHistory(days: longTermLookbackDays)
        self.fetchSleep()
        self.fetchBaselines()
        self.fetchTrainingLoad()
        self.fetchSleepQuality(days: longTermLookbackDays)
        self.fetchMindfulness(days: 7)
        print("[refreshAllMetrics] calling fetchVitals...")
        self.fetchVitals(days: longTermLookbackDays)
        self.fetchIntensityMetrics(days: longTermLookbackDays)
        self.inferFavoriteSportAndFrequency()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let age = await self.hkManager.fetchAgeAsync()
            self.userAge = age
            self.estimatedMaxHeartRate = Self.estimateMaxHeartRateNes(age: age)
            self.scheduleScoresRefresh()
            self.scheduleMetricsSnapshotSave()
        }
        self.updateScores()
        self.scheduleMetricsSnapshotSave(delayNanoseconds: 2_000_000_000)
    }

    func refreshStartupMetrics(force: Bool = false) {
        if !force, AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            return
        }

        if !force,
           let lastMetricsRefreshAt,
           Date().timeIntervalSince(lastMetricsRefreshAt) < metricsRefreshCooldown {
            return
        }
        lastMetricsRefreshAt = Date()
        beginBackgroundMetricsRefreshWindow()

        if Self.usesAggregatedCloudHealthPath {
            Task { [weak self] in
                await self?.reloadAggregatedHealthSnapshotFromICloud()
                self?.scheduleScoresRefresh()
                self?.scheduleMetricsSnapshotSave(delayNanoseconds: 400_000_000)
            }
            return
        }

        // Startup should only refresh lightweight, user-visible summary metrics.
        self.fetchLatestHRV()
        self.fetchRestingHeartRate()
        self.fetchSleep()
        self.fetchBaselines()
        self.fetchTrainingLoad()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let age = await self.hkManager.fetchAgeAsync()
            self.userAge = age
            self.estimatedMaxHeartRate = Self.estimateMaxHeartRateNes(age: age)
            self.scheduleScoresRefresh()
            self.scheduleMetricsSnapshotSave()
        }

        self.updateScores()
        self.scheduleMetricsSnapshotSave(delayNanoseconds: 1_000_000_000)
    }
    
    private func scheduleScoresRefresh() {
        scoreRefreshTask?.cancel()
        scoreRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.updateScores()
            self.scheduleMetricsSnapshotSave()
        }
    }

    private func scheduleStartupWorkoutCoverageSync() {
        if Self.usesAggregatedCloudHealthPath { return }
        startupWorkoutCoverageTask?.cancel()
        startupWorkoutCoverageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled, self.isAppActive else { return }
            self.isSyncingStartupWorkoutCoverage = true
            defer { self.isSyncingStartupWorkoutCoverage = false }
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -startupWorkoutCoverageDays, to: end) ?? end
            await self.ensureWorkoutAnalyticsCoverage(from: start, to: end)
        }
    }

    /// Refresh workout analytics with smart caching
    /// Only fetches from HealthKit if cache is stale or days range changed
    func refreshWorkoutAnalytics(days: Int = 30, forceRefresh: Bool = false) async {
        if !forceRefresh, AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            return
        }

        if Self.usesAggregatedCloudHealthPath {
            if forceRefresh {
                await reloadAggregatedHealthSnapshotFromICloud(userInitiatedRefresh: true)
                scheduleMetricsSnapshotSave()
            } else {
                let cachedEntries = loadPersistedWorkoutAnalyticsEntries()
                if !cachedEntries.isEmpty {
                    workoutAnalytics = rebuildWorkoutAnalytics(from: cachedEntries)
                    workoutAnalyticsCacheTimestamp = Date()
                    lastCachedWorkoutDate = cachedEntries.map(\.workoutStartDate).max()
                    earliestRequestedWorkoutDate = cachedEntries.map(\.workoutStartDate).min()
                    hasInitializedWorkoutAnalytics = true
                    scheduleScoresRefresh()
                    scheduleMetricsSnapshotSave()
                } else {
                    hasInitializedWorkoutAnalytics = true
                }
            }
            return
        }

        if !forceRefresh, activeWorkoutRefreshDays == days {
            return
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end

        if !forceRefresh,
           !workoutAnalytics.isEmpty,
           !needsWorkoutAnalyticsCoverage(from: start, to: end),
           !workoutAnalyticsNeedsSeriesBackfill(workoutAnalytics) {
            workoutAnalyticsCacheTimestamp = Date()
            lastCacheDaysRequested = days
            hasInitializedWorkoutAnalytics = true
            return
        }

        // Check if cache is still valid
        if !forceRefresh && isCacheValid(for: days) {
            return // Use cached data
        }

        activeWorkoutRefreshDays = days
        defer {
            if activeWorkoutRefreshDays == days {
                activeWorkoutRefreshDays = nil
            }
        }

        let analytics = await hkManager.fetchWorkoutsWithAnalytics(
            from: start,
            to: end,
            allowDuringForegroundCritical: forceRefresh
        )
        self.workoutAnalytics = analytics
        self.workoutAnalyticsCacheTimestamp = Date()
        self.lastCacheDaysRequested = days
        self.earliestRequestedWorkoutDate = start
        self.lastCachedWorkoutDate = analytics.map { $0.workout.startDate }.max()
        self.hasInitializedWorkoutAnalytics = true // Mark initial load complete
        savePersistentCacheMetadata(analytics)
        scheduleScoresRefresh()
        scheduleMetricsSnapshotSave()
    }
    
    /// Check if the current cache is valid
    private func isCacheValid(for requestedDays: Int) -> Bool {
        // Cache is invalid if:
        // 1. Never been fetched
        // 2. Requested days range changed
        // 3. Cache has expired (older than cacheValidityDuration)
        guard let timestamp = workoutAnalyticsCacheTimestamp else { return false }
        guard requestedDays == lastCacheDaysRequested else { return false }
        guard !workoutAnalyticsNeedsSeriesBackfill(workoutAnalytics) else { return false }
        return Date().timeIntervalSince(timestamp) < cacheValidityDuration
    }
    
    /// Force refresh from HealthKit (bypasses cache)
    func forceRefreshWorkoutAnalytics(days: Int = 30) async {
        await refreshWorkoutAnalytics(days: days, forceRefresh: true)
    }
    
    // MARK: - Persistent Cache & Smart Differential Refresh
    
    /// Load cached workouts from disk synchronously - no blocking, immediate HealthKit fetch
    func initializeWithCachedData() {
        guard !hasStartedInitialDifferentialRefresh else { return }
        hasStartedInitialDifferentialRefresh = true

        if Self.usesAggregatedCloudHealthPath {
            let cachedEntries = loadPersistedWorkoutAnalyticsEntries()
            if !cachedEntries.isEmpty {
                self.lastCachedWorkoutDate = cachedEntries.map(\.workoutStartDate).max()
                self.earliestRequestedWorkoutDate = cachedEntries.map(\.workoutStartDate).min()
                self.workoutAnalytics = rebuildWorkoutAnalytics(from: cachedEntries)
                self.workoutAnalyticsCacheTimestamp = Date()
                self.requiresInitialFullSync = false
                self.hasInitializedWorkoutAnalytics = true
                self.scheduleScoresRefresh()
                print("[Cache] Mac Catalyst: loaded \(cachedEntries.count) workouts from disk cache (HealthKit disabled).")
            } else {
                self.requiresInitialFullSync = false
                self.hasInitializedWorkoutAnalytics = true
                print("[Cache] Mac Catalyst: no workout disk cache; use iPhone to sync or open app on iOS first.")
            }
            if hasHydratedCachedMetrics {
                scheduleMetricsSnapshotSave()
            }
            return
        }

        let cachedEntries = loadPersistedWorkoutAnalyticsEntries()
        let cachedSummaries = cachedEntries.map { entry in
            CachedWorkoutSummary(
                startDate: entry.workoutStartDate,
                endDate: entry.workoutEndDate,
                duration: entry.workoutDuration,
                workoutType: HKWorkoutActivityType(rawValue: entry.workoutTypeRawValue)?.name ?? "other",
                metTotal: entry.metTotal ?? 0,
                vo2Max: entry.vo2Max,
                avgHR: entry.heartRates.map(\.value).average ?? 0,
                peakHR: entry.peakHR,
                totalKcal: entry.totalEnergyBurnedKilocalories ?? 0,
                distance: entry.totalDistanceMeters ?? 0
            )
        }
        
        if !cachedSummaries.isEmpty {
            self.lastCachedWorkoutDate = cachedSummaries.map { $0.startDate }.max()
            self.earliestRequestedWorkoutDate = cachedSummaries.map { $0.startDate }.min()
            self.workoutAnalytics = rebuildWorkoutAnalytics(from: cachedEntries)
            self.workoutAnalyticsCacheTimestamp = Date()
            self.requiresInitialFullSync = false
            print("[Cache] ✅ Found cached data for \(cachedSummaries.count) workouts (latest: \(self.lastCachedWorkoutDate?.formatted() ?? "unknown"))")
            self.hasInitializedWorkoutAnalytics = true
            self.scheduleScoresRefresh()
        } else {
            self.requiresInitialFullSync = true
            print("[Cache] No cached workouts found, will fetch all from HealthKit")
            smartDifferentialRefreshTask?.cancel()
            smartDifferentialRefreshTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }
                await self.smartDifferentialRefresh(totalDays: self.longTermLookbackDays)
            }
        }

        if hasHydratedCachedMetrics {
            scheduleMetricsSnapshotSave()
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
        if Self.usesAggregatedCloudHealthPath { return }
        let endDate = Date()
        let totalStartDate = Calendar.current.date(byAdding: .day, value: -totalDays, to: endDate) ?? endDate
        
        // Startup policy: trust cached history and only fetch workouts newer than the
        // latest cached workout. Historical edits/deletes are handled by explicit refresh.
        if let cachedDate = lastCachedWorkoutDate {
            let incrementalStart = cachedDate.addingTimeInterval(1)
            guard incrementalStart < endDate else {
                self.hasNewDataAvailable = false
                return
            }

            print("[Cache] Loading workouts newer than cached latest date...")
            let newWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: incrementalStart, to: endDate)
            guard !Task.isCancelled else { return }

            if !newWorkouts.isEmpty {
                var mergedByID = Dictionary(uniqueKeysWithValues: workoutAnalytics.map { (canonicalWorkoutID(for: $0.workout), $0) })
                for workout in newWorkouts {
                    mergedByID[canonicalWorkoutID(for: workout.workout)] = workout
                }

                let merged = mergedByID.values.sorted { lhs, rhs in
                    lhs.workout.startDate > rhs.workout.startDate
                }

                self.workoutAnalytics = merged
                self.workoutAnalyticsCacheTimestamp = Date()
                self.lastCachedWorkoutDate = merged.map { $0.workout.startDate }.max()
                self.earliestRequestedWorkoutDate = merged.map { $0.workout.startDate }.min()
                self.hasNewDataAvailable = false
                savePersistentCacheMetadata(merged)
                scheduleScoresRefresh()
                scheduleMetricsSnapshotSave()
                print("[Cache] ✅ Appended \(newWorkouts.count) new workouts without recomputing cached history")
            } else {
                self.workoutAnalyticsCacheTimestamp = Date()
                self.hasNewDataAvailable = false
                print("[Cache] No new workouts found beyond cached history")
            }
            return
        }
        
        // FALLBACK: If no cached date (first run), load all data from HealthKit
        // This only happens on very first app launch
        print("[Cache] First run: fetching full 10-year workout history from HealthKit")
        if workoutAnalytics.isEmpty {
            let historicalWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: totalStartDate, to: endDate)

            self.workoutAnalytics = historicalWorkouts
            self.workoutAnalyticsCacheTimestamp = Date()
            self.lastCacheDaysRequested = totalDays
            self.lastCachedWorkoutDate = historicalWorkouts.map { $0.workout.startDate }.max()
            self.earliestRequestedWorkoutDate = historicalWorkouts.map { $0.workout.startDate }.min() ?? totalStartDate
            self.hasInitializedWorkoutAnalytics = true
            self.requiresInitialFullSync = false
            savePersistentCacheMetadata(historicalWorkouts)
            scheduleMetricsSnapshotSave()
            
            print("[Cache] ✅ Initial load: \(historicalWorkouts.count) workouts cached across 10 years")
            return
        }
        
        // Fallback path when in-memory state exists but we do not have a cached latest date.
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
            scheduleMetricsSnapshotSave()
        }
        
        if !hasDataChanges {
            self.hasNewDataAvailable = false
        }
    }

    private func scheduleHistoricalBatchLoad(from earliestDate: Date, to latestDate: Date, batchSize: Int) {
        historicalBatchLoadTask?.cancel()
        historicalBatchLoadTask = Task { [weak self] in
            await self?.batchLoadHistoricalWorkouts(from: earliestDate, to: latestDate, batchSize: batchSize)
        }
    }
    
    /// Batch-load historical workouts in chunks (non-blocking, progressive population)
    /// Loads data backwards in time: from newest unfetched to oldest
    /// This ensures batches append naturally to the view in chronological order
    private func batchLoadHistoricalWorkouts(from earliestDate: Date, to latestDate: Date, batchSize: Int = 30) async {
        if Self.usesAggregatedCloudHealthPath { return }
        print("[Cache] Starting batch historical load: \(earliestDate.formatted()) to \(latestDate.formatted())")
        
        // Start from latest (most recent unfetched) and work backwards
        var currentEnd = latestDate
        var batchCount = 0
        
        while currentEnd > earliestDate {
            let currentStart = Calendar.current.date(byAdding: .day, value: -batchSize, to: currentEnd) ?? earliestDate
            let batchStart = max(currentStart, earliestDate)
            
            print("[Cache] Loading batch \(batchCount + 1): \(batchStart.formatted()) to \(currentEnd.formatted())")
            
            let batchWorkouts = await hkManager.fetchWorkoutsWithAnalytics(from: batchStart, to: currentEnd)
            guard !Task.isCancelled else { break }
            
            if !batchWorkouts.isEmpty {
                self.workoutAnalytics.append(contentsOf: batchWorkouts)
                self.savePersistentCacheMetadata(self.workoutAnalytics)
                self.scheduleMetricsSnapshotSave()
                print("[Cache] ✅ Batch \(batchCount + 1) complete: +\(batchWorkouts.count) workouts (total: \(self.workoutAnalytics.count))")
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
        if Self.usesAggregatedCloudHealthPath {
            await reloadAggregatedHealthSnapshotFromICloud(userInitiatedRefresh: true)
            scheduleMetricsSnapshotSave()
            return
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let analytics = await hkManager.fetchWorkoutsWithAnalytics(from: start, to: end)
        
        self.workoutAnalytics = analytics
        self.workoutAnalyticsCacheTimestamp = Date()
        self.lastCacheDaysRequested = days
        self.lastCachedWorkoutDate = analytics.map { $0.workout.startDate }.max()
        self.earliestRequestedWorkoutDate = start
        self.hasNewDataAvailable = false

        // Save fresh copy
        savePersistentCacheMetadata(analytics)
        scheduleScoresRefresh()
        scheduleMetricsSnapshotSave()
    }

    func clearWorkoutAnalyticsCache() {
        historicalBatchLoadTask?.cancel()
        smartDifferentialRefreshTask?.cancel()
        allWorkoutHRCache = []
        analyticsCache = []
        stagedWorkoutAnalytics = []
        workoutAnalytics = []
        workoutAnalyticsCacheTimestamp = nil
        lastCacheDaysRequested = 0
        lastCachedWorkoutDate = nil
        earliestRequestedWorkoutDate = nil
        hasInitializedWorkoutAnalytics = false
        hasNewDataAvailable = false

        if let url = persistentCacheURL() {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = metricsSnapshotURL() {
            try? FileManager.default.removeItem(at: url)
        }
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.removeObject(forKey: metricsSnapshotCloudKey)
    }

    func needsWorkoutAnalyticsCoverage(from start: Date, to end: Date) -> Bool {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        let latestCoveredDate = lastCachedWorkoutDate ?? workoutAnalytics.map { $0.workout.startDate }.max()

        if let earliestRequestedWorkoutDate, let latestCoveredDate {
            if normalizedStart < calendar.startOfDay(for: earliestRequestedWorkoutDate) {
                return true
            }

            // When cached analytics were refreshed today, treat the current day as covered
            // so simply opening a screen does not retrigger expensive HRR analytics work.
            if hasInitializedWorkoutAnalytics,
               let workoutAnalyticsCacheTimestamp,
               calendar.isDate(workoutAnalyticsCacheTimestamp, inSameDayAs: Date()),
               !workoutAnalyticsNeedsSeriesBackfill(workoutAnalytics) {
                return false
            }

            return normalizedEnd > calendar.startOfDay(for: latestCoveredDate)
        }

        return true
    }

    func ensureWorkoutAnalyticsCoverage(from start: Date, to end: Date, forceFetch: Bool = false) async {
        if Self.usesAggregatedCloudHealthPath {
            await reloadAggregatedHealthSnapshotFromICloud()
            scheduleScoresRefresh()
            return
        }
        let normalizedStart = Calendar.current.startOfDay(for: start)
        let normalizedEnd = min(end, Date())
        guard normalizedStart < normalizedEnd else { return }
        guard forceFetch || needsWorkoutAnalyticsCoverage(from: normalizedStart, to: normalizedEnd) else { return }

        let fetched = await hkManager.fetchWorkoutsWithAnalytics(
            from: normalizedStart,
            to: normalizedEnd,
            allowDuringForegroundCritical: true
        )
        var mergedByID = Dictionary(uniqueKeysWithValues: workoutAnalytics.map { (canonicalWorkoutID(for: $0.workout), $0) })
        for workout in fetched {
            mergedByID[canonicalWorkoutID(for: workout.workout)] = workout
        }

        let merged = mergedByID.values.sorted { lhs, rhs in
            lhs.workout.startDate > rhs.workout.startDate
        }

        workoutAnalytics = merged
        workoutAnalyticsCacheTimestamp = Date()
        earliestRequestedWorkoutDate = min(earliestRequestedWorkoutDate ?? normalizedStart, normalizedStart)
        lastCachedWorkoutDate = max(lastCachedWorkoutDate ?? normalizedEnd, merged.map { $0.workout.startDate }.max() ?? normalizedEnd)
        hasInitializedWorkoutAnalytics = true
        savePersistentCacheMetadata(merged)
        scheduleScoresRefresh()
        scheduleMetricsSnapshotSave()
    }

    func ensureFullWorkoutHistoryCoverage() async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -longTermLookbackDays, to: end) ?? end
        await ensureWorkoutAnalyticsCoverage(from: start, to: end)
    }

    func ensureFullSpO2Coverage() async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -longTermLookbackDays, to: end) ?? end
        await ensureSpO2Coverage(from: start, to: end)
    }

    private func needsCoverage<T>(for values: [Date: T], from start: Date, to end: Date) -> Bool {
        let normalizedStart = Calendar.current.startOfDay(for: start)
        let normalizedEnd = Calendar.current.startOfDay(for: end)
        let coveredDates = values.keys.sorted()

        guard let earliest = coveredDates.first, let latest = coveredDates.last else {
            return true
        }

        return normalizedStart < earliest || normalizedEnd > latest
    }

    func needsRecoveryMetricsCoverage(from start: Date, to end: Date) -> Bool {
        needsCoverage(for: Dictionary(uniqueKeysWithValues: dailyHRV.map { ($0.date, $0.average) }), from: start, to: end)
            || needsCoverage(for: dailyRestingHeartRate, from: start, to: end)
            || needsCoverage(for: sleepStages, from: start, to: end)
            || needsCoverage(for: respiratoryRate, from: start, to: end)
            || needsCoverage(for: wristTemperature, from: start, to: end)
            || needsCoverage(for: spO2, from: start, to: end)
            || needsCoverage(for: dailySleepHeartRate, from: start, to: end)
    }

    func needsSpO2Coverage(from start: Date, to end: Date) -> Bool {
        needsCoverage(for: spO2, from: start, to: end)
    }

    func ensureSpO2Coverage(from start: Date, to end: Date) async {
        if Self.usesAggregatedCloudHealthPath {
            await reloadAggregatedHealthSnapshotFromICloud()
            return
        }
        let normalizedStart = Calendar.current.startOfDay(for: start)
        let normalizedEnd = min(end, Date())
        guard normalizedStart < normalizedEnd else { return }
        guard needsSpO2Coverage(from: normalizedStart, to: normalizedEnd) else { return }

        let fetched = await hkManager.fetchDailyOxygenSaturation(from: normalizedStart, to: normalizedEnd)
        guard !fetched.isEmpty else { return }

        var merged = spO2
        for (day, value) in fetched {
            merged[day] = value
        }

        await MainActor.run {
            self.spO2 = merged
        }
        scheduleMetricsSnapshotSave()
    }

    func needsSleepHeartRateCoverage(from start: Date, to end: Date) -> Bool {
        needsCoverage(for: dailySleepHeartRate, from: start, to: end)
    }

    func ensureRecoveryMetricsCoverage(from start: Date, to end: Date) async {
        if Self.usesAggregatedCloudHealthPath {
            await reloadAggregatedHealthSnapshotFromICloud()
            scheduleScoresRefresh()
            scheduleMetricsSnapshotSave()
            return
        }
        let normalizedStart = Calendar.current.startOfDay(for: start)
        let normalizedEnd = min(end, Date())
        guard normalizedStart < normalizedEnd else { return }

        async let hrvTask: Void = ensureHRVCoverage(from: normalizedStart, to: normalizedEnd)
        async let rhrTask: Void = ensureRestingHeartRateCoverage(from: normalizedStart, to: normalizedEnd)
        async let respiratoryTask: Void = ensureRespiratoryRateCoverage(from: normalizedStart, to: normalizedEnd)
        async let wristTask: Void = ensureWristTemperatureCoverage(from: normalizedStart, to: normalizedEnd)
        async let spO2Task: Void = ensureSpO2Coverage(from: normalizedStart, to: normalizedEnd)
        async let sleepTask: Void = ensureSleepRecoveryCoverage(from: normalizedStart, to: normalizedEnd)

        _ = await (hrvTask, rhrTask, respiratoryTask, wristTask, spO2Task, sleepTask)
        scheduleScoresRefresh()
        scheduleMetricsSnapshotSave()
    }

    func ensureSleepHeartRateCoverage(from start: Date, to end: Date) async {
        let normalizedStart = Calendar.current.startOfDay(for: start)
        let normalizedEnd = min(end, Date())
        guard normalizedStart < normalizedEnd else { return }
        guard needsSleepHeartRateCoverage(from: normalizedStart, to: normalizedEnd) else { return }
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let sleepSamples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: normalizedStart, end: normalizedEnd)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            self.healthStore.execute(query)
        }

        guard !sleepSamples.isEmpty else { return }

        let calendar = Calendar.current
        var stageSleepWindows: [Date: [(start: Date, end: Date)]] = [:]
        var inBedSleepWindows: [Date: [(start: Date, end: Date)]] = [:]

        for sample in sleepSamples {
            let day = calendar.startOfDay(for: sample.startDate)
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed:
                inBedSleepWindows[day, default: []].append((start: sample.startDate, end: sample.endDate))
            case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                stageSleepWindows[day, default: []].append((start: sample.startDate, end: sample.endDate))
            default:
                continue
            }
        }

        let tolerance: TimeInterval = 5 * 60
        func mergedWindows(from windowsByDay: [Date: [(start: Date, end: Date)]]) -> [Date: [(start: Date, end: Date)]] {
            var mergedByDay: [Date: [(start: Date, end: Date)]] = [:]
            for (day, intervals) in windowsByDay {
                let sortedIntervals = intervals.sorted { $0.start < $1.start }
                var merged: [(start: Date, end: Date)] = []
                for interval in sortedIntervals {
                    guard var last = merged.last else {
                        merged.append(interval)
                        continue
                    }
                    if interval.start <= last.end.addingTimeInterval(tolerance) {
                        last.end = max(last.end, interval.end)
                        merged[merged.count - 1] = last
                    } else {
                        merged.append(interval)
                    }
                }
                mergedByDay[day] = merged
            }
            return mergedByDay
        }

        let mergedStageWindows = mergedWindows(from: stageSleepWindows)
        let mergedInBedWindows = mergedWindows(from: inBedSleepWindows)
        let allDays = Set(mergedStageWindows.keys).union(mergedInBedWindows.keys)
        var sleepWindows: [Date: [(start: Date, end: Date)]] = [:]
        for day in allDays {
            if let stage = mergedStageWindows[day], !stage.isEmpty {
                sleepWindows[day] = stage
            } else if let inBed = mergedInBedWindows[day], !inBed.isEmpty {
                sleepWindows[day] = inBed
            }
        }

        guard !sleepWindows.isEmpty else { return }

        let fetched = await computeSleepHeartRateBatch(
            days: sleepWindows.keys.sorted(by: >),
            sleepWindows: sleepWindows,
            fallbackStart: normalizedStart,
            fallbackEnd: normalizedEnd,
            heartRateType: heartRateType
        )
        guard !fetched.isEmpty else { return }

        var merged = dailySleepHeartRate
        for (day, value) in fetched {
            merged[day] = value
        }

        await MainActor.run {
            self.dailySleepHeartRate = merged
        }
        scheduleMetricsSnapshotSave()
    }

    private func ensureHRVCoverage(from start: Date, to end: Date) async {
        let existing = Dictionary(uniqueKeysWithValues: dailyHRV.map { ($0.date, $0.average) })
        guard needsCoverage(for: existing, from: start, to: end) else { return }
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }

        guard !samples.isEmpty else { return }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        let fetchedPoints = grouped.map { day, daySamples in
            let values = daySamples.map { $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) }
            let average = values.reduce(0, +) / Double(values.count)
            return DailyHRVPoint(
                date: day,
                average: average,
                min: values.min() ?? average,
                max: values.max() ?? average
            )
        }

        var merged = Dictionary(uniqueKeysWithValues: dailyHRV.map { ($0.date, $0) })
        for point in fetchedPoints {
            merged[point.date] = point
        }

        await MainActor.run {
            self.dailyHRV = merged.values.sorted { $0.date < $1.date }
        }
    }

    private func ensureRestingHeartRateCoverage(from start: Date, to end: Date) async {
        guard needsCoverage(for: dailyRestingHeartRate, from: start, to: end) else { return }
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }

        guard !samples.isEmpty else { return }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        var merged = dailyRestingHeartRate
        for (day, daySamples) in grouped {
            let values = daySamples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
            guard !values.isEmpty else { continue }
            merged[day] = values.reduce(0, +) / Double(values.count)
        }

        await MainActor.run {
            self.dailyRestingHeartRate = merged
        }
    }

    private func ensureRespiratoryRateCoverage(from start: Date, to end: Date) async {
        guard needsCoverage(for: respiratoryRate, from: start, to: end) else { return }
        let fetched = await fetchDailyQuantityValues(
            identifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: start,
            to: end
        )
        guard !fetched.isEmpty else { return }
        await MainActor.run {
            self.respiratoryRate.merge(fetched) { _, new in new }
        }
    }

    private func ensureWristTemperatureCoverage(from start: Date, to end: Date) async {
        guard needsCoverage(for: wristTemperature, from: start, to: end) else { return }
        let fetched = await fetchDailyQuantityValues(
            identifier: .appleSleepingWristTemperature,
            unit: HKUnit.degreeCelsius(),
            from: start,
            to: end
        )
        guard !fetched.isEmpty else { return }
        await MainActor.run {
            self.wristTemperature.merge(fetched) { _, new in new }
        }
    }

    private func ensureSleepRecoveryCoverage(from start: Date, to end: Date) async {
        guard needsCoverage(for: sleepStages, from: start, to: end)
            || needsCoverage(for: dailySleepHeartRate, from: start, to: end)
            || needsCoverage(for: anchoredSleepDuration, from: start, to: end) else {
            return
        }

        await withCheckedContinuation { continuation in
            self.fetchSleepQuality(from: start, to: end, mergeIntoExisting: true) {
                continuation.resume()
            }
        }
    }

    private func fetchDailyQuantityValues(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }

        guard !samples.isEmpty else { return [:] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        var result: [Date: Double] = [:]
        for (day, daySamples) in grouped {
            let values = daySamples.map { $0.quantity.doubleValue(for: unit) }
            guard !values.isEmpty else { continue }
            let average = values.reduce(0, +) / Double(values.count)
            result[day] = identifier == .oxygenSaturation ? average * 100.0 : average
        }
        return result
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
                self.scheduleScoresRefresh()
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
                self.hrvSampleHistory = samplesWithDates.map {
                    HRVSamplePoint(date: $0.date, value: $0.value)
                }
                self.dailyHRV = dailyPoints
                self.scheduleScoresRefresh()
                self.scheduleMetricsSnapshotSave()
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
                self.scheduleScoresRefresh()
            }
        }

        healthStore.execute(query)
    }
    
    private func fetchRestingHeartRateHistory(days: Int) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return }
        
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
                    date: calendar.startOfDay(for: $0.endDate),
                    value: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                )
            }
            
            let grouped = Dictionary(grouping: samplesWithDates, by: \.date)
            let dailyAverages = grouped.reduce(into: [Date: Double]()) { result, entry in
                let values = entry.value.map { $0.value }
                guard !values.isEmpty else { return }
                result[entry.key] = values.reduce(0, +) / Double(values.count)
            }
            
            Task { @MainActor in
                self.dailyRestingHeartRate = dailyAverages
                if let latest = quantitySamples.last {
                    self.restingHeartRate = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                }
                self.scheduleScoresRefresh()
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
                self.scheduleScoresRefresh()
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
                    self.scheduleScoresRefresh()
                }
            }
        }

        healthStore.execute(query)
    }

    private func fetchDailyAverages(
        for identifier: HKQuantityTypeIdentifier,
        days: Int,
        completion: @escaping ([Date: Double]) -> Void
    ) {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion([:])
            return
        }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let interval = DateComponents(day: 1)
        let anchorDate = calendar.startOfDay(for: endDate)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage,
            anchorDate: anchorDate,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, results, _ in
            guard let results else {
                completion([:])
                return
            }

            let unit: HKUnit
            switch identifier {
            case .heartRateVariabilitySDNN:
                unit = HKUnit.secondUnit(with: .milli)
            case .restingHeartRate:
                unit = HKUnit.count().unitDivided(by: .minute())
            default:
                unit = HKUnit.count()
            }

            var series: [Date: Double] = [:]
            results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                guard let average = statistics.averageQuantity() else { return }
                series[calendar.startOfDay(for: statistics.startDate)] = average.doubleValue(for: unit)
            }
            completion(series)
        }

        healthStore.execute(query)
    }

    private func fetchSleepDurationHistory(
        days: Int,
        completion: @escaping ([Date: Double]) -> Void
    ) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([:])
            return
        }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            guard let samples = samples as? [HKCategorySample] else {
                completion([:])
                return
            }

            var stagesByDay: [Date: [Int: [HKCategorySample]]] = [:]
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                stagesByDay[day, default: [:]][sample.value, default: []].append(sample)
            }

            let sleepStageValues = [1, 3, 4, 5]
            var dailyHours: [Date: Double] = [:]
            for (day, stageSamples) in stagesByDay {
                var totalSleep: Double = 0
                for stageValue in sleepStageValues {
                    for sample in stageSamples[stageValue] ?? [] {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate)
                        if duration > 0 {
                            totalSleep += duration
                        }
                    }
                }

                let cappedSleep = min(totalSleep / 3600, 12.0)
                if cappedSleep > 0 {
                    dailyHours[day] = cappedSleep
                }
            }

            completion(dailyHours)
        }

        healthStore.execute(query)
    }

    private func rollingStats(from values: [Double]) -> RollingBaselineStats? {
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.count > 1
            ? values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
            : 0
        let standardDeviation = sqrt(max(variance, 0))
        return RollingBaselineStats(
            mean: mean,
            standardDeviation: standardDeviation,
            sampleCount: values.count
        )
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
        var hrv60Stats: RollingBaselineStats?
        var rhr60Stats: RollingBaselineStats?
        var sleep60Stats: RollingBaselineStats?
        
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

        group.enter()
        fetchDailyAverages(for: .heartRateVariabilitySDNN, days: 60) { series in
            hrv60Stats = self.rollingStats(from: Array(series.values))
            group.leave()
        }

        group.enter()
        fetchDailyAverages(for: .restingHeartRate, days: 60) { series in
            rhr60Stats = self.rollingStats(from: Array(series.values))
            group.leave()
        }

        group.enter()
        fetchSleepDurationHistory(days: 60) { series in
            sleep60Stats = self.rollingStats(from: Array(series.values))
            DispatchQueue.main.async {
                self.dailySleepDuration = series
            }
            group.leave()
        }
        
        // When all fetches complete, update on main thread
        group.notify(queue: .main) {
            if let hrvAvg7 { self.hrvBaseline7Day = hrvAvg7 }
            if let rhrAvg7 { self.rhrBaseline7Day = rhrAvg7 }
            if let sleepAvg7 { self.sleepBaseline7Day = sleepAvg7 }
            if let hrvAvg28 { self.hrvBaseline28Day = hrvAvg28 }
            if let rhrAvg28 { self.rhrBaseline28Day = rhrAvg28 }
            self.hrvBaseline60Day = hrv60Stats
            self.rhrBaseline60Day = rhr60Stats
            self.sleepBaseline60Day = sleep60Stats
            self.scheduleScoresRefresh()
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
                self.acuteTrainingLoad = acuteLoad
                self.chronicTrainingLoad = chronicLoad
                self.trainingLoadRatio = chronicLoad > 0 ? acuteLoad / chronicLoad : 0
                self.scheduleScoresRefresh()
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
    @Published var feelGoodReadiness: ReadinessResult = .unavailable
    
    var feelGoodScoreInputsAvailable: Bool {
        latestHRV != nil && restingHeartRate != nil && sleepHours != nil
    }
    
    var missingFeelGoodInputs: [String] {
        var missing: [String] = []
        if latestHRV == nil {
            missing.append("HRV")
        }
        if restingHeartRate == nil {
            missing.append("Resting HR")
        }
        if sleepHours == nil {
            missing.append("Sleep")
        }
        return missing
    }

    private func clamped(_ value: Double, min lowerBound: Double = 0, max upperBound: Double = 1) -> Double {
        Swift.max(lowerBound, Swift.min(upperBound, value))
    }

    private func zScore(current: Double, stats: RollingBaselineStats?) -> Double? {
        guard let stats else { return nil }
        let denominator = stats.standardDeviation > 0.0001 ? stats.standardDeviation : max(stats.mean * 0.05, 0.1)
        return (current - stats.mean) / denominator
    }

    private func rollingStatsForRecentDays(
        valuesByDay: [Date: Double],
        days: Int,
        endingAt endDate: Date = Date()
    ) -> RollingBaselineStats? {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else { return nil }
        let values = valuesByDay
            .filter { day, _ in
                let normalized = calendar.startOfDay(for: day)
                return normalized >= startDay && normalized <= endDay
            }
            .map(\.value)
        return rollingStats(from: values)
    }

    private func rollingStatsForRecentHRV(
        days: Int,
        endingAt endDate: Date = Date()
    ) -> RollingBaselineStats? {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else { return nil }
        let values = dailyHRV
            .filter { point in
                let normalized = calendar.startOfDay(for: point.date)
                return normalized >= startDay && normalized <= endDay
            }
            .map(\.average)
        return rollingStats(from: values)
    }

    private func sigmoid(_ value: Double) -> Double {
        1.0 / (1.0 + Foundation.exp(-value))
    }

    private func recoveryReserveScore() -> Double {
        var weightedTotal = 0.0
        var totalWeight = 0.0

        if let rhr = restingHeartRate, let stats = rhrBaseline60Day {
            let component = clamped(1 - ((rhr - stats.mean) / max(stats.mean, 1)), min: 0, max: 1.2)
            weightedTotal += component * 0.55
            totalWeight += 0.55
        }

        if let sleep = sleepHours, let stats = sleepBaseline60Day {
            let goal = max(stats.mean, 0.1)
            let component = clamped(sleep / goal, min: 0, max: 1.2)
            weightedTotal += component * 0.45
            totalWeight += 0.45
        }

        guard totalWeight > 0 else { return 50 }
        return (weightedTotal / totalWeight) * 100
    }

    /// Calculate the overall Feel-Good Score using baseline-relative readiness logic.
    private func calculateFeelGoodScore(subjectiveInput: Double = 0.5) -> ReadinessResult {
        guard let hrv = latestHRV, let rhr = restingHeartRate, let sleep = sleepHours else {
            return .unavailable
        }

        let hrvReference = max(hrvBaseline7Day ?? hrvBaseline60Day?.mean ?? hrv, 0.1)
        let physiologyComponent = clamped(hrv / hrvReference, min: 0, max: 1.2)

        let sleepGoal = max(sleepBaseline60Day?.mean ?? sleepBaseline7Day ?? sleep, 0.1)
        let sleepComponent = clamped(sleep / sleepGoal, min: 0, max: 1.2)

        let rhrBaseline = max(rhrBaseline60Day?.mean ?? rhrBaseline7Day ?? rhr, 1)
        let cvEfficiencyComponent = clamped(1 - ((rhr - rhrBaseline) / rhrBaseline), min: 0, max: 1.2)

        // Deliberately exclude raw HRV from the recovery anchor to avoid double-counting it.
        let recoveryAnchor = recoveryReserveScore()
        let balanceSigma = max(
            abs(zScore(current: rhr, stats: rhrBaseline60Day) ?? 0) * 8,
            abs(zScore(current: sleep, stats: sleepBaseline60Day) ?? 0) * 8,
            10
        )
        let balanceDelta = Self.normalizedStrainPercent(from: strainScore) - recoveryAnchor
        var balanceComponent = clamped(1 - (balanceDelta / 100.0), min: 0, max: 1.2)
        if balanceDelta > (1.5 * balanceSigma) {
            let excess = balanceDelta - (1.5 * balanceSigma)
            balanceComponent = clamped(balanceComponent - (excess / 100.0), min: 0, max: 1.2)
        }

        let weightedScore = (physiologyComponent * 0.35)
            + (sleepComponent * 0.25)
            + (cvEfficiencyComponent * 0.15)
            + (balanceComponent * 0.25)

        let score = Int(clamped(weightedScore / 1.2, min: 0, max: 1) * 100)

        let sampleRatios = [
            min(Double(hrvBaseline60Day?.sampleCount ?? 0) / 60.0, 1.0),
            min(Double(rhrBaseline60Day?.sampleCount ?? 0) / 60.0, 1.0),
            min(Double(sleepBaseline60Day?.sampleCount ?? 0) / 60.0, 1.0)
        ]
        let dataCoverage = sampleRatios.reduce(0, +) / Double(sampleRatios.count)
        let requiredInputsCoverage = Double(3 - missingFeelGoodInputs.count) / 3.0
        let confidence = clamped((dataCoverage * 0.8) + (requiredInputsCoverage * 0.2))

        let contributions: [(name: String, impact: Double)] = [
            ("HRV", abs((physiologyComponent - 1.0) * 0.35)),
            ("Sleep", abs((sleepComponent - 1.0) * 0.25)),
            ("Cardiovascular Efficiency", abs((cvEfficiencyComponent - 1.0) * 0.15)),
            ("Strain-Recovery Balance", abs((balanceComponent - 1.0) * 0.25))
        ]
        let primaryDriver = contributions.max(by: { $0.impact < $1.impact })?.name ?? "Balanced"

        _ = subjectiveInput

        return ReadinessResult(
            score: score,
            confidence: confidence,
            primaryDriver: primaryDriver
        )
    }

    /// Update Feel-Good Score whenever scores refresh
    private func updateFeelGoodScore() {
        let result = calculateFeelGoodScore()
        feelGoodReadiness = result
        feelGoodScore = Double(result.score)
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

        // Keep the primary readiness score aligned with the strain/recovery views and watch sync.
        readinessScore = Self.proReadinessScore(
            recoveryScore: recoveryScore,
            strainScore: strainScore,
            hrvTrendComponent: hrvTrendScore
        )
        
        // Update 7-day rolling averages for score baselines
        updateScoreBaselines()

        // Update Feel-Good Score
        updateFeelGoodScore()
        workoutHRVDecay = calculateWorkoutHRVDecay()
        recoverySuppressedFlag = isRecoverySuppressedComparedToSevenDayAverage(currentRecovery: recoveryScore)
        functionalOverreachingFlag = evaluateFunctionalOverreaching()
        scheduleMetricsSnapshotSave()
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
        let today = Calendar.current.startOfDay(for: Date())
        let hrvLookup = Dictionary(uniqueKeysWithValues: dailyHRV.map { ($0.date, $0.average) })
        let inputs = Self.proRecoveryInputs(
            latestHRV: Self.smoothedValue(for: today, values: effectHRV) ?? readinessEffectHRV ?? readinessHRV ?? latestHRV ?? Self.smoothedValue(for: today, values: hrvLookup),
            restingHeartRate: Self.smoothedValue(for: today, values: basalSleepingHeartRate) ?? readinessBasalHeartRate ?? restingHeartRate,
            sleepDurationHours: Self.smoothedValue(for: today, values: anchoredSleepDuration) ?? readinessSleepDuration ?? sleepHours,
            timeInBedHours: Self.smoothedValue(for: today, values: anchoredTimeInBed) ?? readinessTimeInBed ?? readinessSleepDuration ?? sleepHours,
            hrvBaseline60Day: hrvBaseline60Day,
            rhrBaseline60Day: rhrBaseline60Day,
            sleepBaseline60Day: sleepBaseline60Day,
            hrvBaseline7Day: hrvBaseline7Day,
            rhrBaseline7Day: rhrBaseline7Day,
            sleepBaseline7Day: sleepBaseline7Day,
            bedtimeVarianceMinutes: Self.circularStandardDeviationMinutes(from: sleepStartHours, around: today)
        )
        guard !inputs.isInconclusive else { return recoveryScore }
        return Self.proRecoveryScore(from: inputs)
    }

    private func calculateWorkoutHRVDecay() -> [Date: Double] {
        let calendar = Calendar.current
        guard !hrvSampleHistory.isEmpty, !workoutAnalytics.isEmpty else { return [:] }

        let hrvSamplesByDay = Dictionary(grouping: hrvSampleHistory) { sample in
            calendar.startOfDay(for: sample.date)
        }

        var decayByDay: [Date: Double] = [:]
        for (workout, _) in workoutAnalytics {
            let day = calendar.startOfDay(for: workout.startDate)
            guard let nightlyHRV = effectHRV[day] else { continue }
            let workoutSamples = (hrvSamplesByDay[day] ?? []).filter { sample in
                sample.date >= workout.startDate && sample.date <= workout.endDate && isPlausibleHRV(sample.value)
            }
            guard !workoutSamples.isEmpty else { continue }
            let workoutAverage = workoutSamples.map(\.value).reduce(0, +) / Double(workoutSamples.count)
            decayByDay[day] = nightlyHRV - workoutAverage
        }
        return decayByDay
    }

    private func isRecoverySuppressedComparedToSevenDayAverage(currentRecovery: Double) -> Bool {
        let trailing = Array(recoveryScoreHistory.suffix(7))
        guard !trailing.isEmpty else { return false }
        let average = trailing.reduce(0, +) / Double(trailing.count)
        guard average > 0 else { return false }
        return currentRecovery < (average * 0.8)
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

        let hrvStats = rollingStatsForRecentHRV(days: 28) ?? hrvBaseline60Day
        let rhrStats = rollingStatsForRecentDays(valuesByDay: dailyRestingHeartRate, days: 28) ?? rhrBaseline60Day

        let zHRV = zScore(current: hrv, stats: hrvStats) ?? 0
        let zRHR = zScore(current: rhr, stats: rhrStats) ?? 0

        let balance = 50 + (10 * zHRV) - (10 * zRHR)
        let final = 100 * sigmoid((balance - 50) / 12)

        return max(0, min(100, final))
    }

    // MARK: - Strain

    private func calculateAllostaticStress() -> Double {
        let hrvStats = rollingStatsForRecentHRV(days: 28) ?? hrvBaseline60Day
        let rhrStats = rollingStatsForRecentDays(valuesByDay: dailyRestingHeartRate, days: 28) ?? rhrBaseline60Day
        let sleepStats = rollingStatsForRecentDays(valuesByDay: dailySleepDuration, days: 28) ?? sleepBaseline60Day

        let zHRV = latestHRV.flatMap { zScore(current: $0, stats: hrvStats) } ?? 0
        let zRHR = restingHeartRate.flatMap { zScore(current: $0, stats: rhrStats) } ?? 0

        let hrvStress = pow(max(0, -zHRV), 2)
        let rhrStress = pow(max(0, zRHR), 2)

        let sleepDebt: Double
        if let sleep = sleepHours {
            let targetSleep = max(sleepStats?.mean ?? sleepBaseline7Day ?? sleep, 0.1)
            sleepDebt = max(0, (targetSleep - sleep) / targetSleep)
        } else {
            sleepDebt = 0
        }

        let strainLoad = Self.normalizedStrainPercent(from: calculateStrainScore()) / 100.0
        let interaction = hrvStress * strainLoad

        let rawStress =
            (0.32 * hrvStress) +
            (0.23 * rhrStress) +
            (0.20 * sleepDebt) +
            (0.15 * strainLoad) +
            (0.10 * interaction)

        let scaledStress = 100 * (1 - Foundation.exp(-rawStress / 1.6))
        return max(0, min(100, scaledStress))
    }

    private func calculateStrainScore() -> Double {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -27, to: endDate) ?? endDate
        let recentAnalytics = workoutAnalytics
            .filter { pair in
                let day = calendar.startOfDay(for: pair.workout.startDate)
                return day >= startDate && day <= endDate
            }

        if !recentAnalytics.isEmpty {
            var dailyLoads: [Date: Double] = [:]
            var observedPeakHeartRate: Double = estimatedMaxHeartRate
            for pair in recentAnalytics {
                let day = calendar.startOfDay(for: pair.workout.startDate)
                if let peak = pair.analytics.peakHR, peak > observedPeakHeartRate {
                    observedPeakHeartRate = peak
                }
                let load = Self.proWorkoutLoad(
                    for: pair.workout,
                    analytics: pair.analytics,
                    estimatedMaxHeartRate: observedPeakHeartRate
                )
                dailyLoads[day, default: 0] += load
            }
            if observedPeakHeartRate > estimatedMaxHeartRate {
                estimatedMaxHeartRate = observedPeakHeartRate
            }
            let dates = (0..<28).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
            let orderedLoads = dates.map { dailyLoads[$0, default: 0] + Self.passiveDailyBaseLoad() }
            if let latestIndex = orderedLoads.indices.last {
                let state = Self.proTrainingLoadState(loads: orderedLoads, index: latestIndex)
                activityLoad = state.acuteLoad
                acuteTrainingLoad = state.acuteLoad
                chronicTrainingLoad = state.chronicLoad
                trainingLoadRatio = state.acwr
                return Self.proStrainScore(
                    acuteLoad: state.acuteLoad,
                    chronicLoad: state.chronicLoad
                )
            }
        }

        let acute = acuteTrainingLoad > 0 ? acuteTrainingLoad : (activityLoad + Self.passiveDailyBaseLoad())
        let chronic = chronicTrainingLoad > 0 ? chronicTrainingLoad : max(acute * 0.85, 1)
        return Self.proStrainScore(acuteLoad: acute, chronicLoad: chronic)
    }

    private func evaluateFunctionalOverreaching() -> Bool {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -6, to: endDate) ?? endDate
        let hrvLookup = effectHRV
        let rhrLookup = basalSleepingHeartRate
        let sleepDurationLookup = anchoredSleepDuration
        let timeInBedLookup = anchoredTimeInBed

        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
        let loads = dates.map { date -> Double in
            let workoutLoad = workoutAnalytics
                .filter { calendar.isDate($0.workout.startDate, inSameDayAs: date) }
                .reduce(0.0) { partial, pair in
                    partial + Self.proWorkoutLoad(
                        for: pair.workout,
                        analytics: pair.analytics,
                        estimatedMaxHeartRate: estimatedMaxHeartRate
                    )
                }
            return workoutLoad + Self.passiveDailyBaseLoad()
        }

        let strainSeries = dates.indices.map { index in
            Self.proStrainScore(
                acuteLoad: Self.proTrainingLoadState(loads: loads, index: index).acuteLoad,
                chronicLoad: Self.proTrainingLoadState(loads: loads, index: index).chronicLoad
            )
        }
        let recoverySeries = dates.map { day -> Double? in
            let inputs = Self.proRecoveryInputs(
                latestHRV: hrvLookup[day],
                restingHeartRate: rhrLookup[day],
                sleepDurationHours: sleepDurationLookup[day],
                timeInBedHours: timeInBedLookup[day],
                hrvBaseline60Day: hrvBaseline60Day,
                rhrBaseline60Day: rhrBaseline60Day,
                sleepBaseline60Day: sleepBaseline60Day,
                hrvBaseline7Day: hrvBaseline7Day,
                rhrBaseline7Day: rhrBaseline7Day,
                sleepBaseline7Day: sleepBaseline7Day,
                bedtimeVarianceMinutes: Self.circularStandardDeviationMinutes(from: sleepStartHours, around: day)
            )
            guard inputs.hrvZScore != nil || inputs.restingHeartRateZScore != nil || inputs.sleepRatio != nil else {
                return nil
            }
            return Self.proRecoveryScore(from: inputs)
        }

        guard strainSeries.count >= 4, recoverySeries.count >= 4 else { return false }
        let recentStrain = Array(strainSeries.suffix(4))
        let recentRecovery = Array(recoverySeries.suffix(4))
        guard recentRecovery.allSatisfy({ $0 != nil }) else { return false }

        for index in 1..<recentStrain.count {
            if recentStrain[index] <= recentStrain[index - 1] { return false }
            if (recentRecovery[index] ?? 0) >= (recentRecovery[index - 1] ?? 0) { return false }
        }
        return true
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
