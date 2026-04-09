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
    @State private var windowScenePersistentIdentifier: String?
#endif

    var body: some View {
        ContentView()
            .environmentObject(navigationState)
            .environmentObject(searchState)
#if canImport(UIKit)
            .background(NutrivanceSceneKeyWindowResolver(
                navigationState: navigationState,
                searchState: searchState,
                onResolveScene: { resolvedScene in
                    guard let resolvedScene else { return }
                    windowScene = resolvedScene
                    windowScenePersistentIdentifier = NutrivanceSceneMenuRouter.scenePersistentIdentifier(resolvedScene)
                }
            ))
#endif
            .onChange(of: scenePhase) { _, newPhase in
                HealthStateEngine.shared.handleScenePhaseChange(newPhase)
                StrainRecoveryAggressiveCachingController.shared.handleScenePhaseChange(newPhase)
                WatchDashboardSyncBridge.shared.handleScenePhaseChange(newPhase)
                if newPhase == .active {
                    NutrivanceTuningStore.shared.syncOnAppForeground()
                }
#if canImport(UIKit)
                #if DEBUG
                NutrivanceSceneMenuRouter.emitFocusDebug("[SceneRoot] scenePhase -> \(newPhase) sceneID=\(windowScenePersistentIdentifier ?? "nil") \(NutrivanceSceneMenuRouter.focusDebugDescription(for: windowScene))")
                #endif
                if newPhase == .active,
                   windowScenePersistentIdentifier == NutrivanceSceneMenuRouter.targetScenePersistentIdentifierForMenuCommand() {
                    NutrivanceMenuStateBinder.shared.activateScene(persistentIdentifier: windowScenePersistentIdentifier)
                }
#endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceCatalystMainMenuCommand)) { output in
                guard let command = output.userInfo?["command"] as? String else { return }
#if canImport(UIKit)
                // Use shared routing so ⌘ menu targets match `targetSceneForMenuCommand()` even when
                // scene pointers differ (`scenesMatch`) or the notification has no object (key window).
                guard NutrivanceSceneMenuRouter.shouldHandleSceneTargetedNotification(
                    object: output.object,
                    windowScene: windowScene,
                    windowScenePersistentIdentifier: windowScenePersistentIdentifier
                ) else { return }
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
/// Resolves this scene’s `UIWindowScene` and, only when **this** hierarchy’s window is key, updates menu routing + binder.
private struct NutrivanceSceneKeyWindowResolver: UIViewControllerRepresentable {
    var navigationState: NavigationState
    var searchState: SearchState
    var onResolveScene: (UIWindowScene?) -> Void

    final class Coordinator: NSObject {
        weak var lastNotifiedScene: UIWindowScene?
        weak var lastKeyRoutingScene: UIWindowScene?
        var lastKeyRoutingScenePersistentIdentifier: String?
        var lastResolvedScenePersistentIdentifier: String?
        var didScheduleNilWindowRetry = false
        weak var observedViewController: UIViewController?
        var keyWindowObserver: NSObjectProtocol?
        var navigationStateCapture: NavigationState?
        var searchStateCapture: SearchState?
        var onResolveSceneCapture: ((UIWindowScene?) -> Void)?

        deinit {
            if let keyWindowObserver {
                NotificationCenter.default.removeObserver(keyWindowObserver)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.observedViewController = uiViewController
        installKeyWindowObserverIfNeeded(coordinator: coordinator)
        Self.resolveScene(
            navigationState: navigationState,
            searchState: searchState,
            onResolveScene: onResolveScene,
            vc: uiViewController,
            coordinator: coordinator
        )
    }

    private func installKeyWindowObserverIfNeeded(coordinator: Coordinator) {
        guard coordinator.keyWindowObserver == nil else { return }
        coordinator.keyWindowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak coordinator] _ in
            guard let coordinator,
                  let vc = coordinator.observedViewController,
                  let nav = coordinator.navigationStateCapture,
                  let search = coordinator.searchStateCapture,
                  let onResolve = coordinator.onResolveSceneCapture
            else { return }
            NutrivanceSceneKeyWindowResolver.resolveScene(
                navigationState: nav,
                searchState: search,
                onResolveScene: onResolve,
                vc: vc,
                coordinator: coordinator
            )
        }
    }

    static func resolveScene(
        navigationState: NavigationState,
        searchState: SearchState,
        onResolveScene: @escaping (UIWindowScene?) -> Void,
        vc: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.navigationStateCapture = navigationState
        coordinator.searchStateCapture = searchState
        coordinator.onResolveSceneCapture = onResolveScene

        let scene = resolvedScene(for: vc)
        let scenePersistentIdentifier = NutrivanceSceneMenuRouter.scenePersistentIdentifier(scene)
            ?? coordinator.lastResolvedScenePersistentIdentifier
        let windowIsKey = vc.view.window?.isKeyWindow == true

        #if DEBUG
        NutrivanceSceneMenuRouter.emitFocusDebug("[SceneRoot] resolveScene windowIsKey=\(windowIsKey) sceneID=\(scenePersistentIdentifier ?? "nil") resolved=\(NutrivanceSceneMenuRouter.focusDebugDescription(for: scene))")
        #endif

        if let scenePersistentIdentifier {
            coordinator.lastResolvedScenePersistentIdentifier = scenePersistentIdentifier
        }

        NutrivanceMenuStateBinder.shared.registerScene(
            persistentIdentifier: scenePersistentIdentifier,
            scene: scene,
            navigationState: navigationState,
            searchState: searchState
        )

        if coordinator.lastNotifiedScene === scene {
            applySizeRestrictionsIfNeeded(to: scene)
            routeMenusIfKey(
                scene: scene,
                scenePersistentIdentifier: scenePersistentIdentifier,
                windowIsKey: windowIsKey,
                coordinator: coordinator
            )
            syncBinderIfFocused(scene: scene, scenePersistentIdentifier: scenePersistentIdentifier)
            return
        }
        coordinator.lastNotifiedScene = scene
        onResolveScene(scene)
        applySizeRestrictionsIfNeeded(to: scene)
        routeMenusIfKey(
            scene: scene,
            scenePersistentIdentifier: scenePersistentIdentifier,
            windowIsKey: windowIsKey,
            coordinator: coordinator
        )
        syncBinderIfFocused(scene: scene, scenePersistentIdentifier: scenePersistentIdentifier)

        if scene == nil, !coordinator.didScheduleNilWindowRetry {
            coordinator.didScheduleNilWindowRetry = true
            DispatchQueue.main.async { [weak vc] in
                coordinator.didScheduleNilWindowRetry = false
                guard let vc else { return }
                resolveScene(
                    navigationState: navigationState,
                    searchState: searchState,
                    onResolveScene: onResolveScene,
                    vc: vc,
                    coordinator: coordinator
                )
            }
        }
    }

    private static func resolvedScene(for vc: UIViewController) -> UIWindowScene? {
        if let scene = vc.view.window?.windowScene {
            return scene
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { scene in
            scene.windows.contains { window in
                var current: UIView? = vc.view
                while let view = current {
                    if view === window {
                        return true
                    }
                    current = view.superview
                }
                return false
            }
        }
    }

    private static func syncBinderIfFocused(
        scene: UIWindowScene?,
        scenePersistentIdentifier: String?
    ) {
        guard let scenePersistentIdentifier,
              let targetScenePersistentIdentifier = NutrivanceSceneMenuRouter.targetScenePersistentIdentifierForMenuCommand(),
              scenePersistentIdentifier == targetScenePersistentIdentifier else { return }
        #if DEBUG
        let targetScene = NutrivanceSceneMenuRouter.connectedScene(matchingPersistentIdentifier: targetScenePersistentIdentifier)
        NutrivanceSceneMenuRouter.emitFocusDebug("[SceneRoot] syncBinderIfFocused sceneID=\(scenePersistentIdentifier) scene=\(NutrivanceSceneMenuRouter.focusDebugDescription(for: scene)) target=\(NutrivanceSceneMenuRouter.focusDebugDescription(for: targetScene))")
        #endif
        NutrivanceMenuStateBinder.shared.activateScene(persistentIdentifier: scenePersistentIdentifier)
    }

    private static func routeMenusIfKey(
        scene: UIWindowScene?,
        scenePersistentIdentifier: String?,
        windowIsKey: Bool,
        coordinator: Coordinator
    ) {
        guard let scenePersistentIdentifier else { return }
        if windowIsKey {
            if coordinator.lastKeyRoutingScenePersistentIdentifier != scenePersistentIdentifier
                || coordinator.lastKeyRoutingScene !== scene {
                coordinator.lastKeyRoutingScene = scene
                coordinator.lastKeyRoutingScenePersistentIdentifier = scenePersistentIdentifier
                #if DEBUG
                NutrivanceSceneMenuRouter.emitFocusDebug("[SceneRoot] routeMenusIfKey set sceneID=\(scenePersistentIdentifier) -> \(NutrivanceSceneMenuRouter.focusDebugDescription(for: scene))")
                #endif
                if let scene {
                    NutrivanceSceneMenuRouter.registerFocusedScene(scene, reason: "resolverKeyWindow")
                } else {
                    NutrivanceSceneMenuRouter.registerFocusedScenePersistentIdentifier(scenePersistentIdentifier, reason: "resolverKeyWindowRetainedID")
                }
            }
        } else if coordinator.lastKeyRoutingScenePersistentIdentifier == scenePersistentIdentifier {
            #if DEBUG
            NutrivanceSceneMenuRouter.emitFocusDebug("[SceneRoot] routeMenusIfKey cleared sceneID=\(scenePersistentIdentifier) -> \(NutrivanceSceneMenuRouter.focusDebugDescription(for: scene))")
            #endif
            coordinator.lastKeyRoutingScene = nil
            coordinator.lastKeyRoutingScenePersistentIdentifier = nil
        }
    }

    private static var sizeRestrictionsApplied = Set<ObjectIdentifier>()

    private static func applySizeRestrictionsIfNeeded(to scene: UIWindowScene?) {
        guard let scene else { return }
        let id = ObjectIdentifier(scene)
        guard !sizeRestrictionsApplied.contains(id) else { return }
        sizeRestrictionsApplied.insert(id)
        scene.sizeRestrictions?.minimumSize = CGSize(width: 500, height: 380)
    }
}
#endif
