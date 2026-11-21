import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var storageBridge: StorageBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    storageBridge = StorageBridge(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Export uses the document provider's copy facility. The original committed
/// file remains in Application Support even if export fails or the app exits.
private final class StorageBridge: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate {
  private let channel: FlutterMethodChannel
  private var pendingExport: FlutterResult?
  private weak var exportPicker: UIDocumentPickerViewController?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "file_transfer/storage", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "EXPORT_INTERRUPTED", message: "Storage adapter closed.", details: nil))
        return
      }
      switch call.method {
      case "freeBytes": self.freeBytes(call, result: result)
      case "exportFile": self.exportFile(call, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func appSupport() throws -> URL {
    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
  }

  private func contained(_ candidate: URL, in root: URL) -> Bool {
    candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
  }

  private func freeBytes(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "A directory is required.", details: nil))
      return
    }
    do {
      let directory = URL(fileURLWithPath: path, isDirectory: true)
        .resolvingSymlinksInPath().standardizedFileURL
      guard contained(directory, in: try appSupport()) else {
        result(nil)
        return
      }
      // User-requested file storage; the value stays local. The corresponding
      // required reason is declared in PrivacyInfo.xcprivacy.
      let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      if let available = values.volumeAvailableCapacityForImportantUsage, available >= 0 {
        result(available)
      } else {
        result(nil)
      }
    } catch {
      result(nil)
    }
  }

  private func sourceURL(_ path: String) throws -> URL {
    let original = URL(fileURLWithPath: path).standardizedFileURL
    let resolved = original.resolvingSymlinksInPath().standardizedFileURL
    let root = try appSupport().appendingPathComponent("file-transfer-v1/inbox/received", isDirectory: true)
    let values = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard contained(resolved, in: root), resolved.path != root.path,
      values.isRegularFile == true, values.isSymbolicLink != true,
      FileManager.default.isReadableFile(atPath: resolved.path) else {
      throw NSError(domain: "FileTransferExport", code: 1)
    }
    // UIKit owns the copy and does not receive a mutable provider source. Any
    // symlink in the managed subtree is rejected before presenting the picker.
    var current = original
    while contained(current, in: root) {
      if try current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
        throw NSError(domain: "FileTransferExport", code: 2)
      }
      if current.path == root.path { break }
      current.deleteLastPathComponent()
    }
    return resolved
  }

  private func activePresenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
      let window = scene.windows.first(where: { $0.isKeyWindow }),
      var current = window.rootViewController else { return nil }
    while let next = current.presentedViewController { current = next }
    return current
  }

  private func exportFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingExport == nil else {
      result(FlutterError(code: "EXPORT_BUSY", message: "Another export is active.", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["sourcePath"] as? String, !path.isEmpty,
      let displayName = arguments["displayName"] as? String, !displayName.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "A received file is required.", details: nil))
      return
    }
    let source: URL
    do { source = try sourceURL(path) }
    catch {
      result(FlutterError(code: "EXPORT_SOURCE_UNAVAILABLE",
        message: "The received file is unavailable.", details: nil))
      return
    }
    guard let presenter = activePresenter(), presenter.viewIfLoaded?.window != nil else {
      result(FlutterError(code: "EXPORT_UNSUPPORTED",
        message: "Open the app to save a copy.", details: nil))
      return
    }
    pendingExport = result
    // asCopy=true is essential: the app keeps the original committed result.
    let picker = UIDocumentPickerViewController(forExporting: [source], asCopy: true)
    picker.delegate = self
    picker.presentationController?.delegate = self
    exportPicker = picker
    presenter.present(picker, animated: true) { [weak self, weak picker] in
      picker?.presentationController?.delegate = self
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]) {
    guard controller === exportPicker, let result = pendingExport else { return }
    pendingExport = nil
    exportPicker = nil
    guard urls.count == 1, let destination = urls.first, destination.isFileURL,
      !destination.lastPathComponent.isEmpty else {
      result(FlutterError(code: "EXPORT_FAILED",
        message: "The document provider did not confirm a saved copy.", details: nil))
      return
    }
    // This is a provider completion receipt, not a promise that iCloud or a
    // third-party remote service has finished synchronizing the document.
    result([
      "status": "exported",
      "destinationLabel": destination.lastPathComponent,
      "platformReference": destination.absoluteString,
    ])
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === exportPicker else { return }
    finishCancelled()
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === exportPicker else { return }
    finishCancelled()
  }

  private func finishCancelled() {
    let result = pendingExport
    pendingExport = nil
    exportPicker = nil
    result?(nil)
  }
}
