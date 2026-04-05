import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One `NavigationState` / `SearchState` per window so multi-window layouts stay independent.
struct NutrivanceSceneRoot: View {
    @StateObject private var navigationState = NavigationState()
    @StateObject private var searchState = SearchState()
    @EnvironmentObject private var unitPreferences: UnitPreferencesStore
    @Environment(\.scenePhase) private var scenePhase
#if canImport(UIKit)
    @State private var windowScene: UIWindowScene?
#endif

    var body: some View {
        ContentView()
            .environmentObject(navigationState)
            .environmentObject(searchState)
#if canImport(UIKit)
            .background(WindowSceneResolver { windowScene = $0 })
#endif
            .onChange(of: scenePhase) { _, newPhase in
                HealthStateEngine.shared.handleScenePhaseChange(newPhase)
                StrainRecoveryAggressiveCachingController.shared.handleScenePhaseChange(newPhase)
                WatchDashboardSyncBridge.shared.handleScenePhaseChange(newPhase)
                if newPhase == .active {
                    NutrivanceMenuStateBinder.shared.bindActiveScene(
                        navigationState: navigationState,
                        searchState: searchState
                    )
                }
            }
            .onAppear {
                NutrivanceMenuStateBinder.shared.bindActiveScene(
                    navigationState: navigationState,
                    searchState: searchState
                )
            }
            .task {
                NutrivanceMenuStateBinder.shared.bindActiveScene(
                    navigationState: navigationState,
                    searchState: searchState
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceCatalystMainMenuCommand)) { output in
                guard let command = output.userInfo?["command"] as? String else { return }
#if canImport(UIKit)
                let posted = output.object as? UIWindowScene
                let mine = windowScene
                let target = NutrivanceSceneMenuRouter.targetSceneForMenuCommand()
                let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                let allowDelivery: Bool = {
                    if let posted, let mine {
                        return posted === mine
                    }
                    if let mine {
                        if let target { return mine === target }
                        return true
                    }
                    // `windowScene` can lag behind the first menu actions; still deliver for a single window.
                    if let posted {
                        if windowScenes.count <= 1 { return true }
                        if let target { return posted === target }
                        return false
                    }
                    return windowScenes.count <= 1
                }()
                guard allowDelivery else { return }
#else
                return
#endif
                handleMainMenuCommand(command)
            }
    }

    private func handleMainMenuCommand(_ command: String) {
        switch command {
        case "back":
            performBackNavigation(
                presentedDestination: Binding(
                    get: { navigationState.presentedDestination },
                    set: { navigationState.presentedDestination = $0 }
                ),
                dismissAction: navigationState.dismissAction
            )
        case "find":
            navigationState.presentedDestination = nil
            navigationState.selectedRootTab = .search
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchState.isSearching = true
            }
        case "programBuilder":
            navigationState.navigate(focus: .fitness, view: "Program Builder", tab: .programBuilder)
        case "dashboard":
            navigationState.navigate(focus: .fitness, view: "Dashboard", tab: .dashboard)
        case "mindfulnessRealm":
            navigationState.navigate(focus: .mentalHealth, view: "Mindfulness Realm", tab: .mindfulnessRealm)
        case "todaysPlan":
            navigationState.navigate(focus: .fitness, view: "Today's Plan", tab: .todaysPlan)
        case "trainingCalendar":
            navigationState.navigate(focus: .fitness, view: "Training Calendar", tab: .trainingCalendar)
        case "workoutHistory":
            navigationState.navigate(focus: .fitness, view: "Workout History", tab: .workoutHistory)
        case "recoveryScore":
            navigationState.navigate(focus: .fitness, view: "Recovery Score", tab: .recoveryScore)
        case "readiness":
            navigationState.navigate(focus: .fitness, view: "Readiness", tab: .readiness)
        case "strainRecovery":
            navigationState.navigate(focus: .fitness, view: "Strain vs Recovery", tab: .strainRecovery)
        case "pastQuests":
            navigationState.navigate(focus: .fitness, view: "Past Quests", tab: .pastQuests)
        case "heartZones":
            navigationState.navigate(focus: .fitness, view: "Heart Zones", tab: .heartZones)
        case "pathfinder":
            navigationState.navigate(focus: .mentalHealth, view: "Pathfinder", tab: .pathfinder)
        case "journal":
            navigationState.navigate(focus: .mentalHealth, view: "Journal", tab: .journal)
        case "sleep":
            navigationState.navigate(focus: .mentalHealth, view: "Sleep", tab: .sleep)
        case "stress":
            navigationState.navigate(focus: .mentalHealth, view: "Stress", tab: .stress)
        default:
            break
        }
    }
}

#if canImport(UIKit)
private struct WindowSceneResolver: UIViewControllerRepresentable {
    var onResolve: (UIWindowScene?) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        onResolve(uiViewController.view.window?.windowScene)
        if uiViewController.view.window?.windowScene == nil {
            DispatchQueue.main.async {
                onResolve(uiViewController.view.window?.windowScene)
            }
        }
    }
}
#endif
