import UIKit

/// Scene delegate referenced by `Info.plist` (`UISceneDelegateClassName`).
/// SwiftUI still owns the window; Catalyst main-menu registration lives in `NutrivanceAppDelegate`.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // SwiftUI owns the window, but Catalyst benefits from rebuilding the main menu after the first scene connects.
        #if targetEnvironment(macCatalyst)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }

    func sceneDidActivate(_ scene: UIScene) {
        #if targetEnvironment(macCatalyst)
        UIMenuSystem.main.setNeedsRevalidate()
        #endif
    }
}
