import SwiftUI
import HealthKit

@MainActor
class AppState: ObservableObject {
    @Published var healthKitManager = HealthKitManager()
    @Published var selectedNutrient: String?
    @Published var navigationPath = NavigationPath()
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var engine = HealthStateEngine.shared
    @StateObject private var companionWorkoutManager = CompanionWorkoutLiveManager.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("startup_curtain_dismissed") private var hasDismissedStartupCurtain = false
    @State private var showStartupCurtain = true

    private var startupStatusText: String {
        let hasCoreHealthBootstrap =
            engine.hasHydratedCachedMetrics ||
            !engine.dailyHRV.isEmpty ||
            !engine.dailyRestingHeartRate.isEmpty ||
            !engine.sleepStages.isEmpty

        if !engine.hasHydratedCachedMetrics && !engine.hasInitializedWorkoutAnalytics {
            return "Loading cached health data..."
        }
        if engine.isSyncingStartupWorkoutCoverage {
            return "Fetching workouts..."
        }
        if engine.isRefreshingCachedMetrics {
            return "Updating metrics..."
        }
        if !engine.hasInitializedWorkoutAnalytics {
            return "Preparing workout history..."
        }
        if !hasCoreHealthBootstrap {
            return "Updating recovery metrics..."
        }
        return "Finalizing startup..."
    }
    
    var body: some View {
        ZStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
    //                if horizontalSizeClass == .regular {
    //                    ContentView_iPad_alt()
    //                        .environmentObject(appState)
//                    ContentView_iPad_alt()
                    ContentView_iPad_alt()
    //                } else {
    //                    ContentView_iPad()
    //                        .environmentObject(appState)
    //                }
                } else if UIDevice.current.userInterfaceIdiom == .phone {
                    ContentView_iPhone_alt()
//                    ContentView_iPad_alt()
                }
            }

            if showStartupCurtain && !hasDismissedStartupCurtain {
                StartupCurtainView(statusText: startupStatusText)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }

            if companionWorkoutManager.isVisible {
                CompanionWorkoutLiveOverlay(manager: companionWorkoutManager)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            guard !hasDismissedStartupCurtain else {
                showStartupCurtain = false
                return
            }

            let minimumCurtainDuration: UInt64 = engine.hasHydratedCachedMetrics ? 700_000_000 : 2_200_000_000
            let maximumCurtainDuration: UInt64 = 12_000_000_000
            let pollInterval: UInt64 = 200_000_000

            let startedAt = Date()
            try? await Task.sleep(nanoseconds: minimumCurtainDuration)

            while Date().timeIntervalSince(startedAt) < Double(maximumCurtainDuration) / 1_000_000_000 {
                let hasWorkoutBootstrap = engine.hasInitializedWorkoutAnalytics
                let hasCoreHealthBootstrap =
                    engine.hasHydratedCachedMetrics ||
                    !engine.dailyHRV.isEmpty ||
                    !engine.dailyRestingHeartRate.isEmpty ||
                    !engine.sleepStages.isEmpty

                if engine.requiresInitialFullSync {
                    if hasWorkoutBootstrap && !engine.isSyncingStartupWorkoutCoverage {
                        break
                    }
                } else if (hasWorkoutBootstrap || hasCoreHealthBootstrap) && !engine.isSyncingStartupWorkoutCoverage {
                    break
                }

                try? await Task.sleep(nanoseconds: pollInterval)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                hasDismissedStartupCurtain = true
                showStartupCurtain = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, hasDismissedStartupCurtain else { return }
            showStartupCurtain = false
            companionWorkoutManager.activateIfNeeded()
        }
        .onAppear {
            companionWorkoutManager.activateIfNeeded()
        }
    }
}

private struct StartupCurtainView: View {
    let statusText: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.94), Color.orange.opacity(0.24), Color.black.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 104, height: 104)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.orange)
                }
                Text("Preparing Nutrivance")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundColor(.white)
                Text(statusText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, 32)
                ProgressView()
                    .tint(.orange)
                    .scaleEffect(1.15)
                    .padding(.top, 4)
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

@MainActor
final class CompanionWorkoutLiveManager: NSObject, ObservableObject {
    static let shared = CompanionWorkoutLiveManager()

    private struct MirroredMetricPayload: Codable {
        let id: String
        let title: String
        let valueText: String
        let symbol: String
        let tintName: String
    }

    private struct MirroredWorkoutSnapshotPayload: Codable {
        let title: String
        let stateText: String
        let elapsedTime: TimeInterval
        let metrics: [MirroredMetricPayload]
    }

    struct LiveMetric: Identifiable, Hashable {
        let id: String
        let title: String
        let value: String
        let symbol: String
        let tint: Color
    }

    @Published private(set) var isVisible = false
    @Published private(set) var title = "Watch Workout"
    @Published private(set) var stateText = "Preparing"
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var metrics: [LiveMetric] = []

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var hasActivated = false

    func activateIfNeeded() {
        guard hasActivated == false else { return }
        hasActivated = true
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attachMirroredSession(session)
            }
        }
    }

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        mirroredSession = session
        session.delegate = self
        title = session.workoutConfiguration.activityType.name
        stateText = "Live on Apple Watch"
        startedAt = Date()
        startElapsedTimer()
        isVisible = true

        if #available(iOS 26.0, *) {
            let builder = session.associatedWorkoutBuilder()
            self.builder = builder
            builder.delegate = self
            rebuildMetrics()
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func rebuildMetrics() {
        guard let builder else { return }
        var updated: [LiveMetric] = []

        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let heartStats = builder.statistics(for: heartRateType),
           let current = heartStats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            updated.append(.init(id: "hr", title: "Heart Rate", value: "\(Int(current.rounded())) bpm", symbol: "heart.fill", tint: .red))
        }

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let energy = builder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
            updated.append(.init(id: "energy", title: "Energy", value: "\(Int(energy.rounded())) kcal", symbol: "flame.fill", tint: .orange))
        }

        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        if let distanceType = distanceTypes.compactMap(HKQuantityType.quantityType(forIdentifier:)).first(where: { builder.statistics(for: $0) != nil }),
           let distance = builder.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) {
            let label = distance >= 1000 ? String(format: "%.2f km", distance / 1000) : "\(Int(distance.rounded())) m"
            updated.append(.init(id: "distance", title: "Distance", value: label, symbol: "location.fill", tint: .green))
        }

        if let powerType = [HKQuantityTypeIdentifier.cyclingPower, .runningPower]
            .compactMap(HKQuantityType.quantityType(forIdentifier:))
            .first(where: { builder.statistics(for: $0) != nil }),
           let power = builder.statistics(for: powerType)?.mostRecentQuantity()?.doubleValue(for: .watt()) {
            updated.append(.init(id: "power", title: "Power", value: "\(Int(power.rounded())) W", symbol: "bolt.fill", tint: .yellow))
        }

        if let speedType = [HKQuantityTypeIdentifier.runningSpeed, .walkingSpeed]
            .compactMap(HKQuantityType.quantityType(forIdentifier:))
            .first(where: { builder.statistics(for: $0) != nil }),
           let speed = builder.statistics(for: speedType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())) {
            updated.append(.init(id: "speed", title: "Speed", value: String(format: "%.1f km/h", speed * 3.6), symbol: "speedometer", tint: .cyan))
        }

        if let cadenceType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence),
           let cadence = builder.statistics(for: cadenceType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            updated.append(.init(id: "cadence", title: "Cadence", value: "\(Int(cadence.rounded())) rpm", symbol: "metronome.fill", tint: .mint))
        }

        metrics = updated
    }

    private func applyRemoteSnapshot(_ payload: MirroredWorkoutSnapshotPayload) {
        title = payload.title
        stateText = payload.stateText
        elapsedTime = payload.elapsedTime
        startedAt = Date().addingTimeInterval(-payload.elapsedTime)
        metrics = payload.metrics.map {
            LiveMetric(
                id: $0.id,
                title: $0.title,
                value: $0.valueText,
                symbol: $0.symbol,
                tint: companionTintColor(named: $0.tintName)
            )
        }
        isVisible = true
    }

    func primePresentationFromWatchRequest() {
        activateIfNeeded()
        if !isVisible {
            title = "Watch Workout"
            stateText = mirroredSession == nil ? "Connecting..." : stateText
            isVisible = true
        }
    }

    fileprivate func finishSession() {
        stopElapsedTimer()
        stateText = "Ended"
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            self.isVisible = false
            self.metrics = []
            self.builder = nil
            self.mirroredSession = nil
            self.startedAt = nil
            self.elapsedTime = 0
        }
    }
}

extension CompanionWorkoutLiveManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                stateText = "Running"
                if startedAt == nil {
                    startedAt = date
                }
            case .paused:
                stateText = "Paused"
            case .ended:
                finishSession()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            stateText = "Unavailable"
            finishSession()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for packet in data {
                guard let payload = try? JSONDecoder().decode(MirroredWorkoutSnapshotPayload.self, from: packet) else {
                    continue
                }
                applyRemoteSnapshot(payload)
            }
        }
    }
}

extension CompanionWorkoutLiveManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            rebuildMetrics()
        }
    }
}

private struct CompanionWorkoutLiveOverlay: View {
    @ObservedObject var manager: CompanionWorkoutLiveManager

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.title)
                        .font(.headline.weight(.semibold))
                    Text(manager.stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(companionElapsedString(manager.elapsedTime))
                    .font(.headline.monospacedDigit())
            }

            if !manager.metrics.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(manager.metrics) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(metric.title, systemImage: metric.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(metric.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }
}

private func companionElapsedString(_ elapsed: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = elapsed >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: elapsed) ?? "00:00"
}

private func companionTintColor(named name: String) -> Color {
    switch name {
    case "red":
        return .red
    case "orange":
        return .orange
    case "green":
        return .green
    case "cyan":
        return .cyan
    case "yellow":
        return .yellow
    case "mint":
        return .mint
    case "indigo":
        return .indigo
    case "brown":
        return .brown
    case "purple":
        return .purple
    case "teal":
        return .teal
    case "blue":
        return .blue
    default:
        return .white
    }
}
