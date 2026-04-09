import Combine
import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Workout Activity State

struct WorkoutActivityState: Codable, Hashable {
    var elapsedSeconds: Int
    var elapsedReferenceDate: Date
    var isPaused: Bool
    var currentHeartRate: Int
    var heartRateDisplay: String?
    var totalCalories: Double
    var caloriesDisplay: String?
    var totalDistanceKilometers: Double
    var distanceDisplay: String?
    var currentPaceMinutesPerKm: Double?
    var elevationGainMeters: Int
    var currentHeartRateZone: Int?
    var activePhaseTitle: String?
}

// MARK: - Timer Sync Keys

struct WorkoutTimerSyncKeys {
    static let messageKey = "timerSync"
    static let elapsedTimeKey = "elapsedTime"
    static let syncTimestampKey = "syncTimestamp"
    static let workoutStateKey = "workoutState"
    static let splitCountKey = "splitCount"
}

// MARK: - Watch Connectivity for Workouts

#if canImport(WatchConnectivity)
@MainActor
class iOSWorkoutSyncManager: NSObject, WCSessionDelegate, ObservableObject {
    public static let shared = iOSWorkoutSyncManager()
    
    @Published var incomingWorkoutMetrics: WorkoutActivityState?
    @Published var isWatchReachable: Bool = false
    @Published var syncError: String?
    @Published var lastWorkoutTimerSync: WorkoutTimerSync?
    
    private var session: WCSession?
    private var localTimerSyncPoint: Date = Date()
    
    private override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    // MARK: - WCSession Setup
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported on this device")
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }
    
    // MARK: - WCSession Delegate Methods
    
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            if let error = error {
                self.syncError = "WCSession activation failed: \(error.localizedDescription)"
            } else {
                self.syncError = nil
            }
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {}
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }
    
    // MARK: - Receiving Messages
    
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.handleIncomingMessage(message)
        }
        replyHandler([:])
    }
    
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        if let state = try? JSONDecoder().decode(WorkoutActivityState.self, from: messageData) {
            Task { @MainActor in
                self.incomingWorkoutMetrics = state
            }
        }
        replyHandler(Data())
    }
    
    nonisolated func session(
        _ session: WCSession,
        didReceive fileTransfer: WCSessionFileTransfer,
        didFinishReceivingFile file: URL
    ) {
        if file.lastPathComponent == "workoutMetrics.json",
           let data = try? Data(contentsOf: file),
           let state = try? JSONDecoder().decode(WorkoutActivityState.self, from: data) {
            Task { @MainActor in
                self.incomingWorkoutMetrics = state
            }
        }
    }
    
    // MARK: - Private Handling
    
    @MainActor
    private func handleIncomingMessage(_ message: [String: Any]) {
        if message[WorkoutTimerSyncKeys.messageKey] as? Bool == true {
            handleTimerSync(message)
            return
        }

        if message["workoutMetricsSnapshot"] as? Bool == true {
            handleRealtimeWorkoutSnapshot(message)
            return
        }
        
        if let action = message["action"] as? String {
            switch action {
            case "workoutStarted": handleWorkoutStarted(message)
            case "workoutMetrics": handleWorkoutMetrics(message)
            case "workoutEnded": handleWorkoutEnded(message)
            default: break
            }
        }
    }

    @MainActor
    private func handleRealtimeWorkoutSnapshot(_ message: [String: Any]) {
        guard let elapsedTime = message["elapsedTime"] as? TimeInterval,
              let stateRaw = message["state"] as? String else { return }

        let normalizedState = stateRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var state = incomingWorkoutMetrics ?? WorkoutActivityState(
            elapsedSeconds: Int(elapsedTime.rounded(.down)),
            elapsedReferenceDate: Date(),
            isPaused: normalizedState == "paused",
            currentHeartRate: 0,
            heartRateDisplay: nil,
            totalCalories: 0,
            caloriesDisplay: nil,
            totalDistanceKilometers: 0,
            distanceDisplay: nil,
            currentPaceMinutesPerKm: nil,
            elevationGainMeters: 0,
            currentHeartRateZone: nil,
            activePhaseTitle: nil
        )

        state.elapsedSeconds = Int(elapsedTime.rounded(.down))
        state.elapsedReferenceDate = Date().addingTimeInterval(-elapsedTime)
        state.isPaused = normalizedState == "paused"
        if let heartRate = syncNumericValue(message["heartRate"]) {
            state.currentHeartRate = Int(heartRate.rounded())
            state.heartRateDisplay = "\(state.currentHeartRate)"
        }
        if let calories = message["totalCalories"] as? Double {
            state.totalCalories = calories
            state.caloriesDisplay = "\(Int(calories.rounded())) CAL"
        }
        if let distanceMeters = message["totalDistance"] as? Double {
            state.totalDistanceKilometers = distanceMeters / 1000.0
            state.distanceDisplay = distanceMeters >= 1000
                ? String(format: "%.2f km", distanceMeters / 1000.0)
                : "\(Int(distanceMeters.rounded())) m"
        }
        if let pace = message["currentPace"] as? Double {
            state.currentPaceMinutesPerKm = pace
        }
        if let elevationGainMeters = message["elevationGain"] as? Double {
            state.elevationGainMeters = Int(elevationGainMeters.rounded())
        }
        if let activePhase = message["activePhase"] as? String {
            state.activePhaseTitle = activePhase
        }

        incomingWorkoutMetrics = state
    }

    private func syncNumericValue(_ raw: Any?) -> Double? {
        guard let raw else { return nil }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String {
            let filtered = value.filter { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(filtered)
        }
        return nil
    }
    
    @MainActor
    private func handleTimerSync(_ message: [String: Any]) {
        guard let elapsedTime = message[WorkoutTimerSyncKeys.elapsedTimeKey] as? TimeInterval,
              let syncTs = message[WorkoutTimerSyncKeys.syncTimestampKey] as? TimeInterval,
              let state = message[WorkoutTimerSyncKeys.workoutStateKey] as? String,
              let splitCount = message[WorkoutTimerSyncKeys.splitCountKey] as? Int else { return }
        
        let syncDate = Date(timeIntervalSince1970: syncTs)
        let sync = WorkoutTimerSync(
            elapsedTime: elapsedTime,
            syncTimestamp: syncDate,
            workoutState: state,
            splitCount: splitCount
        )
        
        self.lastWorkoutTimerSync = sync
        self.localTimerSyncPoint = Date()
    }
    
    @MainActor
    private func handleWorkoutStarted(_ message: [String: Any]) {
        // Workout started - Live Activity is handled by WorkoutLiveActivityManager in its own file
    }

    public func requestWatchPresentation() {
        guard let session = session else { return }
        let payload: [String: Any] = ["request": "showLiveWorkout"]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in })
        } else {
            session.transferUserInfo(payload)
        }
    }
    
    @MainActor
    private func handleWorkoutMetrics(_ message: [String: Any]) {
        guard let elapsedSeconds = message["elapsedSeconds"] as? Int,
              let heartRate = message["heartRate"] as? Int else { return }
        
        var state = incomingWorkoutMetrics ?? WorkoutActivityState(
            elapsedSeconds: elapsedSeconds,
            elapsedReferenceDate: Date(),
            isPaused: false,
            currentHeartRate: heartRate,
            heartRateDisplay: nil,
            totalCalories: 0,
            caloriesDisplay: nil,
            totalDistanceKilometers: 0,
            distanceDisplay: nil,
            currentPaceMinutesPerKm: nil,
            elevationGainMeters: 0,
            currentHeartRateZone: nil,
            activePhaseTitle: nil
        )
        
        state.elapsedSeconds = elapsedSeconds
        state.elapsedReferenceDate = Date().addingTimeInterval(-Double(elapsedSeconds))
        state.currentHeartRate = heartRate
        state.heartRateDisplay = "\(heartRate)"
        
        if let calories = message["totalCalories"] as? Double {
            state.totalCalories = calories
            state.caloriesDisplay = "\(Int(calories.rounded())) CAL"
        }
        if let distance = message["totalDistanceKilometers"] as? Double {
            state.totalDistanceKilometers = distance
            state.distanceDisplay = distance >= 1
                ? String(format: "%.2f km", distance)
                : "\(Int((distance * 1000).rounded())) m"
        }
        if let pace = message["currentPaceMinutesPerKm"] as? Double {
            state.currentPaceMinutesPerKm = pace
        }
        if let elevation = message["elevationGainMeters"] as? Int {
            state.elevationGainMeters = elevation
        }
        if let zone = message["currentHeartRateZone"] as? Int {
            state.currentHeartRateZone = zone
        }
        if let phase = message["activePhaseTitle"] as? String {
            state.activePhaseTitle = phase
        }
        
        self.incomingWorkoutMetrics = state
    }
    
    @MainActor
    private func handleWorkoutEnded(_ message: [String: Any]) {
        // Workout ended - Live Activity is handled by WorkoutLiveActivityManager in its own file
    }
    
    // MARK: - Sending Messages to Watch
    
    public func sendWorkoutAction(action: String, parameters: [String: Any] = [:]) {
        guard let session = session, session.isReachable else { return }
        var message = parameters
        message["action"] = action
        session.sendMessage(message) { _ in } errorHandler: { [weak self] error in
            self?.syncError = "Failed to send to watch: \(error.localizedDescription)"
        }
    }
    
    public func requestWatchDisplay(show: Bool) {
        sendWorkoutAction(action: "toggleDisplay", parameters: ["shouldShow": show])
    }
    
    public func requestPauseWorkout() { sendWorkoutAction(action: "pauseWorkout") }
    public func requestResumeWorkout() { sendWorkoutAction(action: "resumeWorkout") }
    public func requestEndWorkout() { sendWorkoutAction(action: "endWorkout") }
}
#else
// Stub for platforms without WatchConnectivity
@MainActor
class iOSWorkoutSyncManager: NSObject, ObservableObject {
    public static let shared = iOSWorkoutSyncManager()
    @Published var incomingWorkoutMetrics: WorkoutActivityState?
    @Published var isWatchReachable: Bool = false
    @Published var syncError: String?
    var lastWorkoutTimerSync: Any? = nil
    private override init() { super.init() }
    public func requestWatchPresentation() {}
    public func sendWorkoutAction(action: String, parameters: [String: Any] = [:]) {}
    public func requestWatchDisplay(show: Bool) {}
    public func requestPauseWorkout() {}
    public func requestResumeWorkout() {}
    public func requestEndWorkout() {}
}
#endif
