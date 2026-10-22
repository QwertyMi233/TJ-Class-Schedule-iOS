import Flutter
import UIKit
import tj_ios_bridge

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    for context in connectionOptions.urlContexts {
      TJIosBridgePlugin.openWidgetURL(context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts { TJIosBridgePlugin.openWidgetURL(context.url) }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
