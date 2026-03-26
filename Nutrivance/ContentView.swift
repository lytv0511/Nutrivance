import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var healthKitManager = HealthKitManager()
    @Published var selectedNutrient: String?
    @Published var navigationPath = NavigationPath()
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var engine = HealthStateEngine.shared
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
    //                ContentView_iPhone_alt()
                    ContentView_iPhone_alt()
                }
            }

            if showStartupCurtain && !hasDismissedStartupCurtain {
                StartupCurtainView(statusText: startupStatusText)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
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
