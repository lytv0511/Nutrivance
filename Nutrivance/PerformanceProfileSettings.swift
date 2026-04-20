import Foundation
import SwiftUI
import Combine

/// Single athlete performance optimization profile stored in NutrivanceTuningStore.
/// Provides pro-athlete enhancements: dynamic HRV weighting, sleep quality coefficient,
/// HRV bell-curve detection, ACWR-based readiness, and asymmetric strain penalties.
@MainActor
final class PerformanceProfileSettings: ObservableObject {
    static let shared = PerformanceProfileSettings()
    
    // MARK: - Master Settings
    
    @Published var isProAthleteMode: Bool
    @Published var updatedAt: Date
    
    // MARK: - Dynamic HRV Weighting (Strain-Sensitive)
    
    @Published var enableStrainSensitiveHRV: Bool
    @Published var chronicLoadPercentile: Double  // 0.8 = top 20%
    
    // MARK: - HRV Bell-Curve Cap (Overtraining Detection)
    
    @Published var enableHRVBellCurve: Bool
    @Published var hrvZScoreCap: Double  // default: 2.5 (flags as warning if exceeded)
    
    // MARK: - ACWR-Based Readiness
    
    @Published var enableACWRLogic: Bool
    @Published var acwrOptimalMin: Double  // default: 0.8
    @Published var acwrOptimalMax: Double  // default: 1.3
    @Published var acwrDangerThreshold: Double  // default: 1.5
    
    // MARK: - Sleep Quality Coefficient
    
    @Published var enableSleepQualityCoeff: Bool
    @Published var deepSleepWeightMultiplier: Double  // default: 1.5
    @Published var remSleepWeightMultiplier: Double  // default: 1.2
    
    // MARK: - Strain Modeling
    
    @Published var enableAsymmetricStrainPenalty: Bool
    @Published var enableExponentialZoneWeighting: Bool
    @Published var enableTaperLogic: Bool
    
    // MARK: - Subjective Data Collection
    
    @Published var enableSubjectiveDataCollection: Bool
    
    // MARK: - Personalized MET Tracking
    
    @Published var enablePersonalizedMET: Bool
    @Published var personalizedMETProfile: PersonalizedMETProfile
    @Published var useDailyAdaptiveThreshold: Bool
    
    // MARK: - Storage Keys
    
    private static let storagePrefix = "PerformanceProfile_"
    private let tuningStore = NutrivanceTuningStore.shared
    
    // MARK: - Initialization
    
    private init() {
        self.isProAthleteMode = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)isProAthleteMode")
        self.enableStrainSensitiveHRV = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableStrainSensitiveHRV") || true
        self.chronicLoadPercentile = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)chronicLoadPercentile") == 0 ? 0.8 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)chronicLoadPercentile")
        
        self.enableHRVBellCurve = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableHRVBellCurve") || true
        self.hrvZScoreCap = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)hrvZScoreCap") == 0 ? 2.5 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)hrvZScoreCap")
        
        self.enableACWRLogic = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableACWRLogic") || true
        self.acwrOptimalMin = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)acwrOptimalMin") == 0 ? 0.8 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)acwrOptimalMin")
        self.acwrOptimalMax = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)acwrOptimalMax") == 0 ? 1.3 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)acwrOptimalMax")
        self.acwrDangerThreshold = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)acwrDangerThreshold") == 0 ? 1.5 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)acwrDangerThreshold")
        
        self.enableSleepQualityCoeff = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableSleepQualityCoeff") || true
        self.deepSleepWeightMultiplier = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)deepSleepWeightMultiplier") == 0 ? 1.5 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)deepSleepWeightMultiplier")
        self.remSleepWeightMultiplier = UserDefaults.standard.double(forKey: "\(Self.storagePrefix)remSleepWeightMultiplier") == 0 ? 1.2 : UserDefaults.standard.double(forKey: "\(Self.storagePrefix)remSleepWeightMultiplier")
        
        self.enableAsymmetricStrainPenalty = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableAsymmetricStrainPenalty") || true
        self.enableExponentialZoneWeighting = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableExponentialZoneWeighting") || true
        self.enableTaperLogic = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableTaperLogic") || true
        
        self.enableSubjectiveDataCollection = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enableSubjectiveDataCollection")
        
        // Initialize Personalized MET settings
        self.enablePersonalizedMET = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)enablePersonalizedMET")
        self.useDailyAdaptiveThreshold = UserDefaults.standard.bool(forKey: "\(Self.storagePrefix)useDailyAdaptiveThreshold") || true
        
        if let metProfileData = UserDefaults.standard.data(forKey: "\(Self.storagePrefix)personalizedMETProfile"),
           let decoded = try? JSONDecoder().decode(PersonalizedMETProfile.self, from: metProfileData) {
            self.personalizedMETProfile = decoded
        } else {
            self.personalizedMETProfile = PersonalizedMETProfile()
        }
        
        if let storedDate = UserDefaults.standard.object(forKey: "\(Self.storagePrefix)updatedAt") as? Date {
            self.updatedAt = storedDate
        } else {
            self.updatedAt = Date()
        }
        
        setupPublishers()
    }
    
    // MARK: - Publisher Setup
    
    private func setupPublishers() {
        Publishers.CombineLatest4(
            $isProAthleteMode,
            $enableStrainSensitiveHRV,
            $chronicLoadPercentile,
            $enableHRVBellCurve
        )
        .dropFirst()
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.save()
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest4(
            $hrvZScoreCap,
            $enableACWRLogic,
            $acwrOptimalMin,
            $acwrOptimalMax
        )
        .dropFirst()
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.save()
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest4(
            $acwrDangerThreshold,
            $enableSleepQualityCoeff,
            $deepSleepWeightMultiplier,
            $remSleepWeightMultiplier
        )
        .dropFirst()
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.save()
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest3(
            $enableAsymmetricStrainPenalty,
            $enableExponentialZoneWeighting,
            $enableTaperLogic
        )
        .dropFirst()
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.save()
        }
        .store(in: &cancellables)
        
        $enableSubjectiveDataCollection
            .dropFirst()
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)
        
        Publishers.CombineLatest3(
            $enablePersonalizedMET,
            $personalizedMETProfile,
            $useDailyAdaptiveThreshold
        )
        .dropFirst()
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.save()
        }
        .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Persistence
    
    private func save() {
        UserDefaults.standard.set(isProAthleteMode, forKey: "\(Self.storagePrefix)isProAthleteMode")
        UserDefaults.standard.set(enableStrainSensitiveHRV, forKey: "\(Self.storagePrefix)enableStrainSensitiveHRV")
        UserDefaults.standard.set(chronicLoadPercentile, forKey: "\(Self.storagePrefix)chronicLoadPercentile")
        UserDefaults.standard.set(enableHRVBellCurve, forKey: "\(Self.storagePrefix)enableHRVBellCurve")
        UserDefaults.standard.set(hrvZScoreCap, forKey: "\(Self.storagePrefix)hrvZScoreCap")
        UserDefaults.standard.set(enableACWRLogic, forKey: "\(Self.storagePrefix)enableACWRLogic")
        UserDefaults.standard.set(acwrOptimalMin, forKey: "\(Self.storagePrefix)acwrOptimalMin")
        UserDefaults.standard.set(acwrOptimalMax, forKey: "\(Self.storagePrefix)acwrOptimalMax")
        UserDefaults.standard.set(acwrDangerThreshold, forKey: "\(Self.storagePrefix)acwrDangerThreshold")
        UserDefaults.standard.set(enableSleepQualityCoeff, forKey: "\(Self.storagePrefix)enableSleepQualityCoeff")
        UserDefaults.standard.set(deepSleepWeightMultiplier, forKey: "\(Self.storagePrefix)deepSleepWeightMultiplier")
        UserDefaults.standard.set(remSleepWeightMultiplier, forKey: "\(Self.storagePrefix)remSleepWeightMultiplier")
        UserDefaults.standard.set(enableAsymmetricStrainPenalty, forKey: "\(Self.storagePrefix)enableAsymmetricStrainPenalty")
        UserDefaults.standard.set(enableExponentialZoneWeighting, forKey: "\(Self.storagePrefix)enableExponentialZoneWeighting")
        UserDefaults.standard.set(enableTaperLogic, forKey: "\(Self.storagePrefix)enableTaperLogic")
        UserDefaults.standard.set(enableSubjectiveDataCollection, forKey: "\(Self.storagePrefix)enableSubjectiveDataCollection")
        
        // Save Personalized MET settings
        UserDefaults.standard.set(enablePersonalizedMET, forKey: "\(Self.storagePrefix)enablePersonalizedMET")
        UserDefaults.standard.set(useDailyAdaptiveThreshold, forKey: "\(Self.storagePrefix)useDailyAdaptiveThreshold")
        if let encoded = try? JSONEncoder().encode(personalizedMETProfile) {
            UserDefaults.standard.set(encoded, forKey: "\(Self.storagePrefix)personalizedMETProfile")
        }
        
        updatedAt = Date()
        UserDefaults.standard.set(updatedAt, forKey: "\(Self.storagePrefix)updatedAt")
        
        #if !targetEnvironment(macCatalyst)
        NSUbiquitousKeyValueStore.default.set(updatedAt, forKey: "\(Self.storagePrefix)updatedAt")
        NSUbiquitousKeyValueStore.default.synchronize()
        #endif
    }
    
    // MARK: - Helpers
    
    /// Check if any pro-athlete optimization is actively changing the base calculation
    func hasActiveOptimizations() -> Bool {
        isProAthleteMode && (
            enableStrainSensitiveHRV ||
            enableHRVBellCurve ||
            enableACWRLogic ||
            enableSleepQualityCoeff ||
            enableAsymmetricStrainPenalty ||
            enableExponentialZoneWeighting ||
            enableTaperLogic
        )
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        DispatchQueue.main.async {
            self.isProAthleteMode = false
            self.enableStrainSensitiveHRV = true
            self.chronicLoadPercentile = 0.8
            self.enableHRVBellCurve = true
            self.hrvZScoreCap = 2.5
            self.enableACWRLogic = true
            self.acwrOptimalMin = 0.8
            self.acwrOptimalMax = 1.3
            self.acwrDangerThreshold = 1.5
            self.enableSleepQualityCoeff = true
            self.deepSleepWeightMultiplier = 1.5
            self.remSleepWeightMultiplier = 1.2
            self.enableAsymmetricStrainPenalty = true
            self.enableExponentialZoneWeighting = true
            self.enableTaperLogic = true
            self.enableSubjectiveDataCollection = false
            
            // Reset Personalized MET settings
            self.enablePersonalizedMET = false
            self.useDailyAdaptiveThreshold = true
            self.personalizedMETProfile = PersonalizedMETProfile()
            
            self.save()
        }
    }
}
