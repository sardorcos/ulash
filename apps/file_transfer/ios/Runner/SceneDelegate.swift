import Flutter
import UIKit

/// Files opened with "Open in Ulash" / "Copy to Ulash" arrive here, both on a
/// cold start (connection options) and while the app is running. They are
/// copied into the app's intake folder and offered to Dart; Flutter's own
/// handling still runs first.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    let urls = connectionOptions.urlContexts.map { $0.url }.filter { $0.isFileURL }
    if !urls.isEmpty { IntakeStore.shared.accept(urls) }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    let urls = URLContexts.map { $0.url }.filter { $0.isFileURL }
    if !urls.isEmpty { IntakeStore.shared.accept(urls) }
  }
}
