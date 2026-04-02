import Combine
import Foundation
import WatchConnectivity

// MARK: - Watch Connectivity for Workouts

@MainActor
class iOSWorkoutSyncManager: NSObject, WCSessionDelegate, ObservableObject {
    public static let shared = iOSWorkoutSyncManager()
    
    @Published var incomingWorkoutMetrics: WorkoutActivityState?
    @Published var isWatchReachable: Bool = false
    @Published var syncError: String?
    
    private var session: WCSession?
    
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
        
        // Update reachability
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }
    
    // MARK: - WCSession Delegate Methods
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
            if let error = error {
                self.syncError = "WCSession activation failed: \(error.localizedDescription)"
                print("WCSession activation error: \(error)")
            } else {
                print("WCSession activated successfully")
                self.syncError = nil
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        DispatchQueue.main.async {
            self.isWatchReachable = false
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }
    
    // MARK: - Receiving Messages from Watch
        /// Stores the last timer sync received from the watch
    @Published var lastWorkoutTimerSync: WorkoutTimerSync?
    
    /// Used to sync iPhone's local timer with watch
    private var localTimerSyncPoint: Date = Date()
        func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingMessage(message)
        replyHandler([:])  // Acknowledge receipt
    }
    
    func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        if let state = try? JSONDecoder().decode(WorkoutActivityState.self, from: messageData) {
            DispatchQueue.main.async {
                self.incomingWorkoutMetrics = state
                Task {
                    await self.updateLiveActivityIfActive(with: state)
                }
            }
        }
        replyHandler(Data())
    }
    
    // MARK: - Receiving File Transfers
    
    func session(
        _ session: WCSession,
        didReceive fileTransfer: WCSessionFileTransfer,
        didFinishReceivingFile file: URL
    ) {
        if file.lastPathComponent == "workoutMetrics.json",
           let data = try? Data(contentsOf: file),
           let state = try? JSONDecoder().decode(WorkoutActivityState.self, from: data) {
            DispatchQueue.main.async {
                self.incomingWorkoutMetrics = state
                Task {
                    await self.updateLiveActivityIfActive(with: state)
                }
            }
        }
    }
    
    // MARK: - Private Handling
    
    private func handleIncomingMessage(_ message: [String: Any]) {
        // Handle timer sync from watch
        if message[WorkoutTimerSyncKeys.messageKey] as? Bool == true {
            handleTimerSync(message)
            return
        }

        // Handle high-frequency workout snapshot stream from watch
        if message["workoutMetricsSnapshot"] as? Bool == true {
            handleRealtimeWorkoutSnapshot(message)
            return
        }
        
        if let action = message["action"] as? String {
            switch action {
            case "workoutStarted":
                handleWorkoutStarted(message)
            case "workoutMetrics":
                handleWorkoutMetrics(message)
            case "workoutEnded":
                handleWorkoutEnded(message)
            default:
                print("Unknown message action: \(action)")
            }
        }
    }

    private func handleRealtimeWorkoutSnapshot(_ message: [String: Any]) {
        guard let elapsedTime = message["elapsedTime"] as? TimeInterval,
              let stateRaw = message["state"] as? String else {
            return
        }

        let normalizedState = stateRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedState == "ended" || normalizedState == "failed" || normalizedState == "idle" {
            Task { await WorkoutLiveActivityManager.shared.endActivity() }
            return
        }

        var state = incomingWorkoutMetrics ?? WorkoutActivityState(
            elapsedSeconds: Int(elapsedTime.rounded(.down)),
            currentHeartRate: 0,
            totalCalories: 0,
            totalDistanceKilometers: 0,
            currentPaceMinutesPerKm: nil,
            elevationGainMeters: 0,
            currentHeartRateZone: nil,
            activePhaseTitle: nil
        )

        state.elapsedSeconds = Int(elapsedTime.rounded(.down))
        if let heartRate = message["heartRate"] as? Int {
            state.currentHeartRate = heartRate
        }
        if let calories = message["totalCalories"] as? Double {
            state.totalCalories = calories
        }
        if let distanceMeters = message["totalDistance"] as? Double {
            state.totalDistanceKilometers = distanceMeters / 1000.0
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

        DispatchQueue.main.async {
            self.incomingWorkoutMetrics = state
            Task {
                await self.updateLiveActivityIfActive(with: state)
            }
        }
    }
    
    private func handleTimerSync(_ message: [String: Any]) {
        guard let elapsedTime = message[WorkoutTimerSyncKeys.elapsedTimeKey] as? TimeInterval,
              let syncTs = message[WorkoutTimerSyncKeys.syncTimestampKey] as? TimeInterval,
              let state = message[WorkoutTimerSyncKeys.workoutStateKey] as? String,
              let splitCount = message[WorkoutTimerSyncKeys.splitCountKey] as? Int else {
            return
        }
        
        let syncDate = Date(timeIntervalSince1970: syncTs)
        let sync = WorkoutTimerSync(
            elapsedTime: elapsedTime,
            syncTimestamp: syncDate,
            workoutState: state,
            splitCount: splitCount
        )
        
        DispatchQueue.main.async {
            self.lastWorkoutTimerSync = sync
            self.localTimerSyncPoint = Date()
            print("[iPhone] Timer sync received: \(elapsedTime)s, state=\(state), splits=\(splitCount)")
        }
    }
    
    private func handleWorkoutStarted(_ message: [String: Any]) {
        print("Received workout started message from watch")
        // Extract workout details
        if let workoutType = message["workoutType"] as? String,
           let activityIcon = message["activityIcon"] as? String,
           let targetMinutes = message["targetMinutes"] as? Int,
           let userInitials = message["userInitials"] as? String {
            
            let maxHR = message["maxHeartRate"] as? Int
            
            Task {
                await startWorkoutLiveActivity(
                    workoutType: workoutType,
                    activityIcon: activityIcon,
                    targetMinutes: targetMinutes,
                    userInitials: userInitials,
                    maxHeartRate: maxHR
                )

                // Trigger iPhone->Watch auto-launch request so Watch UI can show live workout context.
                requestWatchPresentation()
            }
        }
    }

    public func requestWatchPresentation() {
        guard let session = session else {
            print("WatchConnectivity session unavailable")
            return
        }

        let payload: [String: Any] = ["request": "showLiveWorkout"]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: { response in
                print("Requested watch presentation; response=\(response)")
            }, errorHandler: { error in
                print("Failed to request watch presentation: \(error.localizedDescription)")
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
            print("Watch not reachable; transferred userInfo for auto-launch")
        }
    }
    
    private func handleWorkoutMetrics(_ message: [String: Any]) {
        // Extract metrics and create state object
        guard let elapsedSeconds = message["elapsedSeconds"] as? Int,
              let heartRate = message["heartRate"] as? Int else {
            return
        }
        
        var state = incomingWorkoutMetrics ?? WorkoutActivityState(
            elapsedSeconds: elapsedSeconds,
            currentHeartRate: heartRate,
            totalCalories: 0,
            totalDistanceKilometers: 0,
            currentPaceMinutesPerKm: nil,
            elevationGainMeters: 0,
            currentHeartRateZone: nil,
            activePhaseTitle: nil
        )
        
        // Update with incoming values
        state.elapsedSeconds = elapsedSeconds
        state.currentHeartRate = heartRate
        
        if let calories = message["totalCalories"] as? Double {
            state.totalCalories = calories
        }
        if let distance = message["totalDistanceKilometers"] as? Double {
            state.totalDistanceKilometers = distance
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
        
        DispatchQueue.main.async {
            self.incomingWorkoutMetrics = state
            Task {
                await self.updateLiveActivityIfActive(with: state)
            }
        }
    }
    
    private func handleWorkoutEnded(_ message: [String: Any]) {
        print("Received workout ended message from watch")
        Task {
            await WorkoutLiveActivityManager.shared.endActivity()
        }
    }
    
    // MARK: - Live Activity Updates
    
    private func startWorkoutLiveActivity(
        workoutType: String,
        activityIcon: String,
        targetMinutes: Int?,
        userInitials: String,
        maxHeartRate: Int?
    ) async {
        do {
            _ = try await WorkoutLiveActivityManager.shared.startActivity(
                workoutType: workoutType,
                activityIcon: activityIcon,
                targetMinutes: targetMinutes,
                userInitials: userInitials,
                maxHeartRate: maxHeartRate
            )
        } catch {
            DispatchQueue.main.async {
                self.syncError = "Failed to start Live Activity: \(error.localizedDescription)"
            }
            print("Error starting Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivityIfActive(with state: WorkoutActivityState) async {
        guard WorkoutLiveActivityManager.shared.isActivityActive else {
            return
        }
        
        await WorkoutLiveActivityManager.shared.updateActivity(with: state)
    }
    
    // MARK: - Sending Messages to Watch
    
    public func sendWorkoutAction(
        action: String,
        parameters: [String: Any] = [:]
    ) {
        guard let session = session, session.isReachable else {
            print("Watch not reachable for action: \(action)")
            return
        }
        
        var message = parameters
        message["action"] = action
        
        session.sendMessage(message) { [weak self] _ in
            print("Sent action to watch: \(action)")
        } errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.syncError = "Failed to send to watch: \(error.localizedDescription)"
            }
            print("Error sending to watch: \(error)")
        }
    }
    
    /// Request watch to toggle its display during active workout
    public func requestWatchDisplay(show: Bool) {
        sendWorkoutAction(
            action: "toggleDisplay",
            parameters: ["shouldShow": show]
        )
    }
    
    /// Request watch to pause the current workout
    public func requestPauseWorkout() {
        sendWorkoutAction(action: "pauseWorkout")
    }
    
    /// Request watch to resume the current workout
    public func requestResumeWorkout() {
        sendWorkoutAction(action: "resumeWorkout")
    }
    
    /// Request watch to end the current workout
    public func requestEndWorkout() {
        sendWorkoutAction(action: "endWorkout")
    }
}
