import UIKit

/// Scene delegate referenced by `Info.plist` (`UISceneDelegateClassName`).
/// SwiftUI’s `WindowGroup` still owns the window; this object receives scene callbacks and (on Catalyst) augments `UIMenuBuilder`.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    #if targetEnvironment(macCatalyst)
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        NutrivanceCatalystMenuBuilder.augmentMainMenu(with: builder)
    }
    #endif

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        NutrivanceSceneMenuRouter.installKeyWindowSceneTrackingIfNeeded()
        if let windowScene = scene as? UIWindowScene {
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 500, height: 380)
        }
        // SwiftUI owns the window, but Catalyst benefits from rebuilding the main menu after the first scene connects.
        #if targetEnvironment(macCatalyst)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }

    func sceneDidActivate(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene {
            NutrivanceSceneMenuRouter.noteSceneDidActivate(windowScene)
            NutrivanceMenuStateBinder.shared.activateScene(
                persistentIdentifier: NutrivanceSceneMenuRouter.scenePersistentIdentifier(windowScene)
            )
        }
        #if targetEnvironment(macCatalyst)
        // Focus + menu routing are still refined by key-window notifications, but scene activation is the best
        // scene-level signal we get from UIKit when the user switches windows.
        UIMenuSystem.main.setNeedsRevalidate()
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NutrivanceSceneMenuRouter.noteSceneDidDisconnect(windowScene)
    }
}
