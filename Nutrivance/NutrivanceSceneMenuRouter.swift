import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
enum NutrivanceSceneMenuRouter {
    /// Scene that should receive Navigation / Search menu actions (key window, else any foreground scene).
    static func targetSceneForMenuCommand() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.first(where: { $0.keyWindow?.isKeyWindow == true }) {
            return key
        }
        return scenes.first { $0.activationState == .foregroundActive }
    }

    static func postMainMenuCommand(_ command: String) {
        NotificationCenter.default.post(
            name: .nutrivanceCatalystMainMenuCommand,
            object: targetSceneForMenuCommand(),
            userInfo: ["command": command]
        )
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

    func bindActiveScene(navigationState: NavigationState, searchState: SearchState) {
        activeNavigationState = navigationState
        activeSearchState = searchState
        subscription?.cancel()
        subscription = navigationState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            #if canImport(UIKit)
            DispatchQueue.main.async {
                UIMenuSystem.main.setNeedsRebuild()
            }
            #endif
        }
        objectWillChange.send()
    }

    /// Drives SwiftUI `CommandMenu("View Controls")` `.id` so iPad menu bar / ⌘-HUD rebuilds when the key window’s tab changes.
    var viewControlsCommandsIdentity: String {
        guard let nav = activeNavigationState else { return "unbound" }
        return "\(ObjectIdentifier(nav))-\(nav.selectedRootTab)"
    }
}
