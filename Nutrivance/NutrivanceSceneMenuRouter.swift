import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let nutrivanceCatalystMainMenuCommand = Notification.Name("nutrivance.catalystMainMenu.command")
}

#if canImport(UIKit)
enum NutrivanceSceneMenuRouter {
    private static weak var lastRegisteredScene: UIWindowScene?
    private static var lastRegisteredScenePersistentIdentifier: String?
    private static var lastLoggedTargetSnapshot: String?

    /// Secondary hint for multi-window when dispatch-time lookup finds no app key window; updated from
    /// `didBecomeKey` (filtered) and self-corrected from `targetSceneForMenuCommand()`.
    private static weak var cachedKeyWindowScene: UIWindowScene?
    private static var cachedKeyWindowScenePersistentIdentifier: String?
    private static var didInstallKeyWindowObserver = false

    /// True when the scene has a key window that looks like the real app content (not a transient Catalyst surface).
    private static func sceneHasAppKeyWindow(_ scene: UIWindowScene) -> Bool {
        scene.windows.contains { window in
            window.isKeyWindow
                && !window.isHidden
                && window.alpha > 0
                && window.rootViewController != nil
        }
    }

    private static func matchingScene(
        for candidate: UIWindowScene?,
        in scenes: [UIWindowScene]
    ) -> UIWindowScene? {
        guard let candidate else { return nil }
        return scenes.first(where: { scenesMatch($0, candidate) })
    }

    static func scenePersistentIdentifier(_ scene: UIWindowScene?) -> String? {
        scene?.session.persistentIdentifier
    }

    static func scenePersistentIdentifier(from object: Any?) -> String? {
        if let scene = object as? UIWindowScene {
            return scenePersistentIdentifier(scene)
        }
        if let identifier = object as? String {
            return identifier
        }
        return nil
    }

    static func connectedScene(matchingPersistentIdentifier persistentIdentifier: String?) -> UIWindowScene? {
        guard let persistentIdentifier else { return nil }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.persistentIdentifier == persistentIdentifier }
    }

    static func currentScenePersistentIdentifier(
        windowScene: UIWindowScene?,
        windowScenePersistentIdentifier: String?
    ) -> String? {
        scenePersistentIdentifier(windowScene) ?? windowScenePersistentIdentifier
    }

    private static func sceneIsForegroundCandidate(_ scene: UIWindowScene) -> Bool {
        scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
    }

    static func focusDebugDescription(for scene: UIWindowScene?) -> String {
        guard let scene else { return "scene=nil" }
        let windows = scene.windows.enumerated().map { index, window in
            "#\(index){key=\(window.isKeyWindow),hidden=\(window.isHidden),alpha=\(String(format: "%.2f", window.alpha)),root=\(window.rootViewController != nil)}"
        }.joined(separator: ", ")
        return "scene[id=\(scene.session.persistentIdentifier),object=\(ObjectIdentifier(scene)),state=\(scene.activationState),appKey=\(sceneHasAppKeyWindow(scene)),windows=[\(windows)]]"
    }

    static func focusDebugDescription(for window: UIWindow?) -> String {
        guard let window else { return "window=nil" }
        return "window[key=\(window.isKeyWindow),hidden=\(window.isHidden),alpha=\(String(format: "%.2f", window.alpha)),root=\(window.rootViewController != nil),scene=\(focusDebugDescription(for: window.windowScene))]"
    }

    private static func allScenesDebugDescription(_ scenes: [UIWindowScene]) -> String {
        scenes.map(focusDebugDescription(for:)).joined(separator: " | ")
    }

    private enum SceneFocusDebugLogger {
        static let logFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NutrivanceSceneFocusDebug.log")
        static let queue = DispatchQueue(label: "com.nutrivance.scene-focus-debug")
        static var hasResetLogFile = false

        static func log(_ message: String) {
            #if DEBUG
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)"
            print(line)

            queue.async {
                if !hasResetLogFile {
                    try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
                    hasResetLogFile = true
                }

                guard let data = (line + "\n").data(using: .utf8) else { return }
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: logFileURL)
                }
            }
            #endif
        }
    }

    static func emitFocusDebug(_ message: String) {
        #if DEBUG
        SceneFocusDebugLogger.log("[SceneFocusDebug] \(message)")
        #endif
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        emitFocusDebug(message)
        #endif
    }

    private static func debugLogTargetDecision(
        reason: String,
        selectedScene: UIWindowScene?,
        scenes: [UIWindowScene]
    ) {
        #if DEBUG
        let snapshot = "reason=\(reason) selected=\(focusDebugDescription(for: selectedScene)) scenes=[\(allScenesDebugDescription(scenes))]"
        guard lastLoggedTargetSnapshot != snapshot else { return }
        lastLoggedTargetSnapshot = snapshot
        debugLog("targetSceneForMenuCommand -> \(snapshot)")
        #endif
    }

    /// Call early (e.g. `NutrivanceApp.init`) so menus can rebuild when the key window changes.
    static func installKeyWindowSceneTrackingIfNeeded() {
        guard !didInstallKeyWindowObserver else { return }
        didInstallKeyWindowObserver = true
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow,
                  window.rootViewController != nil,
                  let scene = window.windowScene else { return }
            debugLog("UIWindow.didBecomeKeyNotification -> \(focusDebugDescription(for: window))")
            registerFocusedScene(scene, reason: "didBecomeKeyNotification")
            NutrivanceMenuStateBinder.shared.noteKeyWindowLikelyChanged(scene: scene)
            DispatchQueue.main.async {
                UIMenuSystem.main.setNeedsRebuild()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            debugLog("UIScene.didActivateNotification -> \(focusDebugDescription(for: scene))")
            noteSceneDidActivate(scene)
        }
    }

    static func registerFocusedScene(_ scene: UIWindowScene?, reason: String = "unspecified") {
        guard let scene else {
            debugLog("registerFocusedScene ignored nil reason=\(reason)")
            return
        }
        let persistentIdentifier = scene.session.persistentIdentifier
        lastRegisteredScene = scene
        lastRegisteredScenePersistentIdentifier = persistentIdentifier
        cachedKeyWindowScene = scene
        cachedKeyWindowScenePersistentIdentifier = persistentIdentifier
        BrowserFocusedSceneTracker.shared.adoptKeyScenePersistentIdentifier(persistentIdentifier)
        debugLog("registerFocusedScene reason=\(reason) -> \(focusDebugDescription(for: scene))")
    }

    static func registerFocusedScenePersistentIdentifier(_ persistentIdentifier: String?, reason: String = "unspecified") {
        guard let persistentIdentifier else {
            debugLog("registerFocusedScenePersistentIdentifier ignored nil reason=\(reason)")
            return
        }
        let scene = connectedScene(matchingPersistentIdentifier: persistentIdentifier)
        lastRegisteredScene = scene
        lastRegisteredScenePersistentIdentifier = persistentIdentifier
        cachedKeyWindowScene = scene
        cachedKeyWindowScenePersistentIdentifier = persistentIdentifier
        BrowserFocusedSceneTracker.shared.adoptKeyScenePersistentIdentifier(persistentIdentifier)
        debugLog("registerFocusedScenePersistentIdentifier reason=\(reason) sceneID=\(persistentIdentifier) scene=\(focusDebugDescription(for: scene))")
    }

    static func noteSceneDidActivate(_ scene: UIWindowScene) {
        registerFocusedScene(scene, reason: "sceneDidActivate")
    }

    static func noteSceneDidDisconnect(_ scene: UIWindowScene) {
        let persistentIdentifier = scene.session.persistentIdentifier
        if lastRegisteredScenePersistentIdentifier == persistentIdentifier {
            lastRegisteredScene = nil
            lastRegisteredScenePersistentIdentifier = nil
        }
        if cachedKeyWindowScenePersistentIdentifier == persistentIdentifier {
            cachedKeyWindowScene = nil
            cachedKeyWindowScenePersistentIdentifier = nil
        }
        BrowserFocusedSceneTracker.shared.clearScenePersistentIdentifier(persistentIdentifier)
        debugLog("noteSceneDidDisconnect -> \(focusDebugDescription(for: scene))")
    }

    /// Returns the identifier of the registered scene (for comparison)
    static func registeredScenePersistentIdentifier() -> String? {
        return lastRegisteredScenePersistentIdentifier
    }

    static func targetScenePersistentIdentifierForMenuCommand() -> String? {
        installKeyWindowSceneTrackingIfNeeded()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let registeredScene = connectedScene(matchingPersistentIdentifier: lastRegisteredScenePersistentIdentifier) {
            debugLogTargetDecision(reason: "persistedFocusedScene", selectedScene: registeredScene, scenes: scenes)
            return registeredScene.session.persistentIdentifier
        }

        if let cachedScene = connectedScene(matchingPersistentIdentifier: cachedKeyWindowScenePersistentIdentifier) {
            debugLogTargetDecision(reason: "persistedKeyWindowScene", selectedScene: cachedScene, scenes: scenes)
            return cachedScene.session.persistentIdentifier
        }

        if scenes.count == 1, let onlyScene = scenes.first {
            registerFocusedScene(onlyScene, reason: "singleConnectedScene")
            debugLogTargetDecision(reason: "singleConnectedScene", selectedScene: onlyScene, scenes: scenes)
            return onlyScene.session.persistentIdentifier
        }

        let activeScenes = scenes.filter { $0.activationState == .foregroundActive }
        if activeScenes.count == 1, let onlyActiveScene = activeScenes.first {
            registerFocusedScene(onlyActiveScene, reason: "singleForegroundActiveScene")
            debugLogTargetDecision(reason: "singleForegroundActiveScene", selectedScene: onlyActiveScene, scenes: scenes)
            return onlyActiveScene.session.persistentIdentifier
        }

        let foregroundScenes = scenes.filter(sceneIsForegroundCandidate)
        if foregroundScenes.count == 1, let onlyForegroundScene = foregroundScenes.first {
            registerFocusedScene(onlyForegroundScene, reason: "singleForegroundCandidateScene")
            debugLogTargetDecision(reason: "singleForegroundCandidateScene", selectedScene: onlyForegroundScene, scenes: scenes)
            return onlyForegroundScene.session.persistentIdentifier
        }

        let fallbackScene = activeScenes.first
            ?? foregroundScenes.first
            ?? scenes.first
        debugLogTargetDecision(reason: "connectedScenesFallback", selectedScene: fallbackScene, scenes: scenes)
        return fallbackScene?.session.persistentIdentifier
    }

    /// Scene that should receive keyboard / menu-bar routed notifications.
    static func targetSceneForMenuCommand() -> UIWindowScene? {
        let targetScene = connectedScene(matchingPersistentIdentifier: targetScenePersistentIdentifierForMenuCommand())
            ?? matchingScene(for: lastRegisteredScene, in: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene })
            ?? matchingScene(for: cachedKeyWindowScene, in: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene })
        return targetScene
    }

    static func postMainMenuCommand(_ command: String) {
        let targetScenePersistentIdentifier = targetScenePersistentIdentifierForMenuCommand()
        debugLog("postMainMenuCommand(\(command)) -> sceneID=\(targetScenePersistentIdentifier ?? "nil") scene=\(focusDebugDescription(for: connectedScene(matchingPersistentIdentifier: targetScenePersistentIdentifier)))")
        NotificationCenter.default.post(
            name: .nutrivanceCatalystMainMenuCommand,
            object: targetScenePersistentIdentifier,
            userInfo: ["command": command]
        )
    }

    static func scenesMatch(_ a: UIWindowScene, _ b: UIWindowScene) -> Bool {
        a === b || a.session.persistentIdentifier == b.session.persistentIdentifier
    }

    /// Browser shell and per-view ⌘ shortcuts: only the hierarchy in `windowScene` should run (multi-window / multi-scene).
    static func shouldHandleSceneTargetedNotification(
        object: Any?,
        windowScene: UIWindowScene?,
        windowScenePersistentIdentifier: String? = nil
    ) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let multiWindow = scenes.count > 1
        let myScenePersistentIdentifier = currentScenePersistentIdentifier(
            windowScene: windowScene,
            windowScenePersistentIdentifier: windowScenePersistentIdentifier
        )

        if let postedScenePersistentIdentifier = scenePersistentIdentifier(from: object) {
            if let myScenePersistentIdentifier {
                let result = myScenePersistentIdentifier == postedScenePersistentIdentifier
                debugLog("shouldHandleSceneTargetedNotification postedSceneID=\(postedScenePersistentIdentifier) mySceneID=\(myScenePersistentIdentifier) myScene=\(focusDebugDescription(for: windowScene)) result=\(result)")
                return result
            }
            if !multiWindow, let only = scenes.first {
                let result = only.session.persistentIdentifier == postedScenePersistentIdentifier
                debugLog("shouldHandleSceneTargetedNotification postedSceneID=\(postedScenePersistentIdentifier) singleScene=\(focusDebugDescription(for: only)) result=\(result)")
                return result
            }
            debugLog("shouldHandleSceneTargetedNotification postedSceneID=\(postedScenePersistentIdentifier) mySceneID=nil result=false")
            return false
        }

        if !multiWindow {
            debugLog("shouldHandleSceneTargetedNotification multiWindow=false result=true")
            return true
        }

        guard let myScenePersistentIdentifier else {
            debugLog("shouldHandleSceneTargetedNotification noPostedScene mySceneID=nil result=false")
            return false
        }
        guard let targetScenePersistentIdentifier = targetScenePersistentIdentifierForMenuCommand() else {
            debugLog("shouldHandleSceneTargetedNotification targetSceneID=nil mySceneID=\(myScenePersistentIdentifier) myScene=\(focusDebugDescription(for: windowScene)) result=false")
            return false
        }
        let result = targetScenePersistentIdentifier == myScenePersistentIdentifier
        debugLog("shouldHandleSceneTargetedNotification targetSceneID=\(targetScenePersistentIdentifier) mySceneID=\(myScenePersistentIdentifier) myScene=\(focusDebugDescription(for: windowScene)) result=\(result)")
        return result
    }
}
#endif

/// Tracks the last foreground scene’s navigation/search state so the menu bar `CommandMenu("View Controls")` reflects the active window.
@MainActor
final class NutrivanceMenuStateBinder: ObservableObject {
    static let shared = NutrivanceMenuStateBinder()

    private(set) weak var activeNavigationState: NavigationState?
    private(set) weak var activeSearchState: SearchState?
    private var subscription: AnyCancellable?
    #if canImport(UIKit)
    private final class SceneBinding {
        let persistentIdentifier: String
        weak var scene: UIWindowScene?
        weak var navigationState: NavigationState?
        weak var searchState: SearchState?

        init(
            persistentIdentifier: String,
            scene: UIWindowScene,
            navigationState: NavigationState,
            searchState: SearchState
        ) {
            self.persistentIdentifier = persistentIdentifier
            self.scene = scene
            self.navigationState = navigationState
            self.searchState = searchState
        }
    }

    private var sceneBindings: [String: SceneBinding] = [:]
    #endif
    #if canImport(UIKit)
    private var menuRebuildWorkItem: DispatchWorkItem?
    #endif

    #if canImport(UIKit)
    private func debugLog(_ message: String) {
        #if DEBUG
        NutrivanceSceneMenuRouter.emitFocusDebug("[Binder] \(message)")
        #endif
    }

    private func stateDebugDescription(
        persistentIdentifier: String?,
        scene: UIWindowScene?,
        navigationState: NavigationState?,
        searchState: SearchState?
    ) -> String {
        let navigationPart = navigationState.map {
            "nav=\(ObjectIdentifier($0)) tab=\($0.selectedRootTab)"
        } ?? "nav=nil"
        let searchPart = searchState.map { "search=\(ObjectIdentifier($0))" } ?? "search=nil"
        return "sceneID=\(persistentIdentifier ?? "nil") \(NutrivanceSceneMenuRouter.focusDebugDescription(for: scene)) \(navigationPart) \(searchPart)"
    }
    #endif

    func bindActiveScene(navigationState: NavigationState, searchState: SearchState) {
        updateActiveScene(navigationState: navigationState, searchState: searchState)
    }

    #if canImport(UIKit)
    func registerScene(
        persistentIdentifier: String?,
        scene: UIWindowScene?,
        navigationState: NavigationState,
        searchState: SearchState
    ) {
        guard let persistentIdentifier else { return }
        pruneSceneBindings()
        if let binding = sceneBindings[persistentIdentifier] {
            binding.scene = scene ?? binding.scene
            binding.navigationState = navigationState
            binding.searchState = searchState
        } else if let scene {
            sceneBindings[persistentIdentifier] = SceneBinding(
                persistentIdentifier: persistentIdentifier,
                scene: scene,
                navigationState: navigationState,
                searchState: searchState
            )
        } else {
            return
        }
        debugLog("registerScene -> \(stateDebugDescription(persistentIdentifier: persistentIdentifier, scene: scene, navigationState: navigationState, searchState: searchState))")
    }

    func registerScene(_ scene: UIWindowScene?, navigationState: NavigationState, searchState: SearchState) {
        registerScene(
            persistentIdentifier: NutrivanceSceneMenuRouter.scenePersistentIdentifier(scene),
            scene: scene,
            navigationState: navigationState,
            searchState: searchState
        )
    }

    func activateScene(_ scene: UIWindowScene?) {
        activateScene(persistentIdentifier: NutrivanceSceneMenuRouter.scenePersistentIdentifier(scene))
    }

    func activateScene(persistentIdentifier: String?) {
        pruneSceneBindings()
        guard let persistentIdentifier else {
            debugLog("activateScene -> sceneID=nil")
            return
        }

        if let binding = sceneBindings[persistentIdentifier],
           let navigationState = binding.navigationState,
           let searchState = binding.searchState {
            debugLog("activateScene directMatch -> \(stateDebugDescription(persistentIdentifier: persistentIdentifier, scene: binding.scene, navigationState: navigationState, searchState: searchState))")
            updateActiveScene(navigationState: navigationState, searchState: searchState)
            return
        }

        for binding in sceneBindings.values {
            guard binding.persistentIdentifier == persistentIdentifier,
                  let navigationState = binding.navigationState,
                  let searchState = binding.searchState else { continue }
            debugLog("activateScene fuzzyMatch requestedSceneID=\(persistentIdentifier) bound=\(stateDebugDescription(persistentIdentifier: binding.persistentIdentifier, scene: binding.scene, navigationState: navigationState, searchState: searchState))")
            updateActiveScene(navigationState: navigationState, searchState: searchState)
            return
        }

        debugLog("activateScene noMatch -> requestedSceneID=\(persistentIdentifier) bindingCount=\(sceneBindings.count)")
    }

    private func pruneSceneBindings() {
        sceneBindings = sceneBindings.filter { _, binding in
            binding.navigationState != nil && binding.searchState != nil
        }
    }
    #endif

    private func updateActiveScene(navigationState: NavigationState, searchState: SearchState) {
        guard activeNavigationState !== navigationState ||
              activeSearchState !== searchState else { return }
        activeNavigationState = navigationState
        activeSearchState = searchState
        #if canImport(UIKit)
        debugLog("updateActiveScene -> \(stateDebugDescription(persistentIdentifier: nil, scene: nil, navigationState: navigationState, searchState: searchState))")
        #endif
        subscription?.cancel()
        subscription = navigationState.objectWillChange
            .debounce(for: .milliseconds(140), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                #if canImport(UIKit)
                self?.scheduleMenuRebuildCoalesced()
                #endif
            }
        objectWillChange.send()
    }

    #if canImport(UIKit)
    private func scheduleMenuRebuildCoalesced() {
        menuRebuildWorkItem?.cancel()
        let item = DispatchWorkItem {
            UIMenuSystem.main.setNeedsRebuild()
        }
        menuRebuildWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: item)
    }

    /// Posted when `UIWindow.didBecomeKeyNotification` fires so SwiftUI `CommandMenu` / deferred UIKit menus pick up the key window’s `NavigationState`.
    func noteKeyWindowLikelyChanged(scene: UIWindowScene? = nil) {
        let persistentIdentifier = NutrivanceSceneMenuRouter.scenePersistentIdentifier(scene)
            ?? NutrivanceSceneMenuRouter.targetScenePersistentIdentifierForMenuCommand()
        debugLog("noteKeyWindowLikelyChanged -> sceneID=\(persistentIdentifier ?? "nil") scene=\(NutrivanceSceneMenuRouter.focusDebugDescription(for: scene))")
        activateScene(persistentIdentifier: persistentIdentifier)
        objectWillChange.send()
        scheduleMenuRebuildCoalesced()
    }
    #endif

    /// Drives SwiftUI `CommandMenu("View Controls")` `.id` so iPad menu bar / ⌘-HUD rebuilds when the key window’s tab changes.
    var viewControlsCommandsIdentity: String {
        guard let nav = activeNavigationState else { return "unbound" }
        return "\(ObjectIdentifier(nav))-\(nav.selectedRootTab)"
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI

private extension UIWindow {
    /// Whether this window’s view hierarchy contains `view` (walks superviews up to the window).
    func containsView(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v === self { return true }
            current = v.superview
        }
        return false
    }
}

private struct ViewControlWindowSceneResolver: UIViewControllerRepresentable {
    var onResolve: (UIWindowScene?) -> Void

    final class Coordinator: NSObject {
        weak var lastNotifiedScene: UIWindowScene?
        var didScheduleNilWindowRetry = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        resolve(from: uiViewController, coordinator: context.coordinator)
    }

    private func resolve(from vc: UIViewController, coordinator: Coordinator) {
        // Primary: direct window → scene (fast path when fully attached).
        if let scene = vc.view.window?.windowScene {
            if coordinator.lastNotifiedScene !== scene {
                coordinator.lastNotifiedScene = scene
                onResolve(scene)
            }
            coordinator.didScheduleNilWindowRetry = false
            return
        }

        // Secondary: Catalyst / multi-window can leave `view.window` nil briefly while the view is still
        // under a `UIWindow` in `connectedScenes` — find the owning scene by hierarchy.
        if let view = vc.view {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let owningScene = scenes.first(where: { scene in
                scene.windows.contains(where: { $0.containsView(view) })
            }) {
                if coordinator.lastNotifiedScene !== owningScene {
                    coordinator.lastNotifiedScene = owningScene
                    onResolve(owningScene)
                }
                coordinator.didScheduleNilWindowRetry = false
                return
            }
        }

        // Tertiary: view not in hierarchy yet — retry next run loop (matches previous nil-window behavior).
        if !coordinator.didScheduleNilWindowRetry {
            coordinator.didScheduleNilWindowRetry = true
            DispatchQueue.main.async { [weak vc] in
                coordinator.didScheduleNilWindowRetry = false
                guard let vc else { return }
                resolve(from: vc, coordinator: coordinator)
            }
        }
    }
}

private struct ViewControlNotificationModifier: ViewModifier {
    let name: Notification.Name
    let voidAction: (() -> Void)?
    let notificationAction: ((Notification) -> Void)?

    @State private var windowScene: UIWindowScene?
    @State private var windowScenePersistentIdentifier: String?

    init(name: Notification.Name, voidAction: @escaping () -> Void) {
        self.name = name
        self.voidAction = voidAction
        self.notificationAction = nil
    }

    init(name: Notification.Name, notificationAction: @escaping (Notification) -> Void) {
        self.name = name
        self.voidAction = nil
        self.notificationAction = notificationAction
    }

    func body(content: Content) -> some View {
        content
            .background(ViewControlWindowSceneResolver { resolvedScene in
                guard let resolvedScene else { return }
                windowScene = resolvedScene
                windowScenePersistentIdentifier = NutrivanceSceneMenuRouter.scenePersistentIdentifier(resolvedScene)
            })
            .onReceive(NotificationCenter.default.publisher(for: name)) { note in
                guard NutrivanceSceneMenuRouter.shouldHandleSceneTargetedNotification(
                    object: note.object,
                    windowScene: windowScene,
                    windowScenePersistentIdentifier: windowScenePersistentIdentifier
                ) else { return }
                voidAction?()
                notificationAction?(note)
            }
    }
}

extension View {
    /// View Control / Catalyst menu shortcuts: handles only when the notification targets this window’s `UIWindowScene`.
    func onReceiveViewControl(_ name: Notification.Name, perform action: @escaping () -> Void) -> some View {
        modifier(ViewControlNotificationModifier(name: name, voidAction: action))
    }

    /// Same as `onReceiveViewControl` but passes the `Notification` (e.g. `userInfo`).
    func onReceiveViewControl(_ name: Notification.Name, performWithNotification action: @escaping (Notification) -> Void) -> some View {
        modifier(ViewControlNotificationModifier(name: name, notificationAction: action))
    }
}
#endif
