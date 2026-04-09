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
    private static var lastRegisteredSceneID: ObjectIdentifier?
    private static var lastUpdateTime: Date = Date()

    /// Authoritative on Mac Catalyst: `UIWindowScene` for the window that actually became key (scanning `isKeyWindow` is flaky with multiple scenes).
    private static weak var cachedKeyWindowScene: UIWindowScene?
    private static var didInstallKeyWindowObserver = false

    /// Call early (e.g. `NutrivanceApp.init`) so the first menu shortcut has a correct target.
    static func installKeyWindowSceneTrackingIfNeeded() {
        guard !didInstallKeyWindowObserver else { return }
        didInstallKeyWindowObserver = true
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow,
                  let scene = window.windowScene else { return }
            // Force refresh to clear stale cache when key window changes
            cachedKeyWindowScene = nil
            cachedKeyWindowScene = scene
            registerFocusedScene(scene)
            BrowserFocusedSceneTracker.shared.adoptKeyScene(scene)
            NutrivanceMenuStateBinder.shared.noteKeyWindowLikelyChanged()
            DispatchQueue.main.async {
                UIMenuSystem.main.setNeedsRebuild()
            }
        }
    }

    static func registerFocusedScene(_ scene: UIWindowScene?) {
        guard let scene else {
            lastRegisteredScene = nil
            lastRegisteredSceneID = nil
            return
        }
        lastRegisteredScene = scene
        lastRegisteredSceneID = ObjectIdentifier(scene)
        lastUpdateTime = Date()
    }

    /// Returns the identifier of the registered scene (for comparison)
    static func registeredSceneID() -> ObjectIdentifier? {
        return lastRegisteredSceneID
    }

    /// Scene that should receive keyboard / menu-bar routed notifications.
    /// Returns the scene that currently has the key window, with fallback logic for edge cases.
    static func targetSceneForMenuCommand() -> UIWindowScene? {
        installKeyWindowSceneTrackingIfNeeded()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        // First priority: find the scene that currently has the key window
        for scene in scenes {
            let hasKeyWindow = scene.windows.contains(where: { window in
                window.isKeyWindow && !window.isHidden && window.alpha > 0 && window.windowScene != nil
            })
            if hasKeyWindow {
                cachedKeyWindowScene = scene
                registerFocusedScene(scene)
                return scene
            }
        }

        // Second priority: validate cached scene still exists
        if let cached = cachedKeyWindowScene, scenes.contains(where: { $0 === cached }) {
            // Check if cached scene has any visible window (not necessarily key)
            let hasVisibleWindow = cached.windows.contains(where: { !$0.isHidden && $0.alpha > 0 })
            if hasVisibleWindow {
                return cached
            }
        }

        // Third priority: registered scene (from didBecomeKeyNotification)
        if let registered = lastRegisteredScene,
           scenes.contains(where: { $0 === registered }),
           registered.activationState == .foregroundActive || registered.activationState == .foregroundInactive {
            return registered
        }

        // Fourth priority: any foregroundActive scene
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
    }

    /// Forces a fresh lookup of the key window scene, bypassing any stale cache.
    /// Use this when you need to ensure you're targeting the truly active window.
    static func forceRefreshKeyScene() {
        cachedKeyWindowScene = nil
    }

    static func postMainMenuCommand(_ command: String) {
        let targetScene = targetSceneForMenuCommand()
        NotificationCenter.default.post(
            name: .nutrivanceCatalystMainMenuCommand,
            object: targetScene,
            userInfo: ["command": command]
        )
    }

    static func scenesMatch(_ a: UIWindowScene, _ b: UIWindowScene) -> Bool {
        a === b || a.session.persistentIdentifier == b.session.persistentIdentifier
    }

    /// Browser shell and per-view ⌘ shortcuts: only the hierarchy in `windowScene` should run (multi-window / multi-scene).
    static func shouldHandleSceneTargetedNotification(object: Any?, windowScene: UIWindowScene?) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let multiWindow = scenes.count > 1

        if let posted = object as? UIWindowScene {
            if let my = windowScene {
                return scenesMatch(posted, my)
            }
            if !multiWindow, let only = scenes.first {
                return scenesMatch(posted, only)
            }
            return false
        }

        if !multiWindow {
            return true
        }

        guard let my = windowScene else { return false }
        return my.windows.contains(where: \.isKeyWindow)
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
    private var menuRebuildWorkItem: DispatchWorkItem?
    #endif

    func bindActiveScene(navigationState: NavigationState, searchState: SearchState) {
        guard activeNavigationState !== navigationState ||
              activeSearchState !== searchState else { return }
        activeNavigationState = navigationState
        activeSearchState = searchState
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
    func noteKeyWindowLikelyChanged() {
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
        let scene = vc.view.window?.windowScene
        if coordinator.lastNotifiedScene === scene {
            return
        }
        coordinator.lastNotifiedScene = scene
        onResolve(scene)

        if scene == nil, !coordinator.didScheduleNilWindowRetry {
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
            .background(ViewControlWindowSceneResolver { windowScene = $0 })
            .onReceive(NotificationCenter.default.publisher(for: name)) { note in
                guard NutrivanceSceneMenuRouter.shouldHandleSceneTargetedNotification(
                    object: note.object,
                    windowScene: windowScene
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
