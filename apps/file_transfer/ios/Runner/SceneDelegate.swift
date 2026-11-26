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
    accept(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    accept(URLContexts)
  }

  /// `openInPlace` tells the intake whether the URL is the user's original
  /// (never deleted) or a copy iOS placed in Ulash's Documents/Inbox.
  private func accept(_ contexts: Set<UIOpenURLContext>) {
    let sources = contexts.filter { $0.url.isFileURL }
      .map { IntakeSource(url: $0.url, openInPlace: $0.options.openInPlace) }
    if !sources.isEmpty { IntakeStore.shared.accept(sources) }
  }
}
